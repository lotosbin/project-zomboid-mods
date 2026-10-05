# Bin2NPCExtension 进游戏测试清单（T1~T18）

> 前提：装了 `OrangeCommunityEconomy` + `ProjectALifeNPCs` (+ 可选 `ProjectALifeJimmy`)，
> 本仓库 `bin2_npc_extension` 已软链到 `~/Zomboid/mods/Bin2NPCExtension` 并在游戏 Mods 里启用。
> 建议先把沙盒 `Bin2NPCExtension.DebugLog` 设为 **true**，测完再关。
> 判定日志统一前缀：`[Bin2NPCExtension]`。日志文件：`~/Zomboid/console.txt`。

## 准备

```
ln -sfn "$PWD/bin2_npc_extension/Contents/mods/Bin2NPCExtension" ~/Zomboid/mods/Bin2NPCExtension
```

| 组 | 用例 | 期望 | 失败时先看 |
| --- | --- | --- | --- |
| A 加载 | T1 单人新档启动 | `loaded v0.1.1 \| economy=true(server=true) alife=true jeem=…`；`client ready … page=true`；无 ERROR | 橙子经济是否启用；`loadModAfter` 是否生效 |
| A 加载 | T2 主菜单 Mods 列表 | mod 名/描述/海报正常，`require` 不报缺依赖 | `mod.info` 的 `require`/`id` |
| B 入口 | T3 打开橙子经济主界面 | 首页出现「NPC 招募」按钮（在「社区中心」左边），中文标题不溢出 | `Entry.install` 是否有 `recruit page registered` 日志 |
| B 入口 | T4 按 Ctrl+Alt+N | 直接打开招募页；与其它模组/原版按键不冲突 | T3 是否通过 |
| B 入口 | T5 沙盒关掉 `Enabled` 重进 | 首页无按钮；服务端命令返回 `disabled`；契约保留 | `Config.enabled()` |
| C 收编 | T6 身边有 A-Life NPC 时开「收编」页 | 列出 NPC（名字/阵营/距离），距离 ≤ RecruitRadius | A-Life 是否真的在跑；`Watchdog.bindings` |
| C 收编 | T7 点「收编」 | 余额减少 = SignPrice；名册出现该 NPC；日志 `hired … for 500` | `Pay` 是否返回 false |
| C 收编 | T8 收编一个远处的 NPC（先在面板外走远再刷新） | 返回「离得太远」，**不扣钱** | `RecruitRadius` |
| C 收编 | T9 余额 <2 价位时收编 | 返回「社区货币不足」，名册为空，余额不变 | `ReasonNoFunds` |
| C 收编 | T10 把 MaxContracts 设为 1 后再收编第二个 | 「雇员名额已满」 | `activeCount` |
| D 派遣 | T11「中介派遣」 | 身边生成一名友好 NPC；余额减少 = SpawnPrice；日志 `spawned …` + `summoned …` | A-Life 人口上限（`ALife.Population_HostileCeiling`） |
| D 派遣 | T12 把人口上限调到最小后再派遣 | 失败并**全额退款**（`refunded …`），名册无残留 | `spawn_failed` 分支 |
| E 岗位 | T13 跟随 | 雇员跟过来；走远再回来它仍在跟（8 秒内重下指令） | `orderFollow` 的 `order_*` 失败串 |
| E 岗位 | T14 守卫 | 雇员停在签约位置附近；你走远它不跟 | `orderHold` 的锚点 |
| E 岗位 | T15 居民（需 Jeem） | 雇员进营地（可能在你自己基地或自动建的小营地）；面板岗位显示「居民」 | `R.recruit` 的失败串会写在 `最近事件` |
| E 岗位 | T16 没装 Jeem 时点居民 | 退化为跟随，面板显示原因；日志 `resident conversion unavailable` | — |
| F 运维 | T17 读档 | 指令恢复（≤8 秒），名册仍在，无重复 NPC | `restored orders for active contracts` |
| F 运维 | T18 工资 / 阵亡 / 欠薪 | 跨 24 小时扣一次日薪（`wage … paid`）；余额清零后 `unpaid=true`，超宽限期自动解约；杀死雇员后名册显示「阵亡」且名额释放 | `Maintain.settleWages` / `Maintain.tick` |

## 多人补充（专用服，用非管理员账号）

| 用例 | 期望 |
| --- | --- |
| M1 两名玩家同时收编同一个 NPC | 一人成功，另一人 `taken_by_other`；只扣一次钱 |
| M2 非管理员转居民 | 若 `MakeAllied=true` 且 `addGroup` 生效则成功；否则降级为跟随（面板写明原因），不报错 |
| M3 客户端看不到服务端 ModData 的情况下 | 面板数据仍完整（走 `sendServerCommand` 推送，不读 ModData） |
| M4 玩家掉线再上线 | 名册恢复；跟随指令在 ≤8 秒内重下 |

## 记录模板

```
T7：结果=通过/失败；console 关键行=<粘贴 5~10 行>；截图=<文件名>；备注=<…>
```

## 明确未验证的部分（写工坊声明时不要美化）

* `StandingService.addGroup(key, groupId, factionId, 400)` 是否真能把 `R.isAlly` 变成真
* 转居民时「整支小队一起进营地」的实际观感
* 首页按钮与「社区中心」按钮的排布是否永远不重叠（对方改布局就会变）
* 与其它 NPC 模组（Bandits2、The Mutants 等）的共存

## YeseMarket 版（`Bin2NPCExtensionYese`）补充用例

同一物品里的另一个口味配 [YeseMarket](https://steamcommunity.com/sharedfiles/filedetails/?id=3735641567)。
它的入口不是首页按钮，而是**导航栏新插的一行**，所以下面这几条必须单独跑一遍：

| 组 | 用例 | 期望 | 失败时先看 |
| --- | --- | --- | --- |
| Y 入口 | Y1 装 YeseMarket + 本模组（**不要**装橙子版依赖） | 控制台 `recruit page registered; YeseMarket navigation row installed` | `Config.economy()` 是否拿到 `YeseMarket` |
| Y 入口 | Y2 开 YeseMarket 界面 | 左侧导航栏**多出一行**「NPC Recruit」，在最后一行下方 | 上游是否改了 `navButtons` / `navigationButtonHeight` 等字段名 |
| Y 入口 | Y3 点那一行 | 右侧切到招募页（**不是**首页） | `setPage` 是否放行我们的 pageId |
| Y 入口 | Y4 按 Ctrl+Alt+N | 从任意时刻都能打开招募面板；与 YeseMarket 自带按键不冲突（它全库零绑定） | 热键是这条路径的兜底 |
| Y 入口 | Y5 先关窗口再按热键 | 会先开窗再切到招募页（`Open(playerNum)` → `Window:setPage`），不会停在首页 | `Open` 只吃一个参数 |
| Y 功能 | Y6 收编 / 派遣 / 岗位 / 工资 / 解雇 | 与 T6~T18 相同；货币显示为「金币」 | 记账看 `RecordPlayerFlow` 的 out/in 两行 |
| Y 共存 | Y7 两个口味同时启用 | 两个界面各自可开；**同一个 NPC 只能被一边雇走**（另一边报「已被其他玩家雇佣」） | `Service.hiredBySibling` 互查 |
