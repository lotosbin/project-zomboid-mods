# Bug report draft (English) — Steam Workshop upload fails on macOS/Linux

Post this to the Project Zomboid bug forum / Steam discussions. Fill in the bracketed bits.

---

**Title:** `[B42.20.4/B42.21] Uploading a mod to the Steam Workshop always fails on macOS and Linux
("error requesting Steam to update the item")`

**Summary**

The in-game Workshop upload wizard cannot upload on macOS, and cannot upload on Linux either.
The workshop item gets created and an ID is returned, but the content is never uploaded
(the item stays at 0.000 B) and the upload log always ends with:

```
start update of existing item ID=<id>
error requesting Steam to update the item
finished
```

Windows is unaffected. **The cause is locale/platform dependent**: it reproduces on any macOS
whose system language is not English (e.g. Simplified Chinese: the dialog button is "好"),
and on Linux when tinyfd cannot find a dialog helper program.

**Root cause**

`zombie.core.znet.SteamWorkshopItem.submitUpdate()` is bytecode-equivalent to:

```java
public boolean submitUpdate() {
    boolean ok = RenderThread.invokeQueryOnRenderContext(this::confirmDialog); // native tinyfd box
    return ok && SteamWorkshop.instance.SubmitWorkshopItem(this);              // ok must == 1
}
```

`confirmDialog` calls `org.lwjgl.util.tinyfd.TinyFileDialogs.tinyfd_messageBox(title, msg, "okcancel",
"warning", 2)` and returns `tinyfd_messageBox(...) == 1`.

On macOS tinyfd implements `tinyfd_messageBox` by shelling out to `osascript` with this script:

```applescript
set {vButton} to {button returned} of ( display dialog "<message>" with title "<title>" with icon caution )
if vButton is "Yes" then
  return 1
else if vButton is "OK" then
  return 1
else if vButton is "No" then
  return 2
else
  return 0
end if
```

Because no `buttons {...}` is passed, the single default button is **localized by the OS** and its
name is returned in `button returned`. On a Simplified-Chinese macOS that string is `好`, so all
three comparisons fail, the script returns `0`, tinyfd returns `0`, and `submitUpdate()` returns
`false` — while `SteamWorkshop.SubmitWorkshopItem()` (and therefore
`ISteamUGC::SubmitItemUpdate`) is never called. That is exactly why Steam's own
`logs/workshop_log.txt` only shows `Create new workshop item ... (OK)` and no update at all.

Windows is fine because there tinyfd uses `MessageBoxA(..., MB_OKCANCEL)` whose return value
(`IDOK = 1`) is language-independent.

**Reproduction on macOS (verified on B42.21.0, macOS 27 arm64, AppleLanguages = zh-Hans-CN)**

1. `~/Zomboid/Workshop/<mod>/` contains `Contents/` and `preview.png`; the upload wizard creates the
   item and writes its id into `workshop.txt`, then reports
   `error requesting Steam to update the item`.
2. Calling the very same API directly with the shipped jar/JRE returns `0`, not `1`:

   ```java
   int r = org.lwjgl.util.tinyfd.TinyFileDialogs.tinyfd_messageBox(
       "WARNING: Steam Workshop upload requested!", "Please confirm ...", "okcancel", "warning", 2);
   // r == 0
   ```

3. Replaying the exact AppleScript tinyfd passes to `osascript` (captured by putting a fake
   `osascript` earlier in `PATH`) prints `0` on stdout, exit code 0, no stderr.
   Asking the OS what that button is called gives:

   ```
   $ osascript -e 'tell application "System Events"' -e 'set r to (display dialog "probe" giving up after 4)' -e 'return r' -e 'end tell'
   button returned:好, gave up:false
   ```

4. Everything else in the upload path works on the same machine: initialising Steam and calling
   `StartItemUpdate`, `SetItemTitle`, `SetItemDescription`, `SetItemVisibility`, `SetItemTags`,
   `SetItemContent`, `SetItemPreview` all return `true` for the staged item (checked with a small
   harness that stops just before `SubmitItemUpdate`). So the confirmation dialog is the only
   failing step.

**Impact**

Mod authors on macOS with a non-English system language, and on Linux machines without
zenity/kdialog/yad, cannot upload or update their Workshop items at all.

**Suggested fixes (any one is enough)**

1. Do not gate `SubmitWorkshopItem()` on the native dialog's return value; the dialog on
   macOS/Linux only has a single OK button anyway. If the dialog is unavailable/unconfirmed,
   still proceed (or just drop the dialog and rely on the wizard's own "Publish" button).
2. If the dialog is kept, pass explicit button labels so the returned string cannot be localized
   (on macOS tinyfd would then emit `buttons {"OK", ...}`).
3. Also write Page 7's log to `Zomboid/WorkshopLog.txt`
   (the `-- TODO: write to WorkshopLog.txt as well` comment is still in
   `media/lua/client/OptionScreens/WorkshopSubmitScreen.lua`). Right now the failure reason only
   appears in an on-screen text box, which makes this class of bug very hard to report.

**Workaround for users (until fixed)**

* Linux: install a dialog helper (`sudo dnf install zenity` on Fedora/Bazzite, `apt install zenity`
  on Debian/Ubuntu).
* macOS: no one-line workaround — the button name follows the system language, so either switch the
  system language to English or patch `SteamWorkshopItem.submitUpdate()` locally.

---

*References:* this report was produced from the reproduction steps in
<https://steamcommunity.com/app/108600/discussions/1/582806854239939623/> ;
LWJGL's tinyfd module: <https://github.com/LWJGL/lwjgl3/tree/master/modules/lwjgl/tinyfd> ;
tinyfiledialogs (the AppleScript/`button returned` comparison shown above):
<https://sourceforge.net/projects/tinyfiledialogs/>.
