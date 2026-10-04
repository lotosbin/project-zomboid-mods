package viewpointmac;

import java.nio.FloatBuffer;

import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL13;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL20;

/**
 * GL 覆盖层：在游戏渲染线程的帧末尾叠加一块自绘面板。
 *
 * <p>这是 P0 的核心证明件——"我们能挂进游戏的 render pass 并用自己的 GL 代码画东西"。
 * 之所以用极简的 GLSL 1.20 + 流式 VBO（而不是现代 GL），是因为 macOS 上 PZ 只给
 * OpenGL 2.1 legacy 上下文；着色器编译失败时自动退回固定管线立即模式，保证在
 * 任何环境都不会把画面搞崩。
 *
 * <p>所有 GL 状态在绘制前后成对保存/恢复，绘制结束立即还原，避免污染游戏自己的渲染。
 */
public final class Overlay {

    /** 顶点格式：x, y, r, g, b, a */
    private static final int FLOATS_PER_VERTEX = 6;
    private static final int MAX_VERTICES = 8192;

    private static final String VERTEX_SHADER_120 =
        "#version 120\n"
        + "attribute vec2 aPos;\n"
        + "attribute vec4 aColor;\n"
        + "varying vec4 vColor;\n"
        + "void main() {\n"
        + "    vColor = aColor;\n"
        + "    gl_Position = vec4(aPos, 0.0, 1.0);\n"
        + "}\n";

    private static final String FRAGMENT_SHADER_120 =
        "#version 120\n"
        + "varying vec4 vColor;\n"
        + "void main() {\n"
        + "    gl_FragColor = vColor;\n"
        + "}\n";

    private static final float[] VERTICES = new float[MAX_VERTICES * FLOATS_PER_VERTEX];
    private static int vertexCount = 0;

    private static boolean initialized = false;
    private static boolean shaderReady = false;
    private static String shaderError = "";

    private static int program = 0;
    private static int vbo = 0;
    private static int attribPos = -1;
    private static int attribColor = -1;
    private static FloatBuffer uploadBuffer = BufferUtils.createFloatBuffer(1024);

    /**
     * 固定占用最高的两个顶点属性槽位。
     *
     * <p>macOS 上只有 GL 2.1 兼容上下文（没有 core VAO），{@code glVertexAttribPointer}
     * 直接改全局属性状态。游戏自己的着色器只用 0~3 号槽位，所以钉在 14/15 号并成对保存/恢复
     * 其启用状态，就不会把游戏的顶点指针改成我们的 VBO —— 这是"自绘内容会不会把游戏画黑"
     * 的关键防线。
     */
    private static final int ATTR_POS = 15;
    private static final int ATTR_COLOR = 14;
    private static final GlAttribState ATTRIB_GUARD = new GlAttribState(ATTR_POS, ATTR_COLOR);

    private static int screenWidth = 0;
    private static int screenHeight = 0;
    private static final int[] previousViewport = new int[4];

    /** 首次调用时在渲染线程上准备资源。 */
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
                shaderError = "vertex compile: " + trim(GL20.glGetShaderInfoLog(vs));
                GL20.glDeleteShader(vs);
                return;
            }
            int fs = GL20.glCreateShader(GL20.GL_FRAGMENT_SHADER);
            GL20.glShaderSource(fs, FRAGMENT_SHADER_120);
            GL20.glCompileShader(fs);
            if (GL20.glGetShaderi(fs, GL20.GL_COMPILE_STATUS) == 0) {
                shaderError = "fragment compile: " + trim(GL20.glGetShaderInfoLog(fs));
                GL20.glDeleteShader(vs);
                GL20.glDeleteShader(fs);
                return;
            }
            program = GL20.glCreateProgram();
            GL20.glAttachShader(program, vs);
            GL20.glAttachShader(program, fs);
            // 必须在 link 之前把属性钉到高位槽位
            GL20.glBindAttribLocation(program, ATTR_POS, "aPos");
            GL20.glBindAttribLocation(program, ATTR_COLOR, "aColor");
            GL20.glLinkProgram(program);
            GL20.glDeleteShader(vs);
            GL20.glDeleteShader(fs);
            if (GL20.glGetProgrami(program, GL20.GL_LINK_STATUS) == 0) {
                shaderError = "link: " + trim(GL20.glGetProgramInfoLog(program));
                GL20.glDeleteProgram(program);
                program = 0;
                return;
            }
            attribPos = GL20.glGetAttribLocation(program, "aPos");
            attribColor = GL20.glGetAttribLocation(program, "aColor");
            boolean bound = attribPos == ATTR_POS && attribColor == ATTR_COLOR;
            vbo = GL15.glGenBuffers();
            shaderReady = bound && vbo != 0;
            if (!shaderReady) {
                shaderError = "attribute binding mismatch (aPos=" + attribPos + ", aColor=" + attribColor + ")";
            }
            Vp.log("overlay pipeline: " + (shaderReady
                ? "GLSL 1.20 shader + streaming VBO (attribs " + ATTR_POS + "/" + ATTR_COLOR + ")"
                : "immediate-mode fallback (" + shaderError + ")"));
        } catch (Throwable t) {
            shaderReady = false;
            shaderError = String.valueOf(t);
            Vp.error("overlay init failed, falling back to immediate mode", t);
        }
    }

    private static String trim(String value) {
        if (value == null) {
            return "";
        }
        String text = value.trim().replace('\n', ' ');
        return text.length() > 200 ? text.substring(0, 200) : text;
    }

    public static boolean shaderReady() {
        return shaderReady;
    }

    public static String shaderError() {
        return shaderError;
    }

    /**
     * 绘制覆盖层。必须在拥有 GL 上下文的渲染线程调用。
     *
     * @return 本次绘制的三角形数量（0 表示没画）
     */
    public static int draw() {
        ensureInit();
        int[] viewport = new int[4];
        GL11.glGetIntegerv(GL11.GL_VIEWPORT, viewport);
        previousViewport[0] = viewport[0];
        previousViewport[1] = viewport[1];
        previousViewport[2] = viewport[2];
        previousViewport[3] = viewport[3];

        // 不要沿用当前 viewport：渲染线程做完世界绘制后它可能停在偏移视口上
        int[] size = GameScreen.resolve(viewport[2], viewport[3]);
        int width = size[0];
        int height = size[1];
        if (width <= 0 || height <= 0) {
            return 0;
        }
        screenWidth = width;
        screenHeight = height;

        buildGeometry();
        if (vertexCount == 0) {
            return 0;
        }
        renderGeometry();
        return vertexCount / 3;
    }

    /** 组装本帧几何：面板底、边框、帧时间柱状图、能力指示块。 */
    private static void buildGeometry() {
        vertexCount = 0;

        int panelX = VpConfig.overlayX();
        int panelY = VpConfig.overlayY();
        int panelW = 360;
        int panelH = 116;

        float borderR = 0.30f;
        float borderG = 0.85f;
        float borderB = 0.40f;
        if (!shaderReady) {
            borderR = 0.95f;
            borderG = 0.65f;
            borderB = 0.20f;
        }
        if (!Compat.ok()) {
            borderR = 0.90f;
            borderG = 0.25f;
            borderB = 0.25f;
        }

        // 底板
        rect(panelX, panelY, panelW, panelH, 0.05f, 0.05f, 0.07f, 0.60f);
        // 边框（上/下/左/右）
        rect(panelX, panelY, panelW, 2, borderR, borderG, borderB, 0.95f);
        rect(panelX, panelY + panelH - 2, panelW, 2, borderR, borderG, borderB, 0.95f);
        rect(panelX, panelY, 2, panelH, borderR, borderG, borderB, 0.95f);
        rect(panelX + panelW - 2, panelY, 2, panelH, borderR, borderG, borderB, 0.95f);

        // 帧时间柱状图
        int bars = Math.min(VpConfig.graphBars(), FrameStats.sampleCount());
        if (bars > 0) {
            float max = Math.max(16.7f, FrameStats.maxFrameMs());
            int graphX = panelX + 8;
            int graphY = panelY + 10;
            int graphH = 66;
            int barW = 3;
            int step = 4;
            int start = FrameStats.sampleCount() - bars;
            for (int i = 0; i < bars; i++) {
                float ms = FrameStats.sample(start + i);
                if (ms <= 0f) {
                    continue;
                }
                int barH = (int) Math.max(1f, Math.min(graphH, ms / max * graphH));
                float t = Math.min(1f, ms / 33.3f);
                float r = 0.25f + 0.70f * t;
                float g = 0.85f - 0.60f * t;
                rect(graphX + i * step, graphY + graphH - barH, barW, barH, r, g, 0.30f, 0.90f);
            }
            // 16.7ms(60fps) 参考线
            int refY = graphY + graphH - (int) (16.7f / max * graphH);
            rect(graphX, refY, Math.min(bars * step, panelW - 16), 1, 0.85f, 0.85f, 0.90f, 0.35f);
        }

        // 能力指示块：① GLSL120 着色器 ② GLSL330 ③ compat
        int dotY = panelY + panelH - 26;
        int dotX = panelX + 10;
        dot(dotX, dotY, shaderReady ? GREEN : RED);
        dot(dotX + 22, dotY, GlProbe.shader330Ok() ? GREEN : GREY);
        dot(dotX + 44, dotY, Compat.ok() ? GREEN : RED);
    }

    private static final float[] GREEN = {0.25f, 0.85f, 0.40f, 0.95f};
    private static final float[] RED = {0.90f, 0.25f, 0.25f, 0.95f};
    private static final float[] GREY = {0.55f, 0.55f, 0.60f, 0.95f};

    private static void dot(int x, int y, float[] color) {
        rect(x, y, 14, 14, color[0], color[1], color[2], color[3]);
    }

    /** 以屏幕像素坐标（左上原点）追加一个矩形（两个三角形）。 */
    private static void rect(float x, float y, float w, float h, float r, float g, float b, float a) {
        if (vertexCount + 6 > MAX_VERTICES) {
            return;
        }
        float x0 = toNdcX(x);
        float y0 = toNdcY(y);
        float x1 = toNdcX(x + w);
        float y1 = toNdcY(y + h);
        push(x0, y0, r, g, b, a);
        push(x1, y0, r, g, b, a);
        push(x1, y1, r, g, b, a);
        push(x0, y0, r, g, b, a);
        push(x1, y1, r, g, b, a);
        push(x0, y1, r, g, b, a);
    }

    private static void push(float x, float y, float r, float g, float b, float a) {
        int base = vertexCount * FLOATS_PER_VERTEX;
        VERTICES[base] = x;
        VERTICES[base + 1] = y;
        VERTICES[base + 2] = r;
        VERTICES[base + 3] = g;
        VERTICES[base + 4] = b;
        VERTICES[base + 5] = a;
        vertexCount++;
    }

    private static float toNdcX(float x) {
        return x / screenWidth * 2f - 1f;
    }

    private static float toNdcY(float y) {
        return 1f - y / screenHeight * 2f;
    }

    /** 保存状态 → 绘制 → 恢复状态。 */
    private static void renderGeometry() {
        // ---- 保存 ----
        int prevProgram = safeGetInteger(GL20.GL_CURRENT_PROGRAM);
        int prevArrayBuffer = safeGetInteger(GL15.GL_ARRAY_BUFFER_BINDING);
        int prevTexture = safeGetInteger(GL11.GL_TEXTURE_BINDING_2D);
        int prevActiveTexture = safeGetInteger(GL13.GL_ACTIVE_TEXTURE);
        int prevMatrixMode = safeGetInteger(GL11.GL_MATRIX_MODE);
        int prevBlendSrc = safeGetInteger(GL11.GL_BLEND_SRC);
        int prevBlendDst = safeGetInteger(GL11.GL_BLEND_DST);
        boolean wasDepthTest = GL11.glIsEnabled(GL11.GL_DEPTH_TEST);
        boolean wasBlend = GL11.glIsEnabled(GL11.GL_BLEND);
        boolean wasCull = GL11.glIsEnabled(GL11.GL_CULL_FACE);
        boolean wasScissor = GL11.glIsEnabled(GL11.GL_SCISSOR_TEST);
        boolean wasStencil = GL11.glIsEnabled(GL11.GL_STENCIL_TEST);
        boolean wasLighting = GL11.glIsEnabled(GL11.GL_LIGHTING);

        try {
            // ---- 设置 ----
            GL11.glViewport(0, 0, screenWidth, screenHeight);
            GL11.glDisable(GL11.GL_DEPTH_TEST);
            GL11.glDisable(GL11.GL_CULL_FACE);
            GL11.glDisable(GL11.GL_SCISSOR_TEST);
            GL11.glDisable(GL11.GL_STENCIL_TEST);
            GL11.glDisable(GL11.GL_LIGHTING);
            GL11.glEnable(GL11.GL_BLEND);
            GL11.glBlendFunc(GL11.GL_SRC_ALPHA, GL11.GL_ONE_MINUS_SRC_ALPHA);

            if (shaderReady) {
                drawWithShader(prevProgram);
            } else {
                drawImmediate(prevProgram, prevMatrixMode);
            }
        } finally {
            // ---- 恢复 ----
            GL11.glViewport(previousViewport[0], previousViewport[1], previousViewport[2], previousViewport[3]);
            GL20.glUseProgram(prevProgram);
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, prevArrayBuffer);
            GL13.glActiveTexture(prevActiveTexture);
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, prevTexture);
            GL11.glBlendFunc(prevBlendSrc, prevBlendDst);
            toggle(GL11.GL_DEPTH_TEST, wasDepthTest);
            toggle(GL11.GL_BLEND, wasBlend);
            toggle(GL11.GL_CULL_FACE, wasCull);
            toggle(GL11.GL_SCISSOR_TEST, wasScissor);
            toggle(GL11.GL_STENCIL_TEST, wasStencil);
            toggle(GL11.GL_LIGHTING, wasLighting);
        }
    }

    private static void drawWithShader(int prevProgram) {
        GL20.glUseProgram(program);
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, vbo);
        int needed = vertexCount * FLOATS_PER_VERTEX;
        if (uploadBuffer.capacity() < needed) {
            uploadBuffer = BufferUtils.createFloatBuffer(needed * 2);
        }
        uploadBuffer.clear();
        uploadBuffer.put(VERTICES, 0, needed);
        uploadBuffer.flip();
        GL15.glBufferData(GL15.GL_ARRAY_BUFFER, uploadBuffer, GL15.GL_STREAM_DRAW);
        // 属性状态是全局的（macOS 无 core VAO），必须先存后改、改完还原
        ATTRIB_GUARD.save();
        GL20.glEnableVertexAttribArray(attribPos);
        GL20.glEnableVertexAttribArray(attribColor);
        int stride = FLOATS_PER_VERTEX * 4;
        GL20.glVertexAttribPointer(attribPos, 2, GL11.GL_FLOAT, false, stride, 0L);
        GL20.glVertexAttribPointer(attribColor, 4, GL11.GL_FLOAT, false, stride, 2L * 4L);
        GL11.glDrawArrays(GL11.GL_TRIANGLES, 0, vertexCount);
        ATTRIB_GUARD.restore();
        GL20.glUseProgram(prevProgram);
    }

    /** 兜底路径：GLSL 不可用时的固定管线立即模式（OpenGL 1.x 语法，2.1 上下文必然支持）。 */
    private static void drawImmediate(int prevProgram, int prevMatrixMode) {
        GL20.glUseProgram(0);
        GL11.glMatrixMode(GL11.GL_PROJECTION);
        GL11.glPushMatrix();
        GL11.glLoadIdentity();
        GL11.glOrtho(0, screenWidth, screenHeight, 0, -1, 1);
        GL11.glMatrixMode(GL11.GL_MODELVIEW);
        GL11.glPushMatrix();
        GL11.glLoadIdentity();
        GL11.glBegin(GL11.GL_TRIANGLES);
        for (int i = 0; i < vertexCount; i++) {
            int base = i * FLOATS_PER_VERTEX;
            GL11.glColor4f(VERTICES[base + 2], VERTICES[base + 3], VERTICES[base + 4], VERTICES[base + 5]);
            float px = (VERTICES[base] + 1f) * 0.5f * screenWidth;
            float py = (1f - VERTICES[base + 1]) * 0.5f * screenHeight;
            GL11.glVertex2f(px, py);
        }
        GL11.glEnd();
        GL11.glMatrixMode(GL11.GL_PROJECTION);
        GL11.glPopMatrix();
        GL11.glMatrixMode(GL11.GL_MODELVIEW);
        GL11.glPopMatrix();
        GL11.glMatrixMode(prevMatrixMode);
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

    private Overlay() {
    }
}
