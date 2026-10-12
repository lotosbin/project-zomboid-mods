// 用**游戏自己的脚本解析器**校验 craftRecipe(不启动游戏、不碰 Steam)。
//
// 为什么需要它:Lua/JSON/正则检查都看不出 B42 配方脚本的真实语义 ——
//   · `-fluid 0.5 categories[Water] mode:mixture` 到底有没有被引擎收下(还是被静默丢掉)
//   · `mode:keep` / `flags[...]` 解析成了什么(keep?destroy?itemCount?notEmpty?)
//   · 引用的物品 fullType 在游戏里是否存在
// 这些只有引擎自己的解析器说了算。本探针把 ScriptManager.Load() 跑在 headless 下
// (需要先手动初始化 RandStandard 与 Bullet,否则 ScriptManager.Load() 会在
//  ServerOptions / 车辆脚本处抛异常),再按 fullType 取回 CraftRecipe 并逐行打印。
//
// 注意:配方脚本必须处在引擎会扫描的目录里才会被 Load() 收下 —— 见 run.sh(临时复制 + 退出时删除)。
//
// 打印的每一行都来自 CraftRecipe 内部的 ioLines(含流体行;公开的 getInputs() 不含流体行),
// 所以这里用反射读 private 字段 ioLines,而不是 getInputs()。
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import zombie.ZomboidFileSystem;
import zombie.core.random.RandStandard;
import zombie.scripting.ScriptManager;
import zombie.scripting.entity.components.crafting.CraftRecipe;
import zombie.scripting.entity.components.crafting.InputScript;
import zombie.scripting.entity.components.crafting.OutputScript;

public class RecipeProbe {

    /** 配方行里出现的 module.Item 形式 fullType */
    private static final Pattern FULL_TYPE =
            Pattern.compile("\\b([A-Za-z_][A-Za-z0-9_]*\\.[A-Za-z_][A-Za-z0-9_]*)\\b");

    public static void main(String[] args) throws Exception {
        ZomboidFileSystem.instance.init();
        RandStandard.INSTANCE.init();   // 否则 ServerOptions.<clinit> NPE
        zombie.core.physics.Bullet.init(); // 否则车辆脚本 defineVehicleScript UnsatisfiedLinkError
        ScriptManager.instance.Load();

        System.out.println("引擎载入的 craftRecipe 总数: " + ScriptManager.instance.getAllCraftRecipes().size());

        int missing = 0;
        int unknownFullTypes = 0;
        for (String name : args) {
            CraftRecipe recipe = find(name);
            if (recipe == null) {
                System.out.println("### " + name + " : NOT FOUND");
                missing++;
                continue;
            }
            System.out.println("### " + name + " : OK  fullType=" + recipe.getScriptObjectFullType()
                    + " time=" + recipe.getTime() + " category=" + recipe.getCategory()
                    + " tags=" + recipe.getTags());
            List<?> ioLines = ioLines(recipe);
            System.out.println("    ioLines=" + ioLines.size() + " (itemInputs=" + recipe.getInputCount()
                    + " outputs=" + recipe.getOutputCount() + ")");
            for (Object line : ioLines) {
                if (line instanceof InputScript) {
                    InputScript in = (InputScript) line;
                    System.out.println("    IN  [" + in.getResourceType() + "] " + in.getOriginalLine());
                    System.out.println("         keep=" + in.isKeep() + " destroy=" + in.isDestroy()
                            + " itemCount=" + in.isItemCount() + " notEmpty=" + in.notEmpty()
                            + " isEmpty=" + in.isEmpty() + " fluidMode=" + in.getFluidMatchMode()
                            + " amount=" + in.getAmount());
                    unknownFullTypes += checkFullTypes(in.getOriginalLine());
                } else if (line instanceof OutputScript) {
                    OutputScript out = (OutputScript) line;
                    System.out.println("    OUT [" + out.getResourceType() + "] " + out.getOriginalLine());
                    unknownFullTypes += checkFullTypes(out.getOriginalLine());
                }
            }
        }
        if (unknownFullTypes > 0) {
            System.out.println("提示: " + unknownFullTypes + " 个 fullType 在本探针里查不到 —— "
                    + "若它们来自另一个 mod(探针没加载那些 mod),属正常;若是原版物品 ID,就是拼错了。");
        }
        System.out.println(missing == 0 ? "ALL RECIPES PARSED" : missing + " RECIPE(S) NOT FOUND");
        System.exit(missing == 0 ? 0 : 1);
    }

    /** 先按 fullType 查,再退化为按后缀匹配(脚本里写的是裸 RecipeID) */
    private static CraftRecipe find(String name) {
        CraftRecipe recipe = ScriptManager.instance.getCraftRecipe(name);
        if (recipe != null) {
            return recipe;
        }
        for (CraftRecipe candidate : ScriptManager.instance.getAllCraftRecipes()) {
            if (candidate.getName().endsWith(name)) {
                return candidate;
            }
        }
        return null;
    }

    /** CraftRecipe 的 private ioLines:含流体输入行,公开的 getInputs() 不含 */
    private static List<?> ioLines(CraftRecipe recipe) throws Exception {
        Field field = CraftRecipe.class.getDeclaredField("ioLines");
        field.setAccessible(true);
        Object value = field.get(recipe);
        return (value instanceof List) ? (List<?>) value : new ArrayList<>();
    }

    /** 校验行里出现的 fullType(物品或流体)是否真实存在 */
    private static int checkFullTypes(String line) {
        int unknown = 0;
        Matcher matcher = FULL_TYPE.matcher(line);
        while (matcher.find()) {
            String fullType = matcher.group(1);
            if (ScriptManager.instance.getItem(fullType) != null) {
                continue;
            }
            if (ScriptManager.instance.getFluidDefinitionScript(fullType) != null) {
                continue;
            }
            System.out.println("         !! UNKNOWN fullType: " + fullType);
            unknown++;
        }
        return unknown;
    }
}
