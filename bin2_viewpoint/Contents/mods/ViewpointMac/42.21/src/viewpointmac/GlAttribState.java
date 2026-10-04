package viewpointmac;

import org.lwjgl.opengl.GL20;

/**
 * 顶点属性状态的保存/恢复守卫。
 *
 * <p>macOS 上游戏用的是 GL 2.1 兼容上下文，**没有 core profile 的 VAO**，
 * 因此 {@code glVertexAttribPointer} 改的是全局属性状态。如果自绘内容点亮了某个属性槽位
 * 却不还原，游戏后续的绘制就会拿着我们的 VBO 当顶点数据用 —— 表现就是"游戏画面全黑、
 * 只有我们的覆盖层还在"。
 *
 * <p>本类配合"把自有着色器的属性钉到高位槽位（14/15）"使用：游戏自己的着色器只用 0~3 号，
 * 所以只需要把高位槽位的**启用状态**还原即可（槽位本身游戏不会碰）。
 */
public final class GlAttribState {

    private final int[] indices;
    private final boolean[] enabled;

    public GlAttribState(int... indices) {
        this.indices = indices.clone();
        this.enabled = new boolean[indices.length];
    }

    /** 在改动属性状态之前调用。 */
    public void save() {
        for (int i = 0; i < indices.length; i++) {
            try {
                enabled[i] = GL20.glGetVertexAttribi(indices[i], GL20.GL_VERTEX_ATTRIB_ARRAY_ENABLED) != 0;
            } catch (Throwable t) {
                enabled[i] = false;
            }
        }
    }

    /** 绘制结束后调用，把启用状态原样放回去。 */
    public void restore() {
        for (int i = 0; i < indices.length; i++) {
            try {
                if (enabled[i]) {
                    GL20.glEnableVertexAttribArray(indices[i]);
                } else {
                    GL20.glDisableVertexAttribArray(indices[i]);
                }
            } catch (Throwable ignored) {
                // 恢复失败不该影响游戏，交由上层的熔断计数处理
            }
        }
    }

    /** 供日志/报告展示。 */
    public String describe() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < indices.length; i++) {
            if (i > 0) {
                sb.append(", ");
            }
            sb.append(indices[i]).append('=').append(enabled[i] ? "on" : "off");
        }
        return sb.toString();
    }
}
