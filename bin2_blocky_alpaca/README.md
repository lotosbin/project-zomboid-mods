# CD: Blocky Alpacas（方块羊驼）· CompanionDogsBlockyAlpaca

Companion Dogs 的第二个羊驼 addon：**方块（voxel）造型**的羊驼品种。
与 [`bin2_companion_alpaca`](../bin2_companion_alpaca/README.md)（写实羊驼）是同一物种的两套造型 ——
同样的数值、同样的叫声、可以互相繁殖，只是几何用长方体拼出来。

* 工坊标题：`CD: Blocky Alpacas - 方块羊驼 (Companion Dogs add-on, Build 42)`
* mod id：`CompanionDogsBlockyAlpaca`，`require=CompanionDogs,CompanionDogsAlpaca`
* 本地加载软链：`~/Zomboid/mods/CompanionDogsBlockyAlpaca`
* 待上传软链：`~/Zomboid/Workshop/bin2_blocky_alpaca`

## 4 种毛色

| 品种键 | engineBreed | 贴图 | 生成后缀（farm / petvet） |
| --- | --- | --- | --- |
| blockycream | blocky_cream | BlockyAlpaca | `\|bk` / `\|bv` |
| blockybrown | blocky_brown | BlockyAlpaca_Brown | `\|bkb` / `\|bvb` |
| blockygray | blocky_gray | BlockyAlpaca_Gray | `\|bkg` / `\|bvg` |
| blockyspot | blocky_spot | BlockyAlpaca_Spot | `\|bks` / `\|bvs` |

`blockyspot` 的花斑是每只随机的（图集里按格子随机加深），所以同一毛色的两只不会一模一样。

## 几何是怎么来的（以及为什么它没有授权问题）

`tools/blocky/make_blocky_alpaca.py`：

1. 用 base 的 Raccoon 骨架（55 骨骼），套用写实羊驼那套已验证的骨长/骨旋转调参（动画因此"演得对"）；
2. **腿链与脖子竖直化**：把四条腿与脖子摆成竖直方柱（方块造型要的就是这个），只改位移不改旋转；
3. **同步改写全部剪辑的位移通道**（关键，见下）；
4. 每个骨段生成一个长方体（正方形横截面），横截面/长度/材质类按部位给；
5. 每顶点权重 100% 给一根骨头（刚体硬绑定 = MC 那种观感）；
6. **逆蒙皮烘焙** `v_bind = (Σ w·D_b)⁻¹ · p_target`，使运行时 LBS 在静止姿态精确复现这些盒子；
7. 每盒面一个图集格子 + 4 张毛色图集（纯色 + 逐格噪声，spot 额外随机加深）。

产物：23 个盒子 → 828 顶点 / 276 三角形；静止高 0.5589 单位；55 骨骼 / 24 剪辑一个不少。

### 两个真实踩过的坑

| 症状 | 根因 | 修法 |
| --- | --- | --- |
| 静止渲染完美，一播动画（walk/eat）**方块当场散架** | 检查发现**每条剪辑对每根骨头都有位移轨道**，运行时位移会覆盖静止位移；我只改了静止位移 | 照着 base 的 `apply_bone_lengths` 的做法，**同步把增量加到该骨骼在全部剪辑里的位移通道**（本次共改写 414 条） |
| 跑步（gallop）时**蹄子飞出去** | 蹄子做成了独立盒子并绑在脚骨上，而脚骨在 gallop 里位移最大 | 取消独立蹄盒，把**腿的最下一段直接染成蹄色**（结构上不可能脱离），并给骨段之间加重叠吸收拉伸 |

第一条的普适结论（写进了 `docs/pz-cc0-mesh-retarget.md` 的姊妹篇里）：
**在这套骨架上改任何静止位移，都必须同时改剪辑通道**；只改静止位移的模型在静止视图里看不出问题。

## 复现 / 校验

```bash
PY=/Users/liubinbin/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3
cd bin2_blocky_alpaca

$PY tools/blocky/make_blocky_alpaca.py --render   # 生成 glb + 4 张图集 + 渲染验证图（tools/blocky/out/）
$PY tools/blocky/make_images.py                   # 4 张品种头像 + 图标 + 海报 + 工坊预览
./tools/check.sh                                  # 一键自检（语法/翻译/glb/图片/Lua 契约测试/工坊探针）
```

## 校验状态

* Lua 5.1 语法 3/3、翻译 EN/CN/CH 键集合一致且与 Breed.lua 交叉一致
* glb：55 骨骼 / 24 剪辑 / 828 顶点 / 276 三角形 / 静止高 0.5589 / UV 与索引连续
* 图片：工坊预览 256²、海报 512²、图标 64²、4 张品种头像 512²
* Lua 集成测试 **9/9 ALL PASS**（含"依赖缺失时安静早退"、"11 次 registerBreed"、
  "12 个剥皮键齐全"、"并进写实羊驼的品种集合"）
* 工坊探针：`readWorkshopTxt=true`、`validatePreviewImage=OK`、`visibility=private`

## 未做的事（如实）

* **没有进游戏实测**（只做了离线渲染与契约测试）；验收清单见 `docs/pz-acceptance-checklist.md` 的方块版（下一步补）
* 刚性绑定 = 没有软蒙皮形变，这是刻意的方块观感，不是缺陷
* 只提供 EN/CN/CH
* `workshop.txt` 是 `visibility=private`，公开前改 `public`（首次上传不要写 `id=`）
