// 用游戏自带的 Lua 编译器（luaj-kahluafork fork）检查 .lua 语法 —— 不启动游戏
// 这里刻意只用反射调用游戏类：因为游戏 class 文件是 Java 25 的，而本机 javac 是 17/21，编译期读不了。
// 用法：<游戏自带 JRE>/bin/java -cp "<游戏>/Contents/Java/projectzomboid.jar:." LuaSyntaxCheck <文件或目录> ...
import java.io.File;
import java.io.FileReader;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

public class LuaSyntaxCheck {

    private static Method loadis;
    private static Object env;

    public static void main(String[] args) throws Exception {
        List<File> files = new ArrayList<File>();
        for (String a : args) collect(new File(a), files);
        if (files.isEmpty()) { System.out.println("no .lua files given"); System.exit(2); }

        Class<?> compiler = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");
        Class<?> table = Class.forName("se.krka.kahlua.vm.KahluaTable");
        loadis = compiler.getMethod("loadis", java.io.Reader.class, String.class, table);
        env = makeEnv();

        int ok = 0, bad = 0;
        for (File f : files) {
            try (FileReader r = new FileReader(f)) {
                loadis.invoke(null, r, f.getPath(), env);
                ok++;
            } catch (InvocationTargetException e) {
                bad++;
                Throwable c = e.getCause() == null ? e : e.getCause();
                System.out.println("FAIL " + f.getPath() + " -> " + c.getClass().getSimpleName() + ": " + c.getMessage());
            } catch (Throwable t) {
                bad++;
                System.out.println("FAIL " + f.getPath() + " -> " + t);
            }
        }
        System.out.println("LUA SYNTAX: " + ok + " ok, " + bad + " failed");
        System.exit(bad == 0 ? 0 : 1);
    }

    // 找一个可用的空环境表；实在造不出来就用 null（编译器只在 rewriteEvents 模式才需要 env）
    private static Object makeEnv() {
        try {
            Class<?> impl = Class.forName("se.krka.kahlua.j2se.KahluaTableImpl");
            for (java.lang.reflect.Constructor<?> c : impl.getDeclaredConstructors()) {
                try {
                    c.setAccessible(true);
                    Object[] argv = new Object[c.getParameterCount()];
                    for (int i = 0; i < argv.length; i++) argv[i] = null;
                    return c.newInstance(argv);
                } catch (Throwable ignored) { }
            }
        } catch (Throwable t) {
            System.out.println("(no env table available: " + t + " - using null)");
        }
        return null;
    }

    private static void collect(File f, List<File> out) {
        if (f.isDirectory()) {
            File[] kids = f.listFiles();
            if (kids != null) for (File k : kids) collect(k, out);
        } else if (f.getName().endsWith(".lua")) {
            out.add(f);
        }
    }
}
