# 标杆扩展 ②：Project A-Life: Aftermath 逆向分析

> 对象：工坊 `3806063445` / 作者 Shinyu / v1.3.1 / 5,921 订阅 / tags：Clothing/Armor、Hardmode、Items、Military、Models、Weapons
> **一个工坊物品里含 3 个 mod**：`ProjectALifeAftermath`（Guns of Marz）、`ProjectALifeAftermathG93`（Guns of '93）、`ProjectALifeAftermathMFS`（Modern Firearms）
> 路径缩写：`$W = .../108600/3806063445`，`$C = .../3803984183/mods/ProjectALifeNPCs`
> 全程只读分析

---

## 1. 一物品三 mod 的打包

`$W` 下**没有 `Contents/`**，直接是 `mods/`（B42 版本根布局：`42/` = 版本专属，`common/` = 全版本共享）：

```
$W/mods/{ProjectALifeAftermath, ProjectALifeAftermathG93, ProjectALifeAftermathMFS}/
  42/mod.info  icon.png  poster.png  media/lua/{shared,server,client}/...
  common/equipment/core/{factions,npcs}.alife
  common/equipment/providers/*.alife
```

`mod.info` 在 `42/mod.info`（不是 mod 根）。三份字段一致，仅 4 项不同：

```ini
# $W/mods/ProjectALifeAftermath/42/mod.info
name=... / id=ProjectALifeAftermath / author=Shinyu / modversion=1.3.1 / versionMin=42.20.0
icon=icon.png / poster=poster.png
require=ProjectALifeNPCs,GunsOfMarz
incompatible=ProjectALifeAftermathMFS,ProjectALifeAftermathG93,ModernFirearmsSystem,guns93
loadModAfter=ProjectALifeNPCs,SWMG,GunsOfMarz,UndeadSuvivor,VanillaOutfitsExpanded,AliceGear,
  TLOUClothingB42fixed,odz_fallout_riotarmorpack,SCP_Foundation_Pack,VanillaGearExpanded,MilPonchoB42,
  EFTBP,ZombieHunterBackpackB42,KATTAJ1_ClothesCore,KATTAJ1_Military,[J&G] Umbrella Corp Uniform,
  FH,SpnHair,BCGTools,BCGRareWeapons
```
G93 版把 `GunsOfMarz→guns93` 并删掉 `SWMG`；MFS 版把 `GunsOfMarz→ModernFirearmsSystem`，
并追加 `BackpackSystemB42,BladesmithSystemB42`。

**assets 规模 = 0**：全包只有 **79 个 `.alife` + 41 个 `.lua` + 6 个 `.png`**。
`find` 确认无 `clothing/`、`models_X/`、`textures/`、`scripts/`、`sound/`、`ui/`、`AnimSets/`。
`poster.png` 三份同为 502,151 B、`icon.png` 6,700 B；总体积 6.4 MB（各 `common/` 1.5/1.5/1.6 MB **全是文本**）。
数据量：GoM/G93 = **13 阵营 / 912 NPC**；MFS = **16 / 943**。

> **这是全报告最重要的一条**：一个 5,921 订阅的扩展**没有任何美术资产**，只有文本数据 + 少量 Lua。
> 纯数据扩展是真实可行且被市场验证的路径。

---

## 2. 核心机制：依赖感知的阵营提供者

**关键结论（与直觉相反）**：不是运行时构造内容，也不是"多套数据按条件选一套"，
而是 —— **单一数据集 + 运行时条件合并**。

三变体的 `common/equipment/**` **79 个文件逐字节完全相同**（md5 校验全部一致；
`core/npcs.alife` 恒为 `69903e29ae52701595a88976bbe37f5b`），且里面**写死了 `MarzGuns.*`**。
加载时按各 provider 的 `requires` 门控逐个 merge 进 A-Life 目录。

### 2.1 唯一的启用探测：`getActivatedMods():contains(id)`

```lua
-- $W/mods/ProjectALifeAftermath/42/media/lua/shared/ALifeEquipment/Loader.lua:7-19
local function active(modId)
    if type(getActivatedMods) ~= "function" then return false end
    local ok, mods = pcall(getActivatedMods)
    if not ok or mods == nil then return false end
    local found = false
    pcall(function() found = mods:contains(modId) == true end)
    return found
end
local function allActive(required)
    for _, id in ipairs(required or {}) do if not active(id) then return false end end
    return true
end
-- Loader.lua:292-293  ← 门控点
for _, provider in ipairs(providers) do
    if allActive(provider.requires) then ... end
```

全包 26 处使用。**不是** `getScriptManager():FindItem`（全包零使用），**不是** `instanceof`。
物品存在性另用 `ScriptManager.instance:getItem()`（`ALifeEquipment/Guns93Backend.lua:37`、`MFSBackend.lua:584`）；
`instanceof(shell,"IsoPlayer")` 只出现在 `ALifeGoMHandgunPatch/Core.lua:31` 与 `ALifeMFSHandgunPatch/Core.lua:56`
（区分 NPC/玩家，与阵营门控无关）。

### 2.2 "身份提供者 vs 通用 overlay"由 `kind` 字段实现（`Loader.lua:95-119`）

| kind | 作用 | 记录数 |
| --- | --- | --- |
| `faction_upsert` | 新增阵营（**受身份门控**） | tlou 2、riot 1、scp 1、vge 1、us 5、kat 1、umbrella 1 |
| `npc_upsert` | 该阵营的 NPC（与同前缀 provider 共用 `requires`） | 6 / 3 / 4 / 0 / 10 / 4 / 4 |
| `npc_merge` | 改已存在 NPC 的装备（overlay） | voe 192、fluffy 204、spongie 202、milponcho 85、alice 72、eft 34、bcg_tools 11、zhb 4、bcg_rare 2 |
| `npc_overlay` | merge + 先清掉核心兜底 outfit | vge 71 |

例：`aep_scp_foundation` 只在 `SCP_Foundation_Pack` 启用时出现；
`aep_us_stalkers/nomads/preppers/headhunters/amazona` 只在 `UndeadSuvivor` 启用时出现；
`aep_vanguard_recovery` 需 `KATTAJ1_Military` + `KATTAJ1_ClothesCore`；
`[J&G] Umbrella Corp Uniform` + `KATTAJ1_ClothesCore` → `aep_umbrella_containment`。
核心阵营（`core/factions.alife`）与纯装备 overlay 无门控。

### 2.3 执行时机

`Aftermath/CatalogBridge.lua` 在 **shared Lua 加载期**（`ZZ_ProjectALifeAftermath.lua:2` require）
就猴补 `ProjectALife.Catalog.load`；真正的门控/合并发生在 `Catalog.load()` 被调用时，即
`Events.OnGameStart` / `OnServerStarted`（`$C/.../Core/ALifeServerBootstrap.lua:30-31`）
→ `Runtime.safeStart` → `Core/ALifeRuntime.lua:288` → `Catalog.load()`。
另有热载兜底 `CatalogBridge.lua:76-83`（若 `Catalog.current` 已存在则强制原版 reload 一次）。
**不涉及 `Events.OnInitGlobalModData`。**

---

## 3. 注入 A-Life 的全部调用点

| A-Life 内部对象 | 操作 | 位置 |
| --- | --- | --- |
| `ProjectALife.Catalog.load` | 包装，在 `baseLoad(true)` 前后插桩 | `CatalogBridge.lua:55-68` |
| `ProjectALife.Catalog.shipped` | 直接改缓存表再走原 API 重建 | `CatalogBridge.lua:17-19` |
| `ProjectALife.Catalog.current` | 读 + 兜底 finalize | `CatalogBridge.lua:76,81` |
| `ProjectALife.CatalogParser.parseText(text, source, kind)` | 解析自带 `.alife` | `Loader.lua:266,298` |
| `ProjectALife.ProfileHydrator.plan/.apply` | 弹药/弹匣元数据、plan 缓存 | `server/Aftermath/ProfileBridge.lua:46-73,112-122` |
| `ProjectALife.LoadoutProgression.apply` | 保留签发枪械 | `ProfileBridge.lua:19-44` |
| `ProjectALife.MagazineState.initialize` | 自定义弹匣容量 / `attachWeaponPart` | `ProfileBridge.lua:77-110` |
| `ProjectALife.DeathDrops.plan/.dropMagazines` | 掉弹匣 / 散弹 | `ProfileBridge.lua:132-197` |
| `ProjectALife.MagazineState.consumeRound` | MFS 分层枪声 | `server/ZZ_ProjectALifeAftermathMFSGunshotBridge.lua` |
| `ProjectALife.Weapons.select` | 手枪动画标记 | `ALifeGoMHandgunPatch/Core.lua:81-91` |
| `ProjectALife.Animations.presentWeapon/.apply` | 手枪动画映射 | `ALifeGoMHandgunPatch/Core.lua:54-79` |
| `ProjectALife.CreatorFolders.seedDefaults` | 建 "Aftermath Factions" 文件夹 | `client/ZZ_ProjectALifeAftermathCreatorFolders.lua:51-59` |

**没做的事**（很有信息量）：
- 无 `Registry.register`（不注册行为模块）
- 无 `ALifeCustomFactions`/`ALifeCustomProfiles` 写入
- **不写** `common/alife_runtime/catalog/*.alife`（那是 A-Life 自己的，由
  `ALifeCatalog.lua:113,117` 用 `getModFileReader("ProjectALifeNPCs", ...)` 读取）
- **不用** `ALIFEPACK1-` 分享码（该格式仅核心 `Records/ALifeFactionShare.lua:197` 定义）
- 自带数据读取走 `getModFileReader(Patch.MOD_ID, path, false)`（`Loader.lua:21`），路径相对 `common/`

**自有 modData 键**：只写 A-Life 已识别的 `ProjectALifePrimaryType`、`MagazineType`、`AmmoList`
（`ALifeGoMHandgunPatch/Core.lua:36`、`ProfileBridge.lua:92,103,172`）+
`shell:setVariable("ALifePrimaryType", ...)`；读 `ProjectALifeActiveWeaponType`。**无自建命名空间。**

---

## 4. 三变体如何从同源分叉

数据 100% 相同，**分叉只靠 4 个常量 + 换一个 backend 文件**：

```lua
-- 00_ProjectALifeAftermathBootstrap.lua:3-8  ← 唯一的"配置"
A.modId   = "ProjectALifeAftermathMFS"      -- 无后缀 / G93 / MFS
A.edition = "Modern Firearms Edition"       -- "Guns of Marz Edition" / "Guns of '93 Edition"
A.backend = "mfs"                           -- "gom" / "g93"
A.tag     = "[ALIFE-AFTERMATH:MFS]"         -- 日志前缀
```

`Loader.lua` 是同源复制（diff 显示 89% 相同），差异只有三处：
`Patch.MOD_ID`、`require "ALifeEquipment/<X>Backend"`、`presets/finalize` 的委托对象：

```lua
-- G93 / MFS Loader.lua:236-244（GoM 版此处是 applyCore + applyProviders + enforceGoM）
function Patch.presets(loaded)
    applyCore(loaded); applyProviders(loaded)
    return Backend.enforce(loaded, put)
end
function Patch.finalize(loaded) return Backend.enforce(loaded, put) end
```

- **GoM 版**：静态 1:1 映射表（`Loader.lua:121-145` `FIREARM_MAP`：`Base.Pistol → MarzGuns.M92FS`）
  + 弹药表 `GOM_META`（`:146-167`）。
- **G93/MFS 版**：语义角色池（`Guns93Backend.lua:6-32` / `MFSBackend.lua:7-329` 的 `POOLS`），
  `SOURCE_ROLE` 把 `Base.*` 与 `MarzGuns.*` 统一映射为 `sidearm/assault/precision_elite/...`，
  `refineRole()` 按 profile 名/行为提级（"sniper"→precision、"breacher"→shotgun_elite），
  `stableIndex(seed, n)` 做**确定性选择**（同 profile 每次同枪），`scriptExists()` 过滤未安装的枪。
- MFS 额外多 4 个 `.alife`（`mfs_factions` / `mfs_npc` / `mfs_backpacks_npc` / `mfs_blades_npc`）、
  `ZZ_ProjectALifeAftermathMFSGunshotBridge.lua`、Creator 文件夹多 3 个 id
  （`aep_mfs_jrtf` / `aep_mfs_ravenwood` / `aep_mfs_blacksite`）。

---

## 5. 装备/服装/武器内容管线

**服装、模型、脚本零自有资产**，全靠引用外部 mod 的 item id。`.alife` 一行一个槽位，`|` 分隔候选：

```
outfitA.Hat Base.Hat_Army|none
outfitA.Top Base.Tshirt_ArmyGreen|Base.Shirt_Workman
weapons.primary MarzGuns.MP5
ammo.primary 60
```

字段分布（GoM）：`outfitA` 8857、`outfitB` 8590、`outfitC~F` 各 8064、`outfitEnabled` 1191、
`general` 733、`spawn` 288、`memberModules` 285、`relations` 164、`weapons` 130。

- **loading 槽位**只有 `weapons.primary` / `secondary`（`Loader.lua:213`）；
  弹药经 `ammoMinimum / standardMagazines / standardMagazineCaps / magazineDrops / looseAmmoDrops` 注入
  （`Loader.lua:193-204` → `ProfileBridge.lua:54-69`）。
- **attachments** 走原版 `AttachedLocations.getGroup("Human"):getOrCreateLocation(...):setAttachmentName(...)`
  （`UndeadSurvivor_Attachments.lua:30-43`）+ `script:DoParam("AttachmentType = GunMagazine")`（`:25`），
  把 GoM 的 52 个弹匣挂到 Prepper Vest 的 4 个物理弹匣槽。
- 行为模块经 `memberModules.*`（285 条）传给 A-Life。

### `incompatible=` 的真实原因（重要）

**不是资产冲突，而是"同一份 GoM 口径数据被三套互斥解释器处理"**：
数据里写 `MarzGuns.MP5`，GoM 版再映射、G93 版翻成 `Base.MP5`、MFS 版翻成 `Base.mp5_cat`。
三者并存会按 `require=` 的加载顺序对同一 profile 反复重写 `weapons.primary/secondary`，结果不确定；
且 `require=` 会同时拉入三个枪械框架。

→ `incompatible=` 是**数据口径互斥声明**。
作者用 `ZZ_ProjectALifeAftermathServer.lua:9-17` 让三变体各写一份 `[ERROR]` 检测来兜底（只 `print`，不阻断）。

---

## 6. 兼容与失败处理（工程细节，值得抄）

- **105 处 `pcall`**；`active()` 三层保护（`type` 检查 → `pcall` → `contains` 再套 `pcall`，`Loader.lua:7-14`）。
- **能力探测 fail-fast**：`Aftermath/Require.lua:16-20` 的 `R.must({备选路径}, label)` 遍历 `pcall(require, path)`，
  全失败则 `error("Aftermath compatibility capability missing: ...")`；
  `CatalogBridge.lua:3-4` 用它**同时兼容 A-Life 的 `Records/` 与旧 `Data/` 两套路径**（A-Life 改过一次目录名）。
- **数据文件缺失不中断**：`Patch.read` 用 `assert`（`:23`），但调用侧全被 `pcall` 包住，
  失败只 `[ERROR] core=... failed`（`:270`）/ `[WARN] provider=... failed`（`:304`）。
- **provider 三态汇总**：`Patch.providerStatus[id] = "loaded"|"inactive"|"error"`（`:302,341,346`），
  尾部打印 `provider scan loaded=/inactive=/errors=`（`:357`）与
  `dependency model=core_federal+specialized_provider_gates`（`:359`）。
- **merge 目标缺失只跳过**：`"provider="..id.." skipped missing NPC="`（`:314,323`）。
  按声明顺序做合并模拟：**悬空 0 条**（vge 71、voe 192、fluffy 204 等全部命中 A-Life 的 780 条 shipped 目录）。
- **旧版残留自检**：`Aftermath/Diagnostics.lua:11-24` 用 `getModFileReader` 探 4 个 1.3 前的 shadow 文件路径，
  命中即 `[ERROR] LEGACY AFTERMATH INSTALL DETECTED`。
- **幂等保护**：所有猴补打 `_AftermathXxxBridge = true` / `Bridge.VERSION`
  （`ProfileBridge.lua:43,72,109,121,144,196`；MFSGunshotBridge 把版本串绑在 magazine 表上，防 `Reset Lua` 重入）。
- **降级**：`clearCoreFallbackOutfit`（`Loader.lua:242-254`）在 overlay 生效时清掉核心兜底 outfit，
  避免两套衣服叠加；`rollPercent` 三级降级 `DeathDrops.adapters` → `ZombRandBetween` → `math.random`
  （`ProfileBridge.lua:124-130`）。

---

## 7. 脆弱点清单

**【内部实现细节，最易崩】**

1. `Catalog.load(useShippedCache)` 的参数语义：依赖"先改 `Catalog.shipped`、再用 `baseLoad(true)` 重建"
   这一**非文档化流程**；A-Life 若改缓存策略或加参数，二次 reload 会失效。
2. `Catalog.shipped` / `Catalog.current` 两个裸字段名（`ALifeCatalog.lua:9-10`）。
3. `CatalogParser.parseText(text, source, kind)` 的三参签名与 `delta.records / delta.byId` 结构（`Loader.lua:266,298`）。
4. `ProfileHydrator.plan/apply`、`LoadoutProgression.apply`、`MagazineState.initialize/consumeRound`、
   `DeathDrops.plan/dropMagazines` 的私有签名与 `plan.weapons/ammo/ammoMode/drop/weaponTypes` 字段名。
5. `Weapons.select(shell,item,slot)` / `Animations.presentWeapon(shell,item,itemType,class,held)` 的栈式签名，
   以及直写 `animations.weaponVisuals[shell].class` 这种内部表（`ALifeGoMHandgunPatch/Core.lua:58-77`）。
6. `Catalog.npc(id)` 触发器（`ProfileBridge.lua:51`）。
7. **780 条 shipped NPC id 耦合**：vge/voe/fluffy/eft/bcg_tools 等全部 merge 到 A-Life 出厂 id
   （含 `k93_jefferson_police_01`）。A-Life 重命名/删除任一 id → **静默 skip、不报错**，只是装备不生效。
   **这是最隐蔽的升级破坏点。**
8. `getModFileReader(modId, path, false)` 依赖 B42 把 `common/` 并入 mod 挂载根的规则。

**【脆弱但已有保护】**

9. A-Life 未导出 API 时 `Require.must` 直接 `error` → 整个 mod 加载失败（比静默错好，但仍是硬依赖）。
10. `[J&G] Umbrella Corp Uniform` 含空格、方括号、`&`，在 `mod.info` 与 `Loader.lua:113` 双处硬编码，大小写/拼写敏感。
11. `require=` 未声明却硬依赖的 `SWMG.*` 弹药 id（`Loader.lua:147-166`，只列在 `loadModAfter=`）
    → 缺 SWMG 时会写入不存在的弹药类型，**NPC 有枪无弹**。
12. `Loader.lua` 三份物理复制、`UndeadSurvivor_Attachments.lua` 同样三份（弹匣清单 52→9→8 已人工分叉）
    → 任一热修要改三遍，漂移风险高。

---

## 8. 多版本变体扩展的推荐做法（10 条）

1. **一个工坊物品 = 一个共享数据基座 + N 个薄变体 mod**：每个变体自带 `42/mod.info`，
   数据放各自 `common/`（B42 版本根，**不要**用 `Contents/mods/`）。
2. 目录骨架：
```
<Item>/mods/<Base>_<Variant>/
  42/mod.info                                  # 只有 require=/incompatible=/loadModAfter= 不同
  42/media/lua/shared/00_<Base>Bootstrap.lua   # 4~6 个常量：modId/edition/backend/tag/version
  42/media/lua/shared/<Base>/Core.lua          # 三份逐字节相同（应由构建脚本生成）
  42/media/lua/shared/<Base>/Backends/<V>.lua  # 唯一真正不同的文件
  common/<base>/core/*.alife                   # 三份相同
  common/<base>/providers/*.alife              # 三份相同，按 kind + requires 门控
```
3. 把"数据"固定成**一种口径**，其它变体只写"角色→物品池"的翻译层，**禁止改数据文件**
   （实测三份 `common/` md5 全等，这是可维护性的关键）。
4. 条件加载骨架（直接照抄这个模式）：
```lua
local function active(id)                     -- 唯一可靠的启用探测
    if type(getActivatedMods) ~= "function" then return false end
    local ok, mods = pcall(getActivatedMods)
    if not ok or mods == nil then return false end
    local found = false
    pcall(function() found = mods:contains(id) == true end)
    return found
end
local function allActive(req)
    for _, id in ipairs(req or {}) do if not active(id) then return false end end
    return true
end
local providers = {
  -- faction_upsert 必须与其 npc_upsert 共用同一 requires（= 身份提供者）
  { id="scp_fac", requires={"SCP_Foundation_Pack"}, kind="faction_upsert", path="providers/scp_factions.alife" },
  { id="scp_npc", requires={"SCP_Foundation_Pack"}, kind="npc_upsert",     path="providers/scp_npc.alife" },
  -- 通用装备 overlay
  { id="voe",     requires={"VanillaOutfitsExpanded"}, kind="npc_merge",   path="providers/voe_npc.alife" },
}
for _, p in ipairs(providers) do
    if allActive(p.requires) then                        -- ← 身份门控就这一行
        local ok, text = pcall(readProviderFile, p.path) -- 读失败只降级，不中断
        if ok then merge(parseText(text, p.id, p.kind))
        else log("WARN provider=" .. p.id .. " error") end
    end
end
```
5. 变体差异**只允许**出现在一个 `Backend` 模块里，主 Loader 通过 `presets/finalize` 委托；
   主 Loader 的三份应由**构建脚本生成**而非手工复制。
6. 角色池必须做**确定性选择**（`stableIndex(seed, n)`），否则同一 NPC 在不同会话/客户端上枪械不一致，多人不同步。
7. 池内每一项都要过**存在性探测**（`ScriptManager.instance:getItem` + `pcall`），
   只把真实存在的物品放进池；缺框架时自动缩小池，而不是产出错误 id。
8. 每条 merge/overlay 都要有 `"skipped missing NPC="` 日志 + 结尾
   `provider scan loaded=/inactive=/errors=` 汇总，否则升级后静默失效无从发现。
9. `mod.info` 的 `require=` 必须覆盖代码里所有硬依赖（含弹药 mod）；
   `incompatible=` 要覆盖同数据口径的兄弟变体 + 各自枪械框架，并配运行时 `[ERROR]` 双检。
10. 每个猴补都打幂等标记（`_XxxBridge = true` 或版本串绑在被补的表上，防 `Reset Lua` 重入）；
    `ModData` 只写上游已识别的键，不自建命名空间。

---

## 9. 稳定性评级

### 【稳定接口】（可放心依赖）

- `getActivatedMods():contains(id)` —— 引擎 API，全包 26 处
- `getModFileReader(modId, path, false)` —— 引擎 API
- `Events.OnGameBoot` / `OnGameStart` / `OnZombieDead` —— **全包仅这 3 个事件名**（3/2/3 处）
- `ScriptManager.instance:getItem(fullType)`、`instanceItem(fullType)`、`instanceof(obj,"IsoPlayer")`
- 原版 `AttachedLocations` / `AttachedWeaponDefinitions` / `DoParam("AttachmentType = ...")`
- `require` + `pcall` 能力探测组合；ModData 的 `MagazineType`/`AmmoList`

### 【半稳定】（版本内可用，换版本需回归）

- `ProjectALife.Catalog.load` 的上游 API 契约（"官方入口"但签名/缓存策略未文档化）
- `CatalogParser.parseText(text, source, kind)` 与 `delta.records`
- `CreatorFolders.seedDefaults/serializeAll/persist`（`CreatorFolders.lua:28,48,51`）
- **A-Life 的 780 条出厂 NPC id 集合**（16 个 provider 的 merge 目标全依赖它）
- `ProjectALife/Records/...` 与 `ProjectALife/Data/...` 的双路径兼容（`Require.lua:3-5` 已为一次改名做过迁移）

### 【内部实现细节】（升级最可能崩，无公开 API 替代）

- `Catalog.shipped` / `Catalog.current` + `load(true)` 二次调用语义（`CatalogBridge.lua:17-19,55-68`）
- `ProfileHydrator.plan/apply`（含只读 `plan.weapons/ammo/ammoMode/drop/looseAmmoDrops/standardMagazines/magazineDrops/weaponTypes`）
- `LoadoutProgression.apply`
- `MagazineState.initialize/consumeRound`
- `DeathDrops.plan/dropMagazines` 与 `DeathDrops.adapters.rollPercent`
- `Weapons.select`、`Animations.presentWeapon/apply` 及 `animations.weaponVisuals[shell].class` 表结构
- `Loader.lua:63-68` 的 `remove|group|field` 反向删除语法（已实现，但 79 个 `.alife` 中**零使用**，是未验证的死代码）

---

## 10. 升级回归清单（每次 A-Life 更新后照做）

先看日志里三类计数是否与本文基线一致：

| 日志 | 基线 |
| --- | --- |
| `core catalog factions/profiles errors=` | core = **13 阵营 / 912 NPC** |
| `provider scan loaded=/inactive=/errors=` | 与当前启用模组集合一致 |
| `skipped missing NPC=` | **merge 悬空应为 0** |

再核对第 7 节的第 1~7 项（内部实现细节）。

---

## 11. 给我们自己的结论

Aftermath 证明了**纯数据扩展的完整可行性**：

- **零美术资产**、6.4 MB 全文本、41 个 Lua 文件；
- 用 `getActivatedMods():contains()` + `kind` 门控 + 猴补 `Catalog.load` 就能把 900+ NPC 的装备
  按玩家实际安装的模组集合动态合并进 A-Life；
- 一个工坊物品带三个变体，用 `incompatible=` 做**数据口径互斥**声明。

> 对照 `alife-extension-api.md`：Aftermath 用到的 `Catalog.load` / `Catalog.shipped`
> 属于【半稳定】~【内部实现】。所以**走 provider 路线的正确姿势是**：
> 先按 Aftermath 的模式做最小可用版本，**同时把"780 条 shipped NPC id 耦合"当成已知风险登记在案**，
> 并在自己的日志里复刻它的三态汇总（`loaded/inactive/errors` + `skipped missing`），
> 这样 A-Life 升级后你能第一时间发现静默失效。
