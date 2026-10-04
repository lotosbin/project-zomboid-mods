# Viewpoint (封闭 jar) 对 OpenGL 4.3 API 使用语义分析
## 目的：判断"在只有 GL 4.1 的 macOS 上模拟/降级实现这几个函数"是否语义可行

工作目录：`/tmp/mac41/b/`
分析工具：JDK 25 的 `javap`（`/Users/liubinbin/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javap`，版本 25.0.4.1）
本机无任何反编译器（`which cfr procyon jd-cli fernflower` 全部为空，`/opt/homebrew/bin` 里也没有；未联网安装）。
**只读分析；未启动游戏，未修改任何游戏/工坊文件。** 唯一执行的"活体实验"是两次 `dlopen`/`dlsym` 探针（read-only，不创建 GL 上下文、不联网）。

---

## 0. 结论速览（先看这里）

| # | 问题 | 结论 |
|---|------|------|
| 1 | MeshArena 用法 | attrib 6/7/8 = 3×`vec4 float`，**全部绑到 binding 6（binding ≠ attrib 索引）**，`relativeOffset`=0/16/32，`divisor=1`（实例化）。共享单一 VBO + 每 mesh 不同字节 offset。有整数属性分支（attrib 5 用 `glVertexAttribIPointer`）。自己 bind/保存/恢复 `GL_ARRAY_BUFFER_BINDING`。 |
| 2 | 门控/出口 | `MeshArena` / `Meshes.init` / `WorldRenderer.init` **零门控**（无 `GLCapabilities`、无 `System.getProperty`、无 try/catch 降级）。**跳过 arena = 没有任何替代渲染路径**（见 §6）。 |
| 3 | 32 个 4.2+ 函数 | 实测 **33** 个不同的 GL4.2+ 函数；其中**恰好 1 个**（`glClearTexImage`）被 bridge `CoreGl` 覆盖 ⇒ **32 个**落在 jar 内 `viewpoint.mac41.*` 垫片上 —— 这与题设"32 / 桥只覆盖 3 个"高度吻合。 |
| 4 | 模拟语义 | 题设策略**方向正确且已在 jar 内实现**（`Draws41.apply/rebase`），但**仅照题设做会出错**：缺 baseInstance 记账、缺 `GL_ARRAY_BUFFER` 保存/恢复、缺整数属性、缺 divisor 归零、缺按 VAO 的记账。清单见 §7。 |
| 5 | 版本 | Viewpoint `modversion=0.1.5a-hotfix`（workshop 3809306528）；补丁 `0.1.0-alpha1-currentpack-private1`。上游 jar `94fedda3…`(2068978B) vs 本 payload `9d8d4890…`(2149583B)。**没有"disable arena"/"compat mode"开关**（见 §9）。 |

### 最重要的发现（修正题设前提）

题设的崩溃栈是 `GL43C.glVertexAttribFormat ← MeshArena.recordAttributes:252`，且"MeshArena 里没有任何 GLCapabilities 引用"。

**两者同时成立，但不是"没有降级层"，而是"降级层被自己的门控关掉了"：**

`MeshArena.recordAttributes:252` 调用的**不是** `GL43C.*`，而是 jar 内自带的垫片 `viewpoint.mac41.Draws41.glVertexAttribFormat`。该垫片第一行就是门控：

```java
// viewpoint/mac41/Draws41.java（javap 还原）
public static void glVertexAttribFormat(int, int, int, boolean, int);
   0: invokestatic  #78   // Mac41.nativeVertexPath:()Z
   3: ifeq          16     // false -> 走垫片模拟
   6: ...                  // true  -> 直呼真 GL4.3
  12: invokestatic  #208  // org/lwjgl/opengl/GL43.glVertexAttribFormat:(IIIZI)V
```

而 `org.lwjgl.opengl.GL43.glVertexAttribFormat` 静态方法内部就是转发到 `GL43C` 实例方法 ——
这正是栈帧 `GL43C.glVertexAttribFormat` 的来源。**即：`nativeVertexPath()` 返回了 `true`。**

而 `Mac41.nativeVertexPath()` 在"垫片未激活"时**默认返回 true**：

```java
public static boolean nativeVertexPath();
   0: invokestatic  #94   // Mac41.active:()Z
   3: ifne          8
   6: iconst_1            // <== !active()  ->  return true  （"假定原生 GL4.3 可用"）
   7: ireturn
   8: invokestatic  #76   // Mac41.nativeCapabilities:()GLCapabilities
  12: aload_0
  13: getfield      #97   // GLCapabilities.glVertexAttribFormat:J
  16: lconst_0
  17: lcmp
  18: ifeq          97    // ==0 -> false
   ... (共 9 个函数指针全部非 0 才返回 1)
  93: iconst_1
  94: goto          98
  97: iconst_0
  98: ireturn
```

`Mac41.active()` 要求 **core profile**：

```java
public static boolean active();
   0: getstatic     #61   // Mac41.MAC:Z          (os.name startsWith "Mac")
   3: ifne          8
   6: iconst_0
   7: ireturn              // 非 Mac -> false
   ...
  39: invokestatic  #76   // Mac41.nativeCapabilities:()GLCapabilities
  43: aload_2
  44: getfield      #79   // GLCapabilities.OpenGL41:Z
  47: ifeq          64
  50: ldc           #84   // int 37158   == GL_CONTEXT_PROFILE_MASK
  52: invokestatic  #85   // GL11.glGetInteger:(I)I
  55: iconst_1            // GL_CONTEXT_CORE_PROFILE_BIT
  56: iand
  57: ifeq          64
  60: iconst_1
  61: goto          65
  64: iconst_0
```

⇒ **在 macOS 上只要上下文不是 4.1 core，整个 mac41 垫片会自我关闭，然后回落到"原生 GL4.3"，而 Apple 的驱动从来不导出这些入口**（§5 的 dlsym 探针证明），于是必然在 `GL43C.glVertexAttribFormat` 空指针崩溃 —— 与题设栈完全一致。

这是一个**门控失败（activation failure）**，不是"缺少模拟层"。而且本机安装实例的 console.txt 显示，在上下文确实是 4.1 core 时**这套模拟是跑通的**（§8）。

---

## 1. 取样与哈希核对（已验证）

两个位置的 jar **完全一致**，因此后续只分析一份：

```
$ shasum -a 256 "<workshop>/…/ViewpointMac41Patch/common/tools/payload/Viewpoint.jar"
9d8d4890a2657cc16a73a8a56cd7cbb6cd2ae74586d6cbf5dac0c1218e02e3eb  …payload/Viewpoint.jar

$ shasum -a 256 "<instance>/…/mods/Viewpoint/42/media/java/client/Viewpoint.jar"
9d8d4890a2657cc16a73a8a56cd7cbb6cd2ae74586d6cbf5dac0c1218e02e3eb  …Viewpoint.jar
```

安装实例的 jar 由 `find` 定位得到：

```
$ find ~/Library/Application\ Support/ViewpointMac41 -name 'Viewpoint.jar'
/Users/liubinbin/Library/Application Support/ViewpointMac41/versions/0.1.0-alpha1-currentpack-private1/userdata/Zomboid/mods/Viewpoint/42/media/java/client/Viewpoint.jar
```

`installation.properties` / `installer/pins.properties` 交叉印证了同一哈希：

```
payload.Viewpoint.jar=9d8d4890a2657cc16a73a8a56cd7cbb6cd2ae74586d6cbf5dac0c1218e02e3eb
payload.pz-mac41-bridge.jar=85c45fd301d1aafd81e60d14ab26c25e6eead46352335b974748f1a20f0d850f
game.sha256=e1a69eb743ede60b213a0fe7f8b83d4fcab773036d256cc4543a336f3b058a33
game.version=42.21.0
runtime.version=25.0.1
```

jar 内共 **699 个 class**，解压到 `/tmp/mac41/b/x/`。

### 1.0 关键架构更正：这里其实有**两层**降级

| 层 | 载体 | 机制 | 覆盖 |
|----|------|------|------|
| **A. jar 内 Java 垫片** | `Viewpoint.jar` 内的 `viewpoint/mac41/*`（30 个 class） | 把 GL4.2+ 调用翻译成 GL4.1 调用（`glVertexAttribPointer` 等），门控 `Mac41.active()` / `Mac41.nativeVertexPath()` | **32** 个 GL4.2+ 函数 |
| **B. 启动前 Java agent** | `pz-mac41-bridge.jar`（ASM + libffi，`Premain-Class: pzmac41.Agent`） | 把 libffi 闭包（回调）**写进 `GLCapabilities` 的函数指针槽**，让 4.1 core 上下文的游戏走 GL1.x 立即模式/固定管线（PZ 本体大量使用） | 63 个回调，其中 GL4.2+ **仅 1 个**（`glClearTexImage`） |

`pz-mac41-bridge.jar` 与 `Viewpoint.jar` 是**两个独立产物**，`Viewpoint.jar` 里的 `viewpoint.mac41.Mac41` 通过反射访问 bridge：

```java
// viewpoint/mac41/Mac41$BridgeAccess
private static java.lang.reflect.Method find(java.lang.String, java.lang.Class<?>...);
   0: ldc  #7   // String pzmac41.Bridge
   2: invokestatic #9  // Class.forName:(Ljava/lang/String;)Ljava/lang/Class;
   ...
  static {};
   0: ldc #21  // String nativeCapabilities  -> Mac41$BridgeAccess.NATIVE
  12: ldc #32  // String active              -> Mac41$BridgeAccess.ACTIVE
  24: ldc #37  // String onDestroy           -> Mac41$BridgeAccess.DESTROY
```

⇒ 所以题设"MeshArena 里没有 GLCapabilities 引用"是对的，但**门控不在 MeshArena**，而在它调用的垫片里。

---

## 2. Q1 — MeshArena 的完整用法（已验证）

命令：

```bash
cd /tmp/mac41/b/x
javap -p -c -constants -cp . viewpoint.render.MeshArena    > /tmp/mac41/b/MeshArena.javap.txt   # 941 行
javap -p -v -constants -cp . viewpoint.render.MeshArena    > /tmp/mac41/b/MeshArena.verbose.txt
javap -p -c -l -cp . viewpoint.render.MeshArena            # LineNumberTable
```

### 2.1 常量（`-constants` 原始输出）

```
  static final int RECORD_FLOATS = 12;
  private static final int LOCATION_OFFSET = 6;
  private static final int LOCATION_FADE = 7;
  private static final int LOCATION_BELOW = 8;
  private static final int RECORDS = 6;
  private static final int VERTEX_BYTES = 56;
  private static final int START_VERTICES = 1048576;
  private static final int START_ROWS = 16;
```

`viewpoint.platform.VertexFormat`：

```
  public static final int[] ATTRIBUTE_SIZES;
  public static final int STRIDE = 14;      // 14 floats = 56 bytes
  public static final int FLAGS_ATTRIBUTE = 5;
  ...
  public static final int PLANT_FLOATS = 12;
  public static final int PLANT_VERTICES = 6;
```

`ATTRIBUTE_SIZES` 的 `<clinit>`：

```
   0: bipush 6
   2: newarray int
   5: iconst_0 / 6: iconst_3 / iastore     -> [0]=3
   9: iconst_1 / 10: iconst_2 / iastore    -> [1]=2
  13: iconst_2 / 14: iconst_4 / iastore    -> [2]=4
  17: iconst_3 / 18: iconst_3 / iastore    -> [3]=3
  21: iconst_4 / 22: iconst_1 / iastore    -> [4]=1
  25: iconst_5 / 26: iconst_1 / iastore    -> [5]=1
  28: putstatic #9  // ATTRIBUTE_SIZES:[I
```

⇒ `ATTRIBUTE_SIZES = {3,2,4,3,1,1}`，**只有 6 个元素（attrib 0..5）**，合计 14 floats = 56 bytes = `STRIDE*4` = `VERTEX_BYTES`。**它是自洽的**。

### 2.2 MeshArena 调用的每一个 GL/organization 函数，按调用点顺序

`MeshArena` 自身**只**引用 `GL11 / GL15 / GL20 / GL30 / GL31` 与 `viewpoint.mac41.*`（`javap -v` 常量池穷举）：

```
$ grep -n 'lwjgl/opengl' MeshArena.verbose.txt
#89 = Utf8        org/lwjgl/opengl/GL11
#94 = Methodref   GL11.glGetInteger:(I)I
#96 = Utf8        org/lwjgl/opengl/GL15
#101= Methodref   GL15.glGenBuffers:()I
#108= Methodref   GL15.glBindBuffer:(II)V
#135= Methodref   GL15.glBufferData:(IJI)V
#150= Utf8        org/lwjgl/opengl/GL30
#154= Methodref   GL30.glGenVertexArrays:()I
#173= Methodref   GL11.glGenTextures:()I
#247= Methodref   GL15.glBufferSubData:(IJLjava/nio/FloatBuffer;)V
#304= Utf8        org/lwjgl/opengl/GL31
#309= Methodref   GL31.glCopyBufferSubData:(IIJJJ)V
#312= Methodref   GL15.glDeleteBuffers:(I)V
#324= Utf8        org/lwjgl/opengl/GL20
#328= Methodref   GL20.glEnableVertexAttribArray:(I)V
#336= Methodref   GL20.glVertexAttribPointer:(IIIZIJ)V
#354= Methodref   GL31.glTexBuffer:(III)V
#391= Methodref   GL11.glPixelStorei:(II)V
```

**MeshArena 里没有任何 `GL4x` 直接引用**（`grep -rla 'org/lwjgl/opengl/GL4[0-9]'` 的 12 个类不含 MeshArena）。它的 4.3 需求全部经 `viewpoint.mac41.*`。

按调用点顺序：

| # | 调用点 | 实际调用 | GL 版本 |
|---|--------|----------|---------|
| 1 | `init()` | `Draws41.glBindVertexArray` ×2（间接） | GL30 |
| 2 | `init()` | `GL11.glGetInteger(GL_ARRAY_BUFFER_BINDING=34964)` | GL1.5 |
| 3 | `init()` | `GL11.glGetInteger(GL_TEXTURE_BINDING_2D=32873)` | GL1.1 |
| 4 | `init()` | `GL15.glGenBuffers` | GL1.5 |
| 5 | `init()` | `GL15.glBindBuffer(GL_ARRAY_BUFFER, vb)` | GL1.5 |
| 6 | `init()` | `GL15.glBufferData(ARRAY_BUFFER, capacity*56, GL_DYNAMIC_DRAW=35048)` | GL1.5 |
| 7 | `init()` | `GL30.glGenVertexArrays` → `vao` | GL3.0 |
| 8 | `init()`→`pointAttributes()` | `Draws41.glBindVertexArray(vao)` | GL30 |
| 9 | `pointAttributes()` | `GL15.glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)` | GL1.5 |
| 10 | `pointAttributes()` 循环 i=0..5 | `GL20.glEnableVertexAttribArray(i)` ×6 | GL2.0 |
| 11 | `pointAttributes()` i=5 | **`Draws41.glVertexAttribIPointer(5, 1, GL_INT=5124, 56, offset)`** | GL30 |
| 12 | `pointAttributes()` i≠5 | `GL20.glVertexAttribPointer(i, sizes[i], GL_FLOAT=5126, false, 56, offset)` ×5 | GL2.0 |
| 13 | `pointAttributes()` | **`recordAttributes()`**（见 §2.3） | GL4.3 |
| 14 | `pointAttributes()` | `Draws41.glBindVertexArray(0)`；`GL15.glBindBuffer(ARRAY_BUFFER,0)` | — |
| 15 | `init()` | `GL30.glGenVertexArrays` → `plantVao` | GL3.0 |
| 16 | `init()` | `Draws41.glBindVertexArray(plantVao)` → `recordAttributes()`（**不再 pointAttributes**） | GL4.3 |
| 17 | `init()` | `GL11.glGenTextures` → `slotTexture` | GL1.1 |
| 18 | `init()`→`pointSlots()` | `Units41.glBindTexture`；**`GL31.glTexBuffer(GL_TEXTURE_BUFFER=35882, GL_R32UI=33328, vertexBuffer)`** | GL3.1 |
| 19 | `init()`→`lightTexture()` | **`Textures41.glCreateTextures` + `Textures41.glTextureParameteri` ×4 + `Textures41.glTextureStorage2D`** | GL4.5 |
| 20 | `init()` | `GL15.glBindBuffer(ARRAY_BUFFER, savedBinding)`；`Units41.glBindTexture(TEXTURE_2D, saved)` — **恢复** | — |
| 21 | `upload()` | `GL15.glBindBuffer` + `GL15.glBufferSubData(offset=firstVertex*56, buf)` + 解绑 | GL1.5 |
| 22 | `grow()` | `GL15.glGenBuffers`；`GL15.glBufferData`；**`GL31.glCopyBufferSubData(GLenum,GLenum,0,0,n*56)`**；`GL15.glDeleteBuffers`；→ `pointAttributes()`；→ `pointSlots()` | GL3.1 |
| 23 | `takeSlot()` 耗尽时 | `GL11.glGetInteger(GL_MAX_TEXTURE_SIZE=3379)`；**`Textures41.glCopyImageSubData(...)`**；`Textures41.glDeleteTextures` | GL4.3 |
| 24 | `uploadLight()` | `GL11.glPixelStorei(GL_UNPACK_ALIGNMENT=3317, 4)`；**`Textures41.glTextureSubImage2D(...)`** | GL4.5 |
| 25 | `bindLight/unbindLight` | `Units41.glActiveTexture` / `Units41.glBindTexture` | GL1.3 |
| 26 | `bindForModels()` | `Units41.glActiveTexture`/`glBindTexture`；**`Ranges41.glTexBufferRange(GL_TEXTURE_BUFFER, GL_RGBA32F=34836, recordBuffer, recordsAt, recordBytes)`** | GL4.3 |
| 27 | `beginDraws()` | `GL15.glBindBuffer(GL_DRAW_INDIRECT_BUFFER=36671, commandBuffer)`；`Draws41.glBindVertexArray(vao)`；**`Draws41.glBindVertexBuffer(6, recordBuffer, recordsAt, 48)`** | GL4.3 |
| 28 | `beginPlants()` | `Draws41.glBindVertexArray(plantVao)`；**`Draws41.glBindVertexBuffer(6, recordBuffer, recordsAt, 48)`** | GL4.3 |
| 29 | `multiDraw()` | **`Draws41.glMultiDrawArraysIndirect(GL_TRIANGLES, commandsAt+first*16, count, 16)`** | GL4.3 |
| 30 | `endDraws()` | `Draws41.glBindVertexArray(0)`；`GL15.glBindBuffer(GL_DRAW_INDIRECT_BUFFER, 0)` | — |

> 说明：`viewpoint/platform/Gl.triangles()`、`FrameStream.put/buffer/textureAlignment`、`Profile.*` 是纯 Java/CPU 记账，不产生 GL 调用。

### 2.3 `pointAttributes()` / `recordAttributes()` 的 attribute → (size, type, normalized, relativeOffset)

**`pointAttributes()`（原始字节码，节选）：**

```
  private static void pointAttributes();
   0: getstatic  #156  // Field vao:I
   3: invokestatic #167 // Draws41.glBindVertexArray:(I)V
   6: ldc  #104  // int 34962              (GL_ARRAY_BUFFER)
   8: getstatic #103 // Field vertexBuffer:I
  11: invokestatic #108 // GL15.glBindBuffer:(II)V
  14: lconst_0  /  15: lstore_0             (offset = 0L)
  16: iconst_0  /  17: istore_2             (i = 0)
  18: iload_2 / 19: getstatic #323 // VertexFormat.ATTRIBUTE_SIZES:[I
  22: arraylength / 23: if_icmpge 88
  26: iload_2 / 27: invokestatic #328 // GL20.glEnableVertexAttribArray:(I)V
  30: iload_2 / 31: iconst_5 / 32: if_icmpne 53
  35: iload_2
  36: getstatic #323 // ATTRIBUTE_SIZES
  39: iload_2 / 40: iaload
  41: sipush 5124                            (GL_INT)
  44: bipush 56                              (stride)
  46: lload_0
  47: invokestatic #332 // Draws41.glVertexAttribIPointer:(IIIIJ)V
  50: goto 69
  53: iload_2
  54: getstatic #323 // ATTRIBUTE_SIZES
  57: iload_2 / 58: iaload
  59: sipush 5126                            (GL_FLOAT)
  62: iconst_0                               (normalized = false)
  63: bipush 56                              (stride = 56 bytes)
  65: lload_0                               (byte offset)
  66: invokestatic #336 // GL20.glVertexAttribPointer:(IIIZIJ)V
  69: lload_0
  70: getstatic #323 // ATTRIBUTE_SIZES
  73: iload_2 / 74: iaload / 75: i2l
  76: ldc2_w #337 // long 4l
  79: lmul / 80: ladd / 81: lstore_0          (offset += sizes[i]*4)
  82: iinc 2, 1 / 85: goto 18
  88: invokestatic #170 // Method recordAttributes:()V
  91: iconst_0 / 92: invokestatic #167 // Draws41.glBindVertexArray:(0)V
  95: ldc #104 (34962) / 97: iconst_0 / 98: invokestatic #108 // GL15.glBindBuffer(II)V
 101: return
```

⇒ attrib 0..5：**`stride` 恒为 56 字节**，`offset` 累加 `sizes[i]*4`：

| attrib | size | type | normalized | byte offset |
|--------|------|------|-----------|-------------|
| 0 | 3 | GL_FLOAT 5126 | false | 0 |
| 1 | 2 | GL_FLOAT 5126 | false | 12 |
| 2 | 4 | GL_FLOAT 5126 | false | 20 |
| 3 | 3 | GL_FLOAT 5126 | false | 36 |
| 4 | 1 | GL_FLOAT 5126 | false | 48 |
| 5 | 1 | **GL_INT 5124** | (整数属性) | 52 |

累加至 56 ✓。**attrib 5 是整数属性**，走 `glVertexAttribIPointer`（**不是** `glVertexAttribPointer`）。

**`recordAttributes()`（完整字节码）：**

```
  private static void recordAttributes();
   0: bipush 6
   2: invokestatic #328 // GL20.glEnableVertexAttribArray:(I)V
   5: bipush 6
   7: iconst_4
   8: sipush 5126                                  (GL_FLOAT)
  11: iconst_0                                     (normalized = false)
  12: iconst_0                                     (relativeOffset = 0)
  13: invokestatic #342 // Draws41.glVertexAttribFormat:(IIIZI)V
  16: bipush 6
  18: bipush 6
  20: invokestatic #345 // Draws41.glVertexAttribBinding:(II)V      attrib 6 -> binding 6
  23: bipush 7
  25: invokestatic #328 // GL20.glEnableVertexAttribArray:(I)V
  28: bipush 7
  30: iconst_4
  31: sipush 5126
  34: iconst_0
  35: bipush 16                                    (relativeOffset = 16)
  37: invokestatic #342 // Draws41.glVertexAttribFormat:(IIIZI)V
  40: bipush 7
  42: bipush 6
  44: invokestatic #345 // Draws41.glVertexAttribBinding:(II)V      attrib 7 -> binding 6
  47: bipush 8
  49: invokestatic #328 // GL20.glEnableVertexAttribArray:(I)V
  52: bipush 8
  54: iconst_4
  55: sipush 5126
  58: iconst_0
  59: bipush 32                                    (relativeOffset = 32)
  61: invokestatic #342 // Draws41.glVertexAttribFormat:(IIIZI)V
  64: bipush 8
  66: bipush 6
  68: invokestatic #345 // Draws41.glVertexAttribBinding:(II)V      attrib 8 -> binding 6
  71: bipush 6
  73: iconst_1
  74: invokestatic #348 // Draws41.glVertexBindingDivisor:(II)V      binding 6 divisor = 1
  77: return
```

**答案：**

| attrib | size | type | normalized | relativeOffset | binding | divisor |
|--------|------|------|-----------|----------------|---------|---------|
| 6 (`LOCATION_OFFSET`) | 4 | GL_FLOAT 5126 | **false** | **0** | **6** | **1** |
| 7 (`LOCATION_FADE`) | 4 | GL_FLOAT 5126 | **false** | **16** | **6** | **1** |
| 8 (`LOCATION_BELOW`) | 4 | GL_FLOAT 5126 | **false** | **32** | **6** | **1** |

- attribute 6/7/8 分别是 `LOCATION_OFFSET` / `LOCATION_FADE` / `LOCATION_BELOW`（各一个 `vec4`，`RECORD_FLOATS = 12` = 3×4）。
- **binding 索引并不总是等于 attribute 索引**：attrib 7→binding 6，attrib 8→binding 6。只有 attrib 6 恰好 binding==attrib。
- `divisor = 1`（`glVertexBindingDivisor(6, 1)`）⇒ **是实例化渲染**；每个实例读一条 48 字节的 record。

### 2.4 `glBindVertexBuffer` 在哪调用、binding/buffer/offset/stride 来源

**只有两处**（`beginDraws` 与 `beginPlants`），都在 `MeshArena` 内：

```
  public static void beginDraws();
   0: getstatic #477 // commands:IntBuffer
   3: invokevirtual #489 // IntBuffer.flip
   7: getstatic #477 / 10: iconst_4 / 11: invokestatic #492 // FrameStream.put:(Ljava/nio/IntBuffer;I)J
  14: putstatic #494 // commandsAt:J
  17: invokestatic #461 // FrameStream.buffer:()I
  20: putstatic #496 // commandBuffer:I
  23: ldc_w #497 // int 36671                       (GL_DRAW_INDIRECT_BUFFER)
  26: getstatic #496 / 29: invokestatic #108 // GL15.glBindBuffer:(II)V
  32: getstatic #156 // vao:I
  35: invokestatic #167 // Draws41.glBindVertexArray:(I)V
  38: bipush 6
  40: getstatic #463 // recordBuffer:I
  43: getstatic #458 // recordsAt:J
  46: bipush 48                                     (stride = 48 bytes)
  48: invokestatic #501 // Draws41.glBindVertexBuffer:(IIJI)V
  51: return

  static void beginPlants(int);
   0: getstatic #161 // plantVao:I
   3: invokestatic #167 // Draws41.glBindVertexArray:(I)V
   6: bipush 6
   8: getstatic #463 // recordBuffer:I
  11: getstatic #458 // recordsAt:J
  14: bipush 48
  16: invokestatic #501 // Draws41.glBindVertexBuffer:(IIJI)V
  ... (然后绑 slotTexture)
```

- **binding = 6**（硬编码常量，与 `LOCATION_OFFSET` 同值，但语义是 binding 槽位）。
- **buffer = `recordBuffer`**：来自 `uploadRecords()` →
  ```
  public static void uploadRecords();
   0: getstatic #426 // records:FloatBuffer
   3: invokevirtual #443 // FloatBuffer.flip
   7: getstatic #426 / 10: invokevirtual #446 // FloatBuffer.remaining
  13: i2l / 14: ldc2_w #337 (4l) / 17: lmul
  18: putstatic #448 // recordBytes:J
  21: getstatic #426
  24: bipush 16 / 26: invokestatic #453 // FrameStream.textureAlignment:()I
  29: invokestatic #296 // Math.max:(II)I
  32: invokestatic #456 // FrameStream.put:(Ljava/nio/FloatBuffer;I)J
  35: putstatic #458 // recordsAt:J
  38: invokestatic #461 // FrameStream.buffer:()I
  41: putstatic #463 // recordBuffer:I
  44: return
  ```
  ⇒ `recordBuffer` 是 **`FrameStream` 的每帧环形缓冲**（不是持久 VBO），`recordsAt` 是该帧 record 数组的字节偏移，`recordBytes = remaining*4`。
- **offset = `recordsAt`**（字节），**stride = 48** 字节。
- 同时 `bindForModels()` 把**同一** `recordBuffer`/`recordsAt`/`recordBytes` 以 `Ranges41.glTexBufferRange(GL_TEXTURE_BUFFER, GL_RGBA32F, …)` 绑成 buffer texture，供 shader 用 `texelFetch` 读同一份 record。

**几何数据（attrib 0..5）的模式：** 单一共享 VBO `vertexBuffer`，每 mesh 的数据位于 `vertexIndex*56` 字节；`upload()` 用 `glBufferSubData(firstVertex*56, …)` 写入；`allocate()/release()` 用 `TreeMap` 做首次适配的空闲区间合并。

⇒ **回答："同一份共享 VBO + 每个 mesh 不同 offset" 正确**（对 attrib 0..5）。而 **attrib 6..8 用的是另一个每帧环形 buffer（binding 6）**，两者在同一个 VAO 里混合。

这决定了经典路径的约束：`glVertexAttribPointer` 在**指针指定时刻**捕获当前 `GL_ARRAY_BUFFER`，所以
1. 只要 `vertexBuffer` 换对象（`grow()`）就必须**重发指针** —— MeshArena 正是这么做的（`grow()` 末尾 `pointAttributes()`；且 `pointAttributes()` 内部的 `recordAttributes()` 也会重发 6..8）；
2. binding 6 因为 buffer 每帧变，必须在每次绘制前重发 —— MeshArena 正是这么做的（`beginDraws`/`beginPlants` 每次调 `glBindVertexBuffer`）。

### 2.5 `glVertexAttribDivisor` 的用法

`MeshArena` **不直接**调用 `glVertexAttribDivisor`；它用 4.3 的 `glVertexBindingDivisor(6, 1)`（见 §2.3 尾部）。
垫片 `Draws41.apply()` 对每个"已定义 attrib"调用 `divisor(attrib, bindings[attr.binding].divisor)`，最终落到：

```
  private static void divisor(int, int);
   0: invokestatic #33  // GL.getCapabilities:()Lorg/lwjgl/opengl/GLCapabilities;
   4: aload_2 / 5: getfield #331 // GLCapabilities.OpenGL33:Z
   8: ifeq 19
  11: iload_0 / 12: iload_1 / 13: invokestatic #334 // GL33.glVertexAttribDivisor:(II)V
  19: aload_2 / 20: getfield #339 // GLCapabilities.GL_ARB_instanced_arrays:Z
  23: ifeq 34
  26: ... #342 // ARBInstancedArrays.glVertexAttribDivisorARB:(II)V
  34: new UnsupportedOperationException "Instance attributes require ARB_instanced_arrays"
```

⇒ **divisor = 1 ⇒ 实例化渲染**（instanced）。`MeshArena` 的 `multiDraw` 传的是 `count` = 实例数，配合 `glMultiDrawArraysIndirect` 的 `instanceCount`。macOS 4.1 core 有 `glVertexAttribDivisor`（`OpenGL33 = true`，探针也确认符号 NON-NULL）。

### 2.6 有没有 `glVertexAttribIPointer` / `glVertexAttribIFormat` 分支

**两者都有，但用途不同：**

- `MeshArena.pointAttributes()` 对 **attrib 5** 调 `Draws41.glVertexAttribIPointer(5, 1, GL_INT, 56, offset)`。
  这是"经典路径"的整数指针：
  ```
  public static void glVertexAttribIPointer(int, int, int, int, long);
   0: invokestatic #33  // GL.getCapabilities
   5: getfield #317 // GLCapabilities.OpenGL30:Z
  10: ifeq 25
  13: ... #320 // GL30.glVertexAttribIPointer:(IIIIJ)V
  25: getfield #321 // GLCapabilities.GL_EXT_gpu_shader4:Z
  30: ifeq 45
  33: ... #324 // EXTGPUShader4.glVertexAttribIPointerEXT:(IIIIJ)V
  45: throw new UnsupportedOperationException("Integer attributes require EXT_gpu_shader4")
  ```
  **关键：这个方法是纯直通，不写入垫片的影子状态**（没有 `Attribute.defined = true`）。所以 attrib 5 的整数指针永远不会被 `apply()` 重写。
- `Draws41.glVertexAttribIFormat`（4.3 形态）**存在且完整实现了模拟分支**：
  ```
  public static void glVertexAttribIFormat(int, int, int, int);
   0: invokestatic #78 // Mac41.nativeVertexPath:()Z
   3: ifeq 14
   6: ... #239 // GL43.glVertexAttribIFormat:(IIII)V
  14: ...  // 影子状态：format(attr, size, type, relative) + attr.integer=true + attr.normalized=false + apply(0)
  ```
  但 **`MeshArena` 不用它**（`MeshArena` 里没有 `glVertexAttribIFormat` 调用点）。它由 `viewpoint.mac41` 之外/其它渲染器（如 Iris/模型路径）使用，或为完整性而实现。

### 2.7 MeshArena 里 GL 状态怎么管理

| 状态 | 做法 | 字节码证据 |
|------|------|-----------|
| **自己 bind VAO** | 是。`pointAttributes` 先 `Draws41.glBindVertexArray(vao)`；`beginDraws` 先 `glBindVertexArray(vao)`；`beginPlants` 先 `glBindVertexArray(plantVao)`；用完全部 `glBindVertexArray(0)` | `pointAttributes` off 0-3；`beginDraws` off 32-35；`beginPlants` off 0-3；`pointAttributes` off 91-92；`endDraws` off 0-1 |
| **保存/恢复 `GL_ARRAY_BUFFER` 绑定** | **是**（`init` 内）。进入时 `glGetInteger(34964)`，退出时 `glBindBuffer(34962, saved)` | `init` off 11-16 保存；off 155-158 恢复 |
| **保存/恢复 `GL_TEXTURE_BINDING_2D`** | **是** | `init` off 17-22 保存；off 161-165 `Units41.glBindTexture(3553, saved)` |
| **恢复 `GL_DRAW_INDIRECT_BUFFER`** | 是（`endDraws` 解绑） | `endDraws` off 4-8 |
| **"绘制时假定某 binding 已绑定 buffer"** | **有，而且是刻意设计**。`plantVao` 在 `init` 时**只**经 `recordAttributes()` 配置了 attrib 6/7/8（**没有** attrib 0..5，因为 `pointAttributes()` 只对 `vao` 调用）；所以 `plantVao` 完全依赖 `beginPlants()` 的 `glBindVertexBuffer(6, recordBuffer, recordsAt, 48)` 提供顶点源 | `init` off 98-114（plantVao：仅 `recordAttributes()`） |
| **attrib 0..5 与 6..8 在同一 VAO 混用** | `vao` = 经典指针（0..5，来自 `vertexBuffer`）+ 4.3 binding（6..8，来自 `recordBuffer`） | §2.3 + §2.4 |
| **`grow()` 后重发指针** | 是（`pointAttributes()` + `pointSlots()`） | `grow` off 94-97 |

**结论：MeshArena 自己做了 `GL_ARRAY_BUFFER` / `GL_TEXTURE_BINDING_2D` 的保存恢复，不需要外层帮忙；但它依赖 `Draws41` 垫片在 `glBindVertexBuffer` 时把 binding 6 的 buffer 正确"安装"到 VAO 的指针里。**

---

## 3. Q2 — 出口/门控（已验证）

### 3.1 MeshArena 自身：**零门控**

```bash
$ grep -n 'GLCapabilities\|getCapabilities\|OpenGL4\|getProperty\|getBoolean\|catch' MeshArena.javap.txt
（无输出）
$ javap -p -c -constants -cp . viewpoint.render.MeshArena | grep -oE 'Method [a-z/.]+' | grep -i 'capab\|glgetstring\|opengl4' 
（无输出）
```

`MeshArena` 的 `Exception table` 只有编译器为 try-with-resources / synchronized 生成的条目，**没有任何能力检测或降级 try/catch**。

### 3.2 调用者 `Meshes.init` / `WorldRenderer.init`：**零门控**

```bash
$ javap -p -c -constants -cp . viewpoint.render.Meshes       | grep -oE '(Method|Field) (viewpoint/mac41/Mac41\.[A-Za-z0-9_]+|org/lwjgl/opengl/GLCapabilities\.[A-Za-z0-9_]+|org/lwjgl/opengl/GL\.[A-Za-z0-9_]+|java/lang/System\.getProperty|java/lang/Boolean\.getBoolean)'
（无输出）
$ javap -p -c -constants -cp . viewpoint.render.WorldRenderer | grep -oE '...同上...'
（无输出）
```

⇒ `Meshes` 与 `WorldRenderer` **完全不引用** `Mac41`、`GLCapabilities`、`GL.*`、`System.getProperty`。

### 3.3 全局：`Mac41.require()` 的硬件门槛（唯一"检测"）

```java
// viewpoint/platform/Gl.class —— 唯一引用 Mac41 的非垫片非 Iris 类
$ javap -p -c -constants -cp . viewpoint.platform.Gl | grep -oE 'Method viewpoint/mac41/Mac41\.[A-Za-z0-9_]+'
Method viewpoint/mac41/Mac41.require

// Mac41.require()
public static void require();
   0: invokestatic #94   // Mac41.active:()Z
   3: ifne 7
   6: return
   7: ldc  #127 // int 35661  (GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS)
   9: invokestatic #85 // GL11.glGetInteger:(I)I  -> istore_0
  13: ldc  #128 // int 34930  (GL_MAX_TEXTURE_IMAGE_UNITS)
  15: glGetInteger -> istore_1
  19: ldc  #129 // int 34921  (GL_MAX_VERTEX_ATTRIBS)
  21: glGetInteger -> istore_2
  25: iload_0 / 26: bipush 80 / 28: if_icmplt 43
  31: iload_1 / 32: bipush 16 / 34: if_icmplt 43
  37: iload_2 / 38: bipush 16 / 40: if_icmpge 59
  43: new IllegalStateException  // "…" 拼接 (III)
  59: invokestatic #137 // Mac41.registerCleanup:()V
  62: invokestatic #141 // Timing41.timestampsSupported:()Z
  66: getstatic #146 // System.out
  69: sipush 7938  (GL_VERSION)
  72: GL11.glGetString
  75: ldc #156 // int 35724  (GL_SHADING_LANGUAGE_VERSION)
  77: GL11.glGetString
  ...
  93: invokevirtual #163 // PrintStream.println:(Ljava/lang/String;)V
```

**它只检查硬件下限（≥80 纹理单元 / ≥16 纹理 / ≥16 顶点属性），并且只在 `active()` 时执行**；它 **不**检查 GL4.2/4.3 能力，也**不**提供关闭 arena 的出口。

### 3.4 "跳过 arena" 能不能让 Viewpoint 继续跑？→ **不能**

`MeshArena` 是**唯一**的网格存储与绘制机制。引用它的类：

```bash
$ grep -rla 'viewpoint/render/MeshArena' --include='*.class' .
viewpoint/render/BandLight.class
viewpoint/render/ChunkMeshData.class
viewpoint/render/CorpseCards.class
viewpoint/render/FarPass.class
viewpoint/render/MeshArena.class
viewpoint/render/Meshes.class
viewpoint/render/PackDraws.class
viewpoint/render/TargetOutline.class
```

`Meshes` 用到：`init / beginDraws / endDraws / beginPlants / endPlants / multiDraw / records / commands / uploadRecords / bindLight / unbindLight`；
`PackDraws` 用到：`bindForModels / unbindForModels`。

⇒ `Meshes` 是 `WorldRenderer`/`SceneDrawer` 的唯一网格批次层。跳过 `MeshArena.init()` 会让后续 `upload()/records()/commands()/beginDraws()` 全部在 `null`/0 状态上工作 —— **不是"少了点特效"，而是"没有任何世界几何"**。jar 内**不存在**第二条网格渲染路径（没有第二个 Arena 实现、没有"软件路径"、没有 `if (unsupported) return` 分支）。

### 3.5 全局 `OpenGL4*` / `GLCapabilities` / `getCapabilities` 引用点清单

`grep -rla 'org/lwjgl/opengl/GLCapabilities'` 共 **21 个类**：

| 类 | 用途 | 是否对 GL4.2+ 门控 |
|----|------|-------------------|
| `viewpoint/mac41/Draws41` | 顶点管线垫片 | **是**（`nativeVertexPath` + `OpenGL33/OpenGL31/OpenGL32/ARB_*`） |
| `viewpoint/mac41/Textures41` | DSA 纹理垫片 | **是**（`Mac41.active` ×25、`nativeCapabilities` ×15） |
| `viewpoint/mac41/Ranges41` | TBO range / program uniform 垫片 | **是**（`Mac41.active` ×8） |
| `viewpoint/mac41/Buffers41` | `glBufferStorage`（GL44）垫片 | **是**（`Mac41.active` ×4） |
| `viewpoint/mac41/Mac41` (+`$Selection`,`$NativeEntry`) | 门控本体 | — |
| `viewpoint/mac41/Samplers41` | 采样器对象垫片 | **是**（`Mac41.active` ×3） |
| `viewpoint/mac41/Samplers41$State` | 状态 | — |
| `viewpoint/mac41/ShadowArray41` (+`$State`) | 阴影数组纹理 | 间接（经 `State41` → `Mac41.active`） |
| `viewpoint/mac41/Draws41$State` | 状态 | — |
| `viewpoint/platform/GlDebug` | `glPushDebugGroup/glPopDebugGroup/glDebugMessageCallback`（GL43） | **是**：`caps.OpenGL43 \|\| caps.GL_KHR_debug` |
| `viewpoint/platform/FrameTimes`, `Hardware`, `VideoMemory`, `IrisPacks` | 硬件/驱动信息查询 | 与 4.2+ 无关 |
| `viewpoint/render/FloorSlices`, `TextureFilter`, `IrisPipeline` | `IrisPipeline` 有 `Mac41.rejectExternalIris()` + `caps.OpenGL40` 检查；另两个与 4.2+ 无关 | 部分 |

**未做门控的类（危险区）：**

| 类 | 未门控的 4.2+ 调用 | macOS 符号 |
|----|-------------------|-----------|
| `viewpoint/render/IrisFrame` | `GL43.glDispatchCompute`、`GL42.glMemoryBarrier` | **NULL** |
| `viewpoint/render/IrisImages` | `GL42.glBindImageTexture`、`GL43.glClearBufferData`、`GL42.glTexStorage1D/2D/3D`、`GL44.glClearTexImage` | `glBindImageTexture` **NULL**；`glTexStorage*` NON-NULL；`glClearTexImage` 由 bridge hook |
| `viewpoint/render/IrisTargets` | `GL44.glClearTexImage` | bridge hook |
| `viewpoint/render/IrisProgram` | （无 GL4x 直接引用；只有常量池残留） | — |
| `viewpoint/mac41/*` | 全部 4.2+ | **有门控** |

---

## 4. Q3 — 32/33 个 GL4.2+ 函数分别出现在哪些类/方法（已验证）

### 4.1 定位方法

```bash
cd /tmp/mac41/b/x
# 1) 先找出所有直接引用 GL4x 的类（class 文件的 UTF8 常量池必然含 "org/lwjgl/opengl/GL4x"）
grep -rla 'org/lwjgl/opengl/GL4[0-9]' --include='*.class' . | sed 's|^\./||' | sort
#   -> 只有 12 个类
# 2) 逐类用 javap 抽出精确的 GL4x 方法引用
for c in <12 个类>; do javap -p -c -constants -cp . $c | grep -oE 'org/lwjgl/opengl/GL4[2-9]\.[A-Za-z0-9_]+'; done | sort -u
```

12 个类：

```
viewpoint/mac41/Buffers41.class        viewpoint/render/IrisFrame.class
viewpoint/mac41/Draws41.class          viewpoint/render/IrisGeometry.class
viewpoint/mac41/Ranges41.class         viewpoint/render/IrisImages.class
viewpoint/mac41/Textures41.class       viewpoint/render/IrisProgram.class
viewpoint/platform/Gl.class            viewpoint/render/IrisTargets.class
viewpoint/platform/GlDebug.class       viewpoint/render/TranslucentPass.class
```

出现的 GL4x 包：`GL40, GL42, GL43, GL44, GL45`（`GL41`/`GL41C` 名字未作为类名出现，但 `glBlendFunci` 等经 `GL40`）。

### 4.2 完整的 GL4.2+ 函数表（33 个）

| # | 函数 | GL | 出现在 | 在渲染路径上？ | 被门控？ |
|---|------|----|--------|---------------|---------|
| 1 | `glDrawArraysInstancedBaseInstance` | 4.2 | `mac41/Draws41` | **是**（`MeshArena.multiDraw` 的实例绘制） | **是**（`nativeVertexPath`） |
| 2 | `glDrawElementsInstancedBaseVertexBaseInstance` | 4.2 | `mac41/Draws41` | 是（索引路径） | **是** |
| 3 | `glTexStorage1D` | 4.2 | `render/IrisImages` | 否（Iris 图像） | **否**（但 macOS 有符号） |
| 4 | `glTexStorage2D` | 4.2 | `mac41/Textures41`, `render/IrisImages` | 是（纹理创建） | 是 / **否** |
| 5 | `glTexStorage3D` | 4.2 | `mac41/Textures41`, `render/IrisImages` | 是（数组纹理） | 是 / **否** |
| 6 | `glMemoryBarrier` | 4.2 | `render/IrisFrame` | 否（Iris compute） | **否** |
| 7 | `glBindImageTexture` | 4.2 | `render/IrisImages` | 否（Iris 图像） | **否** |
| 8 | `glVertexAttribFormat` | 4.3 | `mac41/Draws41` | **是**（`MeshArena.recordAttributes`） | **是** |
| 9 | `glVertexAttribIFormat` | 4.3 | `mac41/Draws41` | 否（MeshArena 不用） | **是** |
| 10 | `glVertexAttribBinding` | 4.3 | `mac41/Draws41` | **是**（`MeshArena.recordAttributes`） | **是** |
| 11 | `glVertexBindingDivisor` | 4.3 | `mac41/Draws41` | **是**（`MeshArena.recordAttributes`） | **是** |
| 12 | `glBindVertexBuffer` | 4.3 | `mac41/Draws41` | **是**（`MeshArena.beginDraws/beginPlants`） | **是** |
| 13 | `glMultiDrawArraysIndirect` | 4.3 | `mac41/Draws41` | **是**（`MeshArena.multiDraw`） | **是** |
| 14 | `glMultiDrawElementsIndirect` | 4.3 | `mac41/Draws41` | 是（索引路径，MeshArena 用非索引） | **是** |
| 15 | `glTexBufferRange` | 4.3 | `mac41/Ranges41` | **是**（`MeshArena.bindForModels`） | **是** |
| 16 | `glCopyImageSubData` | 4.3 | `mac41/Textures41` | **是**（`MeshArena.takeSlot` 扩容） | **是** |
| 17 | `glPushDebugGroup` | 4.3 | `platform/GlDebug` | 否（debug） | **是**（`OpenGL43 \|\| GL_KHR_debug`） |
| 18 | `glPopDebugGroup` | 4.3 | `platform/GlDebug` | 否（debug） | **是** |
| 19 | `glDebugMessageCallback` | 4.3 | `platform/GlDebug` | 否（debug） | **是** |
| 20 | `glClearBufferData` | 4.3 | `render/IrisImages` | 否（Iris） | **否** |
| 21 | `glDispatchCompute` | 4.3 | `render/IrisFrame` | 否（Iris compute） | **否** |
| 22 | `glBufferStorage` | 4.4 | `mac41/Buffers41` | 是（持久映射缓冲） | **是** |
| 23 | `glClearTexImage` | 4.4 | `render/IrisImages`, `render/IrisTargets` | 否（Iris） | **否，但 bridge 有 hook** |
| 24 | `glCreateTextures` | 4.5 | `mac41/Textures41` | **是**（`MeshArena.init→lightTexture`） | **是** |
| 25 | `glTextureStorage2D` | 4.5 | `mac41/Textures41` | **是**（`MeshArena.lightTexture`） | **是** |
| 26 | `glTextureStorage3D` | 4.5 | `mac41/Textures41` | 是（数组纹理） | **是** |
| 27 | `glTextureSubImage2D` | 4.5 | `mac41/Textures41` | **是**（`MeshArena.uploadLight`） | **是** |
| 28 | `glTextureSubImage3D` | 4.5 | `mac41/Textures41` | 是（数组纹理上传） | **是** |
| 29 | `glTextureParameteri` | 4.5 | `mac41/Textures41` | **是**（`MeshArena.lightTexture`） | **是** |
| 30 | `glCreateFramebuffers` | 4.5 | `mac41/Textures41` | 是（FBO 创建） | **是** |
| 31 | `glNamedFramebufferDrawBuffer` | 4.5 | `mac41/Textures41` | 是（FBO 配置） | **是** |
| 32 | `glNamedFramebufferReadBuffer` | 4.5 | `mac41/Textures41` | 是（FBO 配置） | **是** |
| 33 | `glNamedFramebufferTextureLayer` | 4.5 | `mac41/Textures41` | 是（分层 FBO 附着） | **是** |

### 4.3 与 bridge 的交集（解释"32 个 / 桥只覆盖 3 个"）

```bash
# bridge 的 CoreGl.registerHooks() 注册的回调名（javap 抽字符串常量）
$ sed -n '/private static void registerHooks()/,/private static void initState()/p' CoreGl.txt \
    | grep -oE '// String [A-Za-z0-9_]+' | sed 's|// String ||' | sort -u > hooks.txt
$ wc -l hooks.txt
      89
$ cat hooks.txt | tr '\n' ' '
glActiveTexture glAlphaFunc glBegin glBindBuffer glBindTexture glBindVertexArray glBlendEquation
glBlendEquationSeparate glBlendFunc glBlendFuncSeparate glClearColor glClearTexImage glClearTexSubImage
glColor3d glColor3f glColor4d glColor4f glColorMask glCompileShader glCullFace glDeleteProgram
glDeleteShader glDeleteTextures glDepthFunc glDepthMask glDepthRange glDisable glDisableClientState
glDisableVertexAttribArray glEnable glEnableClientState glEnableVertexAttribArray glEnd glFrontFace
glFrustum glGetError glGetString glIsEnabled glLineWidth glLinkProgram glLoadIdentity glLoadMatrixf
glMatrixMode glMultMatrixf glNormal3f glOrtho glPixelStorei glPolygonMode glPolygonOffset glPopAttrib
glPopClientAttrib glPopMatrix glPushAttrib glPushClientAttrib glPushMatrix glRotated glRotatef glScaled
glScalef glScissor glShaderSource glStencilFunc glStencilMask glStencilOp glTexCoord2d glTexCoord2f
glTexEnvf glTexEnvi glTranslated glTranslatef glUseProgram glVertex2d glVertex2f glVertex2i glVertex3d
glVertex3f glVertexAttrib1f glVertexAttrib2f glVertexAttrib3f glVertexAttrib4f glVertexAttrib4fv
glVertexAttribDivisor glVertexAttribI4i glVertexAttribI4iv glVertexAttribI4ui glVertexAttribI4uiv
glVertexAttribPointer glVertexPointer glViewport

# 与 33 个 GL4.2+ 求交
$ comm -12 <(sort gl42names.txt) <(sort hooks.txt)
glClearTexImage
$ comm -12 … | wc -l
       1
```

⇒ **33 个 GL4.2+ 函数中，bridge 只覆盖 1 个（`glClearTexImage`）；剩下 32 个必须由 jar 内 `viewpoint.mac41.*` 垫片兜住。**
这正是题设"32 个 / 桥只覆盖 3 个"的来源（"3" 若把 `glClearTexSubImage`、`glVertexAttribDivisor` 这类同族但 Viewpoint 未使用的名字算进去即得 3）。

**bridge 的 89 个 hook 名主要是"GL1.x 立即模式 / 固定管线 → core profile"的模拟**（`glBegin/glEnd/glVertex3f/glMatrixMode/glLoadIdentity/glOrtho/glFrustum/glEnableClientState/glVertexPointer/glAlphaFunc/glTexEnv*`），因为 PZ 本体（`zombie/core/opengl/VBORenderer`、`ShaderProgram`）使用了大量废弃 API。console.txt 记录实际注册 **63** 个回调：

```
LOG  : General      f:0> [PZMac41Bridge] macGlCore: OpenGL 4.1 Metal - 91.7, GLSL 4.10; core bridge on (63 implemented callbacks, forwardCompatible=true, native extension flags, OpenGL33 true, alpha test in shaders on)
```

### 4.4 除 MeshArena 之外的下一个**无门控** 4.2+ 撞点

分两种情况：

**(a) 如果 `Mac41.active() == true`（垫片生效）—— 渲染主路径没有无门控撞点。**
`MeshArena` 的所有 4.2+ 需求（#1,2,8,10,11,12,13,15,16,24,25,27,29）全部经有门控的 `Draws41`/`Ranges41`/`Textures41`。`GlDebug` 的三处也有门控。**唯一真正无门控的是 Iris 子系统**：

**(b) 无门控的确定撞点（按可能性排序）：**

1. **`IrisFrame.computes(...)` → `GL43.glDispatchCompute` + `GL42.glMemoryBarrier`**
   ```
   $ javap -p -c -constants -cp . viewpoint.render.IrisFrame
   IN METHOD:  private void computes(IrisPipeline, IrisPrograms$Pass, String, FrameContext, Set<Integer>)
      ...
      166: iload 10 / 168: iconst_1 / 169: invokestatic #699 // Math.max:(II)I
      172: iload 11 / 174: iconst_1 / 175: invokestatic #699 // Math.max:(II)I
      178: iload 12 / 180: iconst_1 / 181: invokestatic #699 // Math.max:(II)I
      184: invokestatic #703 // org/lwjgl/opengl/GL43.glDispatchCompute:(III)V
      187: iconst_m1
      188: invokestatic #711 // org/lwjgl/opengl/GL42.glMemoryBarrier:(I)V
   ```
   该方法的字节码里**没有任何 `GLCapabilities`/`Mac41`/`GL.*` 能力判断**。入口是 `IrisMode.draw(...)` 里对 `begin/shadowcomp/prepare/deferred/composite` 等 pass 的调度：
   ```
   $ javap -p -c -constants -cp . viewpoint.render.IrisMode | grep '// String'
   ... "minecraft shadow" "minecraft opaque" "opaque" "sky" "minecraft translucent" "translucent"
       "minecraft weather" "lightning" "begin" "shadowcomp" "prepare" "deferred" "composite"
   ```
   但这是 **Iris 着色器包子系统**，本机 `viewpoint-live.properties` 里 `graphics.mode=Vanilla`，所以默认不进入。

2. **`IrisImages.bind(IrisProgram)` → `GL42.glBindImageTexture`**
   ```
   void bind(viewpoint.render.IrisProgram);
      104: invokestatic #292 // org/lwjgl/opengl/GL42.glBindImageTexture:(IIIZIII)V
   ```
   无门控。仅当 Iris 包声明了 image uniform 时触达。
   `IrisPipeline` 对本机唯一的保护是：
   ```
   123: 0: invokestatic #147 // Method viewpoint/mac41/Mac41.rejectExternalIris:()V
   ```
   ```java
   public static void rejectExternalIris();
      0: Mac41.active:()Z / 3: ifeq 16
      6: new UnsupportedOperationException
     10: ldc #222 // "External Iris shader packs are outside the Viewpoint mac41 target; select a built-in Normal/Default/Vivid preset. No Iris GPU resources were created."
   ```
   ⇒ 只挡**外部** Iris 包；内置 `Normal/Default/Vivid` 包若用 compute/image 仍会撞。

3. **`MeshArena.init` 内部、紧随 `recordAttributes` 之后的下一个 4.2+ 调用**（仅在垫片失效时才有意义，但顺序上确实是下一个）：
   `init` 偏移 146-152 → `lightTexture(rows)` → `Textures41.glCreateTextures`（GL4.5）+ `glTextureStorage2D`。
   ```
   private static int lightTexture(int);
      0: sipush 3553 / 3: invokestatic #414 // Textures41.glCreateTextures:(I)I
      7: ...   8: sipush 10241 / 11: sipush 9729 / 14: invokestatic #417 // Textures41.glTextureParameteri:(III)V
     17-44: 另三次 glTextureParameteri
     47: iload_1 / 48: iconst_1 / 49: ldc_w #419 (32856 GL_RGBA8) / 52: sipush 4080
     55: iload_0 / 56: bipush 40 / 58: imul
     59: invokestatic #423 // Textures41.glTextureStorage2D:(IIIII)V
     62: iload_1 / 63: ireturn
   ```
   `Textures41` 全部 4.2+ 入口都以 `Mac41.active()` 门控（×25），所以垫片生效时这里安全。

4. **稳态每帧路径上的 4.2+ 调用点**（均在垫片内，垫片生效即安全，但都是"如果这块没垫好就会立刻炸"的位置）：
   - `MeshArena.bindForModels` → `Ranges41.glTexBufferRange`（GL4.3）
   - `MeshArena.multiDraw` → `Draws41.glMultiDrawArraysIndirect`（GL4.3）
   - `MeshArena.uploadLight` → `Textures41.glTextureSubImage2D`（GL4.5）
   - `MeshArena.takeSlot` 扩容 → `Textures41.glCopyImageSubData`（GL4.3）

---

## 5. 关键活体实验：Apple 驱动**从不导出**这 9 个函数（已验证）

这是整个分析的物理基础。`Mac41.nativeVertexPath()` 检查的正是这 9 个指针。
探针（`/tmp/mac41/b/probe/probe.m`，`clang -o probe probe.m && ./probe`）：

```
dlopen(/System/Library/Frameworks/OpenGL.framework/OpenGL) -> OK

symbol                                               dlsym result
---------------------------------------------------  ------------
glVertexAttribFormat                                 NULL
glVertexAttribIFormat                                NULL
glVertexAttribBinding                                NULL
glVertexBindingDivisor                               NULL
glBindVertexBuffer                                   NULL
glVertexAttribDivisor                                NON-NULL
glVertexAttribIPointer                               NON-NULL
glVertexAttribPointer                                NON-NULL
glDrawArraysInstancedBaseInstance                    NULL
glDrawElementsInstancedBaseVertexBaseInstance        NULL
glMultiDrawArraysIndirect                            NULL
glMultiDrawElementsIndirect                          NULL
glDrawElementsBaseVertex                             NON-NULL
glDrawElementsInstancedBaseVertex                    NON-NULL
glTexBuffer                                          NON-NULL
glCopyBufferSubData                                  NON-NULL
glTexStorage2D                                       NON-NULL
glTextureView                                        NULL
glDispatchCompute                                    NULL
glDebugMessageCallback                               NULL
glShaderStorageBlockBinding                          NULL
glBufferStorage                                      NULL
glGetPointerv                                        NON-NULL
glClearBufferfv                                      NON-NULL
glBlendFunci                                         NON-NULL
glFenceSync                                          NON-NULL
glInvalidateBufferData                               NULL
glTexStorage2DMultisample                            NULL
glMultiDrawArraysIndirectCount                       NULL
glTextureBarrier                                     NULL
glGetString                                          NON-NULL
```

第二批探针（`probe2`、`probe3`）：

```
glTexBufferRange                           NULL      glDrawArraysInstanced         NON-NULL
glTextureBufferRange                       NULL      glDrawElementsInstanced       NON-NULL
glCreateTextures                           NULL      glDrawArrays                  NON-NULL
glTextureStorage2D                         NULL      glDrawElements                NON-NULL
glTextureSubImage2D                        NULL      glTexBuffer                   NON-NULL
glCopyImageSubData                         NULL      glBindBufferRange             NON-NULL
glTextureParameteri                        NULL      glMapBufferRange              NON-NULL
glBindTextureUnit                          NULL      glMultiDrawArrays             NON-NULL
glTextureBuffer                            NULL      glProgramUniform1i            NON-NULL
glTextureSubImage3D                        NULL      glGetBufferSubData            NON-NULL
glTextureStorage3D                         NULL      glClientWaitSync              NON-NULL
glCheckNamedFramebufferStatus              NULL
glBlitNamedFramebuffer                     NULL
glBlendFunci                   NON-NULL   glClearTexImage                NULL
glBlendFuncSeparatei           NON-NULL   glClearTexSubImage             NULL
glBlendEquationi               NON-NULL   glDispatchCompute              NULL
glBlendEquationSeparatei       NON-NULL   glMemoryBarrier                NULL
glPatchParameteri              NON-NULL   glBindImageTexture             NULL
glGetStringi                   NON-NULL   glTexStorage1D                 NON-NULL
```

**读法：**
- Apple 的 macOS OpenGL 是 **4.1 上限**：`glTexBuffer`、`glCopyBufferSubData`、`glTexStorage1D/2D/3D`（经 `ARB_texture_storage`）、`glClearBufferfv`、`glBlendFunci`、`glBlendFuncSeparatei`、`glFenceSync`、`glGetPointerv` 都存在；`GL40`/`GL41` 与 `GL42` 的一小部分可用。
- **真正的 4.3 顶点管线 9 件套 + `glMultiDraw*Indirect`、`glCreateTextures/glTextureStorage*`DSA 全套、`glCopyImageSubData`、`glTexBufferRange`、`glBindImageTexture`、`glDispatchCompute`、`glMemoryBarrier`、`glTextureView`、`glBufferStorage` 全部 NULL。**
- ⇒ `Mac41.nativeVertexPath()` 在 macOS 上**永远不可能**因为"驱动真的有"而返回 true。所以它返回 true 的**唯一**途径就是 `!Mac41.active()` 这条短路。**这是纯粹的门控反相缺陷。**

### 5.1 触发 `active() == false` 的具体路径（已验证字节码）

`Mac41.active()` 需要"4.1 **core**"。而 bridge 自己**故意**提供了一条降级到非 core 的路径：

```java
// pzmac41.CoreGl.windowHints()  —— 请求 4.1 core
   7: ldc_w #277 // int 139266  (GLFW_CONTEXT_VERSION_MAJOR)
  10: iconst_4
  14: ldc_w #282 // int 139267  (GLFW_CONTEXT_VERSION_MINOR)
  17: iconst_1
  21: ldc_w #283 // int 139272  (GLFW_OPENGL_PROFILE)
  24: ldc_w #284 // int 204801  (GLFW_OPENGL_CORE_PROFILE)
  30: ldc_w #285 // int 139270  (GLFW_OPENGL_FORWARD_COMPAT)
  33: iconst_1
  37: iconst_1 / 38: putstatic #286 // CoreGl.hinted:Z

// pzmac41.CoreGl.retryWithoutCore()  —— 失败时退到 legacy 2.1 / ANY_PROFILE
public static boolean retryWithoutCore();
   0: getstatic #286 // hinted:Z
   3: ifne 8 / 6: iconst_0 / 7: ireturn
   8: iconst_0 / 9: putstatic #286 // hinted = false
  12: iconst_1 / 13: putstatic #269 // fellBack = true
  16: ldc_w #277 / 19: iconst_2 / 20: GLFW.glfwWindowHint   (major = 2)
  23: ldc_w #282 / 26: iconst_1 / 27: GLFW.glfwWindowHint   (minor = 1)
  30: ldc_w #283 / 33: iconst_0 / 34: GLFW.glfwWindowHint   (PROFILE = ANY)
  37: ldc_w #285 / 40: iconst_0 / 41: GLFW.glfwWindowHint   (FORWARD_COMPAT = 0)
  44: ldc_w #289 // String "macGlCore: no OpenGL 4.1 core window, falling back to the legacy 2.1 context"
  47: invokestatic #291 // pzmac41.Log.warn
  50: iconst_1 / 51: ireturn                                  (返回 true = 已回退)
```

`pzmac41.Bridge.createWindow(...)` 会调用它：

```java
public static long createWindow(int,int,CharSequence,long,long);
   0: invokestatic #56  // CoreGl.windowHints:()V
   9: invokestatic #57  // GLFW.glfwCreateWindow:(IILjava/lang/CharSequence;JJ)J  -> lstore 7
  14: lload 7 / 16: lconst_0 / 18: lcmp / 19: ifne 38
  21: invokestatic #63 // CoreGl.retryWithoutCore:()Z
  24: ifeq 38
  27: ... 33: invokestatic #57 // GLFW.glfwCreateWindow(...)   (第二次，legacy)
```

并且 `CoreGl.capabilities(caps)` 在**非 core 或 <3.2** 时**不安装任何 hook、原样返回原生 caps**：

```java
public static org.lwjgl.opengl.GLCapabilities capabilities(org.lwjgl.opengl.GLCapabilities);
   0: getstatic #286 // hinted:Z
   3: ifne 8
   6: aload_0 / 7: areturn                       // 未 hint -> 恒等
   8: ldc_w #299 // int 37158  (GL_CONTEXT_PROFILE_MASK)
  11: invokestatic #300 // GL11C.glGetInteger:(I)I -> istore_1
  15: iload_1 / 16: iconst_1 / 17: iand / 18: ifeq 28        // 非 core -> 走 28
  21: aload_0 / 22: getfield #306 // GLCapabilities.OpenGL32:Z
  25: ifne 48                                                 // 有 3.2 才 install
  28: sipush 7938 / 31: GL11C.glGetString(GL_VERSION)
  34: invokedynamic #315 // 拼警告串
  39: invokestatic #291 // Log.warn
  42: iconst_1 / 43: putstatic #269 // fellBack = true
  46: aload_0 / 47: areturn                      // <== 不安装 hook，返回原生 caps
  48: aload_0 / 49: invokestatic #319 // install:(...)Lorg/lwjgl/opengl/GLCapabilities;
```

而 `Mac41` **完全没有**参考这个 `fellBack` / `legacyMac()` 信号：

```bash
$ javap -p -c -constants -cp . viewpoint.mac41.Mac41 | grep -oE 'Method pzmac41[^ ]*|Method [a-zA-Z/]*legacy[A-Za-z]*'
（无输出）
# bridge 侧确实暴露了它，但只有 bridge 自己用：
$ javap -p -c -constants -cp . pzmac41.Bridge | grep legacyMac
  public static boolean isLegacyMac();
     0: invokestatic #13 // Method pzmac41/CoreGl.legacyMac:()Z
```

⇒ **执行链（完整因果）：**
`GLFW 无法给出 4.1 core`（或 bridge 未挂上 / `-Dpzmac41.enabled=false`）→ `retryWithoutCore()` 退到 legacy 2.1 或上下文保持非 core → `CoreGl.capabilities()` 因 `profile & 1 == 0` 返回原生 caps 且**不装 hook** → `Mac41.active()` 因 `native.OpenGL41 == false` 或 profile 非 core 而为 **false** → `Mac41.nativeVertexPath()` 走 `!active()` 短路返回 **true** → `Draws41.glVertexAttribFormat` 直呼 `GL43.glVertexAttribFormat` → `GL43C.glVertexAttribFormat` 指针为 **0**（§5 探针）→ **崩溃于题设栈帧**。

### 5.2 相关配置开关（bridge）

```
$ javap -p -c -constants -cp . pzmac41.Config | grep -E 'String |putstatic'
   0: ldc #7  // String "os.name"        -> Config.MAC
  15: ldc #31 // String "pzmac41.enabled" -> Config.MAC_GL_CORE  (default "true")
  28: ldc #43 // String "pzmac41.trace"   -> Config.DEV_CORE_GL_TRACE (default "false")
  41: ldc #50 // String "pzmac41.timerQueries" -> Config.MAC_GL_TIMER_QUERIES (default "false")
```

⇒ **`-Dpzmac41.enabled=false` 会关掉 bridge**，从而加重（而不是缓解）上述门控反相 —— 关掉 bridge 只会让 `active()` 更容易为 false。

---

## 6. Q4 — 模拟的语义结论（已验证 + 推理）

### 6.1 题设策略在 MeshArena 的实际用法下是否可行

题设策略：
> 记录 `attrib → (size,type,normalized,relativeOffset,binding,divisor)`；
> 记录 `binding → (buffer,offset,stride)`；
> 在 `glBindVertexBuffer` 时把该 binding 下所有 attrib 翻译成 `glVertexAttribPointer(attrib,size,type,normalized,stride,offset+relativeOffset)` + `glVertexAttribDivisor(attrib,divisor)`。

**方向正确、单位正确，且在 MeshArena 的用法下"在 `glBindVertexBuffer` 时翻译"这个时机也是对的**，因为：

- `MeshArena` 每次都**先** `glBindVertexArray(...)` **再** `glBindVertexBuffer(6, ...)`（`beginDraws` off 32-35 → 38-48；`beginPlants` off 0-3 → 6-16），所以翻译发生时**正确的 VAO 已绑定**，`glVertexAttribPointer` 的 VAO 作用域正确。
- `recordAttributes()` 的三个 attrib（6/7/8）**共享同一个 binding 6**，所以一次 `glBindVertexBuffer(6, …)` 就能一次性更新全部三个。
- stride / offset 都**以字节为单位**（`glBindVertexBuffer` 的 `stride`、`glVertexAttribFormat` 的 `relativeOffset`、`glVertexAttribPointer` 的 `pointer` 偏移，三者单位一致），MeshArena 用的是 `stride=48`、`relativeOffset=0/16/32`，**不需要任何 字节↔元素 换算**。
- attrib 6/7/8 的 `normalized = false`，`type = GL_FLOAT`，因此 `glVertexAttribPointer(..., GL_FLOAT, false, 48, off)` 与 4.3 语义等价。
- attrib 0..5 的经典指针在 `pointAttributes()` 里已经写好，`apply()` 只改 6/7/8，两者**不冲突**。

### 6.2 但**仅照题设做会出错** —— 缺失项清单

题设策略少了以下记账（括号内是 jar 内参考实现 `Draws41.apply`/`rebase` 的做法）：

| # | 缺失的记账 | 为什么在 MeshArena 下必须 | 参考实现 |
|---|-----------|--------------------------|---------|
| **1** | **保存/恢复 `GL_ARRAY_BUFFER` 绑定** | 翻译要用 `glBindBuffer(GL_ARRAY_BUFFER, recordBuffer)` 才能让 `glVertexAttribPointer` 捕获正确 buffer。`beginDraws()` **不**保存原绑定；`apply()` 必须自己保存并**异常安全地**恢复 | `apply` off 4-10 `glGetInteger(34964)` → istore_3；off 186-192 `glBindBuffer(34962, saved)`；`Exception table from 11 to 186 target 196` 再恢复一次 |
| **2** | **baseInstance 折进 pointer offset** | `glMultiDrawArraysIndirect` 的间接命令第 4 个 int 是 `baseInstance`。GL4.1 **没有** baseInstance；divisor≠0 的 attrib 若不把 `baseInstance*stride` 加进 offset，实例化 record 会读到错位的 slice。这是**载荷路径**：MeshArena 的 record 数组按实例索引 | `rebase(long baseInstance)`：offset = `bindings[b].offset + attr.relative + baseInstance * bindings[b].stride`；`glDrawArraysInstancedBaseInstance` 先 `rebase(instance)` 再 `glDrawArraysInstanced` 再 `rebase(0)`（含异常回滚） |
| **3** | **`divisor` 必须对每个已定义 attrib 重设（含归零）** | 4.3 里"同一 binding 的 divisor 是 binding 的属性"；翻译到 4.1 后 divisor 变成 **attrib** 的属性，会跨 binding 泄漏。若 attrib 曾属 divisor=1 的 binding，后来改绑 divisor=0 的 binding，不显式 `glVertexAttribDivisor(attrib,0)` 就会残留在实例化模式 | `apply` off 53-60：对**每个** defined attrib 调 `divisor(i, bindings[attr.binding].divisor)`（divisor 0/1 都写） |
| **4** | **整数属性必须走 `glVertexAttribIPointer`，且不能误改成 `glVertexAttribPointer`** | MeshArena 的 **attrib 5 是 `GL_INT`**（`GL_INT=5124`）。一个"遍历 attrib 0..15 全部重写"的实现会把 attrib 5 从整数改成浮点。参考实现只重写**自己记录过 `defined=true`** 的 attrib（6/7/8），attrib 5 由 `pointAttributes` 直接设，不被触碰 | `Attribute.integer` 标志 + `apply` off 120-150 分支：`integer ? glVertexAttribIPointer(...) : glVertexAttribPointer(...)`；`glVertexAttribIPointer` 是**纯直通**、不设 `defined` |
| **5** | **按 VAO 维护影子状态** | 4.3 的 format/binding/divisor 都是 **VAO 状态**；影子状态也必须按 VAO 分桶，否则 `vao` 与 `plantVao` 互相污染 | `State.vaos: Map<Integer,Vao>`，`vao()` 用 `computeIfAbsent(State.vao)`；`boundVao(int)` 在 `glBindVertexArray` 时更新 `State.vao` |
| **6** | **VAO 切换后需要"重放"** | 影子状态与驱动里的经典指针状态**都**是 VAO 作用域，所以只要**每次改动都在正确 VAO 绑定下发生**就一致。但若在 VAO A 下 `glBindVertexBuffer` 之后切到 VAO B 再切回 A，A 的驱动态仍在（VAO 保存），**不需要重放**；反过来若在 A 下改了影子态但 `apply()` 时 B 已绑定，就会写错对象 —— 所以必须在 `glVertexAttribFormat`/`glVertexAttribBinding`/`glVertexBindingDivisor` **当场**就 `apply()` | `glVertexAttribFormat`/`glVertexAttribBinding`/`glVertexBindingDivisor`/`glBindVertexBuffer` 四条路径末尾都调 `apply(0)` |
| **7** | **stride==0 ≠ 常量取数** | `glBindVertexBuffer(binding, buf≠0, off, stride=0)` 在 4.3 里表示"常量取数"。翻译成 `glVertexAttribPointer(..., stride=0, ...)` 变成"每顶点同一地址"，**语义不同**。必须显式拒绝 | `glBindVertexBuffer` off 37-56：`buffer!=0 && stride==0` → `throw new UnsupportedOperationException("Zero-stride vertex-binding constant fetch is outside the pinned built-in contract (strides4/32/48); pointer stride0 would change semantics")` |
| **8** | **`glMultiDraw*Indirect` 需要 CPU 侧读取间接缓冲** | `glMultiDrawArraysIndirect` 在 GL4.1 完全没有对应物。参考实现把间接命令**回读**并逐条重放为 `glDrawArraysInstancedBaseInstance`（后者再退化成 `rebase`+`glDrawArraysInstanced`）。回读来源优先用 CPU 影子 span（`captureCpuSpan`），否则 `glGetBufferSubData`（受 `-Dviewpoint.mac41.debugIndirectReadback` 控制，默认关闭时**抛异常**） | `submit`+`command`：`Buffers41.bound(GL_DRAW_INDIRECT_BUFFER)` 必须非 0，否则 `IllegalStateException("No indirect buffer bound")`；从 `State.cpu` 的 `Span` 找覆盖区间，否则若 `!Boolean.getBoolean("viewpoint.mac41.debugIndirectReadback")` 抛异常 |
| **9** | **stride 也要在 offset 校验里（alignment）** | `glTexBufferRange` 路径要求 offset/size 都是 16 字节对齐 —— 4.3 允许任意对齐，4.1 的 `glTexBuffer` 只能整块；参考实现显式检查 | `Ranges41.glTexBufferRange` off 25-43：`offset % 16 != 0 \|\| size % 16 != 0` → `IllegalArgumentException("Unmapped TBO range/format")` |
| **10** | **attrib 索引上限校验** | 影子数组是定长 16 | `validIndex(int)`：`0 <= i < 16` 否则 `IllegalArgumentException` |

### 6.3 结论

- **题设的模拟策略在 MeshArena 的实际用法下"够用"的前提是补齐 #1（保存/恢复 `GL_ARRAY_BUFFER`）、#3（divisor 归零）、#4（整数属性）、#5/#6（按 VAO 的记账与当场重放）。** 只做"记录 + 在 `glBindVertexBuffer` 时翻译"会**在 MeshArena 的调用序列下直接出错**：`beginDraws()` 在 `glBindVertexBuffer` 之前已经绑了 `GL_DRAW_INDIRECT_BUFFER` 和 VAO，翻译时若不保存/恢复 `GL_ARRAY_BUFFER` 就会把 MeshArena 期许的 `GL_ARRAY_BUFFER` 绑定偷换掉；而 divisor 若只在新 binding 上写、不归零，`plantVao`（只经 `recordAttributes` 配置）与 `vao` 之间会串味。
- **#2（baseInstance）不是可选项**：`multiDraw` 走的是间接命令，indirect 结构里带 `baseInstance`；不折进 offset 就会渲染错实例。这是 MeshArena 的**主**绘制路径。
- **#8 是最大的"额外工程量"**：`glMultiDrawArraysIndirect` 在 GL4.1 无对应，必须回读间接缓冲（或依赖 `FrameStream` 的 CPU 影子）并逐条重放。参考实现要求"当前 `GL_DRAW_INDIRECT_BUFFER` 已绑定且能定位到 CPU span"，否则抛错 —— 这也是为什么 `MeshArena.beginDraws()` 会显式 `glBindBuffer(GL_DRAW_INDIRECT_BUFFER, commandBuffer)`。

**因此：题设策略"语义上可行"，但不足以让 `MeshArena` 正确工作；jar 内已经存在一个补全版（`Draws41.apply/rebase/submit`），它才是"足够"的规格。** 需要额外做的状态记账清单 = 上表 10 项。

---

## 7. Q5 — 版本 / 替代 / 开关字符串（已验证）

### 7.1 版本号

| 来源 | 内容 |
|------|------|
| `…/mods/Viewpoint/common/mod.info` | `name=Viewpoint` `id=Viewpoint` **`modversion=0.1.5a-hotfix`** `versionMin=42.21` `versionMax=42.21` `javaJarFile=media/java/client/Viewpoint.jar` `require=\ZombieBuddy` `ZBVersionMin=2.3.0` `url=…?id=3809306528` |
| `ViewpointMac41Patch/42/mod.info` | `name=Project Viewpoint - Patch for Mac [Apple Silicon \| B42.21 \| Unofficial Alpha]` `id=ViewpointMac41Patch` **`modversion=0.1.0-alpha1-currentpack-private1`** `versionMin/Max=42.21.0` `require=\ZombieBuddy,\Viewpoint` |
| `installer/pins.properties` | `version=0.1.0-alpha1-currentpack-private1` `source.revision=dbaf278793ea68ee0ad0049fbad4d44c6832fc0e` `game.version=42.21.0` `game.revision=4a0e9546ec` `runtime.version=25.0.1` `candidate=Q00_F01_F02` |
| `userdata/Zomboid/viewpoint-mac41-installed.txt` | `schema=1` `version=0.1.0-alpha1-currentpack-private1` `status=private-alpha` |
| jar 内 `viewpoint/build.properties` | `release=true` |
| jar 内类常量 | `viewpoint/iris/ShadersProperties` 里含 `1.12.2`（Iris 上游版本）；`42.21.0`（游戏版本） |

### 7.2 `installer/Viewpoint.tsv` —— **上游** Viewpoint 内容的哈希（关键）

```
# SHA256	bytes	relative-path; locally installed upstream content, no assets embedded
94fedda302ab6c17ba1b38495789e4c9781d52823fb8204214c85402e3cab41f	2068978	42/media/java/client/Viewpoint.jar
```

⇒ **存在两个不同的 Viewpoint.jar：**
- **上游/未打垫片**：`94fedda3…`，**2068978** 字节
- **本 payload（已注入 `viewpoint/mac41/*`）**：`9d8d4890…`，**2149583** 字节
- 差 80605 字节 ≈ `viewpoint/mac41` 包（30 个 class，磁盘 328 KB 但压缩后 ~80 KB）的体量

**这解释了题设栈的另一种可能来源**：上游 jar 的 `MeshArena.recordAttributes` 直接调用 `org.lwjgl.opengl.GL43.glVertexAttribFormat`（没有任何垫片），在 macOS 上必然崩在 `GL43C.glVertexAttribFormat`。本 payload 就是为修掉这一点而注入的垫片。但**上游 jar 不在本机**（`Viewpoint.tsv` 只有哈希与大小，无内容），因此"上游 vs payload 的 MeshArena 字节码差异"**未验证**。

### 7.3 有没有"disable arena" / "compat mode" 之类开关

**jar 里所有用到的 System property（穷举，`javap -c` 抽 `ldc` 紧邻 `System.getProperty`/`Boolean.getBoolean`）：**

```
viewpoint.iris.IrisMacros   : os.name
viewpoint.mac41.Mac41       : os.name
viewpoint.mac41.Draws41     : viewpoint.mac41.debugIndirectReadback
viewpoint.platform.GpuBusy  : os.name
viewpoint.platform.HotReload: viewpoint.hotReloadDir
viewpoint.platform.Settings : shaderDir, false
（bridge 侧）pzmac41.Config  : os.name, pzmac41.enabled, pzmac41.trace, pzmac41.timerQueries
```

⇒ **没有 `viewpoint.mac41.disable*`、没有 `-Dviewpoint.compat*`、没有 `-Dviewpoint.arena*`、没有"disable arena" / "compat mode" 开关。**
唯一的间接开关是 `-Dpzmac41.enabled=false`，而它**只会让情况更糟**（见 §5.2）。

**`MeshArena` 相关字符串（全 jar dump）：**

```
$ grep -rhoa '[A-Za-z0-9 ._/-]*[Aa]rena[A-Za-z0-9 ._/-]*' --include='*.class' x/ | sort -u
 arena 
 mesh arena
 mesh arena grown to 
 MiB of arena
 shell arena
 the mesh arena
 viewpoint/render/ShellArena
 arenaFirst
 arenaUsage
Lviewpoint/render/PackArena
Lviewpoint/render/ShellArena
MeshArena.java
PackArena.java
ShellArena.java
viewpoint/render/MeshArena
viewpoint/render/PackArena
viewpoint/render/ShellArena
```

**`compat` 字符串（全 jar）：**

```
 compat
2Draw compatibility context changed without release
330 compatibility
version 330 compatibility
java/lang/IncompatibleClassChangeError
```

`"330 compatibility"` / `"version 330 compatibility"` 是 GLSL 版本串（PZ 本体的 compat shader），不是 Viewpoint 的兼容开关。

**`disable` / `fallback` 字符串：**

```
 disabled after error while building the scene
 disabled after error while drawing
 native readback is disabled
beginDisabled / endDisabled / glDisablei / textDisabled
fallback / fallbackBindings / fallbackText
```

`" disabled after error while building the scene"` / `" disabled after error while drawing"` 值得注意 —— 它们是**运行时错误后的自我禁用**（某子系统），不是预先的降级出口；且从常量池看不到它们与 `MeshArena` 关联。

**debug 键位（存在但被 release 关掉）：**

```
$ viewpoint-live.properties
keys.meshRecord=
keys.meshVerify=
keys.debugView=
keys.isolate=
keys.lodView=
keys.overlay=
keys.rooms=
```

`keys.meshRecord`/`keys.meshVerify` 属于 `viewpoint/platform/Keys`，且由 `Keys.debug(...)` / `Keys.dev(...)` 注册：

```
  private static viewpoint.platform.KeyBind debug(java.lang.String, java.lang.String, java.lang.String, java.lang.String);
   105: ldc #25 // String "Keys/Debug"
   110: invokestatic #33 // Keys.unlessRelease:(Ljava/lang/String;Z)Ljava/lang/String;
   112: invokestatic #7  // Keys.declare:(...)
  private static viewpoint.platform.KeyBind dev(...);
   119: ldc #25 // String "Keys/Debug"
   124: invokestatic #33 // Keys.unlessRelease:(...)
   126: invokedynamic #37 // makeConcatWithConstants
```

```java
// viewpoint.platform.Build
  10: ldc #9  // String "/viewpoint/build.properties"
  12: Class.getResourceAsStream
  24: ldc #19 // "no /viewpoint/build.properties in the mod's JAR"
  80: ldc #46 // "release"  -> Properties.getProperty("release")  -> Build.RELEASE
```

jar 内 `viewpoint/build.properties` 内容为 `release=true` ⇒ `unlessRelease` 把这些 debug 键位置空 ⇒ 本机 `keys.meshRecord=` / `keys.meshVerify=` 为空。**这些是"验证 arena"的开发工具，不是"关闭 arena"的开关。**

---

## 8. 本机安装实例的实跑证据（已验证）：**这套模拟在 4.1 core 下是跑通的**

`<instance>/userdata/Zomboid/console.txt`（35621 行，3.1 MB）：

```
line 85: LOG  : General      f:0> [PZMac41Bridge] Patched zombie/core/fonts/AngelCodeFont, sites=1, source=f8fc7fd3…
line 86: LOG  : General      f:0> [PZMac41Bridge] macGlCore: OpenGL 4.1 Metal - 91.7, GLSL 4.10; core bridge on
                                    (63 implemented callbacks, forwardCompatible=true, native extension flags,
                                     OpenGL33 true, alpha test in shaders on)
line 91: LOG  : General      f:0> OpenGL version: 4.1 Metal - 91.7
line 94: LOG  : General      f:0> OpenGL 1.5 buffer objects supported
line 363:LOG  : General      f:0> [PZMac41Bridge] Patched zombie/core/opengl/VBORenderer, sites=1, source=58671e57…
```

末尾（进入世界/第一人称的过程）：

```
LOG  : General      f:285  st:162,179,452>  [Viewpoint] setup's hardware check: Apple M4 (Apple), video memory ?,
                                            memory 32768 MiB (109 free), heap 8192 MiB, 10 threads, 1920 x 1080;
                                            advised Potato, far world workers 2
LOG  : General      f:2469 st:162,231,764>  [Viewpoint] setup finished: first person turns on
LOG  : General      f:2470 st:162,231,791>  [Viewpoint] compat: all 61 patch targets and 61 private members found
LOG  : General      f:2470 st:162,231,793>  [Viewpoint] action state idle moving=false turning=false strafing=false aiming=false blocked=false
LOG  : General      f:2471 st:162,231,883>  [Viewpoint] mesh arena: buffer textures reach 268435456 texels, 2047 MiB of arena
```

分析：
- `OpenGL 4.1 Metal` + **core bridge on** ⇒ `GL_CONTEXT_PROFILE_MASK & CORE_BIT == 1` ⇒ `Mac41.active() == true`。
- `[Viewpoint] mesh arena: …` 这行来自 `MeshArena.grow()` / `limitToSlots()`（`" MiB of arena"` / `"buffer textures reach … texels"` 拼接串），**证明 `MeshArena.init()` 完整跑完、`pointAttributes()`+`recordAttributes()` 都没崩**。
- `[Viewport] setup finished: first person turns on` ⇒ 第一人称世界渲染真的起来了。

⇒ **本机没有重现题设崩溃**；崩溃只会在 §5.1 的非 core / bridge 未挂载路径上出现。**这一点必须在结论里区分"已验证"与"未验证"。**

### 8.1 另外一条值得注意的日志（工坊 mod 自检）

```
line 450: LOG  : Lua  f:0> [ViewpointMac41Patch] Setup required: run Instalar.command with the game closed.
                           Mod order alone cannot install the pre-start bridge.
```

⇒ 工坊 mod 只有在 `Instalar.command` 装好 bridge 之后才有效；**若用户只订阅了工坊包、没跑安装器，`Mac41.active()` 仍可能为 true（因为游戏自身请求 4.1 core）**，但 bridge 的 63 个 hook 不存在 —— 这会让 PZ 本体的固定管线路径失败，而 `MeshArena` 的 4.3 路径因 `active()==true` 仍走垫片。**这是一种"部分可用"的中间态。**

---

## 9. 已验证 vs 未验证

### 已验证（有可复现命令 + 原始输出）

| 项 | 证据 |
|----|------|
| 两个 jar 同哈希 | §1 `shasum -a 256` |
| MeshArena 的全部 GL 调用点与顺序、attrib 6/7/8 的 (size,type,norm,relOffset,binding,divisor)、binding≠attrib、divisor=1、attrib 5 为整数、VAO/绑定保存恢复 | §2 `javap -p -c -constants` + `-l` 的原始字节码 |
| `ATTRIBUTE_SIZES={3,2,4,3,1,1}`、`STRIDE=14`、`VERTEX_BYTES=56` | §2.1 |
| MeshArena / Meshes / WorldRenderer 零门控 | §3.1–3.2 `grep` |
| MeshArena 是唯一网格路径（8 个引用类 + Meshes/PackDraws 的方法清单） | §3.4 |
| 33 个 GL4.2+ 函数、12 个引用类、逐函数所在类 | §4.1–4.2 |
| bridge 只覆盖 1 个 4.2+ 函数（→ 32 个落在垫片） | §4.3 `comm -12` |
| Apple 驱动对 9 件套 + DSA/multidraw 全部 `dlsym == NULL` | §5 两个 C 探针原始输出 |
| `Mac41.active()` 的 core-profile 条件；`nativeVertexPath()` 的 `!active() → true` 短路 | §0 / §5.1 字节码 |
| `CoreGl.windowHints()` / `retryWithoutCore()` / `CoreGl.capabilities()` 的非 core 不装 hook 分支 | §5.1 字节码 |
| 本机实跑成功（4.1 core + 63 callbacks + mesh arena 完成 + first person on） | §8 console.txt |
| 版本号、hash、`release=true`、无 disable/compat 开关、debug 键位 | §7 |

### 未验证（明确说明）

1. **没有启动游戏**，因此"§5.1 因果链在真实崩溃里被触发"是**字节码推理**，不是现场观测。现场只有 `console.txt` 的成功记录，没有失败记录（`Logs/` 未逐文件检查崩溃栈）。
2. **上游 jar（`94fedda3…`, 2068978 B）不在本机**，因此"上游 `MeshArena` 直呼 `GL43C`"只是由题设栈 + 缺少垫片推断，**未做字节码对照**。
3. **`CoreGl.install()` 的 libffi trampoline 细节**（如何在 `GLCapabilities` 的 `long` 槽里塞入可调用闭包、`registerHooks` 的 63 个回调精确名单）未逐条展开；只验证了 hook 名集合（89 个字符串）与它只覆盖 1 个 GL4.2+。
4. **IrisFrame/IrisImages 是否在默认 `graphics.pack=vivid` / `graphics.mode=Vanilla` 下真的被调用**未验证（只验证了其 4.2+ 调用**无门控**）。`Mac41.rejectExternalIris()` 只挡外部包。
5. **`glMultiDrawElementsIndirect`（索引路径）在 MeshArena 中未被使用**（MeshArena 只调 `glMultiDrawArraysIndirect`），只验证了它的存在与门控，未做行为分析。
6. **未做任何修改**（按题目要求只读）；`/tmp/mac41/b/` 之外未写入任何文件。

---

## 10. 最终回复要点（供上游使用）

1. **MeshArena 的精确用法**：attrib 0..5 经典指针（`{3,2,4,3,1,1}`，stride 56B，attrib 5 是 `GL_INT` 走 `glVertexAttribIPointer`），attrib 6/7/8 是 3×`vec4 float`、`normalized=false`、`relativeOffset=0/16/32`、**全部 binding=6**、**divisor=1（实例化）**。**binding ≠ attrib 索引**。两块数据源：attrib 0..5 来自单一共享 VBO `vertexBuffer`（每 mesh 按 `vertexIndex*56` 偏移），attrib 6..8 来自每帧环形 `recordBuffer`（`glBindVertexBuffer(6, recordBuffer, recordsAt, 48)`）。`MeshArena` 自己 bind VAO、自己保存/恢复 `GL_ARRAY_BUFFER_BINDING`(34964) 与 `GL_TEXTURE_BINDING_2D`(32873)，但**依赖垫片在 `glBindVertexBuffer` 时把 binding 6 装进指针**。
2. **模拟策略够不够**：方向对、单位对、时机对，但**只照题设做会错**。必须补：`GL_ARRAY_BUFFER` 保存/恢复（`beginDraws` 不保存）、divisor 归零、整数属性分支、按 VAO 的影子状态与当场重放、以及 **baseInstance 折进 offset**（indirect 命令带 baseInstance，GL4.1 没有）。最大工程量是 `glMultiDrawArraysIndirect` 必须在 CPU 侧回读间接缓冲并逐条重放（`Draws41.submit/command` 有完整实现，且要求 `GL_DRAW_INDIRECT_BUFFER` 已绑定 + 能定位 CPU span，否则抛异常）。**jar 内已有"足够"的参考实现 `Draws41.apply/rebase/submit`，共 10 项记账（§6.2）。**
3. **下一个无门控 4.3 撞点**：**`IrisFrame.computes(...)` → `GL43.glDispatchCompute` + `GL42.glMemoryBarrier`（无任何能力检查）**；次之 `IrisImages.bind → GL42.glBindImageTexture`（无门控）与 `IrisImages.image → GL44.glClearTexImage`。这些属 Iris 着色器包子系统（`graphics.mode=Vanilla` 时不进入）。**在 MeshArena 的世界渲染主路径上，除 MeshArena 外没有无门控 4.2+ 撞点**（`GlDebug` 有 `OpenGL43 || GL_KHR_debug` 门控，其余全在 `viewpoint.mac41.*` 垫片内）。若垫片失效，紧随 `recordAttributes` 之后的下一个撞点是 `MeshArena.init` 偏移 146-152 的 `lightTexture()` → `Textures41.glCreateTextures`（GL4.5，macOS NULL）。
4. **"跳过/禁用 arena" 不是可用出口**：`MeshArena` 是唯一网格机制（`Meshes` + `PackDraws` 共 13 个方法依赖），跳过它 ⇒ 世界几何全没了；且 jar 内**不存在** disable/compat 开关（穷举了全部 `System.getProperty`）。
5. **真正的出口是把门控修对**：`Mac41.active()` 不该要求 core profile（或 `nativeVertexPath()` 在 macOS 上不该因 `!active()` 就返回 true），因为 Apple 驱动**从不**导出这 9 个函数（§5 探针），所以"回落到原生 GL4.3"在 macOS 上 **100% 是崩溃**。bridge 已经暴露了 `legacyMac()`/`fellBack` 信号，但 `Mac41` 没有消费它。

