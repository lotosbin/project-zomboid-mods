// 用**游戏自己的模组信息**回答一个具体问题：
// 带版本号子目录的模组（<mod>/42.21/media/...）里放贴图，引擎到底从哪个目录去找？
//
// 背景：原版侧边栏的贴图路径是拼出来的
//     media/ui/Sidebar/<尺寸>/<名字>_<On|Off>_<尺寸>.png
// （ISEquippedItem.lua:620-660），而我们的模组把 media/ui 放在 42.21/media/ui/ 下。
// 找不到就是游戏里一个空白按钮，而离线检查（语法/测试/生成器一致性）看不出来。
//
// 证据来源：ChooseGameInfo$Mod 上就带着引擎解析出来的目录
//     public java.lang.String dir;        // 模组根
//     public java.lang.String versionDir; // 版本子目录（B42 的 42.21）
//     public final PZModFolder mediaFile; // media 的两套：common（模组根）/ version（版本子目录）
// 所以这里直接问引擎："media/ui/... 在哪个目录下？" —— 再用 java.io.File 确认真的存在。
import java.io.File;
import java.util.ArrayList;

public class TextureProbe {
    public static void main(String[] args) throws Exception {
        zombie.ZomboidFileSystem.instance.init();

        if (args.length > 0 && args[0].equals("--folders")) {
            ArrayList<String> modFolders = new ArrayList<String>();
            zombie.ZomboidFileSystem.instance.getAllModFolders(modFolders);
            System.out.println("mod folders seen by the engine (" + modFolders.size() + "):");
            for (String folder : modFolders) System.out.println("   " + folder);
            System.out.println();
            return;
        }

        // 第一个参数是 mod id，其余参数是它下面的相对路径
        String modId = args[0];
        zombie.gameStates.ChooseGameInfo.Mod mod = zombie.gameStates.ChooseGameInfo.getModDetails(modId);
        if (mod == null) {
            System.out.println("MISSING MOD " + modId);
            System.exit(1);
        }
        System.out.println("mod        : " + mod.getId());
        System.out.println("dir        : " + mod.getDir());
        System.out.println("versionDir : " + mod.getVersionDir());
        System.out.println("media.common  : " + describe(mod.mediaFile, false));
        System.out.println("media.version : " + describe(mod.mediaFile, true));
        System.out.println();

        int missing = 0;
        for (int i = 1; i < args.length; i++) {
            String path = args[i];
            File found = null;
            String how = null;
            File versionRoot = mod.mediaFile != null && mod.mediaFile.version != null
                    ? mod.mediaFile.version.absoluteFile : null;
            File commonRoot = mod.mediaFile != null && mod.mediaFile.common != null
                    ? mod.mediaFile.common.absoluteFile : null;
            if (versionRoot != null) {
                File candidate = new File(versionRoot, path);
                if (candidate.isFile()) { found = candidate; how = "media.version"; }
            }
            if (found == null && commonRoot != null) {
                File candidate = new File(commonRoot, path);
                if (candidate.isFile()) { found = candidate; how = "media.common"; }
            }
            if (found == null) {
                System.out.println("MISSING  " + path);
                missing++;
            } else {
                System.out.printf("OK   %-52s %8d bytes  <- %s (%s)%n",
                        path, found.length(), found.getAbsolutePath(), how);
            }
        }
        System.out.println(missing == 0 ? "ALL PATHS RESOLVED" : missing + " PATH(S) NOT FOUND");
        System.exit(missing == 0 ? 0 : 1);
    }

    private static String describe(zombie.ZomboidFileSystem.PZModFolder folder, boolean version) {
        if (folder == null) return "(null PZModFolder)";
        zombie.ZomboidFileSystem.PZFolder part = version ? folder.version : folder.common;
        if (part == null || part.absoluteFile == null) return "(absent)";
        return part.absoluteFile.getAbsolutePath();
    }
}
