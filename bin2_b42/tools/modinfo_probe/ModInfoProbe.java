// 用**游戏自己的解析器**读 bin2_b42 各模组的 mod.info（不启动游戏、不碰 Steam、不改游戏目录）。
//
// 为什么需要它：`versionMin=` / `versionMax=` 是**硬门禁** ——
//
//   ChooseGameInfo$Mod.isAvailableSelf():
//       versionMin != null && versionMin.isGreaterThan(游戏版本)  → 返回 false（模组不可用）
//       versionMax != null && versionMax.isLessThan(游戏版本)     → 返回 false
//
// 也就是说 versionMin 写高了，玩家那边表现是"模组整条变红/不可勾选"，而不是配方消失 ——
// 离线看语法（mod.info 是 key=value）和看配方都发现不了。另外版本子目录（42.19.0/ 这种）由
// ZomboidFileSystem.getModVersionDirName 挑：只接受 **≥ 游戏自身的 minRequiredVersion(42.0.0)
// 且 ≤ 当前游戏版本** 的目录名，取其中最大者，所以目录名留在 42.19.0 也能被 42.21 的客户端加载。
//
// 入口用 ChooseGameInfo.readModInfo(dir)（吃**目录路径**）：这样校验的是仓库里的这一份，
// 而不是 Steam 工坊已发布的那一份（两者版本可能不同）。注意 headless 下传模组 id 会返回 null。
//
// 额外做一次"降版模拟"：用反射把 Core 的 gameVersion 临时改成 versionMin 低一个小版本，
// 再问一次 isAvailableSelf()，确认旧客户端上确实会关掉 —— 单向的"现在的版本能加载"不足以
// 证明门禁生效。
import java.lang.reflect.Field;

import zombie.core.Core;
import zombie.core.GameVersion;
import zombie.gameStates.ChooseGameInfo;

public class ModInfoProbe {

    public static void main(String[] args) throws Exception {
        zombie.ZomboidFileSystem.instance.init();

        // 可选：--game=42.20.0 —— 在读 mod.info **之前**改写游戏版本，用来回答
        // "旧客户端上会挑中哪个版本子目录、这门禁放不放行"（版本子目录是在读 mod.info 时定的，
        // 所以必须在读之前改）。不带这个参数就是本机真实版本。
        java.util.ArrayList<String> dirs = new java.util.ArrayList<>();
        for (String arg : args) {
            if (arg.startsWith("--game=")) {
                GameVersion fake = GameVersion.parse(arg.substring("--game=".length()).trim());
                setGameVersion(fake);
                System.out.println("(模拟客户端版本: " + fake + "，int=" + fake.getInt() + ")");
            } else {
                dirs.add(arg);
            }
        }

        int bad = 0;
        for (String dir : dirs) {
            ChooseGameInfo.Mod mod = ChooseGameInfo.readModInfo(dir);
            if (mod == null) {
                System.out.println("### " + dir + " : readModInfo -> null（目录布局或 mod.info 有问题）");
                bad++;
                continue;
            }
            GameVersion game = Core.getInstance().getGameVersion();
            System.out.println("### " + mod.getId() + "  (" + mod.getName() + ")");
            System.out.println("    versionDir    = " + mod.getVersionDir());
            System.out.println("    modversion    = " + mod.getModVersion());
            System.out.println("    versionMin    = " + describe(mod.getVersionMin())
                    + "   versionMax = " + describe(mod.getVersionMax()));
            System.out.println("    game          = " + game + " (int=" + game.getInt() + ")  → availableSelf="
                    + mod.isAvailableSelf());
            GameVersion below = oneMinorBelow(mod.getVersionMin());
            if (below != null) {
                setGameVersion(below);
                boolean available = mod.isAvailableSelf();
                setGameVersion(game);
                System.out.println("    模拟旧客户端  = " + below + " (int=" + below.getInt() + ")  → availableSelf="
                        + available + (available ? "   !! versionMin 没起作用?" : "   (符合预期：旧版本上模组不可用)"));
            }
        }
        System.out.println(bad == 0 ? "ALL MOD.INFO OK" : bad + " MOD DIR(S) FAILED");
        System.exit(bad == 0 ? 0 : 1);
    }

    private static String describe(GameVersion v) {
        return v == null ? "(none)" : v + " (int=" + v.getInt() + ")";
    }

    /** versionMin 低一个小版本（42.21.0 → 42.20.0），用来模拟"版本不够的客户端" */
    private static GameVersion oneMinorBelow(GameVersion v) {
        if (v == null || v.getMinor() == 0) {
            return null;
        }
        return new GameVersion(v.getMajor(), v.getMinor() - 1, "");
    }

    /** Core.gameVersion 是 private static final；反射 + sun.misc.Unsafe 直接改写静态字段，读完立刻还原 */
    private static void setGameVersion(GameVersion v) throws Exception {
        Field field = Core.class.getDeclaredField("gameVersion");
        Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
        Field theUnsafe = unsafeClass.getDeclaredField("theUnsafe");
        theUnsafe.setAccessible(true);
        Object unsafe = theUnsafe.get(null);
        Object base = unsafeClass.getMethod("staticFieldBase", Field.class).invoke(unsafe, field);
        long offset = (Long) unsafeClass.getMethod("staticFieldOffset", Field.class).invoke(unsafe, field);
        unsafeClass.getMethod("putObject", Object.class, long.class, Object.class)
                .invoke(unsafe, base, offset, v);
    }
}
