extends RefCounted
# Pushes overlapping fighters apart so they cannot stand inside each other.
# Fields are read with ram.u8/u16/u32 at "actor + offset"; offsets are listed at the top of ram.gd.
const FMath := preload("res://scripts/combat/fmath.gd")
const SQRT_TABLE := 0x8004af40
const ATAN_TABLE := 0x800210c8
const PREV_POS := 0x8009e6f8
const DISTANCES := 0x8009e660
static func rnd(v: int) -> int:
	return v + 0xfff if v < 0 else v
static func lo16(ram, p: int, q: int) -> int:
	return FMath.s16((p & 0xffff) - (q & 0xffff))
static func angle4096(ram, p1: int, p2: int) -> int:
	if p1 == 0 and p2 == 0:
		return 0
	var t: int
	if p1 < 0:
		if p2 < 0:
			if -p1 < -p2:
				t = FMath.tdiv(p1 << 10, p2)
				return FMath.s16(0xc00 - (ram.u8(ATAN_TABLE + t) + FMath.s16(t >> 1)))
			t = FMath.tdiv(p2 << 10, p1)
			return FMath.s16(ram.u8(ATAN_TABLE + t) + FMath.s16(t >> 1) + 0x800)
		if -p1 < p2:
			t = FMath.tdiv(p1 * -0x400, p2)
			return FMath.s16(ram.u8(ATAN_TABLE + t) + FMath.s16(t >> 1) + 0x400)
		t = FMath.tdiv(p2 << 10, -p1)
		return FMath.s16(0x800 - (ram.u8(ATAN_TABLE + t) + FMath.s16(t >> 1)))
	if p2 < 0:
		if p1 < -p2:
			t = FMath.tdiv(p1 << 10, -p2)
			return FMath.s16(ram.u8(ATAN_TABLE + t) + FMath.s16(t >> 1) + 0xc00)
		t = FMath.tdiv(p2 * -0x400, p1)
		return FMath.s16(0x1000 - (ram.u8(ATAN_TABLE + t) + FMath.s16(t >> 1)))
	if p1 < p2:
		t = FMath.tdiv(p1 << 10, p2)
		return FMath.s16(0x400 - (ram.u8(ATAN_TABLE + t) + FMath.s16(t >> 1)))
	t = FMath.tdiv(p2 << 10, p1)
	return FMath.s16(ram.u8(ATAN_TABLE + t) + FMath.s16(t >> 1))
static func csn(ram, idx: int, which_cos: bool) -> int:
	return ram.s16((FMath.COS_TABLE if which_cos else FMath.SIN_TABLE) + (idx & 0xfff) * 2)
static func facing_index(ram, a: int) -> Array:
	var f: int = ram.s16(a + 0x0e)
	if f < 0:
		f += 0xf
	return [f >> 4, -(f >> 4) + 0x400]
static func push(ram, a: int, b: int) -> void:
	var pa: int = ram.u8(a + 0x1e)
	var pb: int = ram.u8(b + 0x1e)
	for o in [0x3e8, 0x3ec, 0x3f0]:
		ram.w32(a + o, 0)
		ram.w32(b + o, 0)
	var prev_a: int = PREV_POS + pa * 0x10
	var prev_b: int = PREV_POS + pb * 0x10
	var deepest := 0
	for i in 8:
		var sa: int = a + 0x324 + i * 0x10
		var ra: int = ram.u16(sa + 12)
		if ra == 0:
			continue
		for j in 8:
			var sb: int = b + 0x324 + j * 0x10
			var rb: int = ram.u16(sb + 12)
			if rb == 0:
				continue
			var r: int = (ra + rb) & 0xffff
			var dx: int = absi(lo16(ram, ram.s32(sb), ram.s32(sa)))
			if dx >= r:
				continue
			var dy: int = absi(lo16(ram, ram.s32(sb + 4), ram.s32(sa + 4)))
			if dy >= r:
				continue
			var dz: int = absi(lo16(ram, ram.s32(sb + 8), ram.s32(sa + 8)))
			if dz >= r:
				continue
			var dist: int = FMath.table_sqrt(ram, dx * dx + dy * dy + dz * dz, SQRT_TABLE)
			var pen: int = (r - dist) & 0xffff
			if FMath.s16(deepest) < FMath.s16(pen):
				deepest = pen
	var clinch := false
	var row_a: int = ram.u32(a + 0x54)
	var row_b: int = ram.u32(b + 0x54)
	var skip_clinch := false
	if ram.u8(row_a + 0x2d) != 0 and ram.u8(row_b + 0x2d) != 0:
		if FMath.s16(deepest) < 1:
			var dy2: int = ram.s32(a + 0xf6c) - ram.s32(b + 0xf6c)
			if dy2 < 0:
				if ram.s32(b + 0xf6c) - ram.s32(a + 0xf6c) > 299:
					skip_clinch = true
			elif dy2 > 299:
				skip_clinch = true
		if not skip_clinch:
			var ia: int = ram.s16(a + 0x0e)
			if ia < 0:
				ia += 0xf
			var ua: int = (0x400 - (ia >> 4)) & 0xfff
			var cxa: int = rnd(csn(ram, ua, true) * 200)
			var sza: int = rnd(csn(ram, ua, false) * 200)
			var ib: int = ram.s16(b + 0x0e)
			if ib < 0:
				ib += 0xf
			var ub: int = (0x400 - (ib >> 4)) & 0xfff
			var cxb: int = rnd(csn(ram, ub, true) * 200)
			var szb: int = rnd(csn(ram, ub, false) * 200)
			var ddx: int = (ram.s32(b + 0xf68) + (cxb >> 12)) - (ram.s32(a + 0xf68) + (cxa >> 12))
			var ddz: int = (ram.s32(b + 0xf70) + (szb >> 12)) - (ram.s32(a + 0xf70) + (sza >> 12))
			if absi(ddx) < 500 and absi(ddz) < 500:
				if (ram.s32(b) - ram.s32(a)) * ddx + (ram.s32(b + 8) - ram.s32(a + 8)) * ddz < 0:
					clinch = true
					if FMath.s16(deepest) < 400:
						deepest = 400
	if FMath.s16(deepest) <= 0:
		return
	var pen_s: int = FMath.s16(deepest)
	var ax: int = ram.s32(a + 0xf68)
	var ay: int = ram.s32(a + 0xf6c)
	var az: int = ram.s32(a + 0xf70)
	var bx: int = ram.s32(b + 0xf68)
	var by: int = ram.s32(b + 0xf6c)
	var bz: int = ram.s32(b + 0xf70)
	var da: Array = [lo16(ram, ax, ram.s32(prev_a + 4)), lo16(ram, ay, ram.s32(prev_a + 8)), lo16(ram, az, ram.s32(prev_a + 12))]
	var speed_a: int = FMath.table_sqrt(ram, da[0] * da[0] + da[1] * da[1] + da[2] * da[2], SQRT_TABLE) & 0xffff
	var db: Array = [lo16(ram, bx, ram.s32(prev_b + 4)), lo16(ram, by, ram.s32(prev_b + 8)), lo16(ram, bz, ram.s32(prev_b + 12))]
	var speed_b: int = FMath.table_sqrt(ram, db[0] * db[0] + db[1] * db[1] + db[2] * db[2], SQRT_TABLE) & 0xffff
	var fa: int = ram.s16(a + 0x0e)
	if fa < 0:
		fa += 0xf
	var dir_a: int = -(fa >> 4) + 0x400
	var ang: int = angle4096(ram, bx - ax, bz - az)
	var d1: int = (dir_a - FMath.s16(ang)) & 0xfff
	if d1 > 0x7ff:
		d1 = 0x1000 - d1
	if d1 > 0x400:
		dir_a = -(fa >> 4) + 0xc00
	var fb: int = ram.s16(b + 0x0e)
	if fb < 0:
		fb += 0xf
	var dir_b: int = -(fb >> 4) + 0x400
	var d2: int = (dir_b - FMath.s16(ang + 0x800)) & 0xfff
	if d2 > 0x7ff:
		d2 = 0x1000 - d2
	if d2 > 0x400:
		dir_b = -(fb >> 4) + 0xc00
	var bvx: int = rnd(csn(ram, dir_b, true) * speed_b)
	var bvz: int = rnd(csn(ram, dir_b, false) * speed_b)
	var avx: int = rnd(csn(ram, dir_a, true) * speed_a)
	var avz: int = rnd(csn(ram, dir_a, false) * speed_a)
	if speed_a == 0 and speed_b == 0:
		speed_a = 1
		speed_b = 1
	var total: int = speed_a + speed_b
	if total == 0:
		total = 1
	var share_a: int = FMath.tdiv(pen_s * speed_a, total)
	var share_b: int = FMath.tdiv(pen_s * speed_b, total)
	var sax: int = rnd(csn(ram, dir_a, true) * share_a)
	var saz: int = rnd(csn(ram, dir_a, false) * share_a)
	var new_ax: int = (ax + (bvx >> 12)) - (sax >> 12)
	var new_az: int = (az + (bvz >> 12)) - (saz >> 12)
	var sbx: int = rnd(csn(ram, dir_b, true) * share_b)
	var sbz: int = rnd(csn(ram, dir_b, false) * share_b)
	var new_bx: int = (bx + (avx >> 12)) - (sbx >> 12)
	var new_bz: int = (bz + (avz >> 12)) - (sbz >> 12)
	if not clinch:
		ram.w32(a + 0x3e8, (new_ax - ax) >> 1)
		ram.w32(a + 0x3ec, 0)
		ram.w32(a + 0x3f0, (new_az - az) >> 1)
		ram.w32(b + 0x3e8, (new_bx - bx) >> 1)
		ram.w32(b + 0x3ec, 0)
		ram.w32(b + 0x3f0, (new_bz - bz) >> 1)
	else:
		ram.w32(a + 0x3e8, new_ax - ax)
		ram.w32(a + 0x3ec, 0)
		ram.w32(a + 0x3f0, new_az - az)
		ram.w32(b + 0x3e8, new_bx - bx)
		ram.w32(b + 0x3ec, 0)
		ram.w32(b + 0x3f0, new_bz - bz)
static func apply(ram, a: int, b: int) -> void:
	var p: int = ram.u8(a + 0x1e)
	var q: int = ram.u8(b + 0x1e)
	if p > 1:
		p = 1 << (p - 1)
	if q > 1:
		q = 1 << (q - 1)
	if ram.u32(DISTANCES + (p + q) * 0x10) >= 0xbb9:
		return
	if (ram.u8(a + 0xd9) != 0 and ram.u8(b + 0xd9) != 0) or ram.u8(a + 0xc2) == 1 or ram.u8(b + 0xc2) == 1:
		return
	if ram.u8(a + 0xc3) == 0 or ram.u8(b + 0xc3) == 0:
		return
	push(ram, a, b)
	for pair in [[a, b], [b, a]]:
		var x: int = pair[0]
		var y: int = pair[1]
		if ram.u32(x + 0x3e8) != 0 or ram.u32(x + 0x3ec) != 0 or ram.u32(x + 0x3f0) != 0:
			ram.w8(x + 0xd5, 1)
			ram.w8(x + ram.u8(y + 0x1e) + 0xd6, 1)
			for k in 3:
				var v: int = ram.s32(x + 0x3e8 + k * 4)
				ram.w32(x + k * 4, ram.s32(x + k * 4) + v)
				ram.w32(x + 0xf68 + k * 4, ram.s32(x + 0xf68 + k * 4) + v)
