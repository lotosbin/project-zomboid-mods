// Project Zomboid 创意工坊上传链路自检（不触发上传）
//
// 作用：把 SteamWorkshop.SubmitWorkshopItem() 里的 native 调用逐个执行一遍，
//       唯独不调 n_SubmitItemUpdate —— 因此不会真的上传任何东西，却能证明
//       "StartItemUpdate / SetItemContent / SetItemPreview ... 在这台机器上是可用的"。
//
// 用途：用来区分"确认框返回值导致 submitUpdate() 返回 false"（本仓库修复的 bug）
//       和"后面的 native 调用本身就失败"（另一种可能，本机实测不存在）。
//
// 编译（需要 JDK ≥ 游戏版本，B42.21 是 Java 25）：
//     javac -cp "/path/to/projectzomboid.jar" -d out WorkshopProbe.java
// 运行：见同目录 run.sh
//
// 输出参考（macOS 42.21 实测）：
//     StartItemUpdate       = true
//     SetItemTitle          = true
//     SetItemDescription    = true
//     SetItemVisibility     = true
//     SetItemTags           = true
//     SetItemContent        = true
//     SetItemPreview        = true
//     STOP before SubmitItemUpdate (no upload performed)

import java.lang.reflect.Method;

import zombie.core.znet.SteamUtils;
import zombie.core.znet.SteamWorkshop;
import zombie.core.znet.SteamWorkshopItem;

public class WorkshopProbe {

    /** 反射调用 SteamWorkshop 的 private native n_XXX。 */
    static Object call(SteamWorkshop sw, String name, Class<?>[] sig, Object... args) throws Exception {
        Method m = SteamWorkshop.class.getDeclaredMethod(name, sig);
        m.setAccessible(true);
        try {
            return m.invoke(sw, args);
        } catch (java.lang.reflect.InvocationTargetException e) {
            return "EXCEPTION: " + e.getCause();
        }
    }

    public static void main(String[] args) throws Exception {
        String javaDir = require("PZ_JAVA_DIR");        // 游戏的 Contents/Java（或 Linux 游戏根目录）
        String folder = require("PZ_WS_FOLDER");        // ~/Zomboid/Workshop/<待上传的模组目录>
        String libName = System.getProperty("os.name", "").toLowerCase().contains("win") ? null
                : (System.getProperty("os.name", "").toLowerCase().contains("mac")
                   ? "/libZNetJNI.dylib" : "/libZNetJNI.so");
        if (libName != null) {
            System.load(javaDir + libName);
            System.out.println("native lib loaded: " + javaDir + libName);
        }

        zombie.ZomboidFileSystem.instance.init();
        SteamUtils.init();
        System.out.println("steamMode=" + SteamUtils.isSteamModeEnabled());
        if (!SteamUtils.isSteamModeEnabled()) {
            System.out.println("Steam 未初始化（Steam 客户端没开 / steam_appid.txt 不在工作目录），退出。");
            return;
        }
        SteamWorkshop.init();

        SteamWorkshop sw = SteamWorkshop.instance;
        SteamWorkshopItem item = new SteamWorkshopItem(folder);
        System.out.println("readWorkshopTxt       = " + item.readWorkshopTxt());
        String itemId = item.getID();
        System.out.println("id                    = " + itemId
                + (itemId != null ? "  valid=" + SteamUtils.isValidSteamID(itemId) : "  (未发布：workshop.txt 里没有 id=)"));
        System.out.println("title                 = " + item.getTitle());
        System.out.println("visibility            = " + item.getVisibilityInteger());
        System.out.println("tags                  = " + java.util.Arrays.toString(item.getTags().toArray()));
        System.out.println("description           = " + item.getDescription().length() + " chars");
        System.out.println("submitDescription     = " + item.getSubmitDescription().length() + " chars (游戏会再追加 Workshop ID / Mod ID 行)");
        System.out.println("contentFolder         = " + item.getContentFolder()
                + "  exists=" + new java.io.File(item.getContentFolder()).isDirectory());
        System.out.println("previewImage          = " + item.getPreviewImage()
                + "  exists=" + new java.io.File(item.getPreviewImage()).isFile());
        System.out.println("validatePreviewImage  = " + validatePreview(item)
                + "   (规则: 存在/可读 + <=1024000 字节 + 正方形且边长 256 或 512 + PNG)");
        if (itemId == null) {
            System.out.println("该目录的 workshop.txt 里没有 id=，无法测试更新路径（新建物品后向导会写回 id=）。");
            return;
        }

        long id = SteamUtils.convertStringToSteamID(itemId);
        System.out.println("steamID               = " + id);
        System.out.println("StartItemUpdate       = " + call(sw, "n_StartItemUpdate", new Class<?>[]{long.class}, id));
        System.out.println("SetItemTitle          = " + call(sw, "n_SetItemTitle", new Class<?>[]{String.class}, item.getTitle()));
        System.out.println("SetItemDescription    = " + call(sw, "n_SetItemDescription", new Class<?>[]{String.class}, item.getSubmitDescription()));
        System.out.println("SetItemVisibility     = " + call(sw, "n_SetItemVisibility", new Class<?>[]{int.class}, item.getVisibilityInteger()));
        System.out.println("SetItemTags           = " + call(sw, "n_SetItemTags", new Class<?>[]{String[].class}, (Object) item.getSubmitTags()));
        System.out.println("SetItemContent        = " + call(sw, "n_SetItemContent", new Class<?>[]{String.class}, item.getContentFolder()));
        System.out.println("SetItemPreview        = " + call(sw, "n_SetItemPreview", new Class<?>[]{String.class}, item.getPreviewImage()));
        System.out.println("STOP before SubmitItemUpdate (no upload performed)");
    }

    /** 用游戏自己的校验器检查 preview.png（返回 null 表示通过）。 */
    private static String validatePreview(SteamWorkshopItem item) {
        try {
            String err = item.validatePreviewImage(java.nio.file.Paths.get(item.getPreviewImage()));
            return err == null ? "OK" : err;
        } catch (Throwable t) {
            return "EXCEPTION: " + t;
        }
    }

    private static String require(String env) {
        String v = System.getenv(env);
        if (v == null || v.isEmpty()) {
            System.err.println("缺少环境变量 " + env);
            System.exit(2);
        }
        return v;
    }
}
