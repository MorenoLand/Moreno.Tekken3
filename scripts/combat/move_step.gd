extends RefCounted
const FMath := preload("res://scripts/combat/fmath.gd")
const Pad := preload("res://scripts/combat/pad.gd")
const Commands := preload("res://scripts/combat/commands.gd")
const PLAYER_BASE := 0x800a9228
const PLAYER_SIZE := 0x188c
const DISTANCES := 0x8009e660
const REACTION_IDS_A := 0x8001075c
const REACTION_IDS_B := 0x8001075e
const REACTION_IDS_C := 0x80019d2c
const RISE_TABLE := 0x8001a630
static func slot_row(ram, a: int, id: int) -> int:
	var data: int = ram.u32(0x800adc20 + ram.s16(a + 0x12) * 4)
	return ram.u32(ram.u32(data + 0xc) + ((id << 16) >> 14))
static func distance_entry(ram, p: int, q: int) -> int:
	if p > 1:
		p = 1 << (p - 1)
	if q > 1:
		q = 1 << (q - 1)
	return DISTANCES + (p + q) * 0x10
static func opponent(ram, a: int) -> int:
	var uses: int
	if ram.u8(a + 0xc4) == 0:
		if ram.u8(a + 0x87) == 0:
			uses = ram.u8(a + 0x20) if ram.u8(a + 0xd1) == 0 else ram.u8(a + 0x23)
		else:
			uses = ram.u8(a + 0x22)
	else:
		uses = ram.u8(a + 0x21)
	return PLAYER_BASE + uses * 0x1000 + uses * 0x88c
static func face_opponent(ram, a: int, b: int) -> void:
	var back: int
	var diff: int
	if ram.u8(a + 199) == 0:
		var to_opp: int = FMath.atan2(ram, ram.s32(b + 0xf70) - ram.s32(a + 0xf70), ram.s32(b + 0xf68) - ram.s32(a + 0xf68))
		ram.w16(a + 0x2a, to_opp)
		back = FMath.s16(to_opp - 0x8000)
		ram.w16(a + 0x38, back)
		var b_face: int = ram.s16(b + 0x2c)
		ram.w16(a + 0x3a, b_face)
		diff = FMath.s16(b_face - back)
	else:
		var s: int = 0x4000 if ram.u8(a + 200) == 0 else -0x4000
		back = FMath.s16(s - 0x8000)
		ram.w16(a + 0x38, back)
		ram.w16(a + 0x3a, back)
		diff = 0
		ram.w16(a + 0x2a, s)
	ram.w16(a + 0x3c, diff)
	var d1: int = FMath.s16(ram.s16(a + 0x2c) - ram.s16(a + 0x2a))
	var u1: int = (d1 + 0x2000) & 0xffff
	ram.w16(a + 0x2e, d1)
	if u1 < 0x4000:
		ram.w16(a + 0x32, 0)
	else:
		ram.w16(a + 0x32, 1 if u1 < 0x8000 else (2 if u1 < 0xc000 else 3))
	var d2: int = FMath.s16(ram.s16(a + 0x3a) - ram.s16(a + 0x38))
	var u2: int = (d2 + 0x2000) & 0xffff
	ram.w16(a + 0x3c, d2)
	if u2 < 0x4000:
		ram.w16(a + 0x40, 0)
	else:
		ram.w16(a + 0x40, 1 if u2 < 0x8000 else (2 if u2 < 0xc000 else 3))
	var f: int = ram.u16(a + 0x2e)
	ram.w16(a + 0x30, f if (f & 0x8000) == 0 else ~f)
	var g: int = ram.u16(a + 0x3c)
	ram.w16(a + 0x3e, g if (g & 0x8000) == 0 else ~g)
	if ram.u32(a + 0xf8) > 0x200:
		if ram.u16(a + 0x30) < 0x4000:
			ram.w16(a + 0x34, ram.s16(a + 0x2a))
		else:
			ram.w16(a + 0x34, ram.s16(a + 0x2a) - 0x8000)
		if ram.u16(a + 0x3e) < 0x4000:
			ram.w16(a + 0x42, ram.s16(a + 0x38))
		else:
			ram.w16(a + 0x42, ram.s16(a + 0x38) - 0x8000)
static func frame_hold_done(ram, a: int) -> bool:
	var row: int = ram.u32(a + 0x54)
	var f: int = ram.s16(a + 0x58)
	var next: int = ram.u32(a + 0x1a4)
	if next == 0:
		return false
	var step: int = ram.s16(a + 0x6e)
	if step < 1:
		if step < 0:
			return f <= ram.s16(a + 0x198) or f < 1
		return true
	if f < ram.s16(a + 0x198):
		return ram.u8(row + 0x18) <= f
	return true
static func advance(ram, a: int) -> void:
	var row: int = ram.u32(a + 0x54)
	var hold: int = ram.s16(a + 0x76)
	ram.w16(a + 0x5c, ram.s16(a + 0x5c) + 1)
	ram.w8(a + 0xda, 0)
	if ram.s16(a + 0x76) > 0:
		ram.w16(a + 0x76, hold - 1)
		if hold != 1:
			return
		var f: int = ram.s16(a + 0x58)
		ram.w16(a + 0x76, 0)
		ram.w16(a + 0x58, f + 1)
		ram.w16(a + 0x50, f + 1)
		ram.w32(a + 0x4c, row)
		return
	var jump: int = ram.s16(a + 0x6a)
	if jump < 0:
		if ram.s16(a + 0x92) == 0:
			var nf: int = FMath.s16(ram.s16(a + 0x58) + ram.s16(a + 0x6e))
			ram.w16(a + 0x58, nf)
			if nf < 1:
				ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, ram.s16(a + 0x58))
			return
		var f2: int = ram.s16(a + 0x58)
		if f2 == ram.u8(row + 0x1b):
			return
		ram.w16(a + 0x58, f2 + 1)
		ram.w16(a + 0x50, f2 + 1)
		return
	var f3: int = ram.s16(a + 0x58)
	var alt: int
	if f3 == ram.u8(row + 0x1b):
		if jump < 1:
			if jump != 0:
				return
			ram.w16(a + 0x58, f3 + 1)
			ram.w16(a + 0x50, f3 + 1)
			ram.w32(a + 0x4c, row)
			return
		alt = ram.s16(a + 0x50)
		ram.w16(a + 0x6a, jump - 1)
	else:
		alt = ram.s16(a + 0x50)
		ram.w16(a + 0x58, f3 + 1)
	ram.w16(a + 0x50, alt + 1)
static func hold_ok(ram, a: int) -> bool:
	if ram.u8(a + 0x8b) == 3:
		return false
	var nx: int = ram.u32(a + 0x1a4)
	var k: int = ram.u8(nx + 0x2d)
	if k == 0:
		return true
	return k <= ram.u8(nx + 0x18) and ram.s16(a + 0x58) <= ram.u8(nx + 0x2e)
static func restart_or_step(ram, a: int, nx: int) -> void:
	if not hold_ok(ram, a):
		ram.w16(a + 0x58, 1)
		ram.w16(a + 0x50, 1)
	else:
		ram.w16(a + 0x58, ram.s16(a + 0x58) + 1)
		ram.w16(a + 0x50, ram.s16(a + 0x50) + 1)
	if ram.u8(nx + 0x18) < ram.s16(a + 0x58):
		ram.w16(a + 0x58, ram.u8(nx + 0x18))
		ram.w16(a + 0x50, ram.u8(nx + 0x18))
static func combo_cancel(ram, a: int) -> void:
	if ram.s32(a + 0x410) >= 0:
		ram.w32(a + 0x410, 0xffffffff)
		ram.w32(a + 0x414, 0xffffffff)
		ram.w32(a + 0x418, 0xffffffff)
static func combo_start(ram, a: int) -> void:
	if ram.s32(a + 0x410) < 0:
		ram.w32(a + 0x410, 0)
		ram.w32(a + 0x414, 0)
		ram.w32(a + 0x418, 0)
static func combo_age(ram, a: int) -> void:
	if ram.s32(a + 0x414) < ram.s32(a + 0x410):
		ram.w32(a + 0x414, ram.s32(a + 0x414) + 1)
static func begin_common(ram, a: int, b: int) -> int:
	var nx: int = ram.u32(a + 0x1a4)
	var row: int = ram.u32(a + 0x54)
	if ram.u8(a + 0x8b) == 3:
		ram.w16(a + 0x198, 1)
	ram.w16(a + 0x134, ram.s16(a + 0x58))
	ram.w16(a + 0x136, ram.u16(a + 0xa0))
	ram.w16(a + 0x138, ram.u16(nx + 0x10))
	if ram.u8(a + 0x8b) == 3:
		ram.w16(a + 0x198, 1)
	ram.w8(a + 0x86, 0)
	ram.w8(a + 0xb8, 0)
	ram.w8(a + 0x82, 0)
	ram.w8(a + 0xb9, 0)
	ram.w16(a + 0x6a, 0xffff)
	ram.w32(a + 0xac, ram.u32(b + 0xf68))
	var bz: int = ram.u32(b + 0xf70)
	ram.w16(a + 0x6e, 1)
	ram.w16(a + 0x36, 0)
	ram.w8(a + 0xb6, 0)
	ram.w8(a + 0x8c, 0)
	ram.w8(a + 0xbc, 0)
	ram.w8(a + 0xba, 0)
	ram.w16(a + 0x76, 0)
	ram.w8(a + 0x83, 0)
	ram.w8(a + 0x84, 0)
	ram.w8(a + 0x85, 0)
	ram.w16(a + 0x104, 0)
	ram.w32(a + 0xb0, bz)
	if ram.s16(a + 0xea) == 0:
		var v: int = ram.u16(nx + 0x14)
		ram.w16(a + 0x5e, v)
		ram.w8(a + 0xb7, v >> 14)
		ram.w16(a + 0x5e, v & 0x3fff)
		if ram.u8(a + 0xb7) == 1:
			ram.w16(a + 0x5e, 0)
	else:
		ram.w16(a + 0x5e, ram.s16(a + 0xea))
	ram.w32(a + 0x60, ram.u32(nx + 4))
	ram.w16(a + 0x64, ram.u16(nx + 8))
	ram.w16(a + 0x66, ram.u16(a + 0x60) & 0x18)
	ram.w8(a + 0x69, ram.u32(a + 0x60) >> 11 & 0x1f)
	ram.w8(a + 0x68, ram.u16(a + 0x64) >> 8)
	ram.w8(a + 0xca, 1 if ram.u8(a + 0xc5) == 0 else 0)
	if (ram.u32(a + 0x60) & 0x100) != 0 and ram.u8(a + 0xca) == 0:
		ram.w32(a + 0x60, ram.u32(a + 0x60) & 0xffffffe7)
		ram.w16(a + 0x66, ram.u16(a + 0x66) & 0xffe7)
	if (ram.u32(nx + 0x24) >> 8 & 0x20) == 0:
		ram.w8(a + 0xb5, 0)
		combo_cancel(ram, a)
	else:
		ram.w8(a + 0xb5, 1)
		combo_start(ram, a)
	combo_age(ram, a)
	ram.w8(a + 0x89, 0 if ram.u8(a + 0xcf) == 0 else 1)
	if ram.u8(a + 0xce) == 0:
		ram.w8(a + 0x87, 0)
		ram.w16(a + 0x92, 0)
		ram.w16(a + 0x94, 0)
	if ram.u8(a + 0xd1) == 0:
		ram.w8(a + 0x88, 0)
	var bump := false
	if ram.u8(a + 0xd0) != 0 or ((ram.u32(row + 0x24) >> 8 & 0x400) != 0 and (ram.u32(nx + 0x24) >> 8 & 0x400) != 0) or (ram.s16(a + 0x74) < 0 and (ram.u32(nx + 0x24) >> 8 & 0x400) != 0):
		bump = true
		ram.w16(a + 0x80, ram.s16(a + 0x80) + 1)
	elif ram.u8(a + 0x8a) == 0 and ram.s16(a + 0x74) >= 0:
		ram.w16(a + 0x80, 0)
	elif ram.u16(a + 0x19a) - 0x1a > 1:
		var kind: int = ram.u16(a + 0x19a)
		var id: int = ram.s16(a + 0x1a0)
		if kind == 0x22 or id == 0xcc6:
			ram.w16(a + 0x80, ram.s16(a + 0x80) + 1)
		elif id != 0x9a6:
			ram.w16(a + 0x80, 0)
	ram.w8(a + 0x8a, ram.u8(a + 0xd0))
	if ram.u8(a + 0xce) != 0 and ram.u32(a + 0x3f4) != 0:
		ram.w16(a + 0x76, ram.u16(a + 0xee))
	if ram.u8(a + 0x8b) == 3 or ram.u8(a + 0x8b) == 1 or ram.u32(nx) != ram.u32(row):
		ram.w8(a + 0xda, 1)
	var copy: int = ram.u32(row + 0x24) >> 0x1c & 1
	if (ram.u32(row + 0x24) >> 8 & 0x100) != 0:
		ram.w16(a + 0x122, 0x78)
	if (ram.u32(nx + 0x24) >> 8 & 8) != 0:
		ram.w16(a + 0x11c, 9)
	if ram.s16(a + 0x19c) != 0:
		ram.w16(a + 0x19c, 0)
		ram.w16(a + 0x2c, ram.s16(a + 0x2c) - 0x8000)
		ram.w16(a + 0x0e, ram.s16(a + 0x0e) - 0x8000)
	if ram.u8(a + 0xc1) != 0 and ram.u16(a + 0x19a) != 0x22:
		var s: int = ram.s16(a + 0x2c) + ram.s16(row + 0x12)
		ram.w16(a + 0x2c, s)
		ram.w16(a + 0x0e, s)
	face_opponent(ram, a, b)
	return copy
static func approach_rate(ram, a: int, target: int) -> void:
	var span: int = FMath.s16(target - ram.u16(a + 0x2c))
	ram.w16(a + 0x116, FMath.tdiv(span, ram.s16(a + 0x114)))
static func set_approach_frames(ram, nx: int, a: int) -> void:
	var n: int = ram.u8(nx + 0x2d) - 1
	ram.w16(a + 0x114, n)
	if n < 1:
		ram.w16(a + 0x114, 1)
static func copy_position(ram, a: int) -> void:
	ram.w32(a + 0, ram.u32(a + 0xf68))
	ram.w32(a + 8, ram.u32(a + 0xf70))
static func finish(ram, a: int) -> void:
	var nx: int = ram.u32(a + 0x1a4)
	var id: int = ram.u16(a + 0x1a0)
	ram.w32(a + 0x1a4, 0)
	ram.w32(a + 0x54, nx)
	ram.w16(a + 0x1a0, 0xffff)
	ram.w16(a + 0xa0, id)
	var kind_b := 0
	if ram.u8(nx + 0x2d) != 0:
		var flags: int = ram.u32(nx + 0x28)
		if ram.u8(flags + 2) != 0:
			kind_b = 2
		elif ram.u8(flags) != 0:
			kind_b = 1
	ram.w8(a + 0xb4, kind_b)
	ram.w16(a + 0x5c, 1 if ram.u8(a + 0xda) != 0 else ram.u16(a + 0x58))
	var kind: int = ram.u16(a + 0x19a)
	ram.w16(a + 0x19a, 0)
	ram.w16(a + 0x19c, 0)
	ram.w16(a + 0x19e, 0)
	ram.w8(a + 0xc1, 0)
	ram.w16(a + 0xa2, kind)
	ram.w8(a + 0xc4, 1 if ram.s16(a + 0x74) != 0 else 0)
	if ram.s16(a + 0x16) == 0x13 and ram.s16(a + 0x58) == 1 and ram.u8(ram.u32(a + 0x54) + 0x19) != 1:
		ram.w32(a + 4, 0)
static func apply_kind(ram, a: int, b: int, copy: int) -> void:
	var nx: int = ram.u32(a + 0x1a4)
	var kind: int = ram.u16(a + 0x19a)
	var skip_copy := false
	match kind:
		0:
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w16(a + 0x74, 0)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x2c, ram.s16(a + 0x2a))
			ram.w16(a + 0x0e, ram.s16(a + 0x2a))
			copy_position(ram, a)
			skip_copy = true
		1, 2, 3:
			if kind == 1:
				ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			restart_or_step(ram, a, nx)
			ram.w8(a + 0xb9, 0xb)
			ram.w16(a + 0x74, 0)
			ram.w8(a + 0xbe, 1)
			ram.w32(a + 0x4c, nx)
			copy_position(ram, a)
			skip_copy = true
		4:
			var f: int = ram.s16(a + 0x50)
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, f + 1)
			var prev: int = ram.u32(a + 0x4c)
			if ram.u8(prev + 0x18) < FMath.s16(f + 1):
				ram.w16(a + 0x50, ram.u8(prev + 0x18))
			ram.w8(a + 0xb9, 0xb)
			ram.w16(a + 0x6a, ram.u16(a + 0x6c))
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			if ram.s16(a + 0x30) < 0x4fa5:
				set_approach_frames(ram, nx, a)
				approach_rate(ram, a, ram.u16(a + 0x2a))
			ram.w16(a + 0x74, 0)
			skip_copy = true
		5:
			var f5: int = ram.s16(a + 0x50)
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, f5 + 1)
			var prev5: int = ram.u32(a + 0x4c)
			if ram.u8(prev5 + 0x18) < FMath.s16(f5 + 1):
				ram.w16(a + 0x50, ram.u8(prev5 + 0x18))
			ram.w16(a + 0x6a, ram.u16(a + 0x6c))
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			ram.w8(a + 0xb9, 4 if ram.s16(a + 0x30) < 0x4fa4 else 6)
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
			ram.w16(a + 0x74, 0)
			skip_copy = true
		6:
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			if copy != 0:
				copy_position(ram, a)
			ram.w16(a + 0x74, 0)
			skip_copy = true
		7:
			var n7: int = ram.u8(nx + 0x18)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			ram.w16(a + 0x58, n7)
			ram.w16(a + 0x50, n7)
			if copy != 0:
				copy_position(ram, a)
			ram.w16(a + 0x6e, 0xffff)
			ram.w16(a + 0x74, 0)
			skip_copy = true
		8:
			var f8: int = ram.s16(a + 0x58)
			ram.w16(a + 0x58, f8 - 1)
			if FMath.s16(f8 - 1) < 1:
				ram.w16(a + 0x58, 1)
			ram.w16(a + 0x6e, 0xffff)
			ram.w8(a + 0xbe, 1)
			ram.w16(a + 0x74, 0)
			ram.w16(a + 0x50, ram.s16(a + 0x58))
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			copy_position(ram, a)
			skip_copy = true
		9:
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w8(a + 0xb9, 5)
			ram.w16(a + 0x74, 0)
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x0e, ram.s16(a + 0x34))
		10, 0xb:
			ram.w16(a + 0x0e, ram.s16(a + 0x2c) if kind == 10 else ram.s16(a + 0x34))
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w32(a + 0x4c, nx)
			var row: int = ram.u32(a + 0x54)
			var n: int
			if ram.u8(nx + 0x2d) == 0:
				n = 0x10
				if ram.u8(row + 0x18) < 0x10:
					n = ram.u8(row + 0x18)
			else:
				n = ram.u8(nx + 0x2d) - 1
			ram.w16(a + 0x114, n)
			if ram.s16(a + 0x114) < 1:
				ram.w16(a + 0x114, 1)
			if ram.u16(a + 0x30) < 0x4000:
				ram.w16(a + 0x34, ram.s16(a + 0x2a))
			else:
				ram.w16(a + 0x34, ram.s16(a + 0x2a) - 0x8000)
			approach_rate(ram, a, ram.u16(a + 0x34))
			if copy != 0:
				copy_position(ram, a)
			ram.w8(a + 0xb9, 0xb)
			ram.w16(a + 0x74, 0)
			skip_copy = true
		0xc, 0xd, 0xe:
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w32(a + 0x4c, nx)
			var low: bool = ram.s16(a + 0x30) < 0x4fa4
			ram.w8(a + 0xb9, ([4, 3, 2][kind - 0xc]) if low else 6)
			ram.w16(a + 0x0e, ram.s16(a + 0x2a) if low else ram.s16(a + 0x34))
			ram.w16(a + 0x74, 0)
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
		0xf:
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w8(a + 0xb9, 1)
			ram.w16(a + 0x74, 0)
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x0e, ram.s16(a + 0x34))
		0x10:
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w8(a + 0xb9, 0xb)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x0e, ram.s16(a + 0x2a))
			set_approach_frames(ram, nx, a)
			ram.w16(a + 0x74, 0)
			ram.w8(a + 0x82, 1)
			ram.w32(a + 0x78, 0)
			ram.w32(a + 0x7c, 0)
			approach_rate(ram, a, ram.u16(a + 0x2a))
		0x11:
			skip_copy = true
		0x12, 0x13:
			restart_or_step(ram, a, nx)
			ram.w8(a + 0x82, 1)
			ram.w16(a + 0x74, 0)
			ram.w32(a + 0x78, 0)
			ram.w32(a + 0x7c, 0)
			ram.w8(a + 0xb9, 0xb)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x0e, ram.s16(a + 0x2a))
			if kind == 0x13:
				ram.w16(a + 0x2c, ram.s16(a + 0x2c) - 0x8000)
			set_approach_frames(ram, nx, a)
			approach_rate(ram, a, ram.u16(a + 0x2a))
		0x14, 0x15:
			restart_or_step(ram, a, nx)
			ram.w32(a + 0x4c, nx)
			var far: bool = ram.s16(a + 0x30) >= 0x4fa4
			ram.w8(a + 0xb9, 6 if far else (4 if kind == 0x14 else 2))
			ram.w16(a + 0x74, 0)
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
			ram.w8(a + 0xbe, 1)
			copy_position(ram, a)
			skip_copy = true
		0x16, 0x19:
			if kind == 0x19:
				ram.w16(a + 0x74, 0)
			restart_or_step(ram, a, nx)
			ram.w8(a + 0xb9, 8)
			if kind == 0x16:
				ram.w16(a + 0x74, 0)
				ram.w16(a + 0x114, 0)
				ram.w16(a + 0x116, 0)
			ram.w8(a + 0xbe, 1)
			ram.w32(a + 0x4c, nx)
			copy_position(ram, a)
			skip_copy = true
		0x17:
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			if copy != 0:
				copy_position(ram, a)
			ram.w8(a + 0xb9, 9)
			ram.w16(a + 0x74, 0)
			skip_copy = true
		0x18:
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w16(a + 0x74, 0)
			ram.w8(a + 0xb9, 8)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x0e, ram.s16(a + 0x34))
		0x1a, 0x1b:
			ram.w16(a + 0x58, ram.s16(a + 0x58) + 1)
			ram.w16(a + 0x50, ram.s16(a + 0x50) + 1)
			if ram.u8(nx + 0x18) < ram.s16(a + 0x58):
				ram.w16(a + 0x58, ram.u8(nx + 0x18))
				ram.w16(a + 0x50, ram.u8(nx + 0x18))
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			ram.w8(a + 0xb6, 1 if kind == 0x1a else 2)
			skip_copy = true
		0x1c:
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w8(a + 0xb9, 10)
			ram.w16(a + 0x74, 0)
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			ram.w32(a + 0x4c, nx)
			if copy != 0:
				copy_position(ram, a)
			ram.w16(a + 0x128, 0x18)
			skip_copy = true
		0x1d:
			restart_or_step(ram, a, nx)
			ram.w8(a + 0xb9, 10)
			ram.w16(a + 0x74, 0)
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			ram.w32(a + 0x4c, nx)
		_:
			var handled: int = apply_reaction(ram, a, b, copy)
			if handled == 2:
				skip_copy = true
			elif handled == 0:
				ram.w16(a + 0x58, 1)
				ram.w16(a + 0x50, 1)
				ram.w32(a + 0x4c, nx)
				ram.w16(a + 0x0e, ram.s16(a + 0x2a))
				ram.w16(a + 0x2c, ram.s16(a + 0x2a))
	if not skip_copy and copy != 0:
		copy_position(ram, a)
static func juggle_counter(ram, a: int) -> void:
	var kind: int = ram.u16(a + 0x19a)
	if ((kind - 0x27) & 0xffff) < 2 or kind == 0x2b:
		if ram.s16(a + 0x126) == 0:
			ram.w16(a + 0x124, 0)
		elif ram.u16(a + 0x13a) == kind:
			ram.w16(a + 0x124, ram.s16(a + 0x124) + 1)
		ram.w16(a + 0x13a, ram.u16(a + 0x19a))
		ram.w16(a + 0x126, ram.u8(ram.u32(a + 0x1a4) + 0x18) + 10)
static func rise_physics(ram, a: int) -> void:
	ram.w16(a + 0x198, 1)
	var hold: int = ram.u8(ram.u32(a + 0x1a4) + 0x1b)
	if hold == 0:
		hold = ram.u8(ram.u32(a + 0x54) + 0x18)
	var height: int = ram.s32(a + 0xf6c)
	var drop: int = ram.s16(a + 0x96)
	var power: int = ram.s16(a + 0xe8) + (ram.s16(a + 0x94) + 1) * 7 + 10
	if ram.s16(a + 0x90) == 5:
		power += 10
	ram.w16(a + 0x98, 100 if power > 100 else (0 if power < 0 else power))
	var lift: int = (ram.s16(a + 0xe8) * 4 - ((ram.s32(a + 0x3c8) + ram.s32(a + 0x3e0)) >> 3)) - (ram.s16(a + 0x94) * 7 - 0x28)
	var v: int = mini(lift, 100)
	var sq: int = v * v
	if lift < -100:
		v = -100
		sq = 10000
	ram.w16(a + 0x9c, -v)
	sq += (drop + height) * 0xc
	if sq < 0:
		sq = -sq
	var root: int = FMath.isqrt(sq)
	var u: int = ((v + root) & 0xffffffff) / 6
	var neg: int = -u
	if u == 0:
		u = 1
		neg = -1
	var rest: int = hold + neg + 1
	if rest < 1:
		rest = 1
	var start: int
	if (ram.u32(a + 0x60) & 4) == 0 and rest != 1:
		u = (u - 1) + rest
		start = 1
	elif ram.s16(a + 0x94) == 0:
		u += 10
		start = hold - u + 1
		if start < 1:
			start = 1
	else:
		start = rest
		if ram.u32(ram.u32(a + 0x54)) == ram.u32(ram.u32(a + 0x1a4)):
			var diff: int = ram.s16(a + 0x58) - rest
			if diff < 0:
				diff = rest - ram.s16(a + 0x58)
			if diff < 10:
				start = ram.s16(a + 0x58) - 10
				var back: int = -start
				if start < 1:
					start = 1
					back = -1
				u = u + rest + back
	var steps: int = u + 1
	var area: int = steps * steps * 6 >> 1
	if (v * steps - area) - height < drop:
		ram.w16(a + 0x9c, -FMath.tdiv(drop + height + area, steps))
	ram.w32(a + 0x110, 0x80019d2c)
	ram.w16(a + 0x10a, 8)
	ram.w16(a + 0x198, start)
	ram.w16(a + 0x10c, ram.s16(a + 0x2a) - 0x8000)
	if ram.s16(a + 0x90) == 1:
		ram.w16(a + 0x9c, 400)
		ram.w16(a + 0x198, 6)
		var n: int = ram.u8(ram.u32(a + 0x1a4) + 0x18) - 6
		ram.w16(a + 0x106, n)
		if n < 0:
			ram.w16(a + 0x106, 0)
		ram.w16(a + 0x108, 0x28)
		ram.w16(a + 0x10c, ram.s16(a + 0x2a) - 0x8000)
	ram.w32(0x80095770 + ram.u8(a + 0x1e) * 4, steps)
static func stun_blend(ram, a: int, row: int) -> void:
	var v := 0
	if (ram.u32(row + 0x24) >> 8 & 0x10) == 0:
		var h: int = ram.s16(a + 0x118)
		v = ram.s16(a + 0xe8) + ((h - (h >> 31)) >> 1)
	if v > 0x41:
		v = 0x42
	ram.w16(a + 0x118, v)
	ram.w16(a + 0x11a, ram.u8(ram.u32(a + 0x1a4) + 0x18))
static func slide_setup(ram, a: int, id: int) -> void:
	var o: int = id * 2
	ram.w16(a + 0x106, ram.s16(REACTION_IDS_A + o))
	ram.w16(a + 0x108, ram.s16(REACTION_IDS_B + o))
	ram.w32(a + 0x110, REACTION_IDS_B + o + 2)
	ram.w16(a + 0x10a, 8)
static func apply_reaction(ram, a: int, b: int, copy: int) -> int:
	var nx: int = ram.u32(a + 0x1a4)
	var row: int = ram.u32(a + 0x54)
	var kind: int = ram.u16(a + 0x19a)
	var table: int = ram.u32(a + 0x1a8)
	match kind:
		0x1e, 0x24:
			if kind == 0x1e:
				ram.w16(a + 0x90, 5)
				ram.w16(a + 0x1a0, ram.s16(RISE_TABLE + 2 + 5 * 4))
				ram.w16(a + 0x8e, 1)
				ram.w16(a + 0x96, ram.s16(RISE_TABLE + 5 * 4))
			elif ram.s16(a + 0x94) == 0:
				ram.w16(a + 0x9a, 0)
				ram.w16(a + 0x9c, 0)
				ram.w16(a + 0x9e, 0)
			ram.w32(a + 4, ram.u32(a + 0xf6c))
			rise_physics(ram, a)
			ram.w16(a + 0x58, ram.s16(a + 0x198))
			ram.w16(a + 0x50, ram.s16(a + 0x198))
			ram.w8(a + 0xb8, 1)
			ram.w16(a + 0x92, 1)
			ram.w16(a + 0x74, 0)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x94, ram.s16(a + 0x94) + 1)
			stun_blend(ram, a, row)
			ram.w8(a + 0xb9, 0xb)
			if (ram.u32(row + 0x24) >> 8 & 0x10) == 0:
				ram.w16(a + 0x0e, ram.s16(a + 0x34))
			else:
				ram.w16(a + 0x0e, ram.s16(a + 0x34) + ram.s16(table + 0x1c))
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
			return 1
		0x21:
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w32(a + 0x4c, nx)
			if ram.s16(a + 0x74) == 0:
				var s5: int = ram.s16(a + 0x2a)
				var q: int = ram.s16(a + 0x40)
				ram.w16(a + 0x2c, s5 - 0x8000)
				if q == 1:
					ram.w16(a + 0x2c, s5 - 0x4000)
				elif q == 2:
					ram.w16(a + 0x2c, s5)
				elif q == 3:
					ram.w16(a + 0x2c, s5 + 0x4000)
				ram.w16(a + 0x114, 0x10)
				ram.w16(a + 0x0e, ram.u16(a + 0x2c))
				ram.w16(a + 0x116, FMath.tdiv(FMath.s16(ram.u16(b + 0x2c) - ram.u16(a + 0x2c)), 0x10))
				ram.w32(a, ram.u32(b + 0xf68))
				ram.w32(a + 8, ram.u32(b + 0xf70))
			elif ram.s16(a + 0x74) < 0 or (ram.u32(nx + 0x24) >> 8 & 0x800) != 0:
				ram.w16(a + 0x2c, ram.u16(b + 0x0e))
				ram.w16(a + 0x0e, ram.u16(b + 0x0e))
				ram.w32(a, ram.u32(b + 0xf68))
				ram.w32(a + 8, ram.u32(b + 0xf70))
			ram.w16(a + 0x106, 0)
			ram.w16(a + 0x108, 0)
			ram.w16(a + 0x10a, 0)
			ram.w16(a + 0x74, 1 if ram.s16(a + 0x74) < 0 else ram.s16(a + 0x74) + 1)
			return 2
		0x22:
			if ram.s16(a + 0x74) >= 0:
				if (ram.s16(row + 0x14) == 0 or ram.u8(row + 0x2d) <= ram.s16(a + 0x58)) and ram.s16(b + 0x122) == 0:
					ram.w8(a + 0xbd, 0)
				else:
					ram.w8(a + 0xbd, 1)
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w8(a + 0x86, 1)
			ram.w32(a + 0x4c, nx)
			if ram.s16(a + 0x74) < 0:
				if (ram.u32(nx + 0x24) >> 8 & 0x800) != 0:
					ram.w16(a + 0x0e, ram.s16(a + 0x2c))
					copy_position(ram, a)
			else:
				var f: int = ram.s16(a + 0x2c)
				ram.w16(a + 0x2c, f - 0x8000)
				ram.w16(a + 0x0e, f - 0x8000)
				copy_position(ram, a)
				ram.w16(a + 0x70, 0xffff)
				ram.w16(a + 0x72, 0)
				ram.w16(a + 0x11e, 0)
				ram.w16(a + 0x120, 0)
			ram.w16(a + 0x74, -1 if ram.s16(a + 0x74) >= 1 else ram.s16(a + 0x74) - 1)
			var br: int = ram.u32(b + 0x1a4)
			if ram.u8(br + 0x1b) == 0:
				var d: int = ram.u8(br + 0x18) - ram.u8(nx + 0x18)
				var v: int = ram.u8(br + 0x18) if d < 1 else ram.u8(nx + 0x18) + d
				v = FMath.s16(v)
				ram.w16(a + 0x11a, 0 if v < 0 else mini(v, 300))
			else:
				ram.w16(a + 0x11a, ram.u8(br + 0x1b) + ram.u8(nx + 0x18))
			var sv: int = FMath.tdiv(ram.s16(ram.u32(b + 0x1a4) + 0x14) * 0x20, 0x2d) + 0x22
			ram.w16(a + 0x118, 0x42 if FMath.s16(sv) > 0x41 else sv)
			if ram.s16(a + 0x118) < 0x23:
				ram.w16(a + 0x118, 0x22)
			ram.w16(a + 0x106, 0)
			ram.w16(a + 0x108, 0)
			ram.w16(a + 0x10a, 0)
			return 2
		0x23, 0x26:
			if kind == 0x26:
				stun_blend(ram, a, row)
			slide_setup(ram, a, ram.s16(table + (0x28 if kind == 0x23 else 0x22)))
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w16(a + 0x74, 0)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x10c, ram.s16(a + 0x2a) + ram.s16(table + 0x1c) - 0x8000)
			ram.w8(a + 0xb9, 7)
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
			ram.w16(a + 0x0e, ram.s16(a + 0x34))
			return 1
		0x25:
			stun_blend(ram, a, row)
			slide_setup(ram, a, ram.s16(table + 0x26))
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w16(a + 0x118, 0)
			ram.w16(a + 0x74, 0)
			ram.w32(a + 0x4c, nx)
			ram.w16(a + 0x10c, ram.s16(a + 0x2a) + ram.s16(table + 0x24) - 0x8000)
			ram.w8(a + 0xb9, 0xb)
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			return 1
		0x27, 0x28, 0x29, 0x2a, 0x2b:
			stun_blend(ram, a, row)
			slide_setup(ram, a, ram.s16(table + 0x1e))
			var base: int = ram.s16(a + 0x34) if kind == 0x2a else ram.s16(a + 0x2a)
			ram.w16(a + 0x10c, base + ram.s16(table + 0x1c) - 0x8000)
			juggle_counter(ram, a)
			ram.w16(a + 0x58, 1)
			ram.w16(a + 0x50, 1)
			ram.w16(a + 0x74, 0)
			ram.w32(a + 0x4c, nx)
			ram.w8(a + 0xb9, 0xb)
			ram.w16(a + 0x114, 0)
			ram.w16(a + 0x116, 0)
			ram.w16(a + 0x0e, ram.s16(a + 0x2c))
			return 1
	return 0

static func step(ram, a: int, b: int) -> void:
	if ram.u8(a + 0xc3) == 0:
		return
	var left: int = ram.s16(a + 0x128) - 1
	ram.w16(a + 0x128, 0 if left < 0 else left)
	if not frame_hold_done(ram, a):
		advance(ram, a)
		return
	var copy: int = begin_common(ram, a, b)
	apply_kind(ram, a, b, copy)
	finish(ram, a)
static func find_in_row(ram, a: int, b: int) -> int:
	var row: int = ram.u32(a + 0x54)
	return Commands.find_move(ram, ram.u32(row + 0xc), ram.s16(a + 0x58), a, b)
static func queue_by_list(ram, a: int, b: int) -> void:
	ram.w16(a + 0x6c, 0xffff)
	if ram.u32(a + 0x1a4) != 0:
		return
	if ram.s16(a + 0x128) > 0x19:
		return
	var e: int = find_in_row(ram, a, b)
	var row: int = ram.u32(a + 0x54)
	var f: int = ram.s16(a + 0x58)
	if ram.s16(e) != -0x4000:
		var id: int = ram.s16(e + 6)
		ram.w16(a + 0x1a0, id)
		ram.w32(a + 0x1a4, slot_row(ram, a, id))
		ram.w16(a + 0x6c, ram.u8(e + 10) - f)
		ram.w16(a + 0x19a, kind_of(ram, a, ram.u8(e + 8) & 0x3f))
		ram.w16(a + 0x19c, ram.u8(e + 8) >> 7)
		ram.w16(a + 0x19e, ram.u8(e + 8) >> 6 & 1)
		ram.w16(a + 0x198, ram.u8(e + 10) if ram.s16(a + 0x6e) < 0 else ram.u8(e + 11))
		if ram.s16(a + 0x198) == 0xff:
			ram.w16(a + 0x198, ram.u8(row + 0x18))
		ram.w8(a + 0x8b, 2)
		return
	var start: int = ram.u8(e + 9)
	var speed: int = ram.s16(a + 0x6e)
	var look_ahead := false
	if f >= start - 5:
		if start <= f:
			look_ahead = f <= ram.u8(e + 10) and speed > 0
		else:
			look_ahead = speed >= 1 and (ram.u8(a + ram.s32(a + 0x40c) + 0x41c) & 0xf0) != 0
	if look_ahead:
		var ahead: int = slot_row(ram, a, ram.s16(e + 6))
		var saved: int = ram.s16(a + 0x2c)
		ram.w16(a + 0x2c, saved + ram.s16(row + 0x12))
		face_opponent(ram, a, b)
		var e2: int = Commands.find_move(ram, ram.u32(ahead + 0xc), 1, a, b)
		ram.w16(a + 0x2c, saved)
		face_opponent(ram, a, b)
		if ram.s16(e2) != -0x4000:
			var id2: int = ram.s16(e2 + 6)
			ram.w16(a + 0x1a0, id2)
			ram.w32(a + 0x1a4, slot_row(ram, a, id2))
			ram.w16(a + 0x198, start)
			ram.w16(a + 0x19e, ram.u8(e + 8) >> 6 & 1)
			ram.w16(a + 0x6c, ram.u8(e2 + 10) - f)
			ram.w16(a + 0x19a, kind_of(ram, a, ram.u8(e2 + 8) & 0x3f))
			ram.w8(a + 0xc1, 1)
			ram.w8(a + 0x8b, 3)
			ram.w16(a + 0x19c, ram.u8(e2 + 8) >> 7)
			return
	var sum: int = f + speed
	if ram.u8(row + 0x18) < sum or sum < 1:
		ram.w16(a + 0x198, f)
		var id3: int = ram.s16(e + 6)
		ram.w16(a + 0x1a0, id3)
		ram.w32(a + 0x1a4, slot_row(ram, a, id3))
		ram.w16(a + 0x19a, kind_of(ram, a, ram.u8(e + 8) & 0x3f))
		ram.w16(a + 0x19c, ram.u8(e + 8) >> 7)
		ram.w8(a + 0xc1, 1)
		ram.w8(a + 0x8b, 4)
		ram.w16(a + 0x19e, ram.u8(e + 8) >> 6 & 1)
static func kind_of(ram, a: int, k: int) -> int:
	match k - 2:
		0:
			if not spare_frames(ram, a):
				return k
			return 0x14
		10, 11, 12, 13:
			var held: int = ram.u8(ram.u32(a + 0x1a4) + 0x2d)
			return 0xb if held == 0 else k
		14:
			return 0x10
		18, 19:
			return 0xb if not spare_frames(ram, a) else k
		23:
			return 0x16 if spare_frames(ram, a) else k
	return k
static func spare_frames(ram, a: int) -> bool:
	var nx: int = ram.u32(a + 0x1a4)
	if ram.u8(nx + 0x2d) == 0:
		return false
	if ram.s16(a + 0x198) + 1 < ram.u8(nx + 0x2e):
		return ram.u8(nx + 0x2e) <= ram.u8(nx + 0x18)
	return false
static func react_to_hit(ram, a: int, b: int) -> void:
	var tbl: int = ram.u32(a + 0x1a8)
	var row: int = ram.u32(a + 0x54)
	var flags: int = ram.u32(a + 0x60)
	var pick: int = 0 if (flags & 2) == 0 else 1
	if ram.u8(a + 0xcf) == 0:
		if ram.u8(a + 0xdb) == 0 and (ram.u32(row + 4) & 0x400) == 0:
			if (flags & 0x200) == 0:
				if (flags & 4) == 0:
					if ram.u8(a + 0xd3) == 0:
						match ram.s16(a + 0x32):
							1:
								ram.w16(a + 0x19a, kind_of(ram, a, 0x27))
								ram.w16(a + 0x1a0, ram.s16(tbl + (8 if pick else 10)))
							0:
								ram.w16(a + 0x19a, kind_of(ram, a, 0x2a))
								ram.w16(a + 0x1a0, ram.s16(tbl + (0 if pick else 2)))
							2:
								ram.w16(a + 0x19a, kind_of(ram, a, 0x2b))
								ram.w16(a + 0x1a0, ram.s16(tbl + (0x10 if pick else 0x12)))
							3:
								ram.w16(a + 0x19a, kind_of(ram, a, 0x28))
								ram.w16(a + 0x1a0, ram.s16(tbl + (0xc if pick else 0xe)))
					else:
						ram.w16(a + 0x19a, kind_of(ram, a, 0x26))
						ram.w16(a + 0x1a0, ram.s16(tbl + (4 if pick else 6)))
				else:
					ram.w16(a + 0x19a, kind_of(ram, a, 0x25))
					ram.w16(a + 0x1a0, ram.s16(tbl + 0x18))
			else:
				ram.w16(a + 0x19a, kind_of(ram, a, 0x25))
				ram.w16(a + 0x1a0, ram.s16(tbl + 0x1a))
		else:
			ram.w16(a + 0x19a, kind_of(ram, a, 0x24))
			rise_choice(ram, a, b)
	else:
		ram.w16(a + 0x19a, kind_of(ram, a, 0x23))
		ram.w16(a + 0x1a0, ram.s16(tbl + (0x14 if pick else 0x16)))
	ram.w16(a + 0x19c, 0)
	ram.w16(a + 0x19e, 0)
	ram.w16(a + 0x198, ram.s16(a + 0x58))
	ram.w32(a + 0x1a4, slot_row(ram, a, ram.s16(a + 0x1a0)))
static func rise_choice(ram, a: int, b: int) -> void:
	var cur_id: int = ram.s16(a + 0xa0)
	var keep: bool = cur_id != 0xd62
	if cur_id == 0xd63 and ram.s16(a + 0x58) > 0x12:
		keep = false
	if cur_id == 0xd64 and ram.s16(a + 0x58) > 0x12:
		keep = false
	var v: int
	if not keep:
		if cur_id != 0xd62:
			var h: int = ram.s32(a + 0xf6c)
			if h < 0:
				if -FMath.s16(h) > 0x3ff:
					v = 0
				else:
					v = 2
			elif FMath.s16(h) > 0x3ff:
				v = 0
			else:
				v = 2
			ram.w16(a + 0x90, v)
		else:
			ram.w16(a + 0x90, 2)
	else:
		var c := 0
		if ram.s16(b + 0x16) == 9:
			c = 1 if ram.s16(b + 0xa0) == 0x241 else 0
		if ram.s16(b + 0x16) == 0x10 and ram.s16(b + 0xa0) == 0x14a:
			c = 1
			if ram.u32(b + 0x1a4) != 0 and ((ram.u16(b + 0x1a0) - 0x848) & 0xffff) < 2:
				c = 2
		if c == 1 or (c != 2 and ram.s32(a + 0x3e0) > 0x6d):
			ram.w16(a + 0x90, 1)
		else:
			if cur_id != 0xd58:
				var q: int = ram.s16(a + 0x32)
				if q == 1:
					ram.w16(a + 0x90, 4)
				elif q == 3:
					ram.w16(a + 0x90, 3)
				else:
					ram.w16(a + 0x90, 0)
			else:
				ram.w16(a + 0x90, 0)
	ram.w16(a + 0x96, ram.u16(RISE_TABLE + ram.s16(a + 0x90) * 4))
	ram.w16(a + 0x1a0, ram.u16(RISE_TABLE + 2 + ram.s16(a + 0x90) * 4))
static func set_stand(ram, a: int, b: int) -> void:
	ram.w16(a + 0x1a0, 0xd66)
	ram.w32(a + 0x1a4, slot_row(ram, a, 0xd66))
	ram.w16(a + 0x58, 1)
	ram.w16(a + 0x198, 1)
	ram.w16(a + 0x19a, kind_of(ram, a, 6))
	ram.w16(a + 0x19c, 0)
	ram.w16(a + 0x19e, 0)
	ram.w8(a + 0xcf, 0)
	ram.w8(a + 0xd0, 1)
	ram.w16(a + 0x66, 0)
	step(ram, a, b)
static func choose_next(ram, a: int) -> void:
	var b: int = opponent(ram, a)
	face_opponent(ram, a, b)
	var dist: int = ram.u32(distance_entry(ram, ram.u8(a + 0x1e), ram.u8(b + 0x1e)))
	ram.w32(a + 0xf8, dist)
	var n := 0
	if ram.s16(a + 0x18) == 0xb or ram.s16(a + 0x18) == 0x14:
		n = 1
	if ram.s16(b + 0x18) == 0xb or ram.s16(b + 0x18) == 0x14:
		n += 1
	ram.w32(a + 0xf4, dist - 40 * n)
	if ram.u8(a + 0xce) != 0:
		var mode: int = ram.u8(b + 0xb7)
		if mode != 1:
			var go := false
			if mode == 0:
				go = true
			elif mode == 2 and ram.u8(a + 0xdb) == 0 and (ram.u32(a + 0x60) & 4) == 0:
				go = true
			if go:
				react_to_hit(ram, a, b)
				ram.w8(a + 0x8b, 1)
				if ram.s16(a + 0x74) > 0:
					ram.w8(a + 0xb7, 1)
	if ram.u32(a + 0x1a4) == 0:
		queue_by_list(ram, a, b)
	if ram.u8(0x800afa93) == 0:
		if ram.s32(a + 0x3f4) == 0 and ram.u8(a + 0xd0) != 0:
			var r: int = slot_row(ram, a, ram.s16(a + 0x1a0))
			var v: int = ram.u16(r + 0x10)
			if v == 3 or v == 0x28:
				ram.w8(a + 0xdb, 1)
				ram.w8(a + 0xcf, 0)
				ram.w8(a + 0xd0, 1)
				ram.w16(a + 0x66, 0)
				react_to_hit(ram, a, b)
				ram.w8(a + 0xb7, 1)
	elif ram.s32(a + 0x3f4) == 0 and ram.u8(a + 0xd0) != 0:
		var r2: int = slot_row(ram, a, ram.s16(a + 0x1a0))
		var v2: int = ram.u16(r2 + 0x10)
		if v2 == 3 or v2 == 0x28 or ((ram.u32(r2 + 4) & 4) == 0 and ram.u8(r2 + 0x19) == 0):
			set_stand(ram, a, b)
			ram.w8(a + 0xb7, 1)
	if ram.s16(a + 0x19a) == 0x21:
		ram.w8(a + 0x84, ram.u8(b + 0x1e))
		ram.w8(b + 0x84, ram.u8(a + 0x1e))
		ram.w8(b + 0xc4, 1)
		ram.w8(a + 0xc4, 1)
static func opponent_index(ram, a: int) -> int:
	if ram.u8(a + 0xc4) == 0:
		if ram.u8(a + 0x87) == 0:
			return ram.u8(a + 0x20) if ram.u8(a + 0xd1) == 0 else ram.u8(a + 0x23)
		return ram.u8(a + 0x22)
	return ram.u8(a + 0x21)
static func update_distances(ram) -> void:
	var far: Array = [0, 0]
	for p in 2:
		var a: int = PLAYER_BASE + p * PLAYER_SIZE
		far[p] = 1 if ram.u16(a + 0x1278) >= 0x191 else 0
	var a1: int = PLAYER_BASE + PLAYER_SIZE
	var dx: int = ram.s32(a1 + 0xf68) - ram.s32(PLAYER_BASE + 0xf68)
	var dz: int = ram.s32(a1 + 0xf70) - ram.s32(PLAYER_BASE + 0xf70)
	var e: int = distance_entry(ram, 1, 0)
	ram.w32(e, FMath.isqrt(dx * dx + dz * dz))
	ram.w32(e + 4, dx)
	ram.w32(e + 8, dz)
	ram.w16(e + 12, FMath.atan2(ram, dz, dx))
	for p in 2:
		var a: int = PLAYER_BASE + p * PLAYER_SIZE
		var idx: int = opponent_index(ram, a)
		var entry: int = distance_entry(ram, p, idx)
		var opp: int = opponent(ram, a)
		ram.w32(a + 0x12c, ram.u32(a + 0xf68))
		ram.w32(a + 0x130, ram.u32(a + 0xf70))
		var dist: int = ram.u32(entry)
		ram.w32(a + 0xf8, dist)
		var n := 0
		if ram.s16(a + 0x18) == 0xb or ram.s16(a + 0x18) == 0x14:
			n = 1
		if ram.s16(opp + 0x18) == 0xb or ram.s16(opp + 0x18) == 0x14:
			n += 1
		ram.w32(a + 0xf4, dist - 40 * n)
		ram.w32(a + 0xfc, ram.u32(entry + 4))
		ram.w32(a + 0x100, ram.u32(entry + 8))
		var ang: int = ram.s16(entry + 12)
		if idx >= p:
			ang -= 0x8000
		if ram.u8(a + 0xc7) == 0 and far[idx] == 0:
			ram.w16(a + 0x2a, ang)
		else:
			var side: int = 0xb4 - ram.s16(a + 0x1278)
			side = absi(side)
			side = absi(0xb4 - side)
			ram.w16(a + 0x2a, 0x4000 if ram.u8(a + 0xc8) == 0 else -0x4000)
			ram.w32(a + 0xf8, side * 10)
			ram.w32(a + 0xfc, side * 10)
			ram.w16(a + 0x100, 0)
			ram.w16(a + 0x102, 0)
	ram.w32(0x800afa3c, ram.u32(PLAYER_BASE + 0xf8))
static func react_pick(ram, a: int, b: int) -> void:
	if ram.s16(b + 0x18) == 0x11:
		return
	ram.w16(a + 0xea, 0)
	if ram.u8(a + 0xce) == 0:
		return
	var row: int = ram.u32(a + 0x54)
	var e: int = Commands.find_reaction(ram, ram.u32(row + 0xc), ram.s16(a + 0x58), a, b)
	if ram.s16(e) == -0x4000:
		return
	var id: int = ram.s16(e + 6)
	ram.w16(a + 0x1a0, id)
	ram.w32(a + 0x1a4, slot_row(ram, a, id))
	ram.w16(a + 0x198, ram.u8(e + 11))
	ram.w8(a + 0x87, 0)
	ram.w8(a + 0xce, 0)
	ram.w8(a + 0xcf, 0)
	ram.w8(a + 0xd0, 0)
	ram.w16(a + 0x104, 0)
	ram.w16(a + 0x6c, ram.u8(e + 10) - ram.s16(a + 0x58))
	ram.w8(b + 0xd1, 0)
	ram.w8(b + 0x83, 0)
	ram.w8(b + 0x84, 0)
	ram.w8(b + 0x85, 0)
	ram.w8(b + 0x88, 0)
	ram.w16(a + 0x19a, kind_of(ram, a, ram.u8(e + 8) & 0x3f))
	ram.w16(a + 0x19c, 0)
	ram.w16(a + 0x19e, 0)
	ram.w8(a + 0x189, 0)
	ram.w8(a + 0x15d, 0)
	var dmg: int = FMath.s16(ram.u16(b + 0x5e))
	ram.w16(a + 0xea, ((dmg - (dmg >> 31)) >> 1) + 0x19)
static func clear_events(ram, a: int) -> void:
	ram.w16(a + 0x70, 0xffff)
	ram.w16(a + 0x72, 0)
	ram.w16(a + 0x11e, 0)
	ram.w16(a + 0x120, 0)
