# 给 Companion Dogs 写 addon：契约、实证与踩坑速查

面向"要给 [Companion Dogs [ALPHA]](https://steamcommunity.com/sharedfiles/filedetails/?id=3740052292)
（Workshop 3740052292）加新品种/新物种"的场景。所有结论都来自 **base 自己的代码**与官方手册
<https://companiondogs.pet/docs/en/modding.html>，手册与代码冲突处一律以代码为准并标注。

本机 base 版本：`modversion=0.7.4`、`CD.API_VERSION = 11`（`media/lua/shared/CompanionDogs/skills/BreedAPI.lua:4`）。
下文 `BASE` = `.../steamapps/workshop/content/108600/3740052292/mods/CompanionDogs/42`。

## 1. 一个 addon 的最小骨架

```
<ModId>/
├── mod.info                  # id=CompanionXxx（VersionStamp 只认 "Companion" 前缀）、require=CompanionDogs
└── media/
    ├── lua/shared/<ModId>_Breed.lua                      # registerSpecies + registerVoices + registerBreed
    ├── lua/shared/Definitions/animal/<X>Definitions.lua  # stages / breeds / 三个动物类型 / avatar
    ├── lua/shared/Definitions/animal/<ModId>_Parts.lua   # 剥皮表（每个 engineBreed 一次）
    ├── lua/client/<ModId>_Moodle.lua                     # CD.DogMoodles 追加
    ├── lua/shared/Translate/<LANG>/{IG_UI,Sandbox,ItemName}.json
    ├── scripts/models_<x>.txt / sounds_<x>.txt / <x>_meat.txt
    ├── models_X/Skinned/<Name>.glb
    ├── textures/Body/<texture>.png、CDPortrait_<breedKey>.png
    └── textures/<moodleIcon>_<32..128>.png
```

每个 Lua 文件顶部按"用到什么就 guard 什么"挡一层，**不要**在 addon 里写 `CompanionDogs = CompanionDogs or {}`：

```lua
local CD = CompanionDogs
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 6) then return end
```

`versionMin` 只管游戏版本，**没有**"依赖 base 的哪个版本"字段 ⇒ base 版本下限只能靠 guard + 描述文字表达。

## 2. 三个必须知道的"手册 ≠ 代码"

| 手册说法 | 代码事实 | 后果 |
| --- | --- | --- |
| `engineBreed` 缺省 = `key` | 实际回落到 `CD.BREED = "brown"`（金毛的皮）`skills/Skills.lua:240-243` | 漏写 ⇒ 所有新品种贴同一张皮，`CD.BREED_BY_ENGINE` 被争夺 |
| 钩子/handler "在各自的 pcall 里跑" | base 全目录 **没有任何 pcall**：`skills/BreedAPI.lua:12-24`、`server/systems/CompanionDogs_Hunting.lua:1033-1038`、`server/CompanionDogs_Spawn.lua:215`、`server/systems/CompanionDogs_Distract.lua:122,133` 都是裸调用 | 你的 handler 抛异常会打断整轮 upkeep / 整次 chunk 分类 ⇒ **自己包 pcall** |
| `registerSpecies` 只需 `key/nounKey/youngKey` | 还支持 `labelKey`（档案卡 Species 行）`skills/Species.lua:14,70-75` | 不写就回落 nounKey（小写） |

## 3. 手册没写、但一定会踩的

* **`registerVoices` 不登记 `CD.SOUND_LOOPED`**：循环音（吃/喝）必须自己补 `CD.SOUND_LOOPED[name] = true`，
  否则动物走出听觉范围后声道不会被停（`config/Needs.lua:26,76-92` + `client/CompanionDogs_Client.lua:850-858`）。
* **音量分类只能是 `bark` / `fx` / `ambient`**：滑条只按这三个建，`setCatMute` 对未知分类静默 return
  （`config/Needs.lua:20`、`client/CompanionDogs_Settings.lua:36-39,203-204`）。
* **`registerVoices` 必须在 `registerBreed` 之前调用**：注册时只检查 `CD.SOUND_CATEGORY` 并打日志，不阻断
  （`skills/BreedAPI.lua:125-142`）。
* **注册后再改字段要自己补缓存刷新**：`CD.clearDietCache()`（`core/Diet.lua:107-119`）、
  `CD.rebuildEngineIndex()`（`skills/Skills.lua:142-152`）、`CD.rebuildBreedOrder()`（`skills/BreedAPI.lua:26-31`）。
* **`breed` 字段不是过滤器**：它是"品种专属 moodle"的开关，玩家关掉品种 moodle 或动物生病时**连 condition 都不调用**
  （`client/CompanionDogs_Moodles.lua:538-545` + `core/Status.lua:140-142`）。
* **`puppySize` 是绝对值且每轮 `setSizeForced`**（`server/CompanionDogs/life/Mounted.lua:134-141`），
  体型比狗大的新物种必须显式给值，否则幼崽按 base 默认 0.6 被压成小狗。
* **剥皮表键带毛色**：`<typePrefix><male|female|pup><engineBreed>`（`ButcheringUtil.lua:15`），
  且 `d.parts = d.parts or parts` ⇒ 同一 key 第二次调用会被忽略（`Definitions/animal/CompanionDogs_Parts.lua:9`）。
* **`registerBuildingClass` 先到先得**（`config/SpawnRegistry.lua:10`），`registerStraySpawns` 会静默丢弃
  缺 `id`/`class`/`chance` 函数的步骤（`:24-28`）⇒ 名字打错就是"完全不生成且没有日志"。
* **存档里存三个标识，永远不能改名**：`key`（品种）、`typePrefix`（动物类型）、`suffix`（生成去重键）。
  新毛色要进老存档，正确做法是**给它新的 suffix**。
* **气候 API 对动物同样合法**：`IsoAnimal extends IsoPlayer`（`javap zombie.characters.animals.IsoAnimal` 实证），
  所以 `getClimateManager():getAirTemperatureForCharacter(animal, false)` 可以直接传动物，
  vanilla 也是这么用的（`media/lua/shared/Fishing/Bobber.lua:83`）。但 base 的 moodle 求值循环没有 pcall，
  **取温度的代码要自己包 pcall**，否则一次异常会打断整轮 moodle 求值。

## 4. 改 glTF 动画数据：共享 accessor 陷阱（本项目最贵的坑）

Companion Dogs 系模型的 glb 里，**同一个 clip 内多条 channel 会共用同一个 sampler/accessor**
（实测 idle 剪辑里 `neck` 的平移 accessor `acc=336` 被 **11 条 channel** 共用）。
若按 channel 迭代并**就地写共享 accessor**，同一个增量会被叠加 N 次：
本项目实测 `neck` 平移被打到 0.909（正确值 0.144），idle 里动物被拉成腊肠（头跑到 z=1.33）。

正确做法：给每条要改的 channel **克隆独占 accessor + sampler**，原数据不动：

```python
new_acc = G.clone_accessor_values(old_sampler["output"], modified_values)
new_sampler = dict(old_sampler); new_sampler["output"] = new_acc
anim["samplers"].append(new_sampler); ch["sampler"] = len(anim["samplers"]) - 1
```

回归检查（已实现于 `bin2_companion_alpaca/tools/alpaca/validate_glb.py`）：算出"真正带蒙皮权重的关节"，
断言它们在所有剪辑里的平移通道 `|t| <= 1.0`（模型自身尺度约 0.6）。注意模型里有个权重为 0 的数据关节
`Translation_Data`，它本来就能到 3.08，必须排除，否则误报。

其它 glb 硬性条件（手册第 2 节）：骨骼 ≤ 60；顶层节点 identity；必须带满 21 个必需 `Rac_*` 剪辑
（缺一个，动物第一次被要求播它就冻住）；`animset` 必须保持 `"raccoon"`（fork 的名字不加载状态机）；
内嵌图是 1x1 占位图，游戏按 `AnimalDefinitions.breeds[...].breeds[engineBreed].texture` 取
`media/textures/Body/<texture>.png`。

### 4.1 换模型（把外部网格搬进来）另有两个必踩的坑

如果需要**换掉整个几何来源**（例如从 CC0 资产搬一只真羊驼进来），见
`docs/pz-cc0-mesh-retarget.md`。两条与本项目直接相关的结论：

* **混合仿射算位置 + 引擎再混合权重不是互逆运算** —— 必须做**逆蒙皮烘焙**
  `v_bind = (Σ w·D_b)⁻¹ · p_target`，否则网格会碎成"一地瓷片"；
* **权重平滑会跨肢体扩散** —— 3 轮网格邻接平滑会把腿/尾巴的权重糊到躯干上，
  动画里直接撕开；宁可保留来源模型作者的权重。

## 5. 没有游戏时怎么验证

1. **离线蒙皮渲染器**：`bin2_companion_alpaca/tools/alpaca/render_glb.py`（numpy + Pillow，自建 LBS +
   z-buffer + 贴图采样）。验收标准是先渲染**未修改的源模型**（要能认出是那只金毛），再渲染产物；
   单张 900×700 约 0.6~3.6 秒。
2. **几何指标代替肉眼**：把"脖子多立、口鼻多平"定义成两个角度（骨骼自身方向仰角 / 关节到关节方向仰角），
   写网格扫描求解（`tools/alpaca/tune_pose.py`）。
3. **静态校验器**：glb 结构（骨骼/剪辑/accessor 越界/min-max/蒙皮/平移爆值）、翻译（重复键/BOM/裸 %/键集合）、
   图片尺寸、声音参数，一键 `tools/check.sh`。
4. **用游戏自己的解析器验发布物**：`bin2_workshop_upload_fix/tools/pz_workshop_probe/run.sh "" <staging 目录>`
   会调 `SteamWorkshopItem.readWorkshopTxt` / `validatePreviewImage`，并逐个调 native setter（不上传）。

## 6. 授权与署名

base 的 `mod.info` 里写明：允许为 Companion Dogs 做 addon 与新犬种、并**在其 addon 中使用它的美术**，
只需注明出处；除此之外不得抽取/重新打包/分发到无关项目。若 addon 的模型/贴图是派生物，
必须在 `CREDITS.txt` 写清"派生自哪个文件、用什么脚本、改了哪些量、没改哪些量"，并在
`mod.info` 与工坊描述里点明依赖与版本下限。

## 7. 参考实现

* 新物种范例：`CompanionCat`（Workshop 3791294616）——本项目的结构模板。
* 新品种最小范例：`CompanionDogsPug`（Workshop 3787202559）——最小 `registerBreed` + moodle + 服务端钩子。
* 本项目产物：`bin2_companion_alpaca/`（模组 id `CompanionDogsAlpaca`，7 毛色，EN/CN/CH）。
