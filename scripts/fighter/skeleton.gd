extends RefCounted
const PART_ROWS := [0, 1, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24]
const PART_SLOTS := [0, 1, 11, 12, 13, 14, 15, 16, 17, 3, 4, 5, 6, 7, 8, 9, 10, 2, 18, 19, 20, 21]
const SECOND_MESH := [1, 2, 17]
const IDENTITY := [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]
const FACING := [13, 0, 4096, 0, 4096, 0, -4096, 0, 13]
const OFFSET_TABLES := [0x80096ECC, 0x80096ED8, 0x80096EE4, 0x80096EF0, 0x80096EFC, 0x80096F08, 0x80096F14, 0x80096F20]
var sin_table: PackedInt32Array
var sqrt_table: PackedInt32Array
var order: Array = []
var fixed: Array = []
var offsets := {}
func _init(exe) -> void:
	sin_table = exe.s16s(0x8001E8C4, 5120)
	sqrt_table = exe.s16s(0x80098D08, 512)
	for k in 10:
		order.append(exe.u8(0x8001A330 + k))
	fixed = Array(exe.s16s(0x80096EAC, 9))
	for a in OFFSET_TABLES:
		offsets[a] = Array(exe.s32s(a, 3))
func _s16(v: int) -> int:
	return ((v + 0x8000) & 0xFFFF) - 0x8000
func _s32(v: int) -> int:
	return ((v + 0x80000000) & 0xFFFFFFFF) - 0x80000000
func _clamp16(v: int) -> int:
	return clampi(v, -32768, 32767)
func _sn(i: int) -> int:
	return sin_table[i >> 1]
func _cs(i: int) -> int:
	return sin_table[(i >> 1) + 1024]
func _gpf(ir0: int, a: int, b: int, c: int) -> Array:
	return [_clamp16(ir0 * a >> 12), _clamp16(ir0 * b >> 12), _clamp16(ir0 * c >> 12)]
func _lzcr(x: int) -> int:
	x &= 0xFFFFFFFF
	if x & 0x80000000:
		x = ~x & 0xFFFFFFFF
	var n := 0
	while x != 0:
		x >>= 1
		n += 1
	return 32 - n
func mat_mul(p: Array, l: Array) -> Array:
	var out := []
	for i in 3:
		for j in 3:
			out.append(_clamp16((p[i * 3] * l[j] + p[i * 3 + 1] * l[3 + j] + p[i * 3 + 2] * l[6 + j]) >> 12))
	return out
func rotate(p: Array, v: Array) -> Array:
	var out := []
	for i in 3:
		out.append((p[i * 3] * v[0] + p[i * 3 + 1] * v[1] + p[i * 3 + 2] * v[2]) >> 12)
	return out
func rotate_big(p: Array, v: Array) -> Array:
	var hi := []
	var lo := []
	for x in v:
		var sgn := 1 if x >= 0 else -1
		hi.append(_clamp16((absi(x) >> 15) * sgn))
		lo.append(_clamp16((absi(x) & 0x7FFF) * sgn))
	var out := []
	for i in 3:
		var big: int = p[i * 3] * hi[0] + p[i * 3 + 1] * hi[1] + p[i * 3 + 2] * hi[2]
		var small: int = (p[i * 3] * lo[0] + p[i * 3 + 1] * lo[1] + p[i * 3 + 2] * lo[2]) >> 12
		out.append(small + big * 8)
	return out
func euler(p1: int, p2: int, p3: int) -> Array:
	var i8 := p1 >> 3 & 0x1FFE
	var i12 := p3 >> 3 & 0x1FFE
	var i10 := p2 >> 3 & 0x1FFE
	var c3 := _cs(i12)
	var c1 := _cs(i8)
	var c2 := _cs(i10)
	var s3 := _sn(i12)
	var s1 := _sn(i8)
	var iv4 := c1 * c3 >> 12
	var g1 := _gpf(s1, c3, s3, c2)
	var s2 := _sn(i10)
	var iv7 := c1 * s3 >> 12
	var g2 := _gpf(s2, g1[0], g1[1], iv4)
	var g3 := _gpf(c2, c3, s3, c1)
	return [_s16(g3[0]), _s16(g2[0] - iv7), _s16(g1[1] + g2[2]), _s16(g3[1]), _s16(iv4 + g2[1]), _s16((iv7 * s2 >> 12) - g1[0]), _s16(-s2), _s16(g1[2]), _s16(g3[2])]
func compose(parent: Array, local: Array, offset: Array) -> Array:
	var v := []
	for x in offset:
		v.append(_s16(x))
	var r := rotate(parent[0], v)
	return [mat_mul(parent[0], local), [parent[1][0] + r[0], parent[1][1] + r[1], parent[1][2] + r[2]]]
func isqrt(x: int) -> int:
	var z := _lzcr(x)
	if z == 32:
		return 0
	z &= ~1
	var y := x >> (0x18 - z) if z - 0x18 < 0 else x << (z - 0x18)
	return ((sqrt_table[y - 0x40] << ((0x1F - z) >> 1)) & 0xFFFFFFFF) >> 12
func _twist(m: Array, a: int, b: int) -> void:
	var x0: int = m[0]
	var x1: int = m[1]
	var x3: int = m[3]
	var x4: int = m[4]
	var x6: int = m[6]
	var x7: int = m[7]
	m[0] = _s16(x0 * b + x1 * a >> 12)
	m[3] = _s16(x3 * b + x4 * a >> 12)
	m[1] = _s16(-x0 * a + x1 * b >> 12)
	m[4] = _s16(-x3 * a + x4 * b >> 12)
	m[6] = _s16(x6 * b + x7 * a >> 12)
	m[7] = _s16(-x6 * a + x7 * b >> 12)
func aim(goal: Array, angle: int, arm: bool) -> Array:
	var x: int = goal[0]
	var y: int = goal[1]
	var z: int = goal[2]
	var d2 := x * x + y * y + z * z
	if d2 == 0:
		return []
	var dist := isqrt(d2)
	var inv := 0x400000 / dist
	var ax := x * inv >> 10
	var ay := y * inv >> 10
	var az := z * inv >> 10
	var a13 := ax + 0x1000
	var a10 := 0
	var a5 := 0x1000
	if a13 == 0:
		a13 = -0x800
		a10 = y * inv >> 11
		a5 = -0x1000
	elif a13 < 0x2000:
		a13 = -(0x1000000 / a13)
		a10 = a13 * ay >> 12
	else:
		a13 = -0x800
		a10 = -ay >> 1
	var a4 := (a10 * ay >> 12) + a5
	a13 = a13 * az >> 12
	var u := angle >> 3 & 0x1FFE
	var c := _cs(u)
	var s := _sn(u)
	var a6 := a10 * (a5 + ax) >> 12
	var a5b := a13 * (a5 + ax) >> 12
	var a14 := a13 * ay >> 12
	var a11 := a10 * az >> 12
	var a12 := (a13 * az >> 12) + 0x1000
	var m1 := [_s16(ax), _s16(c * a6 + s * a5b >> 12), _s16(-s * a6 + c * a5b >> 12), _s16(ay), _s16(c * a4 + s * a14 >> 12), _s16(-s * a4 + c * a14 >> 12), _s16(az), _s16(c * a11 + s * a12 >> 12), _s16(-s * a11 + c * a12 >> 12)]
	var hi := 0
	var lo := 0
	if not arm:
		if dist > 0x37B:
			return [m1, null]
		if dist < 3:
			return [m1, 1]
		var t := inv * 0x6F8 >> 11
		hi = (dist * 0x800 + t) * 0x92
		lo = (dist * 0x800 - t) * 0x93
	else:
		if dist > 0x215:
			return [m1, null]
		if dist < 0x47:
			return [m1, 1]
		var t2 := inv * 0x9204 >> 11
		hi = (dist * 0x800 + t2) * 0xD9
		lo = (dist * 0x800 - t2) * 0x11A
	hi = _s32(hi) >> 16
	lo = _s32(lo) >> 16
	var r12 := 0
	if hi < 0x1001:
		if hi < -0x1000:
			hi = -0x1000
		else:
			r12 = isqrt(0x1000000 - hi * hi)
			r12 = r12 if arm else -r12
	else:
		hi = 0x1000
	_twist(m1, _s16(r12), _s16(hi))
	var r13 := 0
	if lo < 0x1001:
		if lo < -0x1000:
			lo = -0x1000
		elif not arm:
			r13 = r12 * -0x1012 >> 12
		else:
			r13 = r12 * -0x14D4 >> 12
	else:
		lo = 0x1000
	var a := hi * lo + r12 * r13
	if a < 0:
		a += 0xFFF
	var b := -r12 * lo + hi * r13
	if b < 0:
		b += 0xFFF
	var sv := _s16(b >> 12)
	return [m1, [_s16(a >> 12), _s16(-sv), 0, sv, _s16(a >> 12), 0, 0, 0, 0x1000]]
func locals(pose: PackedInt32Array) -> Array:
	var loc := []
	for i in 32:
		loc.append([0, 0, 0, 0, 0, 0, 0, 0, 0])
	for k in 10:
		loc[order[k]] = euler(pose[19 + 3 * k], pose[20 + 3 * k], pose[21 + 3 * k])
	for s in [2, 3, 7]:
		loc[s] = mat_mul(loc[s], fixed)
	var root := [loc[0], [pose[0], pose[1], pose[2]]]
	var r1 := compose(root, loc[1], offsets[0x80096ECC])
	var r2 := compose(r1, loc[3], offsets[0x80096ED8])
	var r3 := compose(r1, loc[7], offsets[0x80096EE4])
	var r4 := compose(root, loc[11], offsets[0x80096EF0])
	var goals := []
	var refs := [[r2, 0x80096EFC, 3], [r3, 0x80096F08, 6], [r4, 0x80096F14, 9], [r4, 0x80096F20, 12]]
	for r in refs:
		var m: Array = r[0][0]
		var rt := [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]
		var d := []
		for i in 3:
			d.append(pose[r[2] + i] - r[0][1][i])
		var v := rotate_big(rt, d)
		goals.append([v[0] + offsets[r[1]][0], v[1] + offsets[r[1]][1], v[2] + offsets[r[1]][2]])
	var limbs := [[4, 15, true], [8, 16, true], [12, 17, false], [15, 18, false]]
	for k in 4:
		var res := aim(goals[k], pose[limbs[k][1]], limbs[k][2])
		if res.is_empty():
			continue
		loc[limbs[k][0]] = res[0]
		if res[1] is Array:
			loc[limbs[k][0] + 1] = res[1]
	return loc
func world(model: PackedByteArray, pose: PackedInt32Array, root_matrix: Array, root_pos: Array, extra: Dictionary = {}) -> Dictionary:
	var info := {}
	for part in PART_ROWS.size():
		var r: int = PART_ROWS[part]
		if r >= model.decode_u32(0):
			continue
		var base := 24 + r * 56
		info[PART_SLOTS[part]] = [model.decode_s32(base + 24), [model.decode_s32(base + 12), model.decode_s32(base + 16), -model.decode_s32(base + 20)]]
	var loc := locals(pose)
	for slot in extra:
		loc[slot] = extra[slot]
	var result := {}
	var root := [root_matrix, root_pos]
	for s in info:
		_solve(s, info, loc, result, root)
	return result
func _solve(slot: int, info: Dictionary, loc: Array, result: Dictionary, root: Array) -> Array:
	if result.has(slot):
		return result[slot]
	var parent_part: int = info[slot][0]
	var parent: Array = root if parent_part < 0 else _solve(PART_SLOTS[parent_part], info, loc, result, root)
	var m: Array = loc[slot] if slot < loc.size() else IDENTITY
	var blank := true
	for v in m:
		if v != 0:
			blank = false
	result[slot] = compose(parent, IDENTITY if blank else m, info[slot][1])
	return result[slot]
