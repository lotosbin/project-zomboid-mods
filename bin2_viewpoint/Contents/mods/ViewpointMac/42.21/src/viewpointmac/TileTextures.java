package viewpointmac;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Map;

/**
 * P2.4：把原版精灵图集当作体素的材质来源。
 *
 * <p>重要事实：**原版 Project Zomboid 的物件美术是 2D 等距精灵**（图集里的菱形地板、
 * 立面墙贴图），不是 3D 模型；原版只有角色与载具是真 3D（`.x` / `.fbx`）。
 * 所以"用原版材质"的正确做法是：拿 {@code IsoSprite.texture} 对应的 GL 贴图 +
 * 它在图集里的 UV 矩形，把精灵贴到我们自己的体素盒子上。
 *
 * <p>反射链路：
 * <pre>
 *   IsoObject.getSprite()            → IsoSprite
 *   IsoSprite.texture (public field) → Texture
 *   Texture.getTextureId().getID()   → GL 贴图名
 *   Texture.getXStart()/getYStart()/getXEnd()/getYEnd() → 图集内 UV 矩形
 * </pre>
 *
 * <p>每次重建网格前 {@link #reset()} 清空槽位表；解析失败一律返回 -1，
 * 调用方回退成纯色（用 1x1 白贴图），保证任何情况下都不会画错。
 */
public final class TileTextures {

    /** 单次重建最多缓存多少种不同贴图（避免频繁切换 GL 纹理状态）。 */
    public static final int MAX_SLOTS = 512;

    private static final int[] GL_ID = new int[MAX_SLOTS];
    private static final float[] U0 = new float[MAX_SLOTS];
    private static final float[] V0 = new float[MAX_SLOTS];
    private static final float[] U1 = new float[MAX_SLOTS];
    private static final float[] V1 = new float[MAX_SLOTS];
    private static final int[] TEX_W = new int[MAX_SLOTS];
    private static final int[] TEX_H = new int[MAX_SLOTS];
    private static final int[] TEX_HW = new int[MAX_SLOTS * 2];
    private static final float[] RAW = new float[MAX_SLOTS * 4];
    private static final Map<String, Integer> LOOKUP = new HashMap<>();
    private static int slotCount = 0;
    private static boolean overflow = false;

    private static boolean initialized = false;
    private static boolean available = false;
    private static String failReason = "";

    private static Method mGetSprite;
    private static Field fSpriteTexture;
    private static Method mGetTextureId;
    private static Method mGetId;
    private static Method mGetXStart;
    private static Method mGetYStart;
    private static Method mGetXEnd;
    private static Method mGetYEnd;
    private static Method mGetWidth;
    private static Method mGetHeight;
    private static Method mGetWidthHw;
    private static Method mGetHeightHw;

    private static long requests = 0;
    private static long misses = 0;
    private static int pixelRectCount = 0;
    private static int normalizedRectCount = 0;

    private static synchronized void init() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            Class<?> objectClass = Class.forName("zombie.iso.IsoObject");
            mGetSprite = objectClass.getMethod("getSprite");

            Class<?> spriteClass = Class.forName("zombie.iso.sprite.IsoSprite");
            fSpriteTexture = spriteClass.getField("texture");

            Class<?> textureClass = Class.forName("zombie.core.textures.Texture");
            mGetTextureId = textureClass.getMethod("getTextureId");
            mGetXStart = textureClass.getMethod("getXStart");
            mGetYStart = textureClass.getMethod("getYStart");
            mGetXEnd = textureClass.getMethod("getXEnd");
            mGetYEnd = textureClass.getMethod("getYEnd");
            mGetWidth = textureClass.getMethod("getWidth");
            mGetHeight = textureClass.getMethod("getHeight");
            mGetWidthHw = textureClass.getMethod("getWidthHW");
            mGetHeightHw = textureClass.getMethod("getHeightHW");

            Class<?> textureIdClass = Class.forName("zombie.core.textures.TextureID");
            mGetId = textureIdClass.getMethod("getID");

            available = true;
            Vp.log("tile textures bridge ready: IsoSprite.texture + Texture UV rect (reflection).");
        } catch (Throwable t) {
            available = false;
            failReason = String.valueOf(t);
            Vp.warn("tile textures bridge unavailable: " + failReason);
        }
    }

    public static boolean available() {
        init();
        return available;
    }

    /** 每次重建体素网格前调用。 */
    public static void reset() {
        slotCount = 0;
        overflow = false;
        LOOKUP.clear();
        requests = 0;
        misses = 0;
    }

    public static int slotCount() {
        return slotCount;
    }

    public static int glId(int slot) {
        return slot >= 0 && slot < slotCount ? GL_ID[slot] : 0;
    }

    public static float u0(int slot) {
        return slot >= 0 && slot < slotCount ? U0[slot] : 0.5f;
    }

    public static float v0(int slot) {
        return slot >= 0 && slot < slotCount ? V0[slot] : 0.5f;
    }

    public static float u1(int slot) {
        return slot >= 0 && slot < slotCount ? U1[slot] : 0.5f;
    }

    public static float v1(int slot) {
        return slot >= 0 && slot < slotCount ? V1[slot] : 0.5f;
    }

    /**
     * 解析一个游戏对象用到的精灵贴图。
     *
     * @return 槽位下标；-1 表示没有可用贴图（调用方用纯色）
     */
    public static int slotFor(Object isoObject) {
        init();
        if (!available || !VpConfig.voxelTextured() || isoObject == null) {
            return -1;
        }
        requests++;
        try {
            Object sprite = mGetSprite.invoke(isoObject);
            if (sprite == null) {
                misses++;
                return -1;
            }
            Object texture = fSpriteTexture.get(sprite);
            if (texture == null) {
                misses++;
                return -1;
            }
            Object textureId = mGetTextureId.invoke(texture);
            if (textureId == null) {
                misses++;
                return -1;
            }
            int glId = ((Number) mGetId.invoke(textureId)).intValue();
            if (glId <= 0) {
                misses++;
                return -1;
            }
            float u0 = ((Number) mGetXStart.invoke(texture)).floatValue();
            float v0 = ((Number) mGetYStart.invoke(texture)).floatValue();
            float u1 = ((Number) mGetXEnd.invoke(texture)).floatValue();
            float v1 = ((Number) mGetYEnd.invoke(texture)).floatValue();
            float rawU0 = u0;
            float rawV0 = v0;
            float rawU1 = u1;
            float rawV1 = v1;

            // getXStart()/getYEnd() 返回的可能是**像素坐标**而不是归一化 UV。
            // 判断依据：归一化 UV 永远落在 [0,1]，一旦出现 > 1.5 就必然是像素。
            // 之前没做这一步，导致 UV 越界 → GL_REPEAT 平铺 → 地面出现"跨十几格的大菱形"。
            if (u0 > 1.5f || u1 > 1.5f || v0 > 1.5f || v1 > 1.5f) {
                // 像素坐标要除以**图集硬件尺寸**（getWidthHW），不是精灵尺寸（getWidth）
                int width = texWidthHw(texture);
                int height = texHeightHw(texture);
                if (width <= 0) {
                    width = texWidth(texture);
                }
                if (height <= 0) {
                    height = texHeight(texture);
                }
                if (width > 0) {
                    u0 /= width;
                    u1 /= width;
                }
                if (height > 0) {
                    v0 /= height;
                    v1 /= height;
                }
                pixelRectCount++;
                if (pixelRectCount == 1) {
                    Vp.log("tile texture UV: rects look like PIXEL coords, normalized by texture size"
                        + " (" + width + "x" + height + ").");
                }
            } else {
                normalizedRectCount++;
            }
            // 防御：上下界反了就交换
            if (u1 < u0) {
                float t = u0;
                u0 = u1;
                u1 = t;
            }
            if (v1 < v0) {
                float t = v0;
                v0 = v1;
                v1 = t;
            }

            String key = glId + ":" + Math.round(u0 * 8192f) + ":" + Math.round(v0 * 8192f)
                + ":" + Math.round(u1 * 8192f) + ":" + Math.round(v1 * 8192f);
            Integer existing = LOOKUP.get(key);
            if (existing != null) {
                return existing;
            }
            if (slotCount >= MAX_SLOTS) {
                overflow = true;
                return -1;
            }
            int slot = slotCount++;
            GL_ID[slot] = glId;
            RAW[slot * 4] = rawU0;
            RAW[slot * 4 + 1] = rawV0;
            RAW[slot * 4 + 2] = rawU1;
            RAW[slot * 4 + 3] = rawV1;
            TEX_HW[slot * 2] = texWidthHw(texture);
            TEX_HW[slot * 2 + 1] = texHeightHw(texture);
            try {
                TEX_W[slot] = ((Number) mGetWidth.invoke(texture)).intValue();
                TEX_H[slot] = ((Number) mGetHeight.invoke(texture)).intValue();
            } catch (Throwable ignored) {
                TEX_W[slot] = 0;
                TEX_H[slot] = 0;
            }
            U0[slot] = u0;
            V0[slot] = v0;
            U1[slot] = u1;
            V1[slot] = v1;
            LOOKUP.put(key, slot);
            return slot;
        } catch (Throwable t) {
            misses++;
            return -1;
        }
    }

    /** 单个槽位的贴图与 UV 矩形，用于诊断"UV 是否归一化"。 */
    public static String describeSlot(int slot) {
        if (slot < 0 || slot >= slotCount) {
            return "slot" + slot + "=none";
        }
        return String.format(java.util.Locale.ROOT,
            "slot%d gl=%d sprite=%dx%d atlas=%dx%d raw=(%.3f,%.3f)-(%.3f,%.3f)"
                + " -> uv=(%.5f,%.5f)-(%.5f,%.5f)",
            slot, GL_ID[slot], TEX_W[slot], TEX_H[slot],
            TEX_HW[slot * 2], TEX_HW[slot * 2 + 1],
            RAW[slot * 4], RAW[slot * 4 + 1], RAW[slot * 4 + 2], RAW[slot * 4 + 3],
            U0[slot], V0[slot], U1[slot], V1[slot]);
    }

    private static int texWidth(Object texture) {
        if (mGetWidth == null) {
            return 0;
        }
        try {
            return ((Number) mGetWidth.invoke(texture)).intValue();
        } catch (Throwable t) {
            return 0;
        }
    }

    private static int texWidthHw(Object texture) {
        if (mGetWidthHw == null) {
            return 0;
        }
        try {
            return ((Number) mGetWidthHw.invoke(texture)).intValue();
        } catch (Throwable t) {
            return 0;
        }
    }

    private static int texHeightHw(Object texture) {
        if (mGetHeightHw == null) {
            return 0;
        }
        try {
            return ((Number) mGetHeightHw.invoke(texture)).intValue();
        } catch (Throwable t) {
            return 0;
        }
    }

    private static int texHeight(Object texture) {
        if (mGetHeight == null) {
            return 0;
        }
        try {
            return ((Number) mGetHeight.invoke(texture)).intValue();
        } catch (Throwable t) {
            return 0;
        }
    }

    public static String describe() {
        init();
        if (!VpConfig.voxelTextured()) {
            return "textures off";
        }
        if (!available) {
            return "textures unavailable (" + failReason + ")";
        }
        return "slots=" + slotCount + "/" + MAX_SLOTS + " resolved=" + (requests - misses)
            + " missed=" + misses
            + " uv=" + (pixelRectCount > 0 ? "pixel(" + pixelRectCount + ")" : "normalized")
            + (overflow ? " [slot budget reached]" : "");
    }

    private TileTextures() {
    }
}
