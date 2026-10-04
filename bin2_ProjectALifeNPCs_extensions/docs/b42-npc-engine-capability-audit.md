# B42 NPC 模组：引擎能给你什么、不能给你什么（字节码取证报告）

环境：macOS，`JAVA_DIR=.../Project Zomboid.app/Contents/Java`，`projectzomboid.jar`（class 主版本 69 / Java 25），
`JDK25=~/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin`。全部为只读分析，临时文件在 `/tmp`。

---

## 1. NPC 相关现成类：类存在，AI 不存在

```bash
cd "$JAVA_DIR" && unzip -l projectzomboid.jar | grep -E 'zombie/' \
  | grep -iE 'npc|survivor|companion|humanai' | awk '{print $1, $4}'
```

```
3277 zombie/characters/IsoSurvivor.class
21442 zombie/characters/SurvivorDesc.class
1432 zombie/characters/SurvivorFactory$SurvivorType.class
5075 zombie/characters/SurvivorFactory.class
1026 zombie/characters/SurvivorGroup.class
3988 zombie/randomizedWorld/randomizedDeadSurvivor/RDSBandPractice.class
... （39 个 RDS* 全是"场景装饰/尸体摆放"，与 NPC 行为无关）
```

【已证实】`IsoSurvivor` 是**空壳**，没有任何 update/AI：

```bash
"$JDK25/javap" -p /tmp/pz/zombie/characters/IsoSurvivor.class
```
```
public final class zombie.characters.IsoSurvivor extends zombie.characters.IsoLivingCharacter {
  public void Despawn();
  public java.lang.String getObjectName();
  public zombie.characters.IsoSurvivor(zombie.iso.IsoCell);
  public zombie.characters.IsoSurvivor(zombie.characters.SurvivorDesc, zombie.iso.IsoCell, int, int, int);
  public void reloadSpritePart();
  public zombie.characters.IsoSurvivor(..., boolean);
}
# grep -c 'void update' → 0
```

构造器**是真活的**（不是残留注释）：`javap -c` 里能看到它把自己加进 `IsoCell.getSurvivorList()`、
触发 `OnCreateSurvivor`、`initWornItems("Human")` / `initAttachedItems("Human")`。
所以"能生成出一个幸存者实体"，但**没有任何驱动它的循环**。

【已证实】B41 的 NPC 事件是**死事件**——只在 `LuaEventManager` 注册，全 jar 无触发点：

```bash
cd /tmp/pzall && for ev in OnNPCSurvivorUpdate OnAIStateEnter OnAIStateExecute OnAIStateExit \
  OnTriggerNPCEvent OnMultiTriggerNPCEvent; do
  printf "%-24s " "$ev"; grep -ral "$ev" --include='*.class' . ; done
```
```
OnNPCSurvivorUpdate       ./zombie/Lua/LuaEventManager      ← 只有注册处
OnAIStateEnter            ./zombie/Lua/LuaEventManager
OnAIStateExecute          ./zombie/Lua/LuaEventManager
OnAIStateExit             ./zombie/Lua/LuaEventManager
OnTriggerNPCEvent         ./zombie/Lua/LuaEventManager ./zombie/iso/IsoMetaCell
OnMultiTriggerNPCEvent    ./zombie/Lua/LuaEventManager ./zombie/iso/IsoMetaCell
```
`OnTriggerNPCEvent` 只在 `IsoMetaCell`（**离屏元格子**）里有触发点，**不在玩家所在格子**触发 ⇒ 不能当 NPC 主循环。
Lua 侧引用数：`grep -rl OnNPCSurvivorUpdate media/lua | wc -l` = **0**。

【已证实】但 `IsoSurvivor` / `SurvivorDesc` / `SurvivorFactory` 都在 Lua 暴露白名单里
（见第 4 节 `LuaManager$Exposer.exposeAll` 常量池，1001 个类）⇒ Lua 侧 `IsoSurvivor.new(...)`、`SurvivorFactory.CreateSurvivor()` 可调。

---

## 2. 僵尸作为 NPC 载体

```bash
"$JDK25/javap" -p /tmp/pz/zombie/characters/IsoZombie.class   # 495 行
```
关键签名（均**已证实**存在）：

| 用途 | 签名 |
| --- | --- |
| 更新入口 | `public void update()`；`private void updateInternal()`；`private void updateActiveState()` |
| 状态注册 | `public void initializeStates()`；`registerAIState(String, State)`（118 次调用）；`clearAIStateMap()` |
| 目标 | `public void setTarget(IsoMovingObject)` / `getTarget()` / `setTargetSeenTime(float)` / `getTargetSeenTime()` |
| 寻路 | `public void pathToCharacter(IsoGameCharacter)` / `pathToLocationF(float,float,float)` / `getPath2()`（继承） |
| 血量 | `getHealth()/setHealth(float)`（继承自 `IsoGameCharacter`），`setImmortalTutorialZombie(boolean)` |
| 停摆开关 | `public void setUseless(boolean)` / `isUseless()` |
| 复生 | `setReanimatedPlayer(boolean)` / `isReanimatedPlayer()` / `getReanimatedPlayer()`；`setReanimate(boolean)`；`setReanimatedForGrappleOnly(boolean)` |
| 倒地 | `setAlwaysKnockedDown(boolean)`；`setKnockedDown(boolean)`（继承） |
| 假死 | `setFakeDead(boolean)` / `isFakeDead()` / `setForceFakeDead(boolean)` |
| 姿势 | `setWalkType(String)` / `setSpeedTypeFromWalkType()` / `crawling` / `lunger` / `running` 公有字段 |
| 吃尸体 | `setEatBodyTarget(IsoMovingObject, boolean[, float])` / `setBodyToEat(IsoDeadBody)` |
| 攻击位 | `getPlayerAttackPosition()` / `setPlayerAttackPosition(String)` |
| 网络 | `getOnlineID()` / `isRemoteZombie()` / `getOwnerPlayer()` / `setOwnerPlayer(IsoPlayer)` |

**AI 驱动链（已证实）**：`IsoZombie.update()` → `updateInternal()`；`OnZombieUpdate` 就触发在 `updateInternal` 内：

```
8685: ldc_w  #3480   // String OnZombieUpdate
8687: invokestatic  zombie/Lua/LuaEventManager.triggerEvent:(Ljava/lang/String;Ljava/lang/Object;)V
```
而 `private void updateActiveState()` 已经**退化成 3 条指令**（只剩 `GameTime.isZombieInactivityPhase()` → `makeInactive()`），
`javap -p -c` 全文：
```
private void updateActiveState();
   0: aload_0
   1: invokestatic  zombie/GameTime.getInstance:()Lzombie/GameTime;
   4: invokevirtual zombie/GameTime.isZombieInactivityPhase:()Z
   7: invokevirtual makeInactive:(Z)V
  10: return
```
⇒ B42 的僵尸 AI 已从"巨型 switch"重构为 **ECS 状态机**：真正的容器是
`zombie/characters/component/StateMachineComponent`（`getStateMachine()` / `registerAIState(String,State)` /
`getDefaultState()` / `getAdvancedAnimator()` / `getActionContext()` / `getMinimumSimulationLevel()`）。
`IsoZombie.registerECSComponents()` 只额外注册 `NetworkZombieComponent`；`StateMachineComponent` 在
`IsoGameCharacter.registerECSComponents()` 里注册。

**状态类清单**：`zombie/ai/states/` 下 100+ 个类，`initializeStates()` 实际注册的状态名字符串（118 次 `registerAIState`）：
```
idle attack attack-network attackvehicle attackvehicle-network bumped climbfence climbwindow
corpseThrown* eatbody face-target fakedead fakedead-attack fakedead-attack-network
falldown* falling getdown getup getup-fromOnBack/OnFront/Sitting grappled
hitreaction* hitreaction-shothead-* knockeddown-* lunge lunge-network onground onground-ragdoll
pathfind reanimate sitting staggerback* thump turn turnalerted vehicleCollision* walktoward walktoward-network
```

**能不能禁掉原版 AI？**
- `setUseless(true)` 是**真开关但覆盖面有限**：`useless` 字段本身只被写一次，读取方限于
  `zombie/ai/states/ZombieIdleState`、`WalkTowardState`、`zombie/ai/ZombieGroupManager`、`NetworkZombieVariables`。
  `ZombieIdleState` 里的读取点：`invokevirtual IsoZombie.isUseless()Z` → 直接 `return`（不做 idle 行为）。
  ⇒ 只压住 idle/walktoward，**不阻止** attack / hitreaction / thump / falldown 等状态。
- `setTarget(null)`：`target` 是 public 字段，`setTarget(IsoMovingObject)` 可传 null ⇒ 断掉追击目标，可行。
- **没有 `bDead` 字段或方法**（`grep -nE 'bDead|setDead' /tmp/isoZombie.txt` → 0 命中）；死亡走继承的 `isDead()` /
  `IsoGameCharacter` 分支。想"停用"一个僵尸，工程上只有 `setUseless(true)` + `setTarget(null)` + `setKnockedDown(true)` 组合，
  或 `setInactive`/`makeInactive`（`inactive` 是 public 字段）——**都不等于"可控 NPC"**。
- 僵尸没有 `getModData()` 的**自有**实现，见第 6 节（继承自 `IsoObject`）。

---

## 3. 玩家/角色可复用能力

`zombie/characters/IsoGameCharacter`（1828 行）里与"像人一样行动"相关的公开方法：
```
632  getHealth() / 633 setHealth(float)
774  setbClimbing(boolean) / 773 isClimbing()
1026 isClimbingThroughWindow(zombie.iso.objects.IsoWindow)
1030 canClimbSheetRope(IsoGridSquare) / 1031 canClimbDownSheetRopeInCurrentSquare() / 1032 canClimbDownSheetRope(IsoGridSquare)
1213 setMoving(boolean)
1237 setPath2(zombie.pathfind.Path)
1337 getHitReaction() / 1338 setHitReaction(String)
1387 isSitOnGround()/setSitOnGround(boolean) / 1389 isSittingOnFurniture()/setSittingOnFurniture(boolean)
1518 setKnockedDown(boolean) / 1517 isKnockedDown()
645  getInventory() / 648 getPrimaryHandItem() / 649 setPrimaryHandItem(InventoryItem)
696  getSecondaryHandItem() / 702 removeFromHands(InventoryItem) / 698 isHandItem(InventoryItem)
712  isSpeaking() / 713 setSpeaking(boolean) / 714 getSpeakTime() / 715 setSpeakTime(int)
882  PlayAnim(String) / 883 PlayAnimWithSpeed(String,float) / 884 PlayAnimUnlooped(String)
1299-1304 setVariable(String,String|boolean|float) / setVariableEnum / setVariable(AnimationVariableHandle,boolean)
1490 getAnimationStateName() / 1491 getActionStateName()
447  getAnimationPlayer() / 450 getAdvancedAnimator()
```
`zombie/characters/IsoPlayer`（瞄准/射击/换弹）：
```
291  nullifyAiming()                    315 getAimVector(Vector2)         324 getAimingMod()
325  getReloadingMod()                  367 private checkReloading()      389 isAiming()
393  isAimControlActive()               411 setAngleFromAim()             458 IsUsingAimWeapon()
475  pressedAim()                       544 playRangedWeaponShootSound(String)
637  OnAnimEvent(AnimLayer, AnimationTrack, AnimEvent)
```
【已证实】**没有公开的 `shoot()` / `reload()` / `openDoor()` / `useItem()`**。
`checkReloading()` 是 private，开火与开门都不是"函数调用"而是 **ActionState + TimedAction** 驱动。
Lua 侧能白嫖的是 `media/lua/shared/TimedActions/`（约 200 个 `IS*` 动作类，含 `ISBaseTimedAction`、`ISOpenDoor`、
`ISClimbThroughWindow`、`ISApplyBandage`、`ISCraftAction`…）+ `media/lua/shared/Vehicles/TimedActions/ISOpenVehicleDoor.lua`。

---

## 4. 动画与状态机：Lua 只能用角色上的"转发方法"

【已证实】Lua 暴露是**白名单**机制。`LuaManager$Exposer.shouldExpose`：
```
public boolean shouldExpose(java.lang.Class<?>);
   0: aload_1 / 1: ifnonnull 6 / 4: iconst_0 / 5: ireturn
   6: aload_0 / 7: getfield exposed:HashSet
  10: aload_1 / 11: invokevirtual HashSet.contains / 14: ireturn
```
`exposeAll()` 常量池中提取到 **1001 个类**（`/tmp/exposed.txt`）：
```
zombie/characters/IsoGameCharacter     zombie/characters/IsoPlayer     zombie/characters/IsoZombie
zombie/characters/IsoSurvivor          zombie/characters/SurvivorDesc  zombie/characters/SurvivorFactory
zombie/characters/SurvivorFactory$SurvivorType   zombie/iso/IsoCell  zombie/iso/IsoGridSquare
zombie/iso/IsoMovingObject             zombie/iso/objects/IsoDeadBody  zombie/Lua/LuaEventManager
zombie/world/moddata/ModData           zombie/pathfind/PathFindBehavior2  zombie/ai/states/PathFindState
```
**不在**白名单（`grep -cE 'AnimationPlayer|AdvancedAnimator|ActionState|action/ActionContext'` → **0**）：
`AnimationPlayer`、`AdvancedAnimator`、`ActionState`/`ActionContext`、`AnimEvent`、`GlobalModData` 本体。
`getAnimationPlayer()` 返回的对象 Lua 拿得到但**调不了方法**（Java 对象方法解析同样走白名单）。

所以 Lua 侧唯一的动画入口是 `IsoGameCharacter` 上的转发方法，**真实游戏 Lua 就是这么用的**：
```bash
grep -rn "PlayAnim\|setVariable(" "$JAVA_DIR/media/lua" | head
# media/lua/shared/Vehicles/TimedActions/ISOpenVehicleDoor.lua:21:  self.character:PlayAnim("Idle")
# media/lua/shared/TimedActions/ISRestAction.lua:81: self.character:setVariable("ExerciseStarted", false);
```
`AnimationPlayer` 本身有 `play(String,boolean)` / `play(StartAnimTrackParameters,AnimLayer)` / `startClip(...)` / `stopAll()`
——**Java 侧可用，纯 Lua 不可用**。
僵尸/角色的动画变量由 `AdvancedAnimator`（`StateMachineComponent.getAdvancedAnimator()`）驱动，
`IsoZombie.updateInternal()` 里显式调用 `AdvancedAnimator.OnAnimDataChanged(Z)`。

---

## 5. Lua 可挂钩事件（264 个，从常量池提取）

```bash
"$JDK25/javap" -p -c -constants /tmp/pz/zombie/Lua/LuaEventManager.class \
  | grep -oE '// String [A-Za-z0-9_]+' | sed 's|// String ||' | sort -u > /tmp/pz_events.txt
wc -l /tmp/pz_events.txt   # 264
```
NPC 开发相关事件 + **触发类**（`grep -ral <event> /tmp/pzall --include='*.class'`）：

| 事件 | 触发点（真实类） | 语义 |
| --- | --- | --- |
| `OnZombieUpdate` | `zombie/characters/IsoZombie`（`updateInternal` 的 696 偏移） | 每只僵尸每帧更新时，**主线程**，参数 = 该 IsoZombie |
| `OnPlayerUpdate` | `zombie/characters/IsoPlayer`（`private boolean updateInternal2()` 内 1141 偏移） | 每帧玩家更新 |
| `OnTick` | `zombie/GameWindow`、`zombie/gameStates/IngameState` | 渲染/逻辑主循环，每帧 |
| `EveryTenMinutes` | `zombie/GameTime`（紧跟 `ErosionMain.EveryTenMinutes()` / `ClimateManager.updateEveryTenMins()`） | 游戏内每 10 分钟 |
| `EveryOneMinute` / `EveryHours` / `EveryDays` | 同名机制（LuaEventManager 注册） | 时间粒度事件 |
| `OnAIStateChange` | `zombie/ai/StateMachine`（`triggerEvent(String,Object,Object,Object)`） | 状态机切换，**唯一活着的 AI 事件** |
| `OnAIStateEnter/Execute/Exit` | **仅 LuaEventManager** | 【已证实】死事件，全 jar 无触发点 |
| `OnZombieCreate` | `zombie/VirtualZombieManager` | 僵尸生成 |
| `OnZombieDead` | `zombie/characters/IsoZombie`、`IsoGameCharacter` | 僵尸死亡 |
| `OnCreateLivingCharacter` | `zombie/characters/IsoPlayer`、`zombie/characters/IsoSurvivor` | 活体角色创建（**NPC 生成可挂**） |
| `OnCreateSurvivor` | `zombie/characters/IsoSurvivor` | IsoSurvivor 构造时（Lua 侧 1 处引用） |
| `OnNPCSurvivorUpdate` | **仅 LuaEventManager** | 死事件 |
| `OnTriggerNPCEvent` / `OnMultiTriggerNPCEvent` | `zombie/iso/IsoMetaCell` | 离屏元格子触发器，不在玩家格子 |
| `OnPostMapLoad` | `zombie/iso/CellLoader` | 地图块加载完成 |
| `OnObjectAdded` | `zombie/network/packets/AddItemToMapPacket`（**注意：只在网络包路径**） | 对象入格 |
| `LoadGridsquare` / `ReuseGridsquare` | `zombie/iso/WorldStreamer`、`IsoChunk`、`IsoChunkMap`、`IsoChunk`… | 格子流式加载 |
| `OnSave` / `OnPostSave` / `OnServerStartSaving` / `OnServerFinishSaving` | `zombie/GameWindow`（`OnSave`） | 存档 |
| `OnCharacterDeath` | `zombie/characters/IsoGameCharacter`、`animals/IsoAnimal` | 角色死亡 |
| `OnInitGlobalModData` | `zombie/world/moddata/GlobalModData` | 全局 ModData 初始化 |
| `OnCreatePlayer` / `OnNewGame` / `OnGameStart` | LuaEventManager 注册 | 开局 |

**线程语义（已证实，`javap -c LuaEventManager`）**：
```
private static boolean IsMainThread();
   0: getstatic zombie/Lua/LuaManager.thread:KahluaThread
   3: getfield  KahluaThread.debugOwnerThread
   6: invokestatic java/lang/Thread.currentThread
   9: if_acmpne 16 ...
```
```
public static void triggerEvent(String);
  27: invokestatic IsMainThread:()Z
  30: ifne 40
  33: aload_2 / 34: invokestatic QueueEvent:(Lzombie/Lua/Event;)V
  37: aload_1 / 38: monitorexit / 39: return
  40: ... Event.trigger(...)      ← 只有主线程才当场执行
```
⇒ **非主线程触发的 Lua 回调被排进 `QueuedEvents`，由 `RunQueuedEvents()` 在主线程延后执行**（对象引用可能已过期，别缓存）。
另：`public static final ArrayList<LuaClosure> OnTickCallbacks` 是可直接操作的热路径。

---

## 6. 持久化

【已证实】`IsoZombie` / `IsoGameCharacter` **没有自己的** `getModData()`；它来自 **`zombie.iso.IsoObject`**：
```bash
"$JDK25/javap" -p /tmp/pz/zombie/iso/IsoObject.class | grep -i moddata
```
```
public se.krka.kahlua.vm.KahluaTable getModData();
public void setModData(se.krka.kahlua.vm.KahluaTable);
public boolean hasModData();
public void transmitModData();
```
（链：`IsoObject` → `IsoMovingObject` → `IsoGameCharacter` → `IsoZombie`/`IsoPlayer`。`grep -n ModData /tmp/igc.txt`
在 `IsoGameCharacter` 上只有 `setMusicIntensityEventModData`——即 `getModData` 是 **IsoObject 层**的能力。）

全局存档：
```
zombie/world/moddata/GlobalModData:
  SAVE_EXT, SAVE_FILE, instance
  init()/reset()/exists(String)/getOrCreate(String)/get(String)/create([String])/remove(String)
  add(String,KahluaTable)/collectTableNames(List)/transmit(String)/request(String)/receiveRequest(...)
  save()/load()
zombie/world/moddata/ModData:   ← Lua 静态门面（在白名单内）
  getTableNames/exists/getOrCreate/get/create/remove/add/transmit/request
```
`OnInitGlobalModData` 正是由 `GlobalModData` 触发。

Lua 写文件（`LuaManager$GlobalObject`）：
```
public static LuaFileWriter getFileWriter(String, boolean, boolean)
public static LuaFileWriter getModFileWriter(String, String, boolean, boolean)
public static BufferedReader getFileReader(String, boolean)
public static BufferedReader getModFileReader(String, String, boolean)
```
`getFileWriter` 的路径基准是 `LuaManager.getLuaCacheDir()`，且先校验 `LuaManager.ALLOWED_FILE_EXTENSIONS`
（扩展名不在白名单直接失败）；`getModFileWriter` 用 `ChooseGameInfo.getModDetails(modId).getCommonDir()`，
**写回 mod 自身目录**——Workshop 场景不可靠。【建议】自建数据走 `getFileWriter("MyMod/xxx.txt", true, true)`
（落到 Lua 缓存目录，即存档侧的 Lua 目录）或 `ModData`/`GlobalModData`。

`zombie/savefile/` 只有 `PlayerDB` / `ServerPlayerDB` / `ClientPlayerDB` / `AccountDBHelper` / `SavefileNaming` /
`SavefileThumbnail`——**没有任何 NPC 存档层**。

---

## 7. 性能护栏

【已证实】`IsoCell.getZombieList()` **直接返回引擎内部 list 本体，不是副本**：
```
public java.util.ArrayList<zombie.characters.IsoZombie> getZombieList();
   0: aload_0
   1: getfield  #206  // Field zombieList:Ljava/util/ArrayList;
   4: areturn
```
`getSurvivorList()` 同理（`final ArrayList<IsoSurvivor> survivorList`，包可见字段）。
对比：`IsoCell` 另有 `public List<IsoMovingObject> getObjectListForLua()` 与 `getObjectList():Set`——**只有它们带 ForLua/拷贝语义**。

⇒ 结论：
- Lua 遍历 `getCell():getZombieList()` 是**在直接读引擎的活 list**；引擎同帧若 add/remove 会 `ConcurrentModificationException` 或漏项；
  **绝对不能**对它 `add/remove/clear`（会破坏引擎状态）。安全姿势：只读 + 立刻拷进自己的表，或按 id/坐标回查。
- 无任何"分帧""限流""只给可见僵尸"的 Java 侧保护（`getZombieList` 是整个 cell 的 list，含远处僵尸）。
- 线程语义见第 5 节：`OnTick`（`GameWindow`/`IngameState` 触发）、`EveryTenMinutes`（`GameTime` 触发）都在主线程；
  跨线程事件走队列后仍在主线程跑 ⇒ **Lua 里没有并发，但有"同一帧的预算"**。
  护栏只能自己写：`EveryTenMinutes` 做重决策、`OnTick` 只做常数时间的事、每帧只处理 N 个僵尸（自己的轮转指针）。

---

## 8. ZombieBuddy：能力与边界

【已证实】本机已安装：
```bash
unzip -p "$JAVA_DIR/ZombieBuddy.jar" META-INF/MANIFEST.MF | head -6
# Premain-Class: me.zed_0xff.zombie_buddy.Agent
# Can-Redefine-Classes: true
# Can-Retransform-Classes: true
# Implementation-Version: 2.3.4        ← 不是 skill 里记的 2.3.2
```
工坊内容：`~/Library/Application Support/Steam/steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy`
（`doc/LuaAPI.md`、`doc/ModdingGuide.md`）。

包结构：
```
me/zed_0xff/zombie_buddy/*                核心（Loader, Agent, Config, Exposer, PatchEngine,
                                          PatchTransformer, Patch, EventsAPI, WatchesAPI,
                                          JavaModInfo, ModApprovalsStore, SteamWorkshop, LuaUtils）
me/zed_0xff/zombie_buddy/patches/*         Patch_Core/Display/Exposer/GameWindow/GameServer/
                                          GameLoadingState/ZomboidFileSystem
me/zed_0xff/zombie_buddy/patches/experimental/*  Patch_LuaEventManager, Patch_LuaManager,
                                          Patch_KahluaThread, Patch_IngameState, LuaJson, HttpServer,
                                          JavaStateDumper, ZBEventLog, ZBPacketLog, Patch_InventoryItem…
net/bytebuddy/**, io/github/classgraph/**, zb/org/bouncycastle/**   （内嵌）
```

**Lua 可用（来自 `doc/LuaAPI.md`）**：
- `ZombieBuddy.Events.getAll() / getByName(name) / getByFile(file)`、`ZombieBuddy.Events.<EventName>`
- `ZombieBuddy.Watches.Add(class, method) / Remove / Clear`（**可监控任意 Java 方法调用及其参数**，实验性）
- `ZombieBuddy.getVersion() / getClosureInfo() / getCallableInfo() / getClosureFilename()`

**Java 侧（真正的杠杆）**：
- `me.zed_0xff.zombie_buddy.Exposer.exposeClass(Class|String) / exposeMethod(Class,String) /
  exposeClassToLua / exposeAnnotatedClasses(pkg)` + 注解 `@Exposer.LuaClass`、
  `@LuaMethod(name=..., global=true)`（`se.krka.kahlua.integration.annotations.LuaMethod`）
  ⇒ **可以把引擎没暴露给 Lua 的类（`AnimationPlayer`、`ActionState`、私有方法）挂上去**。
- `PatchEngine.applyPatches(pkg, classLoader)` + `me.zed_0xff.zombie_buddy.Patch`
  （ByteBuddy `Advice.*` 别名）⇒ 任意引擎方法前后插桩 / 整体替换。
- `Loader` 有 Jar 审批策略（`POLICY_PROMPT / POLICY_DENY_NEW / POLICY_ALLOW_ALL`、`g_known_jars`、`ModApprovalsStore`）
  ⇒ Java 补丁需人工审批（见 skill 的 tinyfd 平台坑）。

**边界判定**：

| 需求 | 纯 Lua + 僵尸载体 | ZombieBuddy Java 补丁 |
| --- | --- | --- |
| 生成/销毁实体、换装、动画、说话 | ✅（`IsoZombie`、`PlayAnim`、`setVariable`、`IsoSurvivor`） | — |
| 每帧决策、感知、寻路 | ✅（`OnZombieUpdate` + `getZombieList` + `pathToLocationF`） | — |
| 关掉/改写原版僵尸 AI 某状态 | ❌（只能 `setUseless`/`setTarget(null)`/`setKnockedDown` 打补丁式压制） | ✅（`@Patch` `ZombieIdleState`/`StateMachine` 等） |
| 新增 AI 状态、给角色加组件 | ❌（`registerAIState` 不在 Lua 暴露面；`StateMachineComponent` 未暴露） | ✅（Java 内直接调，或插桩 `initializeStates`） |
| 用 `AnimationPlayer`/`ActionState` 细粒度控制 | ❌（未暴露） | ✅（`Exposer.exposeClass`） |
| 每帧 per-zombie 独立回调 | ❌（只有全局 `OnZombieUpdate`，参数 = 当前那只） | ✅（插桩 `IsoZombie.update`） |
| 交付成本 | 低（无构建、无审批、无版本脆性） | 高（Java 构建 + Jar 签名/审批 + 每次游戏更新重验） |

---

## 给从零开发者的引擎结论

1. **B42 没有任何可用的 NPC AI**。`IsoSurvivor` 类还在、能被 Lua new 出来、能进世界、能触发 `OnCreateSurvivor`，
   但**没有 update、没有状态机、没有寻路**——B41 的 NPC 代码是被"摘掉 AI 后留了壳"。
2. **必须自己实现的**：感知（视觉/听觉）、决策/行为树、群体调度、路径请求节流、目标选择、逐帧轮转、
   存档结构、与玩家的交互/命令 UI、性能预算。引擎不会替你做任何一件。
3. **僵尸是唯一"现成的活动载体"**，但它的 AI 是**状态机内的硬编码**：
   `IsoZombie.update()` → `updateInternal()`；`updateActiveState()` 已空。可用 `setUseless(true)`（只压 idle/walktoward）、
   `setTarget(null)`、`setKnockedDown(true)`、`inactive` 字段组合把僵尸"冻住"，再自己驱动位置/动画。
4. **白嫖得动的**：模型/贴图/装备（`initWornItems`）、`PlayAnim` + `setVariable`（动画变量系统）、
   `getPath2/setPath2`、`pathToLocationF`、`IsoGridSquare` 全套查询、`IsoDeadBody`、
   Lua 侧 ~200 个 `IS*TimedAction`、`GameTime`、`ModData`/`GlobalModData`。
5. **Lua 暴露是白名单（1001 类），`AnimationPlayer`/`AdvancedAnimator`/`ActionState`/`StateMachineComponent`/
   `GlobalModData` 本体全部不在**。想要细粒度动画或状态机控制，**必须**走 Java 补丁（ZombieBuddy `Exposer`）或放弃。
6. **走不通的路**：`OnAIStateEnter/Execute/Exit`、`OnNPCSurvivorUpdate` 是**死事件**（注册但无触发点）；
   `OnTriggerNPCEvent` 只在离屏 `IsoMetaCell`，不能当主循环；`getZombieList()` 返回活 list 本体，
   别改它、别在遍历里缓存对象。
7. **没有 NPC 存档层**：`zombie/savefile/` 只有玩家/账号 DB。NPC 状态自己存——
   `IsoObject.getModData()`（随实体走）、`GlobalModData`（全局、有 `OnInitGlobalModData`）、
   或 `getFileWriter` 写 Lua 缓存目录（注意 `ALLOWED_FILE_EXTENSIONS` 校验；`getModFileWriter` 写回 mod 目录，Workshop 不可靠）。
8. **线程模型是安全的、但不是免费的**：非主线程触发的 Lua 回调被 `QueueEvent` 排队延后执行（`IsMainThread` = 与
   `KahluaThread.debugOwnerThread` 同线程）。`OnTick`/`EveryTenMinutes` 都在主线程，**护栏只能自己写**。
9. **决策树**：纯 Lua + 僵尸载体做"批量简单 NPC"边界清晰、交付最省；要"新物种 AI/精确动画/改原版僵尸行为"，
   就得接受 ZombieBuddy Java 补丁的构建 + 审批 + 版本脆性成本。
10. **本机 ZB 是 2.3.4**（`Implementation-Version`），提供 `Exposer.exposeClass/exposeMethod`、`@Exposer.LuaClass`、
    `@LuaMethod(global=true)`、`@Patch`（Advice/Delegation）、`ZombieBuddy.Events/Watches` ——
    这是把第 5 条"路走不通"变成"走得通"的唯一现成工具。

**未验证/推测项**：① `inactive` 字段与 `makeInactive(true)` 是否足以完全阻止僵尸被 `update`，未做运行时实验；
② `getObjectListForLua()` 是否真是拷贝（仅按命名与签名推断）；
③ 未实机启动游戏，所有结论来自字节码；`OnTick` 是否每渲染帧调用由 `GameWindow`/`IngameState` 的调用点推断。
