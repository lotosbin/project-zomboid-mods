# recipe_gap —— 扫描原版配方体系缺了什么

`recipe_probe` 回答"我写的这条配方引擎怎么理解",这个脚本回答另一个问题:
**原版有那么多配方,哪些物品是"配方在消耗、却没人能造出来"的?**
本次 `bin2_extension` 新增的 5 条配方(螺母螺栓 / 螺丝 / 圆锯片 / 手锯条 / 胶水)就是它找出来的,
结论与完整数据见 `docs/craft-recipe-study.md` 第 14 节。

```
python3 scan_recipe_gaps.py                    # 打印报告(默认取前 50)
python3 scan_recipe_gaps.py --top 80
python3 scan_recipe_gaps.py --json gaps.json   # 全量数据,便于二次查询
python3 scan_recipe_gaps.py --lang CN          # 中文名(默认 CN,可换 ItemName_<lang>.json)
python3 scan_recipe_gaps.py --game /path/to/Project\ Zomboid.app/Contents/Java
```

不启动游戏、不读存档、不需要 JDK —— 纯读 `<游戏>/media/scripts` 与 `media/lua/shared/**` 的文本。

## 判据

| 概念 | 定义 |
| --- | --- |
| **消耗** | 某条 `craftRecipe` 的 `inputs` 里出现,且**不是**工具位(`mode:keep` / `flags[Prop1\|Prop2\|ToolLeft\|ToolRight]`) |
| **产出** | `outputs` 直接产出;`itemMapper` 的**键**(mapper 语义是 `产出 = 触发它的输入`,见 `generated/entities/blacksmith/craftRecipes/recipes_blacksmith_bar.txt`);`evolvedrecipe` 的 `ResultItem` 与 `值 = 键` 行 |
| **世界来源** | 拆家具 `ISMoveableDefinitions.lua` 的 `addScrapItem`,采集表 `Foraging/**/*.lua` |
| **替代品** | 同一条 input 的兄弟物品(`[A;B;C]` 里 A 进不了货但 C 能造),或**小标签**等价族(`tags[base:thread]` 这种成员 ≤ 12 个的标签,成员之间可互换;`base:hasmetal` 上千成员,不算替代关系) |

`tags[...]` 输入会展开成标签的全部成员:写 `tags[base:charcoal]` 就等于把 `Base.Charcoal`、
`Base.CharcoalCrafted`、`Base.Coke` 都算作"被消耗",避免了"按标签选料"被整片漏掉。

## 输出的四类

| 分类 | 含义 | 要不要补配方 |
| --- | --- | --- |
| 真缺口(只能搜刮) | 被消耗、无产出、无世界来源、无替代品 | **要**(本次就是这一类) |
| 有世界来源的材料 | 无产出路径,但拆家具/采集能拿 | 看设计,通常不补 |
| 有替代品的材料 | 无产出路径,但同族有可造替代品 | 不补 |
| 做得出没人用 | 有产出、无消耗(成品为主) | 不补,**不是**缺口 |

"完全没配方的物品"(衣服、书、罐头……)不在报告里 —— 它们本来就不该有配方,那不是缺口。
Build 42.21 的完整数字(5079 物品 / 969 craftRecipe / 379 真缺口)见第 14.1 节。

## 坑

- **`item` 的数量可能是小数**:原版有 3 行写成 `item 1.0` / `item 2.0` / `item 5.0`
  (`recipes_jarring.txt:49-50` 的 `MakeJar` 就在其中)。数量正则必须写 `\d+(?:\.\d+)?`,
  写成 `\d+` 会**整行漏掉**、静默少算(`Base.Salt` 由 7 条变成 6 条就是这个 bug)。
- **方括号有三种,先摘掉 `tags/flags/mappers` 再找物品列表**:`item 1 tags[base:glass] flags[ItemCount]`
  若直接取"第一个方括号",会解析出"物品 = ItemCount"(假阳性);更糟的是
  `item 1 Base.HandScytheBlade flags[IsBlunt]` 会解析出"物品 = IsBlunt"而**漏掉真物品**(假阴性)。
  `[*]` 是任意物品通配,也要排除。
- **`mode:keep` 不是"不消耗"的同义词**:工具位(`Prop1/Prop2/ToolLeft/ToolRight`)也在 keep 里,
  所以脚本把两者都归到"工具使用",否则锤子、凿子会被算成"被消耗的材料",报告里全是工具。
- **`default =` 在 itemMapper 里是兜底产出**,不是消耗源,键值语义反了会得出完全错误的结论。
- **CN 名取法**:原版 `ItemName.json` 的键是裸 fullType(`Base.NutsBolts`);
  mod 的翻译才带 `ItemName_` 前缀,两种都试。
- 报告只解决"缺不缺",**不解决"该不该补"**:补配方前必须逐条检查能不能形成材料泵
  (能不能回炉、回炉产出与配方消耗谁多),做法见第 14.4 节。
- **顺手 grep 复核会假阳性,物品 ID 必须精确匹配**。脚本本身按物品 ID 建索引比较,不受影响;
  会踩的是人工抽查:比如 `grep Base.CircularSawblade` 会连 `Base.CircularSawblade_Half` 一起命中
  (`CutCircularSawblade` / `SawCircularSawblade` 正好是消耗整片、产出半片),于是把真缺口判成"有产出"。
  要 grep 就用 `ID(?=[\s,;\]\n]|$)` 这种边界断言,别用子串包含。详见第 14.9 节。
- **`mapper:<名字>` 里的名字不是产出物**——它是作者起的标签,和产出什么物品无关。实例(2026-10-13,耙头):
  `generated/recipes/recipes_improvised_weapons.txt:497` 的 `itemMapper RakeHeadMapper` 键是
  `Base.BaseballBat_RakeHead = Base.BaseballBat`、`Base.LongHandle_RakeHead = Base.LongHandle`、
  `Base.ShortBat_RakeHead = Base.ShortBat`、`default = Base.BaseballBat_RakeHead`
  —— **产出的是棒球棍 / 长手柄**。同一处还有第二个陷阱:mapper 的**键是派生变体 ID**
  (`Base.BaseballBat_RakeHead` 这种,原版另有 `Base.BaseballBat`),grep 物品名会连它一起命中。
  脚本不受影响:`produced` 的 1622 个键里**没有任何一个含 `Mapper`**,`Base.RakeHead` 只有
  `DismantleLongImplement`;会踩的只有人工 grep。
- **"有多少条"必须连数法一起写**。同一个文件 `recipes_blacksmith_heads.txt`,三个数都对、答的是三个问题:
  `craftRecipe` 总数 **19**、名字含 `head` **15**(工具头)、大小写不敏感 `^forge_.*_head$` **14**、
  大小写敏感 `^Forge_.*_Head$` **13** —— 差在 `forge_garden_fork_head` 全小写、`ForgeMaceHead` 没下划线。
  报"15 条 `Forge_*_Head`"这类话时**模式和大小写都要写出来**,否则下一个人复算不出来(2026-10-13 就这么
  让一个没跑过的数字进了账本)。
