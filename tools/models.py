import struct
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
def rest_pose(b):
    n = struct.unpack_from("<I", b, 0)[0]
    rows = [struct.unpack_from("<14I", b, 24 + r * 56) for r in range(n)]
    parent = [struct.unpack_from("<i", b, 24 + r * 56 + 24)[0] for r in range(n)]
    pivot = [struct.unpack_from("<3i", b, 24 + r * 56 + 12) for r in range(n)]
    world = []
    for r in range(n):
        w = (0, 0, 0) if parent[r] < 0 or parent[r] >= r else world[parent[r]]
        world.append(_add(w, pivot[r]))
    t0 = [(0, 0, 0)] * 256
    t1 = [(0, 0, 0)] * 256
    meshes = []
    for r in range(1, n):
        prev = rows[r - 1]
        f = rows[r]
        if not f[1] or not prev[12]:
            continue
        v = parse_vertex_stream(b, prev[12])
        pos = 0
        for bank, lst in ((0, v["copy"][0]), (1, v["copy"][1])):
            for byte in lst:
                t0[pos] = t0[byte // 2 - 1] if bank == 0 else t1[byte // 2]
                pos += 1
        for raw in v["verts"]:
            t0[pos] = _add(raw, world[r])
            pos += 1
        dest = v["slot"] // 2 - 1
        d = dest
        for byte, flag in v["sum"]:
            i = byte // 2
            val = _add(_half(t0[d]) if flag else t0[d], t1[i])
            t1[i] = t0[d] = val
            d += 1
        for k, lst in enumerate(v["pair_a"]):
            for byte, flag in lst:
                i = byte // 2
                src = t1[i] if k == 0 else t0[i - 1]
                t0[d] = _add(src, _half(t0[d]) if flag else t0[d])
                d += 1
        for k, lst in enumerate(v["pair_b"]):
            for byte, flag in lst:
                i = byte // 2
                val = _half(t0[d]) if flag else t0[d]
                if flag:
                    t0[d] = val
                if k == 0:
                    t1[i] = val
                else:
                    t0[i - 1] = val
                d += 1
        for e in v["half"]:
            if e != 1:
                t0[d] = _half(t0[d])
            d += 1
        p = parse_polys(b, f[1])
        verts = list(t0[:pos])
        faces = []
        for name in ("tri", "ttri"):
            faces += [poly_indices(name, w) for w in p[name]]
        for name in ("quad", "tquad"):
            for w in p[name]:
                a, bb, c, dd = poly_indices(name, w)
                faces.append([a, bb, dd, c])
        meshes.append({"row": r, "parent": parent[r], "pivot": pivot[r], "verts": verts, "faces": faces})
    return meshes
