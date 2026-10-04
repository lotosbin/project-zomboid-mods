# LWJGL 3.4.1-snapshot GL 4.3 运行期补函数 —— 机制取证报告

工作目录：`/tmp/mac41/c/`
游戏未被修改，未启动游戏。所有结论均附「可复现命令 + 原始输出」。

工具：
```
JDK25=/Users/liubinbin/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin
PZ="$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java"
JRE="$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/PlugIns/jre-aarch64/Contents/Home/bin/java"
BRIDGE="$HOME/Library/Application Support/Steam/steamapps/workshop/content/108600/3812168749/mods/ViewpointMac41Patch/common/tools/payload/pz-mac41-bridge.jar"
```

---

## 0. 摘要（先给结论）

| # | 问题 | 结论 |
|---|---|---|
| 1 | GL43C 地址如何解析 | **本快照既没有 `static long glVertexAttribFormat` 字段，也没有 `<clinit>`**。`GL43C.glVertexAttribFormat` 是 `public static native`。地址集中存放在 **`GLCapabilities` 的一个 2236 槽 `PointerBuffer addresses`（native 内存）**里，在 `GL.createCapabilities(...)` 时**一次性**填好；native 侧每次调用按槽位下标读该表。**槽值可以在运行期任意时刻改写，下一次调用立即生效。** |
| 2 | 能否替换 provider | `org.lwjgl.system.Configuration.FUNCTION_PROVIDER` **在这个快照里不存在**（已删除/改名）。`GL.create(FunctionProvider)` 存在但只允许调用一次，之后抛 `IllegalStateException: OpenGL library has already been loaded.`（已实测）。**"后来的 agent 包一层 provider" 不可行**；但**不需要它**——正确入口是 `GL.createCapabilities(boolean, IntFunction<PointerBuffer>)` 传入"预填表"，因为 `Checks.checkFunctions` **遇到非 0 槽位直接跳过**（已实测）。 |
| 3 | libffi/Callback | 本快照用 `org.lwjgl.system.CallbackI` + `Callback.Descriptor`（内部 `Upcalls` → Java 25 走 FFM/BC upcall）。**接口必须标 `@FunctionalInterface`**（已验证：不标报 `UnsupportedOperationException: The upcall interface must be annotated with @FunctionalInterface`）。**已跑通 native→Java 回调往返**。仅需 `--enable-native-access=ALL-UNNAMED`（游戏 JVMOptions 已带）。 |
| 4 | ZB 补丁作用域 | 目标是**任意类名**（只拒绝 `me.zed_0xff.*`）；用 ByteBuddy `AgentBuilder` + `RedefinitionStrategy.RETRANSFORMATION` + `Instrumentation.retransformClasses`（ZB manifest `Can-Retransform-Classes: true`）。**能补丁 `pzmac41.CoreGl`（系统类加载器，已验证）**。`viewpoint.render.MeshArena` **能按类名命中**，但有类加载器可见性注意点（见 §4.4）。**没有第三方 ClassFileTransformer 扩展点**（`WatchesAPI` 的 transformer 是内部私有的）。 |
| 5 | 推荐路线 | **路线 A（bridge 式预填表）** > 路线 C（ZB 补 MeshArena） > 路线 B（explicitInit 抢占 provider）。 |

---

## 1. GL43C 的地址解析机制

### 1.1 GL43C 没有 static long 字段，也没有 `<clinit>`

```bash
cd /tmp/mac41/c && unzip -o -q "$PZ/projectzomboid.jar" \
  'org/lwjgl/opengl/GL43C.class' 'org/lwjgl/opengl/GLCapabilities.class' \
  'org/lwjgl/system/Configuration.class' 'org/lwjgl/system/Checks.class' \
  'org/lwjgl/system/ThreadLocalUtil.class' 'org/lwjgl/system/Callback*.class' \
  'org/lwjgl/system/libffi/*' -d pz
$JDK25/javap -p pz/org/lwjgl/opengl/GL43C.class | grep -n 'VertexAttribFormat'
$JDK25/javap -p pz/org/lwjgl/opengl/GL43C.class | grep -c clinit
```

原始输出：
```
352:  public static native void glVertexAttribFormat(int, int, int, boolean, int);
353:  public static native void glVertexAttribIFormat(int, int, int, int);
354:  public static native void glVertexAttribLFormat(int, int, int, int);
355:  public static native void glVertexAttribBinding(int, int);
356:  public static native void glVertexBindingDivisor(int, int);

(no <clinit>)
```
运行期进一步确认（探针 `probe/Probe.java`，见 §1.5）：
```
GL43C declared fields named glVertexAttribFormat = 0  (0 => no per-class static long address field)
GL43C declared methods count = 114  static-long-fields = 0
GL43C.glVertexAttribFormat mods = public static native
```

### 1.2 地址集中在 `GLCapabilities.addresses`

```bash
$JDK25/javap -p pz/org/lwjgl/opengl/GLCapabilities.class | grep -nE 'addresses|forwardCompatible|glVertexAttribFormat|ADDRESS_BUFFER_SIZE'
```

原始输出：
```
3:  static final int ADDRESS_BUFFER_SIZE;
911:  public final long glBindVertexBuffer;
912:  public final long glVertexAttribFormat;
913:  public final long glVertexAttribIFormat;
914:  public final long glVertexAttribLFormat;
915:  public final long glVertexAttribBinding;
916:  public final long glVertexBindingDivisor;
2682:  public final boolean forwardCompatible;
2683:  final org.lwjgl.PointerBuffer addresses;
```

地址来源（`GLCapabilities` 构造器，`javap -p -c`，共 32000+ 字节）：
```
   9: aload         4
  11: sipush        2236
  14: invokeinterface #5,  2  // IntFunction.apply:(I)Ljava/lang/Object;
  19: checkcast     #6        // class org/lwjgl/PointerBuffer
  ...
  30: invokestatic  #7        // check_GL11:(FunctionProvider,PointerBuffer,Set,boolean)Z
  ...
31975: aload_0
31976: aload         5
31978: invokestatic  #3132     // ThreadLocalUtil.setupAddressBuffer:(PointerBuffer)PointerBuffer;
31981: putfield      #3133     // Field addresses:Lorg/lwjgl/PointerBuffer;
31984: return
```

`check_GL43` 的收尾（`javap -p -c GLCapabilities`，从偏移 615 起）：
```
 615: invokestatic  #3411  // Checks.checkFunctions:(FunctionProvider,PointerBuffer,[I[Ljava/lang/String;)Z
 618: ifne          633
 621: ldc_w         #3476  // String GL
 624: ldc_w         #4025  // String OpenGL43
 627: invokestatic  #3477  // Checks.reportMissing:(String,String)Z
```
以及第 38 个函数名就是我们要的：
```
 581: bipush        38
 583: ldc_w         #4064  // String glVertexAttribFormat
```

### 1.3 **关键**：`Checks.checkFunctions` 跳过非 0 槽位（这是可行的根本原因）

```bash
$JDK25/javap -p -c pz/org/lwjgl/system/Checks.class
```
第三个重载（`FunctionProvider, PointerBuffer, int[], String...`）原始字节码：
```
  26: aload_3
  27: iload         8
  29: invokevirtual #5   // PointerBuffer.get:(I)J
  32: lconst_0
  33: lcmp
  34: ifeq          40
  37: goto          76          <<<<<< 槽位非 0 => 直接跳到下一个函数，不覆盖
  40: aload_0
  41: lload_1
  42: aload         5
  44: iload         7
  46: aaload
  47: invokeinterface #8   // FunctionProviderLocal.getFunctionAddress:(JLjava/lang/CharSequence;)J
  54: lload         9
  56: lconst_0
  57: lcmp
  58: ifeq          73
  61: aload_3
  62: iload         8
  64: lload         9
  66: invokevirtual #7   // PointerBuffer.put:(IJ)PointerBuffer;
```

实测（`probe/Probe.java` §2c）：
```
== [2c] Checks.checkFunctions honours a pre-seeded slot ==
checkFunctions -> false
slot 908 glVertexAttribFormat : 0xDEADBEEFCAFE -> 0xDEADBEEFCAFE  PRESERVED=true
slot 907 glBindVertexBuffer    : 0x0 -> 0x0  filledFromProvider=false
slot 909 glVertexAttribIFormat : 0x0 -> 0x0  filledFromProvider=false
```
（907/909 为 0 是因为此探针**没有 GL context**，`GL$1.getFunctionAddress` 返回 0；908 的保留正是要证的。）
`checkFunctions -> false` 也顺带证明了「缺函数 ⇒ 返回 false ⇒ `Checks.reportMissing`」。

### 1.4 native 侧每次调用按下标读表

```bash
$JDK25/javap -p -c pz/org/lwjgl/opengl/GL.class | sed -n '/public static void setCapabilities/,/^$/p'
```
原始输出：
```
  0: getstatic     #58   // Field capabilitiesTLS:Ljava/lang/ThreadLocal;
  3: aload_0
  4: invokevirtual #59   // ThreadLocal.set:(Ljava/lang/Object;)V
  7: aload_0
  8: ifnonnull     15
 11: lconst_0
 12: goto          22
 15: aload_0
 16: getfield      #60   // Field GLCapabilities.addresses:Lorg/lwjgl/PointerBuffer;
 19: invokestatic  #61   // MemoryUtil.memAddress:(Lorg/lwjgl/system/CustomBuffer;)J
 22: invokestatic  #62   // ThreadLocalUtil.setCapabilities:(J)V
 25: getstatic     #6    // Field icd:Lorg/lwjgl/opengl/GL$ICD;
 28: aload_0
 29: invokeinterface #63,  2  // GL$ICD.set:(GLCapabilities)V
 34: return
```
`ThreadLocalUtil.setCapabilities(long)` 把这个**缓冲区基址**写进 JNI env data：
```
public static void setCapabilities(long);
   0: invokestatic  #4   // getThreadJNIEnv:()J
   ...
  63: lload         4
  65: getstatic     #7   // Field CAPABILITIES_OFFSET:I
  68: i2l
  69: ladd
  70: lload_0
  71: invokestatic  #9   // MemoryUtil.memPutAddress:(JJ)V
```
native 侧与之一一对应：`liblwjgl_opengl.dylib` 恰好导出 **2236** 个 `_Java_*` stub：
```bash
D=/tmp/mac41/c/nat/macos/arm64/org/lwjgl/opengl/liblwjgl_opengl.dylib   # unzip 自 projectzomboid.jar
dyld_info -exports "$D" | grep -c '_Java_'
dyld_info -exports "$D" | grep -E 'GL43C_(glBindVertexBuffer|glVertexAttribFormat|glVertexAttribIFormat|glVertexAttribLFormat|glVertexAttribBinding|glVertexBindingDivisor)'
```
原始输出：
```
2236
        0x0000C340  _Java_org_lwjgl_opengl_GL43C_glBindVertexBuffer
        0x0000C3C4  _Java_org_lwjgl_opengl_GL43C_glVertexAttribBinding
        0x0000C360  _Java_org_lwjgl_opengl_GL43C_glVertexAttribFormat
        0x0000C384  _Java_org_lwjgl_opengl_GL43C_glVertexAttribIFormat
        0x0000C3A4  _Java_org_lwjgl_opengl_GL43C_glVertexAttribLFormat
        0x0000C3DC  _Java_org_lwjgl_opengl_GL43C_glVertexBindingDivisor
```
（注意：`nm -gU` 看不到这些符号，必须用 `dyld_info -exports`。）

> **回答 Q1 的"关键"**：解析发生在 **`GL.createCapabilities()` 期间一次性填入**（不是每次调用 dlsym）。但 **native stub 每次调用都从表里按下标取指针**，因此 **运行期改写槽位 = 立即生效**。这就是"补函数"路线的全部基础。
>
> 补充：`GLCapabilities.<init>` 末尾调用 `ThreadLocalUtil.setupAddressBuffer(addresses)`，它把仍是 0 的槽位换成 `FUNCTION_MISSING_ABORT`（native abort 桩）。所以：
> * 构造前预填（工厂返回已填好的表）→ 0 填充 + 我们的槽位保留；
> * 构造后改写（`getAddressBuffer().put(i,p)`）→ 直接覆盖 abort 桩，同样有效。

### 1.5 探针

`/tmp/mac41/c/probe/Probe.java`（只读，不建 GL context）。编译与运行：
```bash
cd /tmp/mac41/c/probe
$JDK25/javac -nowarn -cp "$PZ/projectzomboid.jar" -d out Probe.java
"$JRE" -Djava.awt.headless=true --enable-native-access=ALL-UNNAMED \
  --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED \
  -cp "out:$PZ/projectzomboid.jar" Probe
```
关键原始输出（完整见 `/tmp/mac41/c/probe/probe_run.txt`）：
```
java.version = 25.0.1   os.arch = aarch64
GL.getFunctionProvider() = org.lwjgl.opengl.GL$1@66d1af89
GL43C declared fields named glVertexAttribFormat = 0
GL43C.glVertexAttribFormat mods = public static native
GLCapabilities final = true
GLCapabilities.glVertexAttribFormat type=long mods=public final
GLCapabilities.addresses type=org.lwjgl.PointerBuffer mods=final
GLCapabilities public ctors = 0;  declared ctors = [GLCapabilities(FunctionProvider,Set,boolean,IntFunction)]
GLCapabilities.getAddressBuffer() public = true
slot 908 glVertexAttribFormat : 0xDEADBEEFCAFE -> 0xDEADBEEFCAFE  PRESERVED=true
CallbackI.address() = 0x11CB4F340  nonzero=true
   >>> callback fired: index=3 size=4 type=0x1406 normalized=0 relOffset=0
ROUND TRIP OK = true
PROBE DONE
```

---

## 2. 能否在 GL 初始化前替换/包装 provider

### 2.1 `Configuration.FUNCTION_PROVIDER` 不存在

```bash
$JDK25/javap -p pz/org/lwjgl/system/Configuration.class | grep -n 'FUNCTION_PROVIDER'   # 无输出, exit 1
$JDK25/javap -p pz/org/lwjgl/system/Configuration.class | grep -vE '\(' | wc -l
```
原始输出：`(exit 1)`，即 **该类没有 `FUNCTION_PROVIDER` 字段**（3.4.x 已移除；现存相关的是 `OPENGL_LIBRARY_NAME / OPENGL_CONTEXT_API / OPENGL_EXPLICIT_INIT / OPENGL_MAXVERSION`）。
注意 `DISABLE_FUNCTION_CHECKS`、`JNI_NATIVE_INTERFACE_FUNCTION_COUNT` 存在。

### 2.2 `org.lwjgl.opengl.GL` 的全部相关 public 成员

```bash
$JDK25/javap -p pz/org/lwjgl/opengl/GL.class | grep -vE '^\s+public static final int '
```
原始输出（节选，完整）：
```
  private static final APIUtil$APIVersion MAX_VERSION;
  private static FunctionProvider functionProvider;
  private static final ThreadLocal<GLCapabilities> capabilitiesTLS;
  private static GL$ICD icd;
  static void initialize();
  public static void create();
  private static SharedLibrary loadNative();
  private static SharedLibrary loadEGL();
  private static SharedLibrary loadOSMesa();
  public static void create(java.lang.String);
  private static void create(SharedLibrary);
  public static void create(FunctionProvider);
  public static void destroy();
  public static FunctionProvider getFunctionProvider();
  public static void setCapabilities(GLCapabilities);
  public static GLCapabilities getCapabilities();
  public static GLCapabilities createCapabilities();
  public static GLCapabilities createCapabilities(java.util.function.IntFunction<PointerBuffer>);
  public static GLCapabilities createCapabilities(boolean);
  public static GLCapabilities createCapabilities(boolean, java.util.function.IntFunction<PointerBuffer>);
  static GLCapabilities getICD();
  static {};
```
**没有 `setFunctionProvider`。** 唯一 setter 是 `create(FunctionProvider)`。

`GL.<clinit>` 会在类初始化时立刻 `create()`（除非 `-Dorg.lwjgl.opengl.explicitInit=true`）：
```
  37: invokestatic  #202  // Platform.mapLibraryNameBundled:(String)String
  40: invokestatic  #203  // Library.loadSystem:(Consumer,Consumer,Class,String,String)V
  43: getstatic     #204  // Configuration.OPENGL_MAXVERSION
  46: invokestatic  #205  // APIUtil.apiParseVersion:(Configuration)APIUtil$APIVersion
  49: putstatic     #108  // MAX_VERSION
  52: getstatic     #206  // Configuration.OPENGL_EXPLICIT_INIT
  55: iconst_0
  56: invokestatic  #207  // Boolean.valueOf:(Z)Boolean
  59: invokevirtual #208  // Configuration.get:(Object)Object
  68: ifne          74
  71: invokestatic  #211  // create:()V          <<<<<< 立刻装载 native 库并设置 provider
  74: return
```

`create(SharedLibrary)` 无条件走 `create(FunctionProvider)`：
```
private static void create(org.lwjgl.system.SharedLibrary);
  0: new           #45   // class org/lwjgl/opengl/GL$1
  8: invokestatic  #47   // create:(FunctionProvider)V
```
`create(FunctionProvider)` 只允许一次：
```
public static void create(org.lwjgl.system.FunctionProvider);
  0: getstatic     #50   // Field functionProvider
  3: ifnull        16
  6: new           #19   // class java/lang/IllegalStateException
 10: ldc           #51   // String OpenGL library has already been loaded.
 15: athrow
 16: aload_0
 17: putstatic     #50   // Field functionProvider
 20: sipush        2236
 23: invokestatic  #53   // ThreadLocalUtil.setFunctionMissingAddresses:(I)V
```

### 2.3 实测：晚到的包装 provider 会被拒绝

`probe/Probe.java` §2a 原始输出：
```
== [2a] GL.create(FunctionProvider) after the library is loaded ==
GL.create(wrapper) -> java.lang.IllegalStateException: OpenGL library has already been loaded.
```

### 2.4 多 `-javaagent` premain 的时序（实测）

用两个自制 agent（`/tmp/mac41/c/ag/`）实测：
```bash
cd /tmp/mac41/c/ag/out
"$JRE" -Djava.awt.headless=true --enable-native-access=ALL-UNNAMED \
  -javaagent:../jar/agent1.jar -javaagent:../jar/agent2.jar -cp ".:$PZ/projectzomboid.jar" M
"$JRE" -Djava.awt.headless=true --enable-native-access=ALL-UNNAMED \
  -javaagent:../jar/agent2.jar -javaagent:../jar/agent1.jar -cp ".:$PZ/projectzomboid.jar" M
```
原始输出（正序）：
```
[A.premain ] #1 running. A.class loader = jdk.internal.loader.ClassLoaders$AppClassLoader@355da254
[A.premain ] #1 can retransform = true
[A.premain ] #1 A2 visible already? = false
[A2.premain] #2 running.
[A2.premain] agent1.done sysprop      = yes
[A2.premain] A resolved from loader   = jdk.internal.loader.ClassLoaders$AppClassLoader@355da254  (same as system CL? true)
[A2.premain] GL.getFunctionProvider() = org.lwjgl.opengl.GL$1@77ec78b9
[A2.premain] => GL is initialized INSIDE premain, before main
[M.main    ] Class.forName("B")   = B  loader=jdk.internal.loader.ClassLoaders$AppClassLoader@355da254  isSystemCL=true
[M.main    ] GL.getFunctionProvider = org.lwjgl.opengl.GL$1@77ec78b9
```
逆序输出（`agent2` 先跑）：`[A2.premain] agent1.done sysprop = null`，`[A.premain] #1 A2 visible already? = true`。

**结论：**
* premain 严格按命令行顺序执行，全部早于 `main`。✔
* **agent jar 里的类由 AppClassLoader（系统类加载器）加载**，且后续 agent 能直接解析先前 agent jar 的类（`A2` resolve `A` 成功，同一 AppClassLoader）。✔
* `GL` 一旦在 premain 里被碰到，provider 就固定了，`main` 里拿到的是同一个实例。✔
* 因此"后加载的 agent 把 provider 包一层"**不可行**：`GL.create()` 已经跑过，`create(wrapper)` 必抛 `IllegalStateException`。
* **唯一能抢占 provider 的办法**是 `-Dorg.lwjgl.opengl.explicitInit=true` 让 `<clinit>` 跳过 `create()`，然后在 premain 里 `GL.create(wrapper)`。但代价是 `lwjgl_opengl` 的 native 装载得自己负责（`Library.loadSystem` 是 public，但 `GL.loadNative()` 是 private；而 `GL.create(String)` 会走 `create(SharedLibrary)`→`create(FunctionProvider)`，与已设的 wrapper 冲突抛异常）。**不推荐。**

### 2.5 正确入口：预填表

```java
// 唯一需要的 public API：GL.createCapabilities(boolean, IntFunction<PointerBuffer>)
GLCapabilities caps = GL.createCapabilities(true, mySeededFactory); // 返回后已自动 setCapabilities
```
`createCapabilities(boolean, IntFunction)` 直接用静态 `functionProvider`（无 wrapper 空间），
关键：**工厂返回的表里的非 0 槽位被 `checkFunctions` 保留**（§1.3），所以 hook 地址能"穿过"。

---

## 3. libffi / Callback：从 Java 造一个可被 native 调用的函数

### 3.1 public/package 成员

```bash
$JDK25/javap -p pz/org/lwjgl/system/Callback.class pz/org/lwjgl/system/CallbackI.class \
  'pz/org/lwjgl/system/Callback$Descriptor.class' pz/org/lwjgl/system/libffi/LibFFI.class
```
```
public abstract class org.lwjgl.system.Callback implements Pointer, NativeResource {
  private long address;
  protected Callback(Callback$Descriptor);
  protected Callback(long);
  public long address();
  public void free();
  public static <T extends CallbackI> T get(long);
  public static <T extends CallbackI> T getSafe(long);
  public static void free(long);
}
public final class org.lwjgl.system.Callback$Descriptor {
  final java.lang.invoke.MethodHandles$Lookup lookup;     // package-private
  final org.lwjgl.system.libffi.FFICIF cif;               // package-private
  public Callback$Descriptor(MethodHandles$Lookup, FFICIF);   // public ctor
}
public interface org.lwjgl.system.CallbackI extends Pointer {
  public abstract Callback$Descriptor getDescriptor();
  public default long address();     // -> Upcalls.upcallCreate(getDescriptor(), this)
  public abstract void callback(long, long);
}
```
`CallbackI.address()` 的字节码：
```
  0: aload_0
  1: invokeinterface #1  // getDescriptor:()Callback$Descriptor;
  6: aload_0
  7: invokestatic  #2    // Upcalls.upcallCreate:(Callback$Descriptor,Object)J
 10: lreturn
```
`LibFFI` 相关（都在 `org.lwjgl.system.libffi`）：
```
public static final FFIType ffi_type_void / _sint32 / _uint8 / _float / _double / _pointer ...
public static final int FFI_DEFAULT_ABI, FFI_OK;
public static int ffi_prep_cif(FFICIF, int, FFIType, PointerBuffer);
public static void ffi_call(FFICIF, long, ByteBuffer, PointerBuffer);
public static FFIClosure ffi_closure_alloc(long, PointerBuffer);
public static int ffi_prep_closure_loc(FFIClosure, FFICIF, long, long, long);
public static long ffi_get_closure_size();
```
`FFICIF` / `FFIType` / `FFIClosure` 的 public 成员完整清单见 §3.4 附录；另有 `APIUtil.apiCreateCIF(FFIType, FFIType...)` 直接造 CIF。

**但是**——本快照在 Java 25 上 `CallbackI.address()` **不走 libffi**，走 `Upcalls`：
```
static long upcallCreate(Callback$Descriptor, Object);
   0: invokestatic  #3   // MemoryStack.stackPush()
  16: getstatic     #5   // Field CLOSURE_SIZE:I
  19: i2l
  22: invokestatic  #6   // LibFFI.ffi_closure_alloc:(JLPointerBuffer;)FFIClosure;
```
而 `Upcalls` 内部的 `getBinder()` 在 Java 25 上选 **FFM/BC** 后端（`org.lwjgl.system.ffm.FFM.ffmUpcall` → `BCCallUp`），这就要求接口被 `@FunctionalInterface` 标注。

### 3.2 硬性要求：`@FunctionalInterface`（实测）

不标注时：
```
Exception in thread "main" java.lang.UnsupportedOperationException: The upcall interface must be annotated with @FunctionalInterface
	at org.lwjgl.system.ffm.BCCallUp.<init>(BCCallUp.java:52)
	at org.lwjgl.system.ffm.FFM.ffmUpcall(FFM.java:697)
	at org.lwjgl.system.Upcalls.lambda$getBinder$1(Upcalls.java:149)
	at org.lwjgl.system.Upcalls.upcallCreate(Upcalls.java:67)
	at org.lwjgl.system.CallbackI.address(CallbackI.java:23)
```
加上 `@FunctionalInterface` 后（**注意 `@FunctionalInterface` 要求恰好 1 个抽象方法**，所以 `callback`/`getDescriptor` 必须是 `default`，真正的抽象方法只有一个）：
```
CallbackI.address() = 0x11CB4F340  nonzero=true
   >>> callback fired: index=3 size=4 type=0x1406 normalized=0 relOffset=0
callback received = [3, 4, 5126, 0, 0]
ROUND TRIP OK = true
```
这就是 `pzmac41.CoreGl$VI` 带注解的实证：
```bash
$JDK25/javap -v /tmp/mac41/c/bridge/pzmac41/CoreGl\$VI.class | grep -A3 RuntimeVisibleAnnotations
```
```
RuntimeVisibleAnnotations:
  0: #59()
    java.lang.FunctionalInterface
```
`CoreGl$VI.<clinit>` 构造 CIF 的原始字节码：
```
  0: new           #17   // class org/lwjgl/system/Callback$Descriptor
  7: getstatic     #25   // Field pzmac41/CoreGl.V:Lorg/lwjgl/system/libffi/FFIType;
 10: iconst_1
 11: anewarray     #29   // class org/lwjgl/system/libffi/FFIType
 16: getstatic     #31   // Field pzmac41/CoreGl.I:Lorg/lwjgl/system/libffi/FFIType;
 20: invokestatic  #34   // APIUtil.apiCreateCIF:(FFIType,[FFIType;)FFICIF;
 23: invokespecial #40   // Callback$Descriptor."<init>":(Lookup,FFICIF;)V
 26: putstatic     #1    // Field DESC
```
其中 `CoreGl.I=LibFFI.ffi_type_sint32`、`F=ffi_type_float`、`D=ffi_type_double`、`P=ffi_type_pointer`、
`Z=ffi_type_uint8`、`V=ffi_type_void`（`CoreGl.<clinit>` 偏移 594..627）。

### 3.3 最短可用骨架（已编译通过）

见 `/tmp/mac41/c/probe/Skeleton.java`。编译：
```bash
cd /tmp/mac41/c/probe
$JDK25/javac -nowarn -cp "$PZ/projectzomboid.jar:out" -d out Skeleton.java
# javac exit=0  -> Skeleton.class Skeleton$Fn_II.class Skeleton$Fn_IIIZI.class Skeleton$Fn_IIJI.class
```
核心片段：
```java
@FunctionalInterface                       // 必须！
public interface Fn_IIIZI extends CallbackI {          // void f(int,int,int,boolean,int)
    FFIType I = LibFFI.ffi_type_sint32;
    FFIType Z = LibFFI.ffi_type_uint8;                  // GLboolean 走 uint8
    FFIType V = LibFFI.ffi_type_void;
    FFICIF CIF = APIUtil.apiCreateCIF(V, I, I, I, Z, I);
    Callback.Descriptor DESC = new Callback.Descriptor(MethodHandles.lookup(), CIF);

    @Override default Callback.Descriptor getDescriptor() { return DESC; }
    @Override default void callback(long ret, long args) {
        invoke(arg(args,0), arg(args,1), arg(args,2), arg(args,3), arg(args,4));
    }
    void invoke(int a, int b, int c, int d, int e);     // 唯一的抽象方法
    static int arg(long a, int i) {
        return MemoryUtil.memGetInt(MemoryUtil.memGetAddress(a + 8L * i));
    }
}
long addr = myImpl.address();     // 立刻可用作函数指针
// 必须强引用住 myImpl（或至少 addr 注册在 Upcalls 注册表里），否则被 GC 后 native 回调野指针
```
JVM 参数（**不需要 `--add-opens`**）：
```
--enable-native-access=ALL-UNNAMED
```
（游戏 `Info.plist` 的 `JVMOptions` 已经带了，见 §5.1；缺它是 warning，Java 25 下仍可运行，实测如此。）

### 3.4 附录：`FFICIF` / `FFIType` / `FFIClosure` public 成员

```
org.lwjgl.system.libffi.FFICIF  extends Struct<FFICIF> implements NativeResource
  static final int SIZEOF, ALIGNOF, ABI, NARGS, ARG_TYPES, RTYPE, BYTES, FLAGS;
  public int sizeof(); public int abi(); public int nargs();
  public PointerBuffer arg_types(); public FFIType rtype(); public int bytes(); public int flags();
  public static FFICIF malloc()/calloc()/create()/create(long)/createSafe(long);
  public static FFICIF$Buffer malloc(int)/calloc(int)/create(int)/create(long,int);
  public static int nabi(long); public static int nnargs(long);
  public static PointerBuffer narg_types(long); public static FFIType nrtype(long);
  public static int nbytes(long); public static int nflags(long);

org.lwjgl.system.libffi.FFIType  extends Struct<FFIType> implements NativeResource
  static final int SIZEOF, ALIGNOF, SIZE, ALIGNMENT, TYPE, ELEMENTS;
  public int sizeof(); public long size(); public short alignment(); public short type();
  public PointerBuffer elements(int);
  public FFIType size(long)/alignment(short)/type(short)/elements(PointerBuffer);
  public FFIType set(long,short,short,PointerBuffer); public FFIType set(FFIType);
  public static FFIType malloc()/calloc()/create()/create(long)/createSafe(long);
  public static long nsize(long); public static short nalignment(long); public static short ntype(long);
  public static PointerBuffer nelements(long,int);
  public static void nsize(long,long); public static void nalignment(long,short);
  public static void ntype(long,short); public static void nelements(long,PointerBuffer);

org.lwjgl.system.libffi.FFIClosure extends Struct<FFIClosure> implements NativeResource
  static final int SIZEOF, ALIGNOF, CIF, FUN, USER_DATA;
  public int sizeof(); public FFICIF cif(); public long fun(); public long user_data();
  public static FFIClosure malloc()/calloc()/create()/create(long)/createSafe(long);
  public static FFICIF ncif(long); public static long nfun(long); public static long nuser_data(long);

org.lwjgl.system.libffi.LibFFI (public class)
  public static final String FFI_VERSION_STRING; public static final int FFI_VERSION_NUMBER;
  public static final short FFI_TYPE_VOID/INT/FLOAT/DOUBLE/LONGDOUBLE/UINT8/SINT8/.../POINTER;
  public static final int FFI_FIRST_ABI/WIN64/GNUW64/UNIX64/EFI64/SYSV/.../FFI_DEFAULT_ABI;
  public static final int FFI_OK/FFI_BAD_TYPEDEF/FFI_BAD_ABI/FFI_BAD_ARGTYPE;
  public static final FFIType ffi_type_void/_uint8/_sint8/.../_sint32/.../_pointer;
  public static int ffi_prep_cif(FFICIF,int,FFIType,PointerBuffer);
  public static int ffi_prep_cif_var(FFICIF,int,int,FFIType,PointerBuffer);
  public static void ffi_call(FFICIF,long,ByteBuffer,PointerBuffer);
  public static int ffi_get_struct_offsets(int,FFIType,PointerBuffer);
  public static long ffi_get_closure_size();
  public static FFIClosure ffi_closure_alloc(long,PointerBuffer);
  public static void ffi_closure_free(FFIClosure);
  public static int ffi_prep_closure_loc(FFIClosure,FFICIF,long,long,long);
```

---

## 4. ZombieBuddy 2.3.2 的补丁作用域

> 额外收获：**ZB 把完整 Java 源码随 mod 一起发布了**，所以下面用源码而不是反编译作证据：
> `~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java/steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy/java/src/main/java/me/zed_0xff/zombie_buddy/`
> （`PatchEngine.java` `Loader.java` `PatchTransformer.java` `Patch.java` …）
> 注意 ZB.jar 里的类与这份源码一致（用 `javap` 交叉核对过 `applyPatches` / `collectPatches` 的字节码）。

### 4a. 目标类筛选规则：**任意类名**，唯一黑名单是 `me.zed_0xff.*`

`PatchEngine.java:134-172`（原文）：
```java
public static void applyPatches(String packageName, ClassLoader modLoader) {
    List<Class<?>> patches = collectPatches(packageName, modLoader);
    ...
    for (Class<?> patch : patches) {
        Patch ann = patch.getAnnotation(Patch.class);
        if (ann == null) continue;
        if (ann.className().startsWith("me.zed_0xff.")) continue; // refuse to patch our own classes

        if (ann.className().equals("zombie.Lua.LuaManager$Exposer") && ann.methodName().equals("exposeAll")
            && !ann.IKnowWhatIAmDoing()) { ... continue; }
        PatchTarget target = new PatchTarget(ann.className(), ann.methodName());
        ...
```
对应的字节码（`javap -p -c PatchEngine`，`applyPatches`）：
```
112: ldc           #161  // String me.zed_0xff.
114: invokevirtual #163  // String.startsWith:(String)Z
117: ifeq          123
120: goto          63          <<< 只有这一条名字前缀黑名单
```
* `packageName` 参数不是"目标类"，而是**你自己 mod 的 `javaPkgName`**，用来在 `collectPatches` 里扫描你的 `@Patch` 类：
  `PatchEngine.java:674-708` → `new ClassGraph().enableAllInfo().acceptPackages(packageName)`，然后
  `scanResult.getClassesWithAnnotation(Patch.class.getName())`，并用
  `patchClass.getPackage().getName().equals(packageName)` 过滤。
* `Loader.loadJar(...)` 把它串起来（`Loader.java:977-989`）：
```java
static boolean loadJar(Path jarPath, String packageName, String approvedHash, Phase phase) {
    ...
    if (!addJarToClasspath(jarPath, packageName, approvedHash)) return false;
    return ApplyPatchesFromPackage(packageName, null, phase);   // modLoader == null
}
```
* **是不是白名单/前缀过滤？不是。** 目标类名只受 `me.zed_0xff.` 前缀限制。
* **`retransformClasses` 还是全量 transformer？两者都用**：
```java
// PatchEngine.java:221-232
AgentBuilder builder = new AgentBuilder.Default();
if (hasAdviceOnLoadedClasses) builder = builder.disableClassFormatChanges();
builder = builder
    .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
    .with(bbLogger)
    .with(new AgentBuilder.Listener.Adapter() { ... });
...
// PatchEngine.java:279-280
builder = builder.type(SyntaxSugar.typeMatcher(className))
                 .transform((bl, td, cl, mo, pd) -> { ... });
...
// PatchEngine.java:1018-1023 (字节码偏移)
1018: aload  11
1020: getstatic #217  // Loader.g_instrumentation
1023: invokeinterface #319  // AgentBuilder.installOn:(Instrumentation;)ResettableClassFileTransformer
```
以及对**已加载**目标显式重转换（`javap -p -c PatchEngine`，偏移 1089..1108）：
```
1089: aload         13
1091: invokestatic  #329  // Class.forName:(String)Class;
1096: getstatic     #217  // Loader.g_instrumentation
1099: iconst_1
1108: invokeinterface #333  // Instrumentation.retransformClasses:([Ljava/lang/Class;)V
```
* **ZB agent 的 manifest**（`unzip -p ZombieBuddy.jar META-INF/MANIFEST.MF`）：
```
Manifest-Version: 1.0
Premain-Class: me.zed_0xff.zombie_buddy.Agent
Can-Redefine-Classes: true
Can-Retransform-Classes: true
Implementation-Version: 2.3.2
Multi-Release: true
X-Local-Compatibility-Fix: b42.20.4-b42.21-list-loader-1
```
* **mod 的类由哪个 loader 加载？系统（App）类加载器**（`Loader.java:512`）：
```java
g_instrumentation.appendToSystemClassLoaderSearch(jf);
```
（我在 §2.4 用自制 agent 实测过：`-javaagent` jar 里的类由 `jdk.internal.loader.ClassLoaders$AppClassLoader` 加载。）

### 4a-1. 能不能补丁 `pzmac41.CoreGl`（来自另一个 `-javaagent` 的 jar）？**能。**

* `CoreGl` 在 bridge 的 `-javaagent:pz-mac41-bridge.jar` 里，manifest `Premain-Class: pzmac41.Agent`（实测 `unzip -p` 已确认）→ 由 **AppClassLoader** 加载（与 ZB、与 mod 的 jar 同一个 loader，见 §2.4 实测 `isSystemCL=true`）。
* ZB 的筛选只看 `@Patch.className()` 是否以 `me.zed_0xff.` 开头 → `pzmac41.CoreGl` **通过**。
* `Class.forName("pzmac41.CoreGl")` 在 `retransformClasses` 那段里能成功（系统 CL 可见）。
* **前提（顺序）**：bridge 的 `Agent.premain` 必须已经跑过并且 `CoreGl` 已经被加载/初始化，否则重转换会在 CoreGl 尚未加载时 targeting（ByteBuddy 对未加载类用 transform-on-load，也能生效）。
  `-javaagent` 顺序 = 命令行顺序（§2.4 实测），所以 `-javaagent:ZombieBuddy.jar ... -javaagent:pz-mac41-bridge.jar` 或反之，ZB 都能找到它——ZB 的 `loadMods` 发生在 premain，而 bridge 的 `CoreGl.install` 发生在 `org/lwjglx/opengl/Display.createCapabilities` 被改写后调用时（运行时），所以 ZB 有时间先动手。

### 4a-2. 能不能补丁 `viewpoint.render.MeshArena`（来自 `media/java/client/Viewpoint.jar`）？**按类名能命中，但有类加载器可见性坑。**

* 筛选规则同样只看名字 → **不会被白名单拦住**。`typeMatcher("viewpoint.render.MeshArena")` + `AgentBuilder` + `retransformClasses` 都按字符串匹配，与包无关。
* 坑在 **`@Patch` advice 是 ByteBuddy Advice = 内联进目标方法**，内联体里如果调用你自己的 helper 类（`Helper.doIt(...)`），**目标类的 classloader 必须能解析那个 helper**。`MeshArena` 由游戏为 `media/java/client/*.jar` 建的加载器加载；ZB 把你的 jar 加进的是 **系统** 加载器（`appendToSystemClassLoaderSearch`）。只要游戏的加载器 parent 链能到 AppClassLoader，就能解析；**这一段我未实测**（需要真跑游戏，本次按要求不启动）。
* 另一个坑：`@Patch` 的 `isAdvice=false`（MethodDelegation）对**已加载**类基本无效，ZB 自己在 `PatchEngine.java:191-198` 把告警注释掉了——**只能用 `isAdvice=true`（Advice）**。
* 顺带：`MeshArena` 属于第三方 mod（Viewpoint），不是游戏本体，ZB 文档只谈"game classes"；`ModdingGuide.md` 里**没有任何关于"只能补丁游戏类"的限制**（全文 378 行，`grep -iE 'whitelist|classloader|transformer|extension|plugin'` 只命中 `javaPkgName`/`package` 相关行）。文档相关原文在 `doc/ModdingGuide.md:142-196`（"Creating Patches"/"Patch Options"）与 `:334-341`（"Tips"）：
```
| `className` | Fully qualified name of the target class |
| `methodName` | Name of the method to patch |
| `warmUp` | If `true`, forces the class to load before patching (needed for some game classes) |
- **Retransformation**: Patches can be applied to already-loaded classes, but MethodDelegation
  patches work best on classes that haven't loaded yet
```

### 4b. `MeshArena` 的"最简单补救"评估（只评估可否作用，不写补丁）

可以，形式是：
```java
@Patch(className = "viewpoint.render.MeshArena", methodName = "recordAttributes")
public static class Patch_RecordAttributes {
    @Patch.OnEnter(skipOn = true)                 // 跳过原方法
    public static boolean enter(@Patch.This Object self, /* 参数用 Object 宽容接 */ ...) {
        return true;                              // 原方法不执行；我们自己在 helper 里做 4.1 等价调用
    }
}
```
`skipOn=true` 时原方法被跳过、返回值是默认值（ModdingGuide.md:165-183 明确说明），所以这里适合"完全接管"。
调用者 `MeshArena.recordAttributes` 的返回值/副作用需要自己复刻。
**这一步是"绕开缺失函数"而不是"补上缺失函数"**，语义上更脆（要自己实现 4.3 的 vertex-attrib-format 语义）。

### 4c. 有没有第三方 ClassFileTransformer 扩展点？**没有。**

* 全 jar 里实现 `ClassFileTransformer` 的只有两个：
```bash
$JDK25/javap -p all/me/zed_0xff/zombie_buddy/PatchEngine.class | head -3
$JDK25/javap -p 'all/me/zed_0xff/zombie_buddy/WatchesAPI$1.class'
```
```
class me.zed_0xff.zombie_buddy.WatchesAPI$1 implements java.lang.instrument.ClassFileTransformer
```
* `WatchesAPI` 成员全是 `private static`（`ensureTransformer()` / `createTransformer()` / `REGISTRY` / `transformerInstalled`），是 Lua `Watches` 功能的实现细节，**不是公开扩展点**：
```
public class me.zed_0xff.zombie_buddy.WatchesAPI {
  private static final ConcurrentHashMap<String,Integer> REGISTRY;
  private static volatile boolean transformerInstalled;
  ...
  private static void ensureTransformer();
  private static ClassFileTransformer createTransformer();
  private static void retransform(String);
}
```
* `Loader` 的 public API 里也没有 transformer 相关入口：
```
public static boolean g_hasDoLoadingText;
public static void loadMods(ArrayList<String>);  public static void loadMods(List<String>);
public static void onEnterLoadMods(String);      public static void onExitLoadMods(String);
public static void setAutoFixModOrder(boolean);  public static boolean fixApprovalDialogCursor();
public static void setFixApprovalDialogCursor(boolean);
```
* `g_instrumentation` 是 **package-private** `static Instrumentation g_instrumentation;`（`javap` 显示无修饰符），第三方 mod 若想自己挂 transformer，只能靠反射 + `setAccessible`（同包不同 loader 不行；`Loader` 与你的 mod 同为 AppClassLoader，但包不同 → 需要 `setAccessible(true)`，ZB 未开放 `--add-opens`，**实测 `Field.setAccessible` 在同 classloader 不同包下可用**，因为 unnamed module 对自己的包全部 open）。
* 结论：**想挂自己的 transformer，只能反射拿 `Loader.g_instrumentation`，或者干脆自己写一个 `-javaagent`**。

---

## 5. 可行性结论

### 5.1 环境事实（来自游戏自身配置）

```bash
cat "$PZ/../Info.plist" | sed -n '/JVMOptions/,/array>/p'
```
```
	<key>JVMOptions</key>
	<array>
		<string>-Djava.awt.headless=true</string>
		<string>--enable-native-access=ALL-UNNAMED</string>
		<string>--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED</string>
		<string>-XstartOnFirstThread</string>
		<string>-Dzomboid.steam=1</string>
		<string>-Dzomboid.znetlog=1</string>
		<string>-Xmx3072m</string>
		<string>-XX:+UseZGC</string>
		<string>-XX:-OmitStackTraceInFastThrow</string>
	</array>
```
`-javaagent` 走 Steam 启动参数（`doc/Installation.md:146`）：`-javaagent:ZombieBuddy.jar --`。

### 5.2 路线清单

| 路线 | 做法 | JVM 启动参数 | 改游戏文件 | 状态 | 风险 |
|---|---|---|---|---|---|
| **A. 预填地址表**（bridge 现用） | 拦截/替换 `GL.createCapabilities(...)` 调用点，传入 `IntFunction<PointerBuffer>` 工厂，把 4.3 的 5 个槽位预填成我们 libffi closure 的地址；其余由 `checkFunctions` 正常填 | 无（沿用现有 `--enable-native-access`） | 否 | **机制 ✅ 已验证**（`checkFunctions` 跳过非 0 槽位、`CapabilitySlots.SLOTS` 索引表、`install()` 字节码、closure 往返）；**端到端需 GL context，未跑** | 需 1 个 `-javaagent`（ClassFileTransformer 改写调用点）；依赖 `capability-slots.properties` 式**钉死的下标表**，游戏换 LWJGL 版本即失效（bridge 已用 SHA256 门禁处理）；closure 必须强引用防 GC |
| **A'. 改写活表**（更简单，本次新发现） | `GL.getCapabilities().getAddressBuffer().put(908, addr)` —— 表是 native 内存且 native 每次调用读它，**立即生效** | 无 | 否 | **机制 ✅ 已验证**（`GL.setCapabilities` → `ThreadLocalUtil.setCapabilities(memAddress(addresses))`；`getAddressBuffer()` public） | 必须在 `GL.setCapabilities` **之后**执行；`GLCapabilities` 的 `public final long` 字段是快照（这 5 个方法都是 `static native`，不受影响，但别的函数的 Java 重载会受影响）；同样依赖下标表 |
| **B. 抢占 provider** | `-Dorg.lwjgl.opengl.explicitInit=true` + 在 premain 里 `GL.create(wrapper)` | 追加 1 个属性 | 否 | **不可行/高脆**：`GL.create(String)` 与 `create(FunctionProvider)` 互斥（`create(SharedLibrary)` 无条件再调 `create(FunctionProvider)` → 抛异常）；且 native 库装载需自己负责。实测 `GL.create(wrapper)` 直接抛 `IllegalStateException` | 高 |
| **C. ZB 补 `MeshArena`** | ZB `@Patch` + `OnEnter(skipOn=true)` 自己实现 4.1 等价逻辑 | 无（ZB 已在跑） | 否 | **筛选规则 ✅ 已验证**（任意类名，只拒 `me.zed_0xff.*`；RETRANSFORMATION + retransformClasses）；**目标类 classloader 可见性未实测**（需跑游戏） | 中：要复刻 4.3 语义；helper 类必须对 `MeshArena` 的 loader 可见 |
| **D. ZB 补 `pzmac41.CoreGl`** | 让 ZB 去改 bridge 的 `capabilities()` | 无 | 否 | 可达性 ✅ 已验证（同一个 AppClassLoader） | 与路线 A 等价但更绕：等于用 ZB 去驱动 bridge 的机制 |
| **E. 直接改 `projectzomboid.jar`** | 把 `GLCapabilities` 构造函数改掉 | 无 | **是** | 未做 | 高：26000 条目整包重写；且 4.3 实现代码仍需注入 |

### 5.3 推荐

**推荐路线 A（用 A' 做兜底）**，即 bridge 已经在用的那条：

1. `pzmac41.CoreGl.install(GLCapabilities)` 的字节码已经给出完整范式：
```
  0: invokestatic  #368  // GL.getFunctionProvider:()FunctionProvider;   -> base
  6: aload_0
  7: invokestatic  #376  // Bridge.setNativeCapabilities:(GLCapabilities)V
 ...
 95: invokestatic  #415  // registerHooks:()V            <<< 造 libffi closure，填 hooks Map
 98: iconst_1
 99: invokedynamic #418  // IntFunction.apply -> lambda$install$0
104: invokestatic  #422  // GL.createCapabilities:(ZLjava/util/function/IntFunction;)GLCapabilities;
107: astore_3
111: iconst_1
112: putstatic     #126  // active:Z
116: invokestatic  #429  // Bridge.setEffectiveCapabilities:(GLCapabilities)V
```
2. `lambda$install$0(int)` → `CapabilitySlots.allocate(size, hooks, base)`：
   * 校验 `size == 2236`，否则抛（`CapabilitySlots.allocate` 偏移 1..20）；
   * `PointerBuffer.allocateDirect(2236)` 全 0；
   * 对 `hooks` 里每个名字查 `SLOTS`（`capability-slots.properties`，**2233 条，必须恰好 2233**），把 closure 地址写入对应下标；
   * 名字不在表里、或地址为 0 → 抛 `IllegalStateException`（偏移 104..149）。
3. 5 个 4.3 函数的槽位（本次从 bridge 自带的 `capability-slots.properties` 直接读出）：
```
glBindVertexBuffer=907
glVertexAttribFormat=908
glVertexAttribIFormat=909
glVertexAttribLFormat=910
glVertexAttribBinding=911
glVertexBindingDivisor=912
```
4. 签名（GL43 规范 / LWJGL 参数展开）：
```
glBindVertexBuffer(int bindingindex, int buffer, long offset, int stride)         = void(IIJI)
glVertexAttribFormat(int index, int size, int type, boolean normalized, int rel) = void(IIIZI)
glVertexAttribIFormat(int index, int size, int type, int relativeoffset)         = void(IIII)
glVertexAttribLFormat(int index, int size, int type, int relativeoffset)         = void(IIII)
glVertexAttribBinding(int attribindex, int bindingindex)                         = void(II)
glVertexBindingDivisor(int bindingindex, int divisor)                            = void(II)
```
   `boolean` 用 `LibFFI.ffi_type_uint8`（ZB/bridge 的 `Z` 就是它），`int` 用 `ffi_type_sint32`，返回 `void`。
5. 兜底：拿到 `GL.getCapabilities()` 后，如果发现 `caps.getAddressBuffer().get(908) == 0`（说明工厂没生效），就直接 `put` 覆盖——因为 native 每次都读表，**下一次调用即生效**。

**为什么推荐它**：它是唯一「不改游戏文件 + 不动 ZB + 已被真实部署验证过机制」的路线；而 4.3 语义的正确实现（要真能跑）是独立的一步，本报告只负责机制。

**未做**：
* 没有真实创建 GL context，因此 `GL.createCapabilities(true, factory)` 的**端到端**结果未跑（这需要 `-XstartOnFirstThread` + 窗口，等于启动图形栈）。
* 没有启动游戏，没有验证 `MeshArena` 的 classloader 可见性。
* 没有验证 5 个函数的 4.1 等价实现语义（`recordAttributes` 的实际调用形态没读）。
