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
PART_ROWS = (0, 1, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24)
PART_SLOTS = (0, 1, 11, 12, 13, 14, 15, 16, 17, 3, 4, 5, 6, 7, 8, 9, 10, 2, 18, 19, 20, 21)
IDENTITY = ((4096, 0, 0, 0, 4096, 0, 0, 0, 4096), (0, 0, 0))


def _transform(pose, v):
    r, t = pose
    return tuple((r[i * 3] * v[0] + r[i * 3 + 1] * v[1] + r[i * 3 + 2] * v[2] >> 12) + t[i] for i in range(3))


def build_parts(b, poses):
    n = struct.unpack_from("<I", b, 0)[0]
    rows = [struct.unpack_from("<14I", b, 24 + r * 56) for r in range(n)]
    t0 = [(0, 0, 0)] * 256
    t1 = [(0, 0, 0)] * 256
    meshes = []
    for part, r in enumerate(PART_ROWS):
        f = rows[r]
        if r == 0 or not f[1] or not rows[r - 1][12]:
            continue
        v = parse_vertex_stream(b, rows[r - 1][12])
        pose = poses[PART_SLOTS[part]]
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
        meshes.append({"part": part, "row": r, "verts": list(t0[:pos]), "polys": textured_polys(b, f)})
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


class Motion:
    def __init__(self, exe):
        self.exe = exe

    def u16(self, addr):
        o = addr - 0x80010000 + 0x800
        return self.exe[o] | self.exe[o + 1] << 8

    def u8(self, addr):
        return self.exe[addr - 0x80010000 + 0x800]

    def spline(self, words, i, count, shift):
        last = count - 1
        s16 = lambda v: v - 0x10000 if v & 0x8000 else v
        v3 = s16(words[0])
        key = s16(words[1])
        ptr = 2
        v2 = v3
        v7 = ((key >> 5) << shift) + v3
        end = 0
        while True:
            start, v6, v5, v4 = end, v7, v2, v3
            end = start + (key & 31) + 1
            if end == last:
                break
            key = s16(words[ptr])
            ptr += 1
            v7 = v6 + ((key >> 5) << shift)
            v3, v2 = v5, v6
            if not 0 < i - end:
                break
        t = i - start
        length = end - start
        idx = 0
        if t:
            idx = (self.u8(0x800966F8 + length * 32 + t + 3) if length - 16 < 1 else self.u8(0x80096B3C - length * 32 - t)) << 1
        neg = -idx
        carry = 0
        if start == 0:
            mul = self.u16(0x80096C20 + neg)
            acc = self.u16(0x80096A1C + neg) * (v7 - v5)
        else:
            prev = self.u16(0x8009691C + idx) * (v4 - v5)
            if end == last:
                mul = self.u16(0x80096C20 + neg) + self.u16(0x80096A1C + neg) + 0x2AAB
                acc = prev
            else:
                acc = self.u16(0x80096A1C + neg) * (v7 - v5)
                mul = self.u16(0x80096B1E + neg)
                carry = prev
        if start != 0 and end != last:
            acc += carry
        total = (acc + mul * (v6 - v5)) & 0xFFFFFFFF
        total = total - (1 << 32) if total & 0x80000000 else total
        return (total >> 16) + v5

    def frame(self, stream, frame, channels=49):
        count = stream[0]
        frame = max(0, min(frame, count - 1))
        desc = [stream[1]] + list(stream[2:2 + channels - 1])
        words = [stream[o] | stream[o + 1] << 8 for o in range(50, len(stream) - 1, 2)]
        out = []
        pos = 0
        for k in range(channels):
            n = desc[k]
            i = frame if k % 2 == 0 else count - (frame + 1)
            data = words[pos:pos + n]
            s16 = lambda v: v - 0x10000 if v & 0x8000 else v
            if n == 0:
                v = 0
            elif n == 1:
                v = s16(data[0]) << 1
            elif n == 2:
                v = s16(data[1]) * i
                v = v >> 5 if count > 9 else v
                v = (data[0] + v) << 1
            elif n == count:
                v = s16(data[i]) << 1
            else:
                v = self.spline(data, i, count, self.u8(0x80096C24 + k)) << 1
            out.append(((v + 0x8000) & 0xFFFF) - 0x8000)
            pos += n
        return out
