"""校验翻译文件（发布前必跑）。

手册列出的四类坑，全部变成断言：
  1. JSON 必须能解析，且**不能有重复键**（重复键会被后一个静默吃掉，玩家看到的是旧文案）；
  2. 文件不能带 BOM（带 BOM 的语言文件不编译，而且报错会指向另一个文件）；
  3. 同一批键必须在所有语言里都存在（少一个，那个语言就显示原始 key）；
  4. 文案里不能有裸的 `%`：getText 是格式化器，裸 `%` 会让显示它的窗口崩掉（`%1` / `%%` 合法）。

另外检查本模组自己新增的键是否齐全（物种/品种/类型/moodle/沙盒/物品）。

用法：
  python check_translations.py
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TRANS = os.path.abspath(os.path.join(
    HERE, "..", "..", "Contents", "mods", "CompanionDogsAlpaca", "42",
    "media", "lua", "shared", "Translate"))

LANGS = ["EN", "CN", "CH"]

# 手册第 6 节：这些键支持 `_<species>` 后缀（base 会先找带后缀的版本）。
SPECIES_KEYS = [
    "IGUI_PD_ScanStray", "IGUI_PD_ScanTitle", "IGUI_PD_PauseGrowthTip", "IGUI_PD_BadFood",
    "IGUI_PD_AlertFullDesc", "IGUI_PD_AlertQuietDesc", "IGUI_PD_AlertLockedTip",
    "IGUI_PD_HuntModeDesc", "IGUI_PD_TrickGotoDesc", "IGUI_PD_TrickDistractDesc",
    "IGUI_PD_TrickDistractDone", "IGUI_PD_TrickSniffDesc", "IGUI_PD_TrickFetchDesc",
    "IGUI_PD_TrickSniffStopDesc", "IGUI_PD_TrickFetchStopDesc", "IGUI_PD_TrickNeedsBag",
    "IGUI_PD_TrickGotoPick", "IGUI_PD_TrickSniffNoItem", "IGUI_PD_TrickFetchNoItem",
    "IGUI_PD_AlertGroup", "IGUI_PD_DogLost", "IGUI_PD_Refused_nodata",
    "IGUI_PD_KennelStatusNoData", "IGUI_PD_Moodle_Sick_desc", "IGUI_PD_Moodle_Weak_desc",
    "IGUI_PD_Moodle_Hunger_desc", "IGUI_PD_Moodle_Thirst_desc", "IGUI_PD_Moodle_Rested_desc",
    "IGUI_PD_Moodle_Grief_desc",
]

# 本模组自己新增、必须存在的键（物种三键 + 组名 + 品种 + 类型 + moodle + 沙盒 + 物品）
BREED_KEYS = ["alpaca", "alpacafawn", "alpacabrown", "alpacablack", "alpacagrey",
              "alpacarosegrey", "alpacasuri"]
ENGINE_BREEDS = ["alpaca", "alpaca_fawn", "alpaca_brown", "alpaca_black", "alpaca_grey",
                 "alpaca_rose", "alpaca_suri"]
OWN_IGUI_KEYS = (
    ["IGUI_PD_SpeciesNoun_alpaca", "IGUI_PD_Young_alpaca", "IGUI_PD_SpeciesDisplay_alpaca",
     "IGUI_Animal_Group_alpaca", "IGUI_PD_BreedDesc_alpaca",
     "IGUI_PD_Moodle_AlpacaFleece", "IGUI_PD_Moodle_AlpacaFleece_desc"]
    + ["IGUI_PD_Breed_" + k for k in BREED_KEYS]
    + ["IGUI_Breed_" + k for k in ENGINE_BREEDS]
    + ["IGUI_AnimalType_alpaca" + s for s in ("male", "female", "pup")]
)
SANDOX_KEYS = ["Sandbox_CompanionAlpaca", "Sandbox_CompanionAlpaca_AlpacaSpawnMultiplier",
               "Sandbox_CompanionAlpaca_AlpacaSpawnMultiplier_tooltip"]
ITEM_KEYS = ["Base.CompanionDogsAlpacaMeat"]


def load_no_dup(path, errs):
    raw = open(path, "rb").read()
    if raw.startswith(b"\xef\xbb\xbf"):
        errs.append(f"{path}: has a UTF-8 BOM (will not compile in game)")
    text = raw.decode("utf-8")
    dups = []

    def hook(pairs):
        seen = set()
        for k, _ in pairs:
            if k in seen:
                dups.append(k)
            seen.add(k)
        return dict(pairs)

    try:
        data = json.loads(text, object_pairs_hook=hook)
    except Exception as exc:  # noqa: BLE001
        errs.append(f"{path}: JSON parse error: {exc}")
        return {}
    for d in dups:
        errs.append(f"{path}: duplicate key '{d}'")
    return data


def check_percent(path, data, errs):
    bad = re.compile(r"%(?![0-9]|%)")
    for k, v in data.items():
        if isinstance(v, str) and bad.search(v):
            errs.append(f"{path}: key '{k}' has a bare '%' (getText formatter will crash the screen)")


def main():
    ap = argparse.ArgumentParser(description="validate the addon translation files")
    ap.add_argument("--dir", default=TRANS)
    args = ap.parse_args()

    errs = []
    per_lang = {}
    for lang in LANGS:
        d = os.path.join(args.dir, lang)
        if not os.path.isdir(d):
            errs.append(f"missing language folder: {d}")
            continue
        files = {}
        for name in ("IG_UI.json", "Sandbox.json", "ItemName.json"):
            p = os.path.join(d, name)
            if not os.path.isfile(p):
                errs.append(f"missing file: {p}")
                continue
            data = load_no_dup(p, errs)
            check_percent(p, data, errs)
            files[name] = data
        per_lang[lang] = files

    # 键集合必须逐语言一致
    if per_lang:
        base_lang = "EN" if "EN" in per_lang else list(per_lang)[0]
        for name in ("IG_UI.json", "Sandbox.json", "ItemName.json"):
            base_keys = set(per_lang.get(base_lang, {}).get(name, {}))
            for lang, files in per_lang.items():
                keys = set(files.get(name, {}))
                for k in sorted(base_keys - keys):
                    errs.append(f"{lang}/{name}: missing key '{k}' (present in {base_lang})")
                for k in sorted(keys - base_keys):
                    errs.append(f"{lang}/{name}: extra key '{k}' (not in {base_lang})")

    # 本模组自己的键
    igui = per_lang.get("EN", {}).get("IG_UI.json", {})
    required = OWN_IGUI_KEYS + [k + "_alpaca" for k in SPECIES_KEYS]
    for k in required:
        if k not in igui:
            errs.append(f"EN/IG_UI.json: missing required key '{k}'")
    sandbox = per_lang.get("EN", {}).get("Sandbox.json", {})
    for k in SANDOX_KEYS:
        if k not in sandbox:
            errs.append(f"EN/Sandbox.json: missing required key '{k}'")
    items = per_lang.get("EN", {}).get("ItemName.json", {})
    for k in ITEM_KEYS:
        if k not in items:
            errs.append(f"EN/ItemName.json: missing required key '{k}'")

    for lang, files in per_lang.items():
        counts = ", ".join(f"{n}={len(v)}" for n, v in sorted(files.items()))
        print(f"{lang}: {counts}")
    print(f"required own keys: {len(required)} igui + {len(SANDOX_KEYS)} sandbox + {len(ITEM_KEYS)} item")
    for e in errs:
        print(f"ERROR: {e}")
    print("RESULT: " + ("FAIL" if errs else "OK"))
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
