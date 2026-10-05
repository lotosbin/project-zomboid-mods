# bin2_npc_extension 设计文档

> 目标模组：`Bin2NPCExtension`（物品目录 `bin2_npc_extension`）
> 依赖：`OrangeCommunityEconomy`（必需）、`ProjectALifeNPCs`（需要）、`ProjectALifeJimmy`（可选）
> 版本：0.2.2（2026-10-05）｜ 工坊 id：3813914438（已发布，物品内含两个模组）
> 状态：**已进游戏跑通基础流程，完整清单（T1~T18）未跑完**

---

## 1. 目标与不做什么

**要做**：把「招募 NPC」做成橙子社区经济里的一门生意 —— 玩家花社区货币雇 A-Life NPC，
雇员能跟随、站岗、或交给 Jeem 的居民系统守营地；有名册、日薪、名额与解雇。

**不做**（都是有意的）：

| 不做 | 原因 |
| --- | --- |
| 不修改橙子经济 / A-Life / Jeem 的任何文件 | 三个模组都可能随时更新；改文件等于把别人的升级变成我们的 breakage |
| 不带 A-Life / Jeem 的 Lua 副本 | A-Life 的 `Compat.foreignCopies` 会点名这种模组，且旧副本会 shadow 新版本 |
| 不借用 `"ProjectALife"` / `"ProjectALifeJimmy"` 的网络 module | 那是对方的命令通道；第三方复用会撞车（A-Life 官方红线） |
| 不复制 Jeem 的 `jimmy*` memory 私有键 | 它写的是内部 schema，版本一改就静默失效；我们只读 `residentOf()` |
| 不改玩家的战斗/AI 平衡 | 我们只下 A-Life 已有的 `follow` / `hold` 指令，不新增行为模块 |

---

## 2. 架构

```
                     ┌──────────────────────── 客户端 ────────────────────────┐
  玩家操作 ──► Page.lua（招募页，注册进 OrangeTradingMod.UIPageRegistry）
                     │  读 Net.cache（服务端推来的状态快照）
                     │  改状态 → Net.send(cmd, args, mutating=true)
                     └───────────────┬───────────────────────────────────────┘
                                     │ 联机客户端：sendClientCommand(player,"Bin2NPCExtension",…)
                                     │ 单机/主机：直接调用（同一进程）
                     ┌───────────────▼───────────────────────────────────────┐
                     │  Service.dispatch  —— 唯一改状态的地方（限速 + requestId 去重）
                     │   ├─ Economy.pay  → OrangeTradingModServer.Pay（服务端权威扣款）
                     │   ├─ Alife.spawn / orderFollow / orderHold / protect
                     │   └─ Jimmy.recruit / leaveOne（居民岗位）
                     │  Store.data（ModData["Bin2NPCExtension.Contracts.v1"]）+ transmit
                     └───────────────┬───────────────────────────────────────┘
                                     │ sendServerCommand(player,"Bin2NPCExtension","State",payload)
                     ┌───────────────▼───────────────────────────────────────┐
                     │  Maintain.tick（1s 节流）：岗位补派、指令重下、阵亡清理
                     │  Maintain.settleWages（每分钟）：日薪结算
                     └───────────────────────────────────────────────────────┘
```

**四层职责**

| 文件 | 层 | 职责 |
| --- | --- | --- |
| `shared/Bin2NPCExtension/{Config,Contracts,Text}.lua` | shared | 常量/沙盒选项/依赖探测、存档形状与纯逻辑、翻译包装 |
| `server/Bin2NPCExtension/{Store,Alife,Jimmy,Economy}.lua` | server | 三个依赖各一个**适配层**（存在性探测 + pcall + 缺失即降级） |
| `server/Bin2NPCExtension/{Service,Maintain,Bootstrap}.lua` | server | 命令处理、周期维护、事件接线 |
| `client/Bin2NPCExtension/{Net,Bootstrap}.lua` + `ui/{Page,Entry}.lua` | client | 网络分发、页面与入口安装 |

**一个刻意的取舍**：客户端**不读 ModData**，只读服务端推来的快照。
理由：A-Life 的 `Executor.PROTECTED` 白名单不含第三方 memory 键，多人下客户端拿不到可靠状态；
统一走 `sendServerCommand` 就不会出现"主机能看到、别人看不到"。

---

## 3. 数据模型

存档：`ModData["Bin2NPCExtension.Contracts.v1"]`（服务端权威写，`ModData.transmit` 同步）

```lua
{
  schema = 1,
  players = {
    ["Bin2NPCExtensionPlayer_<用户名>"] = {
      seq = 3,
      contracts = {
        ["palife:1730000000:12"] = {          -- 键就是 A-Life actor uid，天然去重
          id = "c:3", uid = "palife:…", name = "John",
          factionId = "…", profileId = "…",
          mode = "follow" | "guard" | "resident",
          source = "hired" | "spawned",
          baseId = "…",                        -- 居民岗位时的 Jeem 基地
          anchor = { x = 0, y = 0, z = 0 },    -- 守卫岗位的锚点
          hiredHours = 12.5, wagePaidHours = 12.5, unpaidSince = nil,
          status = "active" | "dead" | "dismissed",
          deadHours = nil, price = 500,
          note = "resident:no_beds",           -- 最近一次降级/失败原因（面板上显示）
        },
      },
      order = { "palife:…" },                  -- 显示顺序（Kahlua 没有 next()，显式维护）
    },
  },
}
```

**为什么按"账号"而不是"角色"记**：钱在橙子经济里是按用户名记的（`OrangeTradingModPlayer_<name>`），
契约跟钱同粒度才不会出现"角色死了钱还在、雇员没了"的错位。

---

## 4. 关键流程

### 4.1 收编已有 NPC（`HireExisting`）

```
1. 开关 / A-Life / 经济 可用性检查           → disabled / no_alife / no_economy
2. 名额（activeCount < MaxContracts）        → limit_reached
3. 归属检查 Contracts.owner(store, uid)      → taken_by_other / already_hired
4. 记录存在且 lifecycle=="active"            → not_found / not_active
5. 距离（服务端算，Jeem 自己是不校验距离的） → too_far
6. 态度（Relations.baselineStance）          → hostile（沙盒可放行）
7. 扣款 OrangeTradingModServer.Pay           → no_funds
8. 写契约 + Alife.protect（防人口回收）
9. Service.applyMode（岗位指派，失败只降级不退款）
10. Store.transmit + 推送状态
```

### 4.2 中介派遣（`HireSpawned`）

```
1..2 同上 → 3. 从 Catalog 挑一个 friendly/neutral 阵营 + 其下档案（挑不到就保底任意阵营）
4. 找玩家身边一个已加载的空方块
5. 扣款（放在造人之前：Pay 会重新校验余额，失败时我们还什么都没造）
6. Alife.spawn：ActorRegistry.create（operationId 每次唯一，避免幂等命中旧记录）
              → SpawnService.request（同步 createShell + hydrate，异步等 active）
   失败 → Economy.refund 全额退款 → spawn_failed
7. 写契约（note="pending"），此后由 Maintain.tick 在 lifecycle=="active" 时补派岗位
```

### 4.3 岗位指派（`Service.applyMode`）

```
protect(uid) → 防回收标记（memory.persistent + memory.admin.persistent + moduleOverrides.orders）
resident → Jimmy.recruit(player, uid)
             成功：记 baseId；失败：degraded="resident:<why>"，落到 follow
guard    → Alife.orderHold(uid, 玩家当前位置)
             成功：返回；失败：degraded 追加 "guard:<why>"，落到 follow
follow   → Alife.orderFollow(player, uid, quiet)
             成功：note = degraded（有降级就留着，让玩家看到原因）
```

契约**不因为岗位失败而撤销**：钱已经收了、人也造出来了，最差也要给玩家一个跟随的雇员。

### 4.4 可观测性（同域项目的"通用工程约定 §3/§4"落地）

| 机制 | 做什么 | 为什么 |
| --- | --- | --- |
| 启动能力自检 `Bootstrap.capabilities()` | 把 10 个**半公开入口**逐个探一遍，打印 `hooks active=N inactive=M` 并 WARN 列出缺的名字（`alife.orders`、`jeem.standing`…） | A-Life/Jeem 升级把函数改名时，**第一次进游戏就能看到**，而不是等玩家点按钮没反应再翻代码 |
| 兼容自检 `Bootstrap.reportCompat()` | 只读跑 A-Life 自己的 `Compat.foreignCopies(active)`，点名"自带 A-Life Lua 副本"的模组 | 那类模组会让每次 NPC 水合失败，而生成 NPC 正是本模组主路径 |
| 幂等 + 防 Reset Lua 重入 | 三个注册 Events 的文件用 **`Events` 表的身份**做守卫（同一张表 = 同一次会话，跳过；换表 = 引擎重置过 Lua，重新注册） | 布尔守卫在"重置 Lua"后会永久失效；表身份判据两头都对 |

### 4.5 周期维护（`Maintain`）

| 周期 | 做什么 | 为什么 |
| --- | --- | --- |
| 每 ~1 秒 | 岗位补派（note=="pending"）、follow/hold 指令重下（8 秒/人）、阵亡清理 | A-Life 的 `DecisionLoop.orders` 是**内存表**，读档即失效；Jeem 的 `Friendlies.sync` 也是同一套路 |
| 每 1 分钟 | 日薪结算（跨满 24 世界小时才扣）、欠薪超宽限期自动解约 | 钱必须服务端定期收，否则玩家可以"雇了就不管" |
| 进档一次 | `Maintain.restore()` 立刻重下全部指令 | 覆盖单机（OnGameStart）与专用服（OnServerStarted） |

---

## 5. 降级矩阵（每一种都有日志）

| 情形 | 行为 |
| --- | --- |
| 橙子经济缺失 | 页面不注册（客户端重试 60 次后放弃并报日志），服务端命令全部 `no_economy` |
| A-Life 缺失 / 未启动 | 面板可用但招募按钮禁用，面板上写明原因；服务端 `no_alife` |
| Jeem 缺失或 `Residents_Enabled=false` | 隐藏「居民」按钮；请求居民时降级为跟随并记 `no_jeem` |
| Jeem 拒绝收编（床位/声望/权限） | 契约降级为跟随，`note="resident:<why>"`，面板显示原因 |
| A-Life 人口上限导致 spawn 失败 | 全额退款 + `spawn_failed` |
| `setOrder` 被拒（actor 未 active / 被小队指令占用） | 保持契约，`Maintain.tick` 下一个周期重试 |
| 雇员阵亡 | 契约标 `dead`，**释放名额**，面板显示"阵亡"，玩家可手动清除 |
| 欠薪超宽限期 | 契约标 `dismissed`（居民先 `leaveOne` 退出居民系统），名额释放 |
| 沙盒关掉 Enabled | 首页入口不显示；服务端所有命令 `disabled`（契约与 NPC 保留，重开即恢复） |

---

## 6. 稳定性评级（我们依赖的每一个外部接口）

来自 `docs/research/jeem-recruit-api.md` §9 与 `economy-integration-hooks.md` §10，按"我们实际用到的"筛选：

| 接口 | 评级 | 我们的用法 |
| --- | --- | --- |
| `ProjectALife.ActorRegistry.create / read / update / remove` | 半稳定 | 造人、读状态、打防回收标记 |
| `ProjectALife.SpawnService.request / retire` | 半稳定 | 让实体落地 / 失败回滚 |
| `ProjectALife.DecisionLoop.setOrder`（follow / hold） | 半稳定 | 岗位指派的唯一实现 |
| `ProjectALife.Watchdog.bindings` + `ShellAdapter.shellPosition` | 内部实现细节 | **只读**，用于算距离与找身边 NPC；拿不到就跳过该候选，不报错 |
| `ProjectALife.Catalog.current / faction / npc` | 稳定接口 | 挑阵营与档案 |
| `ProjectALife.Relations.baselineStance` | 半稳定 | 敌对判定（只在候选筛选用，判不出来就当作不敌对） |
| `ProjectALife.ModCompat.foreignCopies`（**只读**） | 半稳定 | 启动时跑 A-Life 自己的检测器，把"自带 A-Life Lua 副本"的模组点名报出来 |
| ~~`ProjectALife.ModCompat.known`（写入）~~ | — | **已废弃**：`Compat.report()` 会按 `entry.verdict` 打印成 `[A-Life] compat: … -> adapted: …`，第三方写进去等于借 A-Life 的口替自己背书（`ALifeModCompat.lua:314-330`） |
| `ProjectALifeJimmy.Residents.recruit / leaveOne / residentOf / residents` | 半稳定 | 居民岗位 |
| `ProjectALifeJimmy.BaseAreas.who / basesFor / createBase / transmit` | 半稳定 | 找/建基地 |
| `ProjectALifeJimmy.StandingService.addGroup` | 内部实现细节 | 只在 `MakeAllied=true` 时调用，失败不致命 |
| `ProjectALifeJimmy.enabled / nameOf` | 稳定接口 | 开关判定与显示名 |
| `OrangeTradingModServer.Pay / AddCoins / PlayerData` | 稳定接口（公开全局函数） | 扣款/退款/查余额 |
| `OrangeTradingModServer.RecordPlayerFlow` | 半稳定 | 可选流水（写不进去就算了） |
| `OrangeTradingMod.UIPageRegistry.Register / Has` | 稳定接口（对方给扩展用的公开 API） | 注册页面 |
| `OrangeTradingMod.UIPageRegistry.factories["index"]` 包装 | 半稳定 | 首页入口按钮；照抄对方 `ui/bootstrap.lua` 自己的做法 |
| `OrangeTradingMod.Open`、`UIPageRegistry` 页面契约 | 半稳定 | 打开面板；页面对象实现 `relayout/activate/deactivate/render` |

**没有一处 monkey patch 对方函数**：唯一的"包装"是注册表里那个**数据项**（`factories.index`），
这是对方自己在 `bootstrap.lua` 里示范过的扩展方式。

---

## 7. 风险清单

1. **版本错配**：Jeem `versionMin=42.20.0` 低于 A-Life 自身的 `42.21.0`（上游事实）。
   任一方改 `setOrder` 的校验串或 `R.recruit` 的失败码，我们的降级文案会退化成 `ReasonUpstream`（不会崩）。
2. **人口回收**：不写 `memory.admin.persistent` 的第三方 NPC 会被 A-Life 在离玩家 60 格外 8 小时后物理删除。
   我们只给**雇员的** NPC 打这个标记（副作用：死记录不再被 `pruneDead` 清理，registry 只增不减）。
3. **命令槽争用**：`DecisionLoop.orders[uid]` 一人一槽，A-Life 的 squad leader 指令（`source="leader"`）
   会覆盖我们（`source="player"`）。因此**同一名 NPC 不要既当居民守卫又下 follow**——
   转居民时我们会先清掉自己的指令，改回跟随时会先 `leaveOne`。
4. **依赖加载时序**：橙子经济的 `UIPageRegistry` 可能在我们的 client 文件之后才创建。
   对策：文件加载时试一次 + 进世界后每秒重试（最多 60 次），失败只打一条日志。
5. **单机 vs 联机**：单机下 server 文件会加载但 `OnClientCommand` 不触发 —— 客户端 `Net` 层自己分叉
   （`isClient()` 为真才发命令，否则直连 `Service.dispatch`）。
6. **环境里有"自带 A-Life Lua 副本"的模组**（实测：某中文汉化整包重传了 A-Life 233 个 Lua 文件）：
   这类模组会让**每次 NPC 水合**都抛 `no such location`，而"把 NPC 生成出来"正是本模组的主路径。
   对策：启动时跑 A-Life 自己的 `Compat.foreignCopies(active)` 把嫌疑模组点名打进日志（只读，不改对方任何东西）。
7. **未验证项**（见 §9）：`StandingService.addGroup` 是否真能把组点数顶到同盟阈值、`bedsOverride` 的读取优先级、
   专用服上非管理员玩家转居民的成功率。

---

## 8. 测试与校验

| 手段 | 覆盖什么 | 命令 |
| --- | --- | --- |
| Lua 语法检查（fengari） | 14 个文件的语法 | `tools/lua_syntax_check.mjs` |
| 离线逻辑测试（fengari + mock 三依赖） | 招募/退款/降级/工资/死亡/去重/单机分支/UI 接入 | `tools/test/run_lua_test.sh` |
| 工坊探针（游戏自己的解析器） | `workshop.txt` 字段、tags 白名单、`validatePreviewImage` | `bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh` |
| 翻译键一致性 | 代码里出现的键 ↔ CN/EN JSON | 离线测试的一部分 |

实测（2026-10-05）：

* `lua syntax: files=14 failed=0`
* `[test] 33/33 passed, 0 failed` → `ALL PASS`（mock 忠实复刻了 A-Life `setOrder` 的校验顺序与拒绝码、
  Jeem `R.recruit` 的 15 个失败串、橙子经济 `Pay` 的先查后扣、`UIPageRegistry` 的逐行语义）
* 仓库级 `check_all.sh`：`ALL CHECKS PASSED (18 item(s))`，本物品 `submitDescription=4274` 字节

### 8.1 离线测试抓到并修掉的四个缺陷（这是它最大的价值）

| # | 缺陷 | 后果 | 修法 |
| --- | --- | --- | --- |
| 1 | `Service.dismiss` 没有 `Config.enabled()` 闸门 | 沙盒关掉模组后玩家仍能解雇，与其它三个命令行为不一致 | 补上闸门，返回 `disabled` |
| 2 | 周期重下指令丢掉了 `quiet=true`（`Maintain` → `applyMode` → `orderFollow` 没透传） | 每 8 秒重下一次 follow，会重放 follow 动画与 `ORDER_ACK` 语音 | `applyMode(player, contract, mode, quiet)` 透传；`Maintain` 传 true，首次雇佣仍为 false（保留一次"领命"反馈） |
| 3 | 退款只调 `AddCoins`、不写流水 | 玩家账单里只有扣钱、看不到退钱，对账时会以为钱丢了 | 新增 `Economy.flow(player, "in", "npc_hire_refund", …)` 与翻译键 `FlowRefund` |
| 4 | `hireSpawned` 不校验 spawn 后的 uid 是否还在 | 记录被当场回收时仍收钱、写契约，钱不退 | 读不到记录就 `retire` + 全额退款 + 返回 `spawn_failed` |

另外修掉两个"可疑点"：`Contracts.sanitize` 现在**先剔除非法项再重建 order**（一遍就干净，不再留一轮幽灵 uid）；
`Service` 的 requestId 去重队列改为**按时间裁剪**（原来只留 64 条，60 秒内连发 65 个不同 requestId
就能把最早那条挤出去，之后重放它不再判 duplicate）。两条都补了回归断言。

### 8.2 进游戏实测发现的问题（v0.1.1 修复）

首轮实机（2026-10-05 下午）跑通了：模组加载、首页入口出现、招募面板可用、**中介派遣两次成功**
（经济流水里能看到两笔 `FlowHire NPC -1500.00`）。同时暴露两个**版面**缺陷 —— 都属于
"离线逻辑测试测不到、只有真窗口尺寸才会现形"的那一类：

| # | 现象 | 根因 | 修法 |
| --- | --- | --- | --- |
| 1 | 右侧说明文字压住「跟随/守卫/居民」按钮行（窗口越矮越明显） | 模式按钮固定在 `listTop + 118`，而文本从上往下**不限行数**地画，行数一多就撞上 | 右侧面板改为**自下而上**排版：从底部预留「模式行 + 主按钮 + 次按钮」两块固定高度，文本区夹在中间；`drawLines()` 只画得下的行。次按钮位**永远预留**，切页签时按钮不跳 |
| 2 | 首页入口按钮与对方「卡片」视图按钮重叠（两个标题叠成「NPC 招募: 卡片」） | 原实现只把 `communityCenterButton` 当锚点；社区中心功能关闭时它不存在 → 回退"贴右边缘" → 正好压住右侧那排视图按钮 | 收集 `communityCenterButton` / `homeViewButtons.classic` / `.launcher` 三个锚点取**最左**，贴在它左侧；一个都没有时贴左边缘 |

对应新增的回归手段：**把版面几何当契约来测** —— 在 800×600 / 1200×700 / 520×420 三种尺寸下断言
`textBottom < modeRow.y`、主按钮在模式行之下、次按钮在主按钮之下、五个控件全部落在页面内、
三连模式按钮互不重叠、列表不侵入右侧面板、小窗口 `render()` 不抛错。
失败实验：把文本裁剪改回旧行为（`textBottom = height`），三条断言立刻变红。

**还没做**：进游戏跑完 `docs/test-plan.md` 的 T1~T18。

---

## 9. 待进游戏确认的清单

1. 首页入口按钮是否真的出现在"社区中心"按钮左边（依赖对方的 `relayout` 顺序）。
2. `Ctrl+Alt+N` 是否与其它模组/原版按键冲突（本机 1150 个模组的 grep 只覆盖了本仓库，未全量扫）。
3. 收编成功后 `setOrder(follow)` 是否真的让它跟过来（`behaviorProfile.overlays.orders` 是否都有）。
4. 转居民的非管理员路径：`StandingService.addGroup(key, groupId, factionId, 400)` 之后
   `R.isAlly` 是否返回真（需要用日志确认 `groupPoints`）。
5. 读档后指令恢复的实际延迟（预期 ≤8 秒）。
6. 专用服上两人同时雇同一个 NPC 的竞态（预期服务端 `taken_by_other`）。
7. 欠薪自动解约对居民的实际表现（是否干净退出 Jeem 居民系统）。
8. A-Life 人口上限下的派遣失败与退款日志。

---

## 10. 后续增强（v0.1.x 未实现，按优先级）

1. **世界右键菜单**：`Events.OnFillWorldObjectContextMenu` 是干净的挂接点（橙子经济自己用了 3 处，
   与本模组零冲突）。照 Jeem 的 `Features/Residents/Menu.lua`（读 shell 的 `modData.ProjectALifeUID`，
   扫周围 5×5 格）就能做"对着 NPC 右键 → 招募"。现在只有面板列表一条路径。
2. **雇员指令**：招手/待命/换装备等 —— 需要先摸清 A-Life 的 `Talk` 意图与 `ModuleConducts`，
   属于"新增行为"而非"调用已有指令"，风险等级比现在高一档，不建议在 0.1.x 做。
3. **中介刷新（招聘市场）**：每天随机几名"可招募的候选人 + 报价"，把一次性买断变成经营玩法；
   纯数据 + 现有 spawn 路径，风险低。
4. **欠薪仲裁**：欠薪时让雇员降为中立而非直接消失（需要改关系，属于 A-Life 内部行为，谨慎）。
5. **每名雇员的独立工资/岗位配置**：现在工资是全局一项；加个 per-contract 覆盖需要扩展存档字段
   （`Contracts.sanitize` 已经能吃下新增字段，属于向后兼容改动）。

---

## 11. 第二个口味：YeseMarket 版（`Bin2NPCExtensionYese`）

同一个工坊物品里再放一个模组，配另一个经济模组 [YeseMarket](https://steamcommunity.com/sharedfiles/filedetails/?id=3735641567)（mod id `YeseMarket`，作者 Dusk）。

### 11.1 为什么能几乎照搬：两边的 API 是同一套形状

逆向报告（`docs/research/yese-integration-hooks.md`）逐条比对后的结论：
`Pay / AddCoins / PlayerData().coins / IsSinglePlayer / UIPageRegistry.{Register,Has,Ids} / setPage / RecordPlayerFlow`
**签名完全一致**，只有两处实质断点：

| 断点 | 橙子经济 | YeseMarket |
| --- | --- | --- |
| 打开面板 | `Open(number, targetPage)` 支持直接指定页 | `Open(playerNum)` **只吃一个参数**（`client/event_handlers.lua:299`）→ 必须 `Open(n)` 后再 `Window:setPage(id)` |
| 入口位置 | 首页工厂有官方先例（包 `factories.index`），锚点是 `communityCenterButton` | 首页**没有**那两个锚点；导航是 `shell.lua:32` 的 `local NAVIGATION`，加不进去 → 改为**包 `UIShell:buildNavigation` + `:layoutNavigationItems` 插一行**（壳把按钮与度量放在实例字段上） |

所以变体里只有 `ui/Entry.lua` 是**独立实现**，其余全部由生成器从基模组派发。

### 11.2 变体目录是生成物（防分叉）

`tools/fork_variant.py`：

* `--write` 从 `Contents/mods/Bin2NPCExtension/42.21/**` 生成 `Bin2NPCExtensionYese/**` 与 `tools/test-yese/**`
  （替换表 + per-file 补丁 + 区域替换 + 单个文件的 override）；
* `--check` 重新生成到临时目录并逐字节比对磁盘上的变体 —— **有人手改变体就会报差异**。
  这条是这套方案能站住的关键：A-Life 适配层最容易随上游变动，两份手抄必分叉。

生成器里三处"非机械"的地方，都在源码注释里写明了理由：`ui/Entry.lua`（入口策略不同）、
`Config.SIBLING_MODULE`（PRE_SUBS 补丁，把兄弟模组 id 翻过来）、测试 19 的入口断言（策略不同，断言自然不同）。

### 11.3 跨模组互查：同一个 NPC 不能被两边同时雇走

两个模组各有一份 ModData、各自独立的名册。没有互查的话，玩家可以在两个界面各雇一次同一个 actor，
两边都认为自己拥有它，而 `DecisionLoop.orders` 是**一人一槽**，指令会互相顶掉。

`Service.hireExisting` 里加了一道**只读**互查（`takenBySibling`）：读 `Config.SIBLING_MODULE` 指向的模组的
`Store.data()` + `Contracts.owner()`，有主的直接返回 `taken_by_other`；对方不存在/字段缺失就当没有，
不会把自己锁死。测试用例 34 覆盖了"有主被拒 / 拿掉替身后又能雇"。

### 11.4 YeseMarket 版的稳定性评级

| 接口 | 评级 | 说明 |
| --- | --- | --- |
| `YeseMarket.UIPageRegistry.{Register,Has,Ids}`、`Pay/AddCoins/PlayerData`、`RecordPlayerFlow`、`setPage` | 半稳定 | 与橙子版同形状；`setPage` 对未进 `NAVIGATION` 的 id 默认放行（`navigationEnabled()` 兜底 `return true`） |
| `YeseMarket.Open(playerNum)` | 半稳定 | 唯一开窗入口，只吃一个参数 |
| `YeseMarket.UIShell.buildNavigation / layoutNavigationItems` 包装 | **内部实现细节** | 依赖 `navButtons`/`navigationViewport`/`navigationButtonHeight`/`navigationGap`/`navigationContentHeight` 五个实例字段；字段改名则该行消失（**热键仍可用**，且只会在日志里留一行） |
| `YeseMarket.Window:setPage` | 半稳定 | 开窗后切页的唯一路径 |

### 11.5 进游戏验证补充（并进 `docs/test-plan.md`）

除橙子版的 T1~T18 外，YeseMarket 版要额外测：导航栏那一行是否出现且位置正确、
点它是否切到招募页、Ctrl+Alt+N 是否也能开、`Open` 后是否停在招募页而不是首页、
以及两个模组同时启用时同一名 NPC 只能被一边雇走。

### 11.6 进游戏第一轮暴露的两个问题（v0.2.1 修复）

| # | 现象 | 根因 | 修法 |
| --- | --- | --- | --- |
| 1 | 招募页打不开，界面弹「该页面暂时不可用」 | 变体的 `Page.lua` 是从橙子版派生的，用的是橙子独有原语 `CreateCardGrid` / `GetDensityMetrics`；**YeseMarket 没有这两个**（`grep '^function Primitives\.'` 对比：它只有 `CreateList` / `CreateCard` / `CreateButton` …），于是 `Page.lua:80` 直接 "Object tried to call nil" | 变体的 `ui/Page.lua` 改为**独立实现**：`CreateList` + 自定义 `doDrawItem`（YeseMarket 自己的页面就这么做，`pages/goods.lua:432-435`），行高/按钮高改用 `UITheme.FontHeight()` 自算；选中走 `list.target` + `list.onmousedown` |
| 2 | 导航按钮显示成 `IGUI_YeseMarket_EntryButton` | 借了对方的 `YeseMarket.Text()`，它会给键强制加 `IGUI_YeseMarket_` 前缀（我们的键在自己的命名空间里） | 改用本模组自己的翻译表 `Config.Text.get("EntryButton")` |

**真正的教训不在代码，而在测试的 mock**：变体的 mock 也是从橙子版**替换**出来的，
所以它同时提供了 `CreateCardGrid`（真实 YeseMarket 没有）——测试于是"绿着"而游戏里必炸。
现在把这条变成约束：**变体 mock 只提供上游真实存在的原语**，橙子独有的两个已删除，
页面再依赖它们就会在离线测试里报 `attempt to call a nil value`（已做失败实验验证）。

> 通用原则：**跨模组 fork 时，mock 必须按目标模组的真实 API 面重建，而不是按来源模组替换** ——
> 否则"绿着的测试"反而是最危险的信号。

### 11.7 第二轮进游戏：雇下的人当不成队友（v0.2.2 修复）

**现象**：面板里雇下一名 NPC（跟随），之后想让他在营地当居民（队友）—— 不管是用 Jeem 自己的右键
「邀请入住」还是我们面板的「居民」岗位，都被拒绝，游戏提示
`[ALIFE-JIMMY] 他们对你信任不足（需要同盟关系）。`

**取证**（`~/Zomboid/console.txt` 6 次同样的提示，且我们模组一行日志都没有 → 说明我们**没参与**那次判定）：
提示本身来自 Jeem，拦截点是它的同盟门槛：

| 证据 | 位置 | 内容 |
| --- | --- | --- |
| 拦截点 | `ProjectALifeJimmy/Features/Residents/Server.lua:581` | `if not force and not R.isAlly(who.key, record) then return nil, "not_allied" end` |
| 判定 | 同上 `:490-497` | `labelFor(key, factionId) == "allied"` **或** `groupPoints(key, groupId) >= R.allyGroupPoints` |
| 阈值 | `:22` | `R.allyGroupPoints = 50` |
| 档位 | `Services/Standing.lua:24-27` | `ladder = hostile→careful→neutral→friendly→allied`、`thresholds = {25,75,150,250}`、`clamp = 400` |

**根因（两条叠加）**：
1. 沙盒选项 `MakeAllied` 的说明写的是"签约后把声望垫到同盟档"，但代码**只在 `Jimmy.recruit`（转居民）里**垫；
   于是先用 follow 雇下的人，之后永远过不了那道门（而 Jeem 自己的右键邀请走的是同一个门槛）。
2. 垫声望只调了 `StandingService.addGroup`（**小队**路径），而且要求 `memory.groupId` 是字符串 ——
   拿不到就整段静默跳过，`groupId` 那本来就不是承诺字段。

**修法**：
* 签约即垫（`Service.markAllied`，`hireExisting` / `hireSpawned` 都调用）—— 让选项兑现它文档承诺的行为；
* 改用 `StandingService.add(key, factionId, delta, { groupId = …, groupPoints = delta })`：
  阵营标签与小队点数一起顶。从最坏（hostile）到 allied 要 ≥250 点，所以一次给到 `clamp`(400)；
* 新增 `Jimmy.who(player)`：照 Jeem 自己的兜底顺序取 key（`BaseAreas.who` → `playerKey` → `username`，
  同 `Features/DoorMarks/Marks.lua:326`）。

**测试基建的教训（第二次同类）**：mock 里 Jeem 的同盟判定写成 `points >= 0`（几乎永远为真），
而且**漏了阵营标签那条路**，`StandingService` 也没有 `add`/`labelFor`/`groupPoints` ——
整条"垫声望"链路在离线测试里从未被覆盖，所以 bug 一路绿着进游戏。
现在 mock 逐条对齐真实实现，用例 35 断言的是**端到端结果**：

```
雇下（follow）→ labelFor == "allied" 且 groupPoints >= 50 且 R.isAlly == true
             → Residents.recruit(..., force=false) 成功 → 这名 NPC 成为居民（队友）
关掉 MakeAllied → labelFor == "hostile" → R.isAlly == false → 收编被拒，理由码就是 not_allied
```

**失败实验**：撤销修复后用例 35 立刻以 `not_allied` 变红（与游戏里同一句话），已记进日志。

> 这两轮（11.6 容器原语、11.7 同盟门槛）暴露的是同一个方法论问题：
> **mock 必须按目标模组的真实实现重建**。凡是 mock 比真实实现"更宽松"的地方，
> 就是下一个会在游戏里爆炸的地方。

### 11.8 第三轮进游戏：队友被误报成「居民化被拒」（v0.2.3 修复）

**现象**（用户截图，YeseMarket 版）：名册里两名雇员的第三行写着
「居民化被拒（resident（上游返回）），已降级为跟随」，岗位「跟随」、状态「在岗」；
而这两名 NPC 在 Jeem 那边**其实是居民**（`console.txt` 里有
`npc safety: hit on … blocked (your resident)`、`1 back from scavenge`、
`residents: bin2 invited 1 (…:81289) to base base:1 '河畔警察局'`）。

**证据链**：

| 证据 | 位置 | 内容 |
| --- | --- | --- |
| 拒绝码 | `…/server/ProjectALifeJimmy/Features/Residents/Server.lua:577` | `if R.residentOf(record) then return nil, "resident" end` —— `resident` 的真实含义是"**他已经是居民了**"，不是失败 |
| 事实来源 | `…/shared/ProjectALifeJimmy/Features/Residents/Residents.lua:120` | `R.residentOf(record)` = `record.memory.jimmyResident`（带 `baseId`/`index`） |
| 必然路径 | `client/…/ui/Page.lua`（roster 页） | 「应用岗位」发的是 `mode = self.pendingMode or contract.mode`，而岗位按钮当时是点一下立刻发 —— 于是"对已经是居民的人再应用一次居民"**必然**被走到 |
| 文案兜底 | `shared/…/Text.lua` 的 `REASONS` | 没有穷举 Jeem 的拒绝码，于是面板显示 `resident（上游返回）` 而不是人话 |
| 缓存写坏 | `server/…/Service.lua:setMode` | 只有"缓存说自己是居民"时才调 `leaveOne`；降级把缓存改成 follow 之后，玩家再点多少次「居民」都回不去 |

**根因**：我们把契约里的 `mode` 当成事实，而它只是 Jeem `memory.jimmyResident` 的**缓存**；
把一次**幂等的成功**（"他已经是居民"）当成了失败。

**修法（服务端幂等 + 双向对账 + 客户端不再重发）**：

* `Service.applyMode` 先读权威状态（`Jimmy.residentEntry` + `Jimmy.canManage`）：
  已经是居民就直接成功（写回 `baseId`、清 note），`Jimmy.recruit` 同样先返回；
  `resident` 拒绝码再兜一层（检查与调用之间成了居民的情况）；
* `Maintain.reconcile`（30 秒一次，进世界第一次立刻跑）双向对账：事实是居民 → 改回 `resident`；
  事实不是居民 → 落回 `follow` 并写 `left_residence`；
* `hireExisting` 在**扣款前**拦住已经是居民的 NPC（`already_resident`）；
  `dismiss`/`setMode` 按权威状态决定要不要 `leaveOne`，Jeem 说 `busy` 时如实拒绝（`leave_busy`）；
* `R.recruit` 收编的是整支小队 → `Service.adoptJoined` 把被一起带进来的契约同步改成居民；
* `Text.lua` 穷举 Jeem 的拒绝码（新增 19 个 CN/EN 键，73 → 92）；
* 客户端：「选岗位 → 点应用岗位」两步，`primaryAction` 只在岗位**确实变了**时才发；
  结果码带 `*_degraded:<原因>`，提示改为「已处理（有降级）：<原因>」；
  `Net.apply` 用服务端单调 `seq` 去重（同一份 payload 会走 `dispatch` 返回值与
  `sendServerCommand` 两条路 —— 那是聊天栏连刷 5 条「招募操作已完成。」的原因）；
* 降级路径改用 `Config.always` 打日志（以前只在沙盒 `DebugLog` 打开时才打，线上只能靠猜）。

**离线覆盖**：用例 36（重复应用同一岗位必须幂等）、37（已是居民的人在付费前被拒）、
38（对账双向自愈）、39（真失败仍降级，且原因是**人话**）；用例 19 增加了
"选岗位不发命令、岗位没变不重发"的流程断言。
**失败实验**：把幂等预读与 `Jimmy.recruit` 的快速返回同时撤掉，用例 36 立刻变红
（`mode_degraded:resident:…`、岗位变 follow、写出降级 note），与截图现象一致。

> 沉淀的判断（已同步进 `docs/rolling_log.md`）：
> 1. 契约里的状态是**缓存**，对方模组的 memory 才是事实 —— 改状态前重读事实，并配周期对账自愈；
>    判定"失败"之前先问一句"这是不是幂等的成功"。
> 2. 幂等不是可选项：UI 上任何一个"应用当前设置"的按钮，都会把同一个请求重复发出去。
> 3. 不可观测 = 不可诊断：降级必须留下始终可见的日志，拒绝码必须有本地化文案。
