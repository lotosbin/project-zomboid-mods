#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 base/ 里的美术与 Lua 组装成可直接上传的两个工坊物品（16:9 / 21:9）。

产物结构（Steam 上传时选 bin2_title_cover/Contents/... 所属的**物品目录**这一层）：

    bin2_title_cover/
    ├── ZomboidTitleCoverWide/            21:9，1280+1280 x 1280
    │   ├── workshop.txt / preview.png / changelog.txt / README.md / CREDITS.md
    │   └── Contents/mods/ZomboidTitleCoverWide/{42.21,common}/
    └── ZomboidTitleCover/                16:9，960+960 x 1024
        └── ...

只做文件搬运与元数据生成：美术由 tools/make_title_cover.py 负责，本脚本不画图。
"""

from __future__ import annotations

import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                 # bin2_title_cover/
BASE = os.path.join(ROOT, "base")

VERSION_DIR = "42.21"

# 每个变体：(物品目录名, 模组 id, 变体键, 画布, 比例说明)
VARIANTS = [
    {
        "folder": "ZomboidTitleCover",
        "mod_id": "ZomboidTitleCover",
        "art": "v16",
        "canvas": "1920x1024（960+960，正好铺满 1920x1080）",
        "aspect": "16:9",
        "name": "Zomboid Apocalypse Cover 末世封面 (16:9)",
        "title": "Zomboid Apocalypse Cover 末世封面 - 主菜单尸潮背景 (16:9, Build 42)",
    },
    {
        "folder": "ZomboidTitleCoverWide",
        "mod_id": "ZomboidTitleCoverWide",
        "art": "v219",
        "canvas": "2560x1280（1280+1280，带鱼屏铺满、16:9 居中裁掉两侧）",
        "aspect": "21:9",
        "name": "Zomboid Apocalypse Cover 末世封面 (21:9)",
        "title": "Zomboid Apocalypse Cover 末世封面 - 主菜单尸潮背景 (21:9, Build 42)",
    },
]

LUA_SRC = os.path.join(BASE, "lua", "ZomboidTitleCover_StaticMenu.lua")

# 16:9 与 21:9 两套互斥：同时启用会互相覆盖 media/ui/Title*.png，画面会在两种构图间闪
INCOMPATIBLE = "\\ZomboidTitleCover,\\ZomboidTitleCoverWide"

MOD_INFO = """name={name}
id={mod_id}
versionMin=42.0.0
modversion=1.0.0
icon=media/ui/ZomboidTitleCover_icon.png
poster=media/ui/ZomboidTitleCover_poster.png
incompatible={incompatible}
description=用一张末世尸潮封面替换主菜单标题背景（写实电影感 + 经典末世配色 + 英雄居中/尸群围困 + 做旧破损字体）。
description=Replaces the main-menu title background with a zombie-apocalypse cover artwork.
description=
description=画布：{canvas}。
description=Draws media/ui/Title.png + Title2.png + Title3.png + Title4.png (the four textures the
description=engine composes in MainScreenState.renderOriginalBackground), and turns off
description="Video Effects" for the session so the engine stops covering them with
description=media/videos/title_screen_background.bik.
description=
description=与原版不冲突的界面元素：不修改 PZ logo、菜单排版与按钮位置。
"""

WORKSHOP_TXT = """version=1
title={title}
description=用一张程序化生成的末世尸潮封面替换主菜单标题背景（Build 42）。
description=
description=【视觉】写实电影感 + 经典末世配色（深灰 / 土褐 / 血红点缀）+ "英雄居中、尸群围困" 构图 +
description=做旧破损标题字。渲染分层：夜空与云 -> 废墟天际线（楼顶火点/天线）-> 地平线雾光 ->
description=地面碎石 -> 三层尸潮剪影 -> 主角与背光 -> 前景道具 -> 标题 -> 胶片颗粒/暗角/半调网点。
description=
description=【技术】引擎只有关掉 "Video Effects" 时才会绘制媒体层可覆盖的 media/ui/Title*.png，
description=否则播放 media/videos/title_screen_background.bik 把背景盖住。本模组在载入/进入主菜单时
description=把该选项关掉（只在本局内存生效，不写你的 options.ini）。画布 {canvas}。
description=
description=【互斥】16:9 与 21:9 两套共用同名纹理，同时启用会互相覆盖，已在 mod.info 里声明 incompatible。
description=
description=【已知限制】未在 Linux 上实测；未做真实工坊上传验证；标题视频关闭是本模组生效的前提，
description=如果你在选项里重新打开 "视频背景特效"，封面会被视频盖住。
description=
description=源码与完整分析：https://github.com/lotosbin/project-zomboid-mods
tags=Build 42;Misc;Interface
visibility=private
"""

CHANGELOG = """版本 1.0.0 (2026-10-03)
- 初始发布：主菜单标题背景替换为程序化生成的末世尸潮封面（{aspect}）。
- 做法：覆盖 media/ui/Title.png / Title2.png / Title3.png / Title4.png 四张引擎合成纹理；
  并在载入与进入主菜单时关闭 "Video Effects"（doVideoEffects），否则
  media/videos/title_screen_background.bik 会盖住自定义背景。
- 关键几何（来自引擎字节码，不是猜的）：左右两半底图按 screenHeight/1080 缩放；顶栏条
  Title3/Title4 实际也按整幅正方形高绘制（56f*scale 算进局部变量后未被读取），因此这两张
  输出为"仅顶部 56 行不透明、其余透明"的 RGBA，避免在加法混合下变成横贯屏幕的色带。
- 未产出 Title_lightning*.png 的满幅版本：那 4 张按加法混合绘制，给满幅亮图会撕开画面；
  而原版 lightningDelta 恒为 0，它们本来就不会被绘制。
- 已知限制：未在 Linux 实测；未做真实工坊上传验证；美术为程序化生成（非手绘/非图库素材）。
"""

README = """# {name}

用一张**程序化生成的末世尸潮封面**替换 Project Zomboid Build 42 主菜单的标题背景。

![preview](preview.png)

## 为什么需要配套 Lua

引擎（`zombie.gameStates.MainScreenState.renderBackground()`，Build 42.21 字节码）：

```java
if (Core.getInstance().getOptionDoVideoEffects()) { if (renderVideo()) return; }
renderOriginalBackground(1.0f - lightningDelta * 0.6f);
```

* `renderVideo()` 播放 `media/videos/title_screen_background.bik`；
* `doVideoEffects` 的默认值是 **true**（`Core` 构造里 `newOption("doVideoEffects", true)`）。

也就是说：**只把 `Title*.png` 放进 `media/ui/` 是不够的** —— 默认配置下引擎根本不会调用
`renderOriginalBackground()`，视频会把你的图整片盖住。`common/media/lua/shared/` 里的脚本
只做一件事：在载入与进入主菜单时把该选项关掉（**只在本局内存生效，不写 options.ini**）。

## 覆盖了哪些纹理

`renderOriginalBackground()` 只读这 8 个名字，本模组覆盖前 4 个：

| 文件 | 尺寸（本变体） | 引擎绘制方式 |
| --- | --- | --- |
| `Title.png` | {t_left} | 左半底图，`(x, 0, w*scale, h*scale)`，`scale = screenHeight/1080` |
| `Title2.png` | {t_right} | 右半底图，接在左半右边 |
| `Title3.png` | {t_left} | 原版是 1024x56 顶栏条；引擎实际按整幅高绘制，故输出"仅顶部 56 行不透明"的 RGBA |
| `Title4.png` | {t_right} | 同上（左右两半） |
| `Title_lightning*.png` | 不提供 | 加法混合（`glBlendFunc(770,1)`），且原版 `lightningDelta` 恒为 0；交回原版最安全 |

画布 {canvas}。

## 安装

1. 订阅后，游戏内 **Mods** 里启用 `{mod_id}`；
2. 进入主菜单即可看到新背景。

`incompatible` 已声明：**16:9 与 21:9 两套不要同时启用**（它们写的是同一批文件名，会互相覆盖）。

## 已知限制

* 未在 Linux 上实测（macOS 42.21 + 引擎探针验证）；
* 未做真实工坊上传验证（`workshop.txt` 里 `visibility=private`，发布前自行改 `public`）；
* 若你在「选项 → 视频背景特效」里重新打开为 Yes，标题视频会重新盖住封面（这是引擎行为）；
* 美术是**程序化生成**的（脚本 `tools/make_title_cover.py`，无需联网、可复现）：有意做成
  暗调剪影风格而不是写实渲染图，避免使用任何第三方素材或图库资产。

## 复现美术

```bash
python3 tools/make_title_cover.py           # 生成 base/art 下全部纹理与预览图
python3 tools/make_title_cover.py --check   # 校验尺寸/模式/透明度/非纯色
```
"""

CREDITS = """# CREDITS / 素材来源

* **美术**：100% 由本仓库脚本 `tools/make_title_cover.py` 程序化生成（Pillow），
  **没有**使用任何第三方图片、图库素材、商业游戏资产或 AI 生成图。
  构图与配色的**风格**参考了末世题材的通行视觉语言（剪影尸群、废墟天际线、
  做旧破损标题、深灰/土褐/血红配色），风格本身不受版权保护。
* **字体**：生成时使用本机系统字体（macOS: `Impact.ttf` 作拉丁标题、`Hiragino Sans GB.ttc`
  作中文副标题）。**字体文件没有随模组分发**，产出的 PNG 是文字轮廓的位图。
  依据 Apple 系统字体许可，系统字体不得再分发，因此仓库内不含任何字体文件。
* **引擎研究**：`zombie.gameStates.MainScreenState` / `zombie.core.Core` 的绘制与选项逻辑
  由 `javap` 反编译本机 `projectzomboid.jar` 得到，并做了真机探针验证（隔离 cachedir）。
"""


def write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def copy(src: str, dst: str) -> None:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)


def build_variant(v: dict) -> None:
    item = os.path.join(ROOT, v["folder"])
    if os.path.isdir(item):
        shutil.rmtree(item)

    art = os.path.join(BASE, "art", v["art"])
    ui_dir = os.path.join(item, "Contents", "mods", v["mod_id"], VERSION_DIR, "media", "ui")
    lua_dir = os.path.join(item, "Contents", "mods", v["mod_id"], "common", "media", "lua", "shared")

    # ---- 引擎纹理 ----
    for name in ("Title.png", "Title2.png", "Title3.png", "Title4.png"):
        copy(os.path.join(art, name), os.path.join(ui_dir, name))

    # ---- mod.info 的 icon / poster（放 media/ui，随内容一起打包）----
    copy(os.path.join(BASE, f"icon_{v['art']}.png"),
         os.path.join(ui_dir, "ZomboidTitleCover_icon.png"))
    copy(os.path.join(BASE, f"poster_{v['art']}.png"),
         os.path.join(ui_dir, "ZomboidTitleCover_poster.png"))

    # ---- Lua ----
    copy(LUA_SRC, os.path.join(lua_dir, "ZomboidTitleCover_StaticMenu.lua"))

    # ---- 元数据 ----
    left = "960x1024" if v["art"] == "v16" else "1280x1280"
    write(os.path.join(item, "Contents", "mods", v["mod_id"], VERSION_DIR, "mod.info"),
          MOD_INFO.format(name=v["name"], mod_id=v["mod_id"], incompatible=INCOMPATIBLE,
                          canvas=v["canvas"]))
    write(os.path.join(item, "workshop.txt"),
          WORKSHOP_TXT.format(title=v["title"], canvas=v["canvas"]))
    write(os.path.join(item, "changelog.txt"), CHANGELOG.format(aspect=v["aspect"]))
    # 注意：README 正文里有 Java 代码的 `{`，所以用 replace 而不是 str.format
    readme = (README.replace("{name}", v["name"]).replace("{mod_id}", v["mod_id"])
                    .replace("{canvas}", v["canvas"]).replace("{t_left}", left)
                    .replace("{t_right}", left))
    write(os.path.join(item, "README.md"), readme)
    write(os.path.join(item, "CREDITS.md"), CREDITS)

    # ---- 工坊预览图（硬性规则：正方形 256/512，PNG，<= 1024000 字节）----
    copy(os.path.join(BASE, f"preview_{v['art']}.png"), os.path.join(item, "preview.png"))

    size = os.path.getsize(os.path.join(item, "preview.png"))
    assert size <= 1024000, f"{v['folder']}/preview.png 超过 1024000 字节：{size}"
    print(f"[{v['folder']}] 组装完成（preview {size/1024:.0f} KB）")


def main() -> int:
    if not os.path.isdir(os.path.join(BASE, "art")):
        print("缺少 base/art，请先运行 tools/make_title_cover.py", file=sys.stderr)
        return 1
    for v in VARIANTS:
        build_variant(v)
    print("两个变体都已生成。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
