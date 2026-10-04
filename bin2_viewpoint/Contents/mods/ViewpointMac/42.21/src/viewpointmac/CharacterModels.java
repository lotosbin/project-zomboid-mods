package viewpointmac;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * 用**原世界自己的骨骼模型与动画**渲染玩家 / 僵尸（1.5）。
 *
 * <h3>为什么这样做才符合"原世界拖底"</h3>
 * 角色模型不是静态网格，而是骨架 + 蒙皮权重 + 每帧姿态；这些**游戏全都算好了**，
 * 就在 {@code ModelManager.getSlot(character).model} 里。我们只需要用游戏自己的绘制入口
 * 把它画出来，模型、动画、贴图、朝向全部来自原世界，一点不用自己造。
 *
 * <h3>绘制链路（已逐条核对字节码）</h3>
 * <pre>
 *   ModelManager.instance.getSlot(IsoGameCharacter)        // 拿角色的模型槽（含动画姿态）
 *   ModelCamera.instance.Begin() / End()                    // 游戏自己的相机（等距），模型因此与背景对齐
 *   TextureDraw.drawModel(TextureDraw, ModelSlot)           // public static：准备这次绘制
 *   TextureDraw.DrawQueued(TextureDraw, ModelSlot)          // public static：立刻发 GL 调用
 * </pre>
 *
 * <p>{@code TextureDraw} 有 public 无参构造，所以我们**自己 new 一个 scratch**，
 * 不去动游戏渲染状态里的 {@code sprite[]/numSprites} —— 否则游戏会在同一个 state 里
 * 再画一遍，出现重影。
 *
 * <p>相机直接用 {@code ModelCamera.instance}（游戏自己设置的等距相机），
 * 这样画出来的角色和游戏背景的投影完全一致 —— 正是"用原世界做拖底"。
 * 任何一步失败都会自动退回方块，并在报告里给出原因。
 *
 * <h3>为什么默认关闭（{@code characterModels=false}）</h3>
 * 我们**没有跳过原版渲染**，所以游戏在这一帧里已经用完整的状态机、正确的相机
 * 把角色画好了。我们这里再画一遍属于**脱离渲染状态机的外部调用**：
 * <ul>
 *   <li>它依赖 {@code ModelCamera.instance} 在 {@code postRender} 末尾仍然是世界相机 ——
 *       如果此时它是别的相机（例如物品/预览用的相机），模型就会画到错误的位置/尺寸；</li>
 *   <li>骨骼模型的着色器、骨骼贴图、矩阵栈都由它改写，游戏下一帧若没有全部重置，
 *       会出现"角色被画歪"这类跨帧污染。</li>
 * </ul>
 * 所以它作为**可选的对照开关**（{@code Ctrl+Alt+K}）保留，默认交给原版画。
 */
public final class CharacterModels {

    private static boolean initialized = false;
    private static boolean available = false;
    private static String failReason = "";

    private static Field fManagerInstance;
    private static Method mGetSlot;
    private static Field fCamInstance;
    private static Method mCameraBegin;
    private static Method mCameraEnd;
    private static Constructor<?> cTorTextureDraw;
    private static Method mDrawModel;
    private static Method mDrawQueued;

    private static Object scratch = null;

    /** 与 {@link Entities} 下标对齐：该实体是否有可画的模型槽。 */
    private static final boolean[] HAS_MODEL = new boolean[512];
    private static final Object[] SLOTS = new Object[512];

    private static int ready = 0;
    private static int drawn = 0;
    private static int failed = 0;
    private static int skipped = 0;
    private static volatile boolean worldPass = false;
    private static volatile boolean ourDraw = false;
    private static String cameraClass = "n/a";
    private static String lastError = "";

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
            Class<?> manager = Class.forName("zombie.core.skinnedmodel.ModelManager");
            fManagerInstance = manager.getField("instance");
            mGetSlot = manager.getMethod("getSlot", Class.forName("zombie.characters.IsoGameCharacter"));

            Class<?> camera = Class.forName("zombie.core.skinnedmodel.ModelCamera");
            fCamInstance = camera.getField("instance");
            mCameraBegin = camera.getMethod("Begin");
            mCameraEnd = camera.getMethod("End");

            Class<?> textureDraw = Class.forName("zombie.core.textures.TextureDraw");
            Class<?> slotClass = Class.forName("zombie.core.skinnedmodel.ModelManager$ModelSlot");
            cTorTextureDraw = textureDraw.getConstructor();
            mDrawModel = textureDraw.getMethod("drawModel", textureDraw, slotClass);
            mDrawQueued = textureDraw.getMethod("DrawQueued", textureDraw, slotClass);

            scratch = cTorTextureDraw.newInstance();
            available = true;
            Vp.log("character models ready: ModelManager.getSlot + TextureDraw.drawModel/DrawQueued"
                + " + ModelCamera.instance (vanilla animation and projection).");
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("character models unavailable, keeping entity boxes: " + failReason);
        }
    }

    /**
     * 每帧在实体列表刷新之后调用：把这些角色的模型槽解析出来。
     *
     * @param entityCount {@link Entities#count()}
     */
    public static void prepare(int entityCount) {
        ready = 0;
        drawn = 0;
        failed = 0;
        skipped = 0;
        if (!available || !VpConfig.characterModels()) {
            return;
        }
        try {
            Object manager = fManagerInstance.get(null);
            if (manager == null) {
                return;
            }
            int limit = Math.min(entityCount, HAS_MODEL.length);
            for (int i = 0; i < limit; i++) {
                HAS_MODEL[i] = false;
                SLOTS[i] = null;
                byte kind = Entities.kind(i);
                if (kind != Entities.KIND_PLAYER && kind != Entities.KIND_ZOMBIE) {
                    continue;
                }
                Object character = Entities.object(i);
                if (character == null) {
                    continue;
                }
                Object slot = mGetSlot.invoke(manager, character);
                if (slot == null) {
                    skipped++;
                    continue;
                }
                HAS_MODEL[i] = true;
                SLOTS[i] = slot;
                ready++;
            }
        } catch (Throwable t) {
            failOnce("prepare", t);
        }
    }

    /** 由 {@code Patch_WorldPassFlag} 维护：当前是否在原版世界绘制阶段。 */
    public static void setWorldPass(boolean value) {
        worldPass = value;
    }

    /**
     * 是否跳过原版的角色模型 GL 绘制。
     *
     * <p>必须同时满足：功能开着、我们的相机装上了、当前在世界阶段、且不是我们自己在画 ——
     * 任何一条不满足都返回 false，原版照常画，绝不会出现"角色消失"。
     */
    public static boolean shouldSkipVanillaDraw() {
        return worldPass && !ourDraw && VpConfig.characterModels()
            && available && VpCamera.installed();
    }

    public static boolean hasModel(int index) {
        return available && VpConfig.characterModels()
            && index >= 0 && index < HAS_MODEL.length && HAS_MODEL[index];
    }

    /**
     * 真正绘制：必须在我们的 GL 状态保存块里、最后一步调用。
     *
     * <p>用游戏自己的 {@code ModelCamera}（等距投影），所以角色和游戏背景严格对齐。
     */
    public static void drawAll() {
        if (!available || !VpConfig.characterModels() || ready == 0) {
            return;
        }
        Object camera = null;
        boolean cameraBegun = false;
        boolean cameraSwapped = false;
        ourDraw = true;
        try {
            // 关键：把我们自己的相机装进 ModelCamera.instance，
            // 这样游戏内部的 CharacterModelCameraBegin() 就会用我们的矩阵，
            // 角色于是出现在**我们**的 3D 视角里，而不是复制原版等距那一份。
            cameraSwapped = VpCamera.install();

            int limit = Math.min(Entities.count(), HAS_MODEL.length);
            for (int i = 0; i < limit; i++) {
                if (!HAS_MODEL[i] || SLOTS[i] == null) {
                    continue;
                }
                if (!cameraBegun) {
                    camera = fCamInstance.get(null);
                    cameraClass = cameraSwapped
                        ? "ViewpointCamera" + "(" + (camera == null ? "null" : camera.getClass().getSimpleName()) + ")"
                        : (camera == null ? "null" : camera.getClass().getSimpleName());
                    if (camera != null) {
                        mCameraBegin.invoke(camera);
                        cameraBegun = true;
                    }
                }
                mDrawModel.invoke(null, scratch, SLOTS[i]);
                mDrawQueued.invoke(null, scratch, SLOTS[i]);
                drawn++;
            }
        } catch (Throwable t) {
            failOnce("draw", t);
        } finally {
            if (cameraBegun && camera != null) {
                try {
                    mCameraEnd.invoke(camera);
                } catch (Throwable ignored) {
                    // 收尾失败不影响游戏
                }
            }
            if (cameraSwapped) {
                VpCamera.restore();
            }
            ourDraw = false;
        }
    }

    private static void failOnce(String stage, Throwable t) {
        // InvocationTargetException 只是外壳，真正的原因在 cause 里 —— 必须打出来
        Throwable cause = t;
        while (cause instanceof java.lang.reflect.InvocationTargetException && cause.getCause() != null) {
            cause = cause.getCause();
        }
        available = false;
        failReason = stage + ": " + cause;
        lastError = failReason;
        failed++;
        Vp.warn("character models disabled at " + stage + ": " + cause);
        if (cause != t) {
            Vp.warn("  (wrapped by " + t.getClass().getName() + ")");
        }
    }

    /** 面板重新打开该功能时清掉失败状态，允许再试。 */
    public static void resetFailure() {
        available = true;
        failReason = "";
        lastError = "";
        failed = 0;
    }

    public static String describe() {
        init();
        if (!available) {
            return "unavailable (" + failReason + ")";
        }
        if (!VpConfig.characterModels()) {
            return "off (entity boxes)";
        }
        return "ready=" + ready + " drawn=" + drawn + " skipped=" + skipped + " failed=" + failed
            + " world=" + worldPass + " camera=" + cameraClass
            + " | " + VpCamera.describe()
            + (lastError.isEmpty() ? "" : " lastError=" + lastError);
    }

    private CharacterModels() {
    }
}
