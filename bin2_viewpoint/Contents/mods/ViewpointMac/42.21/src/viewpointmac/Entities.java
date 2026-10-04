package viewpointmac;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Iterator;
import java.util.Set;

/**
 * 实体（玩家 / 僵尸 / 其它移动对象）的世界坐标读桥（1.2）。
 *
 * <p>纯 3D 模式跳过了游戏的世界绘制，**角色也一并消失**。这里从
 * {@code IsoWorld.instance.getCell().getObjectList()}（返回所有 {@code IsoMovingObject}）
 * 取出实体位置，让 {@link Scene3D} 用带色方块把它们画出来 —— 先解决"看不见僵尸"这个
 * 最影响可玩性的问题；之后再把方块换成游戏自带的骨骼模型。
 *
 * <p>全部反射，句柄缓存；每帧只做"取集合 + 遍历 + 3 次取坐标"，并自带距离/视锥剔除。
 */
public final class Entities {

    public static final byte KIND_PLAYER = 0;
    public static final byte KIND_ZOMBIE = 1;
    public static final byte KIND_OTHER = 2;

    private static final int MAX_ENTITIES = 256;

    private static final float[] EX = new float[MAX_ENTITIES];
    private static final float[] EY = new float[MAX_ENTITIES];
    private static final float[] EZ = new float[MAX_ENTITIES];
    private static final byte[] EKIND = new byte[MAX_ENTITIES];
    private static final Object[] EOBJ = new Object[MAX_ENTITIES];
    private static final float[] EDIST = new float[MAX_ENTITIES];
    private static int count = 0;

    private static boolean initialized = false;
    private static boolean available = false;
    private static String failReason = "";

    private static Field fWorldInstance;
    private static Method mGetCell;
    private static Method mGetObjectList;
    private static Method mGetX;
    private static Method mGetY;
    private static Method mGetZ;
    private static Class<?> zombieClass;
    private static Class<?> playerClass;

    private static long seen = 0;
    private static long skipped = 0;

    public static boolean available() {
        init();
        return available;
    }

    public static String failReason() {
        return failReason;
    }

    public static int count() {
        return count;
    }

    public static float x(int i) {
        return i >= 0 && i < count ? EX[i] : 0f;
    }

    public static float y(int i) {
        return i >= 0 && i < count ? EY[i] : 0f;
    }

    public static float z(int i) {
        return i >= 0 && i < count ? EZ[i] : 0f;
    }

    /** 实体对象本身（IsoGameCharacter 等），给角色模型探针用。 */
    public static Object object(int i) {
        return i >= 0 && i < count ? EOBJ[i] : null;
    }

    public static byte kind(int i) {
        return i >= 0 && i < count ? EKIND[i] : KIND_OTHER;
    }

    /** 按距离由近到远排序后的结果可以直接顺序绘制（近处优先占额度）。 */
    public static float distance(int i) {
        return i >= 0 && i < count ? EDIST[i] : 0f;
    }

    private static synchronized void init() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            Class<?> world = Class.forName("zombie.iso.IsoWorld");
            fWorldInstance = world.getField("instance");
            mGetCell = world.getMethod("getCell");

            Class<?> cell = Class.forName("zombie.iso.IsoCell");
            mGetObjectList = cell.getMethod("getObjectList");

            Class<?> moving = Class.forName("zombie.iso.IsoMovingObject");
            mGetX = moving.getMethod("getX");
            mGetY = moving.getMethod("getY");
            mGetZ = moving.getMethod("getZ");

            zombieClass = Class.forName("zombie.characters.IsoZombie");
            playerClass = Class.forName("zombie.characters.IsoPlayer");

            available = true;
            Vp.log("entities bridge ready: IsoCell.getObjectList (players + zombies).");
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("entities bridge unavailable: " + failReason);
        }
    }

    /**
     * 刷新实体列表。每帧在渲染线程调用。
     *
     * @param maxDistance 超过这个距离的实体直接忽略
     */
    public static void update(float eyeX, float eyeY, float eyeZ,
                              float forwardX, float forwardY, float forwardZ,
                              float maxDistance) {
        init();
        count = 0;
        // 角色模型也依赖这份列表，所以只要两者之一开着就要扫描
        if (!available || (!VpConfig.entities() && !VpConfig.characterModels())) {
            return;
        }
        try {
            Object world = fWorldInstance.get(null);
            if (world == null) {
                return;
            }
            Object cell = mGetCell.invoke(world);
            if (cell == null) {
                return;
            }
            Object listObject = mGetObjectList.invoke(cell);
            if (!(listObject instanceof Set)) {
                return;
            }
            Set<?> objects = (Set<?>) listObject;
            Iterator<?> iterator = objects.iterator();
            int examined = 0;
            while (iterator.hasNext() && examined < 4000) {
                Object entity = iterator.next();
                examined++;
                if (entity == null) {
                    continue;
                }
                float ex = ((Number) mGetX.invoke(entity)).floatValue();
                float ey = ((Number) mGetY.invoke(entity)).floatValue();
                float ez = ((Number) mGetZ.invoke(entity)).floatValue();

                float dx = ex - eyeX;
                float dy = ey - eyeY;
                float dz = ez - eyeZ;
                float distance = (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
                if (distance > maxDistance) {
                    skipped++;
                    continue;
                }
                seen++;
                // 视锥剔除：相机背后的不要（自己也允许，反正第一人称看不到）
                if (distance > 0.001f) {
                    float dot = (dx * forwardX + dy * forwardY + dz * forwardZ) / distance;
                    if (dot < -0.35f) {
                        skipped++;
                        continue;
                    }
                }
                if (count >= MAX_ENTITIES) {
                    break;
                }
                EX[count] = ex;
                EY[count] = ey;
                EZ[count] = ez;
                EDIST[count] = distance;
                EKIND[count] = classify(entity);
                EOBJ[count] = entity;
                count++;
            }
            sortByDistance();
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("entities disabled: " + failReason);
        }
    }

    private static byte classify(Object entity) {
        if (playerClass != null && playerClass.isInstance(entity)) {
            return KIND_PLAYER;
        }
        if (zombieClass != null && zombieClass.isInstance(entity)) {
            return KIND_ZOMBIE;
        }
        return KIND_OTHER;
    }

    /** 近的排前面：绘制额度有限时优先画近处。 */
    private static void sortByDistance() {
        for (int i = 1; i < count; i++) {
            float value = EDIST[i];
            float x = EX[i];
            float y = EY[i];
            float z = EZ[i];
            byte kind = EKIND[i];
            Object obj = EOBJ[i];
            int j = i - 1;
            while (j >= 0 && EDIST[j] > value) {
                EDIST[j + 1] = EDIST[j];
                EX[j + 1] = EX[j];
                EY[j + 1] = EY[j];
                EZ[j + 1] = EZ[j];
                EKIND[j + 1] = EKIND[j];
                EOBJ[j + 1] = EOBJ[j];
                j--;
            }
            EDIST[j + 1] = value;
            EX[j + 1] = x;
            EY[j + 1] = y;
            EZ[j + 1] = z;
            EKIND[j + 1] = kind;
            EOBJ[j + 1] = obj;
        }
    }

    public static String describe() {
        init();
        if (!available) {
            return "unavailable (" + failReason + ")";
        }
        if (!VpConfig.entities()) {
            return "off";
        }
        return "visible=" + count + "/" + MAX_ENTITIES + " seen=" + seen + " culled=" + skipped;
    }

    private Entities() {
    }
}
