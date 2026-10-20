extends RefCounted
const FMath := preload("res://scripts/combat/fmath.gd")
const JOINTS := 0x8f4
const JOINT_SIZE := 0x44
const BODY_SLOTS := 0x80096fb8
const PUSH_SLOTS := 0x80096f40
const RADII_TABLES := 0x80096ff0
const MODE := 0x800a05a8
const PREV_BASE := 0x800a0578
const PREV_END_A := 0x800a0528
const PREV_END_B := 0x800a054c
const SIN_FACE := 0x800a05b8
const COS_FACE := 0x800a05bc
const SIN_TURN := 0x800a05c0
const COS_TURN := 0x800a05c4
const TURN := 0x800a05c8
const PIVOT := 0x800a05cc
static func set_radii(ram, a: int) -> void:
	var table: int = ram.u32(RADII_TABLES + ram.s16(a + 0x18) * 4)
	for k in 14:
		var r: int = ram.s16(table + k * 2)
		ram.w16(a + 0x218 + k * 0x14, r)
		ram.w32(a + 0x21c + k * 0x14, r * r)
static func joint_at(ram, a: int, slot: int) -> int:
	return a + slot * JOINT_SIZE + JOINTS
static func copy_joint(ram, a: int, slot: int, dest: int) -> void:
	var at: int = joint_at(ram, a, slot)
	ram.w32(dest, ram.u32(at + 0x14))
	ram.w32(dest + 4, ram.u32(at + 0x18))
	ram.w32(dest + 8, ram.u32(at + 0x1c))
static func body_spheres(ram, a: int) -> void:
	for k in 14:
		var slot: int = ram.s32(BODY_SLOTS + k * 4)
		var dest: int = a + 0x20c + k * 0x14
		copy_joint(ram, a, slot, dest)
		if k == 8:
			ram.w32(dest + 4, ram.s32(dest + 4) - 0x78)
		if k == 0xb:
			ram.w32(dest + 4, ram.s32(dest + 4) - 0x3c)
	for k in 8:
		var slot2: int = ram.s32(PUSH_SLOTS + k * 4)
		copy_joint(ram, a, slot2, a + 0x324 + k * 0x10)
	ram.w32(a + 0x3a4, ram.u32(a + 0x20c))
	ram.w32(a + 0x3a8, ram.u32(a + 0x210))
	ram.w32(a + 0x3ac, ram.u32(a + 0x214))
static func limb_segments(ram, a: int) -> void:
	var list: int = ram.u32(ram.u32(a + 0x54) + 0x28)
	var count: int = ram.u8(a + 0xb4)
	for k in count:
		var entry: int = a + 0x1ac + k * 0x18
		var first: int = ram.u8(list + k * 2)
		var second: int = ram.u8(list + k * 2 + 1)
		if first == 0x13 and ram.s16(a + 0x18) == 0xe:
			first = 6
		if first < 0x18:
			copy_joint(ram, a, first, entry + 0xc)
		if second != 0:
			if second == 0x13 and ram.s16(a + 0x18) == 0xe:
				second = 6
			if second < 0x18:
				copy_joint(ram, a, second, entry)
static func unpack(ram, ptr: int) -> Array:
	var v: int = ram.u32(ptr)
	var w: int = ram.u32(ptr + 1)
	return [(v & 0x1fff) - 0x1000, (v >> 13 & 0x1fff) - 0x1000, (w >> 18) - 0x2000, ptr + 5]
static func rnd(v: int) -> int:
	return (v + 0xfff if v < 0 else v) >> 12
static func place(ram, dest: int, vec: Array, base: Array) -> void:
	var bx: int = base[0]
	var bz: int = base[2]
	if ram.s32(TURN) != 0:
		var dx: int = ram.s32(PIVOT) - bx
		var dz: int = ram.s32(PIVOT + 8) - bz
		var u: int = dx * ram.s32(COS_TURN) - dz * ram.s32(SIN_TURN)
		var w: int = dx * ram.s32(SIN_TURN) + dz * ram.s32(COS_TURN)
		bx = ram.s32(PIVOT) - rnd(u)
		bz = ram.s32(PIVOT + 8) - rnd(w)
	var sn: int = ram.s32(SIN_FACE)
	var cs: int = ram.s32(COS_FACE)
	ram.w32(dest, bx + rnd(vec[0] * cs) - rnd(vec[2] * sn))
	ram.w32(dest + 4, base[1] + vec[1])
	ram.w32(dest + 8, bz + rnd(vec[0] * sn) + rnd(vec[2] * cs))
static func set_mode(ram, a: int) -> void:
	ram.w32(MODE + ram.u8(a + 0x1e) * 4, 1 if ((ram.u16(a + 0x18) - 0xe) & 0xffff) < 2 else 0)
static func end_frame(ram, a: int) -> void:
	var o: int = ram.u8(a + 0x1e) * 0xc
	for i in 3:
		ram.w32(PREV_BASE + o + i * 4, ram.u32(a + i * 4))
		ram.w32(PREV_END_A + o + i * 4, ram.u32(a + 0x1b8 + i * 4))
		ram.w32(PREV_END_B + o + i * 4, ram.u32(a + 0x1d0 + i * 4))
		ram.w32(a + 0x1ac + i * 4, ram.u32(a + 0x1b8 + i * 4))
		ram.w32(a + 0x1c4 + i * 4, ram.u32(a + 0x1d0 + i * 4))
static func trig_index(angle: int) -> int:
	var v: int = -angle
	if v < 0:
		v += 0xf
	return v >> 3 & 0x1ffe
static func copy3(ram, dest: int, src: int) -> void:
	for i in 3:
		ram.w32(dest + i * 4, ram.u32(src + i * 4))
static func window_segments(ram, a: int) -> void:
	var player: int = ram.u8(a + 0x1e)
	var row: int = ram.u32(a + 0x54)
	var data: int = ram.u32(row + 0x28)
	if ram.u8(a + 0xb4) == 0:
		return
	if ram.u8(data) > 0x17:
		return
	var turn: int = ram.s16(a + 0x2c) - ram.s16(a + 0xe)
	ram.w32(TURN, turn)
	if turn != 0:
		ram.w32(PIVOT, ram.s32(a + 0xf68))
		ram.w32(PIVOT + 4, ram.s32(a + 0xf6c))
		ram.w32(PIVOT + 8, ram.s32(a + 0xf70))
		var t: int = trig_index(turn)
		ram.w32(SIN_TURN, ram.s16(FMath.SIN_TABLE + t))
		ram.w32(COS_TURN, ram.s16(FMath.COS_TABLE + t))
	var f: int = trig_index(ram.s16(a + 0x2c))
	ram.w32(SIN_FACE, ram.s16(FMath.SIN_TABLE + f))
	ram.w32(COS_FACE, ram.s16(FMath.COS_TABLE + f))
	var word: int = ram.u8(data + 4) << 8 | ram.u8(data + 5)
	var mode: int = ram.s32(MODE + player * 4)
	var extra := 0
	if mode == 1:
		extra = (word & 0x7fff) >> 4
	elif mode == 2:
		if (ram.u8(data + 4) & 0x80) != 0:
			extra = (word & 0x7ffe) >> 3
	elif mode != 0:
		return
	var type: int = word & 0xf
	var since: int = ram.s16(a + 0x58) - ram.u8(row + 0x2d)
	var skip: int
	match type:
		0:
			skip = since * 10
		1:
			skip = since * 5 + 5
		2:
			skip = since * 10 + 10
		3, 4:
			skip = since * 0xf + 5
		5:
			skip = since * 0x14
		6, 7, 9:
			skip = since * 10 + 5
		10, 12, 14:
			skip = since * 0xf
		13:
			skip = since * 0xf
		_:
			return
	var ptr: int = data + skip + extra + 6
	var cur: Array = [ram.s32(a), ram.s32(a + 4), ram.s32(a + 8)]
	var o: int = player * 0xc
	var prev: Array = [ram.s32(PREV_BASE + o), ram.s32(PREV_BASE + o + 4), ram.s32(PREV_BASE + o + 8)]
	var seg0: int = a + 0x1ac
	var seg0b: int = a + 0x1b8
	var seg1: int = a + 0x1c4
	var seg1b: int = a + 0x1d0
	var iv: int
	match type:
		0, 3, 5, 8, 9, 10, 0xb, 0xc, 0xd, 0xe:
			var u: Array = unpack(ram, ptr)
			place(ram, seg0, u, cur)
			var w: Array = unpack(ram, u[3])
			place(ram, seg0b, w, cur)
			iv = w[3]
		1, 4, 6, 7, 2:
			if since != 0:
				copy3(ram, seg0, PREV_END_A + o)
			else:
				place(ram, seg0, unpack(ram, ptr - (10 if type == 2 else 5)), prev)
			var w2: Array = unpack(ram, ptr)
			place(ram, seg0b, w2, cur)
			iv = w2[3]
		_:
			return
	match type:
		2, 3:
			if since == 0:
				place(ram, seg1, unpack(ram, iv - (10 if type == 2 else 0xf)), prev)
			else:
				copy3(ram, seg1, PREV_END_B + o)
			place(ram, seg1b, unpack(ram, iv), cur)
		4, 5:
			var u5: Array = unpack(ram, iv)
			place(ram, seg1, u5, cur)
			place(ram, seg1b, unpack(ram, u5[3]), cur)
		6, 10:
			place(ram, seg1, unpack(ram, iv), cur)
			copy3(ram, seg1b, seg0b)
		7, 0xb:
			copy3(ram, seg1, seg0b)
			place(ram, seg1b, unpack(ram, iv), cur)
		9:
			if since == 0:
				place(ram, seg1, unpack(ram, iv - 5), prev)
			else:
				copy3(ram, seg1, PREV_END_B + o)
			copy3(ram, seg1b, seg0)
		0xc:
			place(ram, seg1, unpack(ram, iv), cur)
			copy3(ram, seg1b, seg0)
		0xd:
			copy3(ram, seg1, seg0)
			place(ram, seg1b, unpack(ram, iv), cur)
		0xe:
			place(ram, seg1b, unpack(ram, iv), cur)
			copy3(ram, seg1, seg1b)
