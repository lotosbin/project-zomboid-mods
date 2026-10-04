"""扫描 neck / Bip01_Head 两个姿态增量，按目标角度挑最合适的一对。

为什么需要它：头骨是脖子的子骨骼，「抬脖子」会连带把头抬起来，而「低头」是相对脖子转的。
光看渲染图很容易把口鼻越调越朝天（试过：neck=-52 + head=-26 时口鼻仰角到 +50 度）。
这里改成量角度：目标是脖子立到 ~70 度、口鼻基本水平（约 -5 度），在网格上取误差最小的一对。

用法：
  python tune_pose.py                # 扫描默认网格并打印前 8 名
  python tune_pose.py --rows 5 --cols 7
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import derive_alpaca as D  # noqa: E402
from glb_util import Glb  # noqa: E402

TARGET_NECK = 74.0
TARGET_MUZZLE = -5.0


def measure(src, neck_deg, head_deg):
    """在给定姿态增量下量一次角度（每次都从源模型重新开始，避免增量叠加）。"""
    g = Glb(src)
    D.BONE_ROT["neck"] = ("X", neck_deg)
    D.BONE_ROT["Bip01_Head"] = ("X", head_deg)
    D.apply_bone_lengths(g, D.BONE_LEN)
    D.apply_bone_rotations(g, D.BONE_ROT)
    m = D.pose_metrics(g)
    return m


def main():
    ap = argparse.ArgumentParser(description="grid-search the alpaca neck/head pose deltas")
    ap.add_argument("--src", default=D.__dict__.get("DEFAULT_SRC") or
                    ("/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/"
                     "108600/3740052292/mods/CompanionDogs/42/media/models_X/Skinned/Retriever_Body.glb"))
    ap.add_argument("--neck-from", type=float, default=-70.0)
    ap.add_argument("--neck-to", type=float, default=-20.0)
    ap.add_argument("--head-from", type=float, default=-30.0)
    ap.add_argument("--head-to", type=float, default=40.0)
    ap.add_argument("--rows", type=int, default=6)
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--top", type=int, default=8)
    args = ap.parse_args()

    def lin(a, b, i, n):
        return a if n <= 1 else a + (b - a) * i / (n - 1)

    rows = []
    for i in range(args.rows):
        neck = lin(args.neck_from, args.neck_to, i, args.rows)
        for j in range(args.cols):
            head = lin(args.head_from, args.head_to, j, args.cols)
            m = measure(args.src, neck, head)
            err = abs(m["neck_pitch"] - TARGET_NECK) + 2.0 * abs(m["muzzle_pitch"] - TARGET_MUZZLE)
            rows.append((err, neck, head, m))
    rows.sort(key=lambda r: r[0])

    print(f"target: neck_pitch={TARGET_NECK} muzzle_pitch={TARGET_MUZZLE}")
    print(f"{'err':>7} {'neck':>7} {'head':>7} {'neckP':>8} {'muzP':>8} {'headY':>7} {'noseZ':>7}")
    for err, neck, head, m in rows[:args.top]:
        print(f"{err:7.2f} {neck:7.1f} {head:7.1f} {m['neck_pitch']:8.1f} {m['muzzle_pitch']:8.1f} "
              f"{m['head_y']:7.3f} {m['nose_z']:7.3f}")
    err, neck, head, m = rows[0]
    print(f"\nbest: --set-rot neck={neck:.0f} --set-rot Bip01_Head={head:.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
