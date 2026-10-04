package viewpointmac;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * 标记"当前正处于原版世界绘制阶段"（1.9）。
 *
 * <p>**只设置一个标志位，不跳过任何东西** —— 用来把"世界里的角色模型绘制"
 * 和"UI/背包里的角色预览"区分开：我们只想在世界阶段接管角色绘制，
 * 背包纸娃娃、主菜单那些地方的 3D 角色必须保持原样。
 */
@Patch(className = "zombie.core.SpriteRenderer", methodName = "buildStateDrawBuffer")
public class Patch_WorldPassFlag {

    @Patch.OnEnter
    public static void enter() {
        CharacterModels.setWorldPass(true);
    }

    @Patch.OnExit
    public static void exit() {
        CharacterModels.setWorldPass(false);
    }
}
