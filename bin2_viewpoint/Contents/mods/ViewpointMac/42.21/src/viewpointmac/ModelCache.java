package viewpointmac;

import java.awt.image.BufferedImage;
import java.io.File;
import java.nio.ByteBuffer;
import java.util.LinkedHashMap;
import java.util.Map;

import javax.imageio.ImageIO;

import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL12;
import org.lwjgl.opengl.GL15;

/**
 * P3.1：模型与贴图的 GL 缓存（LRU）。
 *
 * <p>10,109 个模型不可能全部常驻显存，所以：
 * <ul>
 *   <li>只在模型真正进入视野时才加载（解析 OBJ + 读 PNG 上传）；</li>
 *   <li>每帧限制加载数量（{@link #beginFrame()}），避免集中读盘造成卡顿；</li>
 *   <li>LRU 上限 {@link #MAX_ENTRIES}，超出就释放最久未用的 VBO/贴图。</li>
 * </ul>
 *
 * <p>顶点格式与 {@link Scene3D} 完全一致（x, y, z, u, v, r, g, b, a），
 * 因此模型绘制可以复用同一套属性指针与着色器。
 */
public final class ModelCache {

    /** 常驻上限（每个条目含一个 VBO + 一张小贴图）。 */
    private static final int MAX_ENTRIES = 1024;

    /** 每帧最多加载几个模型。 */
    private static final int LOADS_PER_FRAME = 16;

    /** 一个已上传到 GL 的模型。 */
    public static final class Entry {
        public final int vbo;
        public final int vertexCount;
        public final int texture;
        public final String key;

        Entry(int vbo, int vertexCount, int texture, String key) {
            this.vbo = vbo;
            this.vertexCount = vertexCount;
            this.texture = texture;
            this.key = key;
        }
    }

    private static final LinkedHashMap<String, Entry> CACHE =
        new LinkedHashMap<String, Entry>(64, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<String, Entry> eldest) {
                if (size() > MAX_ENTRIES) {
                    release(eldest.getValue());
                    evictions++;
                    return true;
                }
                return false;
            }
        };

    private static int loadsThisFrame = 0;
    private static int evictions = 0;
    private static int loadsTotal = 0;
    private static int failures = 0;
    private static int deferred = 0;

    /** 每帧在渲染线程开头调用，重置加载预算。 */
    public static void beginFrame() {
        loadsThisFrame = 0;
    }

    /**
     * 取一个模型；不在缓存里就尝试加载。
     *
     * @return null 表示本帧预算用完或加载失败（调用方应跳过，不要每帧重试爆量）
     */
    public static Entry get(VoxelPack.Bind bind) {
        if (bind == null) {
            return null;
        }
        Entry cached = CACHE.get(bind.cacheKey);
        if (cached != null) {
            return cached;
        }
        if (loadsThisFrame >= LOADS_PER_FRAME) {
            deferred++;
            return null;
        }
        loadsThisFrame++;
        Entry loaded = load(bind);
        if (loaded == null) {
            failures++;
            return null;
        }
        CACHE.put(bind.cacheKey, loaded);
        loadsTotal++;
        return loaded;
    }

    private static Entry load(VoxelPack.Bind bind) {
        try {
            ObjMesh mesh = ObjMesh.load(new File(bind.modelPath), bind);
            if (mesh == null || mesh.vertexCount == 0) {
                return null;
            }
            int vbo = GL15.glGenBuffers();
            if (vbo == 0) {
                return null;
            }
            ByteBuffer buffer = BufferUtils.createByteBuffer(mesh.vertices.length * 4);
            for (float value : mesh.vertices) {
                buffer.putFloat(value);
            }
            buffer.flip();
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, vbo);
            GL15.glBufferData(GL15.GL_ARRAY_BUFFER, buffer, GL15.GL_STATIC_DRAW);
            int texture = uploadTexture(mesh.texturePath);
            return new Entry(vbo, mesh.vertexCount, texture, bind.cacheKey);
        } catch (Throwable t) {
            Vp.warn("model load failed: " + bind.modelPath + " (" + t + ")");
            return null;
        }
    }

    /** 读 PNG 上传成 GL 贴图；失败返回 0（调用方用白贴图）。 */
    private static int uploadTexture(String path) {
        if (path == null) {
            return 0;
        }
        try {
            BufferedImage image = ImageIO.read(new File(path));
            if (image == null) {
                return 0;
            }
            int width = image.getWidth();
            int height = image.getHeight();
            int[] pixels = image.getRGB(0, 0, width, height, null, 0, width);
            ByteBuffer buffer = BufferUtils.createByteBuffer(width * height * 4);
            // ImageIO 首行是顶部，GL 纹理原点在左下。是否翻转由配置决定 ——
            // 不同来源的 OBJ/PNG 约定不同，用户实测"上下反了"就切一下。
            boolean flip = VpConfig.flipModelTextureV();
            for (int row = 0; row < height; row++) {
                int y = flip ? (height - 1 - row) : row;
                for (int x = 0; x < width; x++) {
                    int argb = pixels[y * width + x];
                    buffer.put((byte) ((argb >> 16) & 0xFF));
                    buffer.put((byte) ((argb >> 8) & 0xFF));
                    buffer.put((byte) (argb & 0xFF));
                    buffer.put((byte) ((argb >>> 24) & 0xFF));
                }
            }
            buffer.flip();
            int texture = GL11.glGenTextures();
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, texture);
            GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0, GL11.GL_RGBA, width, height, 0,
                GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, buffer);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_LINEAR);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_LINEAR);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_S, GL12.GL_CLAMP_TO_EDGE);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_T, GL12.GL_CLAMP_TO_EDGE);
            return texture;
        } catch (Throwable t) {
            return 0;
        }
    }

    private static void release(Entry entry) {
        try {
            if (entry.vbo != 0) {
                GL15.glDeleteBuffers(entry.vbo);
            }
            if (entry.texture != 0) {
                GL11.glDeleteTextures(entry.texture);
            }
        } catch (Throwable ignored) {
            // 释放失败不该影响游戏
        }
    }

    public static String describe() {
        return "models=" + CACHE.size() + "/" + MAX_ENTRIES + " loaded=" + loadsTotal
            + " evicted=" + evictions + " failed=" + failures + " deferred=" + deferred;
    }

    private ModelCache() {
    }
}
