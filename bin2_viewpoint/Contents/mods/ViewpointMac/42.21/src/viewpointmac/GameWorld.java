package viewpointmac;

import java.lang.reflect.Method;

/**
 * 游戏世界数据的反射桥。
 *
 * <p>为什么用反射而不是直接引用：游戏自身的 class 文件是 Java 25 格式（major 69），
 * 而本模组用 JDK 17 编译（只依赖 `org.lwjgl.*` 与 ZombieBuddy 注解）。
 * 反射让构建不依赖游戏 jar 的字节码版本，同时把"签名对不上"的风险集中到一处——
 * {@link Compat} 会在启动时校验，{@link #init()} 失败也只是关闭 3D 场景，不会影响游戏。
 *
 * <p>每帧只做几次 invoke，开销可忽略；Method 对象全部缓存。
 */
public final class GameWorld {

    private static boolean initialized = false;
    private static boolean available = false;
    private static String failReason = "";

    private static Method mGetInstance;
    private static Method mGetX;
    private static Method mGetY;
    private static Method mGetZ;
    private static Method mForwardX;
    private static Method mForwardY;
    private static Method mLookAngle;
    private static Method mIsIngameState;
    private static boolean gameStateOk = false;
    private static boolean inGameState = false;

    private static boolean inGame = false;
    private static Object playerRef = null;
    private static float playerX;
    private static float playerY;
    private static float playerZ;
    private static float forwardX = 1f;
    private static float forwardY = 0f;
    private static float lookAngleRad;
    private static int sampleCount = 0;

    public static boolean available() {
        init();
        return available;
    }

    /** 玩家对象本身（{@code IsoPlayer}），给角色模型探针/渲染用。 */
    public static Object player() {
        return playerRef;
    }

    /**
     * 是否真的在存档里（官方 {@code GameWindow.isIngameState()}）。
     *
     * <p>这个判定很关键：主菜单也会创建玩家对象和世界，只有它能把"主菜单背景场景"
     * 和"真的在玩游戏"区分开。取不到句柄时保守返回 false。
     */
    public static boolean inGameState() {
        init();
        if (!gameStateOk || mIsIngameState == null) {
            return false;
        }
        try {
            inGameState = Boolean.TRUE.equals(mIsIngameState.invoke(null));
        } catch (Throwable t) {
            gameStateOk = false;
            inGameState = false;
            Vp.warn("GameWindow.isIngameState unavailable: " + t);
        }
        return inGameState;
    }

    public static String failReason() {
        return failReason;
    }

    public static boolean inGame() {
        return inGame && inGameState();
    }

    public static float playerX() {
        return playerX;
    }

    public static float playerY() {
        return playerY;
    }

    public static float playerZ() {
        return playerZ;
    }

    public static float forwardX() {
        return forwardX;
    }

    public static float forwardY() {
        return forwardY;
    }

    public static float lookAngleRadians() {
        return lookAngleRad;
    }

    public static int sampleCount() {
        return sampleCount;
    }

    private static synchronized void init() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            Class<?> playerClass = Class.forName("zombie.characters.IsoPlayer");
            mGetInstance = playerClass.getMethod("getInstance");
            mGetX = playerClass.getMethod("getX");
            mGetY = playerClass.getMethod("getY");
            mGetZ = playerClass.getMethod("getZ");
            mForwardX = playerClass.getMethod("getForwardDirectionX");
            mForwardY = playerClass.getMethod("getForwardDirectionY");
            mLookAngle = playerClass.getMethod("getLookAngleRadians");

            // 官方判定：zombie.GameWindow.isIngameState()
            // 主菜单里 IsoPlayer.getInstance() 也非空，不能用"玩家存在"当"在游戏里"，
            // 否则会在主菜单/审批对话框上藏光标、跳过背景渲染（1.3.0 的真实事故）。
            Class<?> windowClass = Class.forName("zombie.GameWindow");
            mIsIngameState = windowClass.getMethod("isIngameState");
            gameStateOk = true;
            available = true;
            Vp.log("world bridge ready: zombie.characters.IsoPlayer (reflection).");
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("world bridge unavailable: " + failReason);
        }
    }

    /**
     * 刷新玩家状态。任何异常都会关闭世界桥（并让 3D 场景自动降级），不会向上抛。
     *
     * @return 本帧是否拿到有效的玩家数据
     */
    public static boolean refresh() {
        init();
        if (!available) {
            inGame = false;
            return false;
        }
        try {
            Object player = mGetInstance.invoke(null);
            playerRef = player;
            if (player == null) {
                inGame = false;
                return false;
            }
            playerX = ((Number) mGetX.invoke(player)).floatValue();
            playerY = ((Number) mGetY.invoke(player)).floatValue();
            playerZ = ((Number) mGetZ.invoke(player)).floatValue();
            float fx = ((Number) mForwardX.invoke(player)).floatValue();
            float fy = ((Number) mForwardY.invoke(player)).floatValue();
            if (Math.abs(fx) > 1e-4f || Math.abs(fy) > 1e-4f) {
                forwardX = fx;
                forwardY = fy;
            }
            lookAngleRad = ((Number) mLookAngle.invoke(player)).floatValue();
            inGame = true;
            sampleCount++;
            return true;
        } catch (Throwable t) {
            available = false;
            inGame = false;
            failReason = String.valueOf(t);
            Vp.error("world bridge disabled after a failed read", t);
            return false;
        }
    }

    public static String describe() {
        if (!available) {
            return "unavailable (" + failReason + ")";
        }
        if (!inGame) {
            return "no player yet";
        }
        return String.format(java.util.Locale.ROOT,
            "player=(%.2f, %.2f, %.2f) forward=(%.2f, %.2f) look=%.1fdeg samples=%d",
            playerX, playerY, playerZ, forwardX, forwardY,
            Math.toDegrees(lookAngleRad), sampleCount);
    }

    private GameWorld() {
    }
}
