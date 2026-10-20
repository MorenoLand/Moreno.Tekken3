extends RefCounted
# Hit detection between one fighter attack segments and the other fighter body spheres.
# Fields are read with ram.u8/u16/u32 at "actor + offset"; offsets are listed at the top of ram.gd.
const FMath := preload("res://scripts/combat/fmath.gd")
const Volumes := preload("res://scripts/combat/hit_volumes.gd")
const SQRT_TABLE := 0x8004af40
static var impacts: Array = []
static func abs_half(a: int, b: int) -> int:
	return absi(a - b) >> 1
static func trunc_mid(a: int, b: int) -> int:
	return FMath.tdiv(a + b, 2)
static func seg_sphere(ram, s: int, c: int) -> bool:
	var s0: int = ram.s32(s)
	var s1: int = ram.s32(s + 4)
	var s2: int = ram.s32(s + 8)
	var s3: int = ram.s32(s + 12)
	var s4: int = ram.s32(s + 16)
	var s5: int = ram.s32(s + 20)
	var r: int = ram.s16(c + 12)
	if abs_half(s3, s0) + r < absi(ram.s32(c) - trunc_mid(s3, s0)):
		return false
	if abs_half(s5, s2) + r < absi(ram.s32(c + 8) - trunc_mid(s5, s2)):
		return false
	if abs_half(s4, s1) + r < absi(ram.s32(c + 4) - trunc_mid(s4, s1)):
		return false
	var x0: int = s0
	var z0: int = s2
	var x1: int = s3
	var z1: int = s5
	var dx: int = s3 - x0
	var dy: int = s4 - s1
	var dz: int = s5 - s2
	var y0: int = s1
	var y1: int = s4
	if y0 != y1:
		var lo: int = ram.s32(c + 4) - r
		var hi: int = ram.s32(c + 4) + r
		if y1 < y0:
			if hi < y0:
				var t: int = FMath.tdiv((hi - y0) * 0x1000, dy)
				x0 = s0 + rnd(t * dx)
				z0 = s2 + rnd(t * dz)
			if s4 < lo:
				var t2: int = FMath.tdiv((lo - s1) * 0x1000, dy)
				x1 = s0 + rnd(t2 * dx)
				z1 = s2 + rnd(t2 * dz)
		else:
			if hi < y1:
				var t3: int = FMath.tdiv((hi - y0) * 0x1000, dy)
				x1 = s0 + rnd(t3 * dx)
				z1 = s2 + rnd(t3 * dz)
			if s1 < lo:
				var t4: int = FMath.tdiv((lo - s1) * 0x1000, dy)
				x0 = s0 + rnd(t4 * dx)
				z0 = s2 + rnd(t4 * dz)
	var ex: int = x1 - x0
	var ez: int = z1 - z0
	var px: int = x0 - ram.s32(c)
	var pz: int = z0 - ram.s32(c + 8)
	var len2: int = ex * ex + ez * ez
	var proj: int = -(ex * px + ez * pz)
	var d2: int
	if len2 == 0 or proj < 0:
		d2 = px * px + pz * pz
	else:
		var qx: int = x1 - ram.s32(c)
		if len2 < proj:
			var qz: int = z1 - ram.s32(c + 8)
			d2 = qx * qx + qz * qz
			return d2 <= ram.s32(c + 16)
		var fx: int = px + FMath.tdiv(ex * proj, len2)
		var fz: int = pz + FMath.tdiv(ez * proj, len2)
		d2 = fx * fx + fz * fz
	return d2 <= ram.s32(c + 16)
static func rnd(v: int) -> int:
	return (v + 0xfff if v < 0 else v) >> 12
static func find_hit(ram, a: int, d: int, out: int) -> bool:
	var list: int = ram.u32(ram.u32(a + 0x54) + 0x28)
	if ram.u8(list) >= 0x18:
		return false
	var count: int = mini(ram.u8(a + 0xe3), 4)
	var seg: int = a + 0x1ac
	for i in count:
		if ram.s16(d + 0x104) != 0:
			return false
		for k in 14:
			if seg_sphere(ram, seg, d + 0x20c + k * 0x14):
				ram.w16(out + 0x18, k)
				ram.w32(out, ram.u32(seg + 12))
				ram.w32(out + 4, ram.u32(seg + 16))
				ram.w32(out + 8, ram.u32(seg + 20))
				ram.w16(out + 0x10, ram.s16(seg + 12) - ram.s16(seg))
				ram.w16(out + 0x12, ram.s16(seg + 16) - ram.s16(seg + 4))
				ram.w16(out + 0x14, ram.s16(seg + 20) - ram.s16(seg + 8))
				return true
		seg += 0x18
	return false
static func reset_hits(ram, a: int) -> void:
	ram.w8(a + 0xd1, 0)
	ram.w8(a + 0xd2, 0)
	ram.w8(a + 0xce, 0)
	ram.w16(a + 0xee, 0)
	ram.w8(a + 0xe7, 0)
	for k in 2:
		var r: int = a + 0x13c + k * 0x2c
		ram.w16(r + 0x1c, 0)
		ram.w16(r + 0x1e, 0)
		for o in range(0x20, 0x29):
			ram.w8(r + o, 0)
static func detect(ram, a: int, b: int) -> void:
	var free := 0
	for k in 2:
		if ram.u8(b + 0x13c + k * 0x2c + 0x21) == 0:
			free = b + 0x13c + k * 0x2c
	var row_a: int = ram.u32(a + 0x54)
	var row_b: int = ram.u32(b + 0x54)
	var blocked := false
	if free != 0 and ram.u8(a + 0xc2) == 0 and ram.u8(b + 0xc2) == 0 and ram.u8(a + 0xc3) != 0 and ram.u8(b + 0xc3) != 0 and ram.u8(a + ram.u8(b + 0x1e) + 0x83) == 0:
		if ram.s16(a + 100) == 0x10f and ram.u8(b + 0x69) == 0xc:
			if (ram.u8(ram.u32(b + 0x54) + 0x19) <= ram.s16(b + 0x58) and ram.s16(b + 0x58) <= ram.u8(ram.u32(b + 0x54) + 0x1a) - 5) or ram.u8(b + 0xdb) != 0:
				blocked = true
		if not blocked and ((ram.u8(0x800afa88) != 7 and ram.u8(0x800afa88) != 8) or ram.u8(b + 0xc4) == 0):
			var level: int = ram.u16(a + 100)
			if ram.u8(b + 0xb6) == 2:
				level |= 1
			var landed: bool = find_hit(ram, a, b, free)
			if landed and (level & ram.u16(b + 0x60) & 7) != 0:
				ram.w8(a + ram.u8(b + 0x1e) + 0x83, 1)
				ram.w8(a + 0x88, 1)
				ram.w8(a + 0xd1, 1)
				ram.w8(a + 0x23, ram.u8(b + 0x1e))
				ram.w8(b + 0x87, 1)
				ram.w8(b + 0xce, 1)
				ram.w16(b + 0xee, ram.u8(row_a + 0x2c))
				ram.w8(free + 0x21, 1)
				impacts.append([ram.s32(free), ram.s32(free + 4), ram.s32(free + 8), b])
				ram.w8(free + 0x20, ram.u8(a + 0x1e))
				ram.w8(b + 0xe7, ram.u8(a + 0xe6))
				if ram.s16(a + 0xa0) == 0x898:
					ram.w16(b + 0xee, 0x1e)
				if ram.s16(a + 0x5e) != 0 or ram.u8(b + 0xdb) != 0:
					ram.w16(b + 0x104, 4)
	if ram.u8(row_a + 0x2e) == ram.u16(a + 0x58) and ram.u8(a + 0x88) == 0:
		ram.w8(a + 0xd2, 1)
