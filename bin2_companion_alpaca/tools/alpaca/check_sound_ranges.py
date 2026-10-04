"""跨文件不变量：声音脚本的 distanceMax 必须与 CD.registerVoices 的可听范围一致。

为什么需要它：手册与 base 的注释都强调"改一个就要改另一个"——
`media/scripts/sounds_cdalpaca.txt` 里每个 clip 的 `distanceMax` 决定 FMOD 的距离衰减，
而 `CompanionDogsAlpaca_Breed.lua` 里 `CD.registerVoices(map, engineVoices, ranges)` 的第三个参数
决定**服务端把声音包发给谁**。两边不一致的症状很隐蔽：要么远处玩家收不到该听见的声音，
要么收到了一个听不见的包（白费带宽）。

用法：
  python check_sound_ranges.py
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD42 = os.path.abspath(os.path.join(HERE, "..", "..", "Contents", "mods", "CompanionDogsAlpaca", "42"))
SCRIPT = os.path.join(MOD42, "media", "scripts", "sounds_cdalpaca.txt")
LUA = os.path.join(MOD42, "media", "lua", "shared", "CompanionDogsAlpaca_Breed.lua")


def parse_script(path):
    """返回 {sound_name: max(distanceMax)} 与 {sound_name: loop?}。"""
    text = open(path, encoding="utf-8").read()
    out = {}
    loops = {}
    # 注意：声音块的名字与 "{" 之间通常夹着一行 /* 注释 */（base 与猫都这么写），
    # 所以不能要求名字后面紧跟 "{"。
    for m in re.finditer(r"sound\s+(\w+)[^\n]*\n\s*\{(.*?)\n\s*\}", text, re.S):
        name, body = m.group(1), m.group(2)
        dists = [int(d) for d in re.findall(r"distanceMax\s*=\s*(\d+)", body)]
        mins = [int(d) for d in re.findall(r"distanceMin\s*=\s*(\d+)", body)]
        if not dists:
            out[name] = None
            continue
        out[name] = max(dists)
        loops[name] = bool(re.search(r"\bloop\s*=\s*true", body))
        # distanceMin 是每个 clip 必填，且必须 < max，否则反向 rolloff 不衰减
        if not mins:
            out[name] = ("missing-distanceMin", max(dists))
        elif min(mins) >= max(dists):
            out[name] = ("min>=max", max(dists))
    return out, loops


def parse_lua(path):
    """返回 registerVoices 的 {sound: range}、引擎声音数组，以及 CD.SOUND_LOOPED 的登记集合。"""
    text = open(path, encoding="utf-8").read()
    ranges = {}
    # 第三个参数：最后一次 "}, {" 之后到 "})" 之前的那张表
    tail = text[text.rfind("}, {"):]
    block = tail[:tail.find("})")]
    for k, v in re.findall(r"(\w+)\s*=\s*(\d+)", block):
        ranges[k] = int(v)
    eng = re.search(r"\},\s*\{([^}]*)\},", text)
    engine = re.findall(r'"(\w+)"', eng.group(1)) if eng else []
    looped = set(re.findall(r"CD\.SOUND_LOOPED\.(\w+)\s*=\s*true", text))
    return ranges, engine, looped


def main():
    ap = argparse.ArgumentParser(description="check that sound distanceMax matches registerVoices ranges")
    ap.add_argument("--script", default=SCRIPT)
    ap.add_argument("--lua", default=LUA)
    args = ap.parse_args()

    errs = []
    script, loops = parse_script(args.script)
    ranges, engine, lua_looped = parse_lua(args.lua)

    for name, val in sorted(script.items()):
        if isinstance(val, tuple):
            errs.append(f"{name}: {val[0]} in the sound script")
            continue
        if val is None:
            errs.append(f"{name}: no distanceMax on any clip")
            continue
        if name not in ranges:
            errs.append(f"{name}: present in the sound script but not in registerVoices ranges")
            continue
        if ranges[name] != val:
            errs.append(f"{name}: distanceMax={val} in the script vs range={ranges[name]} in Lua")
    for name in sorted(set(ranges) - set(script)):
        errs.append(f"{name}: registered in Lua but missing from the sound script")

    looped = sorted(n for n, v in loops.items() if v)
    # 循环音必须在 Lua 里登记 CD.SOUND_LOOPED，否则走出听觉范围后不会停
    for name in looped:
        if name not in lua_looped:
            errs.append(f"{name}: loop=true in the script but not registered in CD.SOUND_LOOPED")
    for name in sorted(lua_looped - set(looped)):
        errs.append(f"{name}: registered in CD.SOUND_LOOPED but the script does not set loop=true")

    print(f"sound script : {len(script)} sounds, looped: {', '.join(looped) or 'none'}")
    print(f"lua ranges   : {len(ranges)} entries; engine voices: {', '.join(engine) or 'none'}")
    print(f"lua looped   : {', '.join(sorted(lua_looped)) or 'none'}")
    for name in sorted(script):
        print(f"  {name:22s} distanceMax={script[name]} range={ranges.get(name)} loop={loops.get(name)}")
    for e in errs:
        print(f"ERROR: {e}")
    print("RESULT: " + ("FAIL" if errs else "OK"))
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
