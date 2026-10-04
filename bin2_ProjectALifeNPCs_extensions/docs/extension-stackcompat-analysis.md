# 标杆扩展 ③：[ALifeStackCompat] A-Life × 僵尸行为模组 兼容层

> 对象：工坊 `3808789424` / Mod ID `ALifeStackCompat` / 作者 SteamID `76561198042988729`
> 版本：`mod.info` 与 Lua 均为 **1.3**（工坊描述里的控制台示例仍写 "loaded 1.2"）
> 订阅 226 / 收藏 28 / 浏览 899 / 创建 2026-09-27 / 最后更新 2026-10-03 / tags：Build 42、Balance、Misc、Multiplayer
> `versionMin=42.20`；`loadModAfter=ProjectALifeNPCs,UVDefense,PZTheMutants,KillCount,TrippingZombies,claimableoutposts,ZombieDismembermentB42`
> 全程只读分析（本机已订阅，源码 20 KB）

---

## 0. 为什么这份分析值得单独写

上一轮头脑风暴里，我把 **"兼容/冲突守护层"** 列为 H3 类的一个候选方向（并注明"不与 Bandits2 融合，只做检测提示"）。

**这个模组证明该方向已被市场验证，而且做法比我设想的更激进**：

- 体量极小：**1 个 Lua 文件 / 294 行 / 13 KB**，一个工坊物品，226 订阅；
- 它不"提示"冲突，而是**直接让 6 个第三方模组跳过 A-Life NPC**；
- 它找到了一个**生态级的隐藏契约**（`Bandit` 动画变量），并用它一行代码搞定三个模组。

对我们要做的任何"兼容层/手柄/Viewpoint 适配"，它是**最贴近的工程模板**。

---

## 1. 打包：全项目放进 `common/`（罕见的极简形态）

```
3808789424/mods/ALifeStackCompat/
├── common/mod.info                              ← mod.info 在 common/ 里（没有版本目录！）
└── common/media/lua/shared/ALifeStackCompat.lua  ← 唯一的代码文件，294 行
```

**没有 `42/` 或 `42.20/` 版本目录**。这利用了我们已经用字节码验证过的引擎事实：
`ZomboidFileSystem` 扫描时先探测 `<mod>/common/mod.info`，找到即注册，并把 `common/media` 当作资源根
（`PZModFolder{common, version}`）——所以**整个模组可以只活在 `common/` 里**。

**取舍**：好处是一个文件覆盖所有 B42 小版本；代价是**没有任何按版本分叉的能力**，
一旦某个目标模组在不同 build 上 API 不同，就只能靠运行时探测（它正是这么做的）。

---

## 2. 它到底做了什么

### 2.1 两件"打标"（对每个 A-Life 身体只做一次）

| # | 操作 | 目的 | 代码 |
| --- | --- | --- | --- |
| 1 | `z:setVariable("Bandit", true)` | **借 Bandits2 的标记**，让读该变量的模组跳过这个 NPC | `:93` |
| 2 | `z:getInventory():setExplored(true)` | 关掉原版僵尸"口袋战利品"与 AmmoLootDrop 的弹药掉落；A-Life 自己发掉落 | `:94-97` |

作者在注释里专门说明了**为什么敢这么写**：

```
1. setVariable("Bandit", true) -> TrippingZombies.isModNpc, Claimable
   Outposts' CO_ServerIsBanditsNpc and PZTheMutants.ForeignOwnership all
   skip it. A-Life never reads "Bandit" (checked on 1.1 and 1.3).
```

→ 意思是：**他们审计过 A-Life，确认 A-Life 自己从不读 `Bandit`**，所以设这个值不会干扰 A-Life。

### 2.2 四个 wrapper（全部"缺失即失效"）

| 目标模组 | 挂接点 | 语义 | 目标缺失时 |
| --- | --- | --- | --- |
| **The Mutants** | `PZTheMutants.ForeignOwnership.isClaimed` | 返回 `true, "ProjectALifeNPCs", "moddata"` → NPC 永不被"装扮成 Mutant" | `"absent"` |
| **UV Defense** | `UVDefense.markFeared` / `UVDefense.canDriveZombie` | 永不进入恐慌/撤退状态机、永不被 UV 光照驱动 | `"absent"` |
| **KillCount** | `KillCountWeaponType.addToKillCount` + `KillCount.updateB41_52/60_OnZombieDead` | A-Life 受害者不计入击杀数 | `"absent"` |
| **Zombie Dismemberment** | `ZD_Network.isGrapple` | 对我们的身体返回 `true` → 其命中处理直接 return，**不会切断/斩首/致残 NPC** | `"absent"` |

前三个是"**跳过**"语义（返回 `nil`/`false`/不计数）。
第四个是"**伪装**"语义：把 NPC 假装成"被抓住的身体"，让对方的第一个判断就短路退出——
注释里明确写了它在单人下**不生效**（单人跳过该检查），只覆盖多人：

```
-- Single player is not covered (the check is skipped there); this server is multiplayer.
```

**每个 wrapper 的统一骨架**（这是可以直接抄的模板）：

```lua
local function wrapXYZ()
    local M = XYZMod                                  -- 1. 取全局表
    if type(M) ~= "table" or type(M.fn) ~= "function" then return "absent" end
    if M._alscWrapped then return "wrapped" end        -- 2. 幂等标记
    local original = M.fn                              -- 3. 存原函数
    M.fn = function(...)                               -- 4. 守卫式替换
        if ALSC.isOurs(select(1, ...)) then return <跳过值> end
        return original(...)
    end
    M._alscWrapped = true
    return "wrapped"
end
```

---

## 3. 关键机制深挖

### 3.1 `isOurs`：三路回退（与官方契约完全一致）

```lua
-- :64-83
function ALSC.isOurs(z)
    if z == nil then return false end
    local ok, result = pcall(function()
        if z.getModData ~= nil then
            local md = z:getModData()
            if type(md) == "table" and (md.ProjectALifeOwned == true or md.ProjectALifeActor == true) then
                return true
            end
        end
        if z.getVariableBoolean ~= nil and z:getVariableBoolean("ALifeActor") then return true end
        if z.GetVariable ~= nil then
            local uid = z:GetVariable("ALifeUID")
            if uid ~= nil and uid ~= "" then return true end
        end
        return false
    end)
    return ok and result == true
end
```

三路 = `modData` 布尔 → `getVariableBoolean("ALifeActor")` → `GetVariable("ALifeUID")` 字符串兜底。
**这正是本报告主文档第 4.6 节发现的必要形态**（A-Life 在尸体上会把 `ProjectALifeOwned` 置 `nil`），
说明这位作者也踩过那个坑。

> 附带发现一个 API 细节：代码同时用了 `getVariableBoolean` 与 `GetVariable`
> ——前者是**类型化 getter**（返回 boolean），后者返回字符串。

### 3.2 ⚠️ 核心发现：`Bandit` 是**生态级既成契约**，而不是某个模组的内部变量

我在本机 **1,150 个已装模组**里全量 grep 了 `Bandit` 这个动画变量，**至少 10 个模组在读它**：

| 模组 | 读取点 | 语义 | 对 A-Life NPC 是 |
| --- | --- | --- | --- |
| **Bandits2**（3268487204） | `BanditUpdate.lua:199`（**写入** true）、`BanditZombie.lua:74`、`BanditPlayer.lua:88`、`BanditMenu.lua:153/239` | `if isBandit then GetBrain(zombie) ... 缓存为 bandit` | ⚠️ **当成强盗处理**（会用 Bandits2 的 brain 系统接管） |
| **BanditsFixPlus**（3777752751） | `BFP_Core.lua:41,156`、`BFP_Stealth.lua:95,154`、`BFP_Loot.lua:222`、`BFP_CorpseServer.lua:132` | 雷达/潜行/掉落都按 bandit 分支 | ⚠️ **当成强盗处理** |
| **CompanionDogs**（3740052292） | `core/Identity.lua:20` | `isFriendlyBanditNPC`：读 `Bandit`，再看 `md.brain`，**没有 brain 就返回 true（=友方 NPC）** | ⚠️ **被判为"友方强盗 NPC"** |
| **PZTheMutants**（3796669056） | `PZM_ForeignOwnership.lua:79` | "Bandits documents this animation variable as its external runtime marker" → 返回 claimed | ✅ 跳过（正是本模组的目标） |
| **ZoneLootRefill**（3653007556） | `ZLR_BanditsCompat.lua:1085`、`ZLR_BanditsProtection.lua:85/113/136` | 保护 bandit 尸体不被刷新覆盖 | ✅ 保护 |
| **InjuredZombiesStumble**（3648051123） | `InjuredZombiesStumble.lua:8` | `if getActivatedMods():contains("Bandits") and zombie:getVariableBoolean("Bandit")` → 跳过 | ✅ 跳过 |
| **SZedPlus**（3792733238） | `SZedPlus_Spawn.lua:184` | 生成时跳过 | ✅ 跳过 |
| **NPCBases**（3796483217） | `NPCBases_BanditsBridge.lua:786` | 统计/桥接 Bandits 定居点 | ⚠️ 当成 bandits |
| **Bridge / Stay With Me**（3800989007） | `BridgeData.lua:122` | 读标记做同伴判定 | ⚠️ 待确认 |
| **ALifeStackCompat** 自身 | `:93` | 写入标记 | — |

**结论（本项目最重要的风险条目）**：

> `setVariable("Bandit", true)` 是一把双刃剑。
> 它让 A-Life NPC 对"跳过型"模组隐身（本模组的目标），
> 但也把它**注册进了 Bandits2 生态的语义**——凡是把 `Bandit=true` 当"这是强盗"的模组
> （Bandits2 本体、BanditsFixPlus、NPCBases、CompanionDogs）都会对 A-Life NPC 施加自己的逻辑。
>
> 而 A-Life 官方对 `Bandits2` 的判定是 **`unsupported`**（"另一套建立在僵尸身体上的 NPC 系统，未一起测试"）。
> 本模组的描述里**没有提到这个副作用**。

**对本机（本仓库作者）的直接意义**：本机同时装着
`Bandits2` + `BanditsFixPlus` + `NPCBases` + `CompanionDogs`（+ 本仓库自己的羊驼扩展）+ `PZTheMutants`。
若启用 ALifeStackCompat，A-Life NPC 会同时被"跳过型"和"当强盗型"两批模组处理 ——
**必须先做对照实验**（开/关 Bandits2 两组的日志与行为对比），再决定是否长期启用。

### 3.3 `setExplored(true)`：一行关掉原版掉落

```lua
pcall(function()
    local inv = z:getInventory()
    if inv ~= nil then inv:setExplored(true) end
end)
```

原版僵尸尸体掉落依赖"容器未被探索"这一状态；标记为已探索即可跳过"口袋战利品"，
也顺带让 AmmoLootDrop 之类的弹药注入失效。这与 A-Life 自己的"NPC 尸体只掉 A-Life 的掉落"设计一致。

---

## 4. 工程教训（作者用三个版本换来的，全部写在注释里）

### 4.1 v1.1：**服务端打标竞态** —— 最重要的教训

```
-- 1.1: on the dedicated server the tagging pass no longer depends on
-- OnZombieUpdate (it never reached the shim there: 0 bodies tagged in a
-- session with 118 A-Life spawns). The server now tags from OnZombieCreate
-- (queued, checked on the following ticks, because A-Life marks the body
-- right after createZombie returns) and from a full cell sweep every
-- SWEEP_TICKS ticks. OnZombieUpdate stays for the clients.
```

拆开看：
1. **专用服务器上 `OnZombieUpdate` 根本没触发到本模组** —— 118 次 A-Life 生成，**打标 0 个**。
2. 于是改用 `OnZombieCreate` **入队 + 延迟复查**：
   ```lua
   ALSC.PENDING_TICKS = 10        -- 每 10 tick 复查一次队列
   ALSC.PENDING_MAX_CHECKS = 90   -- 单个身体最多复查 90 次
   ALSC.SWEEP_TICKS = 300         -- 每 300 tick 全量扫一遍 cell 僵尸列表
   ```
3. **为什么必须延迟**：A-Life 是 `createZombie(...)` **之后**才写 modData 标记的，
   所以在 `OnZombieCreate` 当场检查，身体"还不是" A-Life NPC（这正是我主报告 §4.1 里
   `ShellAdapter.lua:82-140` 的顺序：先造壳 → 再 `setVariable`/`getModData`）。
4. 客户端仍保留 `OnZombieUpdate` 路径（客户端能收到该事件）。

> **可复用的规律**：想给 A-Life NPC 打第三方标记，**不能**在 `OnZombieCreate` 同步做，
> 必须"入队 + 下一 tick 起复查"，并备一条**低频全量扫描**兜底（区块流式加载进来的身体不会触发 create 事件）。
> 这与主报告 §4.15 "卸载 ≠ 死亡" 是同一个坑的两面。

### 4.2 v1.2：**按引用重注册事件处理器时，必须镜像原注册条件**

```
-- 1.2: KillCount's OnZombieDead wrapper is re-registered only where KillCount
-- itself registers the handler (isClient() false). 1.1 added it on multiplayer
-- clients too, where KillCount never creates its kill tables, so every zombie
-- death threw KillCountUpdate.lua:149 "attempted index of non-table".
```

```lua
local registered = not (isClient and isClient())
if registered then
    pcall(function() Events.OnZombieDead.Remove(original) end)
    pcall(function() Events.OnZombieDead.Add(wrapped) end)
end
KC[name] = wrapped        -- 无论如何都替换表字段（调用方走字段查表）
```

KillCount 只在**非客户端**注册该 handler；1.1 在多人客户端上也注册了包装版，
导致原函数在**它从未创建的表**上索引 → 每次僵尸死亡都报错。

> **规律**：`Events.X.Remove(original) + Add(wrapped)` 这种"按引用换绑"必须
> **完整复制原 handler 的注册条件**（`isClient()`/`isServer()`/单机判断）。
> 这与我们 `pz-engine-deepdive` skill 里"`@Patch.OnExit` 只在异常路径动手"的思路同源：**正常路径零影响**。

### 4.3 其他值得抄的细节

| 细节 | 做法 | 位置 |
| --- | --- | --- |
| **幂等** | 每个被包的表打 `_alscWrapped = true`；`install()` 在 `OnGameStart` 与 `OnServerStarted` 各挂一次 | `:164,184,206,256,291-292` |
| **失败即降级** | 每个 wrapper 先类型探测，缺依赖返回 `"absent"`；所有引擎调用套 `pcall`（`safe()` helper） | `:57-61, 157-264` |
| **可观测性** | 启动打印 `loaded 1.3: alife=present mutants=wrapped uvdefense=wrapped killcount=wrapped\|absent tripping=shim outposts=shim`；`EveryTenMinutes` 打印 `tagged N A-Life bodies this session (created seen X, pending Y, sweeps Z)` | `:276-285` |
| **打标去重** | 用自己的 key `ALSC_Tagged` 记录"已打标"，热路径只读一个表字段 | `:51, 91, 108-111` |
| **容错日志** | 第一个打标的身体打印其 `ProjectALifeUID`（便于对账） | `:100-102` |

### 4.4 它的取舍与局限（作者自己列了一部分）

| 项 | 说明 |
| --- | --- |
| **单人下 ZD 不覆盖** | 作者明写 "Single player is not covered (the check is skipped there)" |
| **帧计数调度** | `SWEEP_TICKS=300` / `PENDING_TICKS=10` 是**帧计数**而非毫秒，帧率变化会改变实际间隔；全量 sweep 是 O(cell 僵尸数) |
| **遍历活列表** | `sweepCell` 直接 `cell:getZombieList()` 遍历（该 API 返回引擎内部 ArrayList 本体）——它只读 + 打标，**不增删元素**，因此安全；但这是必须遵守的边界 |
| **依赖全局表名** | 所有 wrapper 都直接引用 `PZTheMutants` / `UVDefense` / `KillCount` / `ZD_Network` 等全局表，任一改名即 `"absent"`（静默降级） |
| **版本号不一致** | `mod.info` 与 Lua 是 1.3，工坊描述的示例输出仍写 `loaded 1.2` |
| **未处理的 Bandit 反噬** | 见 §3.2，描述里完全没提 |

---

## 5. 对我们的启发（三条可执行结论）

### 5.1 这就是"兼容层"产品的完整模板，照抄即可

```
<Item>/mods/<ModId>/
├── common/mod.info                                    # 只活一个文件也能成立
└── common/media/lua/shared/<ModId>.lua                # 打标 + 若干 wrapper + install 汇总
```

骨架 = ①`isOurs` 三路回退；②`tagBody` 幂等打标；③`OnZombieCreate` 入队 + `OnTick` 延迟复查 + 低频 sweep；
④每个目标一个 `wrapXxx()` 返回 `"wrapped"/"absent"`；⑤`install()` 汇总 + 启动日志；⑥`EveryTenMinutes` 报计数。

### 5.2 生态里还有**它没覆盖**的栈，这些就是空白点

本模组覆盖 6 个（Tripping/Claimable Outposts/Mutants/UV Defense/KillCount/Zombie Dismemberment），
但本机装着的这些**僵尸/NPC 相关模组不在其中**：

| 未覆盖模组 | 读取的东西 | 风险类型 |
| --- | --- | --- |
| **Bandits2 + BanditsFixPlus + NPCBases** | `Bandit` 标记 | **反噬**（会被当成强盗；A-Life 官方即判 `unsupported`） |
| **CompanionDogs**（+ 本仓库羊驼扩展） | `Bandit` 标记 → `isFriendlyBanditNPC` | 分类错误（A-Life NPC 被当友方强盗） |
| **WanderingZombies** | 已由 **A-Life 官方适配器**覆盖（`adapted`），无需第三方 | — |
| **Improved Hair Menu / moreTraits / Point Blank / AutoAll / CyesPushDoors / RV Interior / PixelStrike / ProjectExile / GaelGunStore** | 均已在 A-Life 官方 `Compat.known` 里 → 无需第三方 | — |
| **Neat 系列（本仓库的手柄相关）** | A-Life 已声明 `compatible`，但**没有手柄支持** | 功能空白（见 `roadmap.md` 阶段 1-B） |

→ **可做的产品**：把同一模板扩展成"**A-Life 栈兼容 2.0**"，
优先解决 **Bandit 标记反噬**（例如：仅在启用 Bandits2 时改用别的标记 / 或对 Bandits2 系模组做反向守卫），
再补 CompanionDogs 的分类修正（与本仓库的羊驼扩展直接相关）。

### 5.3 关键取舍：标记的"最小侵入"原则

`Bandit` 能一行命中三个模组，是因为它**已经被生态广泛读取**；
但它同时是**别人的所有权标记**，借用必然带副作用。

> **新原则（建议写进本目录的工程约定）**：
> 借用第三方标记前，必须先把**全量读取者**列出来，并逐个判定是"跳过语义"还是"认领语义"；
> 只要有任一是认领语义，就不能无条件借用，要么加启用条件，要么用更窄的目标专用标记。

---

## 6. 复核命令

```bash
WS="$HOME/Library/Application Support/Steam/steamapps/workshop/content/108600"

# 1) 元数据
curl -s -X POST "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" \
     -d "itemcount=1&publishedfileids[0]=3808789424"

# 2) 源码（只有 2 个文件）
find "$WS/3808789424" -type f

# 3) Bandit 标记的全部读取者（本机 1,150 个模组全量 grep）
grep -rn --include=*.lua -E 'getVariable(Boolean|String)?\("Bandit"\)' "$WS" | sed "s|$WS/||"
```

---

## 7. 一句话结论

> **13 KB 的模组，226 个订阅，却揭示了整个生态最深的隐藏契约（`Bandit` 动画变量）与两个血泪级工程教训
> （服务端打标竞态、按引用重注册事件时的条件镜像）。
> 它是"兼容层"这一类产品可以照抄的完整模板 —— 同时，它没写进描述的那个副作用（把 A-Life NPC 拉进 Bandits2 语义）
> 正是我们应该接手解决的第一个真问题。**
