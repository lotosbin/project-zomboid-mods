package viewpointmac;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.FloatBuffer;

import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;

/**
 * 抓取**游戏给世界 3D 模型用的那套相机矩阵**（1.10）。
 *
 * <p>为什么要它：游戏在等距视图里画角色/载具这类 3D 模型时，会用
 * {@code zombie.core.skinnedmodel.ModelCamera#Begin()} 设置一套投影/视图矩阵。
 * 我们的 3D 几何（模型包的真 3D 物件）只要用**同一套矩阵**，就会精确落在
 * 它在 2.5D 里对应的位置上 —— 等于原位替换精灵，而且完全不需要 UV 重映射。
 *
 * <p>做法（机制无关，最稳）：
 * <pre>
 *   ModelCamera.instance.Begin()          // 让游戏把"世界 3D 相机"设好
 *   glGetFloatv(GL_PROJECTION_MATRIX)     // 直接读 GL 当前矩阵，不管它是怎么设的
 *   glGetFloatv(GL_MODELVIEW_MATRIX)
 *   ModelCamera.instance.End()            // 还原
 *   mvp = projection * view
 * </pre>
 * 拿不到就返回 false，调用方退回我们自己的相机（功能不会因此失效）。
 */
public final class GameMatrices {

    private static boolean initialized = false;
    private static boolean available = false;
    private static String failReason = "";

    private static Field fCameraInstance;
    private static Method mCameraBegin;
    private static Method mCameraEnd;

    private static final float[] PROJECTION = new float[16];
    private static final float[] VIEW = new float[16];
    private static final float[] MVP = new float[16];
    private static final FloatBuffer BUFFER = BufferUtils.createFloatBuffer(16);

    private static boolean valid = false;
    private static long captures = 0;
    private static long failures = 0;
    private static String lastSummary = "not captured";

    public static boolean available() {
        init();
        return available;
    }

    public static String failReason() {
        return failReason;
    }

    public static boolean valid() {
        return valid;
    }

    public static float[] mvp() {
        return MVP;
    }

    private static synchronized void init() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            Class<?> camera = Class.forName("zombie.core.skinnedmodel.ModelCamera");
            fCameraInstance = camera.getField("instance");
            mCameraBegin = camera.getMethod("Begin");
            mCameraEnd = camera.getMethod("End");
            available = true;
            Vp.log("game matrices bridge ready: ModelCamera.Begin + glGetFloatv (world 3D camera).");
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("game matrices unavailable, keeping our own camera: " + failReason);
        }
    }

    /**
     * 抓一次世界 3D 相机矩阵。每帧在绘制我们自己的几何之前调用。
     *
     * @return 是否拿到可用矩阵
     */
    public static boolean capture() {
        init();
        valid = false;
        if (!available) {
            return false;
        }
        Object camera = null;
        boolean begun = false;
        // 先把 GL 矩阵模式状态存下来，抓完还原
        int previousMatrixMode = 0;
        try {
            previousMatrixMode = GL11.glGetInteger(GL11.GL_MATRIX_MODE);
        } catch (Throwable ignored) {
            // 某些上下文可能不支持，忽略
        }
        try {
            camera = fCameraInstance.get(null);
            if (camera == null) {
                failures++;
                return false;
            }
            mCameraBegin.invoke(camera);
            begun = true;

            GL11.glGetFloatv(GL11.GL_PROJECTION_MATRIX, (FloatBuffer) BUFFER.clear());
            BUFFER.get(PROJECTION);
            GL11.glGetFloatv(GL11.GL_MODELVIEW_MATRIX, (FloatBuffer) BUFFER.clear());
            BUFFER.get(VIEW);

            float[] mvp = Mat4.multiply(PROJECTION, VIEW);
            System.arraycopy(mvp, 0, MVP, 0, 16);
            valid = isSane(MVP);
            if (valid) {
                captures++;
                if (captures == 1) {
                    lastSummary = String.format(java.util.Locale.ROOT,
                        "proj[0]=%.4f proj[5]=%.4f proj[10]=%.4f modelview[12..14]=(%.2f,%.2f,%.2f)",
                        PROJECTION[0], PROJECTION[5], PROJECTION[10],
                        VIEW[12], VIEW[13], VIEW[14]);
                    Vp.log("world 3D camera captured: " + lastSummary);
                }
            } else {
                failures++;
            }
            return valid;
        } catch (Throwable t) {
            failures++;
            if (failures == 1) {
                Vp.warn("world 3D camera capture failed: " + t);
            }
            return false;
        } finally {
            if (begun && camera != null) {
                try {
                    mCameraEnd.invoke(camera);
                } catch (Throwable ignored) {
                    // 还原失败不影响游戏
                }
            }
            try {
                GL11.glMatrixMode(previousMatrixMode);
            } catch (Throwable ignored) {
                // 同上
            }
        }
    }

    /** 粗略判据：不能是全零、也不能全是 NaN/Inf。 */
    private static boolean isSane(float[] m) {
        int nonZero = 0;
        for (float v : m) {
            if (Float.isNaN(v) || Float.isInfinite(v)) {
                return false;
            }
            if (Math.abs(v) > 1e-6f) {
                nonZero++;
            }
        }
        return nonZero >= 4;
    }

    public static String describe() {
        if (!available) {
            return "unavailable (" + failReason + ")";
        }
        return "valid=" + valid + " captures=" + captures + " failures=" + failures
            + " | " + lastSummary;
    }

    private GameMatrices() {
    }
}
