package viewpointmac;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;

/**
 * P3.1：读取第三方 **PZ Voxel Studio** 模型包（Workshop 3810302175 / 3810051489）。
 *
 * <p>原版游戏没有物件的 3D 几何（物件全是 2D 等距精灵），这个模型包补上了这一块：
 * <pre>
 *   common/media/voxel-studio/package*.properties
 *     model.&lt;modelKey&gt;=&lt;uuid&gt;/r1-.../model-....obj
 *     bind.&lt;spriteName&gt;=&lt;modelKey&gt;,&lt;rotationDeg&gt;,&lt;offsetX&gt;,&lt;offsetY&gt;,&lt;offsetZ&gt;,&lt;scale&gt;
 *   common/media/voxel-studio/&lt;uuid&gt;/r1-.../model.obj + model-rp.mtl(map_Kd) + *.png
 * </pre>
 * OBJ 自带说明 {@code # PZ Voxel Studio — Z up, tile units}，与我们的世界坐标约定一致
 * （X 东 / Y 南 / Z 上，1 单位 = 1 地块格），所以不需要额外换算。
 *
 * <p>全部走文件系统扫描（不依赖 Steam 路径常量），并支持 {@code voxelPackDir} 手工指定。
 */
public final class VoxelPack {

    /** 一条精灵名 → 模型的绑定。 */
    public static final class Bind {
        public final String spriteName;
        public final String modelPath;
        public final float rotationDeg;
        public final float offsetX;
        public final float offsetY;
        public final float offsetZ;
        public final float scale;
        public final String cacheKey;

        Bind(String spriteName, String modelPath, float rotationDeg,
             float offsetX, float offsetY, float offsetZ, float scale) {
            this.spriteName = spriteName;
            this.modelPath = modelPath;
            this.rotationDeg = rotationDeg;
            this.offsetX = offsetX;
            this.offsetY = offsetY;
            this.offsetZ = offsetZ;
            this.scale = scale;
            this.cacheKey = spriteName + "|" + modelPath + "|" + rotationDeg + "|"
                + offsetX + "|" + offsetY + "|" + offsetZ + "|" + scale;
        }
    }

    private static final Map<String, Bind> BINDS = new HashMap<>();
    private static boolean scanned = false;
    private static String scanReport = "not scanned";
    private static final List<String> LOADED_FROM = new ArrayList<>();

    public static boolean available() {
        scan();
        return !BINDS.isEmpty();
    }

    public static int bindCount() {
        return BINDS.size();
    }

    /** 查精灵名对应的模型；没有返回 null。 */
    public static Bind bind(String spriteName) {
        if (spriteName == null || spriteName.isEmpty()) {
            return null;
        }
        scan();
        Bind bind = BINDS.get(spriteName);
        if (bind != null) {
            return bind;
        }
        // 精灵名有时带方向/帧后缀，退一步去掉尾部 "_数字"
        int cut = spriteName.lastIndexOf('_');
        if (cut > 0) {
            return BINDS.get(spriteName.substring(0, cut));
        }
        return null;
    }

    /** 扫描一次（在模组加载时调用，避免渲染线程做大量目录 I/O）。 */
    public static synchronized void scan() {
        if (scanned) {
            return;
        }
        scanned = true;
        long start = System.currentTimeMillis();
        List<File> dirs = new ArrayList<>();

        String override = VpConfig.voxelPackDir();
        if (override != null && !override.isEmpty()) {
            collectVoxelStudioDirs(new File(override), dirs);
        }
        File zomboid = Vp.zomboidDir();
        collectUnderMods(new File(zomboid, "mods"), dirs);
        collectUnderItemRoots(new File(zomboid, "Workshop"), dirs);

        File steam = new File(System.getProperty("user.home", "."),
            "Library/Application Support/Steam/steamapps/workshop/content/108600");
        if (steam.isDirectory()) {
            File[] items = steam.listFiles();
            if (items != null) {
                for (File item : items) {
                    collectUnderMods(new File(item, "mods"), dirs);
                }
            }
        }

        int packages = 0;
        for (File dir : dirs) {
            File[] props = dir.listFiles((d, name) -> name.startsWith("package") && name.endsWith(".properties"));
            if (props == null) {
                continue;
            }
            for (File prop : props) {
                packages += loadPackage(prop, dir);
            }
            if (props.length > 0) {
                LOADED_FROM.add(dir.getAbsolutePath());
            }
        }
        scanReport = "packages=" + packages + " binds=" + BINDS.size()
            + " sources=" + LOADED_FROM.size()
            + " took=" + (System.currentTimeMillis() - start) + "ms";
        Vp.log("voxel pack: " + scanReport);
        if (BINDS.isEmpty()) {
            Vp.warn("voxel pack not found; set voxelPackDir in viewpointmac.properties if it lives elsewhere.");
        }
    }

    /** 在 mods 根目录下找 `<mod>/media/voxel-studio` 或 `<mod>/<版本>/media/voxel-studio`。 */
    private static void collectUnderMods(File modsRoot, List<File> out) {
        if (modsRoot == null || !modsRoot.isDirectory()) {
            return;
        }
        File[] mods = modsRoot.listFiles(File::isDirectory);
        if (mods == null) {
            return;
        }
        for (File mod : mods) {
            collectVoxelStudioDirs(mod, out);
        }
    }

    /** 在 `~/Zomboid/Workshop/<item>/Contents/mods` 下找。 */
    private static void collectUnderItemRoots(File workshopRoot, List<File> out) {
        if (workshopRoot == null || !workshopRoot.isDirectory()) {
            return;
        }
        File[] items = workshopRoot.listFiles(File::isDirectory);
        if (items == null) {
            return;
        }
        for (File item : items) {
            collectUnderMods(new File(item, "Contents/mods"), out);
        }
    }

    /** 一个模组目录：自己或一级子目录下的 media/voxel-studio。 */
    private static void collectVoxelStudioDirs(File modDir, List<File> out) {
        if (modDir == null || !modDir.isDirectory()) {
            return;
        }
        File direct = new File(modDir, "media/voxel-studio");
        if (direct.isDirectory()) {
            out.add(direct);
            return;
        }
        File[] subs = modDir.listFiles(File::isDirectory);
        if (subs == null) {
            return;
        }
        for (File sub : subs) {
            File candidate = new File(sub, "media/voxel-studio");
            if (candidate.isDirectory()) {
                out.add(candidate);
            }
        }
    }

    /** @return 该 package 里成功登记的 model 条目数 */
    private static int loadPackage(File propsFile, File baseDir) {
        Properties props = new Properties();
        try (InputStream in = new FileInputStream(propsFile)) {
            props.load(in);
        } catch (Throwable t) {
            Vp.warn("voxel pack: cannot read " + propsFile + " (" + t + ")");
            return 0;
        }
        // 先把 model.<key> 收成表，再解析 bind.<sprite>
        Map<String, String> models = new HashMap<>();
        for (String key : props.stringPropertyNames()) {
            if (key.startsWith("model.")) {
                models.put(key.substring("model.".length()), props.getProperty(key).trim());
            }
        }
        int added = 0;
        for (String key : props.stringPropertyNames()) {
            if (!key.startsWith("bind.")) {
                continue;
            }
            String spriteName = key.substring("bind.".length());
            if (BINDS.containsKey(spriteName)) {
                continue;
            }
            String[] parts = props.getProperty(key).split(",");
            if (parts.length < 1) {
                continue;
            }
            String modelKey = parts[0].trim();
            String relative = models.get(modelKey);
            if (relative == null) {
                continue;
            }
            float rotation = parts.length > 1 ? parseFloat(parts[1]) : 0f;
            float ox = parts.length > 2 ? parseFloat(parts[2]) : 0f;
            float oy = parts.length > 3 ? parseFloat(parts[3]) : 0f;
            float oz = parts.length > 4 ? parseFloat(parts[4]) : 0f;
            float scale = parts.length > 5 ? parseFloat(parts[5]) : 1f;
            if (scale <= 0f) {
                scale = 1f;
            }
            String path = new File(baseDir, relative).getAbsolutePath();
            BINDS.put(spriteName, new Bind(spriteName, path, rotation, ox, oy, oz, scale));
            added++;
        }
        return added;
    }

    private static float parseFloat(String text) {
        try {
            return Float.parseFloat(text.trim());
        } catch (Throwable t) {
            return 0f;
        }
    }

    public static String describe() {
        scan();
        return scanReport + (LOADED_FROM.isEmpty()
            ? ""
            : " from=" + LOADED_FROM.get(0) + (LOADED_FROM.size() > 1 ? " (+" + (LOADED_FROM.size() - 1) + ")" : ""));
    }

    /** 供 UI/报告列出所有来源目录。 */
    public static List<String> sources() {
        scan();
        return Collections.unmodifiableList(LOADED_FROM);
    }

    private VoxelPack() {
    }
}
