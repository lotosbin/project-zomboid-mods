package viewpointmac;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * 接管世界阶段的原版角色模型绘制（1.9）。
 *
 * <p>{@code TextureDraw.DrawQueued(TextureDraw, ModelSlot)} 是**真正发 GL 调用的地方**
 * （准备与状态记账在调用方 {@code GenericSpriteRenderState.drawQueued} 里，所以跳过它
 * 不会破坏 {@code renderRefCount} / {@code numSprites} / {@code postRender} 的记账）。
 *
 * <p>只有当"我们的相机已经装上、并且正在我们自己的绘制里"时才会跳过，
 * 否则一律返回 false，原版照常渲染 —— 任何一步没准备好都不会让角色消失。
 */
@Patch(className = "zombie.core.textures.TextureDraw", methodName = "DrawQueued")
public class Patch_SkipVanillaDraw {

    @Patch.OnEnter(skipOn = true)
    public static boolean enter() {
        try {
            return CharacterModels.shouldSkipVanillaDraw();
        } catch (Throwable t) {
            return false;
        }
    }
}
