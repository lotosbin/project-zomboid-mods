# modinfo_probe —— 用游戏自己的解析器校验 mod.info 与**版本门禁**

`mod.info` 是 `key=value` 纯文本，语法检查看不出对错；真正会出事的是 **`versionMin`**：
它由引擎的 `ChooseGameInfo$Mod.isAvailableSelf()` 判定，写高了玩家那边整条模组变不可用
（不是某个配方消失）。

```
ChooseGameInfo$Mod.isAvailableSelf():
    versionMin != null && versionMin.isGreaterThan(游戏版本) → false   // 模组不可用
    versionMax != null && versionMax.isLessThan(游戏版本)    → false
```

比较用的是 `GameVersion.getInt()` = `major * 1000 + minor`（`42.21.0` → 42021）。

## 用法

```
cd bin2_b42/tools/modinfo_probe
./run.sh                                   # 校验 Contents/mods/ 下所有模组目录
./run.sh "<模组目录>" [<模组目录> ...]
./run.sh --game=42.20.0 "<模组目录>"        # 假装客户端是 42.20.0（旧版本行为）
```

输出每项的 `versionDir`（引擎实际会加载哪个版本子目录）、`modversion`、`versionMin` /
`versionMax`、当前游戏版本下的 `availableSelf`，以及**降一个小版本模拟旧客户端**的结果。

判据：`ALL MOD.INFO OK`，且每个模组的 `模拟旧客户端 → availableSelf=false`。

`--game=` 必须在读 mod.info **之前**生效，因为"挑哪个版本子目录"就是那时定下来的；
所以它由探针在解析参数阶段先改写游戏版本，再逐个读目录 —— 用来回答
"42.20 的客户端会加载哪个子目录、门禁放不放行"这类问题（实测 `bin2_extension`：42.21 → 加载
`42.19.0/` 且可用；42.19/42.20 → 加载 `42.19.0/` 但**不可用**；42.18 → 回落到 EOL 的
`42.15.0/`，可用）。

## 两个容易踩的点

- **入口用 `ChooseGameInfo.readModInfo(目录)`，不是 `getModDetails(模组 id)`**：前者直接读你给的
  目录，校验的是**仓库里的这一份**；后者走模组目录扫描，会命中 Steam 工坊已发布的那一份
  （两者版本可能不同，例如仓库 1.6.2 / 工坊 1.6.1），拿它验证改动会得出错误结论。
  注意 headless 下 `readModInfo(模组 id)` 返回 null，必须给目录路径。
- **版本子目录名不必等于 `versionMin`**：`ZomboidFileSystem.getModVersionDirName` 只接受
  `≥ 游戏自身 minRequiredVersion`（`ChooseGameInfo` 静态初始化里写死 `42.0.0`）`且 ≤ 当前游戏版本`
  的目录名，并取其中最大者。所以 42.21 的客户端会加载名为 `42.19.0/` 的目录 —— 目录名只影响
  "哪个子目录被选中"，`versionMin` 才决定"这个模组在这台客户端上是否可用"。

## 环境要求

- JDK ≥ 25 编译（`projectzomboid.jar` 的 class 是 69.0），用游戏自带 JRE 运行
- `PZ_GAME_DIR` 可覆盖游戏目录

## 降版模拟怎么做的

`Core.gameVersion` 是 `private static final`，`Field.set` 会抛 `IllegalAccessException`，
所以探针用反射拿 `sun.misc.Unsafe` 的 `staticFieldBase/staticFieldOffset/putObject` 改写这个静态
字段，读完立刻还原（脚本进程结束即退出，不影响游戏本体）。这一步是必要的：
"当前版本能加载"是单向证据，只有旧版本上确实关掉，才证明门禁生效。
