import struct
def s16(v): return ((v + 0x8000) & 0xFFFF) - 0x8000
def s32(v): return ((v + 0x80000000) & 0xFFFFFFFF) - 0x80000000
def clamp16(v): return max(-32768, min(32767, v))
class Exe:
    def __init__(self, data): self.data = data
    def at(self, addr, n): return self.data[addr - 0x80010000 + 0x800:addr - 0x80010000 + 0x800 + n]
    def s16s(self, addr, n): return list(struct.unpack("<%dh" % n, self.at(addr, 2 * n)))
    def i32s(self, addr, n): return list(struct.unpack("<%di" % n, self.at(addr, 4 * n)))
def mat_mul(p, l): return [clamp16(sum(p[i * 3 + k] * l[k * 3 + j] for k in range(3)) >> 12) for i in range(3) for j in range(3)]
def rotate(p, v): return [sum(p[i * 3 + k] * v[k] for k in range(3)) >> 12 for i in range(3)]
def rotate_big(p, v):
    hi = [(abs(x) >> 15) * (1 if x >= 0 else -1) for x in v]
    lo = [(abs(x) & 0x7FFF) * (1 if x >= 0 else -1) for x in v]
    big = [sum(p[i * 3 + k] * clamp16(hi[k]) for k in range(3)) for i in range(3)]
    small = [sum(p[i * 3 + k] * clamp16(lo[k]) for k in range(3)) >> 12 for i in range(3)]
    return [small[i] + big[i] * 8 for i in range(3)]
def gpf(ir0, a, b, c): return [clamp16(ir0 * x >> 12) for x in (a, b, c)]
def lzcr(x):
    x &= 0xFFFFFFFF
    x = ~x & 0xFFFFFFFF if x & 0x80000000 else x
    return 32 - x.bit_length()
class Pose:
    def __init__(self, exe):
        self.e = exe
        self.sin = exe.s16s(0x8001E8C4, 5120)
        self.cos = self.sin[1024:]
        self.sqrt_table = exe.s16s(0x80098D08, 512)
        self.order = list(exe.at(0x8001A330, 10))
        self.fixed = exe.s16s(0x80096EAC, 9)
        self.offsets = {a: exe.i32s(a, 3) for a in (0x80096ECC, 0x80096ED8, 0x80096EE4, 0x80096EF0, 0x80096EFC, 0x80096F08, 0x80096F14, 0x80096F20)}
    def euler(self, p1, p2, p3):
        sn = lambda i: self.sin[i >> 1]
        cs = lambda i: self.cos[i >> 1]
        i8, i12, i10 = p1 >> 3 & 0x1FFE, p3 >> 3 & 0x1FFE, p2 >> 3 & 0x1FFE
        c3, c1, c2, s3, s1 = cs(i12), cs(i8), cs(i10), sn(i12), sn(i8)
        iv4 = c1 * c3 >> 12
        u5, u6, u3 = gpf(s1, c3, s3, c2)
        s2 = sn(i10)
        iv7 = c1 * s3 >> 12
        g2 = gpf(s2, u5, u6, iv4)
        out = [0] * 9
        out[7], out[6] = s16(u3), s16(-s2)
        out[1], out[4], out[2] = s16(g2[0] - iv7), s16(iv4 + g2[1]), s16(u6 + g2[2])
        g3 = gpf(c2, c3, s3, c1)
        out[5] = s16((iv7 * s2 >> 12) - u5)
        out[0], out[3], out[8] = s16(g3[0]), s16(g3[1]), s16(g3[2])
        return out
    def compose(self, parent, local, offset):
        v = [s16(x) for x in offset]
        r = rotate(parent[0], v)
        return (mat_mul(parent[0], local), [parent[1][i] + r[i] for i in range(3)])
    def isqrt(self, x):
        z = lzcr(x)
        if z == 32: return 0
        z &= ~1
        y = x >> (0x18 - z) if z - 0x18 < 0 else x << (z - 0x18)
        return ((self.sqrt_table[y - 0x40] << ((0x1F - z) >> 1)) & 0xFFFFFFFF) >> 12
    def twist(self, m, a, b):
        x0, x1, x3, x4, x6, x7 = m[0], m[1], m[3], m[4], m[6], m[7]
        m[0], m[3], m[1] = s16(x0 * b + x1 * a >> 12), s16(x3 * b + x4 * a >> 12), s16(-x0 * a + x1 * b >> 12)
        m[4], m[6], m[7] = s16(-x3 * a + x4 * b >> 12), s16(x6 * b + x7 * a >> 12), s16(-x6 * a + x7 * b >> 12)
    def aim(self, goal, angle, arm):
        x, y, z = goal
        d2 = x * x + y * y + z * z
        if d2 == 0: return None
        dist = self.isqrt(d2)
        inv = 0x400000 // dist
        ax, ay, az = x * inv >> 10, y * inv >> 10, z * inv >> 10
        a13 = ax + 0x1000
        if a13 == 0: a13, a10, a5 = -0x800, y * inv >> 11, -0x1000
        else:
            if a13 < 0x2000:
                a13 = -(0x1000000 // a13)
                a10 = a13 * ay >> 12
            else: a13, a10 = -0x800, -ay >> 1
            a5 = 0x1000
        a4 = (a10 * ay >> 12) + a5
        a13 = a13 * az >> 12
        u = angle >> 3 & 0x1FFE
        c, s = self.cos[u >> 1], self.sin[u >> 1]
        a6, a5b, a14, a11, a12 = a10 * (a5 + ax) >> 12, a13 * (a5 + ax) >> 12, a13 * ay >> 12, a10 * az >> 12, (a13 * az >> 12) + 0x1000
        m1 = [s16(ax), s16(c * a6 + s * a5b >> 12), s16(-s * a6 + c * a5b >> 12), s16(ay), s16(c * a4 + s * a14 >> 12), s16(-s * a4 + c * a14 >> 12), s16(az), s16(c * a11 + s * a12 >> 12), s16(-s * a11 + c * a12 >> 12)]
        if not arm:
            if dist > 0x37B: return m1, None
            if dist < 3: return m1, 1
            t = inv * 0x6F8 >> 11
            hi, lo = (dist * 0x800 + t) * 0x92, (dist * 0x800 - t) * 0x93
        else:
            if dist > 0x215: return m1, None
            if dist < 0x47: return m1, 1
            t = inv * 0x9204 >> 11
            hi, lo = (dist * 0x800 + t) * 0xD9, (dist * 0x800 - t) * 0x11A
        hi, lo = s32(hi) >> 16, s32(lo) >> 16
        if hi < 0x1001:
            r12 = 0
            if hi < -0x1000: hi = -0x1000
            else:
                r12 = self.isqrt(0x1000000 - hi * hi)
                r12 = r12 if arm else -r12
        else: hi, r12 = 0x1000, 0
        self.twist(m1, s16(r12), s16(hi))
        if lo < 0x1001:
            r13 = 0
            if lo < -0x1000: lo = -0x1000
            elif not arm: r13 = r12 * -0x1012 >> 12
            else: r13 = r12 * -0x14D4 >> 12
        else: lo, r13 = 0x1000, 0
        a = hi * lo + r12 * r13
        a = a + 0xFFF if a < 0 else a
        b = -r12 * lo + hi * r13
        b = b + 0xFFF if b < 0 else b
        sv = s16(b >> 12)
        m2 = [s16(a >> 12), s16(-sv), 0, sv, s16(a >> 12), 0, 0, 0, 0x1000]
        return m1, m2
    def locals(self, pose):
        loc = [[[0] * 9, [0, 0, 0]] for _ in range(32)]
        for k in range(10): loc[self.order[k]][0] = self.euler(pose[19 + 3 * k], pose[20 + 3 * k], pose[21 + 3 * k])
        for s in (2, 3, 7): loc[s][0] = mat_mul(loc[s][0], self.fixed)
        root = (loc[0][0], [pose[0], pose[1], pose[2]])
        r1 = self.compose(root, loc[1][0], self.offsets[0x80096ECC])
        r2 = self.compose(r1, loc[3][0], self.offsets[0x80096ED8])
        r3 = self.compose(r1, loc[7][0], self.offsets[0x80096EE4])
        r4 = self.compose(root, loc[11][0], self.offsets[0x80096EF0])
        goals = []
        for ref, off, tgt in ((r2, 0x80096EFC, 3), (r3, 0x80096F08, 6), (r4, 0x80096F14, 9), (r4, 0x80096F20, 12)):
            m = ref[0]
            rt = [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]
            v = rotate_big(rt, [pose[tgt + i] - ref[1][i] for i in range(3)])
            goals.append([v[i] + self.offsets[off][i] for i in range(3)])
        for (slot, ang, arm), g in zip(((4, 15, 1), (8, 16, 1), (12, 17, 0), (15, 18, 0)), goals):
            r = self.aim(g, pose[ang], arm)
            if r is None: continue
            loc[slot][0] = r[0]
            if isinstance(r[1], list): loc[slot + 1][0] = r[1]
        return loc, root
PART_ROWS = (0, 1, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24)
PART_SLOTS = (0, 1, 11, 12, 13, 14, 15, 16, 17, 3, 4, 5, 6, 7, 8, 9, 10, 2, 18, 19, 20, 21)
SECOND_MESH = (1, 2, 17)
IDENTITY = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]
def skeleton(model, pp, pose, root):
    rows = [struct.unpack_from("<14I", model, 24 + r * 56) for r in range(struct.unpack_from("<I", model, 0)[0])]
    info = {}
    for part in range(18):
        r = PART_ROWS[part]
        w = struct.unpack_from("<3ii", model, 24 + r * 56 + 12)
        info[PART_SLOTS[part]] = (struct.unpack_from("<i", model, 24 + r * 56 + 24)[0], (w[0], w[1], -w[2]))
    loc, _ = pp.locals(pose)
    world = {}
    def solve(slot):
        if slot in world: return world[slot]
        parent_part, pivot = info[slot]
        parent = root if parent_part < 0 else solve(PART_SLOTS[parent_part])
        m = loc[slot][0] if any(loc[slot][0]) else IDENTITY
        world[slot] = pp.compose(parent, m, pivot)
        return world[slot]
    for s in range(18): solve(s)
    return world
class Motion:
    def __init__(self, exe):
        self.exe = exe.data

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
def idle_pose(motion, character, common, frame=0):
    rows = struct.unpack_from("<I", character, 8)[0]
    ptr = struct.unpack_from("<I", character, rows)[0]
    source, ptr = (common, ptr - 0x40000000) if ptr >= 0x40000000 else (character, ptr)
    return motion.frame(source[struct.unpack_from("<I", source, 0x1C)[0] + ptr:], frame)
FACING = ([13, 0, 4096, 0, 4096, 0, -4096, 0, 13], [0, 0, 0])
