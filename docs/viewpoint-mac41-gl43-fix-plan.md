# ViewpointMac41Patch（工坊 3812168749）修复思路方案

> 状态：**方案 + 可运行原型已完成离线自证；待一次游戏内确认**
> 结论对早先的 [`viewpoint-mac41-bridge-gap-report.md`](viewpoint-mac41-bridge-gap-report.md) 做了**重要更正**（见第二节）。
> 证据附录（本会话产出，含命令与原始字节码）：[`research/viewpoint-mac41-pad-layer-usage.md`](research/viewpoint-mac41-pad-layer-usage.md)、
> [`research/lwjgl-gl43-address-table-and-zombiebuddy.md`](research/lwjgl-gl43-address-table-and-zombiebuddy.md)、
> [`research/pz-mac41-bridge-hook-seam.md`](research/pz-mac41-bridge-hook-seam.md)、
> [`research/viewpoint-mac41-author-status.md`](research/viewpoint-mac41-author-status.md)

---

## 一、一句话结论

崩溃的**直接原因不是"桥没有实现 GL 4.3"**，而是 **Viewpoint 自带的 macOS 兼容层被它自己的门控关掉了**：

* 补丁包实际安装的 `Viewpoint.jar`（payload，`9d8d4890…`）里有一个 `viewpoint.mac41.*` 垫片层（30 个类），
  **已经完整覆盖 32 个 GL 4.2+ 函数**（把 4.2/4.3/4.4/4.5 入口降级到 4.1 core）。
* 但它的总开关 `Mac41.active()` 要求 `nativeCapabilities().OpenGL41`（"自述 4.1"），而 pz-mac41-bridge
  合成出来的 caps 只标到 **3.3**（日志原文 `... OpenGL33 true ...`）⇒ `active() == false`。
* 于是 `Mac41.nativeVertexPath()` 走它的短路分支：**`if (!active()) return true;`**
  —— "没有 macOS 兼容层 ⇒ 假定原生 GL 4.3 可用"。macOS 的驱动从不导出这些符号（实测 `dlsym` 全 NULL），
  调用落到 LWJGL 的空地址桩 ⇒ `FATAL ERROR in native method ... The JVM will abort execution.`

**修法**：把门控"扶正"——让垫片层在"桥已提供 core ≥3.2"时生效（`active() → true`），
并让顶点路径永不假定原生 4.3（`nativeVertexPath() → false`）；再叠一层 GL 4.3 顶点格式族的降级实现做安全网。
两者都已做原型并离线自证（见第六节）。

---

## 二、对早先结论的更正（重要）

早先的 gap report 写的是"`MeshArena` 无门控直呼 `GL43`"。**那是对着另一份 jar 得出的结论**：

| jar | sha256 前 16 位 | 大小 | 位置 | `MeshArena.recordAttributes` 里是什么 |
|---|---|---|---|---|
| **上游 Viewpoint（工坊 3809306528）** | `94fedda302ab6c17` | 2 068 978 B | `.../workshop/content/108600/3809306528/mods/Viewpoint/42/media/java/client/` | 直接 `GL43.glVertexAttribFormat`（无垫片） |
| **补丁 payload（游戏实际加载）** | `9d8d4890a2657cc1` | 2 149 583 B | 工坊 3812168749 `tools/payload/`；安装实例 `userdata/Zomboid/mods/Viewpoint/…` | `viewpoint/mac41/Draws41.glVertexAttribFormat`（有门控） |

```
# 实测（本机）
$ javap -p -c <安装实例>/…/Viewpoint.jar 的 viewpoint/render/MeshArena
  13: invokestatic  viewpoint/mac41/Draws41.glVertexAttribFormat:(IIIZI)V
  20: invokestatic  viewpoint/mac41/Draws41.glVertexAttribBinding:(II)V
  74: invokestatic  viewpoint/mac41/Draws41.glVertexBindingDivisor:(II)V
```

所以：**"桥缺 GL 4.3 实现"是事实，但它不是本次崩溃的必要条件**——补丁包作者其实自己写了那一层，
只是被自己的门控短路绕过了。这也解释了作者 README 里"M1 上跑通过世界渲染"的说法：那份测试里门控是通的。

---

## 三、证据链（每条都可用本机命令复现）

1. **门控链**（安装实例 jar，`javap -p -c -classpath . viewpoint.mac41.Mac41`）：
   * `active()` = `MAC && nativeCapabilities().OpenGL41 && (GL11.glGetInteger(37158 /*PROFILE_MASK*/) & 1) != 0`
   * `nativeVertexPath()` = `if (!active()) return true;` …否则检查 8 个 `GLCapabilities.glXxx:J` 快照字段是否全非 0
   * `nativeCapabilities()` = `pzmac41.Bridge.nativeCapabilities()`（反射，见下），否则回落 `GL.getCapabilities()`
2. **垫片与桥的关系**（`Mac41$BridgeAccess` 静态初始化）：
   `Class.forName("pzmac41.Bridge")` + `getMethod("nativeCapabilities"/"active"/"onDestroy")`
   ⇒ 这个垫片层**就是为这个桥写的**；桥里 `pzmac41.Bridge` 确实有这三个方法。
3. **垫片覆盖面**（附录报告）：33 个 GL 4.2+ 函数分布在 12 个类，其中 32 个落在 `viewpoint/mac41/*`
   （`Draws41` 9 个、`Textures41` 10 个、`Ranges41` 1 个、`Buffers41` 1 个、`Iris*` 4 个…）；
   桥自己的 172 个 hook 名里 **一个都没有这 5 个顶点格式函数**（实测：`glVertexAttribPointer/Divisor/
   IPointer/BindBuffer/GetInteger` 全在名单里，GL 4.3 族 0/5）。
4. **macOS 驱动侧**（附录报告的 `dlopen`+`dlsym` 探针）：`glVertexAttribFormat/IFormat/Binding/
   VertexBindingDivisor/BindVertexBuffer` 在 `OpenGL.framework` 里**全部 NULL**；
   `glVertexAttribPointer/Divisor/IPointer` 为 NON-NULL ⇒ "回落原生 4.3" 在 macOS 上必定崩。
5. **崩溃落点与地址表**：本机运行的地址表里 `glVertexAttribFormat` 槽位是 **0**
   （LWJGL 的空地址桩文案就是那句 `No context is current or a function that is not available…`）。
   LWJGL 3.4.1 这个快照把地址放在 `GLCapabilities.addresses`（2236 槽 `PointerBuffer`），
   native stub **每次调用按下标读表**，且 `Checks.checkFunctions` 对非 0 槽位**不覆盖**
   ⇒ 运行期还能改表（备用修法，见第五节 B）。
6. **日志侧**：安装实例 `userdata/Zomboid/console.txt` 最后一行是
   `[Viewpoint] mesh arena: buffer textures reach 268435456 texels, 2047 MiB of arena`，
   紧接着就是 `MeshArena.init` → `recordAttributes()` 的第一次 4.3 调用 ⇒ 与崩溃栈一致（abort 文案走 stderr，不落 console.txt）。

---

## 四、修复方案（推荐路线，三层）

### 第 1 层（主修）：把垫片层的门控扶正

自己的 javaagent，在类加载期做**常量池重定向**（只改 Methodref 的 `class_index`，方法体一个字节不动）：

| 被替换的方法 | 替换为 | 语义 |
|---|---|---|
| `viewpoint/mac41/Mac41.active()Z` | `pzglshim.Emul.active()Z` | `MAC && (caps.OpenGL32 \|\| OpenGL33 \|\| OpenGL40..45)` —— 桥已把上下文抬到 core ≥3.2 就算"兼容层接管" |
| `viewpoint/mac41/Mac41.nativeVertexPath()Z` | `pzglshim.Emul.nativeVertexPath()Z` | 恒 `false`：macOS 上永不假定原生 GL 4.3 |

重定向对**所有类**生效（`Draws41`/`Textures41`/`State41`/`Buffers41`… 都调 `Mac41.active()`），
于是作者自带的 32 函数垫片全部真正生效——**不需要我们重新实现 GL 4.3**。

> 为什么这样就够：`Draws41.glVertexAttribFormat` 的字节码是
> `nativeVertexPath() ? GL43.glVertexAttribFormat : <垫片记录 + apply>`，
> 而 `Textures41` 里 `Mac41.active()` 出现 25 次、`nativeCapabilities()` 15 次（`State41` 3 次、`Buffers41` 4 次），
> 门控一旦为真，它们全部走垫片。注意 `nativeVertexPath()` 的**两个条件都要处理**：
> 只把 `active()` 改真、仍可能因 caps 快照字段非 0 而返回 true（这正是第 2 层存在的理由）。

### 第 2 层（安全网）：GL 4.3 顶点格式族的 GL 4.1 降级实现

同一 agent 把 `org/lwjgl/opengl/GL43` 里指向 `GL43C` 的 5 个入口重定向到 `pzglshim.Emul`：

```
glVertexAttribFormat(a,size,type,norm,relOff)  记录
glVertexAttribIFormat(a,size,type,relOff)      记录（整数属性走 glVertexAttribIPointer）
glVertexAttribBinding(a,b)                     记录（默认 a→a）
glVertexBindingDivisor(b,d)                    对每个 attrib[a].binding==b 调 GL33.glVertexAttribDivisor(a,d)
glBindVertexBuffer(b,buf,off,stride)           对每个 attrib[a].binding==b 重放：
    prev = GL11.glGetInteger(GL_ARRAY_BUFFER_BINDING)
    GL15.glBindBuffer(GL_ARRAY_BUFFER, buf)
    GL20.glVertexAttribPointer(a,size,type,norm,stride, off+relOff)
    GL33.glVertexAttribDivisor(a, divisor[b])
    GL15.glBindBuffer(GL_ARRAY_BUFFER, prev)     # 必须恢复，别让桥的虚拟状态漂移
```

`MeshArena` 的真实用法（附录报告已逐条核对）：attrib 6/7/8 的 binding **全是 6**（≠ attrib 索引）、
`relativeOffset = 0/16/32`、`stride = 48`、`divisor = 1`（实例化渲染）、单位全是字节、`normalized=false`，
且总是**先 bind VAO 再 `glBindVertexBuffer`** ⇒ 上面的翻译语义等价。
（附录报告还列出"照搬会出错"的 10 项记账，例如 baseInstance 折进 offset、divisor 归零、按 VAO 影子状态、
拒绝 `buffer!=0 && stride==0` 等——那些属于**自己重写垫片**时的注意事项；本方案直接复用作者的垫片，不需要重做。）

### 第 3 层（诊断）：把门控真值打出来

`Emul.gateReport()` 在第一次碰到垫片类时输出一行：

```
[PZGlShim] gate: isMac=true effectiveCaps=OpenGL33=<..> OpenGL40=<..> OpenGL41=<..>
           bridgeNativeCaps=OpenGL41=<..> bridgeActive=<..> bridgeLegacyMac=<..> ourActive=true
```

这样"到底为什么 active() 为假"（桥只标 3.3 / 桥的 `nativeCapabilities()` 给的不是原生 caps）
可以一次跑完就确证，而不是继续靠推理。agent 另外写 marker 文件（`/tmp/pzglshim-loaded.txt` +
`~/Zomboid/pzglshim-loaded.txt`）证明 premain 真的被加载。

### 集成方式（不动任何被哈希校验的文件）

作者安装器 `Installer.verifyInstalled()`（源码 `.../common/tools/source/Installer.java`）实测会校验：
`game.sha256` / `plist.sha256` / `installer.sha256` / 三个 payload 哈希，并且

```java
require(agents.size()==2 && agents.get(0).contains("pz-mac41-bridge.jar")
                          && agents.get(1).contains("ZombieBuddy.jar"));   // 第 279 行
```

⇒ **不能在 Info.plist 里加第三个 `-javaagent`**（会被直接拒绝启动）。改用环境变量注入，并包一层启动脚本：

```sh
# Jogar.shim.command（放在安装实例目录；Jogar.command 本身不在校验清单里）
export JAVA_TOOL_OPTIONS="-javaagent:/path/pz-mac41-gl43-shim.jar"
exec "$(dirname "$0")/Jogar.command"
```

* 本机实测：游戏自带 `jre-aarch64` 的 JRE 25 认 `JAVA_TOOL_OPTIONS` 与 `_JAVA_OPTIONS`，
  `[SHIM-PROBE] premain ran` 可见；`JavaAppLauncher` 走 `JNI_CreateJavaVM`，参数解析同一套代码，
  **仍需一次实证**（shim 的 marker 文件就是为此准备的）。
* 纯增量：去掉环境变量即完全还原；不碰 `Info.plist`、不碰两个 jar、不碰 `installation.properties`。

---

## 五、为什么不选别的路线

| 路线 | 结论 | 依据 |
|---|---|---|
| A. 给桥补 hook（libffi 回调） | **备选（已逐条验证可行，但不需要）** | 桥按函数名注册，地址表可运行期改（`GL.getCapabilities().getAddressBuffer().put(908, addr)` 对 native 路径立即生效，但**不更新 `GLCapabilities` 的 Java 快照字段**）；反射调 `CoreGl.hook(String, CallbackI)` 与直接 `hooks.put(...)` 都已实测可行；桥**没有**留配置/附加 jar 扩展点；libffi 往返本机已验证（需 `@FunctionalInterface` + `--enable-native-access`）。细节见 [`research/pz-mac41-bridge-hook-seam.md`](research/pz-mac41-bridge-hook-seam.md) |
| B. 直接改桥 jar / 改 Viewpoint jar | **不推荐** | 两个 jar 都在安装器的哈希校验里；桥是闭源且有 `class-pins.properties` 自检；改完还得同步 `installation.properties` |
| C. ZombieBuddy Java 模组补丁 | **可作为发布形态** | ZB 2.3.2 的补丁筛选=任意类名（唯一黑名单 `me.zed_0xff.`），能补 `viewpoint.*`/`pzmac41.*`；但它没有第三方 ClassFileTransformer 扩展点，只能做方法级 advice，做不了我们这种"全局 Methodref 重定向" |
| D. 等作者更新 | **不可指望** | 工坊页 changelog 只有 2 条（首发后 `No runtime changes.`）；评论区同类崩溃（"按 O 秒崩"、`jni_FatalError`、`OpenGL 2.1`）作者 **0 回复**；唯一联系面是 Viewpoint 的 macOS 讨论帖（@xiveboy，无 GitHub/Discord） |
| E. 跳过/禁用 MeshArena | **不可用** | MeshArena 是唯一网格机制（`Meshes` 11 处、`PackDraws` 2 处…），跳过=世界几何全空；且穷举 `System.getProperty` 后确认没有 disable/compat 开关 |
| F. 在 macOS 拿到真 GL 4.3+ | **不存在** | Apple 只给 2.1 legacy / 3.2–4.1 core；MoltenGL 只有 ES 2.0、ANGLE 只输出 ES、Mesa zink 官方自述"macOS 上实验且能力极有限" |
| G. 自研渲染器（`bin2_viewpoint/`） | **长期兜底** | 仓库已有 P0/P1 工程；与"修好这个模组"是两件事 |

---

## 六、已完成的自证（无游戏）

原型在 `/tmp/mac41/shim/`（`Emul` + `Gl4xTransformer` + `ShimAgent` + 测试；未进仓库）：

| 验证 | 结果 |
|---|---|
| 门控重定向（真实 `Mac41.class`/`Draws41.class`/`Textures41.class` 字节） | ✅ 目标方法全部指向 `pzglshim/Emul.active` / `nativeVertexPath`，常量池只 +2 条目，`javap` 可正常反汇编 |
| 常量池改写正确性 | ✅ 只改 `class_index`，NameAndType/方法体不动；非目标类返回 null |
| 4.3→3.3 状态机（记录型 Sink） | ✅ 11 项断言全绿：formats-first 全序列、换 buffer 重放、先 bind 后 format 补发、整数格式、ARRAY_BUFFER 恢复 |
| 端到端（真实 `org.lwjgl.opengl.GL43` + 替身 `GL43C`） | ✅ `INTEGRATION PASSED (GL43 -> pzglshim.Emul)` —— 真 GL43 的调用被我们的实现接住，替身 `GL43C` 未被调用（未走 native） |
| agent 注入 | ✅ `-javaagent` 与 `JAVA_TOOL_OPTIONS`（游戏自带 JRE）都能让 premain 执行并写 marker |
| 合计 | ✅ **23/23 checks, 0 failure** |

**尚未做**：没在游戏里跑过（需要用户在隔离实例上跑一次）；没验证门控真值现场值（第 3 层就是为此）；
Iris 的 compute 路径（`glDispatchCompute`/`glMemoryBarrier`）在 `graphics.mode=Vanilla` 下是否被调用未验证；
Intel Mac 未验证（作者也只测了 M1）。

---

## 七、下一步（建议顺序）

1. 把原型整理成仓库工程（照 `bin2_viewpoint/` 布局：`Contents/mods/<Id>/<ver>/src`、`tools/`、`build.sh`），
   产出 `pz-mac41-gl43-shim.jar`；补一个 `Jogar.shim.command`；
2. 在隔离实例（`~/Library/Application Support/ViewpointMac41/versions/0.1.0-alpha1-currentpack-private1`）跑一次，
   看三件事：`console.txt` 是否越 `mesh arena …` 那一行、有没有 `[PZGlShim] gate: …` 与 `[PZGlShim] … call site(s)`、
   是否还 abort；
3. 按第 3 层的门控日志确证病因，必要时收紧 `Emul.active()` 的条件（例如要求 `OpenGL33` 且 core bit）；
4. 若稳定，可再包装成 ZombieBuddy Java 模组形态（免环境变量），但**不要**公开发布：
   补丁包本身是 private alpha、上游 Viewpoint 许可禁止再分发/反编译复用，本 shim 只做互操作性修正、不含任何被复制的代码/资源。

---

## 八、参考

* 补丁包（private alpha）：工坊 [3812168749](https://steamcommunity.com/sharedfiles/filedetails/?id=3812168749)，作者 xiveboy
* Project Viewpoint：工坊 [3809306528](https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528)
* ZombieBuddy（MIT，最新 v2.3.3；补丁 pin 的是 2.3.2）：工坊 [3619862853](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853)、[GitHub](https://github.com/zed-0xff/ZombieBuddy)
* 公开同类工作（同一思路：4.1 core 上补缺失入口）：[xD3I/PZ_Optimization](https://github.com/xD3I/PZ_Optimization)（无 LICENSE）
* 上游报错归属更正依据：[`viewpoint-mac41-bridge-gap-report.md`](viewpoint-mac41-bridge-gap-report.md) 顶部"更正"一节
