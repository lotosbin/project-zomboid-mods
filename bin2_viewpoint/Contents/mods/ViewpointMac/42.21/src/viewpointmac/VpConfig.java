package viewpointmac;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Properties;

/**
 * 运行期配置（~/Zomboid/viewpointmac.properties）。
 *
 * <p>首次运行会自动写出默认配置，方便玩家手工调整；文件缺失或损坏时一律退回默认值，
 * 绝不因为配置问题影响游戏启动。
 */
public final class VpConfig {

    /** 是否绘制 GL 覆盖层：这是 P0 阶段证明"能注入渲染线程"的可见证据。跨线程读写，必须 volatile。 */
    private static volatile boolean overlay = true;

    /** 是否输出详细日志。跨线程读写，必须 volatile。 */
    private static volatile boolean verbose = false;

    /** 是否在探针完成后自动写一份报告文件。 */
    private static boolean reportOnStart = true;

    /** 覆盖层原点（屏幕逻辑像素，左上角为 0,0）。 */
    private static int overlayX = 16;
    private static int overlayY = 16;

    /** 帧时间柱状图的柱数。 */
    private static int graphBars = 80;

    // ---------------------------------------------------------------- P1：3D 相机

    /** 是否绘制 3D 调试场景（网格 / 坐标轴 / 玩家盒 / 世界原点标记）。跨线程读写，必须 volatile。 */
    private static volatile boolean scene3d = true;

    /** 地面网格半径（单位：地块格）。 */
    private static int sceneGridRadius = 24;

    /** 垂直视场角（度）。 */
    private static float cameraFovDeg = 72f;

    /** 视线俯仰角（度，负值向下看）。 */
    private static float cameraPitchDeg = -8f;

    /** 第一人称眼高（相对于角色脚底）。 */
    private static float cameraEyeHeight = 1.55f;

    /** 是否第三人称。 */
    private static volatile boolean cameraThirdPerson = false;

    /** 第三人称时相机距离角色的距离。 */
    private static float cameraDistance = 4.5f;

    // ---------------------------------------------------------------- P2：体素世界

    /** 是否把游戏世界采样成体素并绘制。跨线程读写，必须 volatile。 */
    private static volatile boolean voxel = true;

    /** 采样半径（地块格，上限 31 以免超出缓冲）。 */
    private static int voxelRadius = 16;

    /** 每帧最多采样多少个地块（预算式，避免掉帧）。 */
    private static int voxelBudget = 256;

    /** 线框模式：不遮挡游戏画面，适合排查采样是否正确。 */
    private static volatile boolean voxelWireframe = false;

    /** 是否使用原版精灵贴图给体素上材质（关掉则退回纯色）。 */
    private static volatile boolean voxelTextured = true;

    /** 是否用 PZ Voxel Studio 模型包渲染物件（真 3D 几何）。 */
    private static volatile boolean voxelModels = true;

    /**
     * 是否给地面铺带贴图的平板。
     * 默认**开**：用原版地板精灵（UV 内缩 25% 取不透明区域）盖住游戏自己的地面绘制。
     */
    private static volatile boolean voxelFloor = false;

    /**
     * 是否绘制天空背景（用游戏天空颜色）。
     * 默认关：天空盒会整屏盖住游戏画面，只在不需要游戏画面时才开。
     */
    private static volatile boolean voxelSky = false;

    /** 是否启用鼠标自由视角（第一人称）。 */
    private static volatile boolean mouseLook = true;

    /**
     * 是否给我们自己的 3D 层绘制实体（玩家/僵尸）方块。
     *
     * <p>默认关：角色在原版渲染里**已经画好了**（有模型有动画），
     * 再叠一个方块只会把它盖住。方块留给"原版没画"的场合做对照（{@code Ctrl+Alt+E}）。
     */
    private static volatile boolean entities = false;

    /**
     * 是否**额外**用原版骨骼模型 + 动画再画一遍玩家/僵尸。
     *
     * <p>默认关：我们没有跳过原版渲染，游戏自己已经把角色画好了；
     * 这里再画一遍是脱离渲染状态机的外部调用，容易位置不对或污染下一帧。
     * 想对比就按 {@code Ctrl+Alt+K} 打开。
     */
    private static volatile boolean characterModels = true;

    /**
     * 原版自带 SpriteModel 的物件（载具等）是否让给游戏自己画。
     * 默认让位（不画盒子盖住它）；若发现这类物件反而变少/不见了，可设为 false 强制铺盒子。
     */
    private static volatile boolean voxelSkipOwn3d = true;

    /**
     * 覆盖模式（Viewpoint 等价）：用我们**不透明的 3D 场景把原版画面整个盖住**，
     * 而不是去 patch/跳过原版的渲染。
     *
     * <p>做法：天空盒是包围相机的大立方体且不透明 → 先画它就把原版整屏盖掉，
     * 之后画的地面/物件/角色再叠在上面。**完全不动游戏的渲染管线，零风险。**
     * 开启后相机必须用我们自己的（没有原版画面可对齐）。
     */
    private static volatile boolean coverVanilla = false;

    /** 模型包贴图（PNG 上传）是否上下翻转。用户反馈"上下反了" → 默认关。 */
    private static volatile boolean flipModelTextureV = false;

    /** 鼠标 Y 轴是否反向（用户反馈"视角方向反了" → 默认反向）。 */
    private static volatile boolean invertMouseY = true;

    /** 自由视角开启时，是否让角色朝向/瞄准跟随 3D 视线（P8 操作）。 */
    private static volatile boolean controlFacing = true;

    /**
     * 是否让我们的 3D 几何使用**游戏自己的世界 3D 相机矩阵**。
     *
     * <p>打开后：模型包的真 3D 物件会精确落在它在 2.5D 里对应的精灵位置上（等同原位替换），
     * 也就不再需要任何地面/精灵 UV 重映射。默认开；取不到矩阵会自动退回我们的相机。
     */
    private static volatile boolean alignVanillaView = true;

    /**
     * 地面 UV 映射模式：
     * <ul>
     *   <li>{@code iso}（默认）：把等距菱形精灵重映射到正方形 —— 菱形四角正好落到方块四角，
     *       不留透明边、也不浪费贴图；</li>
     *   <li>{@code isoflip}：同 {@code iso} 但 V 轴翻转，用来验证纹理 V 方向；</li>
     *   <li>{@code inset}：只取中心 50%（保证不透明，但纹理被放大）；</li>
     *   <li>{@code plain}：整块 UV 直接铺满（会出现菱形透明角）。</li>
     * </ul>
     */
    private static String floorUvMode = "isoflip";

    /** 鼠标灵敏度（弧度/像素）。 */
    private static float mouseSensitivity = 0.0025f;

    /** 模型包目录覆盖（留空 = 自动扫描 Workshop / Zomboid/mods）。 */
    private static String voxelPackDir = "";

    public static boolean overlay() {
        return overlay;
    }

    public static void setOverlay(boolean value) {
        overlay = value;
    }

    public static boolean verbose() {
        return verbose;
    }

    public static boolean reportOnStart() {
        return reportOnStart;
    }

    public static int overlayX() {
        return overlayX;
    }

    public static int overlayY() {
        return overlayY;
    }

    public static int graphBars() {
        return graphBars;
    }

    public static boolean scene3d() {
        return scene3d;
    }

    public static void setScene3d(boolean value) {
        scene3d = value;
    }

    public static int sceneGridRadius() {
        return sceneGridRadius;
    }

    public static float cameraFovDeg() {
        return cameraFovDeg;
    }

    public static float cameraPitchDeg() {
        return cameraPitchDeg;
    }

    public static float cameraEyeHeight() {
        return cameraEyeHeight;
    }

    public static boolean cameraThirdPerson() {
        return cameraThirdPerson;
    }

    public static void setCameraThirdPerson(boolean value) {
        cameraThirdPerson = value;
    }

    public static float cameraDistance() {
        return cameraDistance;
    }

    public static boolean voxel() {
        return voxel;
    }

    public static void setVoxel(boolean value) {
        voxel = value;
    }

    public static int voxelRadius() {
        return voxelRadius;
    }

    public static int voxelBudget() {
        return voxelBudget;
    }

    public static boolean voxelWireframe() {
        return voxelWireframe;
    }

    public static boolean voxelTextured() {
        return voxelTextured;
    }

    public static void setVoxelTextured(boolean value) {
        voxelTextured = value;
    }

    public static boolean voxelModels() {
        return voxelModels;
    }

    public static void setVoxelModels(boolean value) {
        voxelModels = value;
    }

    public static boolean voxelFloor() {
        return voxelFloor;
    }

    public static boolean voxelSky() {
        return voxelSky;
    }

    public static boolean mouseLook() {
        return mouseLook;
    }

    public static boolean entities() {
        return entities;
    }

    public static void setEntities(boolean value) {
        entities = value;
    }

    public static boolean characterModels() {
        return characterModels;
    }

    public static boolean voxelSkipOwn3d() {
        return voxelSkipOwn3d;
    }

    /** 面板用：可开关的选项名列表。 */
    public static String[] optionNames() {
        return new String[] {
            "scene3d", "overlay", "voxel", "voxelFloor", "voxelModels", "voxelSky",
            "voxelWireframe", "voxelTextured", "voxelSkipOwn3d", "entities",
            "characterModels", "mouseLook", "controlFacing", "alignVanillaView", "coverVanilla",
            "flipModelTextureV", "invertMouseY",
        };
    }

    public static boolean option(String name) {
        switch (name) {
            case "scene3d": return scene3d;
            case "overlay": return overlay;
            case "voxel": return voxel;
            case "voxelFloor": return voxelFloor;
            case "voxelModels": return voxelModels;
            case "voxelSky": return voxelSky;
            case "voxelWireframe": return voxelWireframe;
            case "voxelTextured": return voxelTextured;
            case "voxelSkipOwn3d": return voxelSkipOwn3d;
            case "entities": return entities;
            case "characterModels": return characterModels;
            case "mouseLook": return mouseLook;
            case "alignVanillaView": return alignVanillaView;
            case "coverVanilla": return coverVanilla;
            case "controlFacing": return controlFacing;
            case "flipModelTextureV": return flipModelTextureV;
            case "invertMouseY": return invertMouseY;
            default: return false;
        }
    }

    public static boolean setOption(String name, boolean value) {
        switch (name) {
            case "scene3d": scene3d = value; break;
            case "overlay": overlay = value; break;
            case "voxel": voxel = value; break;
            case "voxelFloor": voxelFloor = value; break;
            case "voxelModels": voxelModels = value; break;
            case "voxelSky": voxelSky = value; break;
            case "voxelWireframe": voxelWireframe = value; break;
            case "voxelTextured": voxelTextured = value; break;
            case "voxelSkipOwn3d": voxelSkipOwn3d = value; break;
            case "entities": entities = value; break;
            case "characterModels":
                characterModels = value;
                if (value) {
                    CharacterModels.resetFailure();
                }
                break;
            case "alignVanillaView": alignVanillaView = value; break;
            case "coverVanilla": coverVanilla = value; break;
            case "controlFacing": controlFacing = value; break;
            case "flipModelTextureV": flipModelTextureV = value; break;
            case "invertMouseY": invertMouseY = value; break;
            case "mouseLook":
                mouseLook = value;
                if (!value) {
                    MouseLook.setEnabled(false);
                } else {
                    MouseLook.setEnabled(true);
                }
                break;
            default: return false;
        }
        save(Vp.userFile(Vp.CONFIG_FILE));
        invalidateVoxelMesh();
        return true;
    }

    public static int optionInt(String name) {
        if ("voxelRadius".equals(name)) {
            return voxelRadius;
        }
        return 0;
    }

    public static int addOptionInt(String name, int delta) {
        if ("voxelRadius".equals(name)) {
            voxelRadius = clampInt(voxelRadius + delta, 4, 31);
            save(Vp.userFile(Vp.CONFIG_FILE));
            invalidateVoxelMesh();
        }
        return voxelRadius;
    }

    private static int clampInt(int value, int min, int max) {
        return value < min ? min : (value > max ? max : value);
    }

    public static boolean coverVanilla() {
        return coverVanilla;
    }

    public static boolean controlFacing() {
        return controlFacing;
    }

    public static boolean flipModelTextureV() {
        return flipModelTextureV;
    }

    public static boolean invertMouseY() {
        return invertMouseY;
    }

    public static boolean alignVanillaView() {
        return alignVanillaView;
    }

    public static String floorUvMode() {
        return floorUvMode;
    }

    /**
     * 一键切换"完整 3D（Viewpoint 等价）"：跳过原版世界绘制 + 用我们自己的相机
     * + 打开地面/角色/实体/天空（原版不画了，这些必须由我们补上）。
     */
    public static void applyFull3dPreset() {
        // 覆盖而不是跳过：天空盒整屏不透明盖住原版，其余 3D 叠在上面
        coverVanilla = true;
        voxelSky = true;
        alignVanillaView = false;
        scene3d = true;
        voxel = true;
        voxelFloor = true;
        voxelModels = true;
        voxelTextured = true;
        characterModels = true;
        entities = false;
        controlFacing = true;
        mouseLook = true;
        // "完整的世界"需要更远的几何：16 格太近，放到 24
        if (voxelRadius < 24) {
            voxelRadius = 24;
        }
        voxelBudget = Math.max(voxelBudget, 512);
        save(Vp.userFile(Vp.CONFIG_FILE));
        invalidateVoxelMesh();
        Vp.log("preset applied: 3D world view (opaque 3D covers the vanilla view; nothing patched)");
    }

    /** 一行 dump 全部开关，方便日志排查。 */
    public static String describe() {
        StringBuilder sb = new StringBuilder();
        for (String name : optionNames()) {
            sb.append(name).append('=').append(option(name)).append(' ');
        }
        sb.append("voxelRadius=").append(voxelRadius);
        sb.append(" floorUv=").append(floorUvMode);
        sb.append(" sensitivity=").append(mouseSensitivity);
        return sb.toString();
    }

    public static void setFloorUvMode(String value) {
        floorUvMode = value;
    }

    /** 依次切换 iso → inset → plain，返回新模式。 */
    public static String cycleFloorUvMode() {
        if ("iso".equals(floorUvMode)) {
            floorUvMode = "isoflip";
        } else if ("isoflip".equals(floorUvMode)) {
            floorUvMode = "inset";
        } else if ("inset".equals(floorUvMode)) {
            floorUvMode = "plain";
        } else {
            floorUvMode = "iso";
        }
        save(Vp.userFile(Vp.CONFIG_FILE));
        Vp.log("floor UV mode = " + floorUvMode);
        return floorUvMode;
    }

    /** 切换后让体素网格重建，立刻生效。 */
    public static void invalidateVoxelMesh() {
        VoxelWorld.invalidate();
    }

    public static void setCharacterModels(boolean value) {
        characterModels = value;
    }

    public static void setMouseLook(boolean value) {
        mouseLook = value;
    }

    public static float mouseSensitivity() {
        return mouseSensitivity;
    }

    public static String voxelPackDir() {
        return voxelPackDir;
    }

    public static void setVoxelWireframe(boolean value) {
        voxelWireframe = value;
    }

    /** 读取配置；任何异常都被吞掉并保留默认值。 */
    /**
     * 配置结构版本。旧的配置文件里可能有 {@code voxelSky/voxelFloor=true}
     * 或已废弃的 {@code hideVanillaWorld=true} —— 那些值会让天空盒/地面平板
     * 整屏盖住游戏画面，所以升级到 v2 时强制关掉这两项。
     */
    private static final int CONFIG_VERSION = 6;

    public static void load() {
        File file = Vp.userFile(Vp.CONFIG_FILE);
        if (!file.isFile()) {
            save(file);
            Vp.log("config created: " + file.getAbsolutePath());
            return;
        }
        Properties props = new Properties();
        try (InputStream in = new FileInputStream(file)) {
            props.load(in);
        } catch (IOException e) {
            Vp.error("config read failed, using defaults: " + file, e);
            return;
        }
        // 只记下是否需要迁移；真正的强制覆盖必须放在所有字段加载之后，
        // 否则旧的 voxelSky/voxelFloor=true 会被下面几行的 load 又读回来。
        boolean needsMigration = integer(props, "configVersion", 1) < CONFIG_VERSION;
        overlay = bool(props, "overlay", overlay);
        verbose = bool(props, "verbose", verbose);
        reportOnStart = bool(props, "reportOnStart", reportOnStart);
        overlayX = integer(props, "overlayX", overlayX);
        overlayY = integer(props, "overlayY", overlayY);
        graphBars = Math.max(20, Math.min(240, integer(props, "graphBars", graphBars)));
        scene3d = bool(props, "scene3d", scene3d);
        sceneGridRadius = Math.max(4, Math.min(96, integer(props, "sceneGridRadius", sceneGridRadius)));
        cameraFovDeg = clamp(decimal(props, "cameraFovDeg", cameraFovDeg), 30f, 120f);
        cameraPitchDeg = clamp(decimal(props, "cameraPitchDeg", cameraPitchDeg), -89f, 89f);
        cameraEyeHeight = clamp(decimal(props, "cameraEyeHeight", cameraEyeHeight), 0.1f, 5f);
        cameraThirdPerson = bool(props, "cameraThirdPerson", cameraThirdPerson);
        cameraDistance = clamp(decimal(props, "cameraDistance", cameraDistance), 0.5f, 30f);
        voxel = bool(props, "voxel", voxel);
        voxelRadius = Math.max(4, Math.min(31, integer(props, "voxelRadius", voxelRadius)));
        voxelBudget = Math.max(64, Math.min(4096, integer(props, "voxelBudget", voxelBudget)));
        voxelWireframe = bool(props, "voxelWireframe", voxelWireframe);
        voxelTextured = bool(props, "voxelTextured", voxelTextured);
        voxelModels = bool(props, "voxelModels", voxelModels);
        voxelFloor = bool(props, "voxelFloor", voxelFloor);
        voxelSky = bool(props, "voxelSky", voxelSky);
        mouseLook = bool(props, "mouseLook", mouseLook);
        entities = bool(props, "entities", entities);
        characterModels = bool(props, "characterModels", characterModels);
        voxelSkipOwn3d = bool(props, "voxelSkipOwn3d", voxelSkipOwn3d);
        alignVanillaView = bool(props, "alignVanillaView", alignVanillaView);
        coverVanilla = bool(props, "coverVanilla", coverVanilla);
        controlFacing = bool(props, "controlFacing", controlFacing);
        flipModelTextureV = bool(props, "flipModelTextureV", flipModelTextureV);
        invertMouseY = bool(props, "invertMouseY", invertMouseY);
        floorUvMode = string(props, "floorUvMode", floorUvMode);
        mouseSensitivity = clamp(decimal(props, "mouseSensitivity", mouseSensitivity), 0.0004f, 0.02f);
        voxelPackDir = string(props, "voxelPackDir", voxelPackDir);
        Vp.setVerbose(verbose);
        if (needsMigration) {
            // 迁移策略：
            //   v1（跳过原版渲染时代）→ 天空盒会整屏盖住画面，关掉；
            //   v2 曾把地面也关掉，但需求明确要"用原版地板盖住游戏地面"，所以 v3 强制打开。
            voxelSky = false;
            voxelFloor = true;
            // v4：角色相关全部改为"可选对照"，默认交给原版画：
            // 原版渲染没被跳过，角色本来就有模型和动画，我们重复画只会画歪或盖住它。
            // v5：改用我们自己的相机画角色（ModelCamera 子类 + 矩阵栈替换），
            // 默认打开"我们 3D 视角里的角色/僵尸"。
            // v6：改为"与游戏视图对齐"的架构 —— 我们的 3D 用游戏自己的世界 3D 相机矩阵，
            // 模型包的真 3D 精确落在对应精灵位置（原位替换）。地面/角色/实体方块都交给原版，
            // 因为在对齐视图里它们本来就已经是正确且对齐的。
            alignVanillaView = true;
            voxelFloor = false;
            characterModels = false;
            entities = false;
            save(file);
            Vp.log("config migrated to v" + CONFIG_VERSION
                + ": voxelSky=off, voxelFloor=on (vanilla floor sprites cover the ground),"
                + " characterModels/entities=off (the vanilla renderer already draws characters).");
        }
        Vp.log("config loaded: overlay=" + overlay + " scene3d=" + scene3d
            + " verbose=" + verbose + " reportOnStart=" + reportOnStart);
    }

    private static void save(File file) {
        Properties props = new Properties();
        props.setProperty("configVersion", Integer.toString(CONFIG_VERSION));
        props.setProperty("overlay", Boolean.toString(overlay));
        props.setProperty("verbose", Boolean.toString(verbose));
        props.setProperty("reportOnStart", Boolean.toString(reportOnStart));
        props.setProperty("overlayX", Integer.toString(overlayX));
        props.setProperty("overlayY", Integer.toString(overlayY));
        props.setProperty("graphBars", Integer.toString(graphBars));
        props.setProperty("scene3d", Boolean.toString(scene3d));
        props.setProperty("sceneGridRadius", Integer.toString(sceneGridRadius));
        props.setProperty("cameraFovDeg", Float.toString(cameraFovDeg));
        props.setProperty("cameraPitchDeg", Float.toString(cameraPitchDeg));
        props.setProperty("cameraEyeHeight", Float.toString(cameraEyeHeight));
        props.setProperty("cameraThirdPerson", Boolean.toString(cameraThirdPerson));
        props.setProperty("cameraDistance", Float.toString(cameraDistance));
        props.setProperty("voxel", Boolean.toString(voxel));
        props.setProperty("voxelRadius", Integer.toString(voxelRadius));
        props.setProperty("voxelBudget", Integer.toString(voxelBudget));
        props.setProperty("voxelWireframe", Boolean.toString(voxelWireframe));
        props.setProperty("voxelTextured", Boolean.toString(voxelTextured));
        props.setProperty("voxelModels", Boolean.toString(voxelModels));
        props.setProperty("voxelFloor", Boolean.toString(voxelFloor));
        props.setProperty("voxelSky", Boolean.toString(voxelSky));
        props.setProperty("mouseLook", Boolean.toString(mouseLook));
        props.setProperty("entities", Boolean.toString(entities));
        props.setProperty("characterModels", Boolean.toString(characterModels));
        props.setProperty("voxelSkipOwn3d", Boolean.toString(voxelSkipOwn3d));
        props.setProperty("alignVanillaView", Boolean.toString(alignVanillaView));
        props.setProperty("coverVanilla", Boolean.toString(coverVanilla));
        props.setProperty("controlFacing", Boolean.toString(controlFacing));
        props.setProperty("flipModelTextureV", Boolean.toString(flipModelTextureV));
        props.setProperty("invertMouseY", Boolean.toString(invertMouseY));
        props.setProperty("floorUvMode", floorUvMode);
        props.setProperty("mouseSensitivity", Float.toString(mouseSensitivity));
        props.setProperty("voxelPackDir", voxelPackDir);
        File parent = file.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }
        try (OutputStream out = new FileOutputStream(file)) {
            props.store(out, "ViewpointMac runtime options (edit with the game closed)");
        } catch (IOException e) {
            Vp.error("config write failed: " + file, e);
        }
    }

    private static boolean bool(Properties props, String key, boolean fallback) {
        String raw = props.getProperty(key);
        if (raw == null) {
            return fallback;
        }
        raw = raw.trim().toLowerCase();
        return "true".equals(raw) || "1".equals(raw) || "yes".equals(raw) || "on".equals(raw);
    }

    private static int integer(Properties props, String key, int fallback) {
        try {
            String raw = props.getProperty(key);
            return raw == null ? fallback : Integer.parseInt(raw.trim());
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    private static String string(Properties props, String key, String fallback) {
        String raw = props.getProperty(key);
        return raw == null ? fallback : raw.trim();
    }

    private static float decimal(Properties props, String key, float fallback) {
        try {
            String raw = props.getProperty(key);
            return raw == null ? fallback : Float.parseFloat(raw.trim());
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    private static float clamp(float value, float min, float max) {
        return value < min ? min : (value > max ? max : value);
    }

    private VpConfig() {
    }
}
