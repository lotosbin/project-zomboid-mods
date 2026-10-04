package viewpointmac;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * 兼容性自检：模仿 Viewpoint 的 {@code compat: ...} 机制。
 *
 * <p>游戏每次更新都可能改名/改签名。我们在这里用反射逐项验证要 hook 的类与成员是否存在，
 * 只要有任何一项缺失就把渲染注入整体禁用，只留下日志——宁可没功能，也不能把游戏搞崩。
 */
public final class Compat {

    /** 类名（不存在即致命）。 */
    private static final String[] REQUIRED_CLASSES = {
        "zombie.core.SpriteRenderer",
        "zombie.core.Core",
        "org.lwjglx.opengl.Display",
    };

    /** 类名 + 方法名（缺失即无法挂载）。 */
    private static final String[][] REQUIRED_METHODS = {
        {"zombie.core.SpriteRenderer", "postRender"},
        {"zombie.core.Core", "getScreenWidth"},
        {"zombie.core.Core", "getScreenHeight"},
    };

    /** 类名 + 字段名（缺失只警告，不影响主流程）。 */
    private static final String[][] OPTIONAL_FIELDS = {
        {"zombie.core.SpriteRenderer", "instance"},
    };

    private static final List<String> MISSING = new ArrayList<>();
    private static boolean checked = false;
    private static boolean ok = false;

    public static boolean ok() {
        return ok;
    }

    public static List<String> missing() {
        return Collections.unmodifiableList(MISSING);
    }

    /** 只执行一次；返回是否所有必需项都在。 */
    public static synchronized boolean check() {
        if (checked) {
            return ok;
        }
        checked = true;
        MISSING.clear();

        for (String className : REQUIRED_CLASSES) {
            if (loadClass(className) == null) {
                MISSING.add("class " + className);
            }
        }

        for (String[] entry : REQUIRED_METHODS) {
            Class<?> cls = loadClass(entry[0]);
            if (cls == null) {
                MISSING.add("method " + entry[0] + "#" + entry[1] + " (class missing)");
                continue;
            }
            if (!hasMethod(cls, entry[1])) {
                MISSING.add("method " + entry[0] + "#" + entry[1]);
            }
        }

        for (String[] entry : OPTIONAL_FIELDS) {
            Class<?> cls = loadClass(entry[0]);
            if (cls == null) {
                continue;
            }
            if (!hasField(cls, entry[1])) {
                Vp.warn("optional field missing: " + entry[0] + "#" + entry[1]);
            }
        }

        ok = MISSING.isEmpty();
        return ok;
    }

    public static void checkAndLog() {
        boolean result = check();
        if (result) {
            Vp.log("compat: all " + (REQUIRED_CLASSES.length + REQUIRED_METHODS.length)
                + " patch targets and members found (game build accepted).");
        } else {
            Vp.error("compat: the game build changed; missing: " + String.join(", ", MISSING)
                + " -- render injection stays off.", null);
        }
    }

    /** 安全加载类：失败返回 null，不抛异常。 */
    private static Class<?> loadClass(String name) {
        try {
            return Class.forName(name, false, Compat.class.getClassLoader());
        } catch (Throwable ignored) {
            // 类不存在或初始化失败，都按"缺失"处理
            return null;
        }
    }

    private static boolean hasMethod(Class<?> cls, String name) {
        try {
            for (Method method : cls.getDeclaredMethods()) {
                if (method.getName().equals(name) && Modifier.isPublic(method.getModifiers())) {
                    return true;
                }
            }
        } catch (Throwable ignored) {
            // 反射失败按缺失处理
        }
        return false;
    }

    private static boolean hasField(Class<?> cls, String name) {
        try {
            for (Field field : cls.getDeclaredFields()) {
                if (field.getName().equals(name)) {
                    return true;
                }
            }
        } catch (Throwable ignored) {
            // 反射失败按缺失处理
        }
        return false;
    }

    private Compat() {
    }
}
