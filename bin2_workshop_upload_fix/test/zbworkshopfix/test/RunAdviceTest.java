package zbworkshopfix.test;

import com.lotosbin.zbworkshopfix.Patch_SteamWorkshopItem;

import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Method;

import static net.bytebuddy.matcher.ElementMatchers.named;

/**
 * 离线自测：不做任何上传，只验证 ZombieBuddy 的补丁机制对我们这个补丁类成立。
 *
 * <p>验证三件事：
 * <ol>
 *   <li>ZombieBuddy 的 {@code PatchTransformer} 能把我们的 {@code @Patch.*} 别名注解翻译成
 *       ByteBuddy 的 {@code Advice.*}，并被 ByteBuddy 接受（翻译/应用不报错）；</li>
 *   <li>它不是"跳过原方法"的补丁：原方法照常执行（确认框仍然会弹）；</li>
 *   <li>{@code @OnExit + @Return(readOnly=false) boolean} 确实能改写返回值（补丁生效的机制）。</li>
 * </ol>
 *
 * 运行：{@code java -javaagent:testagent.jar -cp ... zbworkshopfix.test.RunAdviceTest}
 */
public final class RunAdviceTest {

    private static int failures = 0;

    public static void main(String[] args) throws Exception {
        if (TestAgent.instrumentation == null) {
            System.out.println("缺少 -javaagent:testagent.jar");
            System.exit(2);
        }

        // ---- 1) 用 ZombieBuddy 自己的 PatchTransformer 翻译我们的补丁类 --------------
        Class<?> patchClass = transformWithZombieBuddy(
            Patch_SteamWorkshopItem.Patch_submitUpdate.class, TestAgent.instrumentation);
        check("PatchTransformer 返回补丁类", patchClass != null
            && patchClass.getName().endsWith("Patch_submitUpdate"));
        check("补丁方法上出现了 ByteBuddy 的 @OnMethodExit",
            hasAnnotation(patchClass, "net.bytebuddy.asm.Advice$OnMethodExit"));

        // ---- 2) 把补丁挂到假目标上，调用它 -----------------------------------------
        String log = capture(() -> {
            Object target = applyAdvice(patchClass);
            boolean result = (boolean) target.getClass().getMethod("submitUpdate").invoke(target);
            System.out.println("[test] 假目标 submitUpdate() -> " + result);
            boolean originalRan = (boolean) target.getClass().getField("originalRan").get(target);
            check("原方法没有被跳过（确认框仍会弹）", originalRan);
            return null;
        });
        check("补丁代码确实执行了（打出了 ZBWorkshopUploadFix 日志）",
            log.contains("[ZBWorkshopUploadFix]"));
        check("假目标不是 SteamWorkshopItem，异常被兜住且返回 false",
            log.contains("SubmitWorkshopItem threw"));

        // ---- 3) 对照：证明 @Return(readOnly=false) 能改写 boolean 返回值 -------------
        Object forced = new ByteBuddy()
            .redefine(DummyTarget.class)
            .visit(Advice.to(ForceTrueAdvice.class).on(named("submitUpdate")))
            .make()
            .load(DummyTarget.class.getClassLoader(), ClassLoadingStrategy.Default.CHILD_FIRST)
            .getLoaded()
            .getDeclaredConstructor()
            .newInstance();
        boolean forcedResult = (boolean) forced.getClass().getMethod("submitUpdate").invoke(forced);
        check("对照组：返回值被 @Return(readOnly=false) 改写为 true", forcedResult);

        System.out.println(failures == 0 ? "\n== ALL CHECKS PASSED ==" : "\n== " + failures + " CHECK(S) FAILED ==");
        System.exit(failures == 0 ? 0 : 1);
    }

    /**
     * 调用 ZombieBuddy 内部的 {@code PatchTransformer.transformPatchClass(...)}（它是包私有的，
     * 所以这里用反射；它会把 {@code @Patch.*} 别名注解在字节码里替换成 ByteBuddy 的 {@code @Advice.*}）。
     */
    private static Class<?> transformWithZombieBuddy(Class<?> patchClass, Instrumentation inst) throws Exception {
        Class<?> transformer = Class.forName("me.zed_0xff.zombie_buddy.PatchTransformer");
        Method m = transformer.getDeclaredMethod("transformPatchClass",
            Class.class, Instrumentation.class, int.class, boolean.class);
        m.setAccessible(true);
        return (Class<?>) m.invoke(null, patchClass, inst, 0, false);
    }

    private static Object applyAdvice(Class<?> adviceClass) throws Exception {
        Class<?> loaded = new ByteBuddy()
            .redefine(DummyTarget.class)
            .visit(Advice.to(adviceClass).on(named("submitUpdate")))
            .make()
            .load(DummyTarget.class.getClassLoader(), ClassLoadingStrategy.Default.CHILD_FIRST)
            .getLoaded();
        return loaded.getDeclaredConstructor().newInstance();
    }

    private static boolean hasAnnotation(Class<?> patchClass, String annotationName) {
        for (java.lang.reflect.Method m : patchClass.getDeclaredMethods()) {
            for (java.lang.annotation.Annotation a : m.getDeclaredAnnotations()) {
                if (a.annotationType().getName().equals(annotationName)) {
                    return true;
                }
            }
        }
        return false;
    }

    private interface Body {
        Object run() throws Exception;
    }

    /** 运行 body，并把这一段时间的 stdout 一起返回（用来断言补丁日志）。 */
    private static String capture(Body body) throws Exception {
        PrintStream real = System.out;
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        System.setOut(new PrintStream(new java.io.OutputStream() {
            @Override public void write(int b) {
                real.write(b);
                buf.write(b);
            }
        }, true));
        try {
            body.run();
        } finally {
            System.setOut(real);
        }
        return buf.toString();
    }

    private static void check(String what, boolean ok) {
        System.out.println((ok ? "[ok]   " : "[FAIL] ") + what);
        if (!ok) {
            failures++;
        }
    }

    private RunAdviceTest() {}
}
