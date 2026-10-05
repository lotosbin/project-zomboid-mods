// 用**游戏自己的解析器**验证本物品三个模组的 mod.info（不启动游戏、不碰 Steam）。
//
// 为什么需要它：拆成"公共层 + 口味"之后，口味的 mod.info 多了一条
// require=\Bin2NPCExtensionBase。这条依赖写错（id 拼错 / 目录名不一致）时，
// 玩家那边表现为"模组不可用"，而离线检查（语法、测试、生成器一致性）都看不出来。
//
// 入口是 ChooseGameInfo.getModDetails(id)（注意：headless 下 readModInfo(id) 不走模组目录
// 扫描，会返回 null，别用错）。校验：
//   1. 这个 id 能被解析出来（= 目录布局与 mod.info 都合法），并打印 name/modversion；
//   2. require= / loadModAfter= 是否被正确解析成列表；
//   3. 每个依赖能否解析成模组（公开的第三方依赖若没本地目录，这里会显示 unknown —— 见 run.sh 的说明）。
import zombie.gameStates.ChooseGameInfo;
import java.util.ArrayList;

public class ModInfoProbe {
    public static void main(String[] args) throws Exception {
        zombie.ZomboidFileSystem.instance.init();
        int missing = 0;
        for (String id : args) {
            ChooseGameInfo.Mod mod = ChooseGameInfo.getModDetails(id);
            if (mod == null) {
                System.out.println("MISSING  " + id + "   (getModDetails returned null)");
                missing++;
                continue;
            }
            System.out.printf("OK   %-46s id=%-24s ver=%-7s%n",
                    mod.getName(), mod.getId(), mod.getModVersion());
            System.out.println("       require   = " + describe(mod.getRequire()));
            System.out.println("       loadAfter = " + describe(mod.getLoadAfter()));
        }
        System.out.println(missing == 0 ? "ALL MOD.INFO PARSED" : missing + " mod.info NOT FOUND");
        System.exit(missing == 0 ? 0 : 1);
    }

    /** 把依赖列表逐项解析，标出哪些是游戏能认出来的模组。 */
    private static String describe(ArrayList<String> deps) {
        if (deps == null || deps.isEmpty()) return "(none)";
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < deps.size(); i++) {
            String dep = deps.get(i);
            boolean known = ChooseGameInfo.getModDetails(dep) != null;
            if (i > 0) out.append(", ");
            out.append(dep).append(known ? "[ok]" : "[unknown-locally]");
        }
        return out.toString();
    }
}
