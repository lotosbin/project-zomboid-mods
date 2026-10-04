package viewpointmac;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * 世界地块读取（P2）：{@code IsoWorld.instance → IsoCell → IsoGridSquare}。
 *
 * <p>和 {@link GameWorld} 一样全走反射：游戏自身的 class 是 Java 25 格式，
 * 本模组用 JDK 17 编译，编译期不引用任何 {@code zombie.*}。反射句柄全部缓存，
 * 每个地块只做 3~4 次 invoke；失败计数到上限就整体停用，绝不影响游戏。
 */
public final class WorldTiles {

    /** 地块类型（高度与配色在 VoxelWorld 里映射）。 */
    public static final byte EMPTY = 0;
    public static final byte WALL = 1;
    public static final byte SOLID = 2;
    public static final byte FENCE_LOW = 3;
    public static final byte FENCE_HIGH = 4;
    public static final byte WINDOW = 5;
    public static final byte DOOR = 6;
    /** 只有地板、不算实心的地块（草地/路面/室内地板）——用于铺带贴图的地面。 */
    public static final byte FLOOR = 7;

    // ---- 逐物件的高度分类（决定兜底盒子多高、什么颜色）----
    public static final byte KIND_FURNITURE = 0;   // 桌椅柜台：0.9
    public static final byte KIND_TREE = 1;        // 树：3.2
    public static final byte KIND_TALL = 2;        // 墙/楼梯/电线杆/玩家建筑：2.7
    public static final byte KIND_DOOR = 3;        // 门：2.1
    public static final byte KIND_WINDOW = 4;      // 窗：1.5
    public static final byte KIND_LOW = 5;         // 矮栅栏 / 灌木：1.0
    public static final byte KIND_FLOOR = 6;       // 地面平板：0.03（只有顶面可见）

    private static final int MAX_ERRORS = 8;

    private static boolean initialized = false;
    private static boolean available = false;
    private static String failReason = "";
    private static int errors = 0;

    private static Field fWorldInstance;
    private static Method mGetCell;
    private static Method mGetGridSquare;
    private static Method mIsSolid;
    private static Method mGetWall;
    private static Method mIsOutside;
    private static Method mGetProperties;
    private static Method mHasPropertyType;
    private static Method mGetFloor;
    private static Method mGetSprite;
    private static Method mSpriteGetName;
    private static Method mGetObjects;
    private static Method mGetSpriteModel;
    /** 精灵名缓存（按对象身份）；对象是每帧新建的，所以上限到了就整体清空。 */
    private static final java.util.IdentityHashMap<Object, String> SPRITE_CACHE =
        new java.util.IdentityHashMap<>();
    private static final int SPRITE_CACHE_LIMIT = 20000;
    private static Object lastObject = null;
    private static Object lastFloorObject = null;
    private static String lastSpriteName = "";
    private static final java.util.Map<String, Object> PROPERTY_TYPES = new java.util.HashMap<>();

    public static boolean available() {
        init();
        return available;
    }

    public static String failReason() {
        return failReason;
    }

    public static int errors() {
        return errors;
    }

    private static synchronized void init() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            Class<?> worldClass = Class.forName("zombie.iso.IsoWorld");
            fWorldInstance = worldClass.getField("instance");
            mGetCell = worldClass.getMethod("getCell");

            Class<?> cellClass = Class.forName("zombie.iso.IsoCell");
            mGetGridSquare = cellClass.getMethod("getGridSquare", int.class, int.class, int.class);

            Class<?> squareClass = Class.forName("zombie.iso.IsoGridSquare");
            mIsSolid = squareClass.getMethod("isSolid");
            mGetWall = squareClass.getMethod("getWall");
            mGetFloor = squareClass.getMethod("getFloor");

            Class<?> objectClass = Class.forName("zombie.iso.IsoObject");
            mGetSprite = objectClass.getMethod("getSprite");
            Class<?> spriteClass = Class.forName("zombie.iso.sprite.IsoSprite");
            mSpriteGetName = spriteClass.getMethod("getName");
            mGetObjects = squareClass.getMethod("getObjects");
            mGetSpriteModel = objectClass.getMethod("getSpriteModel");
            mIsOutside = squareClass.getMethod("isOutside");

            // 瓦片属性：用来区分墙 / 栅栏 / 窗 / 门（B42 的 IsoPropertyType 枚举）
            try {
                Class<?> propertyContainer = Class.forName("zombie.core.properties.PropertyContainer");
                Class<?> propertyType = Class.forName("zombie.core.properties.IsoPropertyType");
                mGetProperties = squareClass.getMethod("getProperties");
                mHasPropertyType = propertyContainer.getMethod("has", propertyType);
                for (String name : new String[] {
                    "FENCE_TYPE_LOW", "FENCE_TYPE_HIGH", "WINDOW_N", "WINDOW_W", "DOOR_N", "DOOR_W"}) {
                    try {
                        PROPERTY_TYPES.put(name, Enum.valueOf(propertyType.asSubclass(Enum.class), name));
                    } catch (Throwable ignored) {
                        // 该版本没有这个属性常量，跳过即可
                    }
                }
            } catch (Throwable t) {
                mGetProperties = null;
                mHasPropertyType = null;
                Vp.warn("tile property classification unavailable: " + t);
            }

            available = true;
            Vp.log("world tiles bridge ready: IsoWorld/IsoCell/IsoGridSquare (reflection); properties="
                + (mHasPropertyType != null) + " (" + PROPERTY_TYPES.size() + " types).");
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("world tiles bridge unavailable: " + failReason);
        }
    }

    /** 当前世界的 IsoCell；取不到返回 null。 */
    public static Object cell() {
        init();
        if (!available) {
            return null;
        }
        try {
            Object world = fWorldInstance.get(null);
            if (world == null) {
                return null;
            }
            Object cell = mGetCell.invoke(world);
            if (cell == null) {
                return null;
            }
            return cell;
        } catch (Throwable t) {
            fail("cell()", t);
            return null;
        }
    }

    /**
     * 取一个地块的类型。
     *
     * @return {@link #EMPTY} / {@link #WALL} / {@link #SOLID}；取不到按空处理
     */
    public static byte type(Object cell, int x, int y, int z) {
        if (!available || cell == null) {
            return EMPTY;
        }
        try {
            Object square = mGetGridSquare.invoke(cell, x, y, z);
            if (square == null) {
                return EMPTY;
            }
            Object wall = mGetWall.invoke(square);
            if (wall != null) {
                remember(wall);
                return classifyWall(wall);
            }
            Object floor = mGetFloor.invoke(square);
            lastFloorObject = floor;
            remember(floor);
            Object solid = mIsSolid.invoke(square);
            if (Boolean.TRUE.equals(solid)) {
                return SOLID;
            }
            // 只有地板的地块：铺一块带贴图的地面，而不是跳过
            return floor != null ? FLOOR : EMPTY;
        } catch (Throwable t) {
            fail("type()", t);
            return EMPTY;
        }
    }

    /** 墙类对象再细分：矮栅栏 / 高栅栏 / 窗 / 门 / 普通墙。 */
    private static byte classifyWall(Object wall) {
        if (mHasPropertyType == null) {
            return WALL;
        }
        if (hasProperty(wall, "FENCE_TYPE_LOW")) {
            return FENCE_LOW;
        }
        if (hasProperty(wall, "FENCE_TYPE_HIGH")) {
            return FENCE_HIGH;
        }
        if (hasProperty(wall, "WINDOW_N") || hasProperty(wall, "WINDOW_W")) {
            return WINDOW;
        }
        if (hasProperty(wall, "DOOR_N") || hasProperty(wall, "DOOR_W")) {
            return DOOR;
        }
        return WALL;
    }

    private static boolean hasProperty(Object isoObject, String propertyName) {
        Object constant = PROPERTY_TYPES.get(propertyName);
        if (constant == null || mGetProperties == null || mHasPropertyType == null) {
            return false;
        }
        try {
            Object container = mGetProperties.invoke(isoObject);
            if (container == null) {
                return false;
            }
            return Boolean.TRUE.equals(mHasPropertyType.invoke(container, constant));
        } catch (Throwable t) {
            return false;
        }
    }

    /** 记住对象与它的精灵名（精灵名是查模型包 bind 表的键）。 */
    private static void remember(Object isoObject) {
        lastObject = isoObject;
        lastSpriteName = "";
        if (isoObject == null || mGetSprite == null || mSpriteGetName == null) {
            return;
        }
        try {
            Object sprite = mGetSprite.invoke(isoObject);
            if (sprite != null) {
                Object name = mSpriteGetName.invoke(sprite);
                if (name instanceof String) {
                    lastSpriteName = (String) name;
                }
            }
        } catch (Throwable ignored) {
            // 拿不到名字就当没有模型
        }
    }

    /** 按对象身份缓存精灵名，避免同一物件重复反射。 */
    public static String spriteNameOf(Object isoObject) {
        if (isoObject == null || mGetSprite == null || mSpriteGetName == null) {
            return "";
        }
        String cached = SPRITE_CACHE.get(isoObject);
        if (cached != null) {
            return cached;
        }
        String name = "";
        try {
            Object sprite = mGetSprite.invoke(isoObject);
            if (sprite != null) {
                Object value = mSpriteGetName.invoke(sprite);
                if (value instanceof String) {
                    name = (String) value;
                }
            }
        } catch (Throwable ignored) {
            // 拿不到就当没有名字
        }
        if (SPRITE_CACHE.size() >= SPRITE_CACHE_LIMIT) {
            SPRITE_CACHE.clear();
        }
        SPRITE_CACHE.put(isoObject, name);
        return name;
    }

    /**
     * 收集一格上的**所有物件对象**（含 {@code getObjects()} 与单独的 {@code getWall()}）。
     *
     * <p>{@code getWall()} 只给一面墙，而且墙对象不一定出现在 {@code getObjects()} 里，
     * 所以这里两者合并（按身份去重）。
     *
     * @param out 复用的输出数组
     * @return 写入的对象个数
     */
    public static int collectObjects(Object cell, int x, int y, int z, Object[] out, int max) {
        init();
        if (!available || cell == null || mGetObjects == null) {
            return 0;
        }
        int count = 0;
        try {
            Object square = mGetGridSquare.invoke(cell, x, y, z);
            if (square == null) {
                return 0;
            }
            Object listObject = mGetObjects.invoke(square);
            if (listObject instanceof java.util.List) {
                java.util.List<?> list = (java.util.List<?>) listObject;
                int size = Math.min(list.size(), max);
                for (int i = 0; i < size; i++) {
                    Object object = list.get(i);
                    if (object != null) {
                        out[count++] = object;
                    }
                }
            }
            // 墙对象单独补上（可能不在 getObjects 里）
            if (count < max) {
                Object wall = mGetWall.invoke(square);
                if (wall != null) {
                    boolean already = false;
                    for (int i = 0; i < count; i++) {
                        if (out[i] == wall) {
                            already = true;
                            break;
                        }
                    }
                    if (!already) {
                        out[count++] = wall;
                    }
                }
            }
        } catch (Throwable t) {
            fail("collectObjects()", t);
        }
        return count;
    }

    /**
     * 物件的高度分类：只按类名判断，避免逐物件读脚本属性（贵）。
     * 分类结果决定兜底盒子的高度与配色。
     */
    public static byte heightClassOf(Object isoObject) {
        if (isoObject == null) {
            return KIND_FURNITURE;
        }
        // 先看**精灵名**：PZ 的物件分类主要靠 sprite 名（f_bushes / jumbo_tree / tree…），
        // 类名对树/灌木几乎没区分度（日志里 tree=8 / furniture=4315 就是这个原因）。
        byte bySprite = heightClassOfSprite(spriteNameOf(isoObject));
        if (bySprite != KIND_FURNITURE) {
            return bySprite;
        }
        String name = isoObject.getClass().getName();
        if (name.contains("Tree")) {
            return KIND_TREE;
        }
        if (name.contains("Bush") || name.contains("Plant") || name.contains("Fern")
            || name.contains("Grass") || name.contains("Vine")) {
            return KIND_LOW;
        }
        if (name.contains("Window")) {
            return KIND_WINDOW;
        }
        if (name.contains("Door") || name.contains("Curtain") || name.contains("Gate")) {
            return KIND_DOOR;
        }
        if (name.contains("Stairs") || name.contains("Thumpable") || name.contains("Wall")
            || name.contains("Fence") || name.contains("Pole") || name.contains("Pylon")
            || name.contains("Tower") || name.contains("Sign") || name.contains("Light")
            || name.contains("Pillar") || name.contains("Column")) {
            return KIND_TALL;
        }
        return KIND_FURNITURE;
    }

    /** 按精灵名判高度分类（返回 KIND_FURNITURE 表示"没判断出来"）。 */
    private static byte heightClassOfSprite(String sprite) {
        if (sprite == null || sprite.isEmpty()) {
            return KIND_FURNITURE;
        }
        String s = sprite.toLowerCase(java.util.Locale.ROOT);
        if (s.contains("jumbo") || s.contains("tree") || s.contains("pine") || s.contains("birch")) {
            return KIND_TREE;
        }
        if (s.contains("bush") || s.contains("hedge") || s.contains("shrub")
            || s.contains("plant") || s.contains("fern") || s.contains("flower")) {
            return KIND_LOW;
        }
        if (s.contains("window")) {
            return KIND_WINDOW;
        }
        if (s.contains("door") || s.contains("gate")) {
            return KIND_DOOR;
        }
        if (s.contains("wall") || s.contains("fence") || s.contains("pylon")
            || s.contains("pole") || s.contains("tower") || s.contains("sign")
            || s.contains("stairs") || s.contains("pillar") || s.contains("column")) {
            return KIND_TALL;
        }
        return KIND_FURNITURE;
    }

    /**
     * 该物件是否**原版自己就会用 3D 模型画**（{@code IsoObject.getSpriteModel() != null}）。
     *
     * <p>载具、部分道具在游戏里本来就是真 3D 渲染的。我们的 3D 是叠加层，
     * 这些物件交给原世界那套就好 —— 再画一个盒子反而会盖住它。
     */
    public static boolean hasSpriteModel(Object isoObject) {
        init();
        if (!available || isoObject == null || mGetSpriteModel == null) {
            return false;
        }
        try {
            return mGetSpriteModel.invoke(isoObject) != null;
        } catch (Throwable t) {
            return false;
        }
    }

    /**
     * 收集一格上**所有物件**的精灵名（双向墙、家具、装饰、树…），供模型包查 bind。
     *
     * <p>这是"处理所有物品"的关键：{@code getWall()} 只给一面墙，
     * 而一格上可能同时有北墙、西墙和家具；这里遍历 {@code getObjects()}。
     *
     * @param out 复用的输出数组，避免每格分配
     * @return 写入的名字个数
     */
    public static int collectObjectSprites(Object cell, int x, int y, int z, String[] out, int max) {
        init();
        if (!available || cell == null || mGetObjects == null) {
            return 0;
        }
        try {
            Object square = mGetGridSquare.invoke(cell, x, y, z);
            if (square == null) {
                return 0;
            }
            Object listObject = mGetObjects.invoke(square);
            if (!(listObject instanceof java.util.List)) {
                return 0;
            }
            java.util.List<?> list = (java.util.List<?>) listObject;
            int count = 0;
            int size = Math.min(list.size(), max);
            for (int i = 0; i < size; i++) {
                String name = spriteNameOf(list.get(i));
                if (!name.isEmpty()) {
                    out[count++] = name;
                }
            }
            return count;
        } catch (Throwable t) {
            fail("collectObjectSprites()", t);
            return 0;
        }
    }

    /** 上一次分类到的**地板对象**（地面平板取它的贴图）。 */
    public static Object lastFloorObject() {
        return lastFloorObject;
    }

    /** 上一次分类到的对象的精灵名（用于查 PZ Voxel Studio 的 bind 表）。 */
    public static String lastSpriteName() {
        return lastSpriteName;
    }

    /**
     * 上一次 {@link #type} 分类到的游戏对象（有墙取墙，否则取地板）。
     * 只用于取精灵贴图，省掉一次 {@code getGridSquare} 反射；只在渲染线程使用。
     */
    public static Object lastObject() {
        return lastObject;
    }

    /** 该地块是否在室外（给体素上不同颜色用）。 */
    public static boolean isOutside(Object cell, int x, int y, int z) {
        if (!available || cell == null) {
            return true;
        }
        try {
            Object square = mGetGridSquare.invoke(cell, x, y, z);
            if (square == null) {
                return true;
            }
            Object outside = mIsOutside.invoke(square);
            return !Boolean.FALSE.equals(outside);
        } catch (Throwable t) {
            fail("isOutside()", t);
            return true;
        }
    }

    private static synchronized void fail(String where, Throwable t) {
        errors++;
        if (errors <= 3 || errors % 64 == 0) {
            Vp.error("world tiles error (" + where + ", #" + errors + ")", t);
        }
        if (errors >= MAX_ERRORS) {
            available = false;
            failReason = "disabled after " + errors + " errors: " + t;
            Vp.error("world tiles bridge disabled; voxel world stays off.", null);
        }
    }

    public static String describe() {
        init();
        return available ? "ready" : ("unavailable (" + failReason + ")");
    }

    private WorldTiles() {
    }
}
