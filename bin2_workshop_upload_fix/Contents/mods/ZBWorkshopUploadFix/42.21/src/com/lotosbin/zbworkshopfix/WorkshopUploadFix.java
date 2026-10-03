package com.lotosbin.zbworkshopfix;

import zombie.core.znet.SteamWorkshop;
import zombie.core.znet.SteamWorkshopItem;

import java.util.Locale;

/**
 * 修复 Project Zomboid 在 macOS / Linux 上"上传创意工坊失败"的逻辑。
 *
 * <p>背景：{@code zombie.core.znet.SteamWorkshopItem.submitUpdate()} 在提交之前会弹一个原生确认框
 * （LWJGL tinyfd），并且要求它返回 {@code 1} 才算确认：
 *
 * <pre>
 *   boolean ok = RenderThread.invokeQueryOnRenderContext(this::confirmBox);
 *   return ok &amp;&amp; SteamWorkshop.instance.SubmitWorkshopItem(this);
 * </pre>
 *
 * <p>而 tinyfd 在 macOS 上用 AppleScript 实现，脚本把按钮名和写死的英文 {@code "Yes"/"OK"/"No"} 比较；
 * 非英文系统的默认按钮是本地化的（中文是"好"），于是返回 0，{@code submitUpdate()} 直接 false，
 * {@code SubmitItemUpdate} 从未被调用 —— 这就是 {@code error requesting Steam to update the item} 的来源。
 * Linux 上 tinyfd 找不到 zenity/kdialog 时返回 -1，同样 != 1。
 * Windows 走 Win32 {@code MessageBoxA}（IDOK=1），与语言无关，所以不受影响。
 *
 * <p>因此本类在 {@code submitUpdate()} 返回 false 时补一次 {@code SubmitWorkshopItem()}：
 * 正常确认（英文系统 / Windows）时什么都不做，语义完全不变。
 *
 * <p>注意：这些方法与类必须是 {@code public} —— ByteBuddy 的 Advice 是**内联**到被补丁的方法里的，
 * 访问权限按被补丁的类（{@code zombie.core.znet.SteamWorkshopItem}）判定，包私有会抛 IllegalAccessError。
 */
public final class WorkshopUploadFix {

    private static final String TAG = "[ZBWorkshopUploadFix] ";

    /** Windows 用 Win32 对话框，返回值与语言无关，保留其"取消"语义，不做兜底提交。 */
    private static final boolean IS_WINDOWS =
        System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("win");

    private WorkshopUploadFix() {}

    public static boolean isWindows() {
        return IS_WINDOWS;
    }

    /**
     * tinyfd 的确认框没能给出"确认"（本地化按钮 / 没有可用对话框）时，替玩家点下"确定"。
     *
     * @param self {@code SteamWorkshopItem} 实例（用 Object 接收：Advice 的 {@code @This} 参数类型更宽松）
     * @return {@code SubmitWorkshopItem()} 的真实返回值
     */
    public static boolean forceSubmit(Object self) {
        try {
            SteamWorkshopItem item = (SteamWorkshopItem) self;
            boolean ok = SteamWorkshop.instance.SubmitWorkshopItem(item);
            System.out.println(TAG + "confirm box did not report OK (localized button / no tinyfd backend)"
                + " -> SubmitWorkshopItem(item id=" + item.getID() + ") = " + ok);
            return ok;
        } catch (Throwable t) {
            // 例如 "workshop ID is required"：保持原版行为（返回 false），只记一行日志
            System.out.println(TAG + "SubmitWorkshopItem threw: " + t);
            return false;
        }
    }
}
