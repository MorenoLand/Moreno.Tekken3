extends RefCounted
# Fixed-point helpers: sin/cos tables from the exe, atan2, integer square root, C-style division.
# Fields are read with ram.u8/u16/u32 at "actor + offset"; offsets are listed at the top of ram.gd.
const SIN_TABLE := 0x8001e8c4
const COS_TABLE := 0x8001f0c4
const ATAN_TABLE := 0x800210c8
static func s16(v: int) -> int:
	v &= 0xffff
	return v - 0x10000 if v > 0x7fff else v
static func sin(ram, angle: int) -> int:
	var v: int = clampi(ram.s16(SIN_TABLE + (angle >> 3 & 0x1ffe)), -0xfff, 0xfff)
	return v * 8
static func cos(ram, angle: int) -> int:
	var v: int = clampi(ram.s16(COS_TABLE + (angle >> 3 & 0x1ffe)), -0xfff, 0xfff)
	return v * 8
static func atan_table(ram, x: int) -> int:
	x = s16(x)
	var i: int = (x + 3 if x < 0 else x) >> 2
	i = absi(i)
	var v: int = s16(ram.u8(ATAN_TABLE + i) + (i >> 1))
	return -v if x < 0 else v
static func atan2(ram, p1: int, p2: int) -> int:
	var n1: bool = (p1 << 16) & 0x80000000 != 0
	var n2: bool = (p2 << 16) & 0x80000000 != 0
	var a: int = ((-(p1 & 0xffff)) & 0xffff) if n1 else (p1 & 0xffff)
	var b: int = ((-(p2 & 0xffff)) & 0xffff) if n2 else (p2 & 0xffff)
	var t: int
	if a == b:
		t = 0x200
	elif b < a:
		t = atan_table(ram, (b << 12) / a)
	else:
		t = 0x400 - atan_table(ram, (a << 12) / b)
	var u: int = (t * 16) & 0xffff
	if n1:
		return (u + 0x8000) & 0xffff if n2 else (t * -16 + 0x7fff) & 0xffff
	return (~u & 0xffff) if n2 else u
static func isqrt(v: int) -> int:
	v &= 0xffffffff
	if v == 0:
		return 0
	var g := 1
	var h: int = v
	if v > 1:
		while true:
			g <<= 1
			h >>= 1
			if not (g < h):
				break
	var r: int = g
	while true:
		r = g
		g = (v / r + r) >> 1
		if not (g < r):
			break
	return r
static func tdiv(a: int, b: int) -> int:
	if b == 0:
		return 0
	var q: int = absi(a) / absi(b)
	return -q if (a < 0) != (b < 0) else q
static func lzcr(v: int) -> int:
	v &= 0xffffffff
	if v & 0x80000000:
		v = ~v & 0xffffffff
	if v == 0:
		return 32
	return 32 - _bits(v)
static func _bits(v: int) -> int:
	var n := 0
	while v > 0:
		n += 1
		v >>= 1
	return n
static func table_sqrt(ram, x: int, table: int) -> int:
	if x == 0:
		return 0
	var z: int = lzcr(x) & 0xfffe
	var y: int = x >> (0x18 - z) if 0x18 - z >= 0 else x << (z - 0x18)
	return ((ram.s16(table + (y - 0x40) * 2) << ((0x1f - z) >> 1)) & 0xffffffff) >> 12
