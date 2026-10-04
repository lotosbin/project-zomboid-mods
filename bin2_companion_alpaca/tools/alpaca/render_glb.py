#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""render_glb.py —— 纯离线 glTF 2.0 (.glb) 软渲染器（Python + numpy + Pillow，无其它依赖）。

用途：在没有 Project Zomboid 游戏的情况下，目视检查带蒙皮（skinned）的动物模型，
例如 CompanionDogs / CompanionCat 的 * _Body.glb。

实现范围
    * GLB 容器解析（JSON chunk + BIN chunk）
    * node 层级世界矩阵（scene 根节点递归，局部 TRS = T * R * S）
    * 骨骼蒙皮：skin.joints + inverseBindMatrices，最多 4 个影响，权重归一化
    * 动画求值：LINEAR / STEP，translation / rotation(slerp) / scale
    * 透视相机自动取景 + z-buffer 隐藏面消除
    * 逐像素 Blinn 风格光照（主光 + 半球环境光 + rim）+ 贴图双线性采样
    * 超采样抗锯齿

用法
    python3 render_glb.py <model.glb> <out.png> [options]

选项见 --help。典型：
    python3 render_glb.py Retriever_Body.glb out/dog_rest.png --size 900x700 --views

注意（重要）：本仓库用到的这批 PZ 模型，GLB 内嵌的 image 是 71 字节的 1x1 占位 PNG，
真正可用的贴图放在 mod 的 media/textures/Body/*.png。因此本脚本在"内嵌贴图不可用"时
会自动在 .glb 附近向上搜索 media/textures/Body 并按名字匹配外置贴图（可用 --texture 覆盖，
--no-texture 关闭贴图）。匹配到的来源会打印出来。
"""

from __future__ import annotations

import argparse
import io
import json
import math
import os
import struct
import sys
import time as _time
from typing import Optional

import numpy as np
from PIL import Image

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

COMPONENT_DTYPE = {
    5120: np.int8,
    5121: np.uint8,
    5122: np.int16,
    5123: np.uint16,
    5125: np.uint32,
    5126: np.float32,
}
TYPE_COMPONENTS = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
    "MAT2": 4,
    "MAT3": 9,
    "MAT4": 16,
}

IDENTITY4 = np.eye(4, dtype=np.float64)


class ModelError(Exception):
    """用户可见的模型/参数错误（避免打印 traceback）。"""


# ---------------------------------------------------------------------------
# 小工具
# ---------------------------------------------------------------------------


def _normalize(v: np.ndarray, axis: int = -1, eps: float = 1e-12) -> np.ndarray:
    n = np.linalg.norm(v, axis=axis, keepdims=True)
    return v / np.maximum(n, eps)


def quat_to_matrix(q: np.ndarray) -> np.ndarray:
    """四元数 (x, y, z, w) -> 3x3 旋转矩阵（输入会自动归一化）。"""
    q = np.asarray(q, dtype=np.float64)
    n = np.linalg.norm(q)
    if n < 1e-12:
        return np.eye(3, dtype=np.float64)
    x, y, z, w = q / n
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    return np.array(
        [
            [1.0 - 2.0 * (yy + zz), 2.0 * (xy - wz), 2.0 * (xz + wy)],
            [2.0 * (xy + wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz - wx)],
            [2.0 * (xz - wy), 2.0 * (yz + wx), 1.0 - 2.0 * (xx + yy)],
        ],
        dtype=np.float64,
    )


def quat_slerp(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    """最短弧球面线性插值，返回归一化四元数。"""
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na < 1e-12 or nb < 1e-12:
        out = a if na >= nb else b
        n = np.linalg.norm(out)
        return out / n if n > 1e-12 else np.array([0.0, 0.0, 0.0, 1.0])
    a = a / na
    b = b / nb
    d = float(np.dot(a, b))
    if d < 0.0:  # 最短弧
        b = -b
        d = -d
    if d > 0.9995:  # 近平行，退化为线性插值再归一化
        out = a + (b - a) * t
        n = np.linalg.norm(out)
        return out / n if n > 1e-12 else a
    theta0 = math.acos(max(-1.0, min(1.0, d)))
    theta = theta0 * t
    sin0 = math.sin(theta0)
    s0 = math.sin(theta0 - theta) / sin0
    s1 = math.sin(theta) / sin0
    return a * s0 + b * s1


def trs_matrix(translation, rotation, scale) -> np.ndarray:
    """glTF 局部变换 M = T * R * S。"""
    m = np.eye(4, dtype=np.float64)
    if rotation is not None:
        m[:3, :3] = quat_to_matrix(rotation)
    if scale is not None:
        m[:3, :3] = m[:3, :3] @ np.diag(np.asarray(scale, dtype=np.float64))
    if translation is not None:
        m[:3, 3] = np.asarray(translation, dtype=np.float64)
    return m


def srgb_to_linear(x: np.ndarray) -> np.ndarray:
    return np.power(np.clip(x, 0.0, 1.0), 2.2)


def linear_to_srgb(x: np.ndarray) -> np.ndarray:
    return np.power(np.clip(x, 0.0, 1.0), 1.0 / 2.2)


def parse_color(text: str):
    """'transparent' 或 '#RRGGBB' -> (rgb float32 0..1, alpha_flag)。"""
    if text is None:
        text = "#202830"
    s = text.strip().lower()
    if s in ("transparent", "none", "alpha"):
        return np.zeros(3, dtype=np.float64), True
    if s.startswith("#"):
        s = s[1:]
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    if len(s) != 6:
        raise ModelError("无效的 --bg 颜色：%r（应为 transparent 或 #RRGGBB）" % text)
    try:
        v = np.array([int(s[i : i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float64)
    except ValueError:
        raise ModelError("无效的 --bg 颜色：%r（应为 transparent 或 #RRGGBB）" % text)
    return v, False


def parse_size(text: str):
    try:
        w, h = text.lower().split("x")
        w, h = int(w), int(h)
    except Exception:
        raise ModelError("无效的 --size：%r（应为 WxH，例如 900x700）" % text)
    if w <= 0 or h <= 0 or w > 8000 or h > 8000:
        raise ModelError("--size 超出范围：%s" % text)
    return w, h


# ---------------------------------------------------------------------------
# GLB 解析
# ---------------------------------------------------------------------------


class Glb:
    """GLB 容器 + glTF JSON + accessor 读取。"""

    def __init__(self, path: str):
        if not os.path.isfile(path):
            raise ModelError("模型文件不存在：%s" % path)
        self.path = os.path.abspath(path)
        with open(self.path, "rb") as fh:
            data = fh.read()
        if len(data) < 12:
            raise ModelError("文件太小，不是合法 GLB：%s" % path)
        magic, version, length = struct.unpack_from("<III", data, 0)
        if magic != GLB_MAGIC:
            raise ModelError(
                "不是 GLB 文件（magic=0x%08X）。本脚本只支持 .glb 二进制容器，不解析 .gltf+.bin。"
                % magic
            )
        if version != 2:
            raise ModelError("不支持的 glTF 版本：%d（仅支持 2）" % version)
        end = min(length, len(data)) if length else len(data)
        self.json = None
        self.bin = b""
        off = 12
        while off + 8 <= end:
            clen, ctype = struct.unpack_from("<II", data, off)
            body = off + 8
            if clen < 0 or body + clen > len(data):
                raise ModelError("GLB chunk 长度越界（文件中可能被截断）：%s" % path)
            if ctype == CHUNK_JSON:
                self.json = json.loads(data[body : body + clen].decode("utf-8"))
            elif ctype == CHUNK_BIN:
                self.bin = data[body : body + clen]
            off = body + clen
        if self.json is None:
            raise ModelError("GLB 中找不到 JSON chunk：%s" % path)
        self.g = self.json
        self._acc_cache = {}

    # -- accessor -----------------------------------------------------------

    def accessor(self, index: int) -> np.ndarray:
        """读取 accessor，返回 shape=(count, ncomp) 的 numpy 数组（MAT4 保持 16 列）。"""
        if index in self._acc_cache:
            return self._acc_cache[index]
        g = self.g
        if index is None or index < 0 or index >= len(g.get("accessors", [])):
            raise ModelError("accessor 序号越界：%r" % (index,))
        acc = g["accessors"][index]
        if "sparse" in acc:
            raise ModelError("暂不支持 sparse accessor（accessor %d）" % index)
        ctype = acc["componentType"]
        if ctype not in COMPONENT_DTYPE:
            raise ModelError("未知 componentType：%d" % ctype)
        dtype = COMPONENT_DTYPE[ctype]
        ncomp = TYPE_COMPONENTS.get(acc["type"])
        if ncomp is None:
            raise ModelError("未知 accessor type：%s" % acc["type"])
        count = int(acc["count"])

        bv_idx = acc.get("bufferView")
        if bv_idx is None:
            # 无 bufferView：全 0（glTF 允许，语义为 0 填充）
            out = np.zeros((count, ncomp), dtype=np.float64)
            self._acc_cache[index] = out
            return out

        # bufferView -> 字节
        if "bufferView" not in acc:
            raise ModelError("accessor 缺少 bufferView")
        bvs = g.get("bufferViews", [])
        if bv_idx >= len(bvs):
            raise ModelError("bufferView 序号越界：%d" % bv_idx)
        bv = bvs[bv_idx]
        base = int(bv.get("byteOffset", 0)) + int(acc.get("byteOffset", 0))
        elem_size = np.dtype(dtype).itemsize * ncomp
        stride = int(bv.get("byteStride", 0)) or elem_size

        # 内嵌 BIN（本仓库模型）或者外部 buffer（这里只支持 GLB 的 buffer 0）
        if self.bin:
            buf = self.bin
        else:
            buf = b""
        if not buf:
            raise ModelError(
                "GLB 缺少 BIN chunk，无法读取几何数据（外部 .bin 引用不支持）：%s" % self.path
            )

        if stride == elem_size:
            need = count * elem_size
            if base + need > len(buf):
                raise ModelError("accessor %d 数据越界（需要 %d 字节，BIN 仅 %d）" % (index, base + need, len(buf)))
            arr = np.frombuffer(buf, dtype=dtype, count=count * ncomp, offset=base)
            out = arr.reshape(count, ncomp).astype(np.float64)
        else:
            # 交错缓冲：逐元素抽取
            out = np.empty((count, ncomp), dtype=np.float64)
            dt = np.dtype(dtype)
            for i in range(count):
                o = base + i * stride
                out[i] = np.frombuffer(buf, dtype=dt, count=ncomp, offset=o)
        self._acc_cache[index] = out
        return out

    def mat4_accessor(self, index: int) -> np.ndarray:
        """读取 MAT4 accessor，返回 (count, 4, 4) 行主序矩阵（已处理列主序存储）。"""
        raw = self.accessor(index)  # (n, 16)，按 glTF 列主序排布
        if raw.shape[1] != 16:
            raise ModelError("accessor %d 不是 MAT4" % index)
        # glTF 列主序：flat[col*4 + row] = M[row][col]，raw 的列就是 glTF 的列
        return np.ascontiguousarray(raw.reshape(-1, 4, 4).transpose(0, 2, 1))

    # -- 结构 ---------------------------------------------------------------

    @property
    def nodes(self):
        return self.g.get("nodes", [])

    def scene_roots(self):
        scenes = self.g.get("scenes", [])
        scene_idx = self.g.get("scene", 0)
        if scenes:
            if scene_idx is None or scene_idx >= len(scenes):
                scene_idx = 0
            return list(scenes[scene_idx].get("nodes", []))
        # 没有 scenes：把所有没有父节点的 node 当根
        has_parent = set()
        for n in self.nodes:
            for c in n.get("children", []) or []:
                has_parent.add(c)
        return [i for i in range(len(self.nodes)) if i not in has_parent]

    def node_name(self, i: int) -> str:
        n = self.nodes[i]
        return n.get("name") or ("node_%d" % i)

    def node_by_name(self, name: str) -> Optional[int]:
        for i, n in enumerate(self.nodes):
            if n.get("name") == name:
                return i
        return None

    def mesh_primitives(self):
        """返回 [(mesh_idx, prim_idx, prim_dict)]，只保留 mode==4(TRIANGLES) 或未指定。"""
        out = []
        for mi, mesh in enumerate(self.g.get("meshes", [])):
            for pi, prim in enumerate(mesh.get("primitives", [])):
                mode = prim.get("mode", 4)
                if mode != 4:
                    continue
                out.append((mi, pi, prim))
        return out

    def embedded_image_bytes(self, image_index: int) -> Optional[bytes]:
        images = self.g.get("images", [])
        if image_index >= len(images):
            return None
        img = images[image_index]
        bv_idx = img.get("bufferView")
        if bv_idx is None:
            return None
        bvs = self.g.get("bufferViews", [])
        if bv_idx >= len(bvs):
            return None
        bv = bvs[bv_idx]
        o = int(bv.get("byteOffset", 0))
        n = int(bv.get("byteLength", 0))
        if o + n > len(self.bin):
            return None
        return self.bin[o : o + n]


# ---------------------------------------------------------------------------
# 贴图解析
# ---------------------------------------------------------------------------

TEXTURE_NAME_SUFFIXES = (
    "_diffuse", "_basecolor", "_albedo", "_normal", "_metallic_roughness",
    "_specular", "_roughness", "_metallic", "_orm", "_spec",
)


def _score_texture_name(query_tokens, stem: str) -> int:
    low = "".join(ch for ch in stem.lower() if ch.isalnum())
    return sum(1 for t in query_tokens if t and t in low)


def resolve_texture(
    glb: Glb,
    image_index: Optional[int],
    query_names,
    explicit_path: Optional[str] = None,
    verbose: bool = True,
):
    """返回 (PIL.Image RGB 或 None, 说明字符串)。

    优先级：--texture 显式指定 > GLB 内嵌贴图（若可用，>=8x8）> 外置 media/textures/Body 匹配。
    """
    if explicit_path:
        if not os.path.isfile(explicit_path):
            raise ModelError("--texture 指定的文件不存在：%s" % explicit_path)
        try:
            img = Image.open(explicit_path)
            img.load()
            return img.convert("RGB"), "external(--texture): %s" % explicit_path
        except Exception as exc:
            raise ModelError("--texture 无法解码：%s（%s）" % (explicit_path, exc))

    # 1) 内嵌贴图
    note_bad_embedded = None
    if image_index is not None:
        raw = glb.embedded_image_bytes(image_index)
        if raw:
            try:
                img = Image.open(io.BytesIO(raw))
                img.load()
                if min(img.size) >= 8:
                    return img.convert("RGB"), "embedded(images[%d], %dx%d)" % (
                        image_index,
                        img.size[0],
                        img.size[1],
                    )
                note_bad_embedded = "embedded images[%d] 仅为 %dx%d 占位图" % (
                    image_index,
                    img.size[0],
                    img.size[1],
                )
            except Exception as exc:
                note_bad_embedded = "embedded images[%d] 无法解码（%s）" % (image_index, exc)

    # 2) 外置贴图搜索
    found = _search_external_texture(glb.path, query_names)
    if found:
        try:
            img = Image.open(found)
            img.load()
            prefix = (note_bad_embedded + "；") if note_bad_embedded else ""
            return img.convert("RGB"), "%s外部匹配: %s" % (prefix, found)
        except Exception:
            pass

    if verbose and note_bad_embedded:
        print("  [tex] %s，且未找到外置贴图 —— 回退到材质基色/灰色" % note_bad_embedded)
    return None, note_bad_embedded or "无贴图引用"


def _search_external_texture(glb_path: str, query_names) -> Optional[str]:
    """在 .glb 附近的 media/textures/Body（以及 textures/）里按名字找贴图。"""
    roots = []
    d = os.path.dirname(glb_path)
    for _ in range(8):
        if not d or d == os.path.dirname(d):
            break
        roots.append(d)
        d = os.path.dirname(d)
    cand_dirs = []
    for r in roots:
        for sub in (
            os.path.join("media", "textures", "Body"),
            os.path.join("textures", "Body"),
            os.path.join("media", "textures"),
            "textures",
        ):
            p = os.path.join(r, sub)
            if os.path.isdir(p):
                cand_dirs.append(p)

    names = [n for n in query_names if n]
    if not names:
        return None
    # 1) 精确 / 去后缀 精确匹配
    for name in names:
        probes = [name]
        low = name.lower()
        for suf in TEXTURE_NAME_SUFFIXES:
            if low.endswith(suf):
                probes.append(name[: -len(suf)])
        for cd in cand_dirs:
            for probe in probes:
                for ext in (".png", ".PNG", ".jpg", ".jpeg"):
                    p = os.path.join(cd, probe + ext)
                    if os.path.isfile(p):
                        return p
    # 2) 模糊打分匹配（用于 Cat：material 'Grey_Tabby_Mat' -> Cat_GreyTabby.png）
    tokens = set()
    for name in names:
        for t in name.replace("-", "_").split("_"):
            t = "".join(ch for ch in t.lower() if ch.isalnum())
            if len(t) >= 2 and t not in ("mat", "material", "diffuse", "normal", "image", "tex"):
                tokens.add(t)
    if not tokens:
        return None
    best, best_key = None, None
    for cd in cand_dirs:
        try:
            files = sorted(os.listdir(cd))
        except OSError:
            continue
        for f in files:
            if not f.lower().endswith((".png", ".jpg", ".jpeg")):
                continue
            stem = os.path.splitext(f)[0]
            s = _score_texture_name(tokens, stem)
            if s <= 0:
                continue
            key = (s, -len(stem))  # 先比命中 token 数，再取名字最短（基础贴图而非变体）
            if best_key is None or key > best_key:
                best_key, best = key, os.path.join(cd, f)
    return best


# ---------------------------------------------------------------------------
# 世界矩阵 / 动画
# ---------------------------------------------------------------------------


def compute_world_matrices(glb: Glb, overrides=None):
    """按 node 层级递归计算世界矩阵。

    overrides: {node_index: {'translation': (3,), 'rotation': (4,), 'scale': (3,)}}
               动画通道覆盖 node 自身 TRS；未覆盖的节点使用 node 自带 TRS。
    """
    nodes = glb.nodes
    world = [None] * len(nodes)
    overrides = overrides or {}

    def local_of(i):
        node = nodes[i]
        ov = overrides.get(i, {})
        t = ov.get("translation", node.get("translation"))
        r = ov.get("rotation", node.get("rotation"))
        s = ov.get("scale", node.get("scale"))
        if t is None and r is None and s is None:
            return IDENTITY4
        return trs_matrix(t, r, s)

    def walk(i, parent):
        if world[i] is not None:
            return
        m = parent @ local_of(i) if parent is not None else local_of(i)
        world[i] = m
        for c in nodes[i].get("children", []) or []:
            walk(c, m)

    for root in glb.scene_roots():
        walk(root, None)
    for i in range(len(nodes)):
        if world[i] is None:
            walk(i, None)
    return world


def animation_duration(glb: Glb, anim) -> float:
    dur = 0.0
    for smp in anim.get("samplers", []):
        acc = glb.g["accessors"][smp["input"]]
        if acc.get("max"):
            dur = max(dur, float(acc["max"][0]))
        else:
            times = glb.accessor(smp["input"])[:, 0]
            if len(times):
                dur = max(dur, float(times[-1]))
    return dur


def eval_animation(glb: Glb, anim, t: float):
    """在时间 t 求值，返回 {node_index: {path: value}}。"""
    out = {}
    for ch in anim.get("channels", []):
        tgt = ch.get("target", {})
        node = tgt.get("node")
        path = tgt.get("path")
        if node is None or path not in ("translation", "rotation", "scale"):
            continue
        smp = anim["samplers"][ch["sampler"]]
        times = glb.accessor(smp["input"])[:, 0]
        vals = glb.accessor(smp["output"])
        n = len(times)
        if n == 0:
            continue
        if n == 1 or t <= times[0]:
            v = vals[0]
        elif t >= times[-1]:
            v = vals[-1]
        else:
            i = int(np.searchsorted(times, t, side="right")) - 1
            i = max(0, min(i, n - 2))
            interp = smp.get("interpolation", "LINEAR")
            if interp == "STEP":
                v = vals[i]
            elif interp == "CUBICSPLINE":
                raise ModelError(
                    "暂不支持 CUBICSPLINE 插值（animation %r, node %d, path %s）"
                    % (anim.get("name"), node, path)
                )
            else:
                span = float(times[i + 1] - times[i])
                a = 0.0 if span <= 0 else (t - float(times[i])) / span
                if path == "rotation":
                    v = quat_slerp(vals[i], vals[i + 1], a)
                else:
                    v = vals[i] * (1.0 - a) + vals[i + 1] * a
        out.setdefault(node, {})[path] = np.asarray(v, dtype=np.float64)
    return out


# ---------------------------------------------------------------------------
# 蒙皮
# ---------------------------------------------------------------------------


class SkinnedMesh:
    """把 primitive 的 POSITION/NORMAL/TEXCOORD_0/JOINTS_0/WEIGHTS_0 + skin 打包起来。"""

    def __init__(self, glb: Glb):
        prims = glb.mesh_primitives()
        if not prims:
            raise ModelError("模型里没有 TRIANGLES primitive")
        mi, pi, prim = prims[0]
        self.glb = glb
        self.prim = prim
        self.mesh_index = mi
        self.mesh_name = (glb.g["meshes"][mi].get("name") or "mesh_%d" % mi)
        attrs = prim.get("attributes", {})
        for req in ("POSITION", "NORMAL", "JOINTS_0", "WEIGHTS_0"):
            if req not in attrs:
                raise ModelError(
                    "primitive 缺少必需属性 %s —— 本渲染器只支持带蒙皮（JOINTS_0/WEIGHTS_0）的模型" % req
                )
        self.positions = glb.accessor(attrs["POSITION"])[:, :3].astype(np.float64)
        nrm = glb.accessor(attrs["NORMAL"])[:, :3].astype(np.float64)
        self.normals = _normalize(nrm)
        if "TEXCOORD_0" in attrs:
            self.uv = glb.accessor(attrs["TEXCOORD_0"])[:, :2].astype(np.float64)
        else:
            self.uv = np.zeros((len(self.positions), 2), dtype=np.float64)
        self.joints = glb.accessor(attrs["JOINTS_0"])[:, :4].astype(np.int64)
        self.weights = glb.accessor(attrs["WEIGHTS_0"])[:, :4].astype(np.float64)

        idx = prim.get("indices")
        if idx is None:
            tri = np.arange(len(self.positions), dtype=np.int64)
        else:
            tri = glb.accessor(idx)[:, 0].astype(np.int64)
        if len(tri) % 3:
            tri = tri[: len(tri) - (len(tri) % 3)]
        self.tris = tri.reshape(-1, 3)
        self.vertex_count = len(self.positions)
        self.tri_count = len(self.tris)

        # skin：找到引用该 mesh 的节点，取其 skin
        self.skin_index = None
        for i, node in enumerate(glb.nodes):
            if node.get("mesh") == mi and node.get("skin") is not None:
                self.skin_index = node["skin"]
                self.node_index = i
                break
        if self.skin_index is None:
            raise ModelError("该 mesh 没有绑定 skin —— 本脚本用于检查带蒙皮模型，无法继续")
        skins = glb.g.get("skins", [])
        if self.skin_index >= len(skins):
            raise ModelError("skin 序号越界：%d" % self.skin_index)
        skin = skins[self.skin_index]
        self.joint_nodes = list(skin.get("joints", []))
        if not self.joint_nodes:
            raise ModelError("skin.joints 为空")
        ibm_idx = skin.get("inverseBindMatrices")
        if ibm_idx is None:
            ibm = np.tile(IDENTITY4, (len(self.joint_nodes), 1, 1))
        else:
            ibm = glb.mat4_accessor(ibm_idx)
            if len(ibm) < len(self.joint_nodes):
                pad = np.tile(IDENTITY4, (len(self.joint_nodes) - len(ibm), 1, 1))
                ibm = np.concatenate([ibm, pad], axis=0)
        self.inverse_bind = ibm

        # 材质
        self.material = None
        if prim.get("material") is not None:
            mats = glb.g.get("materials", [])
            if prim["material"] < len(mats):
                self.material = mats[prim["material"]]
        self.base_color = np.array([1.0, 1.0, 1.0], dtype=np.float64)
        self.base_color_texture_index = None
        self.double_sided = False
        if self.material:
            pbr = self.material.get("pbrMetallicRoughness", {}) or {}
            bcf = pbr.get("baseColorFactor")
            if bcf:
                self.base_color = np.array(bcf[:3], dtype=np.float64)
            bct = pbr.get("baseColorTexture")
            if bct and "index" in bct:
                texs = glb.g.get("textures", [])
                ti = bct["index"]
                if ti < len(texs):
                    self.base_color_texture_index = texs[ti].get("source")
            self.double_sided = bool(self.material.get("doubleSided", False))
        # 归一化权重（并对全 0 权重做保护）
        wsum = self.weights.sum(axis=1)
        self.zero_weight = wsum <= 1e-8
        if not np.all(self.zero_weight):
            self.weights[~self.zero_weight] /= wsum[~self.zero_weight][:, None]

    @staticmethod
    def _mesh_node_index(glb, mesh_index):
        for i, node in enumerate(glb.nodes):
            if node.get("mesh") == mesh_index:
                return i
        return None

    # -- 求姿态 --------------------------------------------------------------

    def skin_matrices(self, world):
        """skin_mats = jointWorld * inverseBind。"""
        jw = np.stack([world[j] if world[j] is not None else IDENTITY4 for j in self.joint_nodes], axis=0)
        return jw @ self.inverse_bind

    def posed(self, world):
        """返回 (world_positions, world_normals)。"""
        skin_mats = self.skin_matrices(world)  # (J,4,4)
        jsel = np.clip(self.joints, 0, len(skin_mats) - 1)
        vert_mats = np.einsum("nk,nkij->nij", self.weights, skin_mats[jsel])
        if np.any(self.zero_weight):
            vert_mats[self.zero_weight] = IDENTITY4

        # mesh 节点自身的世界矩阵（通常为 identity，但按 glTF 语义要乘上）
        mesh_node = getattr(self, "node_index", None)
        nm = world[mesh_node] if mesh_node is not None and world[mesh_node] is not None else IDENTITY4
        vert_mats = nm[None, :, :] @ vert_mats

        ph = np.concatenate([self.positions, np.ones((self.vertex_count, 1))], axis=1)
        pos = np.einsum("nij,nj->ni", vert_mats, ph)[:, :3]

        # 法线：用蒙皮矩阵的 3x3（含旋转+缩放）变换后归一化
        nrm = np.einsum("nij,nj->ni", vert_mats[:, :3, :3], self.normals)
        return pos, _normalize(nrm)

    def rest_bbox(self):
        return self.positions.min(axis=0), self.positions.max(axis=0)


# ---------------------------------------------------------------------------
# 相机
# ---------------------------------------------------------------------------


class Camera:
    def __init__(self, eye, target, up, fov_y_deg, width, height, near, far):
        self.eye = np.asarray(eye, dtype=np.float64)
        self.target = np.asarray(target, dtype=np.float64)
        self.width = width
        self.height = height
        self.near = float(near)
        self.far = float(far)
        fwd = _normalize(self.target - self.eye)
        upv = np.asarray(up, dtype=np.float64)
        if abs(float(np.dot(fwd, _normalize(upv)))) > 0.999:
            upv = np.array([0.0, 0.0, 1.0]) if abs(fwd[2]) < 0.9 else np.array([0.0, 1.0, 0.0])
        right = _normalize(np.cross(fwd, upv))
        trueup = np.cross(right, fwd)
        self.fwd, self.right, self.up = fwd, right, trueup

        view = np.eye(4)
        view[0, :3] = right
        view[1, :3] = trueup
        view[2, :3] = -fwd
        view[:3, 3] = -view[:3, :3] @ self.eye
        self.view = view

        aspect = width / float(height)
        f = 1.0 / math.tan(math.radians(fov_y_deg) * 0.5)
        proj = np.zeros((4, 4))
        proj[0, 0] = f / aspect
        proj[1, 1] = f
        proj[2, 2] = (far + near) / (near - far)
        proj[2, 3] = 2.0 * far * near / (near - far)
        proj[3, 2] = -1.0
        self.proj = proj
        self.viewproj = proj @ view
        self.fov_y_deg = fov_y_deg


def fit_camera(points, azimuth_deg, elevation_deg, width, height, zoom, fov_y_deg=30.0, fill=0.82):
    """按包围盒自动取景，保证模型大约占画面 fill（默认 82%）。"""
    lo = points.min(axis=0)
    hi = points.max(axis=0)
    center = (lo + hi) * 0.5
    az = math.radians(azimuth_deg)
    el = math.radians(elevation_deg)
    # 相机相对 center 的方向（az=0, el=0 -> +Z 方向看模型）
    dirv = np.array([math.sin(az) * math.cos(el), math.sin(el), math.cos(az) * math.cos(el)])
    dirv = _normalize(dirv)

    # 相机基（与 Camera 保持一致）
    up_hint = np.array([0.0, 1.0, 0.0])
    if abs(float(np.dot(dirv, up_hint))) > 0.999:
        up_hint = np.array([0.0, 0.0, 1.0])
    right = _normalize(np.cross(-dirv, up_hint))  # fwd = -dirv
    up = np.cross(right, -dirv)

    aspect = width / float(height)
    tan_v = math.tan(math.radians(fov_y_deg) * 0.5) * fill
    tan_h = tan_v * aspect

    corners = np.array(
        [[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])],
        dtype=np.float64,
    )
    rel = corners - center
    x_c = rel @ right
    y_c = rel @ up
    z_c = rel @ (-dirv)  # 沿视线方向的深度（正的表示在 center 后面）
    need = np.maximum(np.abs(x_c) / tan_h, np.abs(y_c) / tan_v) - z_c
    dist = float(np.max(need))
    radius = float(np.linalg.norm(hi - lo) * 0.5)
    dist = max(dist, radius * 0.05, 1e-4)
    dist = dist / max(zoom, 1e-4)

    eye = center + dirv * dist
    near = max(dist * 0.02, 1e-3)
    far = dist + radius * 4.0 + 1.0
    return Camera(eye, center, up_hint, fov_y_deg, width, height, near, far), (lo, hi)


# ---------------------------------------------------------------------------
# 光栅化 + 着色
# ---------------------------------------------------------------------------


def sample_texture(tex: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """双线性采样，越界 clamp。tex: (H,W,3) float。u/v: 1D 数组。"""
    h, w = tex.shape[0], tex.shape[1]
    x = u * w - 0.5
    y = v * h - 0.5
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    fx = (x - x0)[:, None]
    fy = (y - y0)[:, None]
    x0c = np.clip(x0, 0, w - 1)
    x1c = np.clip(x0 + 1, 0, w - 1)
    y0c = np.clip(y0, 0, h - 1)
    y1c = np.clip(y0 + 1, 0, h - 1)
    c00 = tex[y0c, x0c]
    c10 = tex[y0c, x1c]
    c01 = tex[y1c, x0c]
    c11 = tex[y1c, x1c]
    top = c00 * (1.0 - fx) + c10 * fx
    bot = c01 * (1.0 - fx) + c11 * fx
    return top * (1.0 - fy) + bot * fy


class Renderer:
    def __init__(self, width, height, bg_rgb, transparent, tex_lin=None, use_texture=True,
                 base_color=None, flip_uv=False, double_sided=True, ambient=0.42):
        self.w = width
        self.h = height
        self.bg = np.asarray(bg_rgb, dtype=np.float64)
        self.transparent = transparent
        self.tex = tex_lin
        self.use_texture = use_texture and tex_lin is not None
        self.base_color = np.ones(3) if base_color is None else np.asarray(base_color, dtype=np.float64)
        self.flip_uv = flip_uv
        self.double_sided = double_sided
        self.ambient = ambient

    def render(self, cam: Camera, pos: np.ndarray, nrm: np.ndarray, uv: np.ndarray,
               tris: np.ndarray, use_vertex_normal_shading=True):
        w, h = self.w, self.h
        vp = cam.viewproj
        n = len(pos)
        ph = np.concatenate([pos, np.ones((n, 1))], axis=1)
        clip = ph @ vp.T  # (n,4)
        cw = clip[:, 3]
        behind = cw <= 1e-9
        safe_w = np.where(behind, 1.0, cw)
        ndc = clip[:, :3] / safe_w[:, None]
        sx = (ndc[:, 0] * 0.5 + 0.5) * w
        sy = (1.0 - (ndc[:, 1] * 0.5 + 0.5)) * h
        # 深度用 ndc.z（透视投影下在屏幕空间线性）
        sz = ndc[:, 2]
        iw = 1.0 / safe_w

        color = np.empty((h, w, 3), dtype=np.float32)
        color[:] = self.bg.astype(np.float32)
        zbuf = np.full((h, w), np.inf, dtype=np.float32)

        # 光照：key 光跟随相机（相机空间 3/4 打光），另加半球环境光 + rim
        key_dir = _normalize(-cam.fwd * 0.75 + cam.right * -0.55 + cam.up * 0.62)
        key_col = np.array([1.0, 0.97, 0.90])
        sky_col = np.array([0.42, 0.50, 0.62])
        gnd_col = np.array([0.20, 0.18, 0.16])
        rim_dir = _normalize(-cam.fwd * -1.0 + cam.up * 0.25)
        rim_col = np.array([1.0, 0.95, 0.88])

        eye = cam.eye
        drawn = 0
        skipped = 0
        t0 = _time.time()
        for k in range(len(tris)):
            i0, i1, i2 = int(tris[k, 0]), int(tris[k, 1]), int(tris[k, 2])
            if behind[i0] or behind[i1] or behind[i2]:
                skipped += 1
                continue
            x0, y0, z0, w0 = sx[i0], sy[i0], sz[i0], iw[i0]
            x1, y1, z1, w1 = sx[i1], sy[i1], sz[i1], iw[i1]
            x2, y2, z2, w2 = sx[i2], sy[i2], sz[i2], iw[i2]

            minx = int(max(0, math.floor(min(x0, x1, x2))))
            maxx = int(min(w - 1, math.ceil(max(x0, x1, x2))))
            miny = int(max(0, math.floor(min(y0, y1, y2))))
            maxy = int(min(h - 1, math.ceil(max(y0, y1, y2))))
            if minx > maxx or miny > maxy:
                continue
            det = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            if abs(det) < 1e-12:
                continue

            px = np.arange(minx, maxx + 1, dtype=np.float64) + 0.5
            py = np.arange(miny, maxy + 1, dtype=np.float64) + 0.5
            PX = px[None, :]
            PY = py[:, None]

            l0 = ((y1 - y2) * (PX - x2) + (x2 - x1) * (PY - y2)) / det
            l1 = ((y2 - y0) * (PX - x2) + (x0 - x2) * (PY - y2)) / det
            l2 = 1.0 - l0 - l1
            inside = (l0 >= -1e-9) & (l1 >= -1e-9) & (l2 >= -1e-9)
            if not inside.any():
                continue

            zz = l0 * z0 + l1 * z1 + l2 * z2
            sub_z = zbuf[miny : maxy + 1, minx : maxx + 1]
            pass_mask = inside & (zz < sub_z)
            if not pass_mask.any():
                continue
            rows, cols = np.nonzero(pass_mask)

            iwp = l0 * w0 + l1 * w1 + l2 * w2
            iwp_p = iwp[rows, cols]
            inv = 1.0 / iwp_p

            # 透视正确的属性插值
            u = (l0 * (w0 * uv[i0, 0]) + l1 * (w1 * uv[i1, 0]) + l2 * (w2 * uv[i2, 0]))[rows, cols] * inv
            v = (l0 * (w0 * uv[i0, 1]) + l1 * (w1 * uv[i1, 1]) + l2 * (w2 * uv[i2, 1]))[rows, cols] * inv
            nxs = (l0 * (w0 * nrm[i0, 0]) + l1 * (w1 * nrm[i1, 0]) + l2 * (w2 * nrm[i2, 0]))[rows, cols] * inv
            nys = (l0 * (w0 * nrm[i0, 1]) + l1 * (w1 * nrm[i1, 1]) + l2 * (w2 * nrm[i2, 1]))[rows, cols] * inv
            nzs = (l0 * (w0 * nrm[i0, 2]) + l1 * (w1 * nrm[i1, 2]) + l2 * (w2 * nrm[i2, 2]))[rows, cols] * inv
            wxs = (l0 * (w0 * pos[i0, 0]) + l1 * (w1 * pos[i1, 0]) + l2 * (w2 * pos[i2, 0]))[rows, cols] * inv
            wys = (l0 * (w0 * pos[i0, 1]) + l1 * (w1 * pos[i1, 1]) + l2 * (w2 * pos[i2, 1]))[rows, cols] * inv
            wzs = (l0 * (w0 * pos[i0, 2]) + l1 * (w1 * pos[i1, 2]) + l2 * (w2 * pos[i2, 2]))[rows, cols] * inv

            nvec = np.stack([nxs, nys, nzs], axis=1)
            nvec = _normalize(nvec)
            vvec = _normalize(np.stack([eye[0] - wxs, eye[1] - wys, eye[2] - wzs], axis=1))
            if self.double_sided:
                flip = (nvec * vvec).sum(axis=1) < 0.0
                nvec[flip] = -nvec[flip]

            ndl = np.maximum(0.0, nvec @ key_dir)
            hemi = nvec[:, 1] * 0.5 + 0.5
            amb = gnd_col[None, :] * (1.0 - hemi)[:, None] + sky_col[None, :] * hemi[:, None]
            ndv = np.clip(1.0 - np.abs((nvec * vvec).sum(axis=1)), 0.0, 1.0)
            rim = (ndv ** 3)[:, None] * rim_col[None, :]

            if self.use_texture:
                if self.flip_uv:
                    uu = 1.0 - u
                    vv = 1.0 - v
                else:
                    uu, vv = u, v
                base = sample_texture(self.tex, uu, vv)
            else:
                base = np.tile(self.base_color, (len(rows), 1))

            lit = base * (amb + key_col[None, :] * ndl[:, None] * 0.95) + rim * 0.34
            lit = linear_to_srgb(lit)
            color[miny + rows, minx + cols] = lit.astype(np.float32)
            sub_z[rows, cols] = zz[rows, cols]
            drawn += 1

        cov = np.isfinite(zbuf)
        return color, cov, drawn, skipped, (_time.time() - t0)


# ---------------------------------------------------------------------------
# 渲染主流程
# ---------------------------------------------------------------------------


def build_parser():
    p = argparse.ArgumentParser(
        prog="render_glb.py",
        description="纯离线 glTF(.glb) 软渲染器：检查带蒙皮的模型（PZ CompanionDogs / CompanionCat）。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("model", help="输入 .glb 模型路径")
    p.add_argument("out", nargs="?", help="输出 PNG 路径（--list 时可省略）")
    p.add_argument("--anim", default=None, help="播放的 clip 名（默认不播，使用绑定/rest 姿态）")
    p.add_argument("--time", type=float, default=0.35, help="动画采样时间（秒），默认 0.35，超出时长则 clamp 到末尾")
    p.add_argument("--size", default="900x700", help="输出尺寸 WxH，默认 900x700")
    p.add_argument("--azimuth", type=float, default=-35.0, help="环绕方位角（度），默认 -35")
    p.add_argument("--elevation", type=float, default=12.0, help="仰角（度），默认 12")
    p.add_argument("--zoom", type=float, default=1.0, help="自动取景后的额外缩放，默认 1.0")
    p.add_argument("--ss", type=int, default=2, help="超采样倍数，默认 2")
    p.add_argument("--bg", default="#202830", help="背景色：transparent 或 #RRGGBB，默认 #202830")
    p.add_argument("--no-texture", action="store_true", help="不采样贴图，用材质基色/灰色平涂")
    p.add_argument("--list", action="store_true", help="只打印诊断信息后退出")
    p.add_argument("--flip-uv", action="store_true", help="UV 的 V 翻转（默认按 glTF 约定 v 向下）")
    p.add_argument("--views", action="store_true", help="渲染 4 个方位角（-35/35/145/215）拼成 2x2 图")
    p.add_argument("--texture", default=None, help="显式指定外置贴图 PNG（覆盖内嵌/自动匹配）")
    p.add_argument("--fov", type=float, default=30.0, help="垂直视场角（度），默认 30")
    p.add_argument("--fill", type=float, default=0.82, help="自动取景时模型占画面的比例，默认 0.82")
    p.add_argument("--bg-color", default=None, help=argparse.SUPPRESS)
    return p


def describe(glb: Glb, mesh: SkinnedMesh, tex_desc: str, tex_img, overrides=None, pose_label="rest") -> str:
    lines = []
    lines.append("模型        : %s" % glb.path)
    lines.append("generator   : %s" % glb.g.get("asset", {}).get("generator", "?"))
    lines.append("节点数      : %d" % len(glb.nodes))
    lines.append("骨骼(joint) : %d" % len(mesh.joint_nodes))
    lines.append("顶点/三角   : %d verts / %d tris" % (mesh.vertex_count, mesh.tri_count))
    lo, hi = mesh.rest_bbox()
    lines.append(
        "rest bbox   : min=(%.4f, %.4f, %.4f) max=(%.4f, %.4f, %.4f) size=(%.4f, %.4f, %.4f)"
        % (lo[0], lo[1], lo[2], hi[0], hi[1], hi[2], hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    )
    lines.append("材质        : %s  doubleSided=%s" % (
        (mesh.material or {}).get("name", "?"), mesh.double_sided))
    lines.append("贴图        : %s" % tex_desc)
    if tex_img is not None:
        lines.append("贴图尺寸    : %dx%d" % tex_img.size)
    lines.append("动画数      : %d" % len(glb.g.get("animations", [])))
    for i, a in enumerate(glb.g.get("animations", [])):
        try:
            dur = animation_duration(glb, a)
        except Exception:
            dur = float("nan")
        lines.append("  [%2d] %-24s %5.3fs  channels=%d" % (i, a.get("name", "?"), dur, len(a.get("channels", []))))
    interps = set()
    for a in glb.g.get("animations", []):
        for s in a.get("samplers", []):
            interps.add(s.get("interpolation", "LINEAR"))
    lines.append("插值类型    : %s" % (", ".join(sorted(interps)) or "-"))
    # 朝向辅助：头/尾等关节的世界坐标（按节点名取变换，便于后续程序化改造）
    world = compute_world_matrices(glb, overrides)
    lines.append("关节世界坐标 (姿态: %s)：" % pose_label)
    labels = ["Bip01_Head", "neck", "nose", "tail_01", "tail_05", "Root_bone", "Base", "Dummy01",
              "Spine_base", "thigh_f.L", "thigh_b.L", "thigh_f.R", "thigh_b.R", "Ear.L", "Ear.R"]
    for lab in labels:
        ni = glb.node_by_name(lab)
        if ni is not None and ni < len(world) and world[ni] is not None:
            p = world[ni][:3, 3]
            lines.append("  joint %-12s world=(%7.4f, %7.4f, %7.4f)" % (lab, p[0], p[1], p[2]))
    return "\n".join(lines)


def render_one(glb, mesh, args, tex_img, azimuth, width, height, tex_note):
    """渲染单张，返回 (PIL.Image, 采样到的时间, 使用的 bbox, 统计信息)。"""
    overrides = None
    t_used = None
    anim_name = args.anim
    if anim_name:
        anims = glb.g.get("animations", [])
        target = None
        for a in anims:
            if a.get("name") == anim_name:
                target = a
                break
        if target is None:
            raise ModelError(
                "找不到动画 clip：%r\n可用 clip：\n  %s"
                % (anim_name, "\n  ".join(a.get("name", "?") for a in anims) or "(无)")
            )
        dur = animation_duration(glb, target)
        t_used = max(0.0, min(float(args.time), dur))
        overrides = eval_animation(glb, target, t_used)
    world = compute_world_matrices(glb, overrides)
    pos, nrm = mesh.posed(world)

    ss = max(1, int(args.ss))
    rw, rh = width * ss, height * ss
    cam, (lo, hi) = fit_camera(pos, azimuth, args.elevation, rw, rh, args.zoom,
                               fov_y_deg=args.fov, fill=args.fill)

    tex_lin = None
    if tex_img is not None and not args.no_texture:
        tarr = np.asarray(tex_img, dtype=np.float64) / 255.0
        tex_lin = srgb_to_linear(tarr).astype(np.float64)

    bg_rgb, transparent = parse_color(args.bg)
    r = Renderer(rw, rh, bg_rgb, transparent, tex_lin, use_texture=(not args.no_texture),
                 base_color=mesh.base_color, flip_uv=args.flip_uv,
                 double_sided=mesh.double_sided)
    color, cov, drawn, skipped, elapsed = r.render(cam, pos, nrm, mesh.uv, mesh.tris)

    img = Image.fromarray((np.clip(color, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGB")
    if transparent:
        alpha = (cov * 255).astype(np.uint8)
        img = img.convert("RGBA")
        img.putalpha(Image.fromarray(alpha, "L"))
    if ss > 1:
        img = img.resize((width, height), Image.LANCZOS)
    stats = dict(tri_drawn=drawn, tri_skipped=skipped, seconds=elapsed,
                 bbox=(lo, hi), time=t_used, res=(rw, rh))
    return img, stats


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        width, height = parse_size(args.size)
        parse_color(args.bg)  # 提前校验
        glb = Glb(args.model)
        mesh = SkinnedMesh(glb)

        query_names = []
        images = glb.g.get("images", [])
        if mesh.base_color_texture_index is not None and mesh.base_color_texture_index < len(images):
            query_names.append(images[mesh.base_color_texture_index].get("name") or "")
        if mesh.material:
            query_names.append(mesh.material.get("name") or "")
        query_names.append(mesh.mesh_name)
        query_names.append(os.path.splitext(os.path.basename(glb.path))[0])

        tex_img, tex_note = resolve_texture(
            glb, mesh.base_color_texture_index, query_names,
            explicit_path=args.texture, verbose=not args.list,
        )

        if args.list:
            overrides = None
            pose_label = "rest / 绑定姿态"
            if args.anim:
                anims = glb.g.get("animations", [])
                target = next((a for a in anims if a.get("name") == args.anim), None)
                if target is None:
                    raise ModelError(
                        "找不到动画 clip：%r\n可用 clip（%d 个）：\n  %s"
                        % (args.anim, len(anims), "\n  ".join(a.get("name", "?") for a in anims))
                    )
                dur = animation_duration(glb, target)
                t_used = max(0.0, min(float(args.time), dur))
                overrides = eval_animation(glb, target, t_used)
                pose_label = "%s @ t=%.3fs (clip 时长 %.3fs)" % (args.anim, t_used, dur)
            print(describe(glb, mesh, tex_note, tex_img, overrides, pose_label))
            return 0

        if not args.out:
            raise ModelError("缺少输出路径 <out.png>（或使用 --list 只查看诊断信息）")

        out_dir = os.path.dirname(os.path.abspath(args.out))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)

        if args.anim:
            anims = [a.get("name") for a in glb.g.get("animations", [])]
            if args.anim not in anims:
                raise ModelError(
                    "找不到动画 clip：%r\n可用 clip（%d 个）：\n  %s"
                    % (args.anim, len(anims), "\n  ".join(a or "?" for a in anims))
                )

        t_start = _time.time()
        if args.views:
            azs = [-35.0, 35.0, 145.0, 215.0]
            cw = max(1, width // 2)
            ch = max(1, height // 2)
            tiles = []
            for az in azs:
                img, st = render_one(glb, mesh, args, tex_img, az, cw, ch, tex_note)
                tiles.append(img)
                print(
                    "[view az=%6.1f] tris=%d skip=%d %.2fs  sample_t=%s"
                    % (az, st["tri_drawn"], st["tri_skipped"], st["seconds"],
                       ("%.3f" % st["time"]) if st["time"] is not None else "rest")
                )
            sheet = Image.new("RGBA" if tiles[0].mode == "RGBA" else "RGB", (cw * 2, ch * 2))
            for i, im in enumerate(tiles):
                sheet.paste(im, ((i % 2) * cw, (i // 2) * ch))
            if sheet.size != (width, height):
                sheet = sheet.resize((width, height), Image.LANCZOS)
            sheet.save(args.out)
            print("wrote %s (%dx%d, 2x2 views, cell %dx%d)" % (args.out, width, height, cw, ch))
        else:
            img, st = render_one(glb, mesh, args, tex_img, args.azimuth, width, height, tex_note)
            img.save(args.out)
            print(
                "[render] tris=%d skip=%d raster=%.2fs  az=%.1f el=%.1f ss=%d sample_t=%s"
                % (st["tri_drawn"], st["tri_skipped"], st["seconds"], args.azimuth,
                   args.elevation, args.ss,
                   ("%.3f" % st["time"]) if st["time"] is not None else "rest")
            )
            print("wrote %s (%dx%d)" % (args.out, width, height))

        print("[model] %s" % glb.path)
        print("[texture] %s" % tex_note)
        print("[total] %.2fs" % (_time.time() - t_start))
        return 0

    except ModelError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("已中断", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
