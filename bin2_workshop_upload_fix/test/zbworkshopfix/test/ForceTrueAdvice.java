package zbworkshopfix.test;

import net.bytebuddy.asm.Advice;

/**
 * 最小对照advice：只证明"@OnExit + @Return(readOnly=false) boolean"能把返回值改写掉
 * （这正是我们补丁赖以生效的机制）。
 */
public final class ForceTrueAdvice {

    @Advice.OnMethodExit
    public static void exit(@Advice.Return(readOnly = false) boolean result) {
        if (!result) {
            result = true;
        }
    }

    private ForceTrueAdvice() {}
}
