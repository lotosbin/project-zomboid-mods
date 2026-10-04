package viewpointmac;

import java.lang.reflect.Method;

import org.lwjgl.opengl.GL11;

/**
 * 整屏尺寸解析。
 *
 * <p><b>为什么不直接用当前 viewport：</b>PZ 的渲染线程在 `postRender()` 结束时，viewport 往往
 * 还停在"等距相机的偏移视口"上（原点被平移、尺寸比窗口小）。如果我们沿用它的 viewport，
 * 自绘内容就会被整体推到角落里 —— 第一版实测就是这个现象：3D 网格缩在左下角、
 * 2D 面板也不在左上角。
 *
 * <p>所以每次自绘前必须显式把 viewport 设成整屏，画完再还原。整屏尺寸按可靠性依次取：
 * <ol>
 *   <li>{@code org.lwjglx.opengl.Display.getWidth()/getHeight()}（GLFW 窗口）；</li>
 *   <li>{@code zombie.core.Core.getInstance().getScreenWidth()/getScreenHeight()}；</li>
 *   <li>兜底用当前 GL viewport 的尺寸。</li>
 * </ol>
 * 全部走反射，保持"编译期不依赖游戏类"的约束。
 */
public final class GameScreen {

    private static boolean initialized = false;
    private static boolean displayOk = false;
    private static boolean coreOk = false;
    private static String source = "gl viewport";

    private static Method mDisplayWidth;
    private static Method mDisplayHeight;
    private static Method mCoreGetInstance;
    private static Method mCoreWidth;
    private static Method mCoreHeight;

    private static int lastWidth = 0;
    private static int lastHeight = 0;
    private static int lastViewportWidth = 0;
    private static int lastViewportHeight = 0;

    /** 解析后的来源，用于报告/排障。 */
    public static String source() {
        return source;
    }

    public static int width() {
        return lastWidth;
    }

    public static int height() {
        return lastHeight;
    }

    private static synchronized void init() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            Class<?> display = Class.forName("org.lwjglx.opengl.Display");
            mDisplayWidth = display.getMethod("getWidth");
            mDisplayHeight = display.getMethod("getHeight");
            displayOk = true;
        } catch (Throwable t) {
            displayOk = false;
        }
        try {
            Class<?> core = Class.forName("zombie.core.Core");
            mCoreGetInstance = core.getMethod("getInstance");
            Class<?> instance = Class.forName("zombie.core.Core");
            mCoreWidth = instance.getMethod("getScreenWidth");
            mCoreHeight = instance.getMethod("getScreenHeight");
            coreOk = true;
        } catch (Throwable t) {
            coreOk = false;
        }
        Vp.log("screen size source: display=" + displayOk + " core=" + coreOk);
    }

    /**
     * 计算本帧应当使用的整屏尺寸。
     *
     * @param viewportWidth  当前 GL viewport 宽（兜底）
     * @param viewportHeight 当前 GL viewport 高（兜底）
     * @return {width, height}
     */
    public static int[] resolve(int viewportWidth, int viewportHeight) {
        init();
        lastViewportWidth = viewportWidth;
        lastViewportHeight = viewportHeight;
        if (displayOk) {
            Integer w = invokeInt(mDisplayWidth, null);
            Integer h = invokeInt(mDisplayHeight, null);
            if (w != null && h != null && w > 0 && h > 0) {
                source = "lwjglx.Display";
                lastWidth = w;
                lastHeight = h;
                return new int[] {w, h};
            }
        }
        if (coreOk) {
            try {
                Object core = mCoreGetInstance.invoke(null);
                if (core != null) {
                    Integer w = invokeInt(mCoreWidth, core);
                    Integer h = invokeInt(mCoreHeight, core);
                    if (w != null && h != null && w > 0 && h > 0) {
                        source = "zombie.core.Core";
                        lastWidth = w;
                        lastHeight = h;
                        return new int[] {w, h};
                    }
                }
            } catch (Throwable ignored) {
                // 落到兜底
            }
        }
        source = "gl viewport";
        lastWidth = viewportWidth;
        lastHeight = viewportHeight;
        return new int[] {viewportWidth, viewportHeight};
    }

    private static Integer invokeInt(Method method, Object target) {
        try {
            Object value = method.invoke(target);
            return value instanceof Number ? ((Number) value).intValue() : null;
        } catch (Throwable t) {
            return null;
        }
    }

    /** 便捷方法：读取当前 viewport 并解析整屏尺寸。 */
    public static int[] current() {
        int[] viewport = new int[4];
        GL11.glGetIntegerv(GL11.GL_VIEWPORT, viewport);
        return resolve(viewport[2], viewport[3]);
    }

    public static String describe() {
        return "screen=" + lastWidth + "x" + lastHeight + " source=" + source
            + " (game viewport was " + lastViewportWidth + "x" + lastViewportHeight + ")";
    }

    private GameScreen() {
    }
}
