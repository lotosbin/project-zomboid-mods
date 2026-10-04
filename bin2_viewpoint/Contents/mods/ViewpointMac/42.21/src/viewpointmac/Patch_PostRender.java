package viewpointmac;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * 挂载游戏渲染线程的帧边界。
 *
 * <p>目标方法 {@code zombie.core.SpriteRenderer#postRender()} 是渲染线程真正提交本帧
 * 所有绘制的地方（方法尾部调用 {@code SpriteRenderer$RingBuffer.render()}），
 * 方法返回时画面还没交换——这就是我们叠加自绘内容的最佳位置。
 *
 * <p>只做"调用转发"，逻辑全部放在 {@link RenderHook}，这样即使钩子出问题也能一处关闭。
 */
@Patch(className = "zombie.core.SpriteRenderer", methodName = "postRender")
public class Patch_PostRender {

    @Patch.OnEnter
    public static void enter() {
        RenderHook.onFrameEnter();
    }

    @Patch.OnExit
    public static void exit() {
        RenderHook.onFrameExit();
    }
}
