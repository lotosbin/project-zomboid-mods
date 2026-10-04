package viewpointmac;

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.Date;

/**
 * ViewpointMac 的全局常量、日志与路径工具。
 *
 * <p>命名约定：
 * <ul>
 *   <li>日志统一以 {@code [ViewpointMac]} 开头，方便在 Zomboid/console.txt 中检索；</li>
 *   <li>print log 使用英文，代码注释使用中文。</li>
 * </ul>
 *
 * <p>**日志双写**（1.9.2 起）：除了 console.txt，还会追加写
 * {@code ~/Zomboid/ViewpointMac.log}，并周期性写入状态快照（只进文件、不刷控制台）。
 * 这样排查问题不需要用户复制粘贴 —— 直接读那个文件即可。
 * 文件超过 {@link #LOG_MAX_BYTES} 会自动轮转成 {@code .1}。
 */
public final class Vp {

    /** 日志前缀（与 Viewpoint 的 [Viewpoint] 区分开，便于同时排查两个模组）。 */
    public static final String TAG = "[ViewpointMac]";

    /** 模组版本，与 mod.info 的 modversion 保持一致。 */
    public static final String VERSION = "2.2.0";

    /** 运行期配置文件名（位于 ~/Zomboid）。 */
    public static final String CONFIG_FILE = "viewpointmac.properties";

    /** 能力自检报告文件名（位于 ~/Zomboid）。 */
    public static final String REPORT_FILE = "viewpointmac-report.txt";

    /** 独立日志文件名（位于 ~/Zomboid）。 */
    public static final String LOG_FILE = "ViewpointMac.log";

    /** 日志轮转阈值（2 MB）。 */
    private static final long LOG_MAX_BYTES = 2L * 1024L * 1024L;

    private static volatile boolean verbose = false;

    private static PrintWriter fileLog = null;
    private static boolean fileLogFailed = false;
    private static long fileLines = 0;
    private static final SimpleDateFormat STAMP = new SimpleDateFormat("HH:mm:ss.SSS");

    public static void setVerbose(boolean value) {
        verbose = value;
    }

    public static boolean isVerbose() {
        return verbose;
    }

    /** 日志文件路径（给报告/UI 展示用）。 */
    public static File logFile() {
        return userFile(LOG_FILE);
    }

    private static synchronized PrintWriter writer() {
        if (fileLog != null || fileLogFailed) {
            return fileLog;
        }
        try {
            File file = logFile();
            File parent = file.getParentFile();
            if (parent != null && !parent.isDirectory()) {
                parent.mkdirs();
            }
            if (file.isFile() && file.length() > LOG_MAX_BYTES) {
                File old = new File(file.getParentFile(), LOG_FILE + ".1");
                if (old.isFile()) {
                    old.delete();
                }
                file.renameTo(old);
            }
            fileLog = new PrintWriter(new FileWriter(file, true), true);
        } catch (Throwable t) {
            fileLogFailed = true;
            System.out.println(TAG + " WARN cannot open log file: " + t);
        }
        return fileLog;
    }

    private static void write(String level, String message) {
        PrintWriter out = writer();
        if (out == null) {
            return;
        }
        try {
            out.println(STAMP.format(new Date()) + " " + level + " " + message);
            fileLines++;
        } catch (Throwable ignored) {
            // 日志失败绝不影响游戏
        }
    }

    /** 只写日志文件、不写控制台（用于周期性快照，避免刷屏）。 */
    public static void fileOnly(String message) {
        write("SNAP", message);
    }

    public static long fileLines() {
        return fileLines;
    }

    public static void log(String message) {
        System.out.println(TAG + " " + message);
        write("LOG ", message);
    }

    public static void debug(String message) {
        if (verbose) {
            System.out.println(TAG + " " + message);
        }
        write("DBG ", message);
    }

    public static void warn(String message) {
        System.out.println(TAG + " WARN " + message);
        write("WARN", message);
    }

    public static void error(String message, Throwable cause) {
        System.out.println(TAG + " ERROR " + message + (cause == null ? "" : " :: " + cause));
        write("ERR ", message + (cause == null ? "" : " :: " + cause));
        if (cause != null && verbose) {
            cause.printStackTrace(System.out);
        }
    }

    /** 一条醒目的分隔，方便在日志里定位一次启动。 */
    public static void logSessionStart(String detail) {
        write("====", "=== new session: " + detail + " ===");
    }

    /**
     * 僵尸毁灭工程的用户目录（macOS / Linux 为 ~/Zomboid，Windows 为 %USERPROFILE%\Zomboid）。
     * 优先使用游戏自己的目录对象，取不到时退回 user.home。
     */
    public static File zomboidDir() {
        String override = System.getProperty("viewpointmac.zomboidDir");
        if (override != null && !override.isEmpty()) {
            return new File(override);
        }
        try {
            Class<?> cls = Class.forName("zombie.core.Core");
            Object dir = cls.getMethod("getMyDocumentFolder").invoke(null);
            if (dir instanceof String && !((String) dir).isEmpty()) {
                return new File((String) dir);
            }
        } catch (Throwable ignored) {
            // 游戏 API 变化时退回 user.home，不影响功能
        }
        return new File(System.getProperty("user.home", "."), "Zomboid");
    }

    public static File userFile(String name) {
        return new File(zomboidDir(), name);
    }

    private Vp() {
    }
}
