# 原版左侧竖排图标栏（ISEquippedItem）加一个 NPC 入口 —— 证据优先调研报告

> 目的：为 `bin2_npc_extension` 的新口味 `Bin2NPCExtensionVanilla`（纯原版）找出「在屏幕左侧的原版侧边栏里加一个自己的图标按钮，点击打开招募界面」的全部接入点、硬性规格与冲突面。
>
> **只读分析**：本报告没有修改 `bin2_npc_extension` 下的任何模组源码，也没有修改游戏安装目录下的任何文件。
> 报告写作期间，**另一个并行任务**在同一仓库里新搭了 `Bin2NPCExtensionVanilla` 的脚手架（`Profile.lua`、翻译、10 张侧边栏贴图）。本报告**只读取**了那些文件用于对齐（§3.1 末、§8.2 末），未做任何写入。
>
> **版本前提**：`~/Zomboid/console.txt:68` → `version=42.21.0 4a0e9546ec demo=false`。
> 本机安装里 `ISEquippedItem.lua` **只有一份**（`find . -name ISEquippedItem.lua` 唯一命中），不存在 B41/B42 双版本歧义。
>
> **路径约定**
>
> | 记号 | 实际路径 |
> |---|---|
> | `$GAME` | `/Users/liubinbin/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java` |
> | `$PZ` | `$GAME/media/lua/` |
> | `$UI` | `$GAME/media/ui/` |
> | `$JAR` | `$GAME/projectzomboid.jar` |
> | `$JAVAP` | `/Users/liubinbin/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javap` |
>
> 未特别注明的 `相对路径:行号`（如 `client/ISUI/ISEquippedItem.lua:737`）一律相对于 `$PZ/`。
> Java 结论的 `javap` 片段均用 `$JAVAP -p -c[-v -constants] -cp <unzip 出来的目录>` 得到（`projectzomboid.jar` 是 class 主版本 69 / Java 25，必须用 JDK ≥ 25）。

---

## 结论速览

| 问题 | 结论 | 关键证据 |
|---|---|---|
| 谁调用 `launchEquippedItem` | 全游戏只有 2 处：`ISPlayerDataObject:createInventoryInterface` 与 `checkSidebarSizeOption` 的重建 | `client/ISUI/PlayerData/ISPlayerDataObject.lua:98`、`client/ISUI/ISEquippedItem.lua:1067` |
| 创建时机 | `Events.OnCreatePlayer` → `createPlayerData` → 对**每个**活跃玩家调 `createInventoryInterface` | `client/ISUI/PlayerData/ISPlayerData.lua:203,168,172` |
| 销毁时机 | `Events.OnPlayerDeath` → `destroyPlayerData`；`Events.OnPostSave` → `destroyAllPlayerData` | `client/ISUI/PlayerData/ISPlayerData.lua:204,205,177-183,194-201` |
| `ISEquippedItem.instance` 是不是单例 | **是全局唯一字段**，在 `:new()` 里无条件覆盖 ⇒ 分屏时指向**最后创建**的那个玩家的面板，不是 player 0 | `client/ISUI/ISEquippedItem.lua:685` + `ISPlayerData.lua:170-174` 的循环顺序 |
| 原版竖排按钮是给谁建的 | `initialise()` 里整段按钮都在 `if self.chr:getPlayerNum() == 0 then` 内 ⇒ **只有 player 0 有按钮列** | `client/ISUI/ISEquippedItem.lua:737` … `:967` |
| 有没有可 append 的按钮列表 | **没有**。`sidebarButtons` / `sidebarIcons` / `sidebarEntries` 全库 grep 零命中 | grep 退出码 1（见 §2.3） |
| 贴图确切尺寸 | `W × round(W*0.75)`：48×36 / 64×48 / 80×60 / 96×72 / 128×96 | `$UI/Sidebar/*/Inventory_Off_*.png` 的 `sips` 实测 |
| 尺寸映射 | `getOptionSidebarSize()` 1..5 → 48/64/80/96/128；6 → `getOptionFontSizeReal()-1` 后再映射（**128 这一档只能靠 `sidebarSize == 5` 拿到**，走字体分支最大只到 96） | `ISEquippedItem.lua:8-25` + `Core.newOption("sidebarSize",1,6,6)` + `getOptionFontSizeReal` 字节码 |
| 运行中改尺寸 | 下一帧 `prerender` → `checkSidebarSizeOption` → 旧面板 `removeFromUIManager()` + **整个面板重建** | `client/ISUI/ISEquippedItem.lua:27-28,1059-1068` |
| 打开窗口的官方写法 | 模块级 `X.instance` 单例 + `new → initialise → addToUIManager`，`close()` 里 `setVisible(false)+removeFromUIManager()+instance=nil` | `client/ISUI/UserPanel/ISUserPanelUI.lua:184-204`、`client/ISUI/ISEquippedItem.lua:461-468` |
| 手柄 | 原版侧边栏**没有任何手柄导航代码**；唯一的手柄代码是「打开窗口后把焦点交给新窗口」 | `client/ISUI/ISEquippedItem.lua:496-498`；`grep -n "onJoypad" ISEquippedItem.lua` 零命中 |
| 推荐方案 | **2a：后置 hook `ISEquippedItem.initialise`**，在函数尾部 `addChild` 自己的 `ISButton`，再调一次 `self:shrinkWrap()`；并带 2b 兜底 | 见 §2.4、§7 |
| 贴图资产 | **已就绪，且与规格逐像素吻合**：`Bin2NPCExtensionVanilla/42.21/media/ui/Sidebar/{48,64,80,96,128}/NPC_{On,Off}_<W>.png`，实测 48×36 / 64×48 / 80×60 / 96×72 / 128×96 | 见 §8.2 末尾的 `sips` 实测块 |
| 翻译键 | **已就绪**，无需新增：`IGUI_Bin2NPCExtensionVanilla_IconTooltip`（Tooltip）与 `_EntryButton`（按钮文案） | `.../Translate/{CN,EN}/IG_UI.json:28,22` |
| 待写代码 | 只差 `.../media/lua/client/Bin2NPCExtensionVanilla/ui/Icon.lua` 一个文件（骨架见 §8.1）；目录名 `ui/Icon.lua` 是脚手架 `Profile.lua:6` 已经写死的 | `Profile.lua:6,51-53` |

---

## 1. 左侧竖排栏的创建与生命周期

### 1.1 容器本体

```lua
-- client/ISUI/ISEquippedItem.lua:1
ISEquippedItem = ISPanel:derive("ISEquippedItem");
```

`launchEquippedItem` 在文件末尾，是**全局函数**（不是 local）：

```lua
-- client/ISUI/ISEquippedItem.lua:1266-1274
function launchEquippedItem(playerObj)
	local playerNum = playerObj:getPlayerNum()
	local x = getPlayerScreenLeft(playerNum)
    local y = getPlayerScreenTop(playerNum)
	local panel = ISEquippedItem:new(x + 10, y + 10, 100, 250, playerObj);
	panel:initialise();
	panel:addToUIManager();
    return panel;
end
```

`getPlayerScreenLeft/Top` 是 Java 暴露给 Lua 的全局静态方法：

```
$ $JAVAP -p -cp /tmp/pzlm 'zombie.Lua.LuaManager$GlobalObject' | grep -i PlayerScreen
  public static int getPlayerScreenLeft(int);
  public static int getPlayerScreenTop(int);
  public static int getPlayerScreenWidth(int);
  public static int getPlayerScreenHeight(int);
```

### 1.2 谁调用 `launchEquippedItem`

```
$ cd $PZ && grep -rn "launchEquippedItem" .
media/lua/client/ISUI/ISEquippedItem.lua:1067:    playerData.equipped = launchEquippedItem(self.chr)
media/lua/client/ISUI/ISEquippedItem.lua:1266:function launchEquippedItem(playerObj)
media/lua/client/ISUI/PlayerData/ISPlayerDataObject.lua:98:    self.equipped = launchEquippedItem(playerObj);
```

只有两个真实入口，`1067` 是「改尺寸后自己重建自己」。

**事件侧**（`client/ISUI/PlayerData/ISPlayerData.lua` 末尾）：

```lua
-- ISPlayerData.lua:203-206
Events.OnCreatePlayer.Add(createPlayerData)
Events.OnPlayerDeath.Add(destroyPlayerData)
Events.OnPostSave.Add(destroyAllPlayerData)
Events.OnResolutionChange.Add(onResolutionChange)
```

```lua
-- ISPlayerData.lua:158-175
function createPlayerData(id)
   if getCore():isDedicated() then return; end
    local numPlayers = getNumActivePlayers();
    ...
    for i=0,numPlayers-1 do
        removeInventoryUI(i);
    end
    ISPlayerData[id+1] = ISPlayerDataObject:new(id);
    for i=0,numPlayers-1 do
        if ISPlayerData[i+1] then
            ISPlayerData[i+1]:createInventoryInterface();
        end
    end
end
```

`Events.OnCreatePlayer` 的**第一个参数是玩家序号**，这有三份独立佐证：

- `ISPlayerData.lua:158` `function createPlayerData(id)` → `ISPlayerDataObject:new(id)` → `getSpecificPlayer(self.id)`
- `client/Foraging/ISSearchWindow.lua:291` `function ISSearchWindow.createUI(_player)` → `getSpecificPlayer(_player)`，且 `:306` 注册到 `OnCreatePlayer`
- `client/Tutorial/TutorialSetup.lua:34` `function doTutorialCreatePlayer(id)` → `getSpecificPlayer(id)`

**第四份证据（最硬，直接看引擎的 triggerEvent 实参个数）**：`OnCreatePlayer` 由 `GameLoadingState` 触发，压了两个参数：

```
$ $JAVAP -p -c -cp /tmp/pzgls zombie.gameStates.GameLoadingState | awk '/String OnCreatePlayer/{f=NR} {l[NR]=$0} END{for(i=f-1;i<=f+12;i++) print l[i]}'
        77: ldc_w         #564   // String OnCreatePlayer
        80: iconst_0                        // 参数 1 = Integer 0
        81: invokestatic  #88    // Integer.valueOf:(I)Ljava/lang/Integer;
        84: getstatic     #566   // Field zombie/characters/IsoPlayer.players:[Lzombie/characters/IsoPlayer;
        87: iconst_0
        88: aaload                          // 参数 2 = IsoPlayer.players[0]
        89: invokestatic  #572   // LuaEventManager.triggerEvent:(Ljava/lang/String;Ljava/lang/Object;Ljava/lang/Object;)V
```

⇒ handler 签名是 `function(playerNum, playerObj)`。**注意这个初始调用点只发 player 0**（`IsoPlayer.players[0]`）；分屏玩家加入时由其它路径再触发一次、序号为加入者的 index（这正是 `createPlayerData(id)` 里 `id` 的来源）。

> **未证实**：分屏玩家加入时 `OnCreatePlayer` 的确切调用点与序号传递（我只证实了初始加载这一处）。验证方法：游戏内 `Events.OnCreatePlayer.Add(function(a,b) print("OnCreatePlayer", tostring(a), tostring(b)) end)`，然后加入 2P 观察输出。

`OnPlayerDeath` 传的是 **player 对象**（`ISPlayerData.lua:177-183` 用 `playerObj:getPlayerNum()`）。

`createInventoryInterface` 里的落点：

```lua
-- client/ISUI/PlayerData/ISPlayerDataObject.lua:98-101
    self.equipped = launchEquippedItem(playerObj);

    self.equipped:setX(self.x1left + 10);
    self.equipped:setY(self.y1top + 10);
```

> **证据**：`client/ISUI/PlayerData/ISPlayerDataObject.lua:8`（`createInventoryInterface` 定义）、`:98-101`；`client/ISUI/PlayerData/ISPlayerData.lua:168-174,203-205`。

**未在 `OnGameStart` 里创建**：`grep -rn "ISEquippedItem" $PZ` 的全部命中里没有任何 `OnGameStart` 关联（命中清单见 §1.5 末尾）。

### 1.3 `ISEquippedItem.instance` 是全局单例吗？多玩家分屏呢？

`:new()` 里**无条件**赋值：

```lua
-- client/ISUI/ISEquippedItem.lua:684-686
    o.sidebarSizeOption = getCore():getOptionSidebarSize();
    ISEquippedItem.instance = o;
    return o;
```

而 `createPlayerData` 的重建循环是 `for i=0,numPlayers-1`（`ISPlayerData.lua:170-174`），`createInventoryInterface` 内部才是 `launchEquippedItem`。所以**分屏时 `ISEquippedItem.instance` 指向序号最大的玩家的面板**（2 人分屏 ⇒ 指向 player 1 的面板，而 player 1 的面板里根本没有按钮，见 §1.4）。

**结论**：`ISEquippedItem.instance` 是**进程级唯一、最后创建者胜出**的字段，**不能**当作「player 0 的侧边栏」使用。
要拿某个玩家的侧边栏，唯一正确来源是 `getPlayerData(playerNum).equipped`：

```lua
-- client/ISUI/PlayerData/ISPlayerData.lua:3-5
function getPlayerData(id)
    return ISPlayerData[id+1];
end
```

> **证据**：`client/ISUI/ISEquippedItem.lua:685`；`client/ISUI/PlayerData/ISPlayerData.lua:3-5,168-174`；`client/ISUI/PlayerData/ISPlayerDataObject.lua:98`。
>
> **未证实**：分屏实机下 `ISEquippedItem.instance` 的实际取值方向（我只能从源码顺序证明「最后创建者胜出」，无法排除 `getNumActivePlayers()` 在加入玩家过程中的中间态）。验证方法：2 人分屏进入游戏后，在游戏内 Lua 控制台打印 `ISEquippedItem.instance.playerNum` 与 `getPlayerData(0).equipped.playerNum` 对比。

### 1.4 按钮列只给 player 0 建

`initialise()` 的结构（这是本次调研最关键的一段）：

```lua
-- client/ISUI/ISEquippedItem.lua:711-713
function ISEquippedItem:initialise()
    setTextureWidth()
	ISPanel.initialise(self);
```

```lua
-- client/ISUI/ISEquippedItem.lua:734-737
    self:setHeight(self.offHand:getBottom());
    local y = self.offHand:getBottom() + UI_BORDER_SPACING + 5

    if self.chr:getPlayerNum() == 0 then
```

…中间是 inv / health / crafting / build / movable / search / zone / map / debug / arf / safety / client / admin / war 全部按钮…

```lua
-- client/ISUI/ISEquippedItem.lua:964-970
            self:setHeight(self.warManagerBtn:getBottom())
            y = self.warManagerBtn:getBottom() + UI_BORDER_SPACING + 5
        end
    end

    self:shrinkWrap()
end
```

`:964` 的 `end` 关 `if isClient()`，`:967` 的 `end` 关 `if self.chr:getPlayerNum() == 0`。

**推论（源码级结论）**：分屏 player 1/2/3 的侧边栏只有 mainHand / offHand 两个 `ISImage`，没有任何 `ISButton`。这也被 `prerender` / `render` 的早退保护印证：

```lua
-- ISEquippedItem.lua:30-32（prerender 内）
    if self.invBtn == nil then
        return;
    end
-- ISEquippedItem.lua:398-400（render 内）
    if self.invBtn == nil then
        return;
    end
```

**未证实**：分屏实机画面（player 2 真的看不到按钮列）。验证方法：2 人分屏，观察 2P 屏幕左侧是否只有两只手。

### 1.5 `removeFromUIManager` / `shrinkWrap` / `checkSidebarSizeOption` 的语义与触发点

`ISEquippedItem` **没有 override `close()`**（`grep -n "^function ISEquippedItem:"` 的 22 个方法里没有 `close`）。它只有：

| 方法 | 语义 | 触发点 |
|---|---|---|
| `ISEquippedItem:removeFromUIManager()` (`:1049-1057`) | 先把自己额外 `addToUIManager` 的 `movablePopup` / `mapPopup` 也摘掉，再走 `ISPanel.removeFromUIManager` | `ISPlayerData.lua:28`（死亡/换人/读档前）、`ISEquippedItem.lua:1066`（改尺寸） |
| `ISEquippedItem:shrinkWrap()` (`:972-984`) | **覆写**了 `ISUIElement:shrinkWrap(padRight, padBottom, predicate)`（`client/ISUI/ISUIElement.lua:1890-1902`）。这个覆写版不收参数，遍历 children 时**只统计 `child.Type == "ISButton"`**，把面板 `width/height` 收紧到这些按钮的 `max(right)/max(bottom)` | 在 `ISEquippedItem` 类内唯一调用点 `:969`（`initialise` 结尾）。见下方 grep |
| `ISEquippedItem:checkSidebarSizeOption()` (`:1059-1068`) | 每帧检查 `getOptionSidebarSize()` 是否变化；变了就隐藏 + `removeFromUIManager()` + **重建** | `:28`（`prerender` 第一行，所以是每帧） |

```lua
-- client/ISUI/ISEquippedItem.lua:1059-1068
function ISEquippedItem:checkSidebarSizeOption()
    local playerData = getPlayerData(self.playerNum)
    if playerData == nil then return end
    if playerData.equipped ~= self then return end        -- 重入保护：只有"当前在册的那一个"才准重建
    if self.sidebarSizeOption == getCore():getOptionSidebarSize() then return end
    self.sidebarSizeOption = getCore():getOptionSidebarSize()
    self:setVisible(false)
    self:removeFromUIManager()
    playerData.equipped = launchEquippedItem(self.chr)
end
```

```lua
-- client/ISUI/ISEquippedItem.lua:972-984
function ISEquippedItem:shrinkWrap()
    local xMax = 0
    local yMax = 0
    local children = self:getChildren()
    for _,child in pairs(children) do
        if child.Type == "ISButton" then
            xMax = math.max(xMax, child:getRight())
            yMax = math.max(yMax, child:getBottom())
        end
    end
    self:setWidth(xMax)
    self:setHeight(yMax)
end
```

`child.Type == "ISButton"` 之所以成立，是因为 `derive` 会给派生类打 `Type`：

```lua
-- shared/ISBaseObject.lua:8-15
function ISBaseObject:derive(type)
    local o = {}
    setmetatable(o, self)
    self.__index = self
	o.Type = type
	o.SuperType = self
    return o
end
```

而 `ISButton = ISPanel:derive("ISButton")`（`client/ISUI/ISButton.lua:3`）⇒ `Type == "ISButton"`。**我们的自制按钮只要用 `ISButton:new(...)` 就天然会被 `shrinkWrap` 计入。**

`shrinkWrap` 的调用点分布（全游戏 grep）：

```
$ cd $PZ && grep -rn "shrinkWrap" . | wc -l
（大量命中，但必须区分两个不同实现：）

$ cd $PZ && grep -rn "function IS.*:shrinkWrap" .
media/lua/client/ISUI/ISUIElement.lua:1890:function ISUIElement:shrinkWrap(padRight, padBottom, predicate)
media/lua/client/ISUI/ISEquippedItem.lua:972:function ISEquippedItem:shrinkWrap()

$ cd $PZ && grep -rn "shrinkWrap" . | grep "ISEquippedItem"
（无输出 —— 说明 ISEquippedItem.lua 内部的调用写的是裸 self:shrinkWrap()，见 :969）
```

⇒ **`DebugUIs/*` 里那一堆 `self:shrinkWrap(UI_BORDER_SPACING+1, UI_BORDER_SPACING+1, nil)` 调的是 `ISUIElement` 的三参版本（`:1890-1902`），与 `ISEquippedItem` 完全无关。**
`ISEquippedItem:shrinkWrap()` 这个**零参覆写版**在它自己的类里只有 `:969` 一个调用点。

⚠ **顺带记一条冷门风险**：如果有别的代码对 `ISEquippedItem` 实例调用三参形式 `panel:shrinkWrap(padRight, padBottom, pred)`，会命中这个零参覆写 —— 参数被吞掉、过滤条件被换成「只算 ISButton」。原版没有这种调用，风险只在别的模组乱写时出现。

> **证据**：`client/ISUI/ISEquippedItem.lua:27-32,398-400,711-713,969,972-984,1049-1057,1059-1068`；`client/ISUI/PlayerData/ISPlayerData.lua:27-30,68-71`；`shared/ISBaseObject.lua:8-15`；`client/ISUI/ISButton.lua:3`。

### 1.6 ⚠ 关键约束：`TEXTURE_WIDTH` / `TEXTURE_HEIGHT` / `setTextureWidth` / `UI_BORDER_SPACING` **全是文件级 local**

```lua
-- client/ISUI/ISEquippedItem.lua:4-8
local UI_BORDER_SPACING = 10
local TEXTURE_WIDTH = 0
local TEXTURE_HEIGHT = 0

local function setTextureWidth()
```

```
$ cd $PZ && grep -rn "setTextureWidth" .
media/lua/client/ISUI/ISEquippedItem.lua:8:local function setTextureWidth()
media/lua/client/ISUI/ISEquippedItem.lua:602:    setTextureWidth()
media/lua/client/ISUI/ISEquippedItem.lua:712:    setTextureWidth()
media/lua/client/ISUI/ISEquippedItem.lua:1174:    setTextureWidth()
media/lua/client/ISUI/ISEquippedItem.lua:1234:    setTextureWidth()
```

⇒ **模组文件里读不到 `TEXTURE_WIDTH`、`TEXTURE_HEIGHT`、也调不到 `setTextureWidth()`**。
两个可行替代：

1. **从原版已建好的按钮上量**：`self.invBtn:getWidth()` / `:getHeight()`（player 0 一定存在）。
2. **自己复刻映射**（§3.3 的表），因为 `UI_BORDER_SPACING = 10` 也得一起复刻。

---

## 2. 加一个自己的图标按钮：方案对比

### 2.1 方案 a（推荐）：后置 hook `ISEquippedItem.initialise`

**做法**：`local OLD = ISEquippedItem.initialise` → `function ISEquippedItem:initialise() OLD(self); <加按钮>; self:shrinkWrap() end`。

**可行性证据（逐条）**

| 关注点 | 结论 | 证据 |
|---|---|---|
| hook 是否会被调用 | 会。`launchEquippedItem` 是唯一创建路径，`initialise()` 是必经步骤 | `ISEquippedItem.lua:1270-1271` |
| 位置怎么算 | `initialise` 结尾 `shrinkWrap()` 后 `self:getHeight() == 所有 ISButton 的最大 bottom`，直接 `y = self:getHeight() + 15` | `:969,972-984` |
| 会不会被 `shrinkWrap` 覆盖 | **不会**。`ISEquippedItem:shrinkWrap()`（零参覆写版）在 `ISEquippedItem` 类内只被 `:969` 调 1 次，就是 `initialise` 的结尾；我们已经在那之后。而且它统计的正是 `ISButton`，我们的按钮加进去后再调一次 `shrinkWrap` 会把自己正确计入 | `:969,972-984`；`client/ISUI/ISUIElement.lua:1890-1902`（区分另一个同名方法） |
| 需要 `setHeight` 吗 | 不需要手算，`self:shrinkWrap()` 会按新按钮的 bottom 重设 width/height | `:982-983` |
| 会不会被原版 `prerender` 打回 | 不会。`prerender` 只 `setImage` 已知按钮，不碰未知子控件；且它在 `:30` 对 `invBtn == nil` 提前 return，player 0 不受影响 | `:27-60` |
| 点击怎么接到自己 | `ISButton:new(x,y,w,h,title,clicktarget,onclick)` 的第 7 参就是自己的回调，不必改 `ISEquippedItem.onOptionMouseDown` 的 `internal` 分派 | `client/ISUI/ISButton.lua:479-531`；原版用法 `:742`、`ISEquippedItem.lua:420-499` |
| 图标要复刻原版外观 | 抄 `invBtn` 的 5 行配置：`setImage` / `setDisplayBackground(false)` / `ignoreWidthChange()` / `ignoreHeightChange()` / `addMouseOverToolTipItem` | `:742-751` |
| 改尺寸选项后会不会重复叠加 | 不会重复叠加，但**必须能重新建**。`checkSidebarSizeOption` 会换掉整个面板 ⇒ `initialise` 重跑 ⇒ 我们的 hook 重跑，按钮自动在新面板上 | `:1059-1068` |

**风险**

1. **位置在最后 ⇒ 大尺寸下可能超出屏幕底部。**
   按源码逐步推算（player 0、有地图按钮、无 debug、单机无 client 系列按钮）在 `W = 48` 时各段 bottom：

   | 段 | 计算 | bottom |
   |---|---|---|
   | mainHand `ISImage(0,0,W,W)` | — | 48 |
   | `y = 48 + 10 + 5` | `:723` | 63 |
   | offHand `ISImage(0,63,W,0.75W)` | `:725` | 99 |
   | invBtn | `y=99+15=114`, h=36 | 150 |
   | healthBtn | `y=165` | 201 |
   | craftingBtn | `y=216` | 252 |
   | buildBtn（x=5） | `y=267` | 303 |
   | movableBtn（h=`W`，不是 0.75W！） | `y=318` | 366 |
   | searchBtn | `y=381` | 417 |
   | zoneBtn | `y=432` | 468 |
   | mapBtn | `y=483` | 519 |

   ⇒ 48 档的 `shrinkWrap` 高度 = 519，通式 `8W + 135`：

   | W | 原版面板高度 | 追加一个按钮后的 bottom（+15+0.75W） | 1080p 下是否越界 |
   |---|---|---|---|
   | 48 | 519 | 570 | 否 |
   | 64 | 647 | 710 | 否 |
   | 80 | 775 | 850 | 否 |
   | 96 | 903 | 990 | 否（但 `isClient()` 的 4 个额外按钮会推到 ≈1338，越界） |
   | 128 | 1159 | 1270 | **是** |

   （`movableBtn` 用的是 `TEXTURE_WIDTH` 当高度：`client/ISUI/ISEquippedItem.lua:798`，所以通式不是纯线性 0.75。）

   **状态**：`8W+135` 是我按 `file:line` 逐段手算的结果（**未实机测量**）。验证方法：游戏内把侧边栏尺寸切到 128，打印 `getPlayerData(0).equipped:getHeight()`。

2. **和其它也 hook `initialise` 的模组叠加**：见 §6。

3. **`ISEquippedItem.instance` 被覆盖**：不影响本方案，因为我们完全不读 `ISEquippedItem.instance`（只从 hook 参数 `self` 拿面板）。

**为什么位置选「追加在最后」而不是「插在手后面」**：插在前面必须把原版每个按钮 `setY(+=Δ)`，而 `movableTooltip` / `movablePopup` 的位置是**建的时候**就按 `movableBtn:getY()` 算好的：

```lua
-- client/ISUI/ISEquippedItem.lua:807-812
        self.movableTooltip = ISMoveablesIconToolTip:new (0, self.movableBtn:getY(), 120, TEXTURE_WIDTH, self.movableBtn:getRight());
        self.movablePopup = ISMoveablesIconPopup:new(10 + self.movableBtn:getX(), 10 + self.movableBtn:getY(), TEXTURE_WIDTH * 6, TEXTURE_WIDTH)
```

整体下移会让这两个浮层错位（`movablePopup` 还已经 `addToUIManager()` 了，`:811`）。**追加在最后是唯一零副作用的插入点。**

### 2.2 方案 b：完全独立的 `ISPanel:derive("Bin2NpcIcon")`

**做法**：自己 `ISPanel:derive`，用 `getPlayerScreenLeft(0)/getPlayerScreenTop(0)` 锚左侧边缘，不碰原版对象。

**优点**

- 零 monkey patch，天然不受其它模组 hook `initialise` 的影响。
- 原版侧边栏整体消失时（被别的模组删掉、`playerNum ~= 0`）依然可用。

**缺点 / 风险（都有证据）**

1. **必然要自己决定怎么避免重叠**。原版面板位置是 `x = screenLeft + 10, y = screenTop + 10`（`ISEquippedItem.lua:1268-1270`，另外 `ISPlayerDataObject.lua:100-101` 又强制 `x1left+10 / y1top+10`），宽度是 `shrinkWrap` 得到的 `W+5`（buildBtn 在 x=5，`:784`）。所以独立图标的锚点至少要 `x = screenLeft + 10 + W + 5 + gap`，而 `W` 又得自己按 §3.3 算 —— 等于还是要复刻映射。
2. **纵向也躲不开**：原版面板高度 `8W+135`（§2.1），在 W=96/128 时可能已经占满屏幕高，独立图标放「右上」或「右下」才安全。
3. **生命周期不跟原版走**。独立面板自己 `addToUIManager()` 之后，`ISEquippedItem:removeFromUIManager()` **不会**清理它（`:1049-1057` 只清 `movablePopup` / `mapPopup`），`ISPlayerData.removeInventoryUI` 也不认识它（`:27-30`）。必须自己挂 `Events.OnPlayerDeath` / `OnPostSave` / `OnResolutionChange` 清理，否则读档后残留。
4. **隐藏 UI 的行为不一致**。本次调研**没有找到**任何「一键隐藏全部 HUD」的选项或代码：`grep -rn "HideUi\|setOptionHideUi" $PZ` **零命中**，`$JAVAP zombie.core.Core | grep -i hideui` **零命中**。也就是说原版侧边栏本身也没有「隐藏 UI」开关概念，独立面板不会因此更差 —— 但也没有现成钩子可蹭。

> **证据**：`client/ISUI/ISEquippedItem.lua:784,1268-1270,1049-1057`；`client/ISUI/PlayerData/ISPlayerDataObject.lua:100-101`；`client/ISUI/PlayerData/ISPlayerData.lua:27-30`。
>
> **未证实**：`getOptionHideUi` 这类 API 是否在更隐蔽的地方存在（我只 grep 了 Lua 全库 + `Core` 的方法名）。验证方法：`$JAVAP -p -cp /tmp/pzcls zombie.core.Core | grep -i "ui\|hud"` 全量比对，或在游戏内 `print(getCore().getOptionHideUi)` 试调用。

### 2.3 方案 c：有没有原版扩展点（可 append 的列表）？—— **没有**

```
$ cd $PZ && grep -rn "sidebarButtons\|sidebarIcons\|sidebarEntries" .
（无输出，退出码 1）

$ cd $PZ && grep -rn "ISEquippedItem" . | wc -l
（命中全部落在 ISEquippedItem.lua 自身、Tutorial/Steps.lua、ISPlace3DItemCursor.lua 的注释里 —— 没有任何注册表）
```

`initialise()` 是**硬编码顺序**逐行 `ISButton:new` + `setImage` + `internal = "XXX"` + `addChild`（`:742` 起的 14 个按钮），没有任何循环或表驱动的注册点。
⇒ **不存在「官方支持的第三方向侧边栏注册按钮」入口。只能 hook 或自建。**

> **证据**：上面两条 grep 的原始输出。

### 2.4 推荐：2a 为主 + 2b 兜底

| 判据 | 2a | 2b |
|---|---|---|
| 风格一致性（跟随 `_On_`/`_Off_`、跟随尺寸选项缩放） | ✅ 天然跟随（原版面板重建时一起重建） | ⚠ 要自己监听选项变化并重建 |
| 零 patch | ❌ 需要 1 个 post-hook | ✅ |
| 自动清理（死亡/读档/换尺寸） | ✅ 跟着原版面板走 | ❌ 要自己挂事件 |
| 位置正确性 | ✅ 接在最后一个按钮下（拥挤时靠 §7 兜底） | ❌ 需要自己算避让 |
| 其它模组 hook 冲突 | ⚠ 见 §6 | ✅ |

**推荐：2a 为主**（风格与一致性优先，代价只有一个 hook），**2b 作为 §7 的兜底**（当原版面板/按钮列不可用，或我们的按钮算出来会越出屏幕底部时启用）。

---

## 3. 贴图规格

### 3.1 确切像素尺寸（`sips` 实测）

```
$ cd $GAME && for d in 48 64 80 96 128; do for f in Inventory_Off Inventory_On; do \
    sips -g pixelWidth -g pixelHeight media/ui/Sidebar/$d/${f}_$d.png | tail -2; done; done
```

实测结果：

| 目录 | 文件名 | 真实像素 |
|---|---|---|
| `$UI/Sidebar/48/` | `Inventory_{On,Off}_48.png` | **48 × 36** |
| `$UI/Sidebar/64/` | `Inventory_{On,Off}_64.png` | **64 × 48** |
| `$UI/Sidebar/80/` | `Inventory_{On,Off}_80.png` | **80 × 60** |
| `$UI/Sidebar/96/` | `Inventory_{On,Off}_96.png` | **96 × 72** |
| `$UI/Sidebar/128/` | `Inventory_{On,Off}_128.png` | **128 × 96** |

⇒ 规律就是 `W × W*0.75`（4:3），与 `ISEquippedItem.lua:24` 的 `TEXTURE_HEIGHT = TEXTURE_WIDTH * 0.75` 完全一致。

**但并不是该目录下所有贴图都是 4:3。** 48 档全量实测：

```
$ cd $GAME && for f in media/ui/Sidebar/48/*.png; do sips -g pixelWidth -g pixelHeight "$f" | \
    awk -v n="$(basename $f)" '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{printf "%-36s %sx%s\n", n, w, h}'; done
Admin_Icon_Off_48.png                48x48
AnimalZone_Off_48.png                48x36
ARF_Icon_Off_48.png                  48x48
Build_Off_48.png                     48x36
BuildingRoomsEditor_48.png           48x36
Carpentry_Off_48.png                 48x36
Client_Icon_Off_48.png               48x48
Debug_Off_48.png                     48x36
Furniture_Disassemble_48.png         48x48
Furniture_Off_48.png                 48x36
Furniture_Pickup_48.png              48x48
HandMain_Off_48.png                  48x48
HandSecondary_Off_48.png             48x35   ← 原版自己都不严格
Heart_Off_48.png                     48x36
Inventory_Off_48.png                 48x36
Map_Off_48.png                       48x36
Safety_Background_48.png             48x36
Safety_Tintable_48.png               48x36
Search_Off_48.png                    48x36
War_Off_48.png                       48x48
...
```

跨档抽查（`64/80/96/128`）：`War_Off` 与 `Admin_Icon_Off` 是 `W×W`（正方形），`HandMain_Off` 是 `W×W`，`HandSecondary_Off` 是 `W×0.72W`。

**所以：4:3 是「按钮矩形」的比例，不是「本目录所有贴图」的比例。**
- `mainHand` 用的是 `ISImage:new(0, 0, TEXTURE_WIDTH, TEXTURE_WIDTH, ...)`（`:715`）⇒ 正方形槽位 + 正方形贴图；
- `offHand` 用 `TEXTURE_WIDTH, TEXTURE_HEIGHT`（`:725`）；
- 绝大多数 `ISButton` 用 `TEXTURE_WIDTH, TEXTURE_HEIGHT`（如 `:742` 的 invBtn）；
- **例外**：`movableBtn = ISButton:new(0, y, TEXTURE_WIDTH, TEXTURE_WIDTH, ...)`（`:798`）是正方形按钮。

### 3.2 `ISButton` 到底怎么画这张图（决定「能不能交正方形」）

```lua
-- client/ISUI/ISButton.lua:196-227（摘）
function ISButton:render()
	if self.image ~= nil then
        ...
		if self.forcedWidthImage and self.forcedHeightImage then
            self:drawTextureScaledAspect(self.image, ..., self.forcedWidthImage, self.forcedHeightImage, ...);
        elseif self.image:getWidthOrig() <= self.width and self.image:getHeightOrig() <= self.height then
            self:drawTexture(self.image, (self.width / 2) - (self.image:getWidthOrig() / 2), (self.height / 2) - (self.image:getHeightOrig() / 2), alpha, ...);
        else
            self:drawTextureScaledAspect(self.image, 0, 0, self.width, self.height, alpha, ...);
        end
	end
```

三条分支的含义：

| 贴图尺寸 vs 按钮矩形 | 结果 |
|---|---|
| 贴图 ≤ 按钮（两轴都 ≤） | **原始像素居中画**，不缩放 ⇒ 48×36 贴图在 48×36 按钮里 1:1 |
| 贴图某轴 > 按钮 | `drawTextureScaledAspect` **等比缩放到装得下**，居中 ⇒ 48×48 贴图在 48×36 按钮里被缩成 36×36（左右各留 6px 透明） |
| `forcedWidthImage/HeightImage` | 需要显式设置，原版侧边栏**没用**这个字段 |

⇒ 交正方形（`W×W`）**不会报错**，但会等比缩小到 `0.75W`，视觉上比原版按钮小一圈（这正好解释了 `War_On_48.png` / `Admin_Icon_On_48.png` 为什么是 48×48 却看起来更小）。
**要 1:1 对齐原版 Inventory 图标，就交 `W × W*0.75`。**

> **证据**：`client/ISUI/ISButton.lua:196-227`；`ISEquippedItem.lua:715,725,742,798`；上面 `sips` 的原始输出。

### 3.3 `getOptionSidebarSize()` → `TEXTURE_WIDTH` 映射表

Lua 侧：

```lua
-- client/ISUI/ISEquippedItem.lua:8-25
local function setTextureWidth()
    local size = getCore():getOptionSidebarSize()
    if size == 6 then
        size = getCore():getOptionFontSizeReal() - 1
    end
        TEXTURE_WIDTH = 48
    if size == 2  then
        TEXTURE_WIDTH = 64
    elseif size == 3  then
        TEXTURE_WIDTH = 80
    elseif size == 4  then
        TEXTURE_WIDTH = 96
    elseif size == 5 then
        TEXTURE_WIDTH = 128
    end

    TEXTURE_HEIGHT = TEXTURE_WIDTH * 0.75
end
```

Java 侧（选项范围与默认值）：

```
$ $JAVAP -p -c -v -constants -cp /tmp/pzcls zombie.core.Core | sed -n '/594: putfield.*optionMoodleSize/,/620: /p'
       599: ldc           #233   // String sidebarSize
       601: iconst_1              // min  = 1
       602: bipush        6       // max  = 6
       604: bipush        6       // def  = 6
       606: invokevirtual #77    // Method newOption:(Ljava/lang/String;III)Lzombie/config/IntegerConfigOption;
       609: putfield      #235   // Field optionSidebarSize:...
```

```
$ $JAVAP -p -c -cp /tmp/pzcls zombie.core.Core | grep -n "public int getOptionSidebarSize" -A 6
  public int getOptionSidebarSize();
    Code:
       0: aload_0
       1: getfield      #235   // Field optionSidebarSize:Lzombie/config/IntegerConfigOption;
       4: invokevirtual #1171  // Method zombie/config/IntegerConfigOption.getValue:()I
       7: ireturn
```

`getOptionFontSizeReal()`（`:6` 分支用的那个）**返回值被夹在 1..5**：

```
$ $JAVAP -p -c -cp /tmp/pzcls zombie.core.Core | sed -n '/public int getOptionFontSizeReal/,/public int getOptionMoodleSize/p'
   5: iload_1
   6: bipush        6
   8: if_icmpne     138        // 非 6 -> 直接返回
  11: sipush        1080       ; 15: sipush 2400 ; 19: sipush 132
  27: invokevirtual getScreenHeight:()I
  34: i2f ; 35: ldc_w float 132.0f ; 38: fdiv ; 39: invokestatic PZMath.floor ; 42: f2i ; 43: iconst_1 ; 44: iadd
  49: iconst_0 ; 50: bipush 10 ; 52: invokestatic PZMath.clamp:(III)I
  57: tableswitch   { 0:->1, 1:->2, 2,3:->3, 4,5,6:->4, 7,8,9,10:->5, default:->138 }
```

**完整映射表**：

| `getOptionSidebarSize()` | 走的分支 | `getOptionFontSizeReal()` | `TEXTURE_WIDTH` | `TEXTURE_HEIGHT` | 对应贴图目录 |
|---|---|---|---|---|---|
| 1 | 不命中任何 `elseif`，保持初值 48 | — | **48** | **36** | `$UI/Sidebar/48/` |
| 2 | `size == 2` | — | **64** | **48** | `$UI/Sidebar/64/` |
| 3 | `size == 3` | — | **80** | **60** | `$UI/Sidebar/80/` |
| 4 | `size == 4` | — | **96** | **72** | `$UI/Sidebar/96/` |
| 5 | `size == 5` | — | **128** | **96** | `$UI/Sidebar/128/` |
| 6 | `size = fontSizeReal - 1` | 1 | `0` → 不命中 → **48** | **36** | `48/` |
| 6 | 同上 | 2 | `1` → 不命中 → **48** | **36** | `48/` |
| 6 | 同上 | 3 | `2` → **64** | **48** | `64/` |
| 6 | 同上 | 4 | `3` → **80** | **60** | `80/` |
| 6 | 同上 | 5 | `4` → **96** | **72** | `96/` |

> ⚠ **`128` 只能靠 `sidebarSize == 5` 拿到。** 因为 `getOptionFontSizeReal()` 最大 5 ⇒ `size` 最大 4 ⇒ 96。
> 但 `128/` 目录的贴图仍然必须准备（用户会把选项设成 5）。

**UI 文案本身就是这张表的证明**（下拉框直接显示像素值）：

```
$ cd $PZ/shared/Translate/CN && grep -n "UI_optionscreen_MoodleSize" UI.json
1500:    "UI_optionscreen_MoodleSize1": "48",
1501:    "UI_optionscreen_MoodleSize2": "64",
1502:    "UI_optionscreen_MoodleSize3": "80",
1503:    "UI_optionscreen_MoodleSize4": "96",
1504:    "UI_optionscreen_MoodleSize5": "128",
1505:    "UI_optionscreen_MoodleSize6": "随字体大小缩放",
```

选项下拉框本体（注意它复用了 Moodle 的文案 key，这是原版的一个小怪癖）：

```lua
-- client/OptionScreens/MainOptions.lua:1280-1297
	local sidebarSize = self:addCombo(splitpoint, y, comboWidth, 20, getText("UI_optionscreen_SidebarSize"), { getText("UI_optionscreen_MoodleSize1"), ..., getText("UI_optionscreen_MoodleSize6") }, 1)
	...
	function gameOption.toUI(self)  box.selected = getCore():getOptionSidebarSize()  end
	function gameOption.apply(self)
		if box.options[box.selected] then
			if getCore():getOptionSidebarSize() ~= box.selected then
				getCore():setOptionSidebarSize(box.selected)
			end
		end
	end
```

**默认值推导**：`sidebarSize` 默认 6 → 走字体分支；`fontSize` 默认 6 → `getOptionFontSizeReal()` 按屏幕高度算：

| 屏幕高 | `floor((h-1080)/132)+1` | clamp 后 | `getOptionFontSizeReal()` | `size` | `TEXTURE_WIDTH` |
|---|---|---|---|---|---|
| 720 | −3 → −2 | 0 | 1 | 0 | 48 |
| **1080** | 0 → 1 | 1 | 2 | 1 | **48** |
| 1440 | 2 → 3 | 3 | 3 | 2 | **64** |
| 2160 (4K) | 8 → 9 | 9 | 5 | 4 | **96** |

> **未证实**：本机屏幕分辨率对应的默认档（我没有读 `~/Zomboid/options.ini` 里的 `fontSize=`）。验证方法：`grep -n "fontSize=" ~/Zomboid/options.ini`，再套上表公式。

### 3.4 玩家运行中改这个选项会发生什么

1. 选项界面 `gameOption.apply` → `getCore():setOptionSidebarSize(box.selected)`（`MainOptions.lua:1293`）。**注意：这里不重建 UI。**
2. 下一帧渲染时，`ISEquippedItem:prerender()` 第一行调 `checkSidebarSizeOption()`（`:27-28`）发现 `self.sidebarSizeOption ~= getCore():getOptionSidebarSize()`。
3. 该面板 `setVisible(false)` + `removeFromUIManager()`，然后 `playerData.equipped = launchEquippedItem(self.chr)`（`:1065-1067`）—— **整个面板被一个全新的实例替换**，`setTextureWidth()` 在新实例的 `:new`/`:initialise` 里重新跑，贴图路径换成新目录。
4. 旧实例变成垃圾对象；它的 children（包括我们追加的按钮）随之不再被渲染，但**不会**自动触发 `removeFromUIManager` 之类的清理回调（`ISEquippedItem.removeFromUIManager` 只额外清 `movablePopup`/`mapPopup`）。
5. `checkSidebarSizeOption` 有重入保护 `if playerData.equipped ~= self then return end`（`:1062`），所以旧实例随后被回收时不会再次重建。

**对我们的意义（正面）**：方案 2a 无需自己监听选项变化，按钮会随面板重建自动以新尺寸重生。
**对我们的意义（负面）**：如果我们的按钮持有任何「贴图缓存」「窗口引用」，必须放在**新实例**上（hook 参数 `self`），不能挂在模块级全局上，否则会拿着旧尺寸的按钮引用。

> **证据**：`client/OptionScreens/MainOptions.lua:1280-1297`；`client/ISUI/ISEquippedItem.lua:27-28,602,712,1059-1068`。

### 3.5 贴图文件放哪里（模组侧可解析性）

模组自己的 `media/ui/...` 路径与游戏同名路径处于同一虚拟命名空间。仓库内两份可复用的先例：

| 先例 | 说明 |
|---|---|
| `bin2/Contents/mods/NotTheEnd2/media/textures/GUI/lightning.png` + `Token_Overlay.lua:3` `getTexture("media/textures/GUI/lightning.png")` | **纯新增**文件。已核实 `$GAME/media/textures/GUI/` 目录在原版**根本不存在**（`ls: No such file or directory`）⇒ 这张贴图只可能来自模组目录，证明「模组新增 `media/` 资产可被 `getTexture` 解析」 |
| `bin2_title_cover/ZomboidTitleCover/Contents/mods/ZomboidTitleCover/42.21/media/ui/Title.png`（原版同名文件确实存在：`$GAME/media/ui/Title.png`，497338 字节） | **同名覆盖**先例，证明 `media/ui/` 这一层模组目录会被挂进同一命名空间 |

纹理加载链（Java）：

```
$ $JAVAP -p -c -cp /tmp/pztex zombie.core.textures.Texture | grep -n "getSharedTextureInternal\|TexturePackPage.getTexture"
 1114:  private static zombie.core.textures.Texture getSharedTextureInternal(java.lang.String, int);
 1170:       112: invokestatic #530  // Method zombie/core/textures/TexturePackPage.getTexture:(Ljava/lang/String;)Lzombie/core/textures/Texture;
```

⇒ 走的是 **texture pack（从 classpath 扫 `media/` 建包）**，而不是 `ZomboidFileSystem.getMediaFile`（后者只对着游戏 `workdir` 解析）：

```
$ $JAVAP -p -c -cp /tmp/pzfs2 zombie.ZomboidFileSystem | sed -n '/public java.io.File getMediaFile/,/public java.lang.String getMediaPath/p'
        24: new           #124  // class java/io/File
        29: getfield      #58   // Field workdir:Lzombie/ZomboidFileSystem$PZFolder;
        32: getfield      #135  // Field ...PZFolder.canonicalFile:Ljava/io/File;
```

⇒ 我们有 `baseFolder/media/ui/Sidebar/<W>/NPC_On_<W>.png` 就够，**不需要**写进 `workdir`。

**未证实**：`42.21/media/ui/...` 版本目录这种布局在本机实机加载成功的日志证据（我无法在本次只读调研里启动游戏）。验证方法：实现后启动游戏，看 `~/Zomboid/console.txt` 是否有该 `getTexture` 的缺图告警；或用 debug 的 Texture Viewer（入口见 `docs/pz-dev-tooling.md:32` 的表格行，以及 `:22` 的 `ISEquippedItem.lua:452` 调试入口）搜 `NPC_On_48`。

---

## 4. 点击后打开自己的窗口

### 4.1 原版侧边栏按钮是怎么开窗的（`ISEquippedItem:onOptionMouseDown`）

```lua
-- client/ISUI/ISEquippedItem.lua:420-499（摘）
function ISEquippedItem:onOptionMouseDown(button, x, y)
    local focus = nil
    local playerNum = self.chr:getPlayerNum()
	if button.internal == "INVENTORY" then
        self.inventory:setVisible(not self.inventory:getIsVisible());
        self.loot:setVisible(self.inventory:getIsVisible());
        if self.inventory:isVisible() then
            focus = self.inventory
        end
    elseif button.internal == "HEALTH" then
		self.infopanel:toggleView(getText("IGUI_XP_Health"));
        if self.infopanel:isVisible() then
            focus = self.infopanel.panel:getActiveView()
        end
    elseif button.internal == "CRAFTING" then
        if ISEntityUI.IsWindowOpen(self.chr:getPlayerNum(), "HandcraftWindow") then
            ISEntityUI.GetWindowInstance(self.chr:getPlayerNum(), "HandcraftWindow"):close();
        else
            ISEntityUI.OpenHandcraftWindow(self.chr, nil);   -- / 按住 LMENU 时 OpenHandcraftWindow(self.chr, nil, "*")
        end
    elseif button.internal == "MOVABLE" ... (在 render/prerender 里另处理)
    elseif button.internal == "MAP" then
        ISWorldMap.ToggleWorldMap(self.chr:getPlayerNum())
    elseif button.internal == "SEARCH" then
        ISSearchWindow.toggleWindow(self.chr);
    elseif button.internal == "BUILD" then
        if ISEntityUI.IsWindowOpen(self.chr:getPlayerNum(), "BuildWindow") then
            ISEntityUI.GetWindowInstance(self.chr:getPlayerNum(), "BuildWindow"):close();
        else
            ISEntityUI.OpenBuildWindow(self.chr, nil, "*");
        end
    elseif button.internal == "ZONE" then
        ISDesignationZonePanel.toggleZoneUI(playerNum);
    elseif button.internal == "USERPANEL" then
        if ISUserPanelUI.instance then
            ISUserPanelUI.instance:close()
        else
            local modal = ISUserPanelUI:new(200, 200, 400, 250, self.chr)
            modal:initialise();
            modal:addToUIManager();
        end
    elseif button.internal == "ADMINPANEL" then ... ISAdminPanelUI.instance ...
    elseif button.internal == "WARMANAGERPANEL" then ... ISWarManagerUI.instance ...
    elseif button.internal == "SAFETY" then
        self:toggleSafety();
    end
    if focus and JoypadState.players[playerNum+1] then
        setJoypadFocus(playerNum, focus)
    end
end
```

**用到的原版机制，分四类**：

| 类别 | API | 证据 |
|---|---|---|
| 直接 show/hide 已有窗口 | `self.inventory:setVisible(...)` / `self.loot:setVisible(...)` | `:424-425` |
| 实体窗口注册表 | `ISEntityUI.IsWindowOpen(playerNum, key)` / `ISEntityUI.GetWindowInstance(playerNum, key)` / `ISEntityUI.OpenHandcraftWindow` / `ISEntityUI.OpenBuildWindow` | `:435-443,486-489` |
| 「自带 toggle」的模块级单例 | `ISWorldMap.ToggleWorldMap(pn)`、`ISSearchWindow.toggleWindow(chr)`、`ISDesignationZonePanel.toggleZoneUI(pn)` | `:445-452,491-492` |
| **模块级 `X.instance` 单例 + new/initialise/addToUIManager** | `ISUserPanelUI` / `ISAdminPanelUI` / `ISWarManagerUI` | `:461-484` |

`ISEntityUI.IsWindowOpen` 的语义要点（**不能拿来当通用窗口注册表**）：

```lua
-- client/Entity/ISEntityUI.lua:622-632
ISEntityUI.IsWindowOpen = function(_playerNum, _windowKey)
    ISEntityUI.EnsurePlayers();
    return ISEntityUI.players[_playerNum] and ISEntityUI.players[_playerNum].windows[_windowKey] and ISEntityUI.players[_playerNum].windows[_windowKey].instance;
end
ISEntityUI.GetWindowInstance = function(_playerNum, _windowKey)
    if ISEntityUI.IsWindowOpen(_playerNum, _windowKey) then
        return ISEntityUI.players[_playerNum].windows[_windowKey].instance;
    end
    return nil;
end
```

它的 `players[pn].windows[key].instance` 只在 `ISEntityUI.createWindow`（`:352-428`）里被写，而 `createWindow` 必须由 `_windowInstance.entity` / `xuiStyleName` 派生 `windowKey`（`:366`），且 `:369` 会 `ISEntityUI.CloseWindows()` **关掉所有其它实体窗口**。⇒ 我们的招募窗口既没有 entity 也不该被它关掉，**不要**往这个注册表里塞。（要蹭也可以：设 `window.xuiStyleName = "Bin2NpcRecruitWindow"` 再自行写 `ISEntityUI.players`，但那是把原版的实体窗口语义硬掰弯，不推荐。）

### 4.2 「打开一个自定义 ISPanel 窗口」的最简、最原版一致写法

最原版一致的模板就是 `ISUserPanelUI`（它本身就是从侧边栏 `USERPANEL` 按钮打开的）：

```lua
-- client/ISUI/UserPanel/ISUserPanelUI.lua:190-204
function ISUserPanelUI:new(x, y, width, height, player)
    local o = {};
    o = ISPanel:new(x, y, width, height);
    setmetatable(o, self);
    self.__index = self;
    ...
    o.moveWithMouse = true;
    ISUserPanelUI.instance = o
    return o
end

-- client/ISUI/UserPanel/ISUserPanelUI.lua:184-188
function ISUserPanelUI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    ISUserPanelUI.instance = nil;
end
```

要点清单：

| 点 | 必须做什么 | 证据 |
|---|---|---|
| 窗口实例单例 | 在 `:new` 里 `X.instance = o`，在 `close()` 里 `X.instance = nil` | `ISUserPanelUI.lua:202,187` |
| 打开 | `local w = X:new(...); w:initialise(); w:addToUIManager()` | `ISEquippedItem.lua:465-467`；`ISDebugMenu.lua:85-97` |
| 关闭 | `setVisible(false)` 之后 **必须** `removeFromUIManager()` | `UserPanel/ISFactionUI.lua:331-334`；`ISUserPanelUI.lua:184-188` |
| 只用 `ISCollapsableWindow:close()` 够不够 | **不够**。基类 `close()` 只 `setVisible(false)`，不摘 UI manager | `client/ISUI/ISCollapsableWindow.lua:134-136` |
| 标题栏用 `ISCollapsableWindow` 还是 `ISPanel` | 想要原版窗口外观/拖动/标题栏/关闭按钮 ⇒ `ISCollapsableWindow`（或 `ISCollapsableWindowJoypad`）。`ISUserPanelUI` 用裸 `ISPanel` + 自己画的标题文字（`ISUserPanelUI.lua:19-22`）是能用但更「自己造轮子」 | `ISCollapsableWindow.lua:26-59`（`createChildren` 里建 `closeButton` / `resizeWidget` / pin / collapse） |
| 焦点/手柄 | 见 §4.3 | — |
| `playerNum` 字段 | 要手柄支持就必须自己存 `o.playerNum = player`（基类不存） | `ISBaseEntityWindow.lua:123`；`ISSearchWindow.lua:61` |

**推荐基类**：`ISCollapsableWindowJoypad`。
它不是 `ISCollapsableWindow` 的子类，而是 `ISPanelJoypad` 的派生 + 用 HACK 循环把 `ISCollapsableWindow` 的方法**拷贝**过来：

```lua
-- client/ISUI/ISCollapsableWindowJoypad.lua:1-10
require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanelJoypad"

ISCollapsableWindowJoypad = ISPanelJoypad:derive("ISCollapsableWindowJoypad")

-- HACK
for k,v in pairs(ISCollapsableWindow) do
	ISCollapsableWindowJoypad[k] = v
end
```

⇒ `ISCollapsableWindow.close(self)` 在它身上可用（方法被拷贝过），并且白拿 `joypadButtonsY` / `onJoypadDown` / `insertNewListOfButtons` 等（`client/ISUI/ISPanelJoypad.lua:144-165,310`）。

### 4.3 手柄（joypad）至少要做什么

**先接受一个事实：原版侧边栏是鼠标专用的。**

```
$ cd $PZ && grep -n "joypad\|Joypad" client/ISUI/ISEquippedItem.lua
496:    if focus and JoypadState.players[playerNum+1] then
497:        setJoypadFocus(playerNum, focus)

$ cd $PZ && grep -n "onJoypad" client/ISUI/ISEquippedItem.lua
（无输出）

$ cd $PZ && grep -rn "setJoypadFocus(.*equipped\|getJoypadFocus" client/ | grep -i equipped
（无输出）
```

⇒ 侧边栏本身**没有** `onJoypadDown` / `onJoypadDirUp/Down`，也**没有任何地方**把焦点交给它。手柄玩家在 B42 里不是靠这条竖排栏开窗的（他们走 `ISBackButtonWheel`，见 `ISPlayerDataObject.lua:107-110`）。所以「侧边栏入口」本质是鼠标入口；手柄支持只需保证「用鼠标点了之后，手柄也能操作新窗口」。

**至少要做的三件事**（全部在原版里有先例）：

1. **打开窗口时把焦点交给它**（照抄 `ISEquippedItem.lua:496-498`）：
   ```lua
   if JoypadState.players[playerNum + 1] then
       setJoypadFocus(playerNum, window)
   end
   ```
   参考 `client/Foraging/ISSearchWindow.lua:272-277`。

2. **窗口自己实现手柄导航**。用 `ISCollapsableWindowJoypad` 基类 + 覆写：

   ```lua
   -- client/ISUI/Maps/ISMapSymbolDialog.lua:279-303（原样板）
   function ISMapSymbolDialog:onGainJoypadFocus(joypadData)
       ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
       self.joypadIndexY = 1
       self.joypadIndex = 1
       self:restoreJoypadFocus(joypadData)
   end
   function ISMapSymbolDialog:onJoypadDown(button, joypadData)
       ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
   end
   function ISMapSymbolDialog:onJoypadDirDown(joypadData) ... end
   function ISMapSymbolDialog:onJoypadDirUp(joypadData) ... end
   ```
   并设 `o.overrideBPrompt = true`（`client/Foraging/ISSearchWindow.lua:235`）。
   仓库既有笔记：`docs/joypad.md:137`（`ISPanelJoypad` 用法）与 `docs/joypad.md:157-167`（必须实现的 6 个手柄回调表）、`checklists/controller-support-checklist.md:27`（「所有外部调用都包装在 `pcall()` 中」）与 `:33-35`（「保存原始函数引用 / 非侵入式补丁设计 / 正确的错误处理」）、`docs/joypad.md:359-365`（`JoypadUtil.safeSetJoypadFocus` 参考实现）。

3. **`close()` 里释放焦点 + 摘 UI manager**：

   ```lua
   -- client/Entity/ISUI/ISBaseEntityWindow.lua:116-135（原样板，含"防重复 close"）
   function ISBaseEntityWindow:close()
       if self.hasClosedWindowInstance then return; end     -- 防 update 里重复调用
       self.hasClosedWindowInstance = true;
       ISCollapsableWindow.close(self);
       ...
       if JoypadState.players[self.playerNum+1] then
           if isJoypadFocusOnElementOrDescendant(self.playerNum, self) then
               setJoypadFocus(self.playerNum, nil);
           end
       end
       self:removeFromUIManager();
   end
   ```

   精简版可照抄 `client/Foraging/ISSearchWindow.lua:59-64`：
   ```lua
   function ISSearchWindow:close()
       ISCollapsableWindow.close(self);
       if JoypadState.players[self.player+1] then
           setJoypadFocus(self.player, nil);
       end;
   end
   ```

> ⚠ 我们的新按钮**本身**不需要写 `onJoypadDown`（原版侧边栏也不是手柄可聚焦的）。如果将来想让它可聚焦，需要额外把按钮塞进某个 `ISPanelJoypad` 的 `joypadButtonsY`（`ISPanelJoypad.lua:144-165`），但那会让它脱离原版行为，**本期不做**。

---

## 5. 多玩家 / 联机

| 事实 | 证据 |
|---|---|
| 每个活跃玩家**都会**被建一个 `ISEquippedItem` 面板 | `ISPlayerData.lua:170-174` 对 `i=0..numPlayers-1` 全部调 `createInventoryInterface` → `ISPlayerDataObject.lua:98` |
| 但**只有 player 0** 的面板里会有按钮列 | `ISEquippedItem.lua:737` `if self.chr:getPlayerNum() == 0 then` … `:967` |
| `ISEquippedItem.instance` 是「最后创建者胜出」，分屏时**不是** player 0 | `ISEquippedItem.lua:685` |
| 每个玩家自己的面板可以从 `getPlayerData(pn).equipped` 拿到 | `ISPlayerData.lua:3-5,71`；`ISPlayerDataObject.lua:98` |
| 面板位置按玩家的分屏视口算 | `launchEquippedItem` 用 `getPlayerScreenLeft/Top(playerNum)`（`ISEquippedItem.lua:1268-1269`），随后被 `self.equipped:setX(self.x1left + 10)` 再对齐（`ISPlayerDataObject.lua:100-101`） |
| 单机/联机没有分支差异 | `ISEquippedItem` 里唯一的联机判断是 `isClient()` 决定要不要画 safety/client/admin/war 四个**多人专属**按钮（`:905-966`），以及 `isClient()` 决定 `addMouseOverToolTipItem` 是否给他加 tooltip（`:737-967` 整段在 player 0 内） |

**建议**：纯原版口味的 NPC 图标**只给 `playerNum == 0`** 建（与原版按钮列一致）。理由：
- 原版 player 1+ 的面板里没有任何按钮，忽然多一个图标会显得孤立且不合风格；
- 招募窗口本身是有状态 UI（列表/选中），分屏多开会让状态管理复杂化；
- 若将来真要支持分屏，正确做法是按 `pn` 各建一个窗口实例（`Bin2NpcRecruitWindow.instances[pn]`），而不是共用 `.instance`。

**联机（isClient）**：图标本身是纯客户端 UI，**不涉及网络**。招募动作走公共层 `Bin2NPCExtensionCore/Net.lua` 的既有通道，不需要为这个入口新增任何 `sendClientCommand`。

> **未证实**：分屏实机下 2P 是否真的看不到按钮列（§1.4 末尾已给验证方法）。

---

## 6. 与其它模组的冲突面 & 幂等防护

### 6.1 后置 hook `initialise` 的常见冲突

| 冲突 | 机制 | 缓解 |
|---|---|---|
| **多个模组都 hook `ISEquippedItem.initialise`** | 后置 hook 是链式的：谁后注册谁在链尾。所有人都能跑（不互相打断），但**顺序不定**（取决于 mod 加载顺序 / `loadModAfter`）。如果别人也调 `self:shrinkWrap()`，而我们在它**之前**加按钮，则我们的按钮会被它的 `shrinkWrap` 一并计入（`shrinkWrap` 统计所有 `ISButton`，`:975-981`）⇒ 结果仍然正确。 | 约定：**每次加完自己的按钮后自己调一次 `self:shrinkWrap()`**，不依赖别人的调用顺序。 |
| **别人无条件覆写（不是 hook）`ISEquippedItem.initialise`** | 若某模组写 `function ISEquippedItem:initialise() ... end` 且没保留 `OLD`，我们的 hook 会**完全失效**（我们的 `OLD` 是原始函数，覆写发生在之后） | 用**运行期校验**而不是信任：在 `Events.OnCreatePlayer` 之后再检查一次 `getPlayerData(0).equipped.bin2NpcBtn` 是否存在，不存在就走 §7 兜底。 |
| **`ISEquippedItem.instance` 被覆盖** | 见 §1.3。任何模组（或分屏）都会覆盖它 | **我们的代码一律不读 `ISEquippedItem.instance`**。只用 hook 的参数 `self` 和 `getPlayerData(pn).equipped`。 |
| **别人的按钮也用同一个 `internal`** | 原版 `onOptionMouseDown` 是 `if/elseif button.internal == "XXX"` 串；我们若也走 `ISEquippedItem.onOptionMouseDown` 就得保证 `internal` 唯一 | **我们完全不碰原版分派器**：`ISButton:new(..., self, 我们自己的回调)`，`internal` 只当自己的标记用。 |
| **别人也建了 `shrinkWrap` 之外的宽高计算** | 我们追加按钮会使面板变高。若有模组按固定高度画东西（如背景板），可能错位 | 无法完全避免；把按钮追加在**最后**是最小侵入（不移动任何现有子控件，§2.1）。 |

### 6.2 「重进世界 / 重载 Lua 后重复添加按钮」的防护写法

**两个层次的重复**：

1. **文件被加载两次**（`42.21` 与 `42` 两个版本目录同时启用、debug 的 `Reload Lua`、同名模组被装进两个 mod 目录）⇒ 会导致 `ISEquippedItem.initialise` 被包 **两层** hook。虽然每层 hook 都会触发实例级幂等（见下），两层都通过的话会加**两个按钮**。
   → **文件级守卫**：把整个 hook 安装包进一次性判定，**并且把标记放在一个稳定的全局命名空间表上**（不要用 `local`，`local` 在新一次 `loadfile` 里是新的）：

   ```lua
   local NS = require "Bin2NPCExtensionVanilla/Profile"   -- 已 bind 的命名空间表
   if NS == nil then return nil end
   if NS.SidebarHookVersion == 1 then
       return NS
   end
   NS.SidebarHookVersion = 1
   ```

   仓库里可复用的同类写法：`bin2_npc_extension/Contents/mods/Bin2NPCExtensionYese/42.21/media/lua/client/Bin2NPCExtensionYese/ui/Entry.lua:24-25`（`local Config = require ...` + `if Config == nil then return nil end` 的顺序声明守卫）、以及该系列 `shared/Bin2NPCExtension*Core/Profile.lua` 的命名空间守卫。经济类报告亦记录了这一模式：`bin2_npc_extension/docs/research/economy-integration-hooks.md:65`「文件首行建表 + 模块级 `if XLoaded then return end` 幂等守卫」。

2. **同一实例的 `initialise` 被调两次**（原版代码里 `initialise` 只调一次：`launchEquippedItem:1271`；但别的模组可能补调）⇒ 会加**两个按钮**。
   → **实例级守卫**：在 `self` 上放一个具名标记字段：

   ```lua
   if self.bin2NpcBtn ~= nil then return end
   ...
   self.bin2NpcBtn = btn
   ```

   原版自己的同类先例（用实例字段做"已处理过"标记）：
   - `client/Entity/ISUI/ISBaseEntityWindow.lua:117-120` 用 `self.hasClosedWindowInstance` 防重复 `close()`
   - `client/ISUI/ISUIElement.lua:1379` 设 `self.removed = true`，`:1776` 读它 —— 这是原版现成的「本实例已从 UI manager 摘除」标记，可直接用来做**陈旧实例**判定（`if self:isRemoved() then return end` 之类）

3. **跨实例残留**：如果我们的按钮/窗口被挂到了模块级全局（而不是 `self`），改尺寸重建后旧引用会指向已 `removeFromUIManager` 的面板。
   → 一律挂在 `self`（`self.bin2NpcBtn`）；窗口单例遵循 §4.2 的 `instance = nil` 约定。

> **证据**：`client/ISUI/ISBaseEntityWindow.lua:116-120`；`client/ISUI/ISUIElement.lua:1373-1380,1776,1780,1991`；`bin2_npc_extension/docs/research/economy-integration-hooks.md:65`；`bin2_npc_extension/Contents/mods/Bin2NPCExtensionYese/42.21/media/lua/client/Bin2NPCExtensionYese/ui/Entry.lua:24-25`。

---

## 7. 「左侧图标」的兜底（原版侧边栏不可用时退化为屏幕左侧独立小图标）

**判定条件（建议按优先级短路，任一条命中就切 2b）**：

| # | 条件 | 判定表达式 | 依据 |
|---|---|---|---|
| 1 | 原版侧边栏类整个不存在（被别的模组移除/更老的引擎） | `ISEquippedItem == nil` | `ISEquippedItem` 是全局表：`ISEquippedItem.lua:1` |
| 2 | hook 目标不存在（别的模组换掉了这个方法名） | `type(ISEquippedItem.initialise) ~= "function"` | `:711` |
| 3 | **不是 player 0**（原版不给按钮列） | `pn ~= 0` | `:737` |
| 4 | 原版按钮列没建成（别人改过 `initialise`，或版本差异） | `self.invBtn == nil` | 原版自己就是这么判的：`:30-32,398-400` |
| 5 | 我们的按钮被其它 hook 挤掉（运行期校验） | `getPlayerData(0) == nil or getPlayerData(0).equipped == nil or getPlayerData(0).equipped.bin2NpcBtn == nil` | `ISPlayerData.lua:3-5,71` |
| 6 | **按钮会越出屏幕底部**（§2.1 算出来的风险） | `self:getY() + self:getHeight() > getPlayerScreenTop(pn) + getPlayerScreenHeight(pn)` | `getPlayerScreenTop/Height` 见 §1.1 javap；面板 `y` 由 `launchEquippedItem:1270` / `ISPlayerDataObject.lua:101` 决定 |
| 7 | 独立兜底该放哪 | 竖直贴屏幕左侧、从顶部往下让开原版手的槽位：`x = getPlayerScreenLeft(pn) + 10`，`y` 取 `getPlayerScreenTop(pn) + 10`（如果条件 6 命中说明侧边栏塞满了，这时建议贴**左下角**：`y = screenTop + screenHeight - h - 10`） | `ISEquippedItem.lua:1268-1270` 的坐标约定 |

**兜底面板的实现要点**（与 §2.2 的缺点对应）：
- 自己 `addToUIManager()` ⇒ 自己负责清理：挂 `Events.OnPlayerDeath`（`ISPlayerData.lua:204` 的同一事件）、`Events.OnPostSave`（`:205`）、`Events.OnResolutionChange`（`:206`）三个事件重算位置/销毁。
- 用 `ISButton` + 同一个 `_On_`/`_Off_` 贴图逻辑，保证风格一致。
- 兜底面板**不要**放进 `ISEntityUI.players`（§4.1 已说明原因）。

---

## 实现建议

### 8.1 最小可用钩子骨架（Kahlua 合法）

> 位置建议：`Bin2NPCExtensionVanilla/42.21/media/lua/client/Bin2NPCExtensionVanilla/ui/Icon.lua`
> —— 这个名字不是本报告定的，而是**已存在的脚手架已经写死的**：
> `42.21/media/lua/shared/Bin2NPCExtensionVanilla/Profile.lua:6` 的文件头注释里写着
> 「左侧入口……是原版左侧竖排图标栏（ISEquippedItem）里的一个 NPC 图标（见 ui/Icon.lua）」，
> 且 `Profile.lua:51-53` 已经预置了装不上时的日志 `uiHint = "the vanilla left sidebar (ISEquippedItem) was not found. ..."`。
> 截止本报告完成时 `ui/Icon.lua` **尚未创建**（该模组下 client 层一个 `.lua` 都没有）。
>
> 必须在 `ISEquippedItem.lua` 之后加载；`media/lua/client/**` 的目录排序里 `ISUI/` 早于 `Bin2NPCExtensionVanilla/`，但**不依赖**这一点——见下 `pcall` + 运行期校验兜底。
>
> 下面只用 Lua 5.1 子集（无 `goto`、无整除、无位运算、无 `table.unpack`），符合 Kahlua。

```lua
--[[
    Bin2NPCExtensionVanilla :: SidebarEntry（client）

    在**原版左侧竖排图标栏**（ISUI/ISEquippedItem.lua）末尾追加一个 NPC 图标按钮。
    只做两件事：把按钮插进原版面板；点击时切换我们自己的招募窗口。

    设计约束（都来自对 42.21 原版源码的取证，详见
    bin2_npc_extension/docs/research/vanilla-sidebar-entry.md）：

      * ISEquippedItem 的 TEXTURE_WIDTH / TEXTURE_HEIGHT / UI_BORDER_SPACING /
        setTextureWidth() 全是**文件级 local**，模组读不到 —— 所以尺寸只能
        (a) 从原版已建好的 self.invBtn 上量，或 (b) 复刻映射表。
      * 原版按钮列只在 playerNum == 0 时创建（ISEquippedItem.lua:737）。
      * initialise 结尾会调一次 self:shrinkWrap()（:969），它只统计
        Type == "ISButton" 的 child —— 我们追加完再调一次即可被正确计入。
      * 原版没有注册表可 append（grep sidebarButtons 零命中），只能 hook。
]]

-- 命名空间：本口味的 Profile（shared 层）已经在 require 时建好并 bind 了，
-- 这里的 require 是**显式的顺序声明**（与 Bin2NPCExtensionYese/ui/Entry.lua:24-25 同一写法）。
local NS = require "Bin2NPCExtensionVanilla/Profile"
if NS == nil then return nil end           -- 公共层缺失 / coreApi 不符：Profile 已经打过日志

-- 文件级幂等：防「42.21 + 42 双目录同时启用」或 debug Reload Lua 导致的重复安装
if NS.SidebarHookVersion == 1 then
    return NS
end
NS.SidebarHookVersion = 1

-- 我们的窗口（见报告 §4.2：ISCollapsableWindowJoypad 派生 + 模块级 instance 单例）
require "Bin2NPCExtensionVanilla/ui/Page"

local Entry = NS.SidebarEntry or {}
NS.SidebarEntry = Entry

-- 复刻 ISEquippedItem.lua:4 与 :723 等的 `+ UI_BORDER_SPACING + 5`
local GAP = 10 + 5
-- 复刻 ISEquippedItem.lua:8-25（调不到那个 local function）
local ALLOWED_WIDTHS = { [48] = 48, [64] = 64, [80] = 80, [96] = 96, [128] = 128 }

local function sidebarTextureWidth()
    local size = getCore():getOptionSidebarSize()
    if size == 6 then
        size = getCore():getOptionFontSizeReal() - 1
    end
    local w = 48
    if size == 2 then
        w = 64
    elseif size == 3 then
        w = 80
    elseif size == 4 then
        w = 96
    elseif size == 5 then
        w = 128
    end
    return w
end

-- 返回 off, on 两张贴图。**路径与文件名已被现有脚手架的 10 个 PNG 固定**：
--   <mod>/42.21/media/ui/Sidebar/<W>/NPC_Off_<W>.png
--   <mod>/42.21/media/ui/Sidebar/<W>/NPC_On_<W>.png
local function sidebarTextures(w)
    if not ALLOWED_WIDTHS[w] then w = 48 end
    local dir = "media/ui/Sidebar/" .. w .. "/"
    local tail = "_" .. w .. ".png"
    return getTexture(dir .. "NPC_Off" .. tail), getTexture(dir .. "NPC_On" .. tail)
end

-- ---------------------------------------------------------------- 窗口单例

-- 见报告 §4.2：模块级 instance + close 里置 nil，是原版 ISUserPanelUI 的写法。
-- 这里用 ISCollapsableWindowJoypad 以白拿手柄导航（原版 ISMapSymbolDialog 同款）。
-- 若口味不做手柄，可把基类换成 ISCollapsableWindow。
function Entry.toggleWindow(player)
    local Win = NS.RecruitWindow
    if Win == nil then return end
    if Win.instance ~= nil then
        Win.instance:close()            -- close() 内部 setVisible(false)+removeFromUIManager()+instance=nil
        return
    end
    local pn = player:getPlayerNum()
    local w, h = 520, 420
    local x = getPlayerScreenLeft(pn) + (getPlayerScreenWidth(pn) - w) / 2
    local y = getPlayerScreenTop(pn) + (getPlayerScreenHeight(pn) - h) / 2
    local win = Win:new(x, y, w, h, player)
    win:initialise()
    win:addToUIManager()
    if JoypadState.players[pn + 1] then
        setJoypadFocus(pn, win)          -- 抄 ISEquippedItem.lua:496-498
    end
end

-- ---------------------------------------------------------------- 按钮

-- ISButton:new(x, y, width, height, title, clicktarget, onclick)
--   clicktarget 必须是我们这个面板（原版也是传 self），onclick 收 (target, button, ...)
function Entry.onIconClick(target, button)
    local panel = target                         -- clicktarget == self（原版面板）
    if panel == nil or panel.chr == nil then return end
    Entry.toggleWindow(panel.chr)
end

function Entry.addIcon(self)
    if self.bin2NpcBtn ~= nil then return end                  -- 实例级幂等（§6.2）
    if self.chr == nil then return end
    if self.chr:getPlayerNum() ~= 0 then return end            -- 原版事实：只有 0 号有按钮列
    if self.invBtn == nil then return end                      -- 原版按钮列没建成 ⇒ 交给兜底

    -- 尺寸：优先量原版按钮（最稳），量不到才自己算
    local w, h = self.invBtn:getWidth(), self.invBtn:getHeight()
    if w == nil or h == nil or w <= 0 or h <= 0 then
        w = sidebarTextureWidth()
        h = w * 0.75
    end

    local offTex, onTex = sidebarTextures(sidebarTextureWidth())
    local y = self:getHeight() + GAP                            -- shrinkWrap 后 == 最后一个按钮的 bottom

    local btn = ISButton:new(0, y, w, h, "", self, Entry.onIconClick)
    btn:setImage(offTex)
    btn.internal = "BIN2_NPC_RECRUIT"                           -- 只作标记；我们不进原版 internal 分派
    btn:initialise()
    btn:instantiate()
    btn:setDisplayBackground(false)                             -- 抄原版 :747-749
    btn:ignoreWidthChange()
    btn:ignoreHeightChange()
    self:addChild(btn)

    self:addMouseOverToolTipItem(btn, getText("IGUI_Bin2NPCExtensionVanilla_IconTooltip"))

    self.bin2NpcBtn = btn
    self.bin2NpcIconOn = onTex
    self.bin2NpcIconOff = offTex

    self:shrinkWrap()                                           -- 把自己计入面板高宽（:972-984）

    -- 越界检查 ⇒ 交由兜底面板（报告 §7 条件 6）
    local pn = self.chr:getPlayerNum()
    if self:getY() + self:getHeight() > getPlayerScreenTop(pn) + getPlayerScreenHeight(pn) then
        print("[Bin2NPCExtensionVanilla] sidebar icon would overflow the screen; using fallback icon")
        self.bin2NpcBtn = nil
        btn:setVisible(false)
        Entry.useFallbackIcon(self.chr)
    end
end

-- On/Off 两态：原版在 prerender 里按窗口可见性切图（:34-60），我们照做。
-- 注意：不要覆盖原 prerender，只后置。
local function onOffImage(self)
    local btn = self.bin2NpcBtn
    if btn == nil then return end
    local Win = NS.RecruitWindow
    local isOpen = Win ~= nil and Win.instance ~= nil and Win.instance:getIsVisible()
    btn:setImage(isOpen and self.bin2NpcIconOn or self.bin2NpcIconOff)
end

-- ---------------------------------------------------------------- 安装 hook

local function install()
    if ISEquippedItem == nil or type(ISEquippedItem.initialise) ~= "function" then
        print("[Bin2NPCExtensionVanilla] ISEquippedItem.initialise not found; sidebar entry disabled")
        return false
    end
    if ISEquippedItem.bin2NpcHooked then return true end        -- 双保险（防别处也装了）
    ISEquippedItem.bin2NpcHooked = true

    local OLD_initialise = ISEquippedItem.initialise             -- 必须先存原函数引用
    function ISEquippedItem:initialise()
        OLD_initialise(self)
        local ok, err = pcall(Entry.addIcon, self)
        if not ok then
            print("[Bin2NPCExtensionVanilla] addIcon failed: " .. tostring(err))
        end
    end

    local OLD_prerender = ISEquippedItem.prerender
    if type(OLD_prerender) == "function" then
        function ISEquippedItem:prerender()
            OLD_prerender(self)
            local ok, err = pcall(onOffImage, self)
            if not ok then return end
        end
    end

    -- 运行期校验（§7 条件 5）：原版面板建好后确认按钮真的在
    Events.OnCreatePlayer.Add(function(playerNum, playerObj)
        if playerNum ~= 0 then return end
        local data = getPlayerData and getPlayerData(0)
        local panel = data ~= nil and data.equipped or nil
        if panel == nil or panel.bin2NpcBtn == nil then
            print("[Bin2NPCExtensionVanilla] sidebar icon missing after OnCreatePlayer; using fallback icon")
            Entry.useFallbackIcon(playerObj)
        end
    end)
    return true
end

-- 兜底实现（报告 §7）：独立 ISPanel + 自己的清理事件。这里只留占位，
-- 实现时按 §2.2 的四条缺点逐条补齐（避让宽度、左下角锚点、
-- OnPlayerDeath/OnPostSave/OnResolutionChange 清理）。
function Entry.useFallbackIcon(player)
    if Entry.fallbackInstalled then return end
    Entry.fallbackInstalled = true
    -- TODO: ISPanel:derive("Bin2NpcFallbackIcon") + getPlayerScreenLeft/Top 锚定 + 自己清理
end

if install() then
    print("[Bin2NPCExtensionVanilla] sidebar entry hook installed (vanilla ISEquippedItem)")
end

return NS
```

**骨架里每一处「照抄」的出处**

| 代码片段 | 抄自 |
|---|---|
| `local GAP = 10 + 5` | `ISEquippedItem.lua:4`(`UI_BORDER_SPACING=10`) + `:723,735,753,…`(`+ UI_BORDER_SPACING + 5`) |
| `sidebarTextureWidth()` | `ISEquippedItem.lua:8-25` |
| `getCore():getOptionSidebarSize()` / `getOptionFontSizeReal()` | `ISEquippedItem.lua:9,11` + `Core` javap |
| `ISButton:new(0, y, w, h, "", self, cb)` | `ISEquippedItem.lua:742` |
| 5 行按钮配置 | `ISEquippedItem.lua:743-749`（`setImage` / `initialise` / `instantiate` / `setDisplayBackground(false)` / `ignoreWidthChange` / `ignoreHeightChange`） |
| `self:addMouseOverToolTipItem(btn, text)` | `ISEquippedItem.lua:751` |
| `self:shrinkWrap()` | `ISEquippedItem.lua:969,972-984` |
| `setJoypadFocus(pn, win)` on open | `ISEquippedItem.lua:496-498`；`ISSearchWindow.lua:272-277` |
| `Win.instance` 单例 + `close()` 置 nil | `ISUserPanelUI.lua:184-188,202` |
| `local OLD = Class.method` 后置 hook | 仓库既有：`bin2_nested_containers_take/.../Client.lua:151,183`（`local OLD_start = ...` → 尾部 `return OLD_start(self)`）；`bin2/Contents/mods/NotTheEnd2/.../Token_FuncReplacer.lua` |
| `pcall` 包住外部调用 | `checklists/controller-support-checklist.md:27` |

### 8.2 贴图清单（规格实测确认；资产已由并行任务就绪）

放在 `Bin2NPCExtensionVanilla/42.21/media/ui/Sidebar/<W>/`，**共 5 档 × 2 态 = 10 个 PNG**，尺寸**必须精确**（不是"大约"）：

| 目录 | 文件名 | 像素尺寸（宽 × 高） | 备注 |
|---|---|---|---|
| `48/` | `NPC_Off_48.png` | **48 × 36** | 默认档（1080p + 默认选项）；`Off` = 未打开招募界面 |
| `48/` | `NPC_On_48.png` | **48 × 36** | `On` = 招募界面已打开 |
| `64/` | `NPC_Off_64.png` | **64 × 48** | |
| `64/` | `NPC_On_64.png` | **64 × 48** | |
| `80/` | `NPC_Off_80.png` | **80 × 60** | |
| `80/` | `NPC_On_80.png` | **80 × 60** | |
| `96/` | `NPC_Off_96.png` | **96 × 72** | |
| `96/` | `NPC_On_96.png` | **96 × 72** | |
| `128/` | `NPC_Off_128.png` | **128 × 96** | 只能靠 `sidebarSize == 5` 抵达，但仍必须提供 |
| `128/` | `NPC_On_128.png` | **128 × 96** | |

绘制约定（与原版一致）：

- 格式 PNG，**带 alpha 通道**（原版按钮贴图四周有透明留白；`ISButton:render` 用 `drawTexture` 居中，靠 alpha 叠出图标）。
- 比例严格 **4:3**（`高度 = 宽 × 0.75`）。**不要交正方形**：正方形会被 `drawTextureScaledAspect` 等比缩到 `0.75W` 见方，比原版 Inventory 图标视觉上小一圈（`ISButton.lua:223-226`）。
- 不要给贴图自带按钮底板/边框：原版按钮用 `setDisplayBackground(false)` 关掉了背景（`ISEquippedItem.lua:747`），视觉上只有图标本身。
- 风格参照 `$UI/Sidebar/48/Inventory_Off_48.png`（未激活）与 `Inventory_On_48.png`（激活）的明暗/描边处理。
- 建议同时准备一个 14×14 或 32×32 的小尺寸 PNG 版本，供 §7 的兜底小图标复用。

**翻译键：不需要新增，现有脚手架里已经有了。** 已核实存在（本报告只读，未改动）：

| 文件 | 行 | 键 | 值（CN / EN） |
|---|---|---|---|
| `.../Translate/CN/IG_UI.json` | 28 | `IGUI_Bin2NPCExtensionVanilla_IconTooltip` | `NPC 招募：用原版钞票雇人。快捷键 Ctrl+Alt+N。` |
| 同上 | 22 | `IGUI_Bin2NPCExtensionVanilla_EntryButton` | `NPC 招募` |
| 同上 | 23 | `IGUI_Bin2NPCExtensionVanilla_EntryTooltip` | `…点屏幕左侧的 NPC 图标，或按 Ctrl+Alt+N。` |
| `.../Translate/EN/IG_UI.json` | 28 / 22 / 23 | 同名键（行号相同） | `NPC recruitment: hire with vanilla cash. Hotkey Ctrl+Alt+N.` / `NPC Recruit` / `…Click the NPC icon on the left of the screen, or press Ctrl+Alt+N.` |

注意 `IGUI_Bin2NPCExtensionVanilla_EntryTooltip` 的文案**已经承诺了 `Ctrl+Alt+N` 热键**。
这说明实现里必须以「热键永远可用」为兜底（与 §2.4 / §7 的结论一致）：侧边栏图标是主入口，热键是不依赖任何原版 UI 的退路。

**贴图：现有脚手架的 10 个 PNG 与 §8.2 的规格表逐像素吻合**（实测，见 §3.1 同款命令）：

```
$ cd .../Bin2NPCExtensionVanilla/42.21/media/ui/Sidebar && for f in */*.png; do sips -g pixelWidth -g pixelHeight "$f" | tail -2; done
128/NPC_Off_128.png    128x96      96/NPC_Off_96.png     96x72
128/NPC_On_128.png     128x96      96/NPC_On_96.png      96x72
48/NPC_Off_48.png      48x36       80/NPC_Off_80.png     80x60
48/NPC_On_48.png       48x36       80/NPC_On_80.png      80x60
64/NPC_Off_64.png      64x48
64/NPC_On_64.png       64x48
```

⇒ **贴图与文件命名这一项已经完成，无需再产出**；`Name` 前缀实测就是 `NPC_`，与骨架里 `sidebarTextures()` 拼出的路径
`media/ui/Sidebar/<W>/NPC_Off_<W>.png` / `NPC_On_<W>.png` **完全一致**。

---

## 未证实清单（附验证方法）

| # | 未证实的事 | 为什么没证实 | 验证方法 |
|---|---|---|---|
| 1 | 分屏 player 1+ 的侧边栏实机真的没有按钮列 | 只能从 `ISEquippedItem.lua:737-967` 的 `if` 包夹推断，无法在只读调研里启动 2P 分屏 | 2P 分屏进游戏，观察 2P 侧边栏；或游戏内打印 `getPlayerData(1).equipped:getChildren()` 的长度与 `Type` 分布 |
| 2 | 分屏时 `ISEquippedItem.instance` 实际等于哪一个 panel | 源码只能证明"最后创建者胜出"（`ISEquippedItem.lua:685` + `ISPlayerData.lua:170-174`），不能排除 `getNumActivePlayers()` 的中间态 | 游戏内打印 `ISEquippedItem.instance.playerNum` vs `getPlayerData(0).equipped.playerNum` |
| 3 | 原版面板高度通式 `8W + 135`（§2.1） | 是按 `file:line` 手算的，未实机测量 | 游戏内把 sidebarSize 依次设成 1..5，打印 `getPlayerData(0).equipped:getHeight()` |
| 4 | `42.21/media/ui/...` 版本目录里的新增贴图在本机实机被 `getTexture` 成功解析 | 没有启动游戏；只能给「模组 `media/` 可被解析」的旁证（NotTheEnd2 的 `lightning.png`） | 实现后启动游戏，看 `~/Zomboid/console.txt` 有无缺图告警；或用 debug 的 Texture Viewer 搜 `NPC_On_48` |
| 5 | 是否存在类似 `getOptionHideUi` 的"隐藏 UI"开关 | `grep -rn "HideUi\|setOptionHideUi" $PZ` 零命中；`javap zombie.core.Core` 方法名里也没有 | 全量比对 `javap -p zombie.core.Core` 的方法名；或游戏内 `print(getCore().getOptionHideUi)` 试调用 |
| 6 | 本机 1080p/4K 对应的默认 `TEXTURE_WIDTH` 档 | 没读 `~/Zomboid/options.ini` 的 `fontSize=` / `sidebarSize=` | `grep -n "fontSize=\|sidebarSize=" ~/Zomboid/options.ini`，套 §3.3 的表 |
| 7 | `OnPostSave → destroyAllPlayerData` 之后侧边栏何时重建 | 只证实了 `ISPlayerData.lua:205` 注册了这个销毁，未追踪 `OnCreatePlayer` 在存档后的再次触发时机 | 游戏内手动保存一次，观察侧边栏是否消失/恢复；或在 `OnPostSave` / `OnCreatePlayer` 上各挂一个 `print` |
| 8 | 分屏玩家加入时 `OnCreatePlayer` 的确切触发点与序号 | 只从 `GameLoadingState` 字节码证实了初始加载那一处只发 player 0 | 游戏内挂 `Events.OnCreatePlayer.Add(function(a,b) print(tostring(a), tostring(b)) end)`，加入 2P 观察 |
| 9 | `ISEquippedItem:shrinkWrap()` 覆写是否已被任何在用模组误用三参形式 | 全库只 grep 了游戏本体的 Lua；没有扫描 `~/Zomboid/Workshop` 与 `~/Zomboid/mods` | `grep -rn ":shrinkWrap(" ~/Zomboid/mods ~/Zomboid/Workshop` 后人工筛 `ISEquippedItem` 实例 |

---

## 附：本次调研用到的原始命令清单

```bash
GAME="/Users/liubinbin/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java"
JAVAP=/Users/liubinbin/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javap

# 调用链
cd "$GAME" && grep -rn "launchEquippedItem" media/lua/
cd "$GAME" && grep -rn "ISEquippedItem" media/lua/ | head -40
cd "$GAME" && grep -rn "createInventoryInterface" media/lua/

# 贴图实测尺寸
cd "$GAME" && for d in 48 64 80 96 128; do for f in Inventory_Off Inventory_On; do \
    sips -g pixelWidth -g pixelHeight media/ui/Sidebar/$d/${f}_$d.png | tail -2; done; done

# 扩展点存在性（负结论）
cd "$GAME" && grep -rn "sidebarButtons\|sidebarIcons\|sidebarEntries" media/lua/   # exit 1
cd "$GAME" && grep -rn "setTextureWidth" media/lua/
cd "$GAME" && grep -n "joypad\|Joypad\|onJoypad" media/lua/client/ISUI/ISEquippedItem.lua

# Java 侧
mkdir -p /tmp/pzcls && unzip -o -q projectzomboid.jar 'zombie/core/Core.class' -d /tmp/pzcls
$JAVAP -p -c -v -constants -cp /tmp/pzcls zombie.core.Core | sed -n '/594: putfield.*optionMoodleSize/,/620: /p'
$JAVAP -p -c -cp /tmp/pzcls zombie.core.Core | sed -n '/public int getOptionFontSizeReal/,/public int getOptionMoodleSize/p'
$JAVAP -p -c -cp /tmp/pzlm 'zombie.Lua.LuaManager$GlobalObject' | grep -i PlayerScreen

# OnCreatePlayer 的实参个数（GameLoadingState 里 triggerEvent 的调用点）
mkdir -p /tmp/pzgls && unzip -o -q projectzomboid.jar 'zombie/gameStates/GameLoadingState.class' -d /tmp/pzgls
$JAVAP -p -c -cp /tmp/pzgls zombie.gameStates.GameLoadingState | grep -n "OnCreatePlayer" -B 4 -A 12

# 区分两个同名 shrinkWrap
cd "$GAME" && grep -rn "function IS.*:shrinkWrap" media/lua/

# 版本
grep -n "version=42" ~/Zomboid/console.txt
```
