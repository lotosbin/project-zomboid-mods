package viewpointmac;

import java.io.File;
import java.util.List;

import me.zed_0xff.zombie_buddy.Exposer;

/**
 * 暴露给 Lua 的接口。
 *
 * <p>沿用 Viewpoint 的暴露方式：类级 {@code @Exposer.LuaClass(name = "...")} 加上
 * 一组 <strong>public static</strong> 方法，ZombieBuddy 会自动把它们挂到同名 Lua 表上
 * （对照 {@code viewpoint.FrameCapsLua} → Lua 里的 {@code Viewpoint.FrameCaps.xxx()}）。
 * 因此这里不需要 Kahlua 的 {@code @LuaMethod}，方法名就是 Lua 里的方法名。
 *
 * <p>每个方法都自行吞掉异常并返回字符串，保证 Lua 侧永远不会因为 Java 异常中断。
 *
 * <p>Lua 用法见 {@code media/lua/client/ViewpointMac/ViewpointMac.lua}：
 * <pre>
 *   print(ViewpointMac.status())
 *   ViewpointMac.toggleOverlay()
 *   print(ViewpointMac.writeReport())
 * </pre>
 */
@Exposer.LuaClass(name = "ViewpointMac")
public final class LuaApi {

    public static String status() {
        try {
            return RenderHook.status();
        } catch (Throwable t) {
            return "status unavailable: " + t;
        }
    }

    public static String version() {
        return Vp.VERSION;
    }

    public static String backend() {
        try {
            String value = GlProbe.backend();
            return value == null ? "UNKNOWN" : value;
        } catch (Throwable t) {
            return "UNKNOWN";
        }
    }

    public static String glVersion() {
        return nullTo(GlProbe.glVersion(), "?");
    }

    public static String glRenderer() {
        return nullTo(GlProbe.glRenderer(), "?");
    }

    public static String glVendor() {
        return nullTo(GlProbe.glVendor(), "?");
    }

    public static String glslVersion() {
        return nullTo(GlProbe.glslVersion(), "?");
    }

    /** 形如 "120=OK 330=FAIL" —— 就地着色器编译结论。 */
    public static String shaderProbe() {
        if (!GlProbe.probed()) {
            return "not probed yet";
        }
        return "120=" + (GlProbe.shader120Ok() ? "OK" : "FAIL")
            + " 330=" + (GlProbe.shader330Ok() ? "OK" : "FAIL");
    }

    /** 当前覆盖层用的是着色器还是固定管线兜底。 */
    public static String overlayPipeline() {
        try {
            return Overlay.shaderReady() ? "GLSL 1.20 shader + VBO" : "immediate mode";
        } catch (Throwable t) {
            return "unknown";
        }
    }

    public static int extensionsPresent() {
        return GlProbe.availableExtensions().size();
    }

    public static String extensionsAbsent() {
        List<String> missing = GlProbe.missingExtensions();
        return missing.isEmpty() ? "" : String.join(", ", missing);
    }

    public static boolean compatOk() {
        return Compat.ok();
    }

    public static String compatMissing() {
        List<String> missing = Compat.missing();
        return missing.isEmpty() ? "" : String.join(", ", missing);
    }

    public static boolean isOverlayEnabled() {
        return VpConfig.overlay();
    }

    public static boolean setOverlay(boolean enabled) {
        try {
            VpConfig.setOverlay(enabled);
            Vp.log("overlay " + (enabled ? "on" : "off") + " (runtime toggle)");
        } catch (Throwable t) {
            Vp.error("setOverlay failed", t);
        }
        return VpConfig.overlay();
    }

    public static boolean toggleOverlay() {
        return setOverlay(!VpConfig.overlay());
    }

    public static boolean hookDisabled() {
        return RenderHook.disabled();
    }

    public static String frameStats() {
        try {
            return FrameStats.describe();
        } catch (Throwable t) {
            return "no samples yet";
        }
    }

    public static double fps() {
        return FrameStats.fps();
    }

    // ---------------------------------------------------------------- P1：3D 场景与相机

    public static boolean isScene3dEnabled() {
        return VpConfig.scene3d();
    }

    public static boolean setScene3d(boolean enabled) {
        try {
            VpConfig.setScene3d(enabled);
            Vp.log("3D scene " + (enabled ? "on" : "off") + " (runtime toggle)");
        } catch (Throwable t) {
            Vp.error("setScene3d failed", t);
        }
        return VpConfig.scene3d();
    }

    public static boolean toggleScene3d() {
        return setScene3d(!VpConfig.scene3d());
    }

    public static boolean isThirdPerson() {
        return VpConfig.cameraThirdPerson();
    }

    public static boolean toggleCameraMode() {
        try {
            VpConfig.setCameraThirdPerson(!VpConfig.cameraThirdPerson());
            Vp.log("camera mode = " + (VpConfig.cameraThirdPerson() ? "third" : "first") + " person");
        } catch (Throwable t) {
            Vp.error("toggleCameraMode failed", t);
        }
        return VpConfig.cameraThirdPerson();
    }

    /** 3D 管线状态（是否可用、本帧图元数、相机参数）。 */
    public static String sceneInfo() {
        try {
            return Scene3D.describe();
        } catch (Throwable t) {
            return "scene unavailable: " + t;
        }
    }

    /** 相机参数（eye / yaw / pitch / fov / 模式）。 */
    public static String cameraInfo() {
        try {
            return Camera.describe();
        } catch (Throwable t) {
            return "camera unavailable: " + t;
        }
    }

    // ---------------------------------------------------------------- P2：体素世界

    public static boolean isVoxelEnabled() {
        return VpConfig.voxel();
    }

    public static boolean setVoxel(boolean enabled) {
        try {
            VpConfig.setVoxel(enabled);
            Vp.log("voxel world " + (enabled ? "on" : "off") + " (runtime toggle)");
        } catch (Throwable t) {
            Vp.error("setVoxel failed", t);
        }
        return VpConfig.voxel();
    }

    public static boolean toggleVoxel() {
        return setVoxel(!VpConfig.voxel());
    }

    public static boolean toggleVoxelWireframe() {
        try {
            VpConfig.setVoxelWireframe(!VpConfig.voxelWireframe());
            Vp.log("voxel wireframe = " + VpConfig.voxelWireframe());
        } catch (Throwable t) {
            Vp.error("toggleVoxelWireframe failed", t);
        }
        return VpConfig.voxelWireframe();
    }

    public static boolean isMouseLookEnabled() {
        return VpConfig.mouseLook();
    }

    public static boolean toggleMouseLook() {
        try {
            VpConfig.setMouseLook(!VpConfig.mouseLook());
            if (!VpConfig.mouseLook()) {
                MouseLook.setEnabled(false);
            } else {
                MouseLook.setEnabled(true);
            }
            Vp.log("mouse look = " + VpConfig.mouseLook());
        } catch (Throwable t) {
            Vp.error("toggleMouseLook failed", t);
        }
        return VpConfig.mouseLook();
    }

    public static boolean isEntitiesEnabled() {
        return VpConfig.entities();
    }

    public static boolean toggleEntities() {
        VpConfig.setEntities(!VpConfig.entities());
        Vp.log("entity boxes = " + VpConfig.entities());
        return VpConfig.entities();
    }

    public static boolean isCharacterModelsEnabled() {
        return VpConfig.characterModels();
    }

    public static boolean toggleCharacterModels() {
        VpConfig.setCharacterModels(!VpConfig.characterModels());
        Vp.log("character models = " + VpConfig.characterModels());
        return VpConfig.characterModels();
    }

    // ---- 调试面板用的通用选项接口（面板只认名字，Java 侧一处映射）----

    public static boolean applyFull3dPreset() {
        try {
            VpConfig.applyFull3dPreset();
            return true;
        } catch (Throwable t) {
            Vp.error("applyFull3dPreset failed", t);
            return false;
        }
    }

    public static boolean isFull3d() {
        return VpConfig.coverVanilla();
    }

    public static String logPath() {
        return Vp.logFile().getAbsolutePath();
    }

    public static String optionList() {
        return String.join(",", VpConfig.optionNames());
    }

    public static boolean optionOn(String name) {
        try {
            return VpConfig.option(name);
        } catch (Throwable t) {
            return false;
        }
    }

    public static boolean setOption(String name, boolean value) {
        try {
            return VpConfig.setOption(name, value);
        } catch (Throwable t) {
            Vp.error("setOption failed: " + name, t);
            return false;
        }
    }

    public static int optionInt(String name) {
        return VpConfig.optionInt(name);
    }

    public static int addOptionInt(String name, int delta) {
        return VpConfig.addOptionInt(name, delta);
    }

    public static String floorUvMode() {
        return VpConfig.floorUvMode();
    }

    public static String cameraModeInfo() {
        try {
            return Camera.describe();
        } catch (Throwable t) {
            return "camera unavailable: " + t;
        }
    }

    public static String cycleFloorUv() {
        try {
            String mode = VpConfig.cycleFloorUvMode();
            VpConfig.invalidateVoxelMesh();
            return mode;
        } catch (Throwable t) {
            return "failed: " + t;
        }
    }

    public static String floorUvInfo() {
        return "floorUv=" + VpConfig.floorUvMode() + " | " + TileTextures.describe()
            + " | " + TileTextures.describeSlot(0);
    }

    public static String characterModelsInfo() {
        try {
            return CharacterModels.describe();
        } catch (Throwable t) {
            return "character models unavailable: " + t;
        }
    }

    public static String entitiesInfo() {
        try {
            return Entities.describe();
        } catch (Throwable t) {
            return "entities unavailable: " + t;
        }
    }

    public static String mouseLookInfo() {
        try {
            return MouseLook.describe();
        } catch (Throwable t) {
            return "mouse look unavailable: " + t;
        }
    }

    public static String skyInfo() {
        try {
            return SkySource.describe();
        } catch (Throwable t) {
            return "sky unavailable: " + t;
        }
    }

    /** 体素采样进度与网格规模。 */
    public static String voxelInfo() {
        try {
            return VoxelWorld.describe() + " | bridge " + WorldTiles.describe();
        } catch (Throwable t) {
            return "voxel unavailable: " + t;
        }
    }

    /** 玩家世界坐标与朝向（验证读到的是真实世界数据）。 */
    public static String playerInfo() {
        try {
            return GameWorld.describe();
        } catch (Throwable t) {
            return "player unavailable: " + t;
        }
    }

    /** 写一份能力报告到 ~/Zomboid/viewpointmac-report.txt，返回路径。 */
    public static String writeReport() {
        try {
            File file = Report.write();
            return file.getAbsolutePath();
        } catch (Throwable t) {
            Vp.error("writeReport failed", t);
            return "report failed: " + t;
        }
    }

    private static String nullTo(String value, String fallback) {
        return value == null || value.isEmpty() ? fallback : value;
    }

    private LuaApi() {
    }
}
