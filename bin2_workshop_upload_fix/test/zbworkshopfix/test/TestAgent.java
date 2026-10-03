package zbworkshopfix.test;

import java.lang.instrument.Instrumentation;

/**
 * 只为离线自测提供 {@link Instrumentation}（ZombieBuddy 的 PatchTransformer 需要一个）。
 * 加在目标 JVM 里：{@code -javaagent:testagent.jar}
 */
public final class TestAgent {

    public static volatile Instrumentation instrumentation;

    private TestAgent() {}

    public static void premain(String args, Instrumentation inst) {
        instrumentation = inst;
    }
}
