# bin2_flier_stash —— 传单寻宝

> **状态：已搁置，不进任何上传内容。** @human 2026-10-14 19:41 原话「不做单机的模组」⇒ 本模组停止推进
> （账本「更有用的传单及海报」那格按"范围/优先级决定"记 `已拒绝`）。代码**留在仓库根**、不进
> `bin2_b42/Contents/mods/`、不随 `bin2_extension` 所在的工坊条目上传 —— 目录放这里只是留档，
> 若日后要做"联机可用"的版本，这份是现成底座；**它现在不发布、也不在任何服务器上**。

读完传单/海报点亮地图某处之后，那片区域里会"藏"下一小群**携带稀有战利品**的丧尸：给"按地图跑过去看看"一个理由。
（社区建议来源：小红书「更有用的传单及海报」；形状是"借原版已有的点亮功能，再往前一步"。）

## 玩家视角的流程

1. 读到一张能点亮地图的传单/海报 → 点窗口底部的"点亮地图"按钮（或在设置里开了"自动点亮"时自动点亮）。
2. 屏幕提示"这张传单标出了一处地点"；该地点被登记为"还没开过"。
3. 走到那片区域（半径 15 格内）→ 身边 6 格以外刷出一小群丧尸，其中 **3 只**各带 1~2 件稀有战利品。
4. 同一个地点**每个存档只开一次**（`ModData` 里记 `done`）。

## 实现（为什么不会跟上游打架）

- **点亮坐标不猜**：直接读原版表 `PrintMediaDefinitions.MiscDetails`（`media/lua/shared/PrintMedia/PrintMediaDefinitions.lua`，135 条 `mediaID → location1..5` 矩形）。
- **只包一层，不替换原版文件**：
  - `ISReadABook:revealPrintMediaLocationsOnMap`（设置里开了"自动点亮"时走这条）
  - `PZAPI.UI.PrintMedia.init`（传单窗口底部按钮那条）——包完之后给每个 `revealOnMapN` 按钮的 `onLeftClick` 追加一个回调
  - 两处都是"原函数先跑、我们再挂"，结构变了就静默不挂钩并打印一行，模组变成空转，不会报错刷屏。
- **刷怪**：`addZombiesInOutfitArea(x1,y1,x2,y2,z,count,outfit,femaleChance)`（javap 确认返回 `ArrayList<IsoZombie>`，所以拿得到僵尸对象、能往背包里塞战利品）。刷在玩家四象限的 6~16 格环带里，避免贴脸刷；**在玩家身边刷**是为了保证所在区块已加载。
- **不新增任何物品/图标**：战利品全是原版物品，ID 逐个核过存在（见 `media/lua/shared/Bin2FlierStash/Bin2FlierStash_Config.lua` 的 `LOOT_TABLE`）。

## 文件

```
42.21/
├── mod.info
├── Changelog.txt
├── poster.png                       (沿用本仓库既有海报)
└── media/lua/
    ├── shared/Bin2FlierStash/Bin2FlierStash_Config.lua   参数 + 战利品表 + 表读取工具
    ├── shared/Bin2FlierStash/Bin2FlierStash_Core.lua     状态(ModData) + 刷怪 + 到达判定
    ├── client/Bin2FlierStash/Bin2FlierStash_Client.lua   两个挂钩 + 单机到达轮询 + 联机上报
    ├── server/Bin2FlierStash/Bin2FlierStash_Server.lua   联机上报处理 + 服务端到达轮询
    └── shared/Translate/CN/UI.json                       本模组自己的两条提示文案
```

## 离线校验

```bash
# 一次性自检：战利品物品 ID 是否都存在于游戏物品定义 + getText 的键是否都在本模组 UI.json + Lua 语法
python3 bin2_flier_stash/tools/check_mod_assets.py

# 只查语法（游戏自带的 Lua 编译器，不启动游戏）
scripts/lua_syntax_check.sh bin2_flier_stash
```

`check_mod_assets.py` 的两档自测（2026-10-14 实测）：正常状态 **17/17 战利品 ID 全过**（会打印每个 ID 的定义文件）、
故意把一个 ID 改成 `Base.NailsXXX` 时**精确报出那一条并 exit 1**；随后已还原。

## 已知边界（别当成已验证）

- **联机（dedicated）未实测**：刷怪用的 `addZombiesInOutfitArea` 在原版里只出现在 `client/DebugUIs`（7 处）与 `client/Tutorial`（1 处），**服务端从没用过**。服务端路径已经写好（客户端上报 → 服务端校验并刷怪），但"服务端能不能用这个函数、刷出来的僵尸会不会同步给客户端"必须实机验证。失败的写法是"只打日志、不刷、不报错"。
- **上报未做防刷校验**：现在只校验"mediaID 在原版表里 + 该地点没开过 + 每玩家 2 秒限流"。要防"凭空点亮任意地点"，需要先确认传单物品的 `printMedia` 是否同步到服务端，再补"必须持有该传单"的检查（代码里留了 TODO）。
- **只覆盖 z=0 那一层**：原版点亮矩形是二维的（`x1,y1,x2,y2`），刷怪用玩家当前 z，楼上楼下不区分。

## 落点说明（给仓库维护者）

本模组目前在仓库根目录 `bin2_flier_stash/`（**脚本开发暂存位**），目的是**不碰 `bin2_b42` 这个工坊条目的上传内容** —— `bin2_b42` 里那份 1.7.2 已经逐项校验过、就等上传，别在我开发期间被带进上传。
验证通过后再 `git mv` 到 `bin2_b42/Contents/mods/bin2_flier_stash/`，跟 `bin2_extension`、`bin2_base`、`bin2_modpack`、`Project Cook Controller Support` 一起由同一个工坊条目分发（**不需要开新工坊条目**）。
