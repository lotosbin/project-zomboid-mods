package viewpointmac;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * 原版天空颜色来源（1.0）。
 *
 * <p>反射链路：{@code zombie.iso.IsoWorld.instance.sky}（public 字段）→
 * {@code zombie.iso.sprite.SkyBox} 的
 * {@code getShaderSkyHColour() / getShaderSkyLColour() / getShaderSunColor()}，
 * 得到 {@code zombie.core.Color}（public float 字段 r/g/b）。
 *
 * <p>这样天空会跟着游戏的**昼夜与天气**变化，而不是我们写死的渐变；
 * 拿不到时退回内置渐变，不影响功能。
 */
public final class SkySource {

    private static boolean initialized = false;
    private static boolean available = false;
    private static String failReason = "";

    private static Field fWorldInstance;
    private static Field fWorldSky;
    private static Method mSkyHigh;
    private static Method mSkyLow;
    private static Method mSkySun;
    private static Field fColorR;
    private static Field fColorG;
    private static Field fColorB;

    /** 天空顶部颜色（天顶）。 */
    private static float highR = 0.28f;
    private static float highG = 0.48f;
    private static float highB = 0.92f;

    /** 天空底部颜色（地平线）。 */
    private static float lowR = 0.72f;
    private static float lowG = 0.83f;
    private static float lowB = 0.95f;

    /** 太阳/光照颜色，用来给地面一侧染色。 */
    private static float sunR = 0.95f;
    private static float sunG = 0.90f;
    private static float sunB = 0.80f;

    private static boolean fromGame = false;
    private static long reads = 0;
    private static long failures = 0;

    public static boolean available() {
        init();
        return available;
    }

    public static boolean fromGame() {
        return fromGame;
    }

    public static float highR() {
        return highR;
    }

    public static float highG() {
        return highG;
    }

    public static float highB() {
        return highB;
    }

    public static float lowR() {
        return lowR;
    }

    public static float lowG() {
        return lowG;
    }

    public static float lowB() {
        return lowB;
    }

    public static float sunR() {
        return sunR;
    }

    public static float sunG() {
        return sunG;
    }

    public static float sunB() {
        return sunB;
    }

    private static synchronized void init() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            Class<?> world = Class.forName("zombie.iso.IsoWorld");
            fWorldInstance = world.getField("instance");
            fWorldSky = world.getField("sky");

            Class<?> skyBox = Class.forName("zombie.iso.sprite.SkyBox");
            mSkyHigh = skyBox.getMethod("getShaderSkyHColour");
            mSkyLow = skyBox.getMethod("getShaderSkyLColour");
            mSkySun = skyBox.getMethod("getShaderSunColor");

            Class<?> color = Class.forName("zombie.core.Color");
            fColorR = color.getField("r");
            fColorG = color.getField("g");
            fColorB = color.getField("b");

            available = true;
            Vp.log("sky source ready: IsoWorld.sky shader colours (reflection).");
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("sky source unavailable, using built-in gradient: " + failReason);
        }
    }

    /** 每帧读一次游戏天空颜色。 */
    public static void update() {
        init();
        if (!available) {
            return;
        }
        try {
            Object world = fWorldInstance.get(null);
            if (world == null) {
                return;
            }
            Object sky = fWorldSky.get(world);
            if (sky == null) {
                return;
            }
            float[] high = read(mSkyHigh, sky);
            float[] low = read(mSkyLow, sky);
            float[] sun = read(mSkySun, sky);
            if (high != null) {
                highR = high[0];
                highG = high[1];
                highB = high[2];
            }
            if (low != null) {
                lowR = low[0];
                lowG = low[1];
                lowB = low[2];
            }
            if (sun != null) {
                sunR = sun[0];
                sunG = sun[1];
                sunB = sun[2];
            }
            fromGame = high != null || low != null;
            reads++;
        } catch (Throwable t) {
            failures++;
            if (failures == 1) {
                Vp.warn("sky colour read failed, using built-in gradient: " + t);
            }
            available = false;
        }
    }

    private static float[] read(Method method, Object sky) {
        try {
            Object colour = method.invoke(sky);
            if (colour == null) {
                return null;
            }
            return new float[] {
                clamp(((Number) fColorR.get(colour)).floatValue()),
                clamp(((Number) fColorG.get(colour)).floatValue()),
                clamp(((Number) fColorB.get(colour)).floatValue()),
            };
        } catch (Throwable t) {
            return null;
        }
    }

    private static float clamp(float value) {
        if (Float.isNaN(value)) {
            return 0f;
        }
        return value < 0f ? 0f : (value > 1f ? 1f : value);
    }

    public static String describe() {
        return (fromGame ? "game sky" : (available ? "built-in gradient (sky not ready)" : "built-in gradient"))
            + String.format(java.util.Locale.ROOT, " high=(%.2f,%.2f,%.2f) low=(%.2f,%.2f,%.2f) reads=%d",
                highR, highG, highB, lowR, lowG, lowB, reads);
    }

    private SkySource() {
    }
}
