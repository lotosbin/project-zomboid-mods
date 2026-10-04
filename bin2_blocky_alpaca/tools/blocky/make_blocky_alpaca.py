#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""方块（voxel / MC 味）羊驼网格生成器 —— 生成 CompanionDogsBlockyAlpaca 的模型与图集。

与 `build_alpaca_from_cc0.py`（写实羊驼：把 CC0 网格仿射传递进来）是**两条独立路线**：
本脚本的几何**完全由脚本生成**（长方体阵列），不含任何第三方资产，因此没有任何授权牵连。

核心思路
--------
1. 骨架照旧用 base 的 Raccoon 骨架（55 骨骼），并套用羊驼那套已验证的骨长/骨旋转调参
   （`derive_alpaca.BONE_LEN/BONE_ROT`）—— 动画剪辑因此仍然"演得对"。
2. **脚要落地**：羊驼调参把腿拉到脚骨 y=-0.043（写实网格是靠"目标形状落地"掩盖了这个偏差，
   而方块是硬绑在骨头上的，骨头在哪方块就在哪）。所以这里数值求解一个腿链缩放 k，
   把四只脚骨拉到 y≈+0.006，方块才站得住。
3. **盒子长在骨头上**：每个盒子由"骨头 -> 子骨头"的骨段推导（位置、朝向、长度都取自骨架），
   横截面是正方形（voxel 观感）。因此换调参也不会错位。
4. **单骨骼硬绑定**：每个盒子的每个顶点权重 100% 给一根骨头（不需要平滑、不会有权重撕裂），
   动画时盒子像刚体一样跟着骨头动 —— 这正是 MC 那种观感。
5. **逆蒙皮烘焙**：`v_bind = D_b⁻¹ · v_target`，`n_bind = (D_b⁻¹)ᵀ · n_target`。
   于是"静止时 LBS 结果 == 我摆的盒子"，动画时按骨头相对运动形变。
   （不这么做就会出现"碎瓷片"，见 docs/pz-cc0-mesh-retarget.md 第 3 节。）
6. UV：每个盒子面一个图集格子；贴图按材质类上色（毛色亮/主/暗 + 蹄/鼻/眼/耳），
   方块风格不需要绒毛场，只加一点点逐格噪声。

用法：
    python3 make_blocky_alpaca.py                 # 写模型 + 4 张图集
    python3 make_blocky_alpaca.py --render        # 顺便渲染 out/ 下的验证图
"""
import argparse
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ALPACA_TOOLS = os.path.abspath(os.path.join(HERE, "..", "..", "..",
                                            "bin2_companion_alpaca", "tools", "alpaca"))
sys.path.insert(0, ALPACA_TOOLS)

import derive_alpaca as D                     # noqa: E402  骨长 / 骨旋转调参表
from glb_util import Glb, world_matrices      # noqa: E402

DEFAULT_BASE = ("/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/"
                "108600/3740052292/mods/CompanionDogs/42/media/models_X/Skinned/Retriever_Body.glb")

MOD = os.path.abspath(os.path.join(HERE, "..", "..", "Contents", "mods", "CompanionDogsBlockyAlpaca", "42"))
DEFAULT_OUT = os.path.join(MOD, "media", "models_X", "Skinned", "BlockyAlpaca_Body.glb")
DEFAULT_TEX = os.path.join(MOD, "media", "textures", "Body")

ATLAS = 512
GRID = 14          # 14x14 = 196 个格子；本模型 23 个盒子 x 6 面 = 138 面
CELL = ATLAS // GRID
INSET = 4
FOOT_TARGET_Y = 0.018      # 脚骨高度：蹄盒挂在脚骨下方，盒底正好落在 y=0 的地面

# 材质类（图集里的调色板槽位）
M_BODY, M_TOP, M_BELLY, M_LEG, M_HOOF, M_MUZZLE, M_NOSE, M_EYE, M_EAR, M_EARIN = range(10)

# 4 种方块毛色；pattern=spots 的会在身体格子上随机点深色块
COATS = {
    "BlockyAlpaca":       ("Cream",  (238, 228, 206), (250, 244, 228), (206, 190, 160), "solid"),
    "BlockyAlpaca_Brown": ("Brown",  (150, 108, 74),  (182, 140, 100), (108, 76, 50),   "solid"),
    "BlockyAlpaca_Gray":  ("Gray",   (152, 150, 148), (186, 184, 182), (110, 108, 106), "solid"),
    "BlockyAlpaca_Spot":  ("Spotted", (228, 216, 194), (242, 234, 216), (120, 96, 72),  "spots"),
}


def log(msg):
    print(f"[blocky] {msg}", flush=True)


# ----------------------------------------------------------------- 骨架准备

def load_skeleton(base_path):
    """载入 base 骨架 + 羊驼调参 + 腿链缩放（让脚骨落地），返回 (Glb, names, W, joints, ibm, invD, D_b)。"""
    g = Glb(base_path)
    D.apply_bone_lengths(g, D.BONE_LEN)
    D.apply_bone_rotations(g, D.BONE_ROT)
    names = g.node_names()
    # 调参之后的节点位移快照：腿链缩放要在这个基础上做
    T0 = {n: list(g.g["nodes"][i].get("translation", [0.0, 0.0, 0.0]))
          for i, n in enumerate(names)}
    kids = {}
    for i, n in enumerate(names):
        for c in g.g["nodes"][i].get("children", []):
            kids[names[c]] = n
    joints = g.g["skins"][0]["joints"]
    jn = [names[j] for j in joints]
    ibm = g.acc(g.g["skins"][0]["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4)
    ibm = np.transpose(ibm, (0, 2, 1))

    # ---- 直腿化 ----------------------------------------------------------------
    # 骨架静止姿态是"犬科锯齿腿"（膝前/飞节后）。方块造型要的是竖直方柱，
    # 所以把四条腿链的关节位置摆成竖直列。关键：**只改位移，不改旋转** ——
    # 剪辑会replace 掉被动画的骨骼旋转，所以改旋转会连带改变动画的摆动方向；
    # 只改位移（把骨头挪到竖直列上）则动画的父级坐标系不变，摆动方向保持原样。
    LEG_CHAINS = {
        "f.L": ["hip_f.L", "thigh_f.L", "leg_f.L", "shin_f.L", "Bip01_L_Foot"],
        "f.R": ["hip_f.R", "thigh_f.R", "leg_f.R", "shin_f.R", "Bip01_R_Foot"],
        "b.L": ["hip_b.L", "thigh_b.L", "leg_b.L", "shin_b.L", "foot_b.L"],
        "b.R": ["hip_b.R", "thigh_b.R", "leg_b.R", "shin_b.R", "foot_b.R"],
    }
    nchan = [0]
    for tag, chain in LEG_CHAINS.items():
        W = world_matrices(g.g)
        pos = [joint_pos(W, names, n) for n in chain]
        lens = [float(np.linalg.norm(pos[i + 1] - pos[i])) for i in range(len(pos) - 1)]
        scale = (pos[0][1] - FOOT_TARGET_Y) / max(sum(lens), 1e-9)   # 腿总长按落地要求缩放
        cum = 0.0
        for i in range(1, len(chain)):
            cum += lens[i - 1] * scale
            target = np.array([pos[0][0], pos[0][1] - cum, pos[0][2]])
            parent = chain[i - 1]
            pw = W[names.index(parent)]
            local = np.linalg.inv(pw) @ np.append(target, 1.0)
            nch = shift_bone_local(g, names, chain[i], local[:3])
            nchan[0] += nch
            W = world_matrices(g.g)      # 父级动了，子级的世界矩阵要重算
    # ---- 脖子竖直化 ------------------------------------------------------------
    # 与腿同理：只改位移。羊驼骨架的"下颈段"原本几乎是**水平前伸**的（Δz 0.165 / Δy 0.028），
    # 方块造型要的是竖直方柱，所以把 neck / Bip01_Head 摆到胸骨上方（保持骨段长度）。
    W = world_matrices(g.g)
    chest = joint_pos(W, names, "Spine_05")
    neck_p, head_p = joint_pos(W, names, "neck"), joint_pos(W, names, "Bip01_Head")
    l1 = float(np.linalg.norm(neck_p - chest))
    l2 = float(np.linalg.norm(head_p - neck_p))
    LEAN_Y, LEAN_Z = 0.78, 0.62                    # 下颈段方向：斜向前上方（约 38°）
    nrm = float(np.hypot(LEAN_Y, LEAN_Z))
    neck_t = chest + np.array([0.0, l1 * LEAN_Y / nrm, l1 * LEAN_Z / nrm])
    head_t = neck_t + np.array([0.0, l2, 0.010])
    for bone, target in (("neck", neck_t), ("Bip01_Head", head_t)):
        pw = world_matrices(g.g)[names.index(names[names.index(bone)])] if False else None
        W = world_matrices(g.g)
        parent = {n: kids[n] for n in ("neck", "Bip01_Head")}[bone]
        pw = W[names.index(parent)]
        local = np.linalg.inv(pw) @ np.append(target, 1.0)
        nchan[0] += shift_bone_local(g, names, bone, local[:3])
    W = world_matrices(g.g)
    log(f"  位移通道共改写 {nchan[0]} 条（rest 与剪辑必须一致，否则动画会散架）")
    log(f"  neck: {np.round(joint_pos(W, names, 'Spine_05'), 4).tolist()} -> "
        f"{np.round(joint_pos(W, names, 'neck'), 4).tolist()} -> "
        f"head {np.round(joint_pos(W, names, 'Bip01_Head'), 4).tolist()}")

    W = world_matrices(g.g)
    for tag, chain in LEG_CHAINS.items():
        log(f"  leg {tag}: hip={np.round(joint_pos(W, names, chain[0]), 4).tolist()} "
            f"foot={np.round(joint_pos(W, names, chain[-1]), 4).tolist()}")

    D_b = np.stack([W[joints[j]] @ ibm[j] for j in range(len(joints))])
    invD = np.stack([np.linalg.inv(D_b[j]) for j in range(len(joints))])
    bone_index = {n: i for i, n in enumerate(jn)}
    return g, names, W, joints, jn, D_b, invD, bone_index


def shift_bone_local(g, names, name, new_local):
    """把某骨骼的**局部平移**改成 new_local，并同步改它在**全部剪辑**里的位移通道。

    这一步不能省：每条剪辑对每根骨头都有位移轨道，运行时位移轨道会**覆盖**静止位移。
    只改静止位移的话，静止渲染一切正常、一播动画就被打回剪辑的旧位置 ——
    硬绑定的方块会当场散架（写实网格因为权重混合只是"被拉伸"，不容易看出来）。
    base 的骨长调参（derive_alpaca.apply_bone_lengths）也是这么做的：rest 与通道一起改。
    """
    i = names.index(name)
    node = g.g["nodes"][i]
    old = np.array(node.get("translation", [0.0, 0.0, 0.0]), dtype=float)
    delta = np.array(new_local, dtype=float) - old
    node["translation"] = [float(v) for v in new_local]
    patched = 0
    for ai, anim in enumerate(g.g.get("animations", [])):
        for ci, ch in enumerate(anim["channels"]):
            if ch["target"]["path"] != "translation" or ch["target"]["node"] != i:
                continue
            acc = anim["samplers"][ch["sampler"]]["output"]
            # 共享 accessor 会被叠加多次，必须拆成独占 accessor（glb_util 里的老坑）
            g.detach_channel_output(ai, ci, g.acc(acc).astype(float) + delta)
            patched += 1
    return patched


def joint_pos(W, names, name):
    return W[names.index(name)][:3, 3].astype(float)


def segment_box(W, names, bone_name, child_name, hw, grow0=0.0, grow1=0.0):
    """由骨段构造一个"方棱柱"盒子的 8 个角点（世界/静止空间）。

    hw 是横截面半宽（正方形）；grow0/grow1 沿骨轴在两端各延伸多少（米）。
    朝向：u = 骨段方向，v/w 取与 u 垂直的两个稳定轴。
    """
    p0 = joint_pos(W, names, bone_name)
    p1 = joint_pos(W, names, child_name)
    u = p1 - p0
    L = float(np.linalg.norm(u))
    if L < 1e-9:
        u = np.array([0.0, 1.0, 0.0])
    else:
        u = u / L
    # 选一个与 u 最不平行的世界轴做叉乘，得到稳定的 v/w
    axis = np.array([1.0, 0.0, 0.0]) if abs(u[0]) < 0.9 else np.array([0.0, 0.0, 1.0])
    v = np.cross(u, axis)
    v /= max(np.linalg.norm(v), 1e-9)
    w = np.cross(u, v)
    a = p0 - u * grow0
    b = p1 + u * grow1
    corners = []
    for s in (a, b):
        for sv in (-1, 1):
            for sw in (-1, 1):
                corners.append(s + v * (hw * sv) + w * (hw * sw))
    return np.array(corners)          # 顺序：a(-,-) a(-,+) a(+,-) a(+,+) b(-,-) ... （见 faces）


def axis_box(lo, hi):
    """轴对齐盒子的 8 个角点：lo/hi 是 (x,y,z)，顺序随便传（内部会归一化）。"""
    lo, hi = np.array(lo, dtype=float), np.array(hi, dtype=float)
    lo, hi = np.minimum(lo, hi), np.maximum(lo, hi)
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    return np.array([[x0, y0, z0], [x0, y0, z1], [x0, y1, z0], [x0, y1, z1],
                     [x1, y0, z0], [x1, y0, z1], [x1, y1, z0], [x1, y1, z1]], dtype=float)


# 角点索引 -> 6 个面（每面 4 个角点，逆时针朝外）
BOX_FACES = [
    ((0, 1, 3, 2), (0, -1, 0)),   # -Y 肚皮
    ((4, 6, 7, 5), (0, 1, 0)),    # +Y 背
    ((0, 4, 5, 1), (0, 0, 1)),    # +Z 前
    ((2, 3, 7, 6), (0, 0, -1)),   # -Z 后
    ((0, 2, 6, 4), (-1, 0, 0)),   # -X
    ((1, 5, 7, 3), (1, 0, 0)),    # +X
]


def build_boxes(W, names):
    """方块羊驼的盒子清单：用骨段给位置/朝向，尺寸与材质类显式指定。

    盒子顺序就是图集格子的顺序（每盒 6 面），所以**只能往后追加，不能重排**，
    否则已有的贴图会错位（贴图与 UV 是一一对应的）。
    """
    boxes = []

    def seg(bone, child, hw, mat_body=M_BODY, grow0=0.0, grow1=0.0,
            mat_top=None, mat_belly=None, mat_front=None, mat_back=None):
        pts = segment_box(W, names, bone, child, hw, grow0, grow1)
        boxes.append(dict(name=f"{bone}->{child}", pts=pts, m_body=mat_body,
                          m_top=mat_body if mat_top is None else mat_top,
                          m_belly=mat_body if mat_belly is None else mat_belly,
                          m_front=mat_body if mat_front is None else mat_front,
                          m_back=mat_body if mat_back is None else mat_back))

    def ax(name, lo, hi, mat_body=M_BODY, mat_top=None, mat_belly=None,
           mat_front=None, mat_back=None):
        boxes.append(dict(name=name, pts=axis_box(lo, hi), m_body=mat_body,
                          m_top=mat_body if mat_top is None else mat_top,
                          m_belly=mat_body if mat_belly is None else mat_belly,
                          m_front=mat_body if mat_front is None else mat_front,
                          m_back=mat_body if mat_back is None else mat_back))

    def px(n, axis=0):
        return float(joint_pos(W, names, n)[axis])

    # ---- 躯干：两段（后桶 + 前胸），围绕脊柱骨段，横截面略扁
    yb0, yb1 = px("Spine_base", 1), px("Spine_05", 1)
    ax("torso", (-0.058, min(yb0, yb1) - 0.062, -0.130), (0.058, max(yb0, yb1) + 0.062, 0.012),
       mat_body=M_BODY, mat_top=M_TOP, mat_belly=M_BELLY)
    ax("chest", (-0.056, min(yb0, yb1) - 0.048, 0.012), (0.056, max(yb0, yb1) + 0.070, 0.118),
       mat_body=M_BODY, mat_top=M_TOP, mat_belly=M_BELLY, mat_front=M_BODY)

    # ---- 脖子：两段（下段跟 neck 骨，上段跟头骨）
    seg("neck", "Bip01_Head", 0.036, mat_body=M_BODY, grow0=-0.02)
    seg("Spine_05", "neck", 0.044, mat_body=M_BODY, grow0=0.01)

    # ---- 头 + 吻 + 耳 + 眼
    hy, hz = px("Bip01_Head", 1), px("Bip01_Head", 2)
    ey = px("Ear.L", 1)
    ax("head", (-0.044, hy - 0.030, hz - 0.062), (0.044, max(hy + 0.046, ey - 0.028), hz + 0.040),
       mat_body=M_BODY, mat_top=M_TOP, mat_belly=M_BELLY, mat_front=M_BODY)
    ax("muzzle", (-0.028, hy - 0.024, hz + 0.040), (0.028, hy + 0.012, hz + 0.082),
       mat_body=M_MUZZLE, mat_top=M_MUZZLE, mat_belly=M_MUZZLE, mat_front=M_NOSE)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        ex = abs(px("Ear.L", 0))
        ax(f"ear.{side}", (sx * (ex - 0.012), ey - 0.026, hz + 0.012),
           (sx * (ex + 0.012), ey + 0.050, hz + 0.040),
           mat_body=M_EAR, mat_top=M_EAR, mat_belly=M_EAR, mat_front=M_EARIN, mat_back=M_EAR)
        ax(f"eye.{side}", (sx * 0.044, hy + 0.008, hz + 0.014),
           (sx * 0.050, hy + 0.026, hz + 0.036), mat_body=M_EYE, mat_top=M_EYE,
           mat_belly=M_EYE, mat_front=M_EYE, mat_back=M_EYE)

    # ---- 四条腿：大腿 / 小腿 / 蹄（每段一根骨头）
    LEGS = [
        ("f.L", "hip_f.L", "thigh_f.L", "leg_f.L", "shin_f.L", "Bip01_L_Foot", 0.026),
        ("f.R", "hip_f.R", "thigh_f.R", "leg_f.R", "shin_f.R", "Bip01_R_Foot", 0.026),
        ("b.L", "hip_b.L", "thigh_b.L", "leg_b.L", "shin_b.L", "foot_b.L", 0.028),
        ("b.R", "hip_b.R", "thigh_b.R", "leg_b.R", "shin_b.R", "foot_b.R", 0.028),
    ]
    for tag, hip, thigh, knee, ankle, foot, hw in LEGS:
        # 三段：大腿 / 小腿 / 踝（踝段用蹄色 = 深色"蹄子"）。
        # 各段之间留重叠：刚性方块没有皮肤可拉伸，剪辑把腿拉长时靠重叠吸收，
        # 否则跑步（gallop 拉伸最大）会在关节处露缝。
        #
        # 注意不要另做"独立的蹄盒并绑到脚骨"：跑步剪辑里脚骨的位移最大，
        # 独立盒子会当场飞出去（实测过）。把最下一段直接染成蹄色，结构上不可能脱离。
        seg(thigh, knee, hw, mat_body=M_LEG, grow0=0.022, grow1=0.014)
        seg(knee, ankle, hw * 0.90, mat_body=M_LEG, grow0=0.014, grow1=0.008)
        seg(ankle, foot, hw * 0.95, mat_body=M_HOOF, grow0=0.012, grow1=0.020,
            mat_top=M_HOOF, mat_belly=M_HOOF, mat_front=M_HOOF, mat_back=M_HOOF)

    # ---- 尾巴：一小段（跟 tail_01）
    seg("tail_01", "tail_02", 0.022, mat_body=M_BELLY, grow0=0.035, grow1=0.012)

    return boxes


# ----------------------------------------------------------------- 蒙皮烘焙

def bake_boxes(boxes, names, jn, invD, bone_of_box):
    """把盒子顶点从"静止空间"反解到绑定空间；返回 (pos, nrm, uv, joints, weights, tri_mat)。

    每个顶点权重 100% 给所属骨头：v_bind = D_b⁻¹ · v_target，n_bind = (D_b⁻¹)ᵀ · n_target。
    """
    pos, nrm, joints, weights, tri_mat = [], [], [], [], []
    for bi, box in enumerate(boxes):
        b = jn.index(bone_of_box[bi])
        M = invD[b][:3, :3]
        t = invD[b][:3, 3]
        n3 = np.transpose(M)          # (D⁻¹)ᵀ 的 3x3 部分（纯线性部分）
        FACE_MAT = ("m_belly", "m_top", "m_front", "m_back", "m_body", "m_body")
        for fi, (quad, n) in enumerate(BOX_FACES):
            nvec = np.array(n, dtype=float)
            mat = box[FACE_MAT[fi]]
            for k in range(2):
                a, bb, c = (quad[0], quad[1], quad[2]) if k == 0 else (quad[0], quad[2], quad[3])
                for vi in (a, bb, c):
                    v = box["pts"][vi]
                    pos.append(M @ v + t)
                    nv = n3 @ nvec
                    ln = float(np.linalg.norm(nv))
                    nrm.append(nv / (ln if ln > 1e-9 else 1.0))
                    joints.append([b, 0, 0, 0])
                    weights.append([1.0, 0.0, 0.0, 0.0])
                tri_mat.append(mat)
    return (np.array(pos, dtype=np.float32), np.array(nrm, dtype=np.float32),
            np.array(joints, dtype=np.uint16), np.array(weights, dtype=np.float32),
            np.array(tri_mat, dtype=np.int32))


def per_face_cells(nboxes):
    """每个盒子面一个格子：返回每三角形 3 个归一化 UV（同一面的两个三角形共用一格）。"""
    tri_uv = []
    for bi in range(nboxes):
        for fi in range(6):
            cell = bi * 6 + fi
            cxi, cyi = cell % GRID, cell // GRID
            x0, y0 = cxi * CELL + INSET, cyi * CELL + INSET
            w = CELL - 2 * INSET
            # 上三角：左下 / 右下 / 上中；下三角：左上 / 右上 / 下中
            up = [(x0, y0 + w), (x0 + w, y0 + w), (x0 + w / 2.0, y0)]
            dn = [(x0, y0), (x0 + w, y0), (x0 + w / 2.0, y0 + w)]
            tri_uv.append([(p[0] / ATLAS, p[1] / ATLAS) for p in up])
            tri_uv.append([(p[0] / ATLAS, p[1] / ATLAS) for p in dn])
    return np.array(tri_uv, dtype=np.float32)


# ----------------------------------------------------------------- 图集

def paint_atlas(tri_mat, coat, nboxes, style="solid", seed=11):
    """按"每盒面一格"上色。方块风格：纯色 + 极轻噪声；spots 会给毛色格子随机点深色。"""
    main, light, dark = coat[1], coat[2], coat[3]
    lut = np.array([
        main,                     # M_BODY
        light,                    # M_TOP
        dark,                     # M_BELLY
        tuple(int(c * 0.88) for c in dark),   # M_LEG
        (58, 50, 44),             # M_HOOF
        (74, 62, 58),             # M_MUZZLE
        (34, 30, 28),             # M_NOSE
        (16, 14, 14),             # M_EYE
        main,                     # M_EAR
        (198, 142, 140),          # M_EARIN
    ], dtype=np.float32)

    ncell = nboxes * 6
    cells = np.zeros((GRID * GRID, 3), dtype=np.float32)
    rng = np.random.RandomState(seed)
    for i in range(ncell):
        cells[i] = lut[int(tri_mat[i * 2])]
    if style == "spots":
        # 只给"毛色"类（0/1/2/8）随机加深，蹄/鼻/眼保持干净
        body_cells = [i for i in range(ncell) if int(tri_mat[i * 2]) in (0, 1, 2, 8)]
        for i in rng.choice(body_cells, size=max(1, len(body_cells) // 4), replace=False):
            cells[i] = np.array(dark, dtype=np.float32) * 0.92
    # 逐格轻微明暗（voxel 贴图的手工感）
    cells *= (1.0 + rng.uniform(-0.05, 0.05, size=(len(cells), 1))).astype(np.float32)

    img = np.zeros((GRID, GRID, 3), dtype=np.float32)
    img.reshape(-1, 3)[:] = cells
    img = np.repeat(np.repeat(img, CELL, axis=0), CELL, axis=1)
    full = np.zeros((ATLAS, ATLAS, 3), dtype=np.float32) + 24.0
    h = GRID * CELL
    full[:h, :h] = img[:h, :h]
    return np.clip(full, 0, 255).astype(np.uint8)


# ----------------------------------------------------------------- 主流程

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--texture-dir", default=DEFAULT_TEX)
    ap.add_argument("--render", action="store_true", help="顺便渲染验证图到 out/")
    args = ap.parse_args()

    g, names, W, joints, jn, D_b, invD, bone_index = load_skeleton(args.base)

    boxes = build_boxes(W, names)
    # 每个盒子绑哪根骨头：按盒子名/来源骨决定
    bone_of_box = []
    for b in boxes:
        nm = b["name"]
        if nm in ("torso",):
            bone_of_box.append("Spine_base")
        elif nm in ("chest",):
            bone_of_box.append("Spine_05")
        elif nm.startswith("neck->"):
            bone_of_box.append("neck")
        elif nm.startswith("Spine_05->neck"):
            bone_of_box.append("Spine_05")
        elif nm in ("head", "muzzle"):
            bone_of_box.append("Bip01_Head")
        elif nm.startswith("ear."):
            bone_of_box.append("Ear." + nm.split(".")[1])
        elif nm.startswith("eye."):
            bone_of_box.append("Bip01_Head")
        elif nm.startswith("hoof."):
            side = nm.split(".")[1]
            bone_of_box.append("Bip01_L_Foot" if side == "f.L" else
                               "Bip01_R_Foot" if side == "f.R" else
                               "foot_b.L" if side == "b.L" else "foot_b.R")
        elif "->" in nm:
            bone_of_box.append(nm.split("->")[0])      # 腿段 / 尾巴：直接用源骨
        else:
            raise SystemExit(f"未指定骨头的盒子: {nm}")

    pos, nrm, jnt, wgt, tri_mat = bake_boxes(boxes, names, jn, invD, bone_of_box)
    ntri = len(tri_mat)
    uv = per_face_cells(len(boxes)).reshape(-1, 2)
    assert len(uv) == len(pos), f"UV 数 {len(uv)} != 顶点数 {len(pos)}"

    # sanity：方块是刚体硬绑定，静止形状必须与盒子一致；检查退化与盒子数
    tri = np.arange(len(pos)).reshape(-1, 3)
    area = np.linalg.norm(np.cross(pos[tri[:, 1]] - pos[tri[:, 0]],
                                   pos[tri[:, 2]] - pos[tri[:, 0]]), axis=1) * 0.5
    log(f"mesh: {len(boxes)} boxes -> {len(pos)} verts / {ntri} tris; "
        f"degenerate={int((area < 1e-12).sum())}; "
        f"bones used={len(set(bone_of_box))}")
    # 静止形状（= 目标空间）bbox，用于和动物定义里的尺寸标定对照
    tgt = np.concatenate([b["pts"] for b in boxes])
    log(f"rest shape bbox: min={np.round(tgt.min(0), 4).tolist()} max={np.round(tgt.max(0), 4).tolist()}")
    log(f"height={float(tgt[:, 1].max() - tgt[:, 1].min()):.4f} "
        f"length={float(tgt[:, 2].max() - tgt[:, 2].min()):.4f} "
        f"width={float(tgt[:, 0].max() - tgt[:, 0].min()):.4f}")

    # ---- 写 glb
    prim = g.g["meshes"][0]["primitives"][0]

    def add_acc(arr, ctype, atype, with_minmax=False):
        bv = g.append_binary(arr.tobytes())
        acc = {"bufferView": bv, "componentType": ctype, "count": len(arr), "type": atype}
        if with_minmax:
            a = np.asarray(arr, dtype=float).reshape(len(arr), -1)
            acc["min"] = a.min(0).tolist()
            acc["max"] = a.max(0).tolist()
        g.g["accessors"].append(acc)
        return len(g.g["accessors"]) - 1

    prim["attributes"] = {
        "POSITION": add_acc(pos, 5126, "VEC3", True),
        "NORMAL": add_acc(nrm, 5126, "VEC3"),
        "TEXCOORD_0": add_acc(uv, 5126, "VEC2"),
        "JOINTS_0": add_acc(jnt.astype(np.uint16), 5123, "VEC4"),
        "WEIGHTS_0": add_acc(wgt, 5126, "VEC4"),
    }
    prim["indices"] = add_acc(np.arange(len(pos), dtype=np.uint32), 5125, "SCALAR")
    prim["material"] = 0
    prim["mode"] = 4
    D.rename_embedded_image(g, "BlockyAlpaca")
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    total = g.save(args.out)
    log(f"wrote {args.out} ({total} bytes)")

    # ---- 写 4 张图集
    os.makedirs(args.texture_dir, exist_ok=True)
    from PIL import Image
    for key, (en, main, light, dark, style) in COATS.items():
        arr = paint_atlas(tri_mat, (en, main, light, dark), len(boxes), style=style)
        p = os.path.join(args.texture_dir, key + ".png")
        Image.fromarray(arr, "RGB").save(p, format="PNG", optimize=True)
        log(f"atlas {key:22s} {en:8s} {style:6s} -> {os.path.getsize(p)} bytes")

    if args.render:
        import subprocess
        outdir = os.path.join(HERE, "out")
        os.makedirs(outdir, exist_ok=True)
        tex = os.path.join(args.texture_dir, "BlockyAlpaca.png")
        for tag, extra in (("views", ["--views"]),
                           ("walk", ["--anim", "Rac_Walk", "--time", "0.3", "--azimuth", "100"]),
                           ("eat", ["--anim", "Rac_Eat", "--time", "0.5", "--azimuth", "100"])):
            cmd = [sys.executable, os.path.join(ALPACA_TOOLS, "render_glb.py"), args.out,
                   os.path.join(outdir, f"blocky_{tag}.png"), "--size", "900x740",
                   "--texture", tex] + extra
            subprocess.run(cmd, capture_output=True)
            log(f"rendered out/blocky_{tag}.png")
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
