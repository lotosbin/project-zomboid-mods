package viewpointmac;

/**
 * 第一/第三人称相机（P1）。
 *
 * <p>坐标约定沿用游戏世界：**X 向东、Y 向南、Z 向上**，1 个单位 = 1 个地块格。
 * 朝向直接取玩家的 {@code getForwardDirectionX/Y()}（单位向量），这样就不必猜
 * 游戏内部的角度基准（0 是北还是东、顺时针还是逆时针）——PZ 里这类约定很容易踩坑。
 */
public final class Camera {

    private static final float[] UP = {0f, 0f, 1f};

    private static final float[] EYE = new float[3];
    private static final float[] TARGET = new float[3];

    private static float[] view = Mat4.identity();
    private static float[] proj = Mat4.identity();
    private static float[] mvp = Mat4.identity();

    private static boolean valid = false;
    private static boolean alignedToGame = false;
    private static float lastYaw = 0f;
    private static float yawDeg;
    private static float pitchDeg;
    private static final float[] forward = {1f, 0f, 0f};

    public static float forwardX() {
        return forward[0];
    }

    public static float forwardY() {
        return forward[1];
    }

    public static float forwardZ() {
        return forward[2];
    }

    public static boolean valid() {
        return valid;
    }

    public static float[] mvp() {
        return mvp;
    }

    /** 投影矩阵（列主序 16 float，可直接喂 glLoadMatrixf / JOML）。 */
    /** 当前是否用的是游戏的世界 3D 相机矩阵。 */
    /** 当前视线 yaw（弧度，世界 XY 平面）。 */
    public static float yaw() {
        return lastYaw;
    }

    public static boolean alignedToGame() {
        return alignedToGame;
    }

    public static float[] projection() {
        return proj;
    }

    /** 视图矩阵（列主序 16 float）。 */
    public static float[] view() {
        return view;
    }

    public static float[] eye() {
        return EYE;
    }

    public static float yawDegrees() {
        return yawDeg;
    }

    public static float pitchDegrees() {
        return pitchDeg;
    }

    /**
     * 从玩家状态刷新相机。
     *
     * @return 本帧是否有可用相机
     */
    public static boolean update(int screenWidth, int screenHeight) {
        if (!GameWorld.available() || !GameWorld.inGame() || screenWidth <= 0 || screenHeight <= 0) {
            valid = false;
            return false;
        }

        // 基准朝向 = 角色朝向；再叠加鼠标自由视角的偏移
        float baseYaw = (float) Math.atan2(GameWorld.forwardY(), GameWorld.forwardX());
        float yaw = baseYaw + MouseLook.yaw();
        float pitch = (float) Math.toRadians(VpConfig.cameraPitchDeg()) + MouseLook.pitch();
        float limit = (float) Math.toRadians(89.0);
        if (pitch > limit) {
            pitch = limit;
        }
        if (pitch < -limit) {
            pitch = -limit;
        }
        float cosPitch = (float) Math.cos(pitch);
        forward[0] = (float) Math.cos(yaw) * cosPitch;
        forward[1] = (float) Math.sin(yaw) * cosPitch;
        forward[2] = (float) Math.sin(pitch);

        lastYaw = yaw;
        yawDeg = (float) Math.toDegrees(yaw);
        pitchDeg = (float) Math.toDegrees(pitch);

        float baseX = GameWorld.playerX();
        float baseY = GameWorld.playerY();
        float baseZ = GameWorld.playerZ();

        if (VpConfig.cameraThirdPerson()) {
            float distance = VpConfig.cameraDistance();
            EYE[0] = baseX - forward[0] * distance;
            EYE[1] = baseY - forward[1] * distance;
            EYE[2] = baseZ + VpConfig.cameraEyeHeight() + 0.25f;
        } else {
            EYE[0] = baseX;
            EYE[1] = baseY;
            EYE[2] = baseZ + VpConfig.cameraEyeHeight();
        }

        TARGET[0] = EYE[0] + forward[0];
        TARGET[1] = EYE[1] + forward[1];
        TARGET[2] = EYE[2] + forward[2];

        // 对齐模式：直接用游戏给世界 3D 模型用的那套矩阵，
        // 这样我们的几何与游戏视图严格对齐（模型正好盖住对应的精灵）。
        // 覆盖模式（3D 盖住原版画面）必须用**我们自己的相机**；
        // 只有叠加对照模式才对齐游戏相机。
        if (VpConfig.alignVanillaView() && !VpConfig.coverVanilla() && GameMatrices.capture()) {
            System.arraycopy(GameMatrices.mvp(), 0, mvp, 0, 16);
            alignedToGame = true;
            valid = true;
            return true;
        }
        alignedToGame = false;

        view = Mat4.lookAt(EYE, TARGET, UP);
        proj = Mat4.perspective((float) Math.toRadians(VpConfig.cameraFovDeg()),
            (float) screenWidth / (float) screenHeight, 0.05f, 240f);
        mvp = Mat4.multiply(proj, view);
        valid = true;
        return true;
    }

    public static String describe() {
        return baseDescribe()
            + (alignedToGame ? " [aligned to game world camera]" : " [own camera]")
            + (VpConfig.coverVanilla() ? " [COVER mode: opaque 3D hides the vanilla view]" : " [overlay mode]");
    }

    private static String baseDescribe() {
        if (!valid) {
            return "camera not available (player not in world yet)";
        }
        return String.format(java.util.Locale.ROOT,
            "eye=(%.2f, %.2f, %.2f) yaw=%.1f pitch=%.1f fov=%.0f mode=%s",
            EYE[0], EYE[1], EYE[2], yawDeg, pitchDeg, VpConfig.cameraFovDeg(),
            VpConfig.cameraThirdPerson() ? "third" : "first");
    }

    private Camera() {
    }
}
