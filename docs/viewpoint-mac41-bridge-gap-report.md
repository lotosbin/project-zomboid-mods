# Bug report — ViewpointMac41Patch: hard JVM abort at the first world draw (`glVertexAttribFormat` is not bridged)

> Paste-ready report for the package author. Every claim below is reproduced on the reporter's machine with the
> exact command shown; no guessing. Written 2026-10-03.

---

## ⚠️ CORRECTION (same day, before sending) — read this first

The stack trace and the "MeshArena calls GL 4.3 unguarded" analysis below were taken from the **upstream**
`Viewpoint.jar` (`94fedda302ab6c17…`, 2 068 978 B, Workshop 3809306528), **not** from the jar the game actually
loads. The patch payload ships a different build:

| jar | sha256 (first 16) | size | `MeshArena.recordAttributes` |
| --- | --- | --- | --- |
| upstream (3809306528) | `94fedda302ab6c17` | 2 068 978 B | calls `org/lwjgl/opengl/GL43.glVertexAttribFormat` directly |
| payload (3812168749 = installed copy) | `9d8d4890a2657cc1` | 2 149 583 B | calls `viewpoint/mac41/Draws41.glVertexAttribFormat` |

The payload jar contains a 30-class macOS compatibility layer `viewpoint.mac41.*` that **already emulates all 32
GL 4.2+ entry points**, and it is wired to this bridge (`Mac41$BridgeAccess` reflects into
`pzmac41.Bridge.nativeCapabilities()/active()/onDestroy(Runnable)`). It is disabled by its own gate:

* `Mac41.active()` = `MAC && nativeCapabilities().OpenGL41 && (GL_CONTEXT_PROFILE_MASK & 1) != 0`
* `Mac41.nativeVertexPath()` = **`if (!active()) return true;`** — "no macOS layer ⇒ assume native GL 4.3"
* `Draws41.glVertexAttribFormat(...)` = `nativeVertexPath() ? GL43.glVertexAttribFormat(...) : <pad>`

Because the bridge's synthesised capabilities advertise only up to **OpenGL 3.3** (`... OpenGL33 true ...` in the
log), `active()` is false, `nativeVertexPath()` short-circuits to `true`, the pad is bypassed, and the native GL 4.3
entry point — which Apple never exports — aborts the JVM. The missing bridge coverage is real, but the actionable
defect is the **gate inversion in `viewpoint.mac41`** (equivalently: the bridge advertising 3.3 while the context
really is 4.1 core). See [`viewpoint-mac41-gl43-fix-plan.md`](viewpoint-mac41-gl43-fix-plan.md).

**Revised questions for the author**

1. Was the "M1, entering the world, first-person rendering" test run against a bridge whose capabilities advertised
   `OpenGL41`? With the published payload + published bridge, `Mac41.active()` is false on this machine, so the pad
   layer is bypassed and the first world draw aborts.
2. Would you make `nativeVertexPath()` (and the other pad gates) not fall back to native GL 4.2+ entry points on
   macOS — or have the bridge advertise the real core-4.1 context so `active()` becomes true?
3. If the bridge is meant to be extended instead, the `Draws41.apply/rebase` code is already a complete reference
   implementation of the `glVertexAttribFormat/IFormat`, `glVertexAttribBinding`, `glVertexBindingDivisor`,
   `glBindVertexBuffer` family.

---


## Summary

`pz-mac41-bridge.jar` does not provide the **OpenGL 4.3 "separate vertex attribute format" family**
(`glVertexAttribFormat`, `glVertexAttribBinding`, `glVertexBindingDivisor`, `glBindVertexBuffer`).
Viewpoint's `viewpoint.render.MeshArena` calls that family **unconditionally** on the first world draw, so on macOS
(the entry point does not exist above GL 4.1) LWJGL gets a NULL function address and **aborts the whole JVM**:

```
FATAL ERROR in native method: Thread[#3,main,5,main]: No context is current or a function that is not
available in the current context was called. The JVM will abort execution.
	at org.lwjgl.opengl.GL43C.glVertexAttribFormat(Native Method)
	at org.lwjgl.opengl.GL43.glVertexAttribFormat(GL43.java:898)
	at viewpoint.render.MeshArena.recordAttributes(MeshArena.java:252)
	at viewpoint.render.MeshArena.pointAttributes(MeshArena.java:244)
	at viewpoint.render.MeshArena.init(MeshArena.java:96)
	at viewpoint.render.Meshes.init(Meshes.java:38)
	at viewpoint.render.WorldRenderer.init(WorldRenderer.java:526)
	at viewpoint.render.WorldRenderer.begin(WorldRenderer.java:169)
	at viewpoint.SceneDrawer.drawFrame(SceneDrawer.java:121)
	at viewpoint.SceneDrawer.render(SceneDrawer.java:63)
	...
	at zombie.core.opengl.RenderThread.renderLoop(RenderThread.java:137)
	at zombie.gameStates.MainScreenState.main(MainScreenState.java:339)
```

The bridge itself works (GL 4.1 core context, 63 callbacks, all game-side patches applied); the failure is a
**coverage gap in the bridge's GL 4.3 emulation**, not a heap/config/pack problem. See "Why this is not an
out-of-memory or multiplayer issue" below.

## Environment (exact)

| Item | Value |
| --- | --- |
| Package | `ViewpointMac41Patch`, version `0.1.0-alpha1-currentpack-private1`, Workshop `3812168749` |
| Bridge | `pz-mac41-bridge.jar` sha256 `85c45fd301d1aafd81e60d14ab26c25e6eead46352335b974748f1a20f0d850f` (unmodified, installer-verified) |
| ZombieBuddy | 2.3.2 (Workshop `3619862853`), agent mode, `frontend=console` |
| Viewpoint | 0.1.5a-hotfix, `42/media/java/client/Viewpoint.jar` sha256 `94fedda302ab6c17ba1b38495789e4c9781d52823fb8204214c85402e3cab41f` (matches `installer/Viewpoint.tsv`) |
| Game | Build 42.21.0, revision `4a0e9546ec`, `projectzomboid.jar` sha256 `e1a69eb743ede60b213a0fe7f8b83d4fcab773036d256cc4543a336f3b058a33` |
| Runtime | bundled `jre-aarch64` 25.0.1 (Azul), `OS_ARCH=aarch64` |
| Machine | Apple M4, 32 GB, macOS 27.0 (build 26A428), OpenGL `4.1 Metal - 91.7`, GLSL 4.10, LWJGL 3.4.1-snapshot |
| Install path | `~/Library/Application Support/ViewpointMac41/versions/0.1.0-alpha1-currentpack-private1` |
| JVM args | `-Xmx8192m` (raised by the reporter; default 3072m also crashes), both `-javaagent` in bridge→Buddy order |

Note: the optional pack `3810302175` could not be validated (its published content no longer matches
`installer/PZVoxelStudioViewpoint.tsv`: 10 missing / 9 size-mismatched / 38 extra files), so the installation was
made with the installer's own `--without-pack`. This does not affect the crash below — it happens before any
pack model is drawn, and `MeshArena.init` is reached regardless of the pack.

## Reproduction

1. Install per `README_EN.txt` (`Instalar.command`, game closed, dependencies downloaded).
2. Open `Jogar.command` (must be a Terminal, ZombieBuddy uses `frontend=console`).
3. Load any world (single-player or multiplayer — both abort).
4. The game reaches Viewpoint's own "setup finished: first person turns on", prints the mesh-arena sizing line,
   then aborts the JVM on the first `glVertexAttribFormat` call.

Relevant good lines before the abort (bridge is healthy):

```
[PZMac41Bridge] macGlCore: OpenGL 4.1 Metal - 91.7, GLSL 4.10; core bridge on (63 implemented callbacks,
                forwardCompatible=true, native extension flags, OpenGL33 true, alpha test in shaders on)
[PZMac41Bridge] Patched zombie/core/opengl/VBORenderer, sites=1, source=58671e57...c03e
[Viewpoint] loaded
[Viewpoint] game build: Build 42.21.0, as pinned
[Viewpoint] compat: all 61 patch targets and 61 private members found
[Viewpoint] setup finished: first person turns on
[Viewpoint] mesh arena: buffer textures reach 268435456 texels, 2047 MiB of arena
<abort>
```

## Evidence

### 1. LWJGL's message is the "function address is 0" abort

```
$ unzip -p projectzomboid.jar macos/arm64/org/lwjgl/liblwjgl.dylib | grep -ao "No context is current[^\"]*"
No context is current or a function that is not available in the current context was called
```

macOS OpenGL is frozen at 4.1 (the driver itself reports `OpenGL 4.1 Metal - 91.7`), so `GL43C.glVertexAttribFormat`
has no symbol to resolve — the address stays `0` and LWJGL aborts.

### 2. Viewpoint calls the family unconditionally

`javap -p -c viewpoint/render/MeshArena.class` → `recordAttributes()` is a straight, unguarded sequence
(no `GLCapabilities` field reference appears anywhere in `MeshArena`):

```
 2: invokestatic  org/lwjgl/opengl/GL20.glEnableVertexAttribArray:(I)V
13: invokestatic  org/lwjgl/opengl/GL43.glVertexAttribFormat:(IIIZI)V   <-- attribute 6, size 4, GL_FLOAT, offset 0
20: invokestatic  org/lwjgl/opengl/GL43.glVertexAttribBinding:(II)V     <-- attribute 6 -> binding 6
23: invokestatic  org/lwjgl/opengl/GL20.glEnableVertexAttribArray:(I)V
37: invokestatic  org/lwjgl/opengl/GL43.glVertexAttribFormat:(IIIZI)V   <-- attribute 7, offset 16
44: invokestatic  org/lwjgl/opengl/GL43.glVertexAttribBinding:(II)V
61: invokestatic  org/lwjgl/opengl/GL43.glVertexAttribFormat:(IIIZI)V   <-- attribute 8, offset 32
68: invokestatic  org/lwjgl/opengl/GL43.glVertexAttribBinding:(II)V
74: invokestatic  org/lwjgl/opengl/GL43.glVertexBindingDivisor:(II)V
```

Its caller `Meshes.init()` also has no capability check (`Meshes` only calls `MeshArena.*`), so a GL 4.1/emulated
context still enters the arena path.

### 3. The bridge does not register a hook for any of them

The bridge hooks by *function name* (`pzmac41.CoreGl.registerHooks()` / `hook(String, CallbackI)`, using
`org.lwjgl.system.libffi` callbacks + a wrapped `org.lwjgl.system.FunctionProvider`). Extracting the pool of GL
names referenced by `pzmac41.CoreGl.class`:

```
$ javap -v -p pzmac41/CoreGl.class | grep -oE 'Utf8 +gl[A-Z][A-Za-z0-9]*' | awk '{print $2}' | sort -u | wc -l
172
$ ... | grep -xE 'glVertexAttribFormat|glVertexAttribBinding|glVertexBindingDivisor|glBindVertexBuffer'
(nothing)
```

The same names *are* present in `pzmac41/capability-slots.properties` (the full 2234-entry GLCapabilities
name→slot map), but no hook is registered for them, and the bridge's own native ceiling is `GL41C`
(the LWJGL classes it references are `GL11C … GL41C` + `GLCapabilities` — it never calls into `GL43C`/`GL45C`).

### 4. This family is not the only gap — it is just the first one reached

All distinct `GL42/GL43/GL44/GL45` functions referenced by `Viewpoint.jar` (32 of them) versus the bridge's hook
list (3 of 32 covered):

```
covered:      glTexStorage2D, glTexStorage3D, glClearTexImage
not covered:  glBindImageTexture, glDrawArraysInstancedBaseInstance, glMemoryBarrier, glTexStorage1D,
              glBindVertexBuffer, glClearBufferData, glCopyImageSubData, glDebugMessageCallback,
              glDispatchCompute, glMultiDrawArraysIndirect, glMultiDrawElementsIndirect, glPopDebugGroup,
              glPushDebugGroup, glTexBufferRange, glVertexAttribBinding, glVertexAttribFormat,
              glVertexAttribIFormat, glVertexBindingDivisor, glBufferStorage, glCreateFramebuffers,
              glCreateTextures, glNamedFramebufferDrawBuffer, glNamedFramebufferReadBuffer,
              glNamedFramebufferTextureLayer, glTextureParameteri, glTextureStorage2D, glTextureStorage3D,
              glTextureSubImage2D, glTextureSubImage3D
```

Most other Viewpoint subsystems are capability-gated (`viewpoint/platform/IrisPacks` reads
`OpenGL40 … OpenGL46`, `GlDebug` reads `OpenGL43`), which is why the run survives shader/texture/model setup.
`MeshArena` is not gated, so it is the first unguarded call and it aborts the JVM instead of failing softly.

## Why this is not an out-of-memory or multiplayer issue

The first reported symptom was `OutOfMemoryError` at `max: 3072 Mb` while connected to a 198-mod multiplayer
server; raising the heap to 8192m removed all OOM (`OutOfMemory` count 0 in the next session) and the game then
produced **this** abort at the first world draw. The abort also occurs with no OOM, on a fresh single-player world,
and with no pack. It is a missing GL 4.3 entry point, not a resource problem.

## Questions for the author

1. `README_EN.txt` states the package was tested in-game on an M1 with "entering the world, first-person scene
   rendering". With the published bridge (sha256 `85c45fd3…`) that cannot happen, because `MeshArena.init` aborts
   on the first world draw. Was the tested bridge a different build? If so, please publish that build (and update
   `pins.properties` / the installer manifest accordingly).
2. If the family is genuinely out of scope, would you consider making `MeshArena` (or `Meshes.init`) not enter the
   arena path when the context is below GL 4.3, so users get a degraded render instead of a JVM abort?
3. Suggested bridge fix, in order of increasing state tracking:
   - `glVertexAttribFormat` / `glVertexAttribIFormat`, `glVertexAttribBinding`, `glVertexBindingDivisor`:
     record `attrib → (size, type, normalized, relativeOffset, binding, divisor)`.
   - `glBindVertexBuffer(binding, buffer, offset, stride)`: record `binding → (buffer, offset, stride)`.
   - Flush on `glBindVertexBuffer` (or at each draw): for every attrib of that binding, temporarily bind
     `buffer` and issue `glVertexAttribPointer(attrib, size, type, normalized, stride, offset + relativeOffset)`
     plus `glVertexAttribDivisor(attrib, divisor)` — all through the bridge's existing hooks so its virtual VAO
     state stays consistent — then restore `GL_ARRAY_BUFFER`.

## Attachments

* `console.txt` of the failing run (isolated profile): `/tmp/mac41-oom-console-2026-10-03.txt` is the earlier OOM
  run; the abort run is `<install>/userdata/Zomboid/console.txt`.
* `installer/PZVoxelStudioViewpoint.tsv` mismatch details (10/9/38) available on request.
