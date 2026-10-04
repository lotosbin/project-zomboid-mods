package viewpointmac;

/**
 * 渲染钩子的落点：由 {@link Patch_PostRender} 在游戏渲染线程的
 * {@code zombie.core.SpriteRenderer#postRender} 前后调用。
 *
 * <p>调用时序（已核对游戏字节码）：
 * <pre>
 *   postRender()                    ← 渲染线程，GL 上下文有效
 *     ├─ buildStateUIDrawBuffer()   → ringBuffer.render()
 *     ├─ buildStateDrawBuffer()     → ringBuffer.render()
 *     └─ return                     ← 本方法在此时被 @OnExit 调用，画面尚未交换
 * </pre>
 * 因此 {@code onFrameExit()} 里画的东西会叠加在本帧画面之上，且早于 buffer swap。
 */
public final class RenderHook {

    /** 连续异常达到该次数后永久关闭注入，避免刷屏或拖慢游戏。 */
    private static final int MAX_ERRORS = 3;

    private static volatile boolean disabled = false;
    private static int errors = 0;
    private static boolean reportWritten = false;

    public static boolean disabled() {
        return disabled;
    }

    public static int errorCount() {
        return errors;
    }

    public static void onFrameEnter() {
        if (disabled) {
            return;
        }
        try {
            GlProbe.probeOnce();
            FrameStats.onFrameEnter();
        } catch (Throwable t) {
            fail("frame enter", t);
        }
    }

    public static void onFrameExit() {
        if (disabled) {
            return;
        }
        long drawStarted = System.nanoTime();
        try {
            // 永远画在游戏画面之上：不 patch 原版渲染，而是**用不透明的 3D 把它盖住**
            if (Compat.ok()) {
                Scene3D.draw();
            }
        } catch (Throwable t) {
            fail("3D scene draw", t);
        }
        try {
            if (VpConfig.overlay() && Compat.ok() && GameWorld.inGameState()) {
                Overlay.draw();
            }
            writeSnapshot();
        } catch (Throwable t) {
            fail("overlay draw", t);
        }
        try {
            FrameStats.onFrameExit(drawStarted);
        } catch (Throwable t) {
            fail("frame exit", t);
        }
        // 首帧末尾落盘：此时 GlProbe / Scene3D / Overlay 都已初始化，报告内容才是完整的
        if (!reportWritten && GlProbe.probed()) {
            reportWritten = true;
            if (VpConfig.reportOnStart()) {
                try {
                    Report.write();
                } catch (Throwable t) {
                    fail("report write", t);
                }
            }
        }
    }

    /** 供 Lua / 报告查询的一行状态。 */
    private static int snapshotTick = 0;

    /**
     * 周期性把状态写进 {@code ~/Zomboid/ViewpointMac.log}（**只写文件**，不刷控制台）。
     *
     * <p>目的：出问题时不用用户复制粘贴 —— 直接读那个文件就能看到
     * 采样规模、贴图 UV 原始值、角色/相机状态、当前开关组合。
     */
    private static void writeSnapshot() {
        snapshotTick++;
        if (snapshotTick % 300 != 0 || !WorldTiles.available()) {
            return;
        }
        if (!GameWorld.inGameState()) {
            return;
        }
        try {
            Vp.fileOnly("STATUS " + status());
            Vp.fileOnly("CONFIG " + VpConfig.describe());
            Vp.fileOnly("SCENE  " + Scene3D.describe());
            Vp.fileOnly("TEX    " + TileTextures.describe());
            Vp.fileOnly("TEXUV0 " + TileTextures.describeSlot(0));
            Vp.fileOnly("TEXUV1 " + TileTextures.describeSlot(1));
            Vp.fileOnly("CHAR   " + CharacterModels.describe());
        } catch (Throwable t) {
            Vp.fileOnly("SNAPSHOT FAILED: " + t);
        }
    }

    public static String status() {
        StringBuilder sb = new StringBuilder();
        sb.append("ViewpointMac ").append(Vp.VERSION)
          .append(" | hook=").append(disabled ? "DISABLED" : "active")
          .append(" | compat=").append(Compat.ok() ? "ok" : "failed")
          .append(" | overlay=").append(VpConfig.overlay() ? "on" : "off")
          .append(" | scene3d=").append(VpConfig.scene3d() ? "on" : "off")
          .append(" | voxel=").append(VpConfig.voxel() ? "on" : "off")
          .append(" | backend=").append(GlProbe.backend())
          .append(" | gl=").append(GlProbe.glVersion())
          .append(" | ").append(FrameStats.describe());
        return sb.toString();
    }

    private static synchronized void fail(String where, Throwable t) {
        errors++;
        Vp.error("render hook error (" + where + ", #" + errors + ")", t);
        if (errors >= MAX_ERRORS) {
            disabled = true;
            Vp.error("render hook disabled after " + errors + " errors; the game keeps running normally.", null);
            try {
                Report.write();
            } catch (Throwable ignored) {
                // 报告失败不影响主流程
            }
        }
    }

    private RenderHook() {
    }
}
