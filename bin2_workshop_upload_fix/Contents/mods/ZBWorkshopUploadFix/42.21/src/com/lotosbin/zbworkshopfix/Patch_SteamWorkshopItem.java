package com.lotosbin.zbworkshopfix;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * ZombieBuddy 补丁：把 {@code SteamWorkshopItem.submitUpdate()} 的"原生确认框必须返回 1"变成兜底可选。
 *
 * <p>不跳过原方法（确认框照旧弹出、Windows/英文系统的行为一个字都不变），
 * 只在它返回 false 时补一次真正的提交，修掉 tinyfd 在 macOS/Linux 上的本地化/缺工具问题。
 *
 * <p>对应的一行"改 jar"等价补丁（script 版本）是把 {@code iload_1; ifeq} 抹成 4 个 {@code nop}；
 * 这里用注解在运行时做同一件事，不动游戏任何文件，也不再被 Steam 更新/校验覆盖。
 */
public final class Patch_SteamWorkshopItem {

    @Patch(className = "zombie.core.znet.SteamWorkshopItem", methodName = "submitUpdate")
    public static class Patch_submitUpdate {

        @Patch.OnExit
        public static void exit(
            @Patch.This Object self,
            @Patch.Return(readOnly = false) boolean result
        ) {
            if (result) {
                return;                         // 英文系统 / Windows：确认框正常返回 1，保持原语义
            }
            if (WorkshopUploadFix.isWindows()) {
                return;                         // Windows 的"取消"是真实意图，不要覆盖
            }
            result = WorkshopUploadFix.forceSubmit(self);
        }
    }

    private Patch_SteamWorkshopItem() {}
}
