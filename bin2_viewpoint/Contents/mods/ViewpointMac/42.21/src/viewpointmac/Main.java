package viewpointmac;

/**
 * 模组入口（ZombieBuddy 会在加载 JAR 时调用 {@code <javaPkgName>.Main#main}）。
 *
 * <p>这里只做三件在<strong>主线程</strong>能安全完成的事：
 * <ol>
 *   <li>读取配置；</li>
 *   <li>兼容性自检（纯反射，不碰 GL）；</li>
 *   <li>打日志，必要时写一份环境报告。</li>
 * </ol>
 * GL 相关的一切都推迟到渲染线程首帧（见 {@link GlProbe}），因为主线程没有当前上下文。
 */
public final class Main {

    public static void main(String[] args) {
        Vp.log("ViewpointMac " + Vp.VERSION + " loading (macOS/Apple Silicon 3D experiment).");
        try {
            VpConfig.load();
        } catch (Throwable t) {
            Vp.error("config load failed; defaults stay in place", t);
        }
        try {
            Compat.checkAndLog();
        } catch (Throwable t) {
            Vp.error("compat check failed", t);
        }
        VpCamera.init();
        // 保险丝：无论怎么退出，都要确保系统光标是可见的
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            try {
                MouseLook.setEnabled(false);
            } catch (Throwable ignored) {
                // 关服阶段不做任何事
            }
        }, "ViewpointMac-cursor-restore"));
        try {
            VoxelPack.scan();
        } catch (Throwable t) {
            Vp.error("voxel pack scan failed", t);
        }
        if (!Compat.ok()) {
            Vp.warn("render injection is OFF: the hook targets are missing on this game build.");
        } else {
            Vp.log("render hook armed on zombie.core.SpriteRenderer#postRender.");
        }
        if (Compat.ok()) {
            Vp.log("patches: SpriteRenderer#postRender (3D render) + SpriteRenderer#buildStateDrawBuffer"
                + " (world-pass flag only, nothing skipped) + TextureDraw.DrawQueued"
                + " (vanilla character draw handover, gated by 4 conditions).");
            Vp.log("mode: overlay - the 3D scene is drawn on top of the untouched vanilla view.");
        }
        Vp.logSessionStart("v" + Vp.VERSION);
        Vp.log("config: " + VpConfig.describe());
        Vp.log("log file: " + Vp.logFile().getAbsolutePath());
        Vp.log("GL probing is deferred to the render thread's first frame.");
    }

    private Main() {
    }
}
