# CD: Alpacas（羊驼）—— Companion Dogs 的扩展 addon

给 [Companion Dogs [ALPHA]](https://steamcommunity.com/sharedfiles/filedetails/?id=3740052292)（Workshop **3740052292**）
增加一个**新物种**：羊驼。走该模组官方的 addon 契约（`registerSpecies` / `registerBreed` / `AnimalDefinitions`
三件套 / `defineCompanionParts` / `CD.DogMoodles` / `CD.onUpkeepStress`），不修改 base 的任何一行。

* 工坊物品目录：`bin2_companion_alpaca/`（`workshop.txt` + `preview.png` + `Contents/`）
* 模组本体：`Contents/mods/CompanionDogsAlpaca/42/`
* 模组 id：`CompanionDogsAlpaca`（`require=CompanionDogs`，即 API 11 / base 0.7.4+）

**姊妹 addon**：[`bin2_blocky_alpaca`](../bin2_blocky_alpaca/README.md)（CD: Blocky Alpacas）——同样的物种与数值，几何是用脚本拼的方块（voxel）造型；它依赖本 addon 提供物种与叫声。

## 它是什么

| 维度 | 羊驼的设计 |
| --- | --- |
| 定位 | **驮兽**：`bagMult 2.2`，`baseEncumbrance 45~55`（狗是 20） |
| 哨兵 | `sentinelMult 1.5`、`barkNoiseMult 1.2`：发现得早，但报警声很大（会招僵尸） |
| 放牧 | `herding xpMult 2.0`，这是它的本职工作 |
| 战斗 | 能踹倒僵尸（`canKnockdown`）但打不死（`canKill=false`），受惊阈值 0.60 偏低 |
| 狩猎 | `skills.hunt = false`：不追猎物、不给觅食加成 |
| 饮食 | 草食，`diet.replace = true`：干草/青草/蔬菜/水果/豆类；肉类不算蛋白；狗的有毒名单照抄 |
| 气候 | `>24℃` 热应激、`<4℃` 才舒服；服务端 `onUpkeepStress` 钩子（自己包 `pcall`，因为 base 的钩子调用不带保护） |
| moodle | 「羊毛暖意」：同伴在身边且不生病、不受热时缓解玩家的无聊/悲伤/压力 |
| 毛色 | 7 种：奶油白 / 浅驼 / 棕 / 黑 / 灰 / 玫瑰灰 / 苏利白（同一躯干，7 组 `engineBreed` + 7 组生成后缀） |
| 生成 | `farm`（主）与 `petvet`（罕见），后缀 `|ap*` / `|av*`；沙盒选项 `CompanionAlpaca.AlpacaSpawnMultiplier` 独立于狗的倍率 |
| 繁殖 | 只与羊驼（`species = "alpaca"`），一胎一崽 |

## 模型是怎么来的

仓库和游戏里都没有羊驼模型，所以羊驼的几何来自 **[Quaternius 的 CC0 "Alpaca"](https://poly.pizza/m/bCVFD48i2l)**
（Public Domain / CC0 1.0，原件存于 `tools/alpaca/vendor/alpaca_cc0.glb`，含 sha256），
再用 `tools/alpaca/build_alpaca_from_cc0.py` **逐骨骼仿射传递**到 base 的 Raccoon 骨架上：

```
1. 合并 CC0 模型的 7 个材质 primitive（它没有 UV、没有贴图，只有纯色材质）
2. 把它的 46 骨骼四足骨架按显式表映射到 base 的 55 骨骼（CC0_TO_OUR）
3. 用 Umeyama 求一个全局相似变换，把它 Idle 姿态的骨架摆到 base 骨架的静止姿态上
   （FBX 转出来的动画世界坐标是绑定的 ~100 倍，不做这步尺度会差 10 倍）
4. 逐骨骼仿射传递 T_b = D_b⁻¹ · G · S_b，按原蒙皮权重混合出"目标形状" p_target
5. **逆蒙皮烘焙**：解 v_bind = (Σ w·D_b)⁻¹ · p_target
6. 每三角形拆独立 UV 岛 + 按材质分类画 7 张毛色图集
```

第 5 步是关键的坑：直接写"混合仿射算出来的位置"、却让引擎用另一组混合权重做 LBS，
二者不是互逆运算，网格会被撕成一地碎三角片（渲染出来像碎瓷片）。逆蒙皮烘焙保证
**静止时 LBS 结果 == 目标形状**，动画时按骨骼相对运动形变。

结果：55 骨骼（引擎上限 60）、24 个 `Rac_*` 剪辑一个不少、animset 仍是 `raccoon`、
网格 2060 三角形 / 6180 顶点（每三角形独立 UV）、静止高度 0.4523 单位（≈ 成年肩高 0.9 m）。
CC0 模型自带的骨架与 26 个动画**没有**被使用。

## 资产与工具
## 资产与工具

| 文件 | 作用 |
| --- | --- |
| `tools/alpaca/render_glb.py` | 离线 glb 蒙皮渲染器（numpy + Pillow），用于在没有游戏时目视验证模型 |
| `tools/alpaca/glb_util.py` | 最小 GLB 读写（accessor/bufferView/独占克隆/重打包） |
| `tools/alpaca/build_alpaca_from_cc0.py` | **当前主流程**：CC0 网格 → base 骨架的仿射传递 + 逆蒙皮烘焙 + UV/图集 |
| `tools/alpaca/derive_alpaca.py` | 只用于**骨架比例调参**（`BONE_LEN`/`BONE_ROT`，被上面那个脚本 import）；它的网格形变部分已被 CC0 传递取代 |
| `tools/alpaca/vendor/` | 第三方 CC0 原件 + 出处/授权/sha256（见 `vendor/README.md`） |
| `tools/alpaca/tune_pose.py` | 姿态求解：网格扫描 neck/head 增量，命中"脖子 74°、口鼻 -5°"的目标 |
| `tools/alpaca/make_images.py` | 头像 / moodle 图标 / 偶蹄图标 / 模组图标 / 海报 / 工坊预览 |
| `tools/alpaca/make_sounds.py` | 9 条羊驼叫声（numpy 合成 → ffmpeg 转 ogg） |
| `tools/alpaca/validate_glb.py` | glb 结构校验（骨骼数/剪辑/越界/min-max/蒙皮/平移爆值） |
| `tools/alpaca/check_translations.py` | 翻译校验（重复键/BOM/裸 %/键集合一致/自有键齐全） |
| `tools/check.sh` | 一键全跑；有 staging 时还会调用游戏自己的 `readWorkshopTxt` 探针 |

重生成全部资产：

```bash
PY=/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3
cd tools/alpaca
$PY build_alpaca_from_cc0.py  # Alpaca_Body.glb + 7 张毛色图集（主流程）
$PY make_sounds.py            # 叫声
$PY make_images.py            # 头像/图标/海报/预览（会调用 render_glb.py）
cd .. && ./check.sh            # 全部校验
```

## 本机验证状态（发布前）

`tools/check.sh` 全绿：

* Lua 5.1 语法（luaparse）：5/5 文件通过
* 翻译：EN/CN/CH 各 53 + 3 + 1 键，键集合一致，无重复键/BOM/裸 `%`
* 声音范围一致性：9 条声音的 `distanceMax` 与 `registerVoices` 的可听范围逐条相同，两条循环音都在 `CD.SOUND_LOOPED` 里
* glb：55 骨骼、24 剪辑、2060 三角形 / 6180 顶点（每三角形独立 UV）、静止高 0.4523 单位、
  accessor 无越界、POSITION min/max 与数据一致、有 `TEXCOORD_0`、索引为 `0..N-1` 连续、
  带权骨骼的平移通道最大 0.228（阈值 1.0）
* 图片：30/30（工坊预览 256×256 PNG，符合 `validatePreviewImage`）
* 声音：9/9（44.1 kHz / 2 声道 / 时长正确）
* 渲染目视：静止 + idle/walk/run/eat/attack 五个剪辑都不变形、不冻结、脚踩地（eat 是低头吃草）
* 工坊物品：**游戏自己的** `readWorkshopTxt` / `validatePreviewImage` 探针通过
  （`readWorkshopTxt=true`、`tags=[Build 42, Animals, Misc]`、`contentFolder exists=true`、`validatePreviewImage=OK`）
* Lua 集成测试（`tools/test/run_lua_test.sh`，fengari 上跑真 Lua + mock base API）：**11/11 断言通过**
  —— 覆盖"base 缺失时静默早退""registerVoices 早于 registerBreed""循环音登记""7 个品种的字段契约"
  "生成后缀不与 base 冲突""两份毛色表一致""剥皮按毛色 7 次""moodle condition 的四种分支"
  "气候钩子在无气候管理器/取温度抛异常时仍不抛"；并做过 5 次"故意变红"实验证明断言有效

## 未做 / 已知限制

* **没有在游戏里实测**（本机没有跑游戏内验证；静态验证与离线渲染全绿，但它不等于进游戏就 100% 正确）。
  下面的验收清单就是留给这一步的。模型本身来自 CC0 资产（见 `CREDITS.txt`），
  骨架/剪辑仍是 base 的，动画**没有**重定向，所以理论上不存在"动作错位"这一类风险。
* `bandSkin`（绷带/断裂贴图四变体）没做：受伤仍会流血、可治疗、可缠绷带，只是不显示绷带纹理。
* 鞍袋与帽子挂点（`models_alpaca.txt` 的 attachment offset/scale）是按躯干比例推算的，需要在游戏里目视微调。
* 声音是合成音，没有做听感验证。
* 只提供 EN / CN / CH 三语；其它语言在游戏里回落英文。
* 工坊 `workshop.txt` 暂时 `visibility=private`，正式公开前改成 `public`。

## 进游戏后的验收清单（本清单是"待做"，不是"已做"）

**先用游戏自带的工具看模型与挂点**（详见 [`docs/pz-dev-tooling.md`](../docs/pz-dev-tooling.md)）：
Steam 启动选项加 `-debug` → 游戏内**右键装备物品 → Debug Menu → `Dev` 标签页**：

* **Animation Viewer**：`Animal Model` 下拉里选我们的羊驼（数据来自 `getAllAnimalsDefinitions()`，
  按动物定义的 `bodyModel` 载入），即可逐条播 24 个 `Rac_*` 剪辑、逐帧/旋转/看关键帧/听声音；
* **Attachment Editor**：直接调 `media/scripts/models_alpaca.txt` 里帽子与驮袋的 `offset/rotate/scale`；
* 也可在调试控制台直接调用 `showAnimationViewer()` / `showAttachmentEditor()`。

已就位的 staging 软链：`~/Zomboid/mods/CompanionDogsAlpaca`（本地加载）、
`~/Zomboid/Workshop/bin2_companion_alpaca`（上传向导可见）。在游戏 Mods 列表里启用后按顺序看：

1. **先看日志**：`~/Zomboid/console.txt` 里不应出现 `registerBreed: ... recusada` /
   `registerSpecies: ... recusado` / `aviso de consistencia`。出现任何一条都说明注册被拒，
   症状是"看起来装上了但什么都不生成"。
2. **生成**：新开一局，用 debug 的动物生成菜单（组名会显示为"羊驼"）刷一只，或在农场建筑附近找流浪羊驼。
   确认 7 种毛色都能出、模型不是黑糊、不是冻结。
3. **移动**：跟随、待命、上楼梯各看一眼；重点确认**动画没有冻结**（脖子与四肢在动）。
4. **驮袋**：装上鞍袋，确认容量明显大于狗（`bagMult 2.2`，上限 100 点），且袋子贴在背上而不是悬空/穿模。
   位置不对就改 `media/scripts/models_alpaca.txt` 里 `saddlebags_*` 的 `offset/scale` 后重启游戏。
5. **放牧**：对着牲畜圈下令，确认它去赶牲畜且 herding 经验在涨（`xpMult 2.0`）。
6. **战斗**：让它打僵尸，确认**能踹倒但打不死**（`canKill=false`），且受惊后撤退（`panicThreshold 0.60`）。
7. **饮食**：喂干草/蔬菜/水果 → 正常；喂肉 → 不认（`diet.replace`）；喂巧克力/洋葱 → 中毒。
8. **气候**：夏天确认有热应激（SERVER TUNING 面板里能读到 `CD.ALPACA_*` 常量），冬天应比狗舒服。
9. **moodle**：同伴羊驼健康、吃饱喝足且不热时，"羊毛暖意"应出现在**模组自己的** moodle 列里
   （不在原版 moodle 里）；缩放界面时六个尺寸都要清晰（没有空方块）。
10. **繁殖**：两只羊驼同圈，确认能怀孕且一胎一崽（`litter {1,1}`），且**不会和狗杂交**（物种隔离）。
11. **剥皮**：杀死一只并剥皮，确认不崩且得到"羊驼肉"（`Base.CompanionDogsAlpacaMeat`）。
12. **联机**：服务器用需要客户端与服务端都装；确认叫声、位置、状态同步正常
    （本模组没有任何客户端写 ModData 的代码，气候应激走服务端钩子）。
13. **多语**：切到简中/繁中各看一遍动物卡片与提示文案，确认没有裸露的 key。
