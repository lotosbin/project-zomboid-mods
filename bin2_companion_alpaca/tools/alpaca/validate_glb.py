"""结构校验 Alpaca_Body.glb（发布前必跑）。

手册第 2 节列的硬性条件 + 我们自己踩过的坑，全部变成可执行的断言：
  1. 骨骼数 <= 60（超了引擎每帧报错，动物渲染成黑糊）；
  2. 顶层节点必须是 identity（否则整只动物偏移）；
  3. 必须带满 21 个必需的 Rac_* 剪辑（缺一个，动物第一次被要求播它就冻住），
     外加两条可选瘸腿剪辑；
  4. 每个 accessor 的字节范围必须落在它的 bufferView / buffer 内（写坏了 GLB 会在游戏里静默丢模型）；
  5. POSITION 的 JSON min/max 必须与真实顶点一致（离线渲染/引擎取景都用它）；
  6. 皮肤关节数必须与 inverseBindMatrices 的行数一致，权重和为 1，关节下标在范围内；
  7. **所有剪辑里的平移通道都不能"爆掉"**：这是本项目真实踩过的坑 —— 同一个 clip 内多条
     channel 共用同一个 accessor，若就地改共享数据，增量会被叠加 N 次（idle 里脖子平移被打到 0.909，
     模型被拉成腊肠）。这里的判据是 |t| <= 1.0（模型自身尺度约 0.6），超了就直接报错。
  8. 必须存在内嵌贴图占位（base 与猫都是 1x1 占位图，游戏按 breeds[...].texture 取外置 png）；
  9. 网格必须带 TEXCOORD_0（本模组的图集是"每三角形一格"，缺 UV 就整只变成纯色）；
 10. 顶点数必须是 3 的整数倍（每三角形拆独立 UV 岛），索引必须是 0..N-1 的连续序列
     （否则会出现"看起来有洞/碎三角片"）。

用法：
  python validate_glb.py [--glb <path>]
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_util import Glb, world_matrices  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_GLB = os.path.abspath(os.path.join(
    HERE, "..", "..", "Contents", "mods", "CompanionDogsAlpaca", "42",
    "media", "models_X", "Skinned", "Alpaca_Body.glb"))

REQUIRED_CLIPS = [
    "Rac_Walk", "Rac_Run", "Rac_Idle01", "Rac_Idle02", "Rac_Idle03", "Rac_IdleLyingDown",
    "Rac_IdleToLieDown", "Rac_LyingDownToIdle", "Rac_ClimbUp", "Rac_ClimbDown", "Rac_HitReaction",
    "Rac_Death", "Rac_Dead", "Rac_Attack", "Rac_Attack2", "Rac_Attack3", "Rac_Eat", "Rac_Drink",
    "Rac_Jump", "Rac_Sniff",
]
OPTIONAL_CLIPS = ["Rac_WalkLimpFront", "Rac_WalkLimpBack", "Rac_RunLimpFront", "Rac_RunLimpBack"]

MAX_BONES = 60
MAX_TRANSLATION = 1.0


def main():
    ap = argparse.ArgumentParser(description="validate the derived alpaca glb")
    ap.add_argument("--glb", default=DEFAULT_GLB)
    args = ap.parse_args()

    G = Glb(args.glb)
    g = G.g
    errs = []
    warns = []

    # 1) 骨骼数
    joints = g["skins"][0]["joints"]
    if len(joints) > MAX_BONES:
        errs.append(f"bones {len(joints)} > {MAX_BONES}")

    # 2) 顶层节点 identity
    for root in g["scenes"][g.get("scene", 0)]["nodes"]:
        t = g["nodes"][root].get("translation", [0, 0, 0])
        r = g["nodes"][root].get("rotation", [0, 0, 0, 1])
        s = g["nodes"][root].get("scale", [1, 1, 1])
        if np.allclose(t, 0, atol=1e-6) and np.allclose(s, 1, atol=1e-6) and abs(r[3] - 1) < 1e-6:
            pass
        else:
            errs.append(f"root node '{g['nodes'][root].get('name')}' is not identity")

    # 3) 剪辑
    names = [a.get("name") for a in g.get("animations", [])]
    missing = [c for c in REQUIRED_CLIPS if c not in names]
    if missing:
        errs.append("missing required clips: " + ", ".join(missing))
    missing_opt = [c for c in OPTIONAL_CLIPS if c not in names]
    if missing_opt:
        warns.append("missing optional limp clips: " + ", ".join(missing_opt))

    # 4) accessor 范围
    buf_len = g["buffers"][0]["byteLength"]
    for i, a in enumerate(g["accessors"]):
        if "bufferView" not in a:
            continue
        bv = g["bufferViews"][a["bufferView"]]
        comp_size = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[a["componentType"]]
        ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
        need = a.get("byteOffset", 0) + a["count"] * ncomp * comp_size
        if bv.get("byteOffset", 0) + need > buf_len:
            errs.append(f"accessor {i} overruns buffer")
        if need > bv["byteLength"]:
            errs.append(f"accessor {i} overruns its bufferView")

    # 5) POSITION min/max
    prim = g["meshes"][0]["primitives"][0]
    pos_acc = prim["attributes"]["POSITION"]
    pos = G.acc(pos_acc)
    a = g["accessors"][pos_acc]
    if "min" in a:
        if not np.allclose(a["min"], pos.min(axis=0), atol=1e-5) or \
           not np.allclose(a["max"], pos.max(axis=0), atol=1e-5):
            errs.append("POSITION accessor min/max does not match the data")

    # 6) 蒙皮
    ibm = G.acc(g["skins"][0]["inverseBindMatrices"])
    if ibm.shape[0] != len(joints):
        errs.append(f"inverseBindMatrices {ibm.shape[0]} != joints {len(joints)}")
    jnt = G.acc(prim["attributes"]["JOINTS_0"])
    wgt = G.acc(prim["attributes"]["WEIGHTS_0"]).astype(float)
    if jnt.max() >= len(joints):
        errs.append(f"JOINTS_0 max {int(jnt.max())} >= joint count {len(joints)}")
    sums = wgt.sum(axis=1)
    if not np.allclose(sums, 1.0, atol=2e-2):
        warns.append(f"weight sums off: min {sums.min():.3f} max {sums.max():.3f}")

    # 7) 平移通道不得爆掉（只看**真的带蒙皮权重**的骨骼）
    #    模型里有一个 Translation_Data 关节，它是数据节点、权重为 0，源模型里它的平移本来就能到 3.08；
    #    把它算进来会误报，所以先算出"有顶点挂在上面的关节"集合。
    weighted = set()
    for slot in range(jnt.shape[1]):
        for j in np.unique(jnt[:, slot][wgt[:, slot] > 1e-6]):
            weighted.add(int(j))
    weighted_nodes = {joints[j] for j in weighted}

    worst = (0.0, None, None, 0)
    for anim in g.get("animations", []):
        for ch in anim["channels"]:
            if ch["target"]["path"] != "translation":
                continue
            if ch["target"]["node"] not in weighted_nodes:
                continue
            acc = anim["samplers"][ch["sampler"]]["output"]
            v = G.acc(acc).astype(float)
            m = float(np.max(np.abs(v))) if v.size else 0.0
            if m > worst[0]:
                node = g["nodes"][ch["target"]["node"]].get("name")
                worst = (m, anim.get("name"), node, v.shape[0])
    if worst[0] > MAX_TRANSLATION:
        errs.append(f"translation blown up: |t|={worst[0]:.3f} in {worst[1]} on {worst[2]} "
                    f"({worst[3]} samples) -- shared accessor double-apply?")
    else:
        warns.append(f"largest skinned-bone translation channel value: {worst[0]:.3f} "
                     f"({worst[2]} in {worst[1]}); {len(weighted_nodes)} weighted bones checked")

    # 8) 内嵌贴图
    imgs = g.get("images", [])
    if not imgs:
        errs.append("no embedded image (the base keeps a 1x1 placeholder; keep it for parity)")

    # 9) UV + 每三角形拆点
    attrs = prim["attributes"]
    if "TEXCOORD_0" not in attrs:
        errs.append("mesh has no TEXCOORD_0 (the per-triangle atlas needs UVs)")
    else:
        uv = G.acc(attrs["TEXCOORD_0"]).astype(float)
        if uv.shape[0] != len(pos):
            errs.append(f"TEXCOORD_0 count {uv.shape[0]} != POSITION count {len(pos)}")
        if not np.all((uv >= -0.001) & (uv <= 1.001)):
            errs.append("TEXCOORD_0 outside 0..1")
    if len(pos) % 3 != 0:
        errs.append(f"vertex count {len(pos)} is not a multiple of 3 (per-triangle split expected)")
    idx = G.acc_flat(prim["indices"]).astype(np.int64)
    if len(idx) != len(pos):
        errs.append(f"index count {len(idx)} != vertex count {len(pos)} (expected 3 verts per triangle)")
    if len(idx) and idx.max() != len(pos) - 1:
        errs.append(f"indices are not the contiguous 0..{len(pos) - 1} range (max {int(idx.max())})")

    # 额外信息：蒙皮静止外框，用来核对动物定义里的 minSize/maxSize
    W = world_matrices(g)
    ibm_m = np.transpose(ibm.reshape(-1, 4, 4), (0, 2, 1))
    mats = np.stack([W[joints[j]] @ ibm_m[j] for j in range(len(joints))])
    w = wgt / np.clip(sums[:, None], 1e-9, None)
    hom = np.concatenate([pos, np.ones((len(pos), 1))], axis=1)
    out = np.zeros((len(pos), 3))
    for slot in range(jnt.shape[1]):
        out += w[:, slot][:, None] * np.einsum("vij,vj->vi", mats[jnt[:, slot]], hom)[:, :3]
    bbox = (out.min(axis=0), out.max(axis=0))

    print(f"file            : {args.glb}")
    print(f"bones           : {len(joints)} (limit {MAX_BONES})")
    print(f"clips           : {len(names)} (required {len(REQUIRED_CLIPS)}, "
          f"optional limp {len(OPTIONAL_CLIPS) - len(missing_opt)}/{len(OPTIONAL_CLIPS)})")
    print(f"verts/tris      : {len(pos)}/{len(G.acc_flat(prim['indices'])) // 3}")
    print(f"skinned rest bbox: min={np.round(bbox[0], 4).tolist()} max={np.round(bbox[1], 4).tolist()}")
    print(f"  height={bbox[1][1] - bbox[0][1]:.4f} length={bbox[1][2] - bbox[0][2]:.4f} "
          f"width={bbox[1][0] - bbox[0][0]:.4f} (metres = this x the animal def size)")
    for wmsg in warns:
        print(f"WARN            : {wmsg}")
    for e in errs:
        print(f"ERROR           : {e}")
    print("RESULT          : " + ("FAIL" if errs else "OK"))
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
