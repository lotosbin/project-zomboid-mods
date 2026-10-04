"""最小可用的 GLB(glTF 2.0 二进制) 读写工具。

只覆盖 CompanionDogs 系模型实际用到的特性：
  * 单文件 GLB：12 字节头 + JSON chunk + BIN chunk
  * accessor：SCALAR / VEC2 / VEC3 / VEC4 / MAT4，分量类型 byte/ubyte/short/ushort/uint/float
  * bufferView 带 byteStride 或不带（模型里每个采样器独占一个 bufferView）

没有实现稀疏 accessor、压缩扩展、GLB 之外的外部 .bin。写入时按 4 字节对齐补 padding。
"""

import json
import struct

import numpy as np

# glTF componentType -> (numpy 单字符码, 字节数)
COMP = {
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
}

# glTF type -> 分量个数
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

GLB_MAGIC = b"glTF"
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


class Glb:
    """就地可改的 GLB：读进来后改 self.g(JSON) 与 self.bin(二进制块)，再 save()。"""

    def __init__(self, path):
        self.path = str(path)
        raw = open(self.path, "rb").read()
        if raw[:4] != GLB_MAGIC:
            raise ValueError(f"not a GLB file: {self.path}")
        self.version, self.length = struct.unpack_from("<II", raw, 4)
        off = 12
        self.g = None
        self.bin = b""
        while off < len(raw):
            ln, ty = struct.unpack_from("<II", raw, off)
            off += 8
            chunk = raw[off:off + ln]
            off += ln
            if ty == CHUNK_JSON:
                self.g = json.loads(chunk.decode("utf-8"))
            elif ty == CHUNK_BIN:
                self.bin = chunk
        if self.g is None:
            raise ValueError(f"GLB has no JSON chunk: {self.path}")

    # ---------- 读 ----------

    def acc(self, index):
        """读一个 accessor，返回 (count, ncomp) 的 ndarray。"""
        a = self.g["accessors"][index]
        fmt, size = COMP[a["componentType"]]
        n = NCOMP[a["type"]]
        bv = self.g["bufferViews"][a["bufferView"]]
        base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride") or size * n
        dt = np.dtype(fmt)
        if stride == size * n:
            flat = np.frombuffer(self.bin, dtype=dt, count=a["count"] * n, offset=base)
            return flat.reshape(a["count"], n).copy()
        out = np.empty((a["count"], n), dtype=dt)
        for k in range(a["count"]):
            out[k] = np.frombuffer(self.bin, dtype=dt, count=n, offset=base + k * stride)
        return out

    def acc_flat(self, index):
        return self.acc(index).reshape(-1)

    def node_names(self):
        return [n.get("name", "?") for n in self.g["nodes"]]

    def node_index(self, name):
        for i, n in enumerate(self.g["nodes"]):
            if n.get("name") == name:
                return i
        raise KeyError(f"node not found: {name}")

    def parent_map(self):
        par = {}
        for i, n in enumerate(self.g["nodes"]):
            for c in n.get("children", []):
                par[c] = i
        return par

    def joint_names(self):
        """skin.joints 顺序（= JOINTS_0 里存的下标所指的顺序）对应的骨骼名。"""
        joints = self.g["skins"][0]["joints"]
        names = self.node_names()
        return [names[j] for j in joints]

    # ---------- 写 ----------

    def set_acc(self, index, values):
        """就地写回 accessor（分量类型与形状必须和原来一致，元素个数不变）。"""
        a = self.g["accessors"][index]
        fmt, size = COMP[a["componentType"]]
        n = NCOMP[a["type"]]
        bv = self.g["bufferViews"][a["bufferView"]]
        base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride") or size * n
        data = np.asarray(values, dtype=np.dtype(fmt))
        if data.shape != (a["count"], n):
            raise ValueError(f"accessor {index}: shape {data.shape} != {(a['count'], n)}")
        buf = bytearray(self.bin)
        if stride == size * n:
            buf[base:base + a["count"] * n * size] = data.tobytes()
        else:
            for k in range(a["count"]):
                buf[base + k * stride:base + k * stride + n * size] = data[k].tobytes()
        self.bin = bytes(buf)

    def update_pos_minmax(self, accessor_index, positions):
        a = self.g["accessors"][accessor_index]
        a["min"] = [float(v) for v in np.asarray(positions).min(axis=0)]
        a["max"] = [float(v) for v in np.asarray(positions).max(axis=0)]

    # ---------- 追加数据（用于把共享 accessor 拆成独占的） ----------

    def append_binary(self, data):
        """把一段字节追加到 BIN 末尾（4 字节对齐），返回新 bufferView 的下标。"""
        buf = bytearray(self.bin)
        pad = (4 - len(buf) % 4) % 4
        buf += b"\x00" * pad
        off = len(buf)
        buf += data
        self.bin = bytes(buf)
        self.g["buffers"][0]["byteLength"] = len(self.bin)
        bv = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        self.g["bufferViews"].append(bv)
        return len(self.g["bufferViews"]) - 1

    def clone_accessor_values(self, accessor_index, values):
        """用一份新的采样值造一个独占 accessor（同 componentType/type/count）。"""
        a = self.g["accessors"][accessor_index]
        fmt, size = COMP[a["componentType"]]
        n = NCOMP[a["type"]]
        arr = np.asarray(values, dtype=np.dtype(fmt))
        if arr.shape != (a["count"], n):
            raise ValueError(f"clone_accessor_values: shape {arr.shape} != {(a['count'], n)}")
        bv = self.append_binary(arr.tobytes())
        new = {
            "bufferView": bv,
            "componentType": a["componentType"],
            "count": a["count"],
            "type": a["type"],
        }
        if "normalized" in a:
            new["normalized"] = a["normalized"]
        if "min" in a or "max" in a:
            new["min"] = [float(v) for v in arr.min(axis=0)]
            new["max"] = [float(v) for v in arr.max(axis=0)]
        self.g["accessors"].append(new)
        return len(self.g["accessors"]) - 1

    def detach_channel_output(self, anim_index, channel_index, values):
        """把某个 channel 的采样输出换成一份**独占**的新数据。

        为什么必须这么做：这些 glb 里同一个 clip 内大量 channel 共用同一个 sampler/accessor
        （实测 idle 剪辑里 neck 的平移 accessor 被 11 条 channel 共用）。若就地修改共享 accessor，
        每个 channel 都会把增量叠加一次 —— 11 条就是 11 倍，模型直接被拉爆。
        所以这里为每条要改的 channel 复制出新 accessor + 新 sampler，原数据保持不动。
        """
        anim = self.g["animations"][anim_index]
        ch = anim["channels"][channel_index]
        old_sampler = anim["samplers"][ch["sampler"]]
        new_acc = self.clone_accessor_values(old_sampler["output"], values)
        new_sampler = dict(old_sampler)
        new_sampler["output"] = new_acc
        anim["samplers"].append(new_sampler)
        ch["sampler"] = len(anim["samplers"]) - 1
        return new_acc

    def save(self, path):
        js = json.dumps(self.g, separators=(",", ":")).encode("utf-8")
        js += b" " * ((4 - len(js) % 4) % 4)
        bn = self.bin + b"\x00" * ((4 - len(self.bin) % 4) % 4)
        total = 12 + 8 + len(js) + (8 + len(bn) if bn else 0)
        out = bytearray()
        out += GLB_MAGIC + struct.pack("<II", 2, total)
        out += struct.pack("<II", len(js), CHUNK_JSON) + js
        if bn:
            out += struct.pack("<II", len(bn), CHUNK_BIN) + bn
        open(path, "wb").write(bytes(out))
        return total


# ---------- 四元数 / 矩阵小工具（列向量约定：world = parent * T * R * S） ----------


def quat_to_mat(q):
    """(x, y, z, w) -> 3x3 旋转矩阵。"""
    x, y, z, w = [float(v) for v in q]
    n = x * x + y * y + z * z + w * w
    if n < 1e-12:
        return np.eye(3)
    s = 2.0 / n
    return np.array([
        [1 - s * (y * y + z * z), s * (x * y - z * w), s * (x * z + y * w)],
        [s * (x * y + z * w), 1 - s * (x * x + z * z), s * (y * z - x * w)],
        [s * (x * z - y * w), s * (y * z + x * w), 1 - s * (x * x + y * y)],
    ])


def mat_to_quat(m):
    """3x3 旋转矩阵 -> (x, y, z, w)，w >= 0。"""
    m = np.asarray(m, dtype=float)
    tr = m[0, 0] + m[1, 1] + m[2, 2]
    if tr > 0:
        s = np.sqrt(tr + 1.0) * 2.0
        w = 0.25 * s
        x = (m[2, 1] - m[1, 2]) / s
        y = (m[0, 2] - m[2, 0]) / s
        z = (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2.0
        w = (m[2, 1] - m[1, 2]) / s
        x = 0.25 * s
        y = (m[0, 1] + m[1, 0]) / s
        z = (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2.0
        w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s
        y = 0.25 * s
        z = (m[1, 2] + m[2, 1]) / s
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2.0
        w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s
        y = (m[1, 2] + m[2, 1]) / s
        z = 0.25 * s
    q = np.array([x, y, z, w], dtype=float)
    if q[3] < 0:
        q = -q
    return q / np.linalg.norm(q)


def quat_mul(a, b):
    """Hamilton 积 a ⊗ b：先应用 b 的旋转，再应用 a（列向量约定）。"""
    ax, ay, az, aw = [float(v) for v in a]
    bx, by, bz, bw = [float(v) for v in b]
    return np.array([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ])


def quat_axis_angle(axis, deg):
    axis = np.asarray(axis, dtype=float)
    n = np.linalg.norm(axis)
    if n < 1e-12:
        return np.array([0.0, 0.0, 0.0, 1.0])
    axis = axis / n
    half = np.radians(deg) * 0.5
    s = np.sin(half)
    return np.array([axis[0] * s, axis[1] * s, axis[2] * s, np.cos(half)])


def local_matrix(node):
    """节点的局部 TRS 矩阵（4x4）。"""
    t = np.array(node.get("translation", [0.0, 0.0, 0.0]), dtype=float)
    r = quat_to_mat(node.get("rotation", [0.0, 0.0, 0.0, 1.0]))
    s = np.array(node.get("scale", [1.0, 1.0, 1.0]), dtype=float)
    m = np.eye(4)
    m[:3, :3] = r * s
    m[:3, 3] = t
    return m


def world_matrices(g):
    """按当前节点 TRS 递归出所有节点的世界矩阵（rest pose）。"""
    nodes = g["nodes"]
    out = {}

    def rec(i, parent):
        m = parent @ local_matrix(nodes[i])
        out[i] = m
        for c in nodes[i].get("children", []):
            rec(c, m)

    for root in g["scenes"][g.get("scene", 0)]["nodes"]:
        rec(root, np.eye(4))
    return out
