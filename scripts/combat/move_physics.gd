extends RefCounted
# Movement of the fighter each frame (steps, turns, jumps, knockback) from the move row data.
# Fields are read with ram.u8/u16/u32 at "actor + offset"; offsets are listed at the top of ram.gd.
const FMath := preload("res://scripts/combat/fmath.gd")
const MoveStep := preload("res://scripts/combat/move_step.gd")
const SLIDE_X := 0x8009e600
const SLIDE_Z := 0x8009e610
const SPEED_BASE := 0x800afa3c
static func clamp_step(v: int, limit: int) -> int:
	return -limit if v < -limit else (limit if v > limit else v)
static func limit(v: int, bound: int) -> int:
	v = FMath.s16(v)
	if v < 0:
		return FMath.s16(-bound) if v < -bound else v
	return FMath.s16(bound) if bound < v else v
static func overshoot(p1: int, p2: int, bound: int) -> int:
	p1 = FMath.s16(p1)
	p2 = FMath.s16(p2)
	if bound < absi(p2) + absi(p1):
		var d: int = FMath.s16(bound - absi(p2))
		return -d if p1 < 0 else d
	return 0
static func span_to(ram, a: int, target_offset: int) -> int:
	return FMath.s16(ram.u16(a + target_offset) - ram.u16(a + 0x2c))
static func frames_left(ram, a: int, row: int) -> int:
	var n: int = FMath.s16(ram.u8(row + 0x2d) + 1 - ram.u16(a + 0x58))
	return 1 if n < 1 else n
static func trig_scale(ram, amount: int, trig: int) -> int:
	return FMath.tdiv(amount * trig, 0x7fff)
static func run(ram, a: int) -> void:
	var b: int = MoveStep.opponent(ram, a)
	ram.w8(a + 0xdc, 0)
	ram.w8(a + 0xdd, 0)
	ram.w8(a + 0xdf, 0)
	MoveStep.face_opponent(ram, a, b)
	var row: int = ram.u32(a + 0x54)
	var prev: int = ram.u32(a + 0x4c)
	var f: int = ram.s16(a + 0x58)
	if ram.u8(a + 0x82) == 1:
		if ram.u8(prev + 0x19) <= f:
			var span: int = ram.u8(prev + 0x1a) - f
			if span == 0:
				span = 1
			ram.w8(a + 0x82, 2)
			var spd: int = ram.s32(SPEED_BASE) - 500
			if ram.s32(SPEED_BASE) > 0xc00:
				spd = 0xa0c
			var per: int = FMath.s16(FMath.tdiv(spd, span))
			ram.w32(a + 0x78, FMath.tdiv(per * FMath.sin(ram, ram.s16(a + 0x2a)), 0x7fff))
			ram.w8(a + 0xb8, 2)
			ram.w32(a + 0x7c, FMath.tdiv(per * FMath.cos(ram, ram.s16(a + 0x2a)), 0x7fff))
	elif ram.u8(a + 0x82) == 2:
		ram.w32(a + 8, ram.s32(a + 8) + ram.s32(a + 0x7c))
		ram.w32(a, ram.s32(a) + ram.s32(a + 0x78))
		if ram.u8(ram.u32(a + 0x4c) + 0x1a) <= f:
			ram.w8(a + 0x82, 0)
			ram.w32(a + 0x78, 0)
			ram.w32(a + 0x7c, 0)
			ram.w32(a, ram.u32(a + 0xf68))
			ram.w32(a + 8, ram.u32(a + 0xf70))
	if ram.s16(a + 0x92) == 0 or (ram.s16(a + 0x76) != 0 and ram.s16(b + 0x16) == 0xe):
		var r2: int = ram.u32(a + 0x54)
		if ram.u8(r2 + 0x19) != 0 and ram.u8(r2 + 0x19) - 1 <= f and f <= ram.u8(r2 + 0x1a):
			var speed: int = ram.s16(r2 + 0x16)
			var player: int = ram.u8(a + 0x1e)
			if speed != 0:
				var x0: int = ram.s32(a)
				var z0: int = ram.s32(a + 8)
				var sx: int = SLIDE_X + player * 4
				var sz: int = SLIDE_Z + player * 4
				ram.w32(sx, ram.s32(sx) + trig_scale(ram, speed, FMath.sin(ram, ram.s16(a + 0xe))))
				ram.w32(sz, ram.s32(sz) + trig_scale(ram, speed, FMath.cos(ram, ram.s16(a + 0xe))))
				ram.w32(a, ram.s32(a) - (ram.s32(sx) >> 8))
				ram.w32(a + 8, ram.s32(a + 8) - (ram.s32(sz) >> 8))
				ram.w32(sx, ram.s32(sx) + (ram.s32(a) - x0) * 0x100)
				ram.w32(sz, ram.s32(sz) + (ram.s32(a + 8) - z0) * 0x100)
	else:
		var vy: int = ram.s16(a + 0x9c) + 6
		ram.w16(a + 0x9c, vy)
		ram.w32(a + 4, ram.s32(a + 4) + FMath.s16(vy))
		ram.w32(a, ram.s32(a) + ram.s16(a + 0x9a))
		ram.w32(a + 8, ram.s32(a + 8) + ram.s16(a + 0x9e))
		ram.w16(a + 0x9a, trig_scale(ram, ram.s16(a + 0x98), FMath.sin(ram, ram.s16(a + 0x2a) + 0x8000)))
		ram.w16(a + 0x9e, trig_scale(ram, ram.s16(a + 0x98), FMath.cos(ram, ram.s16(a + 0x2a) + 0x8000)))
		if ram.s16(a + 0x9c) > 0 and -ram.s16(a + 0x96) <= ram.s32(a + 4):
			ram.w32(a + 8, ram.u32(a + 0xf70))
			ram.w32(a + 4, 0)
			ram.w32(a, ram.u32(a + 0xf68))
			if ram.s16(a + 0x90) == 5:
				ram.w8(a + 0xdc, 1)
			else:
				ram.w8(a + 0xdd, 1)
			ram.w16(a + 0x92, 0)
			ram.w8(a + 0xb8, 2)
	if ram.s16(a + 0x18) == 0x11 and ram.u8(a + 0x8a) != 0 and ram.s16(a + 0x94) == 0:
		if ram.u8(a + 0xdb) == 0:
			ram.w32(a + 4, 0)
		elif ram.s32(a + 0xf6c) + 0x80 < 0:
			ram.w32(a + 4, (ram.s32(a + 0xf6c) + 0x80) >> 1)
	if ram.u8(a + 0xdb) == 0:
		ram.w16(a + 0x8e, 0)
	if ram.s16(a + 0x114) != 0:
		ram.w16(a + 0x114, ram.s16(a + 0x114) - 1)
		var turned: int = ram.s16(a + 0x2c) + ram.s16(a + 0x116)
		ram.w16(a + 0x2c, turned)
		if ram.s16(a + 0x74) == 1:
			ram.w16(a + 0xe, turned)
	if ram.u8(a + 0xbf) == 1:
		ram.w8(a + 0xbf, 0)
		var dz: int = ram.s32(a + 0xf70) - ram.s32(a + 0xa8)
		var dx: int = ram.s32(a + 0xf68) - ram.s32(a + 0xa4)
		ram.w16(a + 0x10c, FMath.atan2(ram, dz, dx))
		ram.w16(a + 0x106, 0x10)
		var dist: int = FMath.isqrt(dx * dx + dz * dz)
		ram.w16(a + 0x108, FMath.tdiv(dist, ram.s16(a + 0x106)))
		ram.w32(a, ram.s32(a + 0xf68) - trig_scale(ram, dist, FMath.sin(ram, ram.s16(a + 0x10c) + 0x8000)))
		ram.w32(a + 8, ram.s32(a + 0xf70) - trig_scale(ram, dist, FMath.cos(ram, ram.s16(a + 0x10c) + 0x8000)))
	var push := 0
	if ram.s16(a + 0x106) > 0:
		push = ram.s16(a + 0x108)
		ram.w16(a + 0x106, ram.s16(a + 0x106) - 1)
	if ram.s16(a + 0x10a) > 0:
		ram.w16(a + 0x10a, ram.s16(a + 0x10a) - 1)
		var table: int = ram.u32(a + 0x110)
		var extra: int = ram.s16(table)
		ram.w32(a + 0x110, table + 2)
		push += extra
		if ram.s16(a + 0x124) > 0:
			push += ram.s16(a + 0x124) * 0x28 + 10
	if push != 0:
		ram.w32(a, ram.s32(a) + trig_scale(ram, push, FMath.sin(ram, ram.s16(a + 0x10c))))
		ram.w32(a + 8, ram.s32(a + 8) + trig_scale(ram, push, FMath.cos(ram, ram.s16(a + 0x10c))))
	turn_mode(ram, a, b)
	post(ram, a, b)
static func ease_turn(ram, a: int, row: int, step: int, cap: int) -> void:
	var d: int = limit(FMath.tdiv(span_to(ram, a, 0x2a), frames_left(ram, a, row)), step)
	var over: int = overshoot(d, ram.s16(a + 0x36), cap)
	if over != 0:
		ram.w8(a + 0xb9, 6)
		d = over
	var s36: int = ram.s16(a + 0x36)
	ram.w16(a + 0x2c, ram.s16(a + 0x2c) + d)
	ram.w16(a + 0x36, s36 + d)
	if ram.u8(row + 0x2d) <= ram.s16(a + 0x58):
		ram.w8(a + 0xb9, 6)
static func catch_up(ram, a: int, row: int) -> void:
	var n: int = ram.u8(row + 0x2d) - ram.u16(a + 0x58)
	ram.w16(a + 0x114, n)
	if FMath.s16(n) < 1:
		ram.w16(a + 0x114, 1)
	var d: int = FMath.tdiv(span_to(ram, a, 0x2a), ram.s16(a + 0x114))
	ram.w16(a + 0x116, d)
	ram.w16(a + 0x116, limit(d, 0x9f4))
	ram.w8(a + 0xb9, 0xc)
static func turn_mode(ram, a: int, b: int) -> void:
	var row: int = ram.u32(a + 0x54)
	var f: int = ram.s16(a + 0x58)
	match ram.u8(a + 0xb9):
		0:
			ram.w16(a + 0x2c, ram.s16(a + 0x0e))
		1:
			var d: int = limit(FMath.tdiv(span_to(ram, a, 0x34), frames_left(ram, a, row)), 0x1555)
			var over: int = overshoot(d, ram.s16(a + 0x36), 0x7fff)
			if over != 0:
				ram.w8(a + 0xb9, 6)
				d = over
			var s36: int = ram.s16(a + 0x36)
			var nf: int = ram.s16(a + 0x2c) + d
			ram.w16(a + 0x2c, nf)
			ram.w16(a + 0x0e, nf)
			ram.w16(a + 0x36, s36 + d)
			if ram.u8(row + 0x2d) <= ram.s16(a + 0x58):
				ram.w8(a + 0xb9, 6)
		2, 3:
			if ram.s16(b + 0x11c) != 0 and ram.u8(a + 0xb4) != 0 and ram.s16(a + 0x5c) < 9:
				catch_up(ram, a, row)
				return
			var n: int = 1
			if ram.u8(a + 0xdb) == 0:
				n = 0xe if ram.s16(a + 0x5c) > 7 else 3
			var rate: int = FMath.tdiv(n * 0xffff, 0x168)
			if ram.u8(a + 0xb9) == 3:
				rate = rate >> 1
			ease_turn(ram, a, row, rate, 0x5555)
		4:
			if ram.s16(a + 0x114) == 0 and (ram.s16(b + 0x11c) == 0 or ram.u8(a + 0xb4) == 0):
				var n4: int = 1
				if ram.u8(a + 0xdb) == 0:
					n4 = 3 if ram.s16(a + 0x5c) > 7 else 2
				ease_turn(ram, a, row, FMath.tdiv(n4 * 0xffff, 0x168), 0xe38)
		5:
			if ram.s16(b + 0x11c) == 0 or ram.u8(a + 0xb4) == 0 or ram.s16(a + 0x5c) > 8:
				var n5: int = 4
				if ram.u8(a + 0xdb) == 0:
					n5 = 100 if ram.s16(a + 0x5c) > 7 else 3
				ease_turn(ram, a, row, FMath.tdiv(n5 * 0xffff, 0x168), 0x9554)
			else:
				catch_up(ram, a, row)
		6:
			if ram.s16(a + 0x5e) == 0 or ram.u8(row + 0x19) == 0 or ram.u8(a + 0xdb) != 0 or f < ram.u8(row + 0x2e):
				if ram.u8(row + 0x2d) < f:
					var d6: int = f - ram.u8(row + 0x2d)
					if d6 == FMath.tdiv(d6, 5) * 5 and ram.s16(a + 0x30) < 0x5556:
						ram.w16(a + 0x114, 5 if ram.u8(row + 0x18) - f < 6 else ram.u8(row + 0x18) - ram.s16(a + 0x58))
						if ram.s16(a + 0x114) < 0:
							ram.w16(a + 0x114, 0)
						else:
							var dd: int = FMath.tdiv(span_to(ram, a, 0x34), ram.s16(a + 0x114))
							ram.w16(a + 0x116, dd)
							ram.w16(a + 0x116, limit(dd, 0x222))
			else:
				ram.w16(a + 0x114, 0)
				ram.w16(a + 0x116, 0)
		7:
			var end: int = ram.u8(row + 0x1a)
			if end == 0:
				end = ram.u8(row + 0x18)
			if f <= end:
				if end == 0:
					end = 1
				ram.w16(a + 0x2c, ram.s16(a + 0x2c) + limit(FMath.tdiv(span_to(ram, a, 0x34) * f, end), 0x38e))
		8:
			var k: int = mini(ram.s16(a + 0x5c), 8)
			ram.w16(a + 0x2c, ram.s16(a + 0x2c) + limit(FMath.tdiv(span_to(ram, a, 0x34) * k, 8), 0x71c))
		9:
			if ram.s32(SPEED_BASE) > 0x4af:
				var ang: int = FMath.atan2(ram, ram.s32(a + 0xb0) - ram.s32(a + 0xf70), ram.s32(a + 0xac) - ram.s32(a + 0xf68))
				var diff: int = (ram.u16(a + 0x0e) - ang) & 0xffffffff
				if diff & 0x8000:
					diff = ~diff & 0xffffffff
				if (diff & 0xffff) > 0x3fff:
					ang -= 0x8000
				var nf9: int = ram.s16(a + 0x0e) + limit(FMath.tdiv(FMath.s16(ang - ram.u16(a + 0x0e)) * f, ram.u8(row + 0x18)), 0x5b0)
				ram.w16(a + 0x0e, nf9)
				ram.w8(a + 0xbe, 1)
				ram.w16(a + 0x2c, nf9)
		10:
			if f <= ram.u8(row + 0x18):
				var step10: int
				if ram.s16(a + 0x18) == 7 and ram.s16(a + 0x32) == 2:
					step10 = 0x71c if ram.s16(a + 0x24) < 0 else -0x71c
				else:
					step10 = -0x11c7 if ram.s16(a + 0x24) < 0 else 0x11c7
				ram.w8(a + 0xbe, 1)
				var nf10: int = ram.s16(a + 0x34) + FMath.tdiv(step10 * f, ram.u8(row + 0x18))
				ram.w16(a + 0x0e, nf10)
				ram.w16(a + 0x2c, nf10)
static func post(ram, a: int, b: int) -> void:
	var row: int = ram.u32(a + 0x54)
	var f: int = ram.s16(a + 0x58)
	if ram.s16(a + 0x11c) > 0:
		ram.w16(a + 0x11c, ram.s16(a + 0x11c) - 1)
	if ram.s16(a + 0x104) > 0:
		ram.w16(a + 0x104, ram.s16(a + 0x104) - 1)
	if f < ram.u8(row + 0x2d) or ram.u8(row + 0x2e) < f:
		ram.w8(a + 0xe3, 0)
	elif ram.u8(ram.u32(row + 0x28) + 2) == 0:
		ram.w8(a + 0xe3, 1)
	else:
		ram.w8(a + 0xe3, 2)
	ram.w8(a + 0xe6, 0)
	if ram.s16(a + 0x94) == 0:
		ram.w8(a + 0xdb, 1 if ram.u8(row + 0x19) <= f and f <= ram.u8(row + 0x1a) else 0)
	else:
		ram.w8(a + 0xdb, 1)
	if ram.u16(a + 0x58) == ram.u8(row + 0x1a) and ram.s16(a + 0x6a) == -1 and ram.u16(a + 0x58) != 1 and ram.u8(a + 0xb8) != 2:
		if ram.u8(a + 0x87) == 0 or ram.s16(a + 0x90) == 5 or (ram.u8(a + 0x69) != 9 and (ram.u32(a + 0x60) & 4) == 0):
			ram.w8(a + 0xdc, 1)
		else:
			ram.w8(a + 0xdd, 1)
	var cd: int = ram.s16(a + 0x11a)
	if cd != 0:
		ram.w16(a + 0x11a, cd - 1)
		if cd - 1 < 0:
			ram.w16(a + 0x11a, 0)
		if ram.u8(a + 0xd0) != 0:
			ram.w16(a + 0x11a, 0)
	if ram.s16(a + 0x11a) < 0x1f and ram.s16(a + 0x118) != 0:
		ram.w16(a + 0x118, ram.s16(a + 0x118) - 1)
		var hist: int = ram.u8(a + ram.s32(a + 0x40c) + 0x41c)
		var dec := 0
		if (hist & 0x20) == 0:
			if (hist & 0xf0) != 0:
				dec = 1
		else:
			dec = 3
		var v: int = ram.u16(a + 0x118) - dec
		ram.w16(a + 0x118, v)
		if FMath.s16(v) < 0:
			ram.w16(a + 0x118, 0)
	if ram.s16(a + 0x5e) != 0:
		var lead: int = ram.u8(row + 0x2d) - 3
		if lead < 0:
			lead = 1
		if lead <= f and f <= ram.u8(row + 0x2d):
			ram.w8(a + 0xdf, 1)
	if (ram.u32(row + 0x24) >> 8 & 4) != 0:
		ram.w8(a + 0xdf, 1)
	if ram.s16(a + 0x18) == 0x11 and ram.s16(b + 0x18) != 0x11:
		ram.w8(a + 0xdf, 1)
	var hist2: int = ram.u8(a + ram.s32(a + 0x40c) + 0x41c) & 0xf
	var skip_to_end := false
	if (ram.u32(row + 0x24) >> 8 & 0x40) == 0:
		if ram.u8(a + 0xb6) != 0:
			if hist2 == 4:
				ram.w32(a + 0x60, 0x1052)
				ram.w16(a + 0x66, ram.u16(a + 0x60) & 0x18)
			elif hist2 == 1:
				ram.w32(a + 0x60, 0x2829)
				ram.w16(a + 0x66, ram.u16(a + 0x60) & 0x18)
			else:
				ram.w32(a + 0x60, ram.s16(row + 4))
				ram.w16(a + 0x66, ram.u16(a + 0x60) & 0x18)
				if (ram.u32(a + 0x60) & 0x100) != 0 and ram.u8(a + 0xca) == 0:
					ram.w32(a + 0x60, ram.u32(a + 0x60) & 0xffffffe7)
					ram.w16(a + 0x66, ram.u16(a + 0x66) & 0xffe7)
	else:
		if ram.u8(a + 0xca) == 0:
			if hist2 == 4:
				ram.w32(a + 0x60, 0x1052)
				ram.w16(a + 0x66, ram.u16(a + 0x60) & 0x18)
			elif hist2 == 1:
				ram.w32(a + 0x60, 0x2829)
				ram.w16(a + 0x66, ram.u16(a + 0x60) & 0x18)
		else:
			if hist2 == 4 or hist2 == 5:
				ram.w32(a + 0x60, 0x1052)
				ram.w16(a + 0x66, ram.u16(a + 0x60) & 0x18)
			elif hist2 == 1 or hist2 == 2:
				ram.w32(a + 0x60, 0x2829)
				ram.w16(a + 0x66, ram.u16(a + 0x60) & 0x18)
	if ram.u8(a + 0xdb) == 0 and ram.s16(a + 0x30) < 0x4000:
		ram.w16(a + 0x66, ram.u16(a + 0x60) & 0x18)
	else:
		ram.w16(a + 0x66, 0)
	if ram.u8(a + 0x69) == 9 and ram.u8(row + 0x19) != 0 and ram.u8(row + 0x19) <= ram.s16(a + 0x58):
		ram.w32(a + 0x60, ram.u32(a + 0x60) | 4)
	if ram.u8(a + 0xd0) == 0 and ram.u8(b + 0xd0) == 0:
		if ram.s16(a + 0x122) != 0:
			var c: int = ram.s16(a + 0x122) - 1
			ram.w16(a + 0x122, c)
			ram.w16(a + 0x66, ram.u16(a + 0x66) & 0xffe7)
			if c < 0:
				ram.w16(a + 0x122, 0)
	else:
		ram.w16(a + 0x122, 0)
	if ram.s16(a + 0x76) == 0 or ram.s16(b + 0x16) != 0xe:
		ram.w32(a + 0x12d0, 0)
	else:
		ram.w32(a + 0x12d0, 1)
	ram.w8(a + 0x128a, 1 if ram.u8(a + 0x8a) == 0 and ram.u8(a + 0xdb) != 0 else 0)
	if ram.u8(a + 0xdb) != 0:
		ram.w16(a + 0x126, 0)
	if ram.s16(a + 0x126) < 1:
		ram.w16(a + 0x126, 0)
	else:
		ram.w16(a + 0x126, ram.s16(a + 0x126) - 1)
	if ram.s16(a + 0x126) == 0:
		ram.w16(a + 0x124, 0)
