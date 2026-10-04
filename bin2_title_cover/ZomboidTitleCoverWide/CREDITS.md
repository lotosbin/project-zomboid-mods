# CREDITS / 素材来源

* **美术**：100% 由本仓库脚本 `tools/make_title_cover.py` 程序化生成（Pillow），
  **没有**使用任何第三方图片、图库素材、商业游戏资产或 AI 生成图。
  构图与配色的**风格**参考了末世题材的通行视觉语言（剪影尸群、废墟天际线、
  做旧破损标题、深灰/土褐/血红配色），风格本身不受版权保护。
* **字体**：生成时使用本机系统字体（macOS: `Impact.ttf` 作拉丁标题、`Hiragino Sans GB.ttc`
  作中文副标题）。**字体文件没有随模组分发**，产出的 PNG 是文字轮廓的位图。
  依据 Apple 系统字体许可，系统字体不得再分发，因此仓库内不含任何字体文件。
* **引擎研究**：`zombie.gameStates.MainScreenState` / `zombie.core.Core` 的绘制与选项逻辑
  由 `javap` 反编译本机 `projectzomboid.jar` 得到，并做了真机探针验证（隔离 cachedir）。
