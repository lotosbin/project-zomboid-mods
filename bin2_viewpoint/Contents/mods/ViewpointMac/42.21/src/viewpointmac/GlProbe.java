package viewpointmac;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL20;

/**
 * 在<strong>游戏自己的渲染线程</strong>上做一次性 GL 能力探测。
 *
 * <p>为什么不放在 {@code Main.main()}：模组加载发生在主线程，那时 GL 上下文并不在当前线程，
 * 所有 glGetString 都会失败。渲染线程（我们挂的 {@code SpriteRenderer.postRender}）才是
 * 上下文有效的地方，因此探针做成"首帧惰性执行"。
 *
 * <p>探测内容：
 * <ol>
 *   <li>GL_VERSION / GL_RENDERER / GL_VENDOR / GLSL 版本；</li>
 *   <li>对本项目关键的扩展是否存在（决定能走哪条渲染路线）；</li>
 *   <li>就地编译 {@code #version 120} 与 {@code #version 330} 测试着色器，
 *       把"macOS 上到底能不能用现代 GLSL"这一结论钉死在真实运行环境里；</li>
 *   <li>若干硬件上限。</li>
 * </ol>
 */
public final class GlProbe {

    /** 与本项目路线直接相关的扩展（macOS legacy 2.1 的实测结果见 docs）。 */
    private static final String[] WATCHED_EXTENSIONS = {
        "GL_ARB_framebuffer_object",
        "GL_EXT_framebuffer_object",
        "GL_EXT_framebuffer_blit",
        "GL_EXT_framebuffer_multisample",
        "GL_ARB_draw_buffers",
        "GL_ARB_texture_float",
        "GL_ARB_depth_texture",
        "GL_ARB_shadow",
        "GL_EXT_texture_array",
        "GL_ARB_vertex_buffer_object",
        "GL_ARB_pixel_buffer_object",
        "GL_APPLE_vertex_array_object",
        "GL_ARB_instanced_arrays",
        "GL_ARB_draw_instanced",
        "GL_EXT_multi_draw_arrays",
        "GL_ARB_sync",
        "GL_EXT_timer_query",
        "GL_APPLE_flush_buffer_range",
        "GL_ARB_occlusion_query",
        "GL_EXT_gpu_shader4",
        "GL_ARB_shader_texture_lod",
        "GL_EXT_texture_filter_anisotropic",
        "GL_ARB_texture_rg",
        "GL_EXT_texture_integer",
        "GL_EXT_texture_compression_s3tc",
        "GL_EXT_texture_sRGB",
        "GL_ARB_framebuffer_sRGB",
        "GL_EXT_transform_feedback",
        "GL_EXT_geometry_shader4",
        // 以下在 macOS 上预期为"无"，列出来是为了让报告能自证
        "GL_ARB_map_buffer_range",
        "GL_ARB_texture_storage",
        "GL_ARB_texture_gather",
        "GL_ARB_gpu_shader5",
        "GL_ARB_uniform_buffer_object",
        "GL_ARB_shader_image_load_store",
        "GL_ARB_compute_shader",
        "GL_ARB_vertex_attrib_binding",
        "GL_ARB_buffer_storage",
        "GL_ARB_multi_draw_indirect",
        "GL_ARB_direct_state_access",
        "GL_ARB_copy_image",
    };

    private static boolean probed = false;
    private static int attempts = 0;
    private static boolean contextOk = false;

    private static String glVersion = "?";
    private static String glRenderer = "?";
    private static String glVendor = "?";
    private static String glslVersion = "?";
    private static String backend = "UNKNOWN";

    private static final Set<String> AVAILABLE = new LinkedHashSet<>();
    private static final List<String> MISSING_EXTENSIONS = new ArrayList<>();

    private static boolean shader120Ok = false;
    private static String shader120Log = "";
    private static boolean shader330Ok = false;
    private static String shader330Log = "";

    private static int maxTextureSize = -1;
    private static int maxDrawBuffers = -1;
    private static int maxColorAttachments = -1;
    private static int maxVaryingFloats = -1;
    private static int maxTextureUnits = -1;

    public static boolean probed() {
        return probed;
    }

    public static boolean contextOk() {
        return contextOk;
    }

    public static String glVersion() {
        return glVersion;
    }

    public static String glRenderer() {
        return glRenderer;
    }

    public static String glVendor() {
        return glVendor;
    }

    public static String glslVersion() {
        return glslVersion;
    }

    public static String backend() {
        return backend;
    }

    public static boolean shader120Ok() {
        return shader120Ok;
    }

    public static boolean shader330Ok() {
        return shader330Ok;
    }

    public static Set<String> availableExtensions() {
        return Collections.unmodifiableSet(AVAILABLE);
    }

    public static List<String> missingExtensions() {
        return Collections.unmodifiableList(MISSING_EXTENSIONS);
    }

    /** 探测是否已经失败太多次（例如始终没有上下文），失败后不再重试。 */
    public static boolean givenUp() {
        return attempts >= 5 && !probed;
    }

    /**
     * 由渲染钩子每帧调用；只在首次真正拿到上下文时完成探测。
     *
     * @return 本次调用是否完成了探测
     */
    public static synchronized boolean probeOnce() {
        if (probed || givenUp()) {
            return probed;
        }
        attempts++;
        try {
            glVersion = safeString(GL11.GL_VERSION);
            glRenderer = safeString(GL11.GL_RENDERER);
            glVendor = safeString(GL11.GL_VENDOR);
            glslVersion = safeString(GL20.GL_SHADING_LANGUAGE_VERSION);
            if (glVersion == null || glVersion.isEmpty()) {
                Vp.debug("probe attempt " + attempts + ": no GL context yet");
                return false;
            }
            contextOk = true;
            readExtensions();
            readLimits();
            compileProbes();
            backend = decideBackend();
            probed = true;
            logSummary();
            // 报告不在这里写：本帧稍后 Scene3D / Overlay 才会初始化，
            // 交给 RenderHook 在首帧末尾统一落盘，报告里才有它们的真实状态。
            return true;
        } catch (Throwable t) {
            Vp.error("probe failed (attempt " + attempts + ")", t);
            return false;
        }
    }

    private static String safeString(int name) {
        try {
            String value = GL11.glGetString(name);
            return value == null ? "" : value.trim();
        } catch (Throwable t) {
            return "";
        }
    }

    private static void readExtensions() {
        AVAILABLE.clear();
        MISSING_EXTENSIONS.clear();
        String all = safeString(GL11.GL_EXTENSIONS);
        Set<String> present = new LinkedHashSet<>();
        for (String token : all.split("\\s+")) {
            if (!token.isEmpty()) {
                present.add(token);
            }
        }
        for (String ext : WATCHED_EXTENSIONS) {
            if (present.contains(ext)) {
                AVAILABLE.add(ext);
            } else {
                MISSING_EXTENSIONS.add(ext);
            }
        }
    }

    private static void readLimits() {
        maxTextureSize = getInteger(GL11.GL_MAX_TEXTURE_SIZE);
        maxTextureUnits = getInteger(GL20.GL_MAX_TEXTURE_IMAGE_UNITS);
        maxVaryingFloats = getInteger(0x8B4B);      // GL_MAX_VARYING_FLOATS
        maxDrawBuffers = getInteger(0x8824);        // GL_MAX_DRAW_BUFFERS
        maxColorAttachments = getInteger(0x8CDF);   // GL_MAX_COLOR_ATTACHMENTS_EXT
    }

    private static int getInteger(int pname) {
        try {
            return GL11.glGetInteger(pname);
        } catch (Throwable t) {
            return -1;
        }
    }

    /** 就地编译两个测试着色器——这是"macOS 能不能用现代 GLSL"的最终判决。 */
    private static void compileProbes() {
        String[] r120 = compileVertex(
            "#version 120\n"
            + "void main() { gl_Position = ftransform(); }\n");
        shader120Ok = "OK".equals(r120[0]);
        shader120Log = r120[1];

        String[] r330 = compileVertex(
            "#version 330\n"
            + "layout(location = 0) in vec3 aPos;\n"
            + "void main() { gl_Position = vec4(aPos, 1.0); }\n");
        shader330Ok = "OK".equals(r330[0]);
        shader330Log = r330[1];
    }

    /** @return {结果, 日志}，结果为 OK 或具体错误 */
    private static String[] compileVertex(String source) {
        int shader = 0;
        try {
            shader = GL20.glCreateShader(GL20.GL_VERTEX_SHADER);
            if (shader == 0) {
                return new String[] {"FAIL", "glCreateShader returned 0"};
            }
            GL20.glShaderSource(shader, source);
            GL20.glCompileShader(shader);
            int status = GL20.glGetShaderi(shader, GL20.GL_COMPILE_STATUS);
            String log = GL20.glGetShaderInfoLog(shader);
            if (status != 0) {
                return new String[] {"OK", log == null ? "" : log.trim()};
            }
            return new String[] {"FAIL", log == null ? "compile failed" : log.trim()};
        } catch (Throwable t) {
            return new String[] {"FAIL", String.valueOf(t)};
        } finally {
            if (shader != 0) {
                try {
                    GL20.glDeleteShader(shader);
                } catch (Throwable ignored) {
                    // 清理失败无所谓
                }
            }
        }
    }

    /**
     * 判定当前可用的渲染后端。
     *
     * <p>macOS + PZ 的现状是 {@code GL 2.1 legacy}：只有 GLSL 1.20，
     * 4.3~4.5 的函数在系统框架里根本不存在 —— 这正是现成 Viewpoint 跑不起来的原因。
     */
    private static String decideBackend() {
        String version = glVersion == null ? "" : glVersion.trim();
        if (version.startsWith("4.6") || version.startsWith("4.5") || version.startsWith("4.4")
            || version.startsWith("4.3")) {
            return "GL_MODERN";
        }
        if (version.startsWith("4.") || version.startsWith("3.")) {
            return "GL_CORE_41";
        }
        if (version.startsWith("2.1") || version.startsWith("2.")) {
            return "GL_LEGACY_21";
        }
        return "UNKNOWN";
    }

    private static void logSummary() {
        Vp.log("GL probe: version=" + glVersion + " renderer=" + glRenderer + " glsl=" + glslVersion);
        Vp.log("GL probe: backend=" + backend + ", shader120=" + (shader120Ok ? "OK" : "FAIL")
            + ", shader330=" + (shader330Ok ? "OK" : "FAIL"));
        Vp.log("GL probe: extensions available " + AVAILABLE.size() + "/" + WATCHED_EXTENSIONS.length);
        if (!shader330Ok) {
            Vp.log("GL probe: GLSL 330 unavailable here -> the upstream Viewpoint renderer cannot run; "
                + "this mod is the macOS path (GL 1.20 overlay / Metal backend plan).");
        }
    }

    /** 供报告使用：多行文本。 */
    public static String describe() {
        StringBuilder sb = new StringBuilder();
        sb.append("context ok       : ").append(contextOk).append('\n');
        sb.append("GL_VERSION       : ").append(glVersion).append('\n');
        sb.append("GL_RENDERER      : ").append(glRenderer).append('\n');
        sb.append("GL_VENDOR        : ").append(glVendor).append('\n');
        sb.append("GLSL_VERSION     : ").append(glslVersion).append('\n');
        sb.append("backend          : ").append(backend).append('\n');
        sb.append("shader #version 120 : ").append(shader120Ok ? "OK" : "FAIL");
        if (!shader120Ok && !shader120Log.isEmpty()) {
            sb.append(" | ").append(shader120Log);
        }
        sb.append('\n');
        sb.append("shader #version 330 : ").append(shader330Ok ? "OK" : "FAIL");
        if (!shader330Ok && !shader330Log.isEmpty()) {
            sb.append(" | ").append(shader330Log);
        }
        sb.append('\n');
        sb.append("limits           : texSize=").append(maxTextureSize)
          .append(" textureUnits=").append(maxTextureUnits)
          .append(" varyingFloats=").append(maxVaryingFloats)
          .append(" drawBuffers=").append(maxDrawBuffers)
          .append(" colorAttachments=").append(maxColorAttachments).append('\n');
        sb.append("extensions present (").append(AVAILABLE.size()).append("):\n");
        for (String ext : AVAILABLE) {
            sb.append("  + ").append(ext).append('\n');
        }
        sb.append("extensions absent (").append(MISSING_EXTENSIONS.size()).append("):\n");
        for (String ext : MISSING_EXTENSIONS) {
            sb.append("  - ").append(ext).append('\n');
        }
        return sb.toString();
    }

    private GlProbe() {
    }
}
