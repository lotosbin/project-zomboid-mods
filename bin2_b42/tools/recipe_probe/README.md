# recipe_probe —— 用游戏自己的解析器离线校验 B42 配方脚本

`bin2_b42` 里的 `media/scripts/**` 是 B42 的 `craftRecipe` 脚本。语法错了、物品 ID 拼错了、
`-fluid` 行被引擎静默丢掉、`mode:keep` 其实被解析成别的 —— 这些在 Lua / JSON / 正则检查里
**都看不出来**,进游戏只表现为"配方不见了"或"材料数字对不上"。

这个探针把游戏的 `ScriptManager.Load()` 跑在 headless 下,然后用引擎自己的解析结果
逐行打印每条配方(`RecipeProbe`),从而在不启动游戏、不碰 Steam 的前提下拿到权威答案。

```
cd bin2_b42/tools/recipe_probe
./run.sh                          # 默认校验 bin2_extension 42.19.0 的配方
./run.sh <recipes.txt> [<...>]    # 校验指定配方脚本
```

判据:输出末尾必须是 `ALL RECIPES PARSED`,且每行的 `keep=` / `destroy=` / `fluidMode=` /
`amount=` 与脚本里写的意图一致。`!! UNKNOWN fullType:` 只在原版物品 ID 写错时才算问题
(探针没加载别的 mod,所以别的 mod 的 ID 查不到是正常的 —— 例如 `LabItems.*` 来自 ZVirusVaccine)。

## 它到底校验了什么

`RecipeProbe.java` 打印的是 `CraftRecipe` 内部的 `ioLines`(含**流体输入行**;公开的
`getInputs()` 里没有流体行,所以这里用反射读 private 字段),因此能看清:

| 脚本里写的 | 引擎解析后打印的 |
| --- | --- |
| `item 1 [A;B] mode:keep flags[ItemCount]` | `keep=true destroy=false itemCount=true` |
| `item 1 [A;B] mode:destroy flags[InheritCondition] mappers[X]` | `destroy=true` + `OUT ... mapper:X` |
| `-fluid 0.5 categories[Water] mode:mixture` | `IN [Fluid] ... fluidMode=Mixture amount=0.5` |
| 物品 fullType | 在 `ScriptManager.getItem(fullType)` 里查得到 |

## 为什么要把文件临时复制进游戏目录

`ScriptManager.Load()` 只扫描两个来源:游戏的 `media/scripts`,以及**已启用 mod** 的
`media/scripts`(来源:`ScriptManager.Load()` → `searchFolders(ZomboidFileSystem.base.lowercaseUri,
ZomboidFileSystem.getMediaFile("scripts"), …)`,以及 `ZomboidFileSystem.getModIDs()` 里每个 mod 的
`getCommonDir()/media/scripts`)。headless 下没有"已启用 mod"这套状态,所以 `run.sh` 把待校验文件
临时复制到 `<游戏>/media/scripts/generated/recipes/zz_probe_<原名>.txt`,并在退出时(EXIT trap)
无条件删除 —— 它是**游戏安装目录里的一个临时文件**,不是配置改动:
Steam 校验文件完整性看到的多余文件也只是这个临时文件,删掉即可。

## 环境要求

- JDK ≥ 25 编译(`projectzomboid.jar` 里的 class 是 **69.0**,旧 JDK 报"错误的类文件版本")
- 用游戏自带的 JRE 运行(`Project Zomboid.app/Contents/PlugIns/jre-*/`),与游戏同一运行时
- `PZ_GAME_DIR` 可覆盖游戏目录(默认取 Steam 默认安装位置)

## headless 下必须手动补的两步初始化

`ScriptManager.Load()` 不是给命令行准备的,直接调会在两处炸;`RecipeProbe` 里已处理:

1. `RandStandard.INSTANCE.init()` —— 否则 `ServerOptions.<clinit>` 里 `randomizer` 为 null(NPE)
   (调用链:`ScriptManager.Load` → `WorldDictionary.StartScriptLoading` → `GameClient.<clinit>` → `ServerOptions.<clinit>`)
2. `zombie.core.physics.Bullet.init()` —— 否则车辆脚本 `VehicleScript.toBullet` 抛
   `UnsatisfiedLinkError: defineVehicleScript`,整个 Load 中断(配方一条都注册不上)
