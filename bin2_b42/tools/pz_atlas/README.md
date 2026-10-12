# pz_atlas —— 从游戏贴图包里导出物品图标

写更新公告、小红书笔记、工坊描述时,常要画"这条配方消耗什么、产出什么"。**B42 的物品图标没有
独立 png 文件**,它们打包在 `<游戏>/media/texturepacks/UI.pack` 与 `UI2.pack` 里(PZPK 格式:
一张雪碧图 + 一张名称索引表,索引表紧挨在它所属的那张雪碧图前面)。这个脚本按物品脚本里的
`Icon = X` 定位 sprite `Item_X`,裁出来并合成成标准 32x32 画布。

```
# 导出某几条配方里出现的全部物品图标(推荐:自动展开 tags[...] 与 [A;B] 多选)
python3 extract_item_icons.py --recipes <recipes.txt> --out <目录> --sheet <目录>/图标总览.png

# 按物品 fullType 导出
python3 extract_item_icons.py --items Base.NutsBolts,Base.Glue --out <目录>

# 直接按 sprite 名导出
python3 extract_item_icons.py --icons Item_NutsBolts,Item_Sawblade --out <目录>
```

输出:`<out>/<sprite>.png`(32x32 原生)、`<out>/<sprite>@4x.png`(最近邻放大 4 倍)、
`<out>/manifest.json`(sprite → 尺寸 / 所在包 / 裁剪矩形 / 对应 fullType 与中文名)、
可选 `--sheet`(带中文名的总览图,便于一眼挑图)。

## 环境

- 依赖 **Pillow**(合成透明画布与放大)。本机可直接用 DSH 自带的解释器:
  `~/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3`
- 默认读 macOS 的 Steam 安装位置,可用 `--game` 或环境变量 `PZ_GAME_DIR` 覆盖
- 只读游戏文件,不写游戏目录(探针那套"临时复制进游戏目录"的做法这里不需要)

## 已知限制

- 物品脚本里**没有 `Icon` 字段**的物品导不出来(原版 `Base.Hammer`、`Base.BallPeenHammer` 就是,
  它们只有锻造版 `Base.HammerForged`/`Base.BallPeenHammerForged` 才有图标);
  别的 mod 的物品也一样(例:`LabItems.*` 不在原版脚本里)
- 中文名取自 `media/lua/shared/Translate/CN/ItemName.json`,该文件没有的键会留空
- 这是**图标**,不是游戏截图:要"配方界面实拍"仍然得有人在游戏里按截图键(本工具替代不了)

## 格式细节

见 `docs/craft-recipe-study.md` 第 14.8 节(含实测出来的记录布局与三个坑)。
