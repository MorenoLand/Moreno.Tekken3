import struct
import zlib
def parse_arc(b):
    if len(b) < 4:
        return None
    n = struct.unpack_from("<I", b, 0)[0]
    if not 1 <= n <= 255 or 4 + 8 * n > len(b):
        return None
    members = [struct.unpack_from("<II", b, 4 + 8 * i) for i in range(n)]
    pos = members[0][0]
    if pos < 4 + 8 * n or pos > 4 + 8 * n + 16:
        return None
    for o, s in members:
        if o != pos or o % 4 or s % 4:
            return None
        pos += s
    return members if pos == len(b) else None
def is_tim(b):
    return len(b) >= 20 and b[:4] == b"\x10\x00\x00\x00" and b[4] in (0, 1, 2, 3, 8, 9, 10, 11) and b[5:8] == b"\0\0\0"
def parse_tim(b, start=0):
    flags = struct.unpack_from("<I", b, start + 4)[0]
    mode = flags & 3
    o = start + 8
    cluts = []
    clut_rect = None
    cw = 0
    if flags & 8:
        size, cx, cy, cw, ch = struct.unpack_from("<IHHHH", b, o)
        data = struct.unpack_from("<%dH" % (cw * ch), b, o + 12)
        cluts = [data[r * cw:(r + 1) * cw] for r in range(ch)]
        clut_rect = (cx, cy, cw, ch)
        o += size
    size, ix, iy, iw, ih = struct.unpack_from("<IHHHH", b, o)
    raw = b[o + 12:o + size]
    width = iw * (4, 2, 1, 2 / 3)[mode]
    return {"mode": mode, "x": ix, "y": iy, "width": int(width), "height": ih, "raw": raw, "cluts": cluts, "clut_rect": clut_rect, "words": iw, "end": o + size}
def rgba(c):
    r, g, b = (c & 31) * 255 // 31, (c >> 5 & 31) * 255 // 31, (c >> 10 & 31) * 255 // 31
    a = 0 if c == 0 else 255
    return bytes((r, g, b, a))
def tim_pixels(t, row=0):
    w, h, raw, mode = t["width"], t["height"], t["raw"], t["mode"]
    out = bytearray()
    if mode in (0, 1):
        if t["cluts"]:
            pal = [rgba(c) for c in t["cluts"][row]]
        else:
            n = 16 if mode == 0 else 256
            pal = [bytes((v, v, v, 255)) for v in (i * 255 // (n - 1) for i in range(n))]
        if mode == 0:
            for i in range(w * h // 2):
                v = raw[i]
                out += pal[v & 15] + pal[v >> 4]
        else:
            for i in range(w * h):
                out += pal[raw[i]]
    elif mode == 2:
        for c in struct.unpack_from("<%dH" % (w * h), raw):
            out += rgba(c)
    else:
        for i in range(w * h):
            out += bytes((raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2], 255))
    return bytes(out)
def write_png(path, w, h, rgba_bytes):
    rows = b"".join(b"\0" + rgba_bytes[y * w * 4:(y + 1) * w * 4] for y in range(h))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)



def tim_stream(b):
    out = []
    o = 0
    while o + 20 <= len(b) and is_tim(b[o:o + 20]):
        t = parse_tim(b, o)
        out.append(t)
        o = t["end"]
    return out


def compose_vram(tims, page_y=0):
    vram = [0] * (1024 * 512)
    for t in tims:
        w = t["words"]
        raw = struct.unpack_from("<%dH" % (w * t["height"]), t["raw"])
        for r in range(t["height"]):
            o = (page_y + t["y"] + r) * 1024 + 384 + t["x"]
            vram[o:o + w] = raw[r * w:(r + 1) * w]
        if t["clut_rect"]:
            cx, cy, cw, ch = t["clut_rect"]
            for r in range(ch):
                o = (504 + cy + r) * 1024 + cx
                vram[o:o + cw] = t["cluts"][r]
    return vram


def decode_page(vram, page, clut):
    tpage = page + 6
    px, py, mode = (tpage & 15) * 64, (tpage >> 4 & 1) * 256, tpage >> 7 & 3
    cx, cy = (clut & 63) * 16, 504 + (clut >> 6)
    pal = [rgba(c) for c in vram[cy * 1024 + cx:cy * 1024 + cx + (16 if mode == 0 else 256)]]
    out = bytearray()
    for y in range(256):
        row = vram[(py + y) * 1024 + px:(py + y) * 1024 + px + (64 if mode == 0 else 128)]
        if mode == 0:
            for w in row:
                out += pal[w & 15] + pal[w >> 4 & 15] + pal[w >> 8 & 15] + pal[w >> 12]
        else:
            for w in row:
                out += pal[w & 255] + pal[w >> 8]
    return bytes(out)
def unpack(src, start=0, limit=1 << 24):
    out = bytearray()
    i = start
    try:
        flag = src[i]
        while flag != 0:
            i += 1
            while flag > 1:
                if flag & 1:
                    out.append(src[i])
                    i += 1
                else:
                    v = src[i] << 8 | src[i + 1]
                    i += 2
                    dist = (v & 0x7FF) or 0x800
                    if dist > len(out):
                        return None
                    for _ in range((v >> 11) or 0x20):
                        out.append(out[-dist])
                flag >>= 1
            if len(out) > limit:
                return None
            flag = src[i]
    except IndexError:
        return None
    return bytes(out), i + 1
def packed_tims(src):
    out = []
    o = 0
    while o < len(src):
        r = unpack(src, o, 1 << 17) if src[o] else None
        if r and len(r[0]) > 40 and is_tim(r[0][:20]):
            out.append(r[0])
            o = (r[1] + 3) & ~3
        else:
            o += 4
    return out
