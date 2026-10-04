package viewpointmac;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;

/**
 * 把运行环境、兼容性自检、GL 能力探针的结果落盘到 {@code ~/Zomboid/viewpointmac-report.txt}。
 *
 * <p>用途：玩家（或作者）可以直接把这个文件贴出来定位问题，不必翻整个 console.txt；
 * 同时也是"这台机器到底能不能走现代 GL"的权威证据。
 */
public final class Report {

    public static synchronized File write() {
        File file = Vp.userFile(Vp.REPORT_FILE);
        StringBuilder sb = new StringBuilder();
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.ROOT);

        sb.append("ViewpointMac capability report\n");
        sb.append("==============================\n");
        sb.append("generated  : ").append(format.format(new Date())).append('\n');
        sb.append("mod version: ").append(Vp.VERSION).append('\n');
        sb.append("game build : ").append(gameBuild()).append('\n');
        sb.append("java       : ").append(System.getProperty("java.version"))
          .append(" (").append(System.getProperty("java.vendor")).append(")\n");
        sb.append("os         : ").append(System.getProperty("os.name"))
          .append(' ').append(System.getProperty("os.version"))
          .append(" arch=").append(System.getProperty("os.arch")).append('\n');
        sb.append("zomboid dir: ").append(Vp.zomboidDir().getAbsolutePath()).append("\n\n");

        sb.append("-- compatibility --\n");
        boolean compat = Compat.check();
        sb.append("render hook usable: ").append(compat).append('\n');
        List<String> missing = Compat.missing();
        if (missing.isEmpty()) {
            sb.append("all required classes and members were found\n");
        } else {
            sb.append("missing:\n");
            for (String item : missing) {
                sb.append("  ! ").append(item).append('\n');
            }
        }
        sb.append('\n');

        sb.append("-- OpenGL probe (render thread) --\n");
        if (GlProbe.probed()) {
            sb.append(GlProbe.describe());
        } else {
            sb.append("not probed yet (the render hook has not run with a live GL context)\n");
        }
        sb.append('\n');

        sb.append("-- overlay --\n");
        sb.append("enabled          : ").append(VpConfig.overlay()).append('\n');
        sb.append("pipeline         : ").append(Overlay.shaderReady() ? "GLSL 1.20 shader + VBO" : "immediate mode")
          .append('\n');
        if (!Overlay.shaderError().isEmpty()) {
            sb.append("shader error     : ").append(Overlay.shaderError()).append('\n');
        }
        sb.append("frame stats      : ").append(FrameStats.describe()).append('\n');
        sb.append('\n');

        sb.append("-- 3D scene (P1 camera) --\n");
        sb.append("enabled          : ").append(VpConfig.scene3d()).append('\n');
        sb.append("pipeline         : ").append(Scene3D.describe()).append('\n');
        sb.append("screen           : ").append(GameScreen.describe()).append('\n');
        sb.append("world bridge     : ").append(GameWorld.describe()).append('\n');
        sb.append("camera           : ").append(Camera.describe()).append('\n');
        sb.append("voxel world      : ").append(VoxelWorld.describe()).append('\n');
        sb.append("world tiles      : ").append(WorldTiles.describe()).append('\n');
        sb.append("tile textures    : ").append(TileTextures.describe()).append('\n');
        for (int i = 0; i < 3 && i < TileTextures.MAX_SLOTS; i++) {
            sb.append("  texture uv[").append(i).append("] : ")
              .append(TileTextures.describeSlot(i)).append('\n');
        }
        sb.append("voxel pack       : ").append(VoxelPack.describe()).append('\n');
        sb.append("model cache      : ").append(ModelCache.describe()).append('\n');
        sb.append("render mode      : overlay (the vanilla view is never skipped)").append('\n');
        sb.append("in game state    : ").append(GameWorld.inGameState()).append('\n');
        sb.append("character models : ").append(CharacterModels.describe()).append('\n');
        sb.append("entities         : ").append(Entities.describe()).append('\n');
        sb.append("mouse look       : ").append(MouseLook.describe()).append('\n');
        sb.append("sky              : ").append(SkySource.describe()).append('\n');
        sb.append('\n');

        sb.append("-- verdict --\n");
        sb.append(verdict()).append('\n');

        try {
            Path path = file.toPath();
            Path parent = path.getParent();
            if (parent != null) {
                Files.createDirectories(parent);
            }
            Files.write(path, sb.toString().getBytes(StandardCharsets.UTF_8));
            Vp.log("report written: " + file.getAbsolutePath());
        } catch (IOException e) {
            Vp.error("report write failed: " + file, e);
        }
        return file;
    }

    private static String verdict() {
        if (!Compat.ok()) {
            return "render injection disabled: the game build does not expose the expected members.";
        }
        if (!GlProbe.probed()) {
            return "waiting for the first rendered frame to probe OpenGL.";
        }
        if ("GL_LEGACY_21".equals(GlProbe.backend())) {
            return "OpenGL 2.1 legacy context: shader-based 3D must target GLSL 1.20, or use the "
                + "Metal/IOSurface backend to composite modern rendering into the game's GL context.";
        }
        if (GlProbe.shader330Ok()) {
            return "GLSL 330 is available here: a modern GL renderer is possible in-process.";
        }
        return "unknown backend: see the extension list above.";
    }

    /** 读游戏自己写的 version.txt，比反射游戏类更稳定。 */
    private static String gameBuild() {
        try {
            File versionFile = Vp.userFile("version.txt");
            if (versionFile.isFile()) {
                String text = new String(Files.readAllBytes(versionFile.toPath()), StandardCharsets.UTF_8).trim();
                if (!text.isEmpty()) {
                    return text.replace('\n', ' ');
                }
            }
        } catch (Throwable ignored) {
            // 读不到就算了
        }
        return "unknown";
    }

    private Report() {
    }
}
