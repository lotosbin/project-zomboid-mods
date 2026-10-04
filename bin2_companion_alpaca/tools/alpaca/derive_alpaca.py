"""从 CompanionDogs 的犬体模型程序化派生羊驼身体模型。

思路（全部在 bind pose 上做，因此不需要重新绑定骨骼、也不需要新动画剪辑）：
  1. 拉伸骨骼段：把关节的局部平移加上一个常量增量 (k-1)*rest，动画里的平移通道同样处理，
     于是"骨头变长"在 24 个剪辑里一致生效（平移通道是逐帧采样的，加常量不会破坏原有动作）。
  2. 骨架姿态增量：给指定骨骼在**父骨骼空间**左乘一个常量四元数，把犬的低头长颈改成羊驼的
     高抬长颈（脖子抬起、头回落成 S 形、耳朵立起来）。同样在全部剪辑里一致生效。
  3. 网格形变：按蒙皮权重混合的区域缩放（躯干变圆）、沿法线的羊毛绒面起伏（fuzz）、
     由变形后几何重算法线。
  4. 重打包 GLB，并把内嵌贴图换成羊驼毛绒贴图，得到一个自洽、可离线渲染的模型。

用法：
  python derive_alpaca.py --src <Retriever_Body.glb> --texture <Alpaca.png> --out <Alpaca_Body.glb>
"""

import argparse
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_util import (  # noqa: E402
    Glb, quat_axis_angle, quat_mul, quat_to_mat, world_matrices,
)

# ---------------------------------------------------------------- 参数表
# 骨骼段长度倍率：t_new = t + (k-1) * t_rest（对逐帧变化的通道也安全）
BONE_LEN = {
    # 颈：羊驼的脖子是身体最显著的特征
    "Spine_04": 1.25,
    "Spine_05": 1.75,
    "neck": 2.85,
    "Bip01_Head": 1.16,
    # 躯干（背/腰链条，常量平移）：略微加长成桶状
    "Spine_01": 0.95,
    "Spine_02": 0.95,
    # 四肢：羊驼腿长
    "hip_f.L": 1.18, "thigh_f.L": 1.34, "leg_f.L": 1.34, "shin_f.L": 1.34, "Bip01_L_Foot": 1.12,
    "hip_f.R": 1.18, "thigh_f.R": 1.34, "leg_f.R": 1.34, "shin_f.R": 1.34, "Bip01_R_Foot": 1.12,
    "hip_b.L": 1.18, "thigh_b.L": 1.30, "leg_b.L": 1.30, "shin_b.L": 1.30, "foot_b.L": 1.12,
    "hip_b.R": 1.18, "thigh_b.R": 1.30, "leg_b.R": 1.30, "shin_b.R": 1.30, "foot_b.R": 1.12,
    # 尾巴：羊驼是短尾
    "tail_01": 0.80, "tail_02": 0.55, "tail_03": 0.50, "tail_04": 0.50, "tail_05": 0.50,
    # 耳朵：立起来的长香蕉耳（长度靠这里，方向靠 BONE_ROT）
    "Ear.L": 1.45, "Ear.R": 1.45,
    # 鼻/嘴：把犬的长吻收短，做出羊驼的钝吻
    "nose": 0.62,
    "mouth": 0.80,
    "tongue_1": 0.70, "tongue_2": 0.60, "tongue_3": 0.55, "tongue_4": 0.55,
}

# 骨骼姿态增量：(轴, 角度) —— 轴用**模型世界空间**的 rest 姿态表达，内部换算到父骨骼空间
#   world X 轴为横向（+X = 左），+Y 上，+Z 前（鼻尖方向）。
#   绕世界 +X 转正角度 = 把"朝前的向量"压低；所以抬脖子用负角度。
BONE_ROT = {
    "Spine_05": ("X", -6.0),
    "neck": ("X", -25.0),
    "Bip01_Head": ("X", 34.0),
    "Ear.L": ("X", -100.0),
    "Ear.R": ("X", -100.0),
    "tail_01": ("X", -25.0),
}

# 区域缩放：按蒙皮权重混合（避免硬边界接缝）。键是骨骼组，值是 (sx, sy, sz)
REGIONS = {
    "torso": {
        "bones": ["Spine_base", "Spine_01", "Spine_02", "Spine_03", "Spine_04", "Spine_05",
                  "hip_f.L", "hip_f.R", "hip_b.L", "hip_b.R"],
        "scale": (1.30, 1.05, 1.02),
    },
    "neck": {
        "bones": ["neck"],
        "scale": (1.45, 1.08, 1.45),
    },
    "head": {
        "bones": ["Bip01_Head", "nose", "mouth"],
        "scale": (1.06, 1.06, 1.02),
    },
}

# 羊毛绒面：沿法线做平滑噪声位移，幅度按骨骼区域权重衰减
FUZZ = {
    "amp": 0.0075,
    "bones": ["Spine_base", "Spine_01", "Spine_02", "Spine_03", "Spine_04", "Spine_05",
              "neck", "Bip01_Head", "tail_01", "tail_02", "thigh_f.L", "thigh_f.R",
              "thigh_b.L", "thigh_b.R"],
    "seed": 20261003,
}


def log(msg):
    print(f"[derive_alpaca] {msg}", flush=True)


# ---------------------------------------------------------------- 骨架改动


def rest_translation(node):
    return np.array(node.get("translation", [0.0, 0.0, 0.0]), dtype=float)


def apply_bone_lengths(G, factors):
    """把每个骨骼的局部平移加上常量增量，rest 与全部动画通道一起改。"""
    nodes = G.g["nodes"]
    name_of = {}
    for i, n in enumerate(nodes):
        name_of[n.get("name")] = i
    touched = {}
    for name, k in factors.items():
        if abs(k - 1.0) < 1e-9:
            continue
        i = name_of.get(name)
        if i is None:
            raise KeyError(f"BONE_LEN refers to a missing bone: {name}")
        t_rest = rest_translation(nodes[i])
        delta = (k - 1.0) * t_rest
        nodes[i]["translation"] = (t_rest * k).tolist()
        touched[name] = {"k": k, "rest": t_rest.tolist(), "delta": delta.tolist(), "channels": 0}
    for ai, anim in enumerate(G.g.get("animations", [])):
        for ci, ch in enumerate(anim["channels"]):
            if ch["target"]["path"] != "translation":
                continue
            i = ch["target"]["node"]
            name = nodes[i].get("name")
            if name not in touched:
                continue
            acc = anim["samplers"][ch["sampler"]]["output"]
            v = G.acc(acc).astype(float) + np.array(touched[name]["delta"])
            # 拆成独占 accessor：共享 accessor 会被叠加多次（详见 glb_util.detach_channel_output）
            G.detach_channel_output(ai, ci, v)
            touched[name]["channels"] += 1
    return touched


def apply_bone_rotations(G, deltas):
    """在父骨骼空间左乘常量四元数：q_new = q_delta ⊗ q_anim。rest 与全部动画通道一起改。"""
    _QD_CACHE.clear()
    nodes = G.g["nodes"]
    parent = G.parent_map()
    W = world_matrices(G.g)
    name_of = {n.get("name"): i for i, n in enumerate(nodes)}
    axis_world = {"X": np.array([1.0, 0, 0]), "Y": np.array([0, 1.0, 0]), "Z": np.array([0, 0, 1.0])}
    touched = {}
    for name, (axis, deg) in deltas.items():
        i = name_of.get(name)
        if i is None:
            raise KeyError(f"BONE_ROT refers to a missing bone: {name}")
        p = parent.get(i)
        rp = W[p][:3, :3] if p is not None else np.eye(3)
        # 世界轴换算到父骨骼局部空间（父骨骼世界旋转的转置 = 逆）
        axis_local = rp.T @ axis_world[axis]
        q_delta = quat_axis_angle(axis_local, deg)
        q_rest = np.array(nodes[i].get("rotation", [0.0, 0.0, 0.0, 1.0]), dtype=float)
        nodes[i]["rotation"] = quat_mul(q_delta, q_rest).tolist()
        touched[name] = {"axis_world": axis, "deg": deg, "axis_local": axis_local.tolist(),
                         "channels": 0, "parent": nodes[p].get("name") if p is not None else None}
    for ai, anim in enumerate(G.g.get("animations", [])):
        for ci, ch in enumerate(anim["channels"]):
            if ch["target"]["path"] != "rotation":
                continue
            i = ch["target"]["node"]
            name = nodes[i].get("name")
            if name not in touched:
                continue
            acc = anim["samplers"][ch["sampler"]]["output"]
            v = quat_mul_rows(qd_of(touched, name), G.acc(acc).astype(float))
            # 同上：旋转采样器也会被共用，必须拆开，否则角度被复合多次
            G.detach_channel_output(ai, ci, v)
            touched[name]["channels"] += 1
    return touched


def quat_mul_rows(q, rows):
    """q ⊗ 每一行（行向量批量 Hamilton 积）。"""
    ax, ay, az, aw = [float(x) for x in q]
    bx, by, bz, bw = rows[:, 0], rows[:, 1], rows[:, 2], rows[:, 3]
    return np.stack([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ], axis=1)


_QD_CACHE = {}


def qd_of(touched, name):
    """缓存每个骨骼的 q_delta，避免在逐帧循环里反复换算。"""
    key = name
    if key not in _QD_CACHE:
        t = touched[name]
        _QD_CACHE[key] = quat_axis_angle(np.array(t["axis_local"]), t["deg"])
    return _QD_CACHE[key]


# ---------------------------------------------------------------- 网格改动


def dominant_bones(G, joints, weights):
    idx = weights.argmax(axis=1)
    return joints[np.arange(len(joints)), idx]


def region_weights(G, names, joints, weights):
    """返回每个顶点落在给定骨骼组上的蒙皮权重之和（用于平滑混合，避免硬边界接缝）。

    向量化：把"骨骼名是否属于该组"预计算成按 skin 关节序号索引的查找表，
    再对 4 个蒙皮槽位做一次 gather。
    """
    names_all = G.node_names()
    joint_nodes = G.g["skins"][0]["joints"]
    mask = np.array([1.0 if names_all[n] in set(names) else 0.0 for n in joint_nodes])
    total = np.zeros(weights.shape[0], dtype=float)
    for slot in range(weights.shape[1]):
        total += weights[:, slot] * mask[joints[:, slot]]
    return np.clip(total, 0.0, 1.0)


def smooth_noise(pos, seed):
    """确定性平滑噪声（多频正弦叠加），输入顶点坐标，输出大致在 [-1, 1]。"""
    rng = np.random.RandomState(seed)
    out = np.zeros(len(pos))
    for f in (17.0, 29.0, 43.0):
        ph = rng.uniform(0, 2 * math.pi, 3)
        out += np.sin(f * pos[:, 0] + ph[0]) * np.sin(f * 1.13 * pos[:, 1] + ph[1]) * \
               np.sin(f * 0.87 * pos[:, 2] + ph[2])
    out /= 3.0
    return out


def recompute_normals(pos, indices):
    nrm = np.zeros_like(pos)
    tri = indices.reshape(-1, 3)
    p0, p1, p2 = pos[tri[:, 0]], pos[tri[:, 1]], pos[tri[:, 2]]
    fn = np.cross(p1 - p0, p2 - p0)
    for k in range(3):
        np.add.at(nrm, tri[:, k], fn)
    ln = np.linalg.norm(nrm, axis=1, keepdims=True)
    ln[ln == 0] = 1.0
    return nrm / ln


# ---------------------------------------------------------------- 蒙皮 / 落地


def skinned_rest(G):
    """按**当前**节点 TRS 做一次线性混合蒙皮，返回静止姿态下的顶点世界坐标。

    为什么需要它：改了骨骼的 rest 平移/旋转之后，rest pose 就不再等于 bind pose
    （inverseBindMatrices 是原始绑定的），所以"脚在哪儿"必须真的算一遍蒙皮，
    不能直接看 POSITION 属性。
    """
    prim = G.g["meshes"][0]["primitives"][0]
    pos = G.acc(prim["attributes"]["POSITION"]).astype(float)
    jnt = G.acc(prim["attributes"]["JOINTS_0"])
    wgt = G.acc(prim["attributes"]["WEIGHTS_0"]).astype(float)
    wgt = wgt / np.clip(wgt.sum(axis=1, keepdims=True), 1e-9, None)

    skin = G.g["skins"][0]
    joints = skin["joints"]
    ibm = G.acc(skin["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4)
    ibm = np.transpose(ibm, (0, 2, 1))  # glTF 列主序 -> 行主序
    W = world_matrices(G.g)

    mats = np.stack([W[joints[j]] @ ibm[j] for j in range(len(joints))])  # (J, 4, 4)
    out = np.zeros_like(pos)
    hom = np.concatenate([pos, np.ones((len(pos), 1))], axis=1)           # (V, 4)
    for slot in range(jnt.shape[1]):
        m = mats[jnt[:, slot]]                                            # (V, 4, 4)
        v = np.einsum("vij,vj->vi", m, hom)[:, :3]
        out += wgt[:, slot][:, None] * v
    return out


def ground_min_y(G):
    return float(skinned_rest(G).min(axis=0)[1])


def apply_root_lift(G, delta_y, bone="Spine_base"):
    """把骨架整体抬高 delta_y（世界 +Y）：给指定骨骼的局部平移加常量（rest + 全部动画通道）。

    选 Spine_base 而不是 Root_bone/Dummy01：后者参与引擎的位移与抖动，改动风险大；
    Spine_base 是"身体"的根，腿全挂在它下面，抬高它就是把整只动物抬起来。
    """
    if abs(delta_y) < 1e-6:
        return 0.0
    nodes = G.g["nodes"]
    parent = G.parent_map()
    W = world_matrices(G.g)
    i = G.node_index(bone)
    p = parent.get(i)
    # 世界 +Y 换算成父骨骼空间的向量
    rp = W[p][:3, :3] if p is not None else np.eye(3)
    local = rp.T @ np.array([0.0, delta_y, 0.0])
    t_rest = rest_translation(nodes[i])
    nodes[i]["translation"] = (t_rest + local).tolist()
    for ai, anim in enumerate(G.g.get("animations", [])):
        for ci, ch in enumerate(anim["channels"]):
            if ch["target"]["path"] != "translation" or ch["target"]["node"] != i:
                continue
            acc = anim["samplers"][ch["sampler"]]["output"]
            G.detach_channel_output(ai, ci, G.acc(acc).astype(float) + local)
    return delta_y


def apply_mesh_ops(G):
    prim = G.g["meshes"][0]["primitives"][0]
    attrs = prim["attributes"]
    pos_acc = attrs["POSITION"]
    nrm_acc = attrs["NORMAL"]
    jnt_acc = attrs["JOINTS_0"]
    wgt_acc = attrs["WEIGHTS_0"]
    idx_acc = prim["indices"]

    pos = G.acc(pos_acc).astype(float)
    joints = G.acc(jnt_acc)
    weights = G.acc(wgt_acc).astype(float)
    weights = weights / np.clip(weights.sum(axis=1, keepdims=True), 1e-9, None)
    indices = G.acc_flat(idx_acc).astype(np.int64)

    before = pos.copy()

    # 1) 区域缩放（按权重平滑混合，围绕 x=0 中线）
    report = {}
    for region, cfg in REGIONS.items():
        w = region_weights(G, cfg["bones"], joints, weights)
        if w.max() <= 0:
            report[region] = 0.0
            continue
        s = np.array(cfg["scale"])
        f = 1.0 + (s - 1.0) * w[:, None]
        pos = pos * f
        report[region] = float(w.max())

    # 2) 羊毛绒面
    w = region_weights(G, FUZZ["bones"], joints, weights)
    noise = smooth_noise(before, FUZZ["seed"])
    nrm_dir = G.acc(nrm_acc).astype(float)
    nrm_dir = nrm_dir / np.clip(np.linalg.norm(nrm_dir, axis=1, keepdims=True), 1e-9, None)
    pos = pos + nrm_dir * (FUZZ["amp"] * noise * w)[:, None]
    report["fuzz_max_weight"] = float(w.max())

    # 3) 法线
    new_nrm = recompute_normals(pos, indices)

    G.set_acc(pos_acc, pos.astype(np.float32))
    G.set_acc(nrm_acc, new_nrm.astype(np.float32))
    G.update_pos_minmax(pos_acc, pos)
    report["bbox_before"] = [before.min(axis=0).tolist(), before.max(axis=0).tolist()]
    report["bbox_after"] = [pos.min(axis=0).tolist(), pos.max(axis=0).tolist()]
    report["verts"] = int(pos.shape[0])
    report["tris"] = int(len(indices) // 3)
    return report


# ---------------------------------------------------------------- 贴图重打包


def repack_with_texture(G, image_bytes, image_index=0):
    """把所有 bufferView 紧凑重排，并把内嵌贴图换成给定的 PNG 字节。返回新 PNG 字节数。

    注意：base 与猫的 glb 里内嵌的图片其实都是 1x1 占位图（71 字节），游戏并不使用它 ——
    引擎按 `AnimalDefinitions.breeds[...].texture` 去 media/textures/Body/<Name>.png 取图。
    所以默认走 rename_embedded_image()，只有 --embed-texture 时才真的把 PNG 塞进 glb
    （便于把模型单独拿出去预览）。
    """
    g = G.g
    img = g["images"][image_index]
    img_bv = img.get("bufferView")
    if img_bv is None:
        raise ValueError("embedded image has no bufferView; nothing to replace")
    used = []
    for a in g["accessors"]:
        if "bufferView" in a:
            used.append(a["bufferView"])
    for im in g.get("images", []):
        if "bufferView" in im:
            used.append(im["bufferView"])
    newbin = bytearray()
    for i in sorted(set(used)):
        bv = g["bufferViews"][i]
        if i == img_bv:
            data = image_bytes
        else:
            start = bv.get("byteOffset", 0)
            data = G.bin[start:start + bv["byteLength"]]
        pad = (4 - len(newbin) % 4) % 4
        newbin += b"\x00" * pad
        bv["byteOffset"] = len(newbin)
        bv["byteLength"] = len(data)
        newbin += data
    img["mimeType"] = "image/png"
    g["buffers"][0]["byteLength"] = len(newbin)
    G.bin = bytes(newbin)
    return len(image_bytes)


# ---------------------------------------------------------------- 报告


def pose_metrics(G):
    """客观量出静止姿态的两个角度（都相对水平面，单位度）：

    neck_pitch   = Spine_05 关节 -> 头骨根 的方向仰角（脖子立起来多少）
    muzzle_pitch = 头骨根 -> 鼻尖 的方向仰角（口鼻朝上还是朝下）

    必须用数字而不是肉眼看图：「抬脖子」与「低头」两个角度互相耦合（头是脖子的子骨骼），
    盯着渲染图调很容易把口鼻越调越朝天。
    """
    W = world_matrices(G.g)
    idx = {G.g["nodes"][i].get("name"): i for i in range(len(G.g["nodes"]))}

    def p(name):
        return W[idx[name]][:3, 3]

    def axis_pitch(name):
        """骨骼自身局部 +Y（= 骨头指向子关节的方向）在世界空间的仰角。"""
        v = W[idx[name]][:3, 1]
        horiz = math.hypot(float(v[0]), float(v[2]))
        return math.degrees(math.atan2(float(v[1]), horiz))

    def pitch(a, b):
        v = b - a
        horiz = math.hypot(float(v[0]), float(v[2]))
        return math.degrees(math.atan2(float(v[1]), horiz))

    return {
        # 脖子真正的"立起来多少"看 neck 骨头自身的方向：Spine_05 那一段是朝前的，
        # 从 Spine_05 原点到头骨的向量只有 35 度，会把脖子角度严重低估。
        "neck_pitch": axis_pitch("neck"),
        "head_bone_pitch": axis_pitch("Bip01_Head"),
        "muzzle_pitch": pitch(p("Bip01_Head"), p("nose")),
        "spine05_to_head_pitch": pitch(p("Spine_05"), p("Bip01_Head")),
        "withers_y": float(p("Spine_base")[1]),
        "head_y": float(p("Bip01_Head")[1]),
        "nose_z": float(p("nose")[2]),
    }


def joint_report(G, keys):
    W = world_matrices(G.g)
    name_of = {}
    for i, n in enumerate(G.g["nodes"]):
        name_of[n.get("name")] = i
    out = {}
    for k in keys:
        i = name_of.get(k)
        if i is not None and i in W:
            out[k] = [round(float(v), 4) for v in W[i][:3, 3]]
    return out


def rename_embedded_image(G, name, image_index=0, material_index=0):
    """把内嵌图片与材质的名字改成羊驼的贴图名。

    内嵌图是占位图，改名字零成本；而离线渲染器（tools/alpaca/render_glb.py）在没有 --texture 时
    会按这个名字去 media/textures/Body/ 找外置贴图，所以改名能让预览直接拿到正确毛色。
    """
    g = G.g
    if g.get("images"):
        g["images"][image_index]["name"] = name
    if g.get("materials"):
        g["materials"][material_index]["name"] = name
    return name


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    mod42 = os.path.abspath(os.path.join(here, "..", "..", "Contents", "mods", "CompanionDogsAlpaca", "42"))
    default_src = ("/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/"
                   "108600/3740052292/mods/CompanionDogs/42/media/models_X/Skinned/Retriever_Body.glb")

    ap = argparse.ArgumentParser(description="derive the alpaca body from the CompanionDogs dog body")
    ap.add_argument("--src", default=default_src)
    ap.add_argument("--texture", default=os.path.join(mod42, "media", "textures", "Body", "Alpaca.png"))
    ap.add_argument("--out", default=os.path.join(mod42, "media", "models_X", "Skinned", "Alpaca_Body.glb"))
    ap.add_argument("--no-fuzz", action="store_true")
    ap.add_argument("--embed-texture", action="store_true",
                    help="embedd the alpaca atlas into the glb (only for standalone previews; "
                         "the game reads media/textures/Body/<texture>.png instead)")
    ap.add_argument("--set-rot", action="append", default=[], metavar="BONE=DEG",
                    help="override a BONE_ROT entry, e.g. --set-rot Bip01_Head=55 (axis stays X)")
    ap.add_argument("--set-len", action="append", default=[], metavar="BONE=K",
                    help="override a BONE_LEN entry, e.g. --set-len neck=2.8")
    ap.add_argument("--out-suffix", default="", help="suffix for --out, for A/B experiments")
    ap.add_argument("--report", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "out",
                                                     "derive_report.json"))
    args = ap.parse_args()

    if args.no_fuzz:
        FUZZ["amp"] = 0.0
    for spec in args.set_rot:
        name, _, deg = spec.partition("=")
        axis = BONE_ROT.get(name, ("X", 0.0))[0]
        BONE_ROT[name] = (axis, float(deg))
        log(f"override BONE_ROT[{name}] = ({axis}, {deg})")
    for spec in args.set_len:
        name, _, k = spec.partition("=")
        BONE_LEN[name] = float(k)
        log(f"override BONE_LEN[{name}] = {k}")
    if args.out_suffix:
        root, ext = os.path.splitext(args.out)
        args.out = root + args.out_suffix + ext

    log(f"source : {args.src}")
    G = Glb(args.src)
    ground_before = ground_min_y(G)
    before_joints = joint_report(G, ["Spine_base", "Spine_05", "neck", "Bip01_Head", "nose",
                                     "Bip01_L_Foot", "tail_05", "Ear.L"])
    log(f"ground (skinned rest min-y, before): {ground_before:.4f}")

    len_report = apply_bone_lengths(G, BONE_LEN)
    rot_report = apply_bone_rotations(G, BONE_ROT)
    mesh_report = apply_mesh_ops(G)

    # 腿变长之后脚会沉到地面以下（rest pose 已不等于 bind pose），把整只动物抬回地面
    ground_raw = ground_min_y(G)
    lift = apply_root_lift(G, ground_before - ground_raw)
    ground_after = ground_min_y(G)
    log(f"ground raw after lengthening: {ground_raw:.4f} -> lifted by {lift:.4f} -> {ground_after:.4f}")

    # 内嵌图：默认只改名（内嵌的本来就是 1x1 占位图，游戏按 breeds[...].texture 取外置贴图）
    tex_name = os.path.splitext(os.path.basename(args.texture))[0]
    if args.embed_texture and os.path.isfile(args.texture):
        tex_size = repack_with_texture(G, open(args.texture, "rb").read())
        rename_embedded_image(G, tex_name)
        log(f"embedded texture replaced with {os.path.basename(args.texture)} ({tex_size} bytes)")
    elif args.embed_texture:
        log(f"WARNING: --embed-texture given but texture missing: {args.texture}")
    else:
        rename_embedded_image(G, tex_name)
        log(f"embedded placeholder image renamed to '{tex_name}' (external texture: media/textures/Body/{tex_name}.png)")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    total = G.save(args.out)

    after_joints = joint_report(G, ["Spine_base", "Spine_05", "neck", "Bip01_Head", "nose",
                                    "Bip01_L_Foot", "tail_05", "Ear.L"])
    skinned = skinned_rest(G)
    skin_bbox = [skinned.min(axis=0).tolist(), skinned.max(axis=0).tolist()]
    bones = len(G.g["skins"][0]["joints"])
    clips = [a.get("name") for a in G.g.get("animations", [])]
    report = {
        "src": args.src,
        "out": args.out,
        "bytes": total,
        "bones": bones,
        "clips": len(clips),
        "clip_names": clips,
        "bone_len": len_report,
        "bone_rot": rot_report,
        "mesh": mesh_report,
        "joints_before": before_joints,
        "joints_after": after_joints,
        "ground_before": ground_before,
        "ground_raw_after_lengthening": ground_raw,
        "root_lift": lift,
        "ground_after": ground_after,
        "skinned_bbox": skin_bbox,
        "skinned_height": skin_bbox[1][1] - skin_bbox[0][1],
        "skinned_length": skin_bbox[1][2] - skin_bbox[0][2],
        "skinned_width": skin_bbox[1][0] - skin_bbox[0][0],
    }
    os.makedirs(os.path.dirname(args.report), exist_ok=True)
    with open(args.report, "w") as fh:
        json.dump(report, fh, indent=2, ensure_ascii=False)

    log(f"wrote {args.out} ({total} bytes), bones={bones}, clips={len(clips)}")
    log(f"withers y: {before_joints['Spine_base'][1]} -> {after_joints['Spine_base'][1]}")
    log(f"neck base y: {before_joints['neck'][1]} -> {after_joints['neck'][1]}")
    log(f"head base  : {before_joints['Bip01_Head']} -> {after_joints['Bip01_Head']}")
    log(f"nose tip   : {before_joints['nose']} -> {after_joints['nose']}")
    log(f"bbox after : {mesh_report['bbox_after']}")
    log(f"skinned rest bbox (what the game draws): {skin_bbox}")
    log(f"skinned height {report['skinned_height']:.4f} / length {report['skinned_length']:.4f} "
        f"/ width {report['skinned_width']:.4f} (model units; in-game metres = this x size)")
    log(f"report     : {args.report}")


if __name__ == "__main__":
    main()
