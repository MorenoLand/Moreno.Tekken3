import struct
from pose import PART_ROWS, PART_SLOTS, SECOND_MESH
class Stream:
    def __init__(self, b, o):
        self.b = b
        self.o = o
    def u32(self):
        v = struct.unpack_from("<I", self.b, self.o)[0]
        self.o += 4
        return v
    def bytes_list(self):
        n = self.u32()
        out = []
        buf = 0
        while len(out) < n:
            if buf == 0:
                buf = self.u32()
            out.append(buf & 0xFF)
            buf >>= 8
        return out
    def nine_list(self):
        n = self.u32()
        out = []
        buf = 0
        while len(out) < n:
            if buf == 0:
                buf = self.u32()
            out.append((buf & 0xFF, buf >> 8 & 1))
            buf >>= 9
        return out
    def two_list(self):
        n = self.u32()
        out = []
        buf = 0
        while len(out) < n:
            if buf == 0:
                buf = self.u32()
            out.append(buf & 3)
            buf >>= 2
        return out
def parse_vertex_stream(b, o):
    s = Stream(b, o)
    r = {"slot": s.u32()}
    r["copy"] = [s.bytes_list(), s.bytes_list()]
    n = s.u32()
    r["verts"] = [struct.unpack_from("<3h", b, s.o + 8 * i) for i in range(n)]
    s.o += 8 * n
    r["sum"] = s.nine_list()
    r["pair_a"] = [s.nine_list(), s.nine_list()]
    r["pair_b"] = [s.nine_list(), s.nine_list()]
    r["half"] = s.two_list()
    r["end"] = s.o
    return r
def parse_polys(b, o):
    s = Stream(b, o)
    out = {"tri": [], "quad": [], "ttri": [], "tquad": []}
    for name, words in (("tri", 2), ("quad", 2), ("ttri", 2), ("tquad", 3)):
        n = s.u32()
        for _ in range(n):
            w = [s.u32() for _ in range(words)]
            out[name].append(w)
    out["end"] = s.o
    return out
def poly_indices(name, w):
    v = w[0]
    if name in ("tri", "ttri"):
        return [(v & 0x1FC) >> 2, (v >> 7 & 0x1FC) >> 2, (v >> 14 & 0x1FC) >> 2]
    return [(v & 0x1FC) >> 2, (v >> 7 & 0x1FC) >> 2, (v >> 14 & 0x1FC) >> 2, (v >> 23 & 0x1FC) >> 2]
def _add(a, b):
    return tuple(x + y for x, y in zip(a, b))
def _half(a):
    return tuple(x >> 1 for x in a)


def _transform(pose, v):
    r, t = pose
    return tuple((r[i * 3] * v[0] + r[i * 3 + 1] * v[1] + r[i * 3 + 2] * v[2] >> 12) + t[i] for i in range(3))


def build_parts(b, poses, passes=2):
    n = struct.unpack_from("<I", b, 0)[0]
    rows = [struct.unpack_from("<14I", b, 24 + r * 56) for r in range(n)]
    tables = [[(0, 0, 0)] * 256, [(0, 0, 0)] * 256]
    def run(stream_row, poly_row, pose, part):
        t0, t1 = tables
        v = parse_vertex_stream(b, rows[stream_row][12])
        pos = 0
        for bank, lst in ((0, v["copy"][0]), (1, v["copy"][1])):
            for byte in lst:
                t0[pos] = t0[byte // 2 - 1] if bank == 0 else t1[byte // 2]
                pos += 1
        for raw in v["verts"]:
            t0[pos] = _transform(pose, raw)
            pos += 1
        d = v["slot"] // 2 - 1
        for byte, flag in v["sum"]:
            i = byte // 2
            t1[i] = t0[d] = _add(_half(t0[d]) if flag else t0[d], t1[i])
            d += 1
        for k, lst in enumerate(v["pair_a"]):
            for byte, flag in lst:
                i = byte // 2
                t0[d] = _add(t1[i] if k == 0 else t0[i - 1], _half(t0[d]) if flag else t0[d])
                d += 1
        for k, lst in enumerate(v["pair_b"]):
            for byte, flag in lst:
                i = byte // 2
                val = _half(t0[d]) if flag else t0[d]
                t0[d] = val if flag else t0[d]
                if k == 0:
                    t1[i] = val
                else:
                    t0[i - 1] = val
                d += 1
        for e in v["half"]:
            t0[d] = _half(t0[d]) if e != 1 else t0[d]
            d += 1
        return {"part": part, "row": poly_row, "verts": list(t0[:pos]), "polys": textured_polys(b, rows[poly_row])}
    for _ in range(passes):
        meshes = []
        for part, r in enumerate(PART_ROWS[:18]):
            pose = poses[PART_SLOTS[part]]
            if r and rows[r][1] and rows[r - 1][12]:
                meshes.append(run(r - 1, r, pose, part))
            if part in SECOND_MESH and rows[r + 1][1] and rows[r][12]:
                meshes.append(run(r, r + 1, pose, part))
    return meshes


def textured_polys(b, f):
    polys = parse_polys(b, f[1])
    c = f[2]
    u16 = lambda o: struct.unpack_from("<H", b, o)[0]
    pool6 = c + u16(c)
    o = pool6 + u16(pool6)
    out = []
    for name, stride in (("tri", 4), ("quad", 5), ("ttri", 4), ("tquad", 5)):
        count = b[o]
        o += 1
        for i in range(count):
            clut_page = u16(c + 2 * (b[o] + 1))
            uvs = [(u16(pool6 + 2 * (b[o + 1 + k] + 1)) & 0xFF, u16(pool6 + 2 * (b[o + 1 + k] + 1)) >> 8) for k in range(stride - 1)]
            out.append({"verts": poly_indices(name, polys[name][i]), "uv": uvs, "clut": clut_page & 0xFF, "page": clut_page >> 8})
            o += stride
    return out
