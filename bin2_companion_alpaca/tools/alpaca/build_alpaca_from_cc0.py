"""用 CC0 的 Quaternius Alpaca 网格替换"拉长脖子的狗"。

背景与数学
----------
base 的骨架（Raccoon_Skeleton，55 骨骼）与 24 个 Rac_* 剪辑必须保留：引擎按动画集的名字播剪辑，
换动画等于重做整套状态机。所以做法是**把 CC0 的羊驼网格搬进 base 的绑定空间**，
让它被 base 的骨骼驱动 —— 这叫逐骨骼仿射传递（per-bone affine transfer）：

  记  D_b = Wn_rest(b) · IBM_dog(b)          # base 骨骼在**我们调过比例后的静止姿态**下的蒙皮矩阵
      S_b = Wc_pose(b) · IBM_cc0(b)          # CC0 骨骼在其**自然站姿** P 下的蒙皮矩阵
  取  T_b = D_b⁻¹ · M · S_b                    # 每个 CC0 骨骼 -> 对应 base 骨骼的传递矩阵
  顶点  v' = Σ_i w_i · T_{map(j_i)} · v      # 按原蒙皮权重线性混合

于是：
  * 静止时 p = D_b·T_b·v = M·S_b·v ⇒ 模型外观**就是 CC0 羊驼在姿态 P 下的样子**（与我们的比例调整无关）；
  * 播放剪辑时 p = Wn_anim·IBM_dog·T_b·v = (Wn_anim·Wn_rest⁻¹)·M·S_b·v
    ⇒ 羊驼被 base 骨骼的**相对运动**带动，剪辑不用改一个关键帧。

骨骼对应关系用**位置最近邻**自动求（两套骨架名字完全不同、拓扑也不同），少数用显式表覆盖。

贴图：CC0 模型按材质拆成 7 个 primitive 且**没有 UV**。所以网格合并后按三角形重排 UV
（每个三角形一个小格，格内填该三角形所属材质的颜色 + 绒毛噪声），7 个材质正好是
skin_light / skin / skin_dark / muzzle / hooves / eyes_black / eyes_white，
于是 7 种毛色只需要换"毛色三元组"，五官与蹄子保持固定。

用法：
  python build_alpaca_from_cc0.py                 # 生成 Alpaca_Body.glb + 7 张毛色图集
  python build_alpaca_from_cc0.py --pose-anim Idle --pose-time 0.3
  python build_alpaca_from_cc0.py --no-transfer   # 只打印诊断
"""

import argparse
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import derive_alpaca as D  # noqa: E402
from glb_util import Glb, mat_to_quat, quat_to_mat, world_matrices  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
MOD42 = os.path.abspath(os.path.join(HERE, "..", "..", "Contents", "mods", "CompanionDogsAlpaca", "42"))
DEFAULT_BASE = ("/Users/liubinbin/Library/Application Support/Steam/steamapps/workshop/content/"
                "108600/3740052292/mods/CompanionDogs/42/media/models_X/Skinned/Retriever_Body.glb")
DEFAULT_CC0 = os.path.join(HERE, "vendor", "alpaca_cc0.glb")

ATLAS = 512
GRID = 46               # 46x46 格；每格 11px（含 1px 出血边）
CELL = ATLAS // GRID    # 11
INSET = 2

# 我们这根骨头不参与传递（纯辅助/数据节点）
OUR_SKIP = {"Translation_Data", "Helper_foot_b.L", "Helper_foot_b.R",
            "Helper_shin_f.L", "Helper_shin_f.R"}

# 权威对应表：CC0 骨骼 -> 我们的骨骼（方向是 CC0 -> 我们，因为传递只需要这一个方向）。
# 依据是上一节打印出来的两边绑定姿态位置：CC0 的 +Z 朝头、+Y 朝上，命名里 Front=前腿、Back=后腿/背。
# 一个 CC0 骨骼可以映到多个我们的骨骼吗？不 —— 反过来可以（多个 CC0 骨骼映到同一个我们的骨骼），
# 权重会在同一根骨头上合并；我们这边多出来的关节由权重平滑自动摊开。
CC0_TO_OUR = {
    # 躯干与颈（CC0 是单链 Body->Back->Torso..->Neck1..3->Head，我们是"腰/胸/颈"三段式）
    "Body": "Spine_01",        # CC0 的躯干根在后腰
    "Back": "Spine_base",      # 鬐甲
    "Torso": "Spine_02",
    "Torso2": "Spine_04",
    "Torso3": "Spine_05",      # 前胸（前腿挂在它下面）
    "Neck1": "Spine_05",
    "Neck2": "neck",
    "Neck3": "Bip01_Head",
    "Head": "Bip01_Head",
    # 耳（CC0 每只耳 4 节，我们 1 节）
    "Ear1.L": "Ear.L", "Ear2.L": "Ear.L", "Ear3.L": "Ear.L", "Ear4.L": "Ear.L",
    "Ear1.R": "Ear.R", "Ear2.R": "Ear.R", "Ear3.R": "Ear.R", "Ear4.R": "Ear.R",
    # 前腿
    "FrontShoulder.L": "hip_f.L", "FrontUpperLeg.L": "thigh_f.L", "FrontLowerLeg.L": "shin_f.L",
    "FF.L": "Bip01_L_Foot", "IKFrontLeg.L": "Bip01_L_Foot", "PoleTarget.L": "hip_f.L",
    "FrontShoulder.R": "hip_f.R", "FrontUpperLeg.R": "thigh_f.R", "FrontLowerLeg.R": "shin_f.R",
    "FF.R": "Bip01_R_Foot", "IKFrontLeg.R": "Bip01_R_Foot", "PoleTarget.R": "hip_f.R",
    # 后腿
    "BackShoulder.L": "hip_b.L", "BackLeg.L": "thigh_b.L", "BackUpperLeg.L": "leg_b.L",
    "BackLowerLeg.L": "shin_b.L", "FFB.L": "foot_b.L", "IKBackLeg.L": "foot_b.L",
    "PoleTargetBack.L": "hip_b.L",
    "BackShoulder.R": "hip_b.R", "BackLeg.R": "thigh_b.R", "BackUpperLeg.R": "leg_b.R",
    "BackLowerLeg.R": "shin_b.R", "FFB.R": "foot_b.R", "IKBackLeg.R": "foot_b.R",
    "PoleTargetBack.R": "hip_b.R",
    # 尾（CC0 三节，我们五节）
    "Tail1": "tail_01", "Tail2": "tail_02", "Tail3": "tail_03",
}

# 我们的骨骼里没有对应物的（嘴/舌/眼/鼻都并到头骨上）：由 CC0 的 Head 一并承担
OUR_EXTRA_FROM_HEAD = ["mouth", "tongue_1", "tongue_2", "tongue_3", "tongue_4",
                       "nose", "eye.L", "eye.R"]

# 我们的骨骼链（用于把 CC0 的少数关节权重沿链摊开，避免"一条腿只有两个铰链"）
CHAINS = [
    ["Spine_base", "Spine_02", "Spine_01", "tail_01", "tail_02", "tail_03"],
    ["Spine_base", "Spine_04", "Spine_05", "neck", "Bip01_Head"],
    ["hip_f.L", "thigh_f.L", "leg_f.L", "shin_f.L", "Bip01_L_Foot", "claws_f.L"],
    ["hip_f.R", "thigh_f.R", "leg_f.R", "shin_f.R", "Bip01_R_Foot", "claws_f.R"],
    ["hip_b.L", "thigh_b.L", "leg_b.L", "shin_b.L", "foot_b.L", "claws_b.L"],
    ["hip_b.R", "thigh_b.R", "leg_b.R", "shin_b.R", "foot_b.R", "claws_b.R"],
]

# CC0 的 7 个材质 -> 语义（顺序与 glb 的 materials 一致）
CC0_MATS = ["skin_light", "skin", "skin_dark", "muzzle", "hooves", "eyes_black", "eyes_white"]

# 7 种毛色：key -> (英文名, 主色, 亮色, 暗色)  sRGB 0..255
COATS = {
    "Alpaca":          ("cream",      (236, 228, 213), (247, 242, 230), (198, 186, 165)),
    "Alpaca_Fawn":     ("light fawn", (203, 166, 118), (219, 187, 143), (168, 133, 89)),
    "Alpaca_Brown":    ("brown",      (139, 96, 61),   (160, 116, 78),   (105, 70, 43)),
    "Alpaca_Black":    ("black",      (58, 53, 50),    (74, 68, 64),     (38, 34, 32)),
    "Alpaca_Grey":     ("grey",       (166, 163, 158), (184, 181, 176),  (128, 125, 121)),
    "Alpaca_RoseGrey": ("rose grey",  (178, 156, 150), (196, 176, 170),  (139, 118, 113)),
    "Alpaca_Suri":     ("suri white", (242, 237, 226), (250, 246, 238),  (206, 199, 186)),
}


def log(msg):
    print(f"[build_cc0] {msg}", flush=True)


# ----------------------------------------------------------------- CC0 侧


class Cc0:
    """合并后的 CC0 羊驼：单 primitive 网格 + 46 骨骼骨架 + 本体动画求值。"""

    def __init__(self, path):
        self.G = Glb(path)
        g = self.G.g
        self.g = g
        self._merge_mesh()
        sk = g["skins"][0]
        self.joints = sk["joints"]
        self.joint_names = [g["nodes"][i].get("name") for i in self.joints]
        ibm = self.G.acc(sk["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4)
        self.ibm = np.transpose(ibm, (0, 2, 1))            # 行主序
        self.parent = {}
        for i, n in enumerate(g["nodes"]):
            for c in n.get("children", []):
                self.parent[c] = i
        self.anims = {a.get("name"): a for a in g.get("animations", [])}

    def _merge_mesh(self):
        prims = self.g["meshes"][0]["primitives"]
        pos, nrm, jnt, wgt, idx, tmat = [], [], [], [], [], []
        base = 0
        for pi, p in enumerate(prims):
            a = p["attributes"]
            v = self.G.acc(a["POSITION"]).astype(np.float32)
            pos.append(v)
            nrm.append(self.G.acc(a["NORMAL"]).astype(np.float32))
            jnt.append(self.G.acc(a["JOINTS_0"]))
            wgt.append(self.G.acc(a["WEIGHTS_0"]).astype(np.float32))
            ii = self.G.acc_flat(p["indices"]).astype(np.int64) + base
            idx.append(ii)
            tmat.append(np.full(len(ii) // 3, pi, dtype=np.int64))
            base += len(v)
        self.pos = np.concatenate(pos)
        self.nrm = np.concatenate(nrm)
        self.jnt = np.concatenate(jnt)
        self.wgt = np.concatenate(wgt)
        self.idx = np.concatenate(idx)
        self.tri_mat = np.concatenate(tmat)
        # 归一化权重（原模型已经是 1.0，这里只是保险）
        s = self.wgt.sum(axis=1, keepdims=True)
        self.wgt = self.wgt / np.clip(s, 1e-9, None)

    # ---- 动画求值：只需要"某一帧的关节世界矩阵" ----

    def _sample_channel(self, sampler, t):
        times = self.G.acc(sampler["input"]).astype(float).reshape(-1)
        vals = self.G.acc(sampler["output"]).astype(float)
        interp = sampler.get("interpolation", "LINEAR")
        if t <= times[0]:
            return vals[0]
        if t >= times[-1]:
            return vals[-1]
        i = int(np.searchsorted(times, t) - 1)
        i = max(0, min(i, len(times) - 2))
        span = max(times[i + 1] - times[i], 1e-9)
        u = (t - times[i]) / span
        a, b = vals[i], vals[i + 1]
        if interp == "STEP":
            return a
        if len(a) == 4:                                    # 四元数 slerp
            qa, qb = a / np.linalg.norm(a), b / np.linalg.norm(b)
            d = float(np.dot(qa, qb))
            if d < 0:
                qb, d = -qb, -d
            if d > 0.9995:
                q = qa + u * (qb - qa)
                return q / np.linalg.norm(q)
            th = math.acos(max(-1.0, min(1.0, d)))
            return (math.sin((1 - u) * th) * qa + math.sin(u * th) * qb) / math.sin(th)
        return a + u * (b - a)

    def animated_local(self, anim_name, t):
        """返回 {node_index: (t, r, s)}，只含被该剪辑驱动的节点。"""
        anim = self.anims[anim_name]
        out = {}
        for ch in anim["channels"]:
            node = ch["target"]["node"]
            path = ch["target"]["path"]
            v = self._sample_channel(anim["samplers"][ch["sampler"]], t)
            out.setdefault(node, {})[path] = v
        return out

    def world_at(self, anim_name, t):
        """按剪辑求值出所有节点的世界矩阵（未驱动的节点用自身 TRS）。"""
        driven = self.animated_local(anim_name, t)
        W = {}

        def rec(i, parent_m):
            n = self.g["nodes"][i]
            tr = driven.get(i, {})
            t_ = tr.get("translation", n.get("translation", [0, 0, 0]))
            r_ = tr.get("rotation", n.get("rotation", [0, 0, 0, 1]))
            s_ = tr.get("scale", n.get("scale", [1, 1, 1]))
            m = np.eye(4)
            m[:3, :3] = quat_to_mat(r_) * np.array(s_)
            m[:3, 3] = t_
            W[i] = parent_m @ m
            for c in n.get("children", []):
                rec(c, W[i])

        for root in self.g["scenes"][0]["nodes"]:
            rec(root, np.eye(4))
        return W

    def mesh_node_world(self, anim_name, t):
        """蒙皮网格所在节点的世界矩阵（FBX 转换在它上面留了 -90°X 与 scale 100）。

        glTF 规定蒙皮网格的节点变换应被忽略，但 FBX2glTF 的产物依赖它把 Z-up 转成 Y-up，
        所以我们把它当可选项（--mesh-node-transform）参与传递，靠渲染结果决定用不用。
        """
        W = self.world_at(anim_name, t)
        for i, n in enumerate(self.g["nodes"]):
            if "mesh" in n:
                return W[i]
        return np.eye(4)


# ----------------------------------------------------------------- 骨架对应


def _normalize(pts):
    """把一组点归一化到单位立方体（用于跨骨架的位置最近邻：两套模型的尺度差 10 倍）。"""
    pts = np.asarray(pts, dtype=float)
    c = (pts.max(axis=0) + pts.min(axis=0)) * 0.5
    s = float((pts.max(axis=0) - pts.min(axis=0)).max())
    return (pts - c) / max(s, 1e-9)


def build_correspondence(our_joint_names, our_bind, their_joint_names, their_bind):
    """CC0 关节下标 -> 我们的关节下标。

    优先用 CC0_TO_OUR；表里没有的（IK/pole 之类的辅助骨）按**归一化位置最近邻**兜底。
    每个带蒙皮权重的 CC0 关节都必须有归属，否则它的顶点会掉到默认骨头上（表现为局部塌陷）。
    """
    our_pos = _normalize([m[:3, 3] for m in our_bind])
    their_pos = _normalize([m[:3, 3] for m in their_bind])
    our_idx = {nm: j for j, nm in enumerate(our_joint_names)}
    fallback = our_idx.get("Spine_base", 0)
    out, via_table, via_nearest = [], 0, 0
    for j, tn in enumerate(their_joint_names):
        nm = CC0_TO_OUR.get(tn)
        if nm is None and tn in OUR_EXTRA_FROM_HEAD:
            nm = "Bip01_Head"
        if nm is not None and nm in our_idx:
            out.append(our_idx[nm])
            via_table += 1
            continue
        d = np.sum((our_pos - their_pos[j]) ** 2, axis=1)
        k = int(np.argmin(d))
        out.append(k if d[k] < 0.25 else fallback)
        via_nearest += 1
        if d[k] >= 0.25:
            log(f"WARN cc0 joint '{tn}' has no close base bone (d={math.sqrt(float(d[k])):.2f}); "
                f"fell back to '{our_joint_names[fallback]}'")
    return out, via_table, via_nearest


def similarity_fit(src, dst):
    """Umeyama：求 (scale, R, t) 使 s·R·src + t ≈ dst（不允许镜像）。

    为什么必须有这一步：CC0 是 FBX 转出来的，它的**动画世界坐标比绑定姿态大约 100 倍**
    （cm/m 差），根节点还带 -90°X。所以光把网格搬进我们的绑定空间不够，
    必须先算一个"把它的骨架摆到我们骨架位置上"的全局相似变换。
    """
    src = np.asarray(src, dtype=float)
    dst = np.asarray(dst, dtype=float)
    mu_s, mu_d = src.mean(axis=0), dst.mean(axis=0)
    s0, d0 = src - mu_s, dst - mu_d
    cov = d0.T @ s0 / len(src)
    U, S, Vt = np.linalg.svd(cov)
    Dm = np.eye(3)
    if np.linalg.det(U) * np.linalg.det(Vt) < 0:
        Dm[2, 2] = -1
    R = U @ Dm @ Vt
    var_s = float((s0 ** 2).sum()) / len(src)
    scale = float((S * np.diag(Dm)).sum() / max(var_s, 1e-12))
    M = np.eye(4)
    M[:3, :3] = scale * R
    M[:3, 3] = mu_d - scale * (R @ mu_s)
    return M, scale


# ----------------------------------------------------------------- 权重平滑


def edge_list(idx, nvert):
    tri = idx.reshape(-1, 3)
    e = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    return np.unique(e, axis=0)


def smooth_weights(joints, weights, edges, njoints, iters=3, alpha=0.5):
    """按网格邻接把权重摊开：CC0 用少量关节驱动大片网格，摊开后腿/脖子能沿链多关节弯曲。"""
    W = np.zeros((len(joints), njoints), dtype=np.float32)
    rows = np.repeat(np.arange(len(joints)), joints.shape[1])
    np.add.at(W, (rows, joints.reshape(-1)), weights.reshape(-1))
    nbr_sum = np.zeros_like(W)
    nbr_cnt = np.zeros(len(joints), dtype=np.float32)
    for _ in range(iters):
        nbr_sum[:] = 0
        nbr_cnt[:] = 0
        np.add.at(nbr_sum, edges[:, 0], W[edges[:, 1]])
        np.add.at(nbr_sum, edges[:, 1], W[edges[:, 0]])
        np.add.at(nbr_cnt, edges[:, 0], 1.0)
        np.add.at(nbr_cnt, edges[:, 1], 1.0)
        avg = nbr_sum / np.clip(nbr_cnt, 1, None)[:, None]
        W = (1 - alpha) * W + alpha * avg
    return W


def top4(W):
    out_j = np.zeros((len(W), 4), dtype=np.uint16)
    out_w = np.zeros((len(W), 4), dtype=np.float32)
    for i in range(len(W)):
        row = W[i]
        k = np.argpartition(-row, min(3, len(row) - 1))[:4]
        k = k[np.argsort(-row[k])]
        s = float(row[k].sum())
        out_j[i] = k
        out_w[i] = row[k] / (s if s > 1e-9 else 1.0)
    return out_j, out_w


# ----------------------------------------------------------------- 图集


def crimp(size, seed=7, style="huacaya"):
    rng = np.random.RandomState(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    if style == "suri":
        base = np.sin(2 * np.pi * (xx / 11.0 + 0.35 * np.sin(yy / 90.0)))
        fine = np.sin(2 * np.pi * (xx / 4.3 + 0.20 * np.sin(yy / 37.0)))
        f = 1.0 + 0.04 * base + 0.02 * fine
    else:
        n1 = np.sin(2 * np.pi * (xx / 27.0 + 0.8 * np.sin(yy / 61.0)))
        n2 = np.sin(2 * np.pi * (yy / 23.0 + 0.7 * np.sin(xx / 49.0)))
        f = 1.0 + 0.055 * n1 + 0.045 * n2
    noise = rng.rand(size, size).astype(np.float32)
    from PIL import Image, ImageFilter
    noise = np.asarray(Image.fromarray((noise * 255).astype(np.uint8))
                      .filter(ImageFilter.GaussianBlur(2.6)), dtype=np.float32) / 255.0
    return np.clip(f * (0.94 + 0.12 * noise), 0.82, 1.18)


def paint_atlas(tri_mat, size=ATLAS, grid=GRID, cell=CELL, inset=INSET,
                coat=(236, 228, 213), style="huacaya"):
    """按"每三角形一格"生成图集（向量化）。

    做法：先建一张"每格材质索引"的小图（grid x grid），按材质 LUT 上色，
    再用最近邻放大到整张图集，最后对毛发材质乘上绒毛场。
    这比逐像素填三角形快几个数量级，视觉上等价（格子很小、颜色本就分块）。
    """
    ntri = len(tri_mat)
    matimg = np.zeros((grid, grid), dtype=np.int32) - 1
    for i, m in enumerate(tri_mat):
        matimg[i // grid, i % grid] = int(m)
    lut = np.array([
        coat[1],            # skin_light
        coat[0],            # skin
        coat[2],            # skin_dark
        (74, 62, 58),       # muzzle
        (62, 54, 46),       # hooves
        (18, 16, 15),       # eyes_black
        (206, 202, 198),    # eyes_white
    ], dtype=np.float32)
    idx = np.clip(matimg, 0, len(lut) - 1)
    # 每格留 inset 边距，避免相邻格线性过滤串色
    gh = gw = grid * cell
    full = lut[idx]
    full = np.repeat(np.repeat(full, cell, axis=0), cell, axis=1)
    gh = gw = min(gh, size)
    img = np.zeros((size, size, 3), dtype=np.float32)
    img[:gh, :gw] = full[:gh, :gw]
    fld = crimp(size, style=style)
    skin = np.isin(matimg, [0, 1, 2])
    skin_full = np.zeros((size, size), dtype=bool)
    sf = np.repeat(np.repeat(skin, cell, axis=0), cell, axis=1)
    skin_full[:gh, :gw] = sf[:gh, :gw]
    img[skin_full] *= fld[skin_full][:, None]
    # 格与格之间留一圈暗边（UV 三角形内缩，正常不会被采样到）
    return np.clip(img, 0, 255).astype(np.uint8)


def pack_uvs(ntri, size=ATLAS, grid=GRID, cell=CELL, inset=INSET):
    """每个三角形一个格子，返回 (每三角形 3 个像素坐标, 每三角形 3 个归一化 UV)。"""
    tri_uv, tri_uvn = [], []
    for i in range(ntri):
        cxi, cyi = i % grid, i // grid
        x0, y0 = cxi * cell + inset, cyi * cell + inset
        w = cell - 2 * inset
        # 上三角：左下 / 右下 / 上中
        px = [(x0, y0 + w), (x0 + w, y0 + w), (x0 + w / 2.0, y0)]
        tri_uv.append(px)
        tri_uvn.append([(p[0] / size, p[1] / size) for p in px])
    return tri_uv, tri_uvn


# ----------------------------------------------------------------- 主流程


def main():
    ap = argparse.ArgumentParser(description="build the alpaca body from the CC0 mesh onto the base rig")
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--cc0", default=DEFAULT_CC0)
    ap.add_argument("--out", default=os.path.join(MOD42, "media", "models_X", "Skinned", "Alpaca_Body.glb"))
    ap.add_argument("--texture-dir", default=os.path.join(MOD42, "media", "textures", "Body"))
    ap.add_argument("--pose-anim", default="Idle")
    ap.add_argument("--pose-time", type=float, default=0.3)
    ap.add_argument("--mesh-node-transform", action="store_true",
                    help="把 FBX 网格节点的 -90°X/scale 100 也算进传递（默认不算）")
    ap.add_argument("--no-smooth", action="store_true")
    ap.add_argument("--smooth-iters", type=int, default=0,
                    help="默认 0 = 保留 CC0 作者的权重；平滑会把相邻肢体权重互相扩散")
    ap.add_argument("--smooth-alpha", type=float, default=0.25,
                    help="权重沿网格平滑的强度；太大会把不同肢体的权重互相扩散（腿/尾会被撕开）")
    ap.add_argument("--no-recompute-normals", dest="recompute_normals", action="store_false",
                    help="保留逐骨骼混合出来的法线（默认改为按几何重算）")
    ap.add_argument("--no-drop-to-ground", dest="drop_to_ground", action="store_false",
                    help="不要把网格下移到地面（默认下移，让脚踩在 y≈0.005）")
    ap.add_argument("--atlas-only", action="store_true", help="只重画 7 张图集")
    ap.add_argument("--no-transfer", action="store_true", help="只打印诊断")
    args = ap.parse_args()

    log(f"base : {args.base}")
    log(f"cc0  : {args.cc0}")

    base = Glb(args.base)
    D.apply_bone_lengths(base, D.BONE_LEN)
    D.apply_bone_rotations(base, D.BONE_ROT)
    our_names = base.node_names()
    our_joints = base.g["skins"][0]["joints"]
    our_joint_names = [our_names[j] for j in our_joints]          # 按 skin 关节序（JOINTS_0 的下标空间）
    our_ibm = base.acc(base.g["skins"][0]["inverseBindMatrices"]).astype(float).reshape(-1, 4, 4)
    our_ibm = np.transpose(our_ibm, (0, 2, 1))
    Wn = world_matrices(base.g)
    D_b = np.stack([Wn[our_joints[j]] @ our_ibm[j] for j in range(len(our_joints))])

    cc0 = Cc0(args.cc0)
    WcP = cc0.world_at(args.pose_anim, args.pose_time)
    S_b = np.stack([WcP[cc0.joints[j]] @ cc0.ibm[j] for j in range(len(cc0.joints))])

    their_bind = [np.linalg.inv(cc0.ibm[j]) for j in range(len(cc0.joints))]
    our_bind = [np.linalg.inv(our_ibm[j]) for j in range(len(our_joints))]
    cc0_to_our, via_table, via_nearest = build_correspondence(
        our_joint_names, our_bind, cc0.joint_names, their_bind)

    # 全局相似变换：把 CC0 在姿态 P 下的骨架摆到我们**静止姿态**的骨架上
    src_pts = np.array([WcP[cc0.joints[j]][:3, 3] for j in range(len(cc0.joints))])
    dst_pts = np.array([Wn[our_joints[cc0_to_our[j]]][:3, 3] for j in range(len(cc0.joints))])
    Gfit, gscale = similarity_fit(src_pts, dst_pts)
    resid = np.linalg.norm((gscale * (Gfit[:3, :3] / gscale) @ src_pts.T).T + Gfit[:3, 3] - dst_pts, axis=1)
    M = Gfit if not args.mesh_node_transform else Gfit @ cc0.mesh_node_world(args.pose_anim, args.pose_time)
    log(f"global fit: scale={gscale:.4f}, residual mean={resid.mean():.4f} max={resid.max():.4f} "
        f"(model units; our skeleton spans ~0.5)")
    order = np.argsort(-resid)
    for k in order[:8]:
        log(f"   worst fit: cc0 {cc0.joint_names[k]:18s} -> {our_joint_names[cc0_to_our[k]]:16s} "
            f"off by {resid[k]:.4f}")
    log(f"correspondence: {via_table} by table, {via_nearest} by nearest position, "
        f"{len(cc0_to_our)} cc0 joints total")

    # 带蒙皮权重的 CC0 关节统计（映射是全覆盖的，所以这里只做展示与自检）
    weight_use = np.zeros(len(cc0.joints))
    for s in range(cc0.wgt.shape[1]):
        np.add.at(weight_use, cc0.jnt[:, s], cc0.wgt[:, s])
    used = int((weight_use > 1e-6).sum())
    log(f"joints: ours {len(our_joints)} / cc0 {len(cc0.joints)}; "
        f"cc0 joints carrying weight: {used}; every one of them has a target")
    if args.no_transfer:
        for j, tn in enumerate(cc0.joint_names):
            tgt = our_joint_names[cc0_to_our[j]]
            mark = "  " if weight_use[j] > 1e-6 else "w "
            log(f"  {mark}{tn:18s} -> {tgt:16s} (weight {weight_use[j]:.1f})")
        return 0

    # 传递矩阵：每个 CC0 关节一个
    T = np.zeros((len(cc0.joints), 4, 4))
    for j in range(len(cc0.joints)):
        oi = cc0_to_our[j]
        if oi is None:
            T[j] = np.eye(4)
            continue
        T[j] = np.linalg.inv(D_b[oi]) @ M @ S_b[j]

    # ---------------- 目标形状（CC0 羊驼在姿态 P 下，按全局相似变换摆好） ----------------
    hom = np.concatenate([cc0.pos, np.ones((len(cc0.pos), 1))], axis=1)
    tgt = np.zeros((len(cc0.pos), 3))
    for s in range(cc0.wgt.shape[1]):
        tgt += cc0.wgt[:, s][:, None] * np.einsum("vij,vj->vi", M @ S_b[cc0.jnt[:, s]], hom)[:, :3]
    # 权重：先按映射重排到我们的关节空间，再沿网格平滑
    ojnt = np.array(cc0_to_our, dtype=np.int64)[cc0.jnt]
    if args.no_smooth:
        W = np.zeros((len(cc0.jnt), len(our_joints)), dtype=np.float32)
        rows = np.repeat(np.arange(len(cc0.jnt)), cc0.wgt.shape[1])
        np.add.at(W, (rows, ojnt.reshape(-1)), cc0.wgt.reshape(-1))
    else:
        edges = edge_list(cc0.idx, len(cc0.pos))
        W = smooth_weights(ojnt, cc0.wgt, edges, len(our_joints),
                           iters=args.smooth_iters, alpha=args.smooth_alpha)
    W = W / np.clip(W.sum(axis=1, keepdims=True), 1e-9, None)
    J, Wt = top4(W)
    log(f"weights: max influences 4, mean used bones/vert {float((W > 1e-4).sum(axis=1).mean()):.1f}")

    # ---------------- 逆蒙皮烘焙：解出绑定空间坐标，使 LBS 在静止姿态精确复现目标形状 ----------------
    # 为什么必须这么做：引擎（和我们）用 Σ w·D_b 去变换绑定空间顶点，而我之前是
    # "先用 Σ w·(D_b⁻¹·G·S_b) 求位置，再让引擎用 (另一组) 权重做 Σ w·D_b" —— 两者不是互逆运算，
    # 每个顶点的误差方向都不同，网格就被撕成一地碎三角片。正确做法是先定目标形状，
    # 再解 v_bind = (Σ w·D_b)⁻¹ · p_target，于是静止时 LBS 结果 == 目标，动画时按骨骼相对运动形变。
    Mv = np.zeros((len(cc0.pos), 4, 4))
    for s in range(J.shape[1]):
        Mv += Wt[:, s][:, None, None] * D_b[J[:, s]]
    ok = 0
    vbind = np.zeros((len(cc0.pos), 3))

    # ---------------- 落地：把**目标形状**下移到 y≈0.005，然后重新烘焙 ----------------
    # 注意：偏移必须加在目标形状上再重解绑定坐标。给绑定坐标加偏移是错的 ——
    # LBS 是逐骨骼仿射，Σw·D_b·(v + c) ≠ (Σw·D_b·v) + c。
    tri = cc0.idx.reshape(-1, 3)
    ground_dy = 0.005 - float(tgt.min(axis=0)[1]) if args.drop_to_ground else 0.0
    tgt[:, 1] += ground_dy
    for i in range(len(cc0.pos)):
        m = Mv[i]
        try:
            det = float(np.linalg.det(m[:3, :3]))
            if abs(det) < 1e-12 or np.linalg.cond(m[:3, :3]) > 1e6:
                raise np.linalg.LinAlgError("ill-conditioned blend")
            vbind[i] = (np.linalg.inv(m) @ np.append(tgt[i], 1.0))[:3]
            ok += 1
        except np.linalg.LinAlgError:
            mi = np.linalg.inv(D_b[J[i, 0]])
            vbind[i] = (mi @ np.append(tgt[i], 1.0))[:3]
    log(f"ground shift {ground_dy:+.4f}; rest shape min-y = {tgt.min(axis=0)[1]:.4f}")

    # 法线：由目标形状算，再用 (Mv⁻¹)ᵀ 预补偿，使引擎按 Mv 变换后正好得到目标法线
    if args.recompute_normals:
        fn = np.cross(tgt[tri[:, 1]] - tgt[tri[:, 0]], tgt[tri[:, 2]] - tgt[tri[:, 0]])
        acc = np.zeros_like(tgt)
        for k in range(3):
            np.add.at(acc, tri[:, k], fn)
        ln = np.linalg.norm(acc, axis=1, keepdims=True)
        ln[ln < 1e-12] = 1.0
        n_tgt = acc / ln
        vnrm = np.zeros_like(n_tgt)
        for i in range(len(n_tgt)):
            try:
                n3 = np.transpose(np.linalg.inv(Mv[i, :3, :3]))
            except np.linalg.LinAlgError:
                n3 = np.eye(3)
            vnrm[i] = n3 @ n_tgt[i]
        ln = np.linalg.norm(vnrm, axis=1, keepdims=True)
        ln[ln < 1e-12] = 1.0
        vnrm = vnrm / ln
        log("normals: from the target shape, pre-compensated by (Mv^-1)^T for the runtime LBS")
    else:
        # 保留 CC0 自身法线：同样做预补偿，否则运行时会被 Mv 拉歪
        vnrm = np.zeros_like(cc0.nrm)
        for i in range(len(cc0.nrm)):
            try:
                n3 = np.transpose(np.linalg.inv(Mv[i, :3, :3]))
            except np.linalg.LinAlgError:
                n3 = np.eye(3)
            vnrm[i] = n3 @ cc0.nrm[i]
        ln = np.linalg.norm(vnrm, axis=1, keepdims=True)
        ln[ln < 1e-12] = 1.0
        vnrm = vnrm / ln

    # sanity：全部按**静止渲染结果**（= tgt）来量，绑定坐标 vbind 是预畸变的，量它没意义
    a = np.linalg.norm(np.cross(tgt[tri[:, 1]] - tgt[tri[:, 0]],
                                tgt[tri[:, 2]] - tgt[tri[:, 0]]), axis=1) * 0.5
    center = tgt.mean(axis=0)
    outward = np.einsum("ij,ij->i", n_tgt, tgt - center)
    log(f"rest-shape sanity: degenerate tris={int((a < 1e-9).sum())}, median area={np.median(a):.3e}, "
        f"verts with inward normal={int((outward < 0).sum())}/{len(tgt)}")
    log(f"rest shape bbox: min={np.round(tgt.min(0), 4).tolist()} max={np.round(tgt.max(0), 4).tolist()}")
    log(f"bind shape bbox: min={np.round(vbind.min(0), 4).tolist()} max={np.round(vbind.max(0), 4).tolist()} "
        f"(pre-distorted on purpose)")
    vpos = vbind

    # ---------------- 写回 base 的 glb：替换网格 ----------------
    # 每三角形拆独立顶点（每格独立 UV）
    ntri = len(cc0.idx) // 3
    tri_uv, tri_uvn = pack_uvs(ntri)
    src = cc0.idx.reshape(-1, 3)
    new_pos = np.zeros((ntri * 3, 3), dtype=np.float32)
    new_nrm = np.zeros((ntri * 3, 3), dtype=np.float32)
    new_uv = np.zeros((ntri * 3, 2), dtype=np.float32)
    new_j = np.zeros((ntri * 3, 4), dtype=np.uint16)
    new_w = np.zeros((ntri * 3, 4), dtype=np.float32)
    for i in range(ntri):
        for k in range(3):
            vi = src[i, k]
            o = i * 3 + k
            new_pos[o] = vpos[vi]
            new_nrm[o] = vnrm[vi]
            new_uv[o] = tri_uvn[i][k]
            new_j[o] = J[vi]
            new_w[o] = Wt[vi]

    G = base
    prim = G.g["meshes"][0]["primitives"][0]
    # clone_accessor_values 要求形状一致，这里顶点数变了，直接手工追加新 accessor

    def add_acc(arr, ctype, atype, with_minmax=False):
        bv = G.append_binary(arr.tobytes())
        acc = {"bufferView": bv, "componentType": ctype, "count": len(arr), "type": atype}
        if with_minmax:
            a = np.asarray(arr, dtype=float).reshape(len(arr), -1)
            acc["min"] = a.min(0).tolist()
            acc["max"] = a.max(0).tolist()
        G.g["accessors"].append(acc)
        return len(G.g["accessors"]) - 1

    new_attrs = {
        "POSITION": add_acc(new_pos, 5126, "VEC3", True),
        "NORMAL": add_acc(new_nrm, 5126, "VEC3"),
        "TEXCOORD_0": add_acc(new_uv, 5126, "VEC2"),
        "JOINTS_0": add_acc(new_j.astype(np.uint16), 5123, "VEC4"),
        "WEIGHTS_0": add_acc(new_w, 5126, "VEC4"),
    }
    new_idx = np.arange(ntri * 3, dtype=np.uint32)
    new_idx_acc = add_acc(new_idx, 5125, "SCALAR")
    prim["attributes"] = new_attrs
    prim["indices"] = new_idx_acc
    prim["material"] = 0
    prim["mode"] = 4
    log(f"mesh replaced: {len(new_pos)} verts / {ntri} tris (per-triangle UV islands)")

    D.rename_embedded_image(G, "Alpaca")
    total = G.save(args.out)
    log(f"wrote {args.out} ({total} bytes)")

    # ---------------- 画 7 张毛色图集 ----------------
    os.makedirs(args.texture_dir, exist_ok=True)
    from PIL import Image
    for key, (en, base_c, light, dark) in COATS.items():
        style = "suri" if key.endswith("Suri") else "huacaya"
        arr = paint_atlas(cc0.tri_mat, coat=(base_c, light, dark), style=style)
        p = os.path.join(args.texture_dir, key + ".png")
        Image.fromarray(arr, "RGB").save(p, format="PNG", optimize=True)
        log(f"atlas {key:16s} {en:11s} -> {os.path.getsize(p)} bytes")
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
