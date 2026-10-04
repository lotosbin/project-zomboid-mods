package viewpointmac;

import java.lang.reflect.Method;

/**
 * 自由视角输入（1.0）：鼠标增量 → 相机 yaw/pitch，并在开启时隐藏游戏光标。
 *
 * <p>反射接口（都在 {@code zombie.input.Mouse} 上）：
 * <pre>
 *   static synchronized int getX() / getY()   每帧自己算增量
 *   static void setCursorVisible(boolean)     第一人称必须藏光标
 *   static boolean isCursorVisible()
 * </pre>
 *
 * <p>只在存档内生效（{@link GameWorld#inGame()}），主菜单不动光标，避免影响菜单操作。
 */
public final class MouseLook {

    private static boolean initialized = false;
    private static boolean available = false;
    private static String failReason = "";

    private static Method mGetX;
    private static Method mGetY;
    private static Method mSetCursorVisible;
    private static Method mIsCursorVisible;

    private static int lastX = 0;
    private static int lastY = 0;
    private static boolean haveLast = false;

    private static float yawOffset = 0f;
    private static float pitchOffset = 0f;
    private static boolean cursorHidden = false;

    private static volatile boolean enabled = true;

    public static boolean available() {
        init();
        return available;
    }

    public static String failReason() {
        return failReason;
    }

    public static boolean enabled() {
        return enabled;
    }

    public static void setEnabled(boolean value) {
        enabled = value;
        if (!value) {
            restoreCursor();
        }
    }

    public static float yaw() {
        return yawOffset;
    }

    public static float pitch() {
        return pitchOffset;
    }

    /** 重置视角偏移（回到角色朝向）。 */
    public static void reset() {
        yawOffset = 0f;
        pitchOffset = 0f;
    }

    private static synchronized void init() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            Class<?> mouse = Class.forName("zombie.input.Mouse");
            mGetX = mouse.getMethod("getX");
            mGetY = mouse.getMethod("getY");
            mSetCursorVisible = mouse.getMethod("setCursorVisible", boolean.class);
            mIsCursorVisible = mouse.getMethod("isCursorVisible");
            available = true;
            Vp.log("mouse look ready: zombie.input.Mouse (delta + cursor control).");
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("mouse look unavailable: " + failReason);
        }
    }

    /** 每帧在渲染线程调用一次。 */
    public static void update() {
        init();
        if (!available) {
            return;
        }
        // 只有真的在存档里才碰光标：主菜单 / 审批对话框上必须保持系统光标可见
        boolean active = enabled && VpConfig.mouseLook() && GameWorld.inGameState();
        try {
            int x = ((Number) mGetX.invoke(null)).intValue();
            int y = ((Number) mGetY.invoke(null)).intValue();
            if (!haveLast) {
                lastX = x;
                lastY = y;
                haveLast = true;
            }
            int dx = x - lastX;
            int dy = y - lastY;
            lastX = x;
            lastY = y;

            if (!active) {
                restoreCursor();
                return;
            }
            hideCursor();
            // 屏幕像素 → 弧度
            float sensitivity = VpConfig.mouseSensitivity();
            yawOffset += dx * sensitivity;
            if (VpConfig.invertMouseY()) {
                pitchOffset += dy * sensitivity;
            } else {
                pitchOffset -= dy * sensitivity;
            }
            float limit = (float) Math.toRadians(89.0);
            if (pitchOffset > limit) {
                pitchOffset = limit;
            }
            if (pitchOffset < -limit) {
                pitchOffset = -limit;
            }
            // 防止长时间转动后数值过大
            float twoPi = (float) (Math.PI * 2);
            if (yawOffset > twoPi || yawOffset < -twoPi) {
                yawOffset %= twoPi;
            }
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("mouse look disabled: " + failReason);
            restoreCursor();
        }
    }

    private static void hideCursor() {
        if (cursorHidden || mSetCursorVisible == null) {
            return;
        }
        try {
            mSetCursorVisible.invoke(null, false);
            cursorHidden = true;
        } catch (Throwable ignored) {
            // 藏不了就算了，不影响相机
        }
    }

    private static void restoreCursor() {
        if (!cursorHidden || mSetCursorVisible == null) {
            return;
        }
        try {
            mSetCursorVisible.invoke(null, true);
        } catch (Throwable ignored) {
            // 同上
        }
        cursorHidden = false;
    }

    public static String describe() {
        if (!available) {
            return "unavailable (" + failReason + ")";
        }
        return String.format(java.util.Locale.ROOT,
            "%s yaw=%.1fdeg pitch=%.1fdeg cursorHidden=%s",
            enabled ? "on" : "off", Math.toDegrees(yawOffset), Math.toDegrees(pitchOffset), cursorHidden);
    }

    private MouseLook() {
    }
}
