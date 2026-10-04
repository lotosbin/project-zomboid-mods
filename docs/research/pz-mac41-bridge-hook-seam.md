# pz-mac41-bridge.jar：外部补 5 个 GL4.3 函数（glVertexAttribFormat 家族）的可行性证据档

* 工作目录：`/tmp/mac41/a/`
* 分析对象（只读，未修改）：
  `/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/108600/3812168749/mods/ViewpointMac41Patch/common/tools/payload/pz-mac41-bridge.jar`
* 目标 sha256：`85c45fd301d1aafd81e60d14ab26c25e6eead46352335b974748f1a20f0d850f`
* JDK：`/Users/liubinbin/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javap`（游戏 class 主版本 69 → 必须 25）
* 探针 JRE：`~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/PlugIns/jre-aarch64/Contents/Home/bin/java`（Zulu 25.0.1）
* 游戏 jar（只读）：`~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java/projectzomboid.jar`
* **没有启动游戏本体**，全部为静态反汇编 + 一个不创建 GL 上下文的 Java 探针。

## 0. 先决核对

```bash
$ shasum -a 256 ".../payload/pz-mac41-bridge.jar"
85c45fd301d1aafd81e60d14ab26c25e6eead46352335b974748f1a20f0d850f  .../pz-mac41-bridge.jar

$ cat jar/META-INF/MANIFEST.MF
Manifest-Version: 1.0
Premain-Class: pzmac41.Agent
Can-Redefine-Classes: false
Can-Retransform-Classes: false

$ javap -p jar/pzmac41/CoreGl.class | head -3
public final class pzmac41.CoreGl {
```

桥的关键 private 成员（javap -p，节选）：

```
  private static org.lwjgl.system.FunctionProvider base;
  private static org.lwjgl.PointerBuffer table;
  private static final java.util.Map<java.lang.String, java.lang.Long> hooks;
  private static final java.util.List<java.lang.Object> keep;
  public static org.lwjgl.opengl.GLCapabilities capabilities(org.lwjgl.opengl.GLCapabilities);
  private static org.lwjgl.opengl.GLCapabilities install(org.lwjgl.opengl.GLCapabilities) throws java.lang.Exception;
  private static long real(java.lang.String);
  private static void hook(java.lang.String, org.lwjgl.system.CallbackI);
  private static void registerHooks();
  private static org.lwjgl.PointerBuffer lambda$install$0(int);
  private static void lambda$traceHooks$45(long, int, int, long);
```

注意两处与任务描述不同的**实测事实**：

1. `CoreGl.table` **从未被赋值**——全类里没有 `putstatic Field table`（见 §3c），是死字段。
2. `registerHooks()` 只注册 **63** 个名字，不是 172。172 是 `CoreGl.class` 常量池中所有 `gl[A-Z]*` Utf8 串的数量（含 `traceHooks()` 的 46 个、以及 `DEPRECATED_TRACE` 的那一大串名字）。见 §5.3。

---

## 1. 时序：谁在什么时候调 `registerHooks()` / `install()` / `capabilities()`（Q1）

### 1.1 结论（调用链，全部由字节码逐跳确认）

```
[游戏] org/lwjglx/opengl/Display.create()            ← 由 RenderThread / MainScreenState 在 GL 初始化时调用
   ├─ GLFW.glfwCreateWindow(...)  被 Agent 改写成 → pzmac41/Bridge.createWindow(...)
   │     └─ Bridge.windowHints() → CoreGl.windowHints()
   │           GLFW_CONTEXT_VERSION 4.1 / OPENGL_CORE_PROFILE / OPENGL_FORWARD_COMPAT=1，并置 hinted=true
   └─ GL.createCapabilities()     被 Agent 改写成 → pzmac41/Bridge.createCapabilities()
         └─ CoreGl.coreRequested() == hinted
         └─ GL.createCapabilities(true)                     ← 真驱动 caps（nativeCaps）
         └─ Bridge.setNativeCapabilities(nativeCaps)
         └─ CoreGl.capabilities(nativeCaps)                 ← 【就是这个方法被外部调用】
               ├─ CoreGl.install(nativeCaps)
               │     ├─ base = GL.getFunctionProvider()
               │     ├─ Bridge.setNativeCapabilities(caps)
               │     ├─ 收集 glGetStringi(GL_EXTENSIONS) → CoreGl.exts / CoreGl.extensionsString
               │     ├─ registerHooks()                     ← 【注册表在这里才被填充】
               │     ├─ GL.createCapabilities(true, lambda$install$0)   ← 用 hooks 构造“模拟 caps”
               │     ├─ initState()                          ← glGenVertexArrays() → defaultVao
               │     └─ CoreGl.active = true
               └─ Log.info("macGlCore: OpenGL …, GLSL …; core bridge on (%d implemented callbacks, …)")
```

### 1.2 字节码证据

**(a) `Agent.patch` 的改写点**（`javap -p -c pzmac41/Agent.class`，`patch` 方法）

```
// org/lwjglx/opengl/Display 的 create() 里：
885: getfield  MethodInsnNode.name      -> "createCapabilities"
899: getfield  MethodInsnNode.desc      -> "()Lorg/lwjgl/opengl/GLCapabilities;"
913: ldc_w     #327 // String pzmac41/Bridge
916: putfield  MethodInsnNode.owner     <- owner 改成 pzmac41/Bridge
...
941: name == "glfwCreateWindow"  →  owner := pzmac41/Bridge, name := "createWindow"   (offset 955-966)
```

**(b) `org/lwjglx/opengl/Display.create()` 的两个调用点**（游戏 jar 内，未打补丁的原始字节码）

```bash
$ cd /tmp/mac41/a/pz && unzip -o -q projectzomboid.jar 'org/lwjglx/opengl/Display.class'
$ "$JAVAP" -p -c org/lwjglx/opengl/Display.class > ../dis/Display.dis
$ grep -nE "glfwCreateWindow|GL.createCapabilities" ../dis/Display.dis
       198: invokestatic  #210   // Method org/lwjgl/glfw/GLFW.glfwCreateWindow:(IILjava/lang/CharSequence;JJ)J
       299: invokestatic  #258   // Method org/lwjgl/opengl/GL.createCapabilities:()Lorg/lwjgl/opengl/GLCapabilities;
```

即 `capabilities(GLCapabilities)` 的**唯一游戏侧调用者**是 `org.lwjglx.opengl.Display.create()`（间接经 `Bridge.createCapabilities()`）。
**不是** `zombie/core/opengl/VBORenderer`：`Agent.patch` 对 `VBORenderer` 只把 `renderRun()` 里的 `GL12.glDrawRangeElements` 改写成 `Bridge.drawRangeElements`。VBORenderer 里没有任何指向 `pzmac41` 的调用点。

**(c) `Bridge.createCapabilities()`（bridge 内）**

```bash
$ javap -p -c pzmac41/Bridge.class | sed -n '/public static org.lwjgl.opengl.GLCapabilities createCapabilities();/,/^  public static org.lwjgl.opengl.GLCapabilities pzoptCapabilities/p'
  public static org.lwjgl.opengl.GLCapabilities createCapabilities();
    Code:
         0: invokestatic  #64   // Method active:()Z
         3: ifeq          16
         6: new           #68   // class java/lang/IllegalStateException
        10: ldc           #70   // String Context bridge already installed
...
        22: invokestatic  #85   // Method pzmac41/CoreGl.coreRequested:()Z
        25: invokestatic  #88   // Method org/lwjgl/opengl/GL.createCapabilities:(Z)Lorg/lwjgl/opengl/GLCapabilities;
        28: astore_0
        29: aload_0
        30: invokestatic  #94   // Method setNativeCapabilities:(Lorg/lwjgl/opengl/GLCapabilities;)V
        33: aload_0
        34: invokestatic  #98   // Method pzmac41/CoreGl.capabilities:(Lorg/lwjgl/opengl/GLCapabilities;)Lorg/lwjgl/opengl/GLCapabilities;
```

**(d) `CoreGl.capabilities()` 与 `install()` 的关键偏移**

```bash
$ awk '/^  public static org.lwjgl.opengl.GLCapabilities capabilities/,/^  private static long real/' dis/CoreGl.dis
  public static org.lwjgl.opengl.GLCapabilities capabilities(org.lwjgl.opengl.GLCapabilities);
    Code:
         0: getstatic     #286   // Field hinted:Z
         3: ifne          8
         6: aload_0
         7: areturn                ← hinted==false（非 Mac / shim 关）时原样返回，安装根本不发生
         8: ldc_w         #299   // int 37158            ← GL_CONTEXT_FLAGS
        11: invokestatic  #300  // GL11C.glGetInteger
        18: ifeq          28
        21: aload_0
        22: getfield      #306   // GLCapabilities.OpenGL32:Z
        25: ifne          48
        28: ... Log.warn("macGlCore: the context is not a core profile (…), shim off")
        42: iconst_1
        43: putstatic     #269   // Field fellBack:Z
        46: aload_0
        47: areturn
        48: aload_0
        49: invokestatic  #319   // Method install:(Lorg/lwjgl/opengl/GLCapabilities;)Lorg/lwjgl/opengl/GLCapabilities;
...
        65: getstatic     #216   // Field hooks:Ljava/util/Map;
        68: invokeinterface #324 // Map.size:()I          ← 日志里的 “%d implemented callbacks”
```

```bash
$ sed -n '700,756p' dis/CoreGl.dis        # install()
  private static org.lwjgl.opengl.GLCapabilities install(org.lwjgl.opengl.GLCapabilities) throws java.lang.Exception;
    Code:
         0: invokestatic  #368   // GL.getFunctionProvider()
         3: putstatic     #372   // Field base
         6: aload_0
         7: invokestatic  #376   // pzmac41/Bridge.setNativeCapabilities
        10: getstatic     #209   // Field exts
        13: invokeinterface #213 // Set.clear
        18: ldc_w         #381   // int 33309  (GL_NUM_EXTENSIONS)
        21: invokestatic  #300   // GL11C.glGetInteger
        ...
        35: loop glGetStringi(7939=GL_EXTENSIONS, i) → exts.add / StringBuilder.append
        78: ... StringBuilder.toString().trim()
        85: iconst_1
        86: invokestatic  #407   // MemoryUtil.memUTF8(CharSequence, boolean)
        89: invokestatic  #411   // MemoryUtil.memAddress(ByteBuffer)
        92: putstatic     #183   // Field extensionsString
        95: invokestatic  #415   // Method registerHooks:()          <<<< 注册表填充点
        98: iconst_1
        99: invokedynamic #418   // IntFunction  -> lambda$install$0
       104: invokestatic  #422   // GL.createCapabilities(Z, IntFunction)
       107: astore_3
       108: invokestatic  #426   // Method initState:()
       111: iconst_1
       112: putstatic     #126   // Field active:Z
       115: aload_3
       116: invokestatic  #429   // pzmac41/Bridge.setEffectiveCapabilities
       119: aload_3
       120: areturn
```

### 1.3 相对 javaagent premain 的顺序

* `pzmac41.Agent.premain` 只做三件事：`verifyPremain(instrumentation)`、`addTransformer(new Agent$1())`、`Log.info("Agent ready; …")`。它**不碰** `CoreGl`。
* 因此 `hooks` / `exts` / `base` / `active` 在 premain 阶段全部为空：`hooks` 只在 `registerHooks()`（即 `install()` 内、GL 初始化时）被填充。
* 所以：**注册表是在游戏 GL 初始化（`Display.create()`）时才读取并填充的，不是在 premain 阶段。**
* 这一点正是外部注入的机会窗口：只要你的代码在 `Display.create()` 之前跑（任何后续 `-javaagent` 的 premain 都满足），你写进 `hooks` 的内容会被 `install()` 原样采用。

**安装器给出的真实 javaagent 顺序**（`common/tools/source/Installer.java`，第 226-227、278-279 行）：

```java
optionsList.add("-javaagent:"+finalApp.resolve("Contents/Java/pz-mac41-bridge.jar"));
optionsList.add("-javaagent:"+finalApp.resolve("Contents/Java/ZombieBuddy.jar")+"=config_dir="+...,+",frontend=console");
...
List<String> agents=options.stream().filter(x->x.startsWith("-javaagent:")).toList();
require(agents.size()==2 && agents.get(0).contains("pz-mac41-bridge.jar") && agents.get(1).contains("ZombieBuddy.jar"),"Ordem de agentes incorreta.");
```

→ 桥的 premain 在 ZombieBuddy 之前；`-javaagent` 按命令行顺序执行 premain，且都早于 `main()`。**追加第 3 个 `-javaagent` 就是天然可用的注入挂点**。

（注意 `Installer.validateApp()` 第 160 行会**拒绝**源 app 的 Info.plist 里出现 `-javaagent:` / `-Dpzopt.` / `-Dpzbaseline.`，所以不能改原 app；安装器是克隆出一个独立 app 再往克隆的 plist 里写 agent 的。）

---

## 2. 注册表可变性：`install()` 到底是“逐名查 hooks”还是“遍历固定名单”（Q2）

### 2.1 `lambda$install$0` 只做一件事：把 `hooks` + `base` 交给 `CapabilitySlots.allocate`

```bash
$ sed -n '8106,8112p' dis/CoreGl.dis
  private static org.lwjgl.PointerBuffer lambda$install$0(int);
    Code:
         0: iload_0                                              ← int 参数 = LWJGL 要求的槽位总数
         1: getstatic     #216   // Field hooks:Ljava/util/Map;
         4: getstatic     #372   // Field base:Lorg/lwjgl/system/FunctionProvider;
         7: invokestatic  #1987  // Method pzmac41/CapabilitySlots.allocate:(ILjava/util/Map;Lorg/lwjgl/system/FunctionProvider;)Lorg/lwjgl/PointerBuffer;
        10: areturn
```

### 2.2 `CapabilitySlots.allocate(int, Map, FunctionProvider)` 全貌

```bash
$ javap -p -c pzmac41/CapabilitySlots.class
  static org.lwjgl.PointerBuffer allocate(int, java.util.Map<java.lang.String, java.lang.Long>, org.lwjgl.system.FunctionProvider);
    Code:
         0: iload_0
         1: sipush        2236
         4: if_icmpeq     21
         7: new #17  // IllegalStateException
        11: iload_0
        12: invokedynamic #132  // "LWJGL table changed: \u0001"
        20: athrow
        21: iload_0
        22: invokestatic  // PointerBuffer.allocateDirect(I)     ← 长度 2236，全 0
        ...
        // 阶段 1：遍历传入的 hooks 映射，逐名查 SLOTS，写对应槽位
        49: aload_1
        50: invokeinterface Map.entrySet
        ...
        84: getstatic     #147  // Field SLOTS:Ljava/util/Map;
        87: ... Map$Entry.getKey
        94: invokeinterface Map.get:(Ljava/lang/Object;)Ljava/lang/Object;
        99: checkcast     java/lang/Integer
       102: astore 6
       104: aload 6
       106: ifnull 127
       109: ... getValue → Long.longValue()
       124: lcmp 0
       124: ifne 150
       127: new IllegalStateException
       133: invokedynamic  // "Invalid implemented callback \u0001"
       149: athrow                                             ← 名字不在 SLOTS 或地址为 0 ⇒ 直接抛
       150: aload_3                                              ← table
       151: aload 6  (slot)
       156: aload 5 → getValue → longValue
       169: PointerBuffer.put(IJ)
        // 阶段 2：遍历 SLOTS 自身，只为 *ARB / *EXT 名字做别名回填（核心名存在 hooks 则用 hooks，
        //         否则 provider 查不到时用反射去 nativeCapabilities 里取）
        176: getstatic     #147 // Field SLOTS
        225: name.endsWith("ARB") || name.endsWith("EXT"); 且 !name.contains("Object")
        255: core = name.substring(0, len-3)
        270: hooks.get(core) != null → table.put(arbSlot, hooksAddr)
        314: base.getFunctionAddress(fullName) == 0 → nativeAddress(core) → table.put(...)
        // 阶段 3：硬编码 glTextureBarrier ← glTextureBarrierNV
        364: SLOTS.get("glTextureBarrier")
        379: ldc "glTextureBarrierNV"; invokestatic nativeAddress    ← 无条件调用（要求 nativeCaps != null）
        411: table.put(barrierSlot, nv)
        423: areturn
```

**关键点：非 hooks、非 ARB/EXT 的名字，`allocate()` 一个都不填（保持 0）。** 那些槽位靠 LWJGL 自己在构造 `GLCapabilities` 时通过 `Checks.checkFunctions` 回填（见 2.4）。

### 2.3 `table` 长度 = 2236，槽位索引来自 `CapabilitySlots.SLOTS`，而它与 `GLCapabilities` 内联的索引一致

`GLCapabilities.SLOTS` 由 jar 内 `pzmac41/capability-slots.properties` 载入，并**强校验条数 2233**：

```bash
$ javap -p -c pzmac41/CapabilitySlots.class | sed -n '/private static java.util.Map<java.lang.String, java.lang.Integer> load();/,/private static long nativeAddress/p' | grep -nE "sipush +2233|IllegalStateException|Map.copyOf|getResourceAsStream"
  2: ldc  #9   // String capability-slots.properties
 97: aload_2
 98: invokeinterface Map.size
103: sipush        2233
106: if_icmpeq     128
109: new #17  // IllegalStateException
119: invokedynamic #80  // "Invalid pinned LWJGL function map: \u0001"
128: aload_2
129: invokestatic  // Map.copyOf      ← 不可变副本，外部改不了 SLOTS
```

`GLCapabilities.this.<init>` 对**每一个** GL 函数都无条件做 `addresses.get(固定槽位)`（这是编译器生成的内联常量，不查名字表）：

```bash
$ grep -n "     16[01][0-9][0-9]:" dis/GLCapabilities.dis | sed -n '1,40p'
12369:      16063: aload_0
12370:      16064: aload         5
12371:      16066: sipush        907
12372:      16069: invokevirtual #898  // Method org/lwjgl/PointerBuffer.get:(I)J
12373:      16072: putfield      #1806   // Field glBindVertexBuffer:J
12374:      16075: aload_0
12375:      16076: aload         5
12376:      16078: sipush        908
12377:      16081: invokevirtual #898  // Method org/lwjgl/PointerBuffer.get:(I)J
12378:      16084: putfield      #1807   // Field glVertexAttribFormat:J
12379:      16087: aload_0
12380:      16088: aload         5
12381:      16090: sipush        909
12382:      16093: invokevirtual #898  // Method org/lwjgl/PointerBuffer.get:(I)J
12383:      16096: putfield      #1808   // Field glVertexAttribIFormat:J
12384:      16099: aload_0
12385:      16100: aload         5
12386:      16102: sipush        910
12387:      16105: invokevirtual #898  // Method org/lwjgl/PointerBuffer.get:(I)J
12388:      16108: putfield      #1809   // Field glVertexAttribLFormat:J
12389:      16111: aload_0
12390:      16112: aload         5
12391:      16114: sipush        911
12392:      16117: invokevirtual #898  // Method org/lwjgl/PointerBuffer.get:(I)J
12393:      16120: putfield      #1810   // Field glVertexAttribBinding:J
12394:      16123: aload_0
12395:      16124: aload         5
12396:      16126: sipush        912
12397:      16129: invokevirtual #898  // Method org/lwjgl/PointerBuffer.get:(I)J
12398:      16132: putfield      #1811   // Field glVertexBindingDivisor:J
```

对照表（两边完全一致，`grep` 自 `pzmac41/capability-slots.properties`）：

| 函数名 | capability-slots.properties | GLCapabilities 构造内联槽位 |
| --- | --- | --- |
| glBindVertexBuffer | 907 | 907 |
| glVertexAttribFormat | 908 | 908 |
| glVertexAttribIFormat | 909 | 909 |
| glVertexAttribLFormat | 910 | 910 |
| glVertexAttribBinding | 911 | 911 |
| glVertexBindingDivisor | 912 | 912 |
| glDrawArraysInstancedBaseInstance | 864 | 864 |
| glDrawElementsInstancedBaseVertexBaseInstance | 866 | 866 |
| glMultiDrawArraysIndirect | 894 | 894 |
| glMultiDrawElementsIndirect | 895 | 895 |
| glVertexAttribPointer | 530 | 530 |

### 2.4 hook 值优先于真驱动：`Checks.checkFunctions` 的 `continue`

```bash
$ javap -p -c org/lwjgl/system/Checks.class | sed -n '/checkFunctions(org.lwjgl.system.FunctionProvider, org.lwjgl.PointerBuffer, int\[\], java.lang.String...)/,/^  public static boolean checkFunctions(org.lwjgl.system.FunctionProviderLocal/p'
  public static boolean checkFunctions(org.lwjgl.system.FunctionProvider, org.lwjgl.PointerBuffer, int[], java.lang.String...);
    Code:
         0: iconst_1
         1: istore        4                              // result = true
        19: iload         6
        21: iflt          72                             // slot < 0 ⇒ skip（可选函数）
        24: aload_1
        25: iload         6
        27: invokevirtual PointerBuffer.get:(I)J
        30: lconst_0
        31: lcmp
        32: ifeq          38
        35: goto          72                             // ★ 槽位已非 0 ⇒ 直接用，不再问 provider
        38: aload_0
        39: aload_3
        40: iload         5
        42: aaload
        43: invokeinterface FunctionProvider.getFunctionAddress
        48: lstore        7
        50: lload         7
        52: lconst_0
        53: lcmp
        54: ifne          63
        57: iconst_0
        58: istore        4                              // 找不到 ⇒ result = false
        60: goto          72
        63: aload_1
        64: iload         6
        65: lload         7
        66: invokevirtual PointerBuffer.put:(IJ)          // 回填进同一张表
```

### 2.5 实测（探针 `Probe.java`，不创建 GL 上下文）

完整输出见附录 B。要点：

```
[2] hooks modifiers=private static final type=java.util.Map
[3] setAccessible(hooks) OK; BEFORE size=0 impl=java.util.HashMap (registerHooks/install not run)
[5] setAccessible(hook) OK; canAccess=true
[6] CapabilitySlots.SLOTS size=2233 SIZE=2236
[8] unknown name rejected: java.lang.IllegalStateException: Invalid implemented callback pzNotARealFunction
[9] zero address rejected: java.lang.IllegalStateException: Invalid implemented callback glVertexAttribFormat
[10] wrong size rejected: java.lang.IllegalStateException: LWJGL table changed: 10

--- PHASE A: hooks EMPTY, provider = today's macOS (无 GL4.2/4.3 入口) ---
[11] OpenGL41=false OpenGL42=false OpenGL43=false        （探针的 provider 只回 ARB/EXT，故 41 也 false）
      capsA.glVertexAttribFormat           = 0x0
      capsA.glVertexAttribIFormat          = 0x0
      capsA.glVertexAttribBinding          = 0x0
      capsA.glVertexBindingDivisor         = 0x0
      capsA.glBindVertexBuffer             = 0x0

--- PHASE B: 同一个 provider，但 5 个名字事先经 CoreGl.hook() 注册 ---
[12] hook(glVertexAttribFormat) -> null
...
[13] hooks AFTER size=5
[14] OpenGL42=false OpenGL43=false
      capsB.glVertexAttribFormat           = 0x1122334455667788 (expect 0x1122334455667788)  table[908]=0x1122334455667788
      capsB.glVertexAttribIFormat          = 0x1122334455667789 (expect 0x1122334455667789)  table[909]=0x1122334455667789
      capsB.glVertexAttribBinding          = 0x112233445566778a (expect 0x112233445566778a)  table[911]=0x112233445566778a
      capsB.glVertexBindingDivisor         = 0x112233445566778b (expect 0x112233445566778b)  table[912]=0x112233445566778b
      capsB.glBindVertexBuffer             = 0x112233445566778c (expect 0x112233445566778c)  table[907]=0x112233445566778c

--- PHASE C: provider 变成“什么都有”的驱动 ---
[15] OpenGL43=true
      capsC.glVertexAttribFormat           = 0x1122334455667788  <- hook value, provider NOT consulted
      capsC.glMultiDrawArraysIndirect      = 0xaa00000000000000  <- checkFunctions filled from provider
      capsC.glVertexAttribPointer          = 0xaa00000000000000  <- checkFunctions filled from provider
```

### 2.6 Q2 结论

* `install()` **不是**只遍历固定名单：它把整个可变 `Map<String,Long> hooks` 交给 `CapabilitySlots.allocate`，后者**逐条遍历该映射**并按名字查 `SLOTS` 落槽。
* 因此：**在 `install()` 之前把一个新名字塞进 `hooks`，就能让对应的 `GLCapabilities` 字段拿到非零地址**——探针 PHASE B 已端到端验证（`capsB.glVertexAttribFormat == 0x1122334455667788`，而 provider 对它是 0）。
* 前提两条，缺一即失败（都是 `IllegalStateException`，会**中止整个桥的安装**）：
  1. 名字必须存在于 `capability-slots.properties`（5 个目标名字都在，槽位 907–912）；
  2. `hooks` 的值必须非 0。
* 另有一个容易误判的点（PHASE B 的 `[14]`）：即使 5 个字段非零，`caps.OpenGL43` 仍然是 **false**，因为 `check_GL43` 需要那 43 个槽位全部非零。**但这对实际调用毫无影响**——`GL43C.glVertexAttribFormat` 的 native 桩只读槽位 908，不看 `OpenGL43`。


---

## 3. 最小注入手段：4 条路线逐条判定（Q3 a–d）

### 3.a 反射调 `CoreGl.hook(String, CallbackI)`（private static）— **可行（已验证）**

```java
Class<?> coreGl = Class.forName("pzmac41.CoreGl");
Field hooksF = coreGl.getDeclaredField("hooks"); hooksF.setAccessible(true);
Map<String,Long> hooks = (Map<String,Long>) hooksF.get(null);

Method hookM = coreGl.getDeclaredMethod("hook", String.class, CallbackI.class);
hookM.setAccessible(true);
hookM.invoke(null, "glVertexAttribFormat", myCallbackI);
```

探针原始输出：

```
[4] hook = private static void pzmac41.CoreGl.hook(java.lang.String,org.lwjgl.system.CallbackI) modifiers=private static
[5] setAccessible(hook) OK; canAccess=true
[12] hook(glVertexAttribFormat) -> null
[13] hooks AFTER size=5
```

为什么 `setAccessible` 一定成功：桥的类是通过 `-javaagent:` 追加到**系统类加载器**搜索路径、并且在**未命名模块（unnamed module）**里的；外部 agent 的类同样是系统类加载器的未命名模块成员。未命名模块之间没有 `exports`/`opens` 边界，`AccessibleObject.setAccessible(true)` 一律成功（没有 SecurityManager 时）。

`hook()` 的字节码（顺带说明它为什么比直接 `put` 更安全）：

```bash
$ sed -n '775,790p' dis/CoreGl.dis
  private static void hook(java.lang.String, org.lwjgl.system.CallbackI);
    Code:
         0: getstatic     #250   // Field keep:Ljava/util/List;
         3: aload_1
         4: invokeinterface #441 // List.add          ← ★ 强引用进 keep，防 GC 回收 upcall stub
        10: getstatic     #216   // Field hooks:Ljava/util/Map;
        13: aload_0
        14: aload_1
        15: invokeinterface #442 // CallbackI.address()
        20: invokestatic  #447  // Long.valueOf
        23: invokeinterface #450 // Map.put
        29: return
```

**失败模式（重要）**：如果 `CallbackI.address()` 返回 0，`CapabilitySlots.allocate` 阶段 1 会抛
`IllegalStateException: Invalid implemented callback <name>`，`install()` 直接失败 →
`capabilities()` 的 catch 把 `GL.setCapabilities(native)` 回滚并抛
`Core bridge installation failed; restart explicitly with bridge disabled`。
**即：这条路线是 fail-closed 的——你的一个 bug 会让整个桥装不上，游戏起不来。**

### 3.b 直接往 `hooks` Map 里 `put` — **可行（已验证），但不推荐单独使用**

* 字段：`private static final java.util.Map<String,Long> hooks`。
  **final 只限制字段本身不可重新赋值，不限制 Map 内容**；实测实现类是 `java.util.HashMap`：
  ```
  [2] hooks modifiers=private static final type=java.util.Map
  [3] setAccessible(hooks) OK; BEFORE size=0 impl=java.util.HashMap (registerHooks/install not run)
  ```
* 拿引用的方法：`Field.setAccessible(true)` + `Field.get(null)`（静态字段传 `null`）→ 已验证。
* 也可以像探针的负例那样直接 `hooks.put(...)`（`[8]`/`[9]` 就是走这条路）。
* **两个坑**：
  1. 绕过 `hook()` 就不会进 `keep`。LWJGL 的 upcall stub 由 `CallbackI` 实例懒创建并持有，
     如果外部没有自己的强引用，stub 可能被 GC → 悬空函数指针 → 崩溃。
     **必须自己用一个 static List 持有全部 callback 对象**。
  2. `releaseCallbacks()` 会遍历 `hooks.values()` 逐个 `Callback.free(addr)` 然后 `hooks.clear()`/`keep.clear()`：

     ```bash
     $ sed -n '514,536p' dis/CoreGl.dis
       static void releaseCallbacks();
            0: getstatic #216  // hooks
            3: Map.values() → iterator
           29: checkcast java/lang/Long
           32: Long.longValue()
           37: invokestatic org/lwjgl/system/Callback.free:(J)V
           43: hooks.clear()
           51: keep.clear()
     ```
     如果你也 `free` 同一个地址 → double free。**别自己 free**。

### 3.c `install()` 之后改地址表 — **对 native 调用路径有效，对 Java 字段无效（已验证/by construction）**

**(1) `CoreGl.table` 是死字段，用不了。** 全类搜索没有任何 `putstatic Field table`：

```bash
$ grep -n "Field table:Lorg/lwjgl/PointerBuffer" dis/CoreGl.dis
(无输出)
```

但 **公开 API** 就能拿到同一张表：

```java
PointerBuffer live = org.lwjgl.opengl.GL.getCapabilities().getAddressBuffer(); // public
live.put(908, closureAddress);
```

（`GLCapabilities.getAddressBuffer()` / `GL.getCapabilities()` / `GL.setCapabilities()` 都是 `public`：

```bash
$ javap -p org/lwjgl/opengl/GL.class | grep -E "getCapabilities|setCapabilities"
  public static void setCapabilities(org.lwjgl.opengl.GLCapabilities);
  public static org.lwjgl.opengl.GLCapabilities getCapabilities();
$ javap -p org/lwjgl/opengl/GLCapabilities.class | grep getAddressBuffer
  public org.lwjgl.PointerBuffer getAddressBuffer();
```）

**(2) 有没有“太晚”？分两半看：**

* **Java 侧字段：太晚。** 构造函数在最后一步之前已经把每个槽位读进 `public final long` 字段：

  ```bash
  $ sed -n '19001,19010p' dis/GLCapabilities.dis
       31975: aload_0
       31976: aload         5
       31978: invokestatic  #3132  // ThreadLocalUtil.setupAddressBuffer:(Lorg/lwjgl/PointerBuffer;)Lorg/lwjgl/PointerBuffer;
       31981: putfield      #3133  // Field addresses:Lorg/lwjgl/PointerBuffer;
       31984: return
  ```
  探针实测：
  ```
  [19] before: caps.glVertexAttribFormat = 0x1122334455667788
  [19] after table.put(908,0x9999): caps.glVertexAttribFormat = 0x1122334455667788  (final long already copied)
  [16] caps.glVertexAttribFormat modifiers=public final type=long
  [17] Field.setLong on final SUCCEEDED -> 0xdead
  ```
  想改 Java 可见值必须再反射写那个 `final long` **实例**字段——**Java 25 下实例 final 字段的 `Field.setAccessible(true)+setLong` 是允许的**（静态 final 不允许），探针 `[17]` 已成功。

* **native 侧：不算太晚。** LWJGL 3.4 存的是**指针**而不是拷贝：

  ```bash
  $ javap -p -c org/lwjgl/opengl/GL.class | sed -n '/public static void setCapabilities(org.lwjgl.opengl.GLCapabilities)/,/areturn/p'
    public static void setCapabilities(org.lwjgl.opengl.GLCapabilities);
         0: getstatic     #58  // GL.capabilitiesTLS
         3: aload_0
         4: ThreadLocal.set
        15: aload_0
        16: getfield      #60  // GLCapabilities.addresses
        19: invokestatic  #61  // MemoryUtil.memAddress(CustomBuffer)
        22: invokestatic  #62  // ThreadLocalUtil.setCapabilities:(J)V   ← 只传指针
        25: getstatic     #6   // GL.icd
        28: aload_0
        29: invokeinterface GL$ICD.set
  ```

  ```bash
  $ javap -p -c org/lwjgl/system/ThreadLocalUtil.class | sed -n '/public static void setCapabilities(long)/,/^  public static void setFunctionMissingAddresses/p'
    public static void setCapabilities(long);
         0: getThreadJNIEnv()
         4: MemoryUtil.memGetAddress(env)          ← env 数据块
        10: if (caps == 0) { env[CAPABILITIES_OFFSET] = FUNCTION_MISSING_ABORT_TABLE; }
        63: env[CAPABILITIES_OFFSET] = caps       ← 把指针存进当前线程的 env 数据
  ```
  即：**每个线程的 env 数据里存的是 caps 表的地址**，GL 的 native 桩调用时通过这个指针 + 第 2 节那张“函数名→固定槽位”表索引取值。**改表 = 改 native 真正会跳转的目标。**

**(3) 还有一条极关键的、决定了“为什么报告里是 FATAL ERROR 而不是 SIGSEGV”的机制：**

```bash
$ sed -n '/public static org.lwjgl.PointerBuffer setupAddressBuffer/,/^  public static boolean areCapabilitiesDifferent/p' <(javap -p -c org/lwjgl/system/ThreadLocalUtil.class)
  public static org.lwjgl.PointerBuffer setupAddressBuffer(org.lwjgl.PointerBuffer);
    Code:
         0: aload_0
         1: PointerBuffer.position()
         5: loop i = pos .. limit-1
        13: aload_0
        14: iload_1
        15: PointerBuffer.get:(I)J
        18: lconst_0
        19: lcmp
        20: ifne          32
        23: aload_0
        24: iload_1
        25: getstatic     #24  // Field FUNCTION_MISSING_ABORT:J
        28: PointerBuffer.put:(IJ)                  ← ★ 0 槽位全部替换成 “缺失即 abort” 桩
```

`GLCapabilities.<init>` 的最后一步就是 `this.addresses = ThreadLocalUtil.setupAddressBuffer(addresses)`。
`FUNCTION_MISSING_ABORT` 指向的原生桩会打印
`FATAL ERROR in native method: … No context is current or a function that is not available in the current context was called. The JVM will abort execution.`
——与 bug 报告里的栈完全一致。

**推论**：`install()` 之后再 `table.put(908, myClosure)` 就是**用真地址覆盖那个 abort 桩**。对 native 调用路径而言，这条路是**成立**的，而且它是 **fail-open** 的（不做/做错都不影响桥自检）。

探针相关输出：

```
[18] caps.addresses IS the PointerBuffer our IntFunction returned: true
     memAddress(caps.addresses) = 0x772f4be000
[19] PointerBuffer put(908,..) after GLCapabilities construction succeeded -> buffer is writable
[20] setupAddressBuffer applied at GLCapabilities construction: slot 894 (missing) = 0x… while caps.glMultiDrawArraysIndirect = 0x0
```

（`[20]` 那条正是 Phase A：字段是 0，表里已经是 abort 桩。）

**唯一的时序问题**：`table` 只有在 `Bridge.createCapabilities()` 跑完之后才存在（`install()` 里创建），
必须在第一次 `GL43C.glVertexAttribFormat` 之前完成写入。桥没有暴露“装好了”的回调，
所以要么用 3.a（在 install 之前写 `hooks`，天然没有时序问题），要么用自己的 agent 去 transform 一个
游戏类（例如在 `zombie/core/opengl/RenderThread.renderLoop` 入口插一句自己的 bootstrap），
或者干脆等 `CoreGl.active == true` 的第一次机会。**推荐 3.a。**

### 3.d 桥有没有留配置/系统属性/附加 jar 扩展点 — **没有（已验证）**

Config 全部内容：

```bash
$ cat dis/Config.dis
  static {};
         0: ldc  #7   // String os.name                        System.getProperty
        15: ldc  #31  // String pzmac41.enabled   default "true"  → MAC_GL_CORE
        28: ldc  #43  // String pzmac41.trace     default "false" → DEV_CORE_GL_TRACE
        41: ldc  #50  // String pzmac41.timerQueries default "false" → MAC_GL_TIMER_QUERIES
```

全 jar 常量池 dump（`javap -v -p` 所有 `pzmac41/*.class` 的 Utf8 串）中的关键字命中：

```bash
$ for f in pzmac41/*.class; do javap -v -p "$f"; done | grep -oE '= Utf8 .*' | sed 's/= Utf8 //' | sort -u > strings/utf8-uniq.txt
$ wc -l strings/utf8-uniq.txt
1863
$ grep -nE 'getProperty|getenv|pzmac41\.|hooks|extra|\.properties|appendToSystem|premain|agentmain|javaagent|ServiceLoader|META-INF' strings/utf8-uniq.txt
513:              Bridge premain version gate rejected \u0001
527:              capability-slots.properties
543:              class-pins.properties
708:              getProperty
977:              hooks
1429:              premain
1482:              pzmac41.enabled
1483:              pzmac41.timerQueries
1484:              pzmac41.trace
```

* 无 `-Dpzmac41.extra`、无插件加载、无 `ServiceLoader`、无 `getenv` 使用（`System.getenv` 在字节码里出现 2 次，但都是 `LWJGL`/`MemoryUtil` 相关，pzmac41 自身的可配项只有上面 3 个属性——`grep -hoE 'Method java/lang/System\.(getenv|getProperty)'` 的结果里 `getProperty` 共 6 次，全部集中在 `Config`）。
* `Agent.TARGETS` 是写死的 5 个类：

  ```bash
  $ awk '/^  static \{\};/,0' dis/Agent.dis
         0: ldc_w  #374  // String org/lwjglx/opengl/Display
         3: ldc_w  #409  // String zombie/core/opengl/VBORenderer
         6: ldc_w  #419  // String zombie/core/opengl/ShaderProgram
         9: ldc_w  #434  // String zombie/core/fonts/AngelCodeFont
        12: ldc    #202  // String pzopt/CoreGl
        14: invokestatic Set.of
  ```
  其中 `pzopt/CoreGl` 是**唯一允许不存在**的（`verifyPremain` 里 `name.equals("pzopt/CoreGl")` 时跳过），
  而本机 `projectzomboid.jar` 里**根本没有 `pzopt/CoreGl.class`**：

  ```bash
  $ unzip -l "$PZ/projectzomboid.jar" | grep -c pzopt/CoreGl
  0
  $ grep -c pzmac41 "$PZ/projectzomboid.jar"     # 游戏 jar 内不含任何 pzmac41 引用
  0
  ```
  → `pzopt` facade 那条补丁分支在这个版本里是死代码；`capabilities()` 的调用者是 `pzmac41.Bridge` 自身（见 §1.2(c)）。
* 桥也**没有**任何“外部可写”的公开注册 API：`CoreGl.hook` 是 private，`CoreGl` 没有 public 的 `addHook`/`register`。


---

## 4. 回调怎么造（Q4）

### 4.1 桥的回调创建方式

`hook(String, CallbackI)` 只做两件事：把 callback 塞进 `keep`，并把 `CallbackI.address()` 放进 `hooks`（见 §3.a）。
真正的“造回调”全在那些内层接口的 `<clinit>` / `default` 方法里。`CoreGl$VIIII` 完整反汇编：

```bash
$ javap -p -c 'jar/pzmac41/CoreGl$VIIII.class'
interface pzmac41.CoreGl$VIIII extends org.lwjgl.system.CallbackI {
  public static final org.lwjgl.system.Callback$Descriptor DESC;

  public default org.lwjgl.system.Callback$Descriptor getDescriptor();
    Code:
         0: getstatic     #1   // Field DESC:Lorg/lwjgl/system/Callback$Descriptor;
         3: areturn

  public default void callback(long, long);
    Code:
         0: aload_0
         1: lload_3                       ← args
         2: iconst_0
         3: invokestatic  #7   // Method pzmac41/CoreGl.ai:(JI)I
         6: lload_3
         7: iconst_1
         8: invokestatic  #7
        11: lload_3
        12: iconst_2
        13: invokestatic  #7
        16: lload_3
        17: iconst_3
        18: invokestatic  #7
        21: invokeinterface #13 // InterfaceMethod invoke:(IIII)V
        26: return

  public abstract void invoke(int, int, int, int);

  static {};
    Code:
         0: new           #17  // class org/lwjgl/system/Callback$Descriptor
         3: dup
         4: invokestatic  #19  // MethodHandles.lookup()   ← 接口自己的 lookup
         7: getstatic     #25  // Field pzmac41/CoreGl.V:Lorg/lwjgl/system/libffi/FFIType;
        10: iconst_4
        11: anewarray     #29  // FFIType[4]
        16: getstatic     #31  // Field pzmac41/CoreGl.I:Lorg/lwjgl/system/libffi/FFIType;   ×4
        38: invokestatic  #34  // APIUtil.apiCreateCIF(FFIType, FFIType...)
        41: invokespecial #40  // Callback$Descriptor.<init>(Lookup, FFICIF)
        44: putstatic     #1   // Field DESC
```

`CoreGl$VIIIZIP`（6 参数）同构，只是 `callback` 多一个 `CoreGl.az(args,3)` / `CoreGl.ap(args,5)`，
`invoke` 变成 `(IIIZIJ)V`。

用到的 LWJGL API（全部是**公开**的，外部可以用同一套）：

| 环节 | API | 证据 |
| --- | --- | --- |
| 参数类型 | `org.lwjgl.system.libffi.LibFFI.ffi_type_sint32 / ffi_type_uint8 / ffi_type_pointer / ffi_type_void` | `CoreGl.<clinit>` 594-627 |
| 建 CIF | `org.lwjgl.system.APIUtil.apiCreateCIF(FFIType ret, FFIType... args)` | 上面的 `<clinit>` |
| 描述符 | `new org.lwjgl.system.Callback$Descriptor(MethodHandles.Lookup, FFICIF)`（public ctor） | 同上 |
| 取函数地址 | `CallbackI.address()` default → `org.lwjgl.system.Upcalls.upcallCreate(Descriptor, Object)` | `javap -p -c org/lwjgl/system/CallbackI.class` |
| 底层 | LWJGL 3.4：`Upcalls.upcallCreate` → `LibFFI.ffi_closure_alloc` + `Upcalls.getBinder` → `org.lwjgl.system.ffm.FFM.ffmUpcall` → `BCCallUp` | 探针异常栈 `BCCallUp.<init>(BCCallUp.java:52)` |
| 参数读取 | `CoreGl.arg(args,i) = memGetAddress(args + i*Pointer.POINTER_SIZE)`，再 `memGetInt/memGetByte/memGetFloat/memGetDouble/memGetAddress` | `CoreGl.arg/ai/az/ap/af/ad` 字节码 |

**两个必须知道的硬性约束（都实测/实测式验证）**：

1. **upcall 接口必须带 `@FunctionalInterface`**。LWJGL 3.4 的新 FFM upcall binder 会检查：
   ```
   $ javap -v -p 'jar/pzmac41/CoreGl$VIIII.class' | grep -A3 RuntimeVisibleAnnotations
   RuntimeVisibleAnnotations:
     0: #59()
       java.lang.FunctionalInterface
   ```
   探针里一开始漏了注解，直接命中：
   ```
   Exception in thread "main" java.lang.UnsupportedOperationException: The upcall interface must be annotated with @FunctionalInterface
        at org.lwjgl.system.ffm.BCCallUp.<init>(BCCallUp.java:52)
        at org.lwjgl.system.ffm.FFM.ffmUpcall(FFM.java:697)
        at org.lwjgl.system.Upcalls.lambda$getBinder$1(Upcalls.java:149)
        at org.lwjgl.system.CallbackI.address(CallbackI.java:23)
   ```
2. **`CallbackI.address()` 不是幂等的**。探针：
   ```
   [22] externally declared @FunctionalInterface CallbackI (void(int,int,int,boolean,int)): 0x11c336240 stable=false
   [23] external class in package pzmac41 implementing CoreGl$VIIII: 0x11c355980 stable=false
   ```
   连续两次 `address()` 得到**不同**地址（每次都新建一个 upcall stub）。所以：**只调一次，把 long 缓存起来**。
   桥的 `hook()` 恰好只调一次，因此没问题；如果你自己 `put`，务必别重复调 `address()`。

   另外桥的内层接口都带 `NestHost: pzmac41/CoreGl`（这就是 `callback()` 默认方法能调用 `CoreGl` 的 **private static** `ai/ap/az` 的原因）。外部类**不可能**成为这个 nest 的成员，所以拿不到 `CoreGl.ai`——但也不需要：`memGetAddress(args + i*8)` 一行就等价。

### 4.2 桥里**所有** `CoreGl$*` 内层类型及其 `invoke` 签名

```bash
$ javap -p 'jar/pzmac41/CoreGl$VIIII.class' | head -3
interface pzmac41.CoreGl$VIIII extends org.lwjgl.system.CallbackI {
  public abstract void invoke(int, int, int, int);
```
（下表由同样的方式对每个 `CoreGl$*.class` 提取 `invoke` 得到）

| 类 | invoke 签名 | 类 | invoke 签名 |
| --- | --- | --- | --- |
| `CoreGl$I0` | `int ()` | `CoreGl$VIIII` | `void(int,int,int,int)` |
| `CoreGl$II` | `void(int,int)` | `CoreGl$VIIIII` | `void(int,int,int,int,int)` |
| `CoreGl$PI` | `long(int)` | `CoreGl$VIIIIIP` | `void(int,int,int,int,int,long)` |
| `CoreGl$V0` | `void()` | `CoreGl$VIIIIP` | `void(int,int,int,int,long)` |
| `CoreGl$V10I` | `void(int×10)` | `CoreGl$VIIIP` | `void(int,int,int,long)` |
| `CoreGl$V10IP` | `void(int×10,long)` | `CoreGl$VIIIPI` | `void(int,int,int,long,int)` |
| `CoreGl$V11` | `void(int×10,long)` | `CoreGl$VIIIZIP` | `void(int,int,int,boolean,int,long)` |
| `CoreGl$V6D` | `void(double×6)` | `CoreGl$VIIP` | `void(int,int,long)` |
| `CoreGl$V6I` | `void(int×6)` | `CoreGl$VIIPP` | `void(int,int,long,long)` |
| `CoreGl$V6IP` | `void(int×6,long)` | `CoreGl$VIIZP` | `void(int,int,boolean,long)` |
| `CoreGl$V8I` | `void(int×8)` | `CoreGl$VIP` | `void(int,long)` |
| `CoreGl$V8IP` | `void(int×8,long)` | `CoreGl$VP` | `void(long)` |
| `CoreGl$VDD` | `void(double,double)` | `CoreGl$VZ` | `void(boolean)` |
| `CoreGl$VDDD` | `void(double×3)` | `CoreGl$VZZZZ` | `void(boolean×4)` |
| `CoreGl$VDDDD` | `void(double×4)` | `CoreGl$ZI` | `boolean(int)` |
| `CoreGl$VF` | `void(float)` | `CoreGl$VI` | `void(int)` |
| `CoreGl$VFF` | `void(float,float)` | `CoreGl$VIF` | `void(int,float)` |
| `CoreGl$VFFF` | `void(float×3)` | `CoreGl$VIFF` | `void(int,float,float)` |
| `CoreGl$VFFFF` | `void(float×4)` | `CoreGl$VIFFF` | `void(int,float×3)` |
| `CoreGl$VII` | `void(int,int)` | `CoreGl$VIFFFF` | `void(int,float×4)` |
| `CoreGl$VIIF` | `void(int,int,float)` | `CoreGl$VIII` | `void(int,int,int)` |

（非回调的内层类型：`CoreGl$Frame`、`CoreGl$GL11`、`CoreGl$GL14`、`CoreGl$Prog`、`CoreGl$VirtualState`）

### 4.3 目标 5 个函数的签名匹配

| GL 函数 | C 原型 | 需要的 invoke | 桥里有吗 |
| --- | --- | --- | --- |
| `glVertexAttribFormat` | `void(GLuint,GLint,GLenum,GLboolean,GLuint)` | `void(int,int,int,boolean,int)` | **没有**。最接近 `CoreGl$VIIIZIP` = `void(int,int,int,boolean,int,long)`（尾部多一个 long） |
| `glVertexAttribIFormat` | `void(GLuint,GLint,GLenum,GLuint)` | `void(int,int,int,int)` | ✅ `CoreGl$VIIII` |
| `glVertexAttribLFormat`（可选） | 同上 | `void(int,int,int,int)` | ✅ `CoreGl$VIIII` |
| `glVertexAttribBinding` | `void(GLuint,GLuint)` | `void(int,int)` | ✅ `CoreGl$VII` |
| `glVertexBindingDivisor` | `void(GLuint,GLuint)` | `void(int,int)` | ✅ `CoreGl$VII` |
| `glBindVertexBuffer` | `void(GLuint,GLuint,GLintptr,GLsizei)` | `void(int,int,long,int)` | **没有**。最接近 `CoreGl$VIIPP` = `void(int,int,long,long)`（尾部多一个 long）；`CoreGl$VIIIPI` 多一个前导 int |

**关于“尾部多一个参数”能否凑合**：CIF 声明 6 个整型参数而调用方只传 5 个，被多读的那个参数在
aarch64 上是 `x5`、x86-64 SysV 上是 `r9`，调用方（LWJGL 生成的 native 桩）不会去设它 ⇒ 读到垃圾值，
只要不把它当指针解引用就无害。
**这是按 ABI 推理的结论，我没有真实 GL 上下文可以执行验证**（探针只证明了 closure 能创建、地址非零）。
不建议依赖；**正确做法是自己声明精确签名的接口**。

### 4.4 桥里有可复用的 `glVertexAttribPointer` / `glVertexAttribDivisor` / `glBindBuffer` 实现吗？

有，但要分清“hook”和“real”：

* **不 hook**，而是解析成**真驱动地址**（`registerHooks()` 尾部）：
  ```
      1106: ldc_w #853  // String glEnableVertexAttribArray
      1109: invokestatic  #456  // real:(Ljava/lang/String;)J
      1112: putstatic     #855  // Field rEnableVAA:J
      1115: ldc_w #858  // String glDisableVertexAttribArray  → rDisableVAA
      1124: ldc_w #863  // String glBindBuffer               → rBindBuffer
      1133: ldc_w #868  // String glVertexAttribPointer      → rVertexAttribPointer
      1142: ldc_w #873  // String glVertexAttribDivisor      → rVertexAttribDivisor
  ```
  `real()` 在查不到地址时会抛 `IllegalStateException("macGlCore: no driver entry point …")`（`registerHooks` 共 49 个 `real()`）。
* **内部已有等价逻辑**（`private static`，可用但需反射）：
  ```bash
  $ sed -n '4484,4499p' dis/CoreGl.dis      # attrib(int index, int size, int type, long ptr)
    private static void attrib(int, int, int, long);
         0: iload_0
         1: getstatic     #855  // Field rEnableVAA:J
         4: invokestatic  #918  // JNI.callV:(IJ)V
         7: iload_0
         8: iload_1
         9: sipush        5126                // GL_FLOAT
        12: iconst_0
        13: iload_2
        14: lload_3
        15: getstatic     #870  // Field rVertexAttribPointer:J
        18: invokestatic  #1368 // JNI.callPV:(IIIIIJJ)V
  $ sed -n '4616,4628p' dis/CoreGl.dis      # vertexPointer(int,int,int,long)
       0: iconst_0
       1: iload_0
       ... rVertexAttribPointer
  ```
  以及 `CoreGl.bindVertexArray(int)`（把 `0` 映射成虚拟 `defaultVao`）：
  ```bash
  $ sed -n '1998,2027p' dis/CoreGl.dis
    private static void bindVertexArray(int);
         9: iload_0
        10: ifne          19
        13: getstatic     #155   // Field defaultVao:I
        16: goto          20
        19: iload_0
        20: getstatic     #490   // Field rBindVertexArray:J
        23: invokestatic  #918   // JNI.callV:(IJ)V
  ```
  这些是 `private static` + nestmate，外部**不能直接调**；反射可用（`setAccessible` 对所有静态 private 成员都成功，探针已对 `hook`/`hooks` 验证过同一机制）。
  更简单的替代：`GL.getFunctionProvider().getFunctionAddress("glVertexAttribPointer")`（public）自己 `JNI.callPV`。

### 4.5 “最省事”的做法（推荐）

自己声明**精确签名**的 upcall 接口，完全不碰桥的内部类型：

```java
@FunctionalInterface
public interface VAttribFormat extends CallbackI {
    Callback.Descriptor DESC = new Callback.Descriptor(
        MethodHandles.lookup(),
        APIUtil.apiCreateCIF(LibFFI.ffi_type_void,
            LibFFI.ffi_type_sint32, LibFFI.ffi_type_sint32, LibFFI.ffi_type_sint32,
            LibFFI.ffi_type_uint8,  LibFFI.ffi_type_sint32));
    @Override default Callback.Descriptor getDescriptor() { return DESC; }
    @Override default void callback(long ret, long args) {
        invoke((int) arg(args,0), (int) arg(args,1), (int) arg(args,2),
               MemoryUtil.memGetByte(args + 3L*Pointer.POINTER_SIZE) != 0, (int) arg(args,4));
    }
    static long arg(long a, int i) { return MemoryUtil.memGetAddress(a + (long)i*Pointer.POINTER_SIZE); }
    void invoke(int attribindex, int size, int type, boolean normalized, int relativeoffset);
}
```

探针里这个接口（`RealCb.java`）编译通过并且真的产出了原生 upcall 地址：
```
[22] externally declared @FunctionalInterface CallbackI (void(int,int,int,boolean,int)): 0x11c336240
```

**若一定要复用桥的内层接口**：把实现类放在 `package pzmac41`（同一 classloader / 同一 unnamed module 下包私有可见），
运行时是能用的：
```
[23] external class in package pzmac41 implementing CoreGl$VIIII: 0x11c355980
[24] external CoreGl$VII closure = 0x11c437800 ; external CoreGl$VIIIZIP (6-arg, extra long) closure = 0x11c338b00
```
但 **javac 在这个包上很挑**：实测
* 一次 `javac` 编译 3 个 `pzmac41/*.java`，只有**第 1 个**能解析 `CoreGl$VII`，其余报 `找不到符号: 类 CoreGl$VII`；
* 逐个 `javac` 编译则**全部成功**。

```bash
$ javac -sourcepath ext -cp "$CP" -d out ext/pzmac41/ExtCb.java ext/pzmac41/ExtCbBind.java ext/pzmac41/ExtCbPtr.java
ext/pzmac41/ExtCbBind.java:2: 错误: 找不到符号
public final class ExtCbBind implements CoreGl$VII { public void invoke(int a,int b) { } }
                                        ^
  符号: 类 CoreGl$VII
ext/pzmac41/ExtCbPtr.java:2: 错误: 找不到符号
public final class ExtCbPtr implements CoreGl$VIIIZIP {
                                       ^
  符号: 类 CoreGl$VIIIZIP
$ for n in ExtCbBind ExtCbPtr; do javac -sourcepath ext -cp "$CP" -d out2 ext/pzmac41/$n.java; done
ExtCbBind -> ExtCbBind.class
ExtCbPtr -> ExtCbPtr.class
```

→ 要么每个文件单独编译，要么直接用 **ASM 生成 class 字节码**（桥 jar 里自带 `org/objectweb/asm` 全部类）绕过 javac 的可见性检查。

