// Project Zomboid：workshop.txt 的 description 解析探针（不联网、不需要 Steam）
//
// 与同目录 WorkshopProbe.java 的区别：
//   * WorkshopProbe 需要 Steam 客户端已登录，用来验证"上传前的 native 链路"；
//   * 本探针只初始化 ZomboidFileSystem + SteamWorkshopItem，**不碰 Steam、不加载 native 库**，
//     用来回答"我写的富文本/多行描述，游戏到底解析成什么字符串"。
//
// 用法：
//   WorkshopTxtProbe <item> [<item> ...]        # dump 模式：逐行用 | 括起来打印解析结果
//   WorkshopTxtProbe --check <item> [<item>...] # check 模式：每个物品一行摘要 + 问题明细
//
// dump 模式把 description 与 getSubmitDescription() 逐行用 | 括起来，因此换行、空行、前导空格
// 都看得见；同时打印字符数与 UTF-8 字节数（Steam 工坊描述上限 8000 字节）。
//
// 编译（需要 JDK ≥ 游戏字节码版本；B42.21 是 Java 25，JDK 17 会报 class file version 69）：
//     javac -nowarn -cp "<游戏目录>/projectzomboid.jar" -d /tmp/bbprobe WorkshopTxtProbe.java
// 运行（必须 cwd 到游戏 Contents/Java；参数必须是白名单路径，见下）：
//     cd "<游戏目录>"
//     java -Djava.awt.headless=true -cp /tmp/bbprobe:projectzomboid.jar \
//          WorkshopTxtProbe --check ~/Zomboid/Workshop/<item> ...
//
// ⚠️ 参数只能传 ~/Zomboid/Workshop/<item> 这类白名单路径（软链即可，见 workshop_create.sop.md §8）。
//    直接传仓库路径会在构造函数里抛 IllegalArgumentException: Invalid prefix found for: …
//
// check 模式检查项（全部来自游戏自己的解析器 + 原始文本对照）：
//   1 readWorkshopTxt 是否成功
//   2 tags 是否全部命中游戏 media/WorkshopTags.txt 白名单（getAllowedTags()）
//   3 visibility 解析出的整数
//   4 description / submitDescription 的 UTF-8 字节数是否 ≤ 8000
//   5 是否出现 6 个合法键之外的键（会被静默忽略）
//   6 description 值里是否出现字面量 "description="（会被 replace 删掉）
//   7 BBCode 成对标签是否闭合（未闭合会把游戏追加的 ID 行吞进列表/引用块）
//
// macOS 42.21 实测输出（dump 模式节选，workshop.txt 里 description= 行含 BBCode 与空 description=）：
//     readWorkshopTxt = true
//     --- getDescription() ---
//     |[h1]中文标题[/h1]|
//     |[b]加粗[/b] 与 [i]斜体[/i] 与 [url=https://example.com]链接[/url]|
//     ||
//     |[list]|
//     |[*]条目一|
//     |[/list]|
//     |  以两个空格缩进的行（空格写在 description= 之后才保留）|
//     --- getSubmitDescription() ---
//     |…同上…|
//     ||
//     |Workshop ID: null|
// 结论：游戏对 BBCode **一个字都不改**（不转义、不剥离），只做"行 trim + 用单个 \n 拼接 + 追加 ID 行"。

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Deque;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import zombie.core.znet.SteamWorkshopItem;

public class WorkshopTxtProbe {

    /** 游戏只认这 6 个键（readWorkshopTxt 字节码），其余一律忽略。 */
    private static final List<String> KNOWN_KEYS = Arrays.asList(
            "version", "id", "title", "description", "tags", "visibility");

    /** BBCode 里需要成对闭合的标签（其余标签不参与配平检查，避免误报）。 */
    private static final List<String> PAIRED_TAGS = Arrays.asList(
            "b", "i", "u", "strike", "h1", "h2", "h3", "list", "olist", "quote", "code",
            "spoiler", "noparse", "url", "img", "table", "tr", "th", "td", "previewyoutube");

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("用法: WorkshopTxtProbe [--check] ~/Zomboid/Workshop/<item> [...]");
            System.exit(2);
        }

        boolean check = "--check".equals(args[0]);
        String[] folders = check ? Arrays.copyOfRange(args, 1, args.length) : args;
        if (folders.length == 0) {
            System.err.println("用法: WorkshopTxtProbe [--check] ~/Zomboid/Workshop/<item> [...]");
            System.exit(2);
        }

        zombie.ZomboidFileSystem.instance.init();

        if (!check) {
            for (String folder : folders) {
                dumpItem(folder);
            }
            return;
        }

        // check 模式：每个物品一行摘要，问题明细单独列出
        System.out.printf("%-46s %-5s %-6s %-8s %-11s %s%n",
                "item", "read", "tags", "vis", "desc/submit", "issues");
        System.out.println("-".repeat(140));
        int problems = 0;
        for (String folder : folders) {
            problems += checkItem(folder);
        }
        System.out.println("-".repeat(140));
        System.out.println(problems == 0
                ? "ALL CHECKS PASSED (" + folders.length + " item(s))"
                : problems + " problem(s) found");
        if (problems != 0) {
            System.exit(1);
        }
    }

    /** dump 模式：打印解析后的 description 与 getSubmitDescription()。 */
    static void dumpItem(String folder) throws Exception {
        SteamWorkshopItem item = new SteamWorkshopItem(folder);
        System.out.println("=== " + folder);
        System.out.println("readWorkshopTxt = " + item.readWorkshopTxt());
        System.out.println("title           = " + item.getTitle());
        System.out.println("tags            = " + item.getTags());
        System.out.println("visibility      = " + item.getVisibilityInteger()
                + "   (0=public 1=friendsOnly 2=private 3=unlisted)");

        String desc = item.getDescription();
        String submit = item.getSubmitDescription();
        System.out.println("description     = " + desc.length() + " chars / "
                + desc.getBytes(StandardCharsets.UTF_8).length + " bytes (UTF-8)");
        System.out.println("submitDesc      = " + submit.length() + " chars / "
                + submit.getBytes(StandardCharsets.UTF_8).length + " bytes"
                + "   (Steam 上限 8000 字节，这里已含游戏自动追加的 Workshop ID / Mod ID 行)");

        dump("getDescription()", desc);
        dump("getSubmitDescription()", submit);
    }

    /** check 模式：返回该物品发现的问题数。 */
    static int checkItem(String folder) throws Exception {
        SteamWorkshopItem item = new SteamWorkshopItem(folder);
        boolean read = item.readWorkshopTxt();
        String name = new File(folder).getName();
        List<String> issues = new ArrayList<>();

        // 2 tags 白名单
        Set<String> allowed = new LinkedHashSet<>(SteamWorkshopItem.getAllowedTags());
        List<String> badTags = new ArrayList<>();
        for (String t : item.getTags()) {
            if (!allowed.contains(t)) {
                badTags.add(t.isEmpty() ? "(空)" : t);
            }
        }
        if (!badTags.isEmpty()) {
            issues.add("tags 不在白名单: " + badTags + " -> Steam 会静默忽略");
        }
        if (item.getTags().isEmpty()) {
            issues.add("没有 tags");
        }

        // 4 长度
        String desc = item.getDescription();
        String submit = item.getSubmitDescription();
        int descBytes = desc.getBytes(StandardCharsets.UTF_8).length;
        int submitBytes = submit.getBytes(StandardCharsets.UTF_8).length;
        if (submitBytes > 8000) {
            issues.add("submitDescription " + submitBytes + " 字节 > 8000（Steam 上限）");
        }

        // 5/6 原始文本对照
        File txt = new File(folder, "workshop.txt");
        List<String> unknownKeys = new ArrayList<>();
        List<String> literalDesc = new ArrayList<>();
        int lineNo = 0;
        for (String raw : Files.readAllLines(txt.toPath(), StandardCharsets.UTF_8)) {
            lineNo++;
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#") || line.startsWith("//")) {
                continue;
            }
            int eq = line.indexOf('=');
            if (eq < 0) {
                unknownKeys.add("L" + lineNo + " 没有 '=': " + shorten(line));
                continue;
            }
            String key = line.substring(0, eq);
            String value = line.substring(eq + 1);
            if (!KNOWN_KEYS.contains(key)) {
                unknownKeys.add("L" + lineNo + " " + key + "=");
                continue;
            }
            if ("description".equals(key) && value.contains("description=")) {
                literalDesc.add("L" + lineNo);
            }
        }
        if (!unknownKeys.isEmpty()) {
            issues.add("非法的键（会被忽略）: " + unknownKeys);
        }
        if (!literalDesc.isEmpty()) {
            issues.add("description 值里出现字面量 'description='（会被 replace 删掉）: " + literalDesc);
        }

        // 7 BBCode 配平
        List<String> bb = bbcodeProblems(desc);
        if (!bb.isEmpty()) {
            issues.add("BBCode: " + bb);
        }

        System.out.printf("%-46s %-5s %-6s %-8d %5d/%-5d %s%n",
                shorten(name, 46), read ? "ok" : "FAIL",
                badTags.isEmpty() ? "ok" : "BAD",
                item.getVisibilityInteger(), descBytes, submitBytes,
                issues.isEmpty() ? "-" : issues.size() + " issue(s)");
        for (String s : issues) {
            System.out.println("      ! " + s);
        }
        return issues.size() + (read ? 0 : 1);
    }

    /** 找出未闭合 / 多余的 BBCode 标签（只查 PAIRED_TAGS）。 */
    static List<String> bbcodeProblems(String text) {
        List<String> problems = new ArrayList<>();
        Deque<String> stack = new ArrayDeque<>();
        Matcher m = Pattern.compile("\\[([^\\[\\]]{1,300})\\]").matcher(text);
        while (m.find()) {
            String inner = m.group(1).trim();
            if (inner.isEmpty()) {
                continue;
            }
            boolean close = inner.startsWith("/");
            String body = close ? inner.substring(1).trim() : inner;
            String tag = body.split("[=\\s]")[0].toLowerCase(Locale.ROOT);
            if (!PAIRED_TAGS.contains(tag)) {
                continue;
            }
            if (close) {
                if (stack.isEmpty() || !stack.peek().equals(tag)) {
                    problems.add("多余的 [/" + tag + "]");
                } else {
                    stack.pop();
                }
            } else {
                stack.push(tag);
            }
        }
        for (String tag : stack) {
            problems.add("未闭合 [" + tag + "]");
        }
        return problems;
    }

    /** 逐行用 | 括起来打印，保留空行与前导空格（split 传 -1 才不吞末尾空串）。 */
    static void dump(String label, String s) {
        System.out.println("--- " + label + " ---");
        for (String line : s.split("\n", -1)) {
            System.out.println("|" + line + "|");
        }
    }

    static String shorten(String s) {
        return shorten(s, 60);
    }

    static String shorten(String s, int max) {
        return s.length() <= max ? s : s.substring(0, max - 1) + "…";
    }
}
