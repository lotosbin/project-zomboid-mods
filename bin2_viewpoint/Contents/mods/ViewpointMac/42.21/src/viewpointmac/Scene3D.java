package viewpointmac;

import java.nio.ByteBuffer;
import java.nio.FloatBuffer;

import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL12;
import org.lwjgl.opengl.GL13;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL20;

/**
 * P1/P2 的 3D 场景：MVP 变换 + 深度缓冲 + 原版精灵贴图。
 *
 * <p>几何分三段绘制：
 * <ol>
 *   <li><b>线段</b>（网格、坐标轴、玩家盒、原点盒、连线）—— 1x1 白贴图 + 顶点色；</li>
 *   <li><b>纯色三角形</b>（原点地板）—— 同样用白贴图；</li>
 *   <li><b>体素材质分桶</b> —— 每个桶绑定一个原版精灵图集贴图，各一次 {@code glDrawArrays}。</li>
 * </ol>
 *
 * <p>顶点格式：x, y, z, u, v, r, g, b, a。
 *
 * <p>深度策略：不清理游戏的深度缓冲，改用 {@code glDepthFunc(GL_ALWAYS)} + 写深度，
 * 使我们的几何永远压过已画好的画面、但彼此之间仍有正确遮挡。
 * 绘制前后成对保存/恢复状态（program / VBO / texture / viewport / depthFunc / depthMask /
 * blend / cull / frontFace / vertex attrib）。
 */
public final class Scene3D {

    /** 顶点格式：x, y, z, u, v, r, g, b, a */
    private static final int FLOATS_PER_VERTEX = 9;
    private static final int MAX_VERTICES = 300000;

    private static final String VERTEX_SHADER_120 =
        "#version 120\n"
        + "attribute vec3 aPos;\n"
        + "attribute vec2 aUv;\n"
        + "attribute vec4 aColor;\n"
        + "uniform mat4 uMvp;\n"
        + "varying vec2 vUv;\n"
        + "varying vec4 vColor;\n"
        + "void main() {\n"
        + "    vUv = aUv;\n"
        + "    vColor = aColor;\n"
        + "    gl_Position = uMvp * vec4(aPos, 1.0);\n"
        + "}\n";

    private static final String FRAGMENT_SHADER_120 =
        "#version 120\n"
        + "uniform sampler2D uTex;\n"
        + "varying vec2 vUv;\n"
        + "varying vec4 vColor;\n"
        + "void main() {\n"
        + "    gl_FragColor = vColor * texture2D(uTex, vUv);\n"
        + "}\n";

    private static final float[] VERTICES = new float[MAX_VERTICES * FLOATS_PER_VERTEX];
    private static int cursor = 0;
    private static int skyVertices = 0;
    private static int lineVertices = 0;
    private static int flatTriangles = 0;
    private static int voxelBaseVertices = 0;
    private static int voxelVertices = 0;

    private static boolean initialized = false;
    private static boolean ready = false;
    private static String error = "";

    private static int program = 0;
    private static int vbo = 0;
    private static int whiteTexture = 0;
    private static int attribPos = -1;
    private static int attribUv = -1;
    private static int attribColor = -1;
    private static int uniformMvp = -1;
    private static int uniformTex = -1;
    private static FloatBuffer uploadBuffer = BufferUtils.createFloatBuffer(8192);

    /** 属性钉在最高几个槽位，避开游戏使用的 0~3 号（macOS 无 core VAO，属性是全局状态）。 */
    /** 单帧最多绘制多少个模型实例（防止模型密集区把帧率拖垮）。 */
    private static final int MAX_MODEL_DRAWS = 320;

    private static final int ATTR_POS = 13;
    private static final int ATTR_UV = 12;
    private static final int ATTR_COLOR = 11;
    private static final GlAttribState ATTRIB_GUARD =
        new GlAttribState(ATTR_POS, ATTR_UV, ATTR_COLOR);

    private static int screenWidth = 0;
    private static int screenHeight = 0;
    private static final int[] previousViewport = new int[4];

    private static int lastLineVertices = 0;
    private static int lastFlatTriangles = 0;
    private static int lastVoxelVertices = 0;
    private static int lastBuckets = 0;

    public static boolean ready() {
        return ready;
    }

    public static String error() {
        return error;
    }

    private static void ensureInit() {
        if (initialized) {
            return;
        }
        initialized = true;
        try {
            int vs = GL20.glCreateShader(GL20.GL_VERTEX_SHADER);
            GL20.glShaderSource(vs, VERTEX_SHADER_120);
            GL20.glCompileShader(vs);
            if (GL20.glGetShaderi(vs, GL20.GL_COMPILE_STATUS) == 0) {
                error = "vertex: " + shorten(GL20.glGetShaderInfoLog(vs));
                GL20.glDeleteShader(vs);
                return;
            }
            int fs = GL20.glCreateShader(GL20.GL_FRAGMENT_SHADER);
            GL20.glShaderSource(fs, FRAGMENT_SHADER_120);
            GL20.glCompileShader(fs);
            if (GL20.glGetShaderi(fs, GL20.GL_COMPILE_STATUS) == 0) {
                error = "fragment: " + shorten(GL20.glGetShaderInfoLog(fs));
                GL20.glDeleteShader(vs);
                GL20.glDeleteShader(fs);
                return;
            }
            program = GL20.glCreateProgram();
            GL20.glAttachShader(program, vs);
            GL20.glAttachShader(program, fs);
            // 必须在 link 之前把属性钉到高位槽位
            GL20.glBindAttribLocation(program, ATTR_POS, "aPos");
            GL20.glBindAttribLocation(program, ATTR_UV, "aUv");
            GL20.glBindAttribLocation(program, ATTR_COLOR, "aColor");
            GL20.glLinkProgram(program);
            GL20.glDeleteShader(vs);
            GL20.glDeleteShader(fs);
            if (GL20.glGetProgrami(program, GL20.GL_LINK_STATUS) == 0) {
                error = "link: " + shorten(GL20.glGetProgramInfoLog(program));
                GL20.glDeleteProgram(program);
                program = 0;
                return;
            }
            attribPos = GL20.glGetAttribLocation(program, "aPos");
            attribUv = GL20.glGetAttribLocation(program, "aUv");
            attribColor = GL20.glGetAttribLocation(program, "aColor");
            uniformMvp = GL20.glGetUniformLocation(program, "uMvp");
            uniformTex = GL20.glGetUniformLocation(program, "uTex");
            vbo = GL15.glGenBuffers();
            whiteTexture = createWhiteTexture();
            boolean bound = attribPos == ATTR_POS && attribUv == ATTR_UV && attribColor == ATTR_COLOR;
            ready = bound && uniformMvp >= 0 && uniformTex >= 0 && vbo != 0 && whiteTexture != 0;
            if (!ready) {
                error = "binding mismatch (aPos=" + attribPos + ", aUv=" + attribUv
                    + ", aColor=" + attribColor + ", uMvp=" + uniformMvp + ", uTex=" + uniformTex + ")";
            }
            Vp.log("3D pipeline: " + (ready
                ? "GLSL 1.20 + MVP + depth + vanilla sprite atlas sampler"
                : "unavailable (" + error + ")"));
        } catch (Throwable t) {
            ready = false;
            error = String.valueOf(t);
            Vp.error("3D pipeline init failed", t);
        }
    }

    /** 1x1 白贴图：让线段与纯色三角形复用同一个着色器。 */
    private static int createWhiteTexture() {
        int texture = GL11.glGenTextures();
        if (texture == 0) {
            return 0;
        }
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, texture);
        ByteBuffer pixel = BufferUtils.createByteBuffer(4);
        pixel.put((byte) 0xFF).put((byte) 0xFF).put((byte) 0xFF).put((byte) 0xFF);
        pixel.flip();
        GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0, GL11.GL_RGBA, 1, 1, 0,
            GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, pixel);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_NEAREST);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_NEAREST);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_S, GL12.GL_CLAMP_TO_EDGE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_T, GL12.GL_CLAMP_TO_EDGE);
        return texture;
    }

    private static String shorten(String value) {
        if (value == null) {
            return "";
        }
        String text = value.trim().replace('\n', ' ');
        return text.length() > 200 ? text.substring(0, 200) : text;
    }

    /**
     * 绘制 3D 场景。必须在渲染线程且 GL 上下文有效时调用。
     *
     * @return 写入的顶点数，0 表示本帧没画
     */
    public static int draw() {
        ensureInit();
        // 光标管理必须最先执行：后面任何提前 return 都不能让它卡在"已隐藏"状态
        MouseLook.update();
        if (!ready || !VpConfig.scene3d()) {
            return 0;
        }
        ModelCache.beginFrame();
        int[] viewport = new int[4];
        GL11.glGetIntegerv(GL11.GL_VIEWPORT, viewport);
        previousViewport[0] = viewport[0];
        previousViewport[1] = viewport[1];
        previousViewport[2] = viewport[2];
        previousViewport[3] = viewport[3];

        // 同 Overlay：显式用整屏尺寸，不沿用渲染线程残留的偏移 viewport
        int[] size = GameScreen.resolve(viewport[2], viewport[3]);
        screenWidth = size[0];
        screenHeight = size[1];
        if (screenWidth <= 0 || screenHeight <= 0) {
            return 0;
        }
        if (!GameWorld.refresh()) {
            return 0;
        }
        SkySource.update();
        if (!Camera.update(screenWidth, screenHeight)) {
            return 0;
        }
        // P8：让角色朝向跟随 3D 视线（自由视角开启时）
        Controls.update(Camera.yaw());
        // 必须在相机更新之后：剔除要用本帧的视点与朝向
        Entities.update(Camera.eye()[0], Camera.eye()[1], Camera.eye()[2],
            Camera.forwardX(), Camera.forwardY(), Camera.forwardZ(),
            VpConfig.voxelRadius() + 12f);

        CharacterModels.prepare(Entities.count());
        buildGeometry();
        int total = cursor;
        if (total == 0) {
            return 0;
        }
        render(total);
        lastLineVertices = lineVertices;
        lastFlatTriangles = flatTriangles;
        lastVoxelVertices = voxelVertices;
        lastBuckets = voxelVertices > 0 ? VoxelWorld.bucketCount() : 0;
        return total;
    }

    // ------------------------------------------------------------------ 几何

    private static void buildGeometry() {
        cursor = 0;
        skyVertices = 0;
        lineVertices = 0;
        flatTriangles = 0;
        voxelBaseVertices = 0;
        voxelVertices = 0;

        // 0) 天空：以相机为中心的大立方体 + 顶点色渐变，最先画，作为背景
        if (VpConfig.voxelSky()) {
            buildSky();
        }
        skyVertices = cursor;

        float px = GameWorld.playerX();
        float py = GameWorld.playerY();
        float pz = GameWorld.playerZ();

        // 推进体素采样（预算式，内部自带缓存与版本控制）
        VoxelWorld.update(px, py, pz);

        // 1) 所有线段
        buildGrid(px, py, pz);
        buildAxes(px, py, pz);
        buildWireBox(px, py, pz, 0.7f, 1.75f, 0.35f, 0.85f, 1.0f, 0.95f);
        buildOriginMarkerBox();
        buildPlayerLine(px, py, pz);
        lineVertices = cursor;

        // 2) 纯色三角形
        buildOriginFloorQuad();
        buildEntityBoxes();
        flatTriangles = cursor - lineVertices;

        // 3) 体素（带原版精灵贴图，VoxelWorld 内部已按材质分桶）
        appendVoxels();
    }

    /**
     * 天空背景：一个以相机为中心的大立方体，天顶偏蓝、地平线偏亮、地面偏灰。
     *
     * <p>先于其它几何绘制，后画的物件自然盖住它。原点版天空贴图（云层）后续再接。
     */
    private static void buildSky() {
        float[] eye = Camera.eye();
        // 必须让整个立方体落在远裁剪面（240）之内，否则面被裁掉会"漏光"。
        // 对角线 = size*sqrt(3)，取 100 → 173 < 240，安全。
        float size = 100f;
        float x0 = eye[0] - size;
        float x1 = eye[0] + size;
        float y0 = eye[1] - size;
        float y1 = eye[1] + size;
        float z0 = eye[2] - size;
        float z1 = eye[2] + size;
        float zTop = Math.min(eye[2] + 1.5f, z1);
        float zMid = eye[2] + 0.15f;

        // 直接用游戏自己的天空颜色（昼夜 / 天气都会跟着变）
        float[] top = {SkySource.highR(), SkySource.highG(), SkySource.highB(), 1f};
        float[] horizon = {SkySource.lowR(), SkySource.lowG(), SkySource.lowB(), 1f};
        float[] bottom = {
            horizon[0] * 0.55f + SkySource.sunR() * 0.10f,
            horizon[1] * 0.55f + SkySource.sunG() * 0.10f,
            horizon[2] * 0.55f + SkySource.sunB() * 0.10f,
            1f,
        };

        // 四个侧面（下→中→上渐变）
        skyQuad(x0, y0, z0, x1, y0, z0, x1, y0, z1, x0, y0, z1, bottom, horizon, top, zMid, zTop);
        skyQuad(x1, y1, z0, x0, y1, z0, x0, y1, z1, x1, y1, z1, bottom, horizon, top, zMid, zTop);
        skyQuad(x0, y1, z0, x0, y0, z0, x0, y0, z1, x0, y1, z1, bottom, horizon, top, zMid, zTop);
        skyQuad(x1, y0, z0, x1, y1, z0, x1, y1, z1, x1, y0, z1, bottom, horizon, top, zMid, zTop);
        // 顶面
        skyQuad(x0, y0, z1, x1, y0, z1, x1, y1, z1, x0, y1, z1, top, top, top, zMid, zTop);
    }

    /** 一条竖直渐变带：底边用 bottom 色、腰线用 horizon、顶边用 top。 */
    private static void skyQuad(float ax, float ay, float az, float bx, float by, float bz,
                                float cx, float cy, float cz, float dx, float dy, float dz,
                                float[] bottom, float[] horizon, float[] top,
                                float zMid, float zTop) {
        float[] a = lift(az, zMid, zTop, bottom, horizon, top);
        float[] b = lift(bz, zMid, zTop, bottom, horizon, top);
        float[] c = lift(cz, zMid, zTop, bottom, horizon, top);
        float[] d = lift(dz, zMid, zTop, bottom, horizon, top);
        push(ax, ay, az, 0.5f, 0.5f, a[0], a[1], a[2], 1f, 1f);
        push(bx, by, bz, 0.5f, 0.5f, b[0], b[1], b[2], 1f, 1f);
        push(cx, cy, cz, 0.5f, 0.5f, c[0], c[1], c[2], 1f, 1f);
        push(ax, ay, az, 0.5f, 0.5f, a[0], a[1], a[2], 1f, 1f);
        push(cx, cy, cz, 0.5f, 0.5f, c[0], c[1], c[2], 1f, 1f);
        push(dx, dy, dz, 0.5f, 0.5f, d[0], d[1], d[2], 1f, 1f);
    }

    private static float[] lift(float z, float zMid, float zTop, float[] bottom, float[] horizon, float[] top) {
        if (z >= zTop) {
            return top;
        }
        if (z >= zMid) {
            float t = (z - zMid) / Math.max(0.0001f, zTop - zMid);
            return new float[] {
                horizon[0] + (top[0] - horizon[0]) * t,
                horizon[1] + (top[1] - horizon[1]) * t,
                horizon[2] + (top[2] - horizon[2]) * t,
            };
        }
        return bottom;
    }

    /** 跟随玩家的地面网格（1 格 = 1 单位），每 8 格加亮一条。 */
    private static void buildGrid(float px, float py, float pz) {
        int radius = VpConfig.sceneGridRadius();
        float z = pz + 0.02f;
        float baseX = (float) Math.floor(px);
        float baseY = (float) Math.floor(py);
        float x0 = baseX - radius;
        float x1 = baseX + radius;
        float y0 = baseY - radius;
        float y1 = baseY + radius;

        for (int i = -radius; i <= radius; i++) {
            float x = baseX + i;
            float y = baseY + i;
            float a = (Math.abs(Math.round(x)) % 8 == 0) ? 0.55f : 0.20f;
            addLine(x, y0, z, x, y1, z, 0.55f, 0.75f, 0.65f, a);
            a = (Math.abs(Math.round(y)) % 8 == 0) ? 0.55f : 0.20f;
            addLine(x0, y, z, x1, y, z, 0.55f, 0.75f, 0.65f, a);
        }
    }

    /** 世界坐标轴：X 红 / Y 绿 / Z 蓝。 */
    private static void buildAxes(float px, float py, float pz) {
        addLine(px, py, pz, px + 4f, py, pz, 0.95f, 0.30f, 0.30f, 1f);
        addLine(px, py, pz, px, py + 4f, pz, 0.35f, 0.95f, 0.40f, 1f);
        addLine(px, py, pz, px, py, pz + 3f, 0.35f, 0.55f, 1.00f, 1f);
    }

    /** 玩家线框盒（脚在 zBase）。 */
    private static void buildWireBox(float cx, float cy, float zBase, float width, float height,
                                     float r, float g, float b, float a) {
        float h = width * 0.5f;
        float x0 = cx - h;
        float x1 = cx + h;
        float y0 = cy - h;
        float y1 = cy + h;
        float z0 = zBase;
        float z1 = zBase + height;

        addLine(x0, y0, z0, x1, y0, z0, r, g, b, a);
        addLine(x1, y0, z0, x1, y1, z0, r, g, b, a);
        addLine(x1, y1, z0, x0, y1, z0, r, g, b, a);
        addLine(x0, y1, z0, x0, y0, z0, r, g, b, a);
        addLine(x0, y0, z1, x1, y0, z1, r, g, b, a);
        addLine(x1, y0, z1, x1, y1, z1, r, g, b, a);
        addLine(x1, y1, z1, x0, y1, z1, r, g, b, a);
        addLine(x0, y1, z1, x0, y0, z1, r, g, b, a);
        addLine(x0, y0, z0, x0, y0, z1, r, g, b, a);
        addLine(x1, y0, z0, x1, y0, z1, r, g, b, a);
        addLine(x1, y1, z0, x1, y1, z1, r, g, b, a);
        addLine(x0, y1, z0, x0, y1, z1, r, g, b, a);
    }

    /** 世界原点 (0,0) 的线框标记：作为"你确实在真实世界里移动"的参照物。 */
    private static void buildOriginMarkerBox() {
        float h = 0.8f;
        float x0 = -h;
        float x1 = h;
        float y0 = -h;
        float y1 = h;
        float z0 = 0f;
        float z1 = 1.6f;
        float r = 0.95f;
        float g = 0.80f;
        float b = 0.25f;
        float a = 0.95f;

        addLine(x0, y0, z0, x1, y0, z0, r, g, b, a);
        addLine(x1, y0, z0, x1, y1, z0, r, g, b, a);
        addLine(x1, y1, z0, x0, y1, z0, r, g, b, a);
        addLine(x0, y1, z0, x0, y0, z0, r, g, b, a);
        addLine(x0, y0, z1, x1, y0, z1, r, g, b, a);
        addLine(x1, y0, z1, x1, y1, z1, r, g, b, a);
        addLine(x1, y1, z1, x0, y1, z1, r, g, b, a);
        addLine(x0, y1, z1, x0, y0, z1, r, g, b, a);
        addLine(x0, y0, z0, x0, y0, z1, r, g, b, a);
        addLine(x1, y0, z0, x1, y0, z1, r, g, b, a);
        addLine(x1, y1, z0, x1, y1, z1, r, g, b, a);
        addLine(x0, y1, z0, x0, y1, z1, r, g, b, a);
    }

    /** 玩家脚下 → 世界原点 的连线，直观看距离。 */
    private static void buildPlayerLine(float px, float py, float pz) {
        addLine(px, py, pz + 0.05f, 0f, 0f, 1.6f, 0.95f, 0.80f, 0.25f, 0.40f);
    }

    /** 原点处的半透明地板方块，提供一个"接地"参照。 */
    private static void buildOriginFloorQuad() {
        float h = 0.8f;
        addQuad(-h, -h, 0f, h, -h, 0f, h, h, 0f, -h, h, 0f, 0.95f, 0.80f, 0.25f, 0.25f);
    }

    /**
     * 实体方块：玩家（青）、僵尸（红）、其它移动对象（黄）。
     *
     * <p>纯 3D 模式下游戏不再画角色，这里先用方块占位 —— 至少能看见僵尸在哪。
     * 后续会换成游戏自带的骨骼模型（{@code ModelManager}）。
     */
    private static void buildEntityBoxes() {
        int count = Entities.count();
        if (count <= 0 || !VpConfig.entities()) {
            return;
        }
        for (int i = 0; i < count && i < 200; i++) {
            // 已经有原版骨骼模型的角色不再画方块
            if (CharacterModels.hasModel(i)) {
                continue;
            }
            byte kind = Entities.kind(i);
            float r;
            float g;
            float b;
            if (kind == Entities.KIND_PLAYER) {
                r = 0.30f;
                g = 0.85f;
                b = 1.00f;
            } else if (kind == Entities.KIND_ZOMBIE) {
                r = 0.92f;
                g = 0.25f;
                b = 0.20f;
            } else {
                r = 0.95f;
                g = 0.85f;
                b = 0.30f;
            }
            // 脚在 z，1.8 高、0.6 见方；僵尸略微前倾的观感靠高度差区分
            float height = kind == Entities.KIND_ZOMBIE ? 1.75f : 1.80f;
            entityBox(Entities.x(i), Entities.y(i), Entities.z(i), 0.6f, height, r, g, b, 0.85f);
        }
    }

    /** 一个带明暗的立方体（6 面，只画 5 面省底面）。 */
    private static void entityBox(float cx, float cy, float zBase, float width, float height,
                                  float r, float g, float b, float a) {
        float h = width * 0.5f;
        float x0 = cx - h;
        float x1 = cx + h;
        float y0 = cy - h;
        float y1 = cy + h;
        float z1 = zBase + height;
        addQuad(x0, y0, z1, x1, y0, z1, x1, y1, z1, x0, y1, z1, r, g, b, a);
        addQuad(x1, y1, zBase, x0, y1, zBase, x0, y1, z1, x1, y1, z1, r * 0.72f, g * 0.72f, b * 0.72f, a);
        addQuad(x0, y1, zBase, x0, y0, zBase, x0, y0, z1, x0, y1, z1, r * 0.62f, g * 0.62f, b * 0.62f, a);
        addQuad(x1, y0, zBase, x1, y1, zBase, x1, y1, z1, x1, y0, z1, r * 0.62f, g * 0.62f, b * 0.62f, a);
        addQuad(x0, y0, zBase, x1, y0, zBase, x1, y0, z1, x0, y0, z1, r * 0.78f, g * 0.78f, b * 0.78f, a);
    }

    /** 把 VoxelWorld 缓存好的体素网格（已按材质分桶）追加到本帧缓冲。 */
    private static void appendVoxels() {
        int floats = VoxelWorld.meshFloats();
        if (floats <= 0) {
            return;
        }
        voxelBaseVertices = cursor;
        float[] mesh = VoxelWorld.mesh();
        int available = VERTICES.length - cursor * FLOATS_PER_VERTEX;
        int copy = Math.min(floats, available);
        copy -= copy % FLOATS_PER_VERTEX;
        if (copy <= 0) {
            voxelBaseVertices = 0;
            return;
        }
        System.arraycopy(mesh, 0, VERTICES, cursor * FLOATS_PER_VERTEX, copy);
        cursor += copy / FLOATS_PER_VERTEX;
        voxelVertices = copy / FLOATS_PER_VERTEX;
    }

    private static void addLine(float x0, float y0, float z0, float x1, float y1, float z1,
                                float r, float g, float b, float a) {
        push(x0, y0, z0, 0.5f, 0.5f, r, g, b, a, 1f);
        push(x1, y1, z1, 0.5f, 0.5f, r, g, b, a, 1f);
    }

    private static void addQuad(float x0, float y0, float z0, float x1, float y1, float z1,
                                float x2, float y2, float z2, float x3, float y3, float z3,
                                float r, float g, float b, float a) {
        push(x0, y0, z0, 0.5f, 0.5f, r, g, b, a, 1f);
        push(x1, y1, z1, 0.5f, 0.5f, r, g, b, a, 1f);
        push(x2, y2, z2, 0.5f, 0.5f, r, g, b, a, 1f);
        push(x0, y0, z0, 0.5f, 0.5f, r, g, b, a, 1f);
        push(x2, y2, z2, 0.5f, 0.5f, r, g, b, a, 1f);
        push(x3, y3, z3, 0.5f, 0.5f, r, g, b, a, 1f);
    }

    private static void push(float x, float y, float z, float u, float v,
                             float r, float g, float b, float a, float shade) {
        int index = cursor * FLOATS_PER_VERTEX;
        if (index + FLOATS_PER_VERTEX > VERTICES.length) {
            return;
        }
        VERTICES[index] = x;
        VERTICES[index + 1] = y;
        VERTICES[index + 2] = z;
        VERTICES[index + 3] = u;
        VERTICES[index + 4] = v;
        VERTICES[index + 5] = r * shade;
        VERTICES[index + 6] = g * shade;
        VERTICES[index + 7] = b * shade;
        VERTICES[index + 8] = a;
        cursor++;
    }

    // ------------------------------------------------------------------ 绘制

    private static void render(int totalVertices) {
        int prevProgram = safeGetInteger(GL20.GL_CURRENT_PROGRAM);
        int prevArrayBuffer = safeGetInteger(GL15.GL_ARRAY_BUFFER_BINDING);
        int prevTexture = safeGetInteger(GL11.GL_TEXTURE_BINDING_2D);
        int prevActiveTexture = safeGetInteger(GL13.GL_ACTIVE_TEXTURE);
        int prevDepthFunc = safeGetInteger(GL11.GL_DEPTH_FUNC);
        int prevBlendSrc = safeGetInteger(GL11.GL_BLEND_SRC);
        int prevBlendDst = safeGetInteger(GL11.GL_BLEND_DST);
        int prevCullMode = safeGetInteger(GL11.GL_CULL_FACE_MODE);
        int prevFrontFace = safeGetInteger(GL11.GL_FRONT_FACE);
        boolean wasDepthTest = GL11.glIsEnabled(GL11.GL_DEPTH_TEST);
        boolean wasBlend = GL11.glIsEnabled(GL11.GL_BLEND);
        boolean wasCull = GL11.glIsEnabled(GL11.GL_CULL_FACE);
        boolean wasScissor = GL11.glIsEnabled(GL11.GL_SCISSOR_TEST);
        boolean wasStencil = GL11.glIsEnabled(GL11.GL_STENCIL_TEST);
        boolean depthMask = GL11.glGetBoolean(GL11.GL_DEPTH_WRITEMASK);

        try {
            GL20.glUseProgram(program);
            GL20.glUniform1i(uniformTex, 0);
            GL20.glUniformMatrix4fv(uniformMvp, false, Camera.mvp());

            GL11.glViewport(0, 0, screenWidth, screenHeight);
            GL11.glEnable(GL11.GL_DEPTH_TEST);
            GL11.glDepthFunc(GL11.GL_ALWAYS);
            GL11.glDepthMask(true);
            // 打开背面剔除：站在体素方块内部时内侧会被剔掉，不会把屏幕糊成一块颜色
            GL11.glEnable(GL11.GL_CULL_FACE);
            GL11.glCullFace(GL11.GL_BACK);
            GL11.glFrontFace(GL11.GL_CCW);
            GL11.glDisable(GL11.GL_SCISSOR_TEST);
            GL11.glDisable(GL11.GL_STENCIL_TEST);
            GL11.glEnable(GL11.GL_BLEND);
            GL11.glBlendFunc(GL11.GL_SRC_ALPHA, GL11.GL_ONE_MINUS_SRC_ALPHA);

            GL13.glActiveTexture(GL13.GL_TEXTURE0);
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, vbo);
            int needed = totalVertices * FLOATS_PER_VERTEX;
            if (uploadBuffer.capacity() < needed) {
                uploadBuffer = BufferUtils.createFloatBuffer(needed * 2);
            }
            uploadBuffer.clear();
            uploadBuffer.put(VERTICES, 0, needed);
            uploadBuffer.flip();
            GL15.glBufferData(GL15.GL_ARRAY_BUFFER, uploadBuffer, GL15.GL_STREAM_DRAW);

            int stride = FLOATS_PER_VERTEX * 4;
            ATTRIB_GUARD.save();
            GL20.glEnableVertexAttribArray(attribPos);
            GL20.glEnableVertexAttribArray(attribUv);
            GL20.glEnableVertexAttribArray(attribColor);
            GL20.glVertexAttribPointer(attribPos, 3, GL11.GL_FLOAT, false, stride, 0L);
            GL20.glVertexAttribPointer(attribUv, 2, GL11.GL_FLOAT, false, stride, 3L * 4L);
            GL20.glVertexAttribPointer(attribColor, 4, GL11.GL_FLOAT, false, stride, 5L * 4L);

            GL11.glBindTexture(GL11.GL_TEXTURE_2D, whiteTexture);
            if (skyVertices > 0) {
                // 天空盒看的是内壁，临时关掉背面剔除
                GL11.glDisable(GL11.GL_CULL_FACE);
                GL11.glDepthMask(false);
                GL11.glDrawArrays(GL11.GL_TRIANGLES, 0, skyVertices);
                GL11.glDepthMask(true);
                GL11.glEnable(GL11.GL_CULL_FACE);
            }
            if (lineVertices > 0) {
                GL11.glDrawArrays(GL11.GL_LINES, skyVertices, lineVertices);
            }
            if (flatTriangles > 0) {
                GL11.glDrawArrays(GL11.GL_TRIANGLES, skyVertices + lineVertices, flatTriangles);
            }
            drawVoxelBuckets();
            drawModels();
            // 最后画原版角色模型：它用的是游戏自己的相机与着色器，
            // 放在最后 + 我们的 finally 状态恢复，能把影响限制在最小范围
            CharacterModels.drawAll();

            ATTRIB_GUARD.restore();
        } finally {
            GL11.glViewport(previousViewport[0], previousViewport[1], previousViewport[2], previousViewport[3]);
            GL20.glUseProgram(prevProgram);
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, prevArrayBuffer);
            GL13.glActiveTexture(prevActiveTexture);
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, prevTexture);
            GL11.glDepthFunc(prevDepthFunc);
            GL11.glDepthMask(depthMask);
            GL11.glBlendFunc(prevBlendSrc, prevBlendDst);
            GL11.glCullFace(prevCullMode);
            GL11.glFrontFace(prevFrontFace);
            toggle(GL11.GL_DEPTH_TEST, wasDepthTest);
            toggle(GL11.GL_BLEND, wasBlend);
            toggle(GL11.GL_CULL_FACE, wasCull);
            toggle(GL11.GL_SCISSOR_TEST, wasScissor);
            toggle(GL11.GL_STENCIL_TEST, wasStencil);
        }
    }

    /** 每个材质桶绑定一次原版精灵贴图各画一次；无贴图的桶用白贴图。 */
    private static void drawVoxelBuckets() {
        if (voxelVertices <= 0) {
            return;
        }
        int mode = VoxelWorld.meshIsLines() ? GL11.GL_LINES : GL11.GL_TRIANGLES;
        int buckets = VoxelWorld.bucketCount();
        for (int i = 0; i < buckets; i++) {
            int count = VoxelWorld.bucketVertices(i);
            int start = VoxelWorld.bucketStart(i);
            if (count <= 0 || start < 0 || start + count > voxelVertices) {
                continue;
            }
            int slot = VoxelWorld.bucketSlot(i);
            int texture = slot >= 0 ? TileTextures.glId(slot) : 0;
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, texture != 0 ? texture : whiteTexture);
            GL11.glDrawArrays(mode, voxelBaseVertices + start, count);
        }
    }

    /**
     * 绘制命中模型包的物件：每个实例换一次 VBO / 贴图 / MVP（模型自身的旋转缩放位移在加载时已烘焙）。
     */
    private static void drawModels() {
        int count = VoxelWorld.modelCount();
        if (count <= 0) {
            return;
        }
        int stride = FLOATS_PER_VERTEX * 4;
        float[] eye = Camera.eye();
        float fx = Camera.forwardX();
        float fy = Camera.forwardY();
        float fz = Camera.forwardZ();
        float maxDistance = VpConfig.voxelRadius() + 6f;
        int drawn = 0;
        for (int i = 0; i < count && drawn < MAX_MODEL_DRAWS; i++) {
            VoxelPack.Bind bind = VoxelWorld.modelBind(i);
            // 视锥剔除：相机背后 / 超出视距的模型直接跳过
            float dx = VoxelWorld.modelX(i) + 0.5f - eye[0];
            float dy = VoxelWorld.modelY(i) + 0.5f - eye[1];
            float dz = VoxelWorld.modelZ(i) - eye[2];
            float distance = (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
            if (distance > maxDistance || distance < 0.0001f) {
                continue;
            }
            float dot = (dx * fx + dy * fy + dz * fz) / distance;
            if (dot < -0.15f) {
                continue;
            }
            ModelCache.Entry entry = ModelCache.get(bind);
            if (entry == null) {
                continue;
            }
            drawn++;
            float[] model = Mat4.translate(VoxelWorld.modelX(i), VoxelWorld.modelY(i), VoxelWorld.modelZ(i));
            GL20.glUniformMatrix4fv(uniformMvp, false, Mat4.multiply(Camera.mvp(), model));
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, entry.vbo);
            GL20.glVertexAttribPointer(attribPos, 3, GL11.GL_FLOAT, false, stride, 0L);
            GL20.glVertexAttribPointer(attribUv, 2, GL11.GL_FLOAT, false, stride, 3L * 4L);
            GL20.glVertexAttribPointer(attribColor, 4, GL11.GL_FLOAT, false, stride, 5L * 4L);
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, entry.texture != 0 ? entry.texture : whiteTexture);
            GL11.glDrawArrays(GL11.GL_TRIANGLES, 0, entry.vertexCount);
        }
        // 把 MVP / VBO / 属性指针交还给批次缓冲，避免影响后续绘制
        GL20.glUniformMatrix4fv(uniformMvp, false, Camera.mvp());
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, vbo);
        GL20.glVertexAttribPointer(attribPos, 3, GL11.GL_FLOAT, false, stride, 0L);
        GL20.glVertexAttribPointer(attribUv, 2, GL11.GL_FLOAT, false, stride, 3L * 4L);
        GL20.glVertexAttribPointer(attribColor, 4, GL11.GL_FLOAT, false, stride, 5L * 4L);
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, whiteTexture);
    }

    private static void toggle(int cap, boolean enabled) {
        if (enabled) {
            GL11.glEnable(cap);
        } else {
            GL11.glDisable(cap);
        }
    }

    private static int safeGetInteger(int pname) {
        try {
            return GL11.glGetInteger(pname);
        } catch (Throwable t) {
            return 0;
        }
    }

    /** 供 Lua / 报告展示。 */
    public static String describe() {
        if (!ready) {
            return "3D pipeline unavailable: " + error;
        }
        return "sky=" + skyVertices + " lines=" + lastLineVertices + " flat=" + lastFlatTriangles
            + " voxel=" + lastVoxelVertices + " buckets=" + lastBuckets
            + " | " + VoxelWorld.describe() + " | " + ModelCache.describe()
            + " | charModels " + CharacterModels.describe()
            + " | controls " + Controls.describe()
            + " | entities " + Entities.describe()
            + " | " + MouseLook.describe() + " | " + Camera.describe();
    }

    private Scene3D() {
    }
}
