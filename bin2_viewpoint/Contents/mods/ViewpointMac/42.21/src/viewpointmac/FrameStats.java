package viewpointmac;

/**
 * 帧时间统计：在渲染线程的帧边界上采样，供覆盖层柱状图与 Lua 状态查询使用。
 *
 * <p>刻意保持无锁：写入只发生在渲染线程，读取方（Lua / 报告）容忍读到略旧的数值。
 */
public final class FrameStats {

    private static final int CAPACITY = 240;

    private static final float[] FRAME_MS = new float[CAPACITY];
    private static volatile int head = 0;
    private static volatile int filled = 0;

    private static long lastEnterNanos = 0L;
    private static long lastExitNanos = 0L;

    /** 我们自己的覆盖层绘制耗时（毫秒，指数平滑）。 */
    private static volatile float overlayMs = 0f;

    /** 累计帧数，用于"探针前不统计"之类的判断。 */
    private static volatile long frames = 0L;

    public static void onFrameEnter() {
        long now = System.nanoTime();
        if (lastEnterNanos != 0L) {
            float ms = (now - lastEnterNanos) / 1_000_000f;
            if (ms >= 0f && ms < 10_000f) {
                FRAME_MS[head] = ms;
                head = (head + 1) % CAPACITY;
                if (filled < CAPACITY) {
                    filled++;
                }
            }
        }
        lastEnterNanos = now;
        frames++;
    }

    public static void onFrameExit(long drawStartedNanos) {
        lastExitNanos = System.nanoTime();
        if (drawStartedNanos != 0L) {
            float ms = (lastExitNanos - drawStartedNanos) / 1_000_000f;
            overlayMs = overlayMs <= 0f ? ms : (overlayMs * 0.9f + ms * 0.1f);
        }
    }

    public static long frames() {
        return frames;
    }

    public static float overlayMs() {
        return overlayMs;
    }

    /** 最近一帧的帧时间（毫秒），没有样本时返回 0。 */
    public static float lastFrameMs() {
        if (filled == 0) {
            return 0f;
        }
        int index = (head - 1 + CAPACITY) % CAPACITY;
        return FRAME_MS[index];
    }

    /** 平均帧率（按最近的样本窗口计算）。 */
    public static float fps() {
        if (filled == 0) {
            return 0f;
        }
        float sum = 0f;
        for (int i = 0; i < filled; i++) {
            sum += FRAME_MS[i];
        }
        float avg = sum / filled;
        return avg <= 0f ? 0f : 1000f / avg;
    }

    /** 最近样本中的最大值（毫秒），用于柱状图归一化。 */
    public static float maxFrameMs() {
        float max = 1f;
        for (int i = 0; i < filled; i++) {
            if (FRAME_MS[i] > max) {
                max = FRAME_MS[i];
            }
        }
        return max;
    }

    public static int sampleCount() {
        return filled;
    }

    /** 第 index 个样本（0 = 最旧），越界返回 0。 */
    public static float sample(int index) {
        if (index < 0 || index >= filled) {
            return 0f;
        }
        int start = (head - filled + CAPACITY) % CAPACITY;
        return FRAME_MS[(start + index) % CAPACITY];
    }

    public static String describe() {
        return String.format(java.util.Locale.ROOT,
            "fps=%.1f last=%.2fms avgWindow=%d frames=%d overlay=%.3fms",
            fps(), lastFrameMs(), filled, frames, overlayMs);
    }

    private FrameStats() {
    }
}
