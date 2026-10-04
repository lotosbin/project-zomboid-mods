package viewpointmac;

import java.lang.reflect.Method;

/**
 * P8：让角色朝向/瞄准跟随我们的 3D 相机（1.11）。
 *
 * <p>自由视角打开后，如果不管朝向，就会出现"你在看东边、角色却朝北开枪"的错位。
 * 游戏提供了可写接口 {@code IsoGameCharacter.setForwardDirection(float, float)}，
 * 我们把相机 yaw 的世界方向喂给它，角色与瞄准就跟视线一致了。
 *
 * <p>只在"自由视角开启 + 存档内"时生效；每帧一次，失败自动禁用，不影响游戏。
 */
public final class Controls {

    private static boolean initialized = false;
    private static boolean available = false;
    private static String failReason = "";

    private static Method mSetForwardDirection;
    private static int writes = 0;
    private static int failures = 0;

    public static boolean available() {
        init();
        return available;
    }

    public static String failReason() {
        return failReason;
    }

    private static synchronized void init() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            Class<?> character = Class.forName("zombie.characters.IsoGameCharacter");
            mSetForwardDirection = character.getMethod("setForwardDirection", float.class, float.class);
            available = true;
            Vp.log("controls ready: IsoGameCharacter.setForwardDirection (character follows the 3D view).");
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("controls unavailable (character keeps the vanilla facing): " + failReason);
        }
    }

    /** 每帧调用：把角色朝向设成相机 yaw。 */
    public static void update(float yawRadians) {
        init();
        if (!available || !VpConfig.controlFacing()) {
            return;
        }
        if (!VpConfig.mouseLook() || !GameWorld.inGameState()) {
            return;
        }
        Object player = GameWorld.player();
        if (player == null) {
            return;
        }
        try {
            float dx = (float) Math.cos(yawRadians);
            float dy = (float) Math.sin(yawRadians);
            mSetForwardDirection.invoke(player, dx, dy);
            writes++;
        } catch (Throwable t) {
            failures++;
            if (failures == 1) {
                Vp.warn("controls disabled: " + t);
            }
            available = false;
        }
    }

    public static String describe() {
        if (!available) {
            return "unavailable (" + failReason + ")";
        }
        if (!VpConfig.controlFacing()) {
            return "off";
        }
        return "writes=" + writes + " failures=" + failures;
    }

    private Controls() {
    }
}
