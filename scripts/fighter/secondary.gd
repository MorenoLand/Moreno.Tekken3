extends RefCounted
# Secondary parts (hair, feathers, hakama, ponytails): parts 0x12..0x15, joint slots 18..21, rows 21..24 of the model.
# Each part swings like a pendulum hung from its parent joint. The state lives in RAM like the original:
#   actor+0x1c fighter id f (2*character+1, selects the parameter tables)   +0x129e+idx*8 three rest angles (s16)
#   +0x1360+idx*2 init flag   +0x136c+idx*4 parameter pointer (table 0x8009623c, f*6+idx)
#   +0x8f4+slot*0x44 joint block: 3x3 s16 matrix, translation s32 at +0x14/+0x18/+0x1c, parent block pointer at +0x40
#   +0xf74+slot*0x20 local block: 3x3 s16 matrix, pivot s32 at +0x14/+0x18/+0x1c (pivot x, y, -z of the model row)
# The parameter record is 12 s16: 0 type (constants at 0x80095d10+type*0x18), 2/3 blend weights, 4 arm length,
# 5 gravity share, 6 mode (1 = follow the joint in 7), 7 joint slot, 8..10 attach vector, 11 type of the joint pull.
const BLOCKS := 0x8f4
const BLOCK_SIZE := 0x44
const LOCALS := 0xf74
const LOCAL_SIZE := 0x20
const PARAMS := 0x8009623c
const NO_PARAMS := 0x80095f48
const TYPES := 0x80095d10
const ATAN := 0x80098e88
const SQRT_B := 0x8004af40
const NORMAL := 0x8001a194
const FIRST := 18
const COUNT := 4
var ram
var sk
func _init(ram_, skeleton_) -> void:
	ram = ram_
	sk = skeleton_
func setup(a: int, f: int, model: PackedByteArray) -> void:
	ram.w16(a + 0x1c, f)
	for idx in COUNT:
		var part := FIRST + idx
		var row: int = sk.PART_ROWS[part]
		ram.w16(a + 0x1360 + idx * 2, 0)
		ram.w32(a + 0x136c + idx * 4, NO_PARAMS)
		if f < 0 or row >= model.decode_u32(0):
			continue
		ram.w32(a + 0x136c + idx * 4, ram.u32(PARAMS + (f * 6 + idx) * 4))
		var base := 24 + row * 56
		var parent_part: int = model.decode_s32(base + 24)
		if parent_part < 0:
			ram.w32(a + 0x136c + idx * 4, NO_PARAMS)
			continue
		ram.w32(a + BLOCKS + (FIRST + idx) * BLOCK_SIZE + 0x40, a + BLOCKS + sk.PART_SLOTS[parent_part] * BLOCK_SIZE)
		ram.w16(a + 0x129e + idx * 8, model.decode_s32(base + 28))
		ram.w16(a + 0x12a0 + idx * 8, model.decode_s32(base + 32))
		ram.w16(a + 0x12a2 + idx * 8, model.decode_s32(base + 36))
		var l: int = a + LOCALS + (FIRST + idx) * LOCAL_SIZE
		ram.w32(l + 0x14, model.decode_s32(base + 12))
		ram.w32(l + 0x18, model.decode_s32(base + 16))
		ram.w32(l + 0x1c, -model.decode_s32(base + 20))
func active(a: int, idx: int) -> bool:
	var p: int = ram.u32(a + 0x136c + idx * 4)
	return p != 0 and p != NO_PARAMS
func local_matrix(a: int, idx: int) -> Array:
	var l: int = a + LOCALS + (FIRST + idx) * LOCAL_SIZE
	var m := []
	for i in 9:
		m.append(ram.s16(l + i * 2))
	return m
func _read_block(a: int, slot: int) -> Array:
	var b: int = a + BLOCKS + slot * BLOCK_SIZE
	var m := []
	for i in 9:
		m.append(ram.s16(b + i * 2))
	return [m, [ram.s32(b + 0x14), ram.s32(b + 0x18), ram.s32(b + 0x1c)]]
func _write_block(a: int, slot: int, block: Array) -> void:
	var b: int = a + BLOCKS + slot * BLOCK_SIZE
	for i in 9:
		ram.w16(b + i * 2, block[0][i])
	for i in 3:
		ram.w32(b + 0x14 + i * 4, block[1][i])
func _transpose(m: Array) -> Array:
	return [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]
func _atan(p1: int, p2: int) -> int:
	var neg2 := p2 < 0
	if neg2:
		p2 = -p2
	var neg1 := p1 < 0
	if neg1:
		p1 = -p1
	if p1 == 0 and p2 == 0:
		return 0
	var r: int
	if p1 < p2:
		var q: int = (p1 << 10) / p2 if (p1 & 0x7fe00000) == 0 else p1 / (p2 >> 10)
		r = ram.s16(ATAN + q * 2)
	else:
		var q2: int = (p2 << 10) / p1 if (p2 & 0x7fe00000) == 0 else p2 / (p1 >> 10)
		r = 0x400 - ram.s16(ATAN + q2 * 2)
	if neg2:
		r = 0x800 - r
	if neg1:
		r = -r
	return r
func _isqrt_b(x: int) -> int:
	var z: int = sk._lzcr(x)
	if z == 32:
		return 0
	z &= ~1
	var y: int = x >> (0x18 - z) if z - 0x18 < 0 else x << (z - 0x18)
	return ((ram.s16(SQRT_B + (y - 0x40) * 2) << ((0x1F - z) >> 1)) & 0xFFFFFFFF) >> 12
func _normalize(v: Array) -> Array:
	var x: int = sk._s16(v[0])
	var y: int = sk._s16(v[1])
	var z: int = sk._s16(v[2])
	var sum: int = sk._s32(x * x + y * y + z * z)
	var ev: int = 0 if sum < 0 else sk._lzcr(sum) & 0x1e
	var shift: int = (0x1f - ev) >> 1
	var t: int = ev - 0x18
	var scaled: int = sum >> -t if t < 0 else sk._s32(sum << t)
	var gain: int = ram.s16(NORMAL + (scaled - 0x40) * 2)
	return [(gain * x) >> shift, (gain * y) >> shift, (gain * z) >> shift]
func _const(type: int, off: int) -> int:
	return ram.s32(TYPES + type * 0x18 + off)
func _follow(a: int, p: int, f: int, bt: Array, pivot_world: Array) -> Array:
	var slot: int = ram.s16(p + 14)
	var ref := _read_block(a, slot)
	var v := [ram.s16(p + 16), ram.s16(p + 18), ram.s16(p + 20)]
	v = sk.rotate_big(ref[0], v)
	for i in 3:
		v[i] = v[i] + ref[1][i] - pivot_world[i]
	v = sk.rotate_big(bt, v)
	var type: int = ram.s16(p)
	var flag := 0
	if f == 0x26 and v[0] < 0:
		type = 8
		flag = 1
	var swing: int = _atan(_const(type, 0x10) * v[2], _const(type, 0x14) * v[0])
	var reach: int = _isqrt_b(v[0] * v[0] + v[2] * v[2])
	var lift: int = _atan(_const(type, 0x18) * v[1], _const(type, 0x1c) * reach)
	return [swing * _const(type, 0x20), lift * _const(type, 0x24), flag]
func _toward_hands(a: int, bt: Array, w: Array) -> Array:
	var t13: Array = _read_block(a, 13)[1]
	var t16: Array = _read_block(a, 16)[1]
	var t18: Array = _read_block(a, FIRST)[1]
	var d := [t16[0] - t13[0], t16[1] - t13[1], t16[2] - t13[2]]
	var sum: int = d[0] * d[0] + d[1] * d[1] + d[2] * d[2]
	if sum <= 0x3fff:
		return w
	var dist: int = _isqrt_b(sum)
	if dist == 0:
		dist = 1
	var q := []
	for i in 3:
		q.append(((d[i] << 7) / dist) + t13[i])
	q[2] += 0x40
	for i in 3:
		q[i] -= t18[i]
	return _normalize(sk.rotate_big(bt, q))
func step(a: int, idx: int) -> bool:
	var p: int = ram.u32(a + 0x136c + idx * 4)
	var f: int = ram.s16(a + 0x1c)
	if ram.u32(0x80095494) != 0 or ram.u32(0x80095468) != 0:
		return false
	if p == NO_PARAMS or p == 0:
		return false
	if f - 0x20 >= 0 and f - 0x20 < 2 and idx < 2:
		return false
	var slot := FIRST + idx
	var l: int = a + LOCALS + slot * LOCAL_SIZE
	var rest: Array = sk.euler(ram.s16(a + 0x129e + idx * 8), ram.s16(a + 0x12a0 + idx * 8), ram.s16(a + 0x12a2 + idx * 8))
	if ram.s16(a + 0x1360 + idx * 2) == 0:
		ram.w16(a + 0x1360 + idx * 2, 1)
		for i in 9:
			ram.w16(l + i * 2, rest[i])
		return true
	var parent := _read_block(a, _parent_slot(a, slot))
	var own := _read_block(a, slot)
	var composed: Array = sk.mat_mul(parent[0], rest)
	var bt := _transpose(composed)
	var arm: int = ram.s16(p + 8)
	var q: Array = sk.rotate(own[0], [sk._s16(arm), sk._s16(arm >> 16), 0])
	for i in 3:
		q[i] += own[1][i]
	var pivot := [sk._s16(ram.s32(l + 0x14)), sk._s16(ram.s32(l + 0x18)), sk._s16(ram.s32(l + 0x1c))]
	var hang: Array = sk.rotate(parent[0], pivot)
	for i in 3:
		hang[i] += parent[1][i]
	var grounded := false
	if q[1] >= 0:
		grounded = true
		q[1] = 0
	var d := [q[0] - hang[0], q[1] - hang[1], q[2] - hang[2]]
	var n := _normalize(sk.rotate_big(bt, d))
	var g := [0, 0, 0]
	if not grounded:
		var share: int = ram.s16(p + 10) >> 4
		g = sk.rotate(bt, [share, (0x100 - ram.s16(p + 10)) * 0x10, share])
		for i in 3:
			g[i] = sk._clamp16(g[i])
	var w := []
	var keep: int = ram.s16(p + 4)
	var pull: int = ram.s16(p + 6)
	for k in 3:
		var v: int = n[k] * keep + g[k] * pull
		if v < 0:
			v += 0xff
		w.append(v >> 8)
	w[0] += (0x100 - (keep + pull)) * 0x10
	var mode: int = ram.s16(p + 12)
	var type: int = ram.s16(p)
	var stored_swing := 0
	var stored_lift := 0
	var flagged := 0
	if mode == 1:
		var st := _follow(a, p, f, bt, hang)
		stored_swing = st[0]
		stored_lift = st[1]
		flagged = st[2]
	elif (f == 0x24 or f == 0x29) and idx == 0:
		w = _toward_hands(a, bt, w)
	if f == 0x26 and flagged != 0:
		type = 2
	var swing: int = _atan(_const(type, 0x10) * w[2], _const(type, 0x14) * w[0])
	var reach: int = sk.isqrt(w[0] * w[0] + w[2] * w[2])
	var lift: int = _atan(_const(type, 0x18) * w[1], _const(type, 0x1c) * reach)
	swing *= _const(type, 0x20)
	lift *= _const(type, 0x24)
	if mode == 1:
		var joint_type: int = ram.s16(p + 22)
		var k34: int = ram.s16(TYPES + joint_type * 0x18 + 0x24)
		var k30: int = ram.s16(TYPES + joint_type * 0x18 + 0x20)
		if k34 * stored_swing + k30 * stored_lift < k34 * swing + k30 * lift:
			swing = stored_swing
			lift = stored_lift
	var pitch: int = sk._s16(swing << 4)
	lift = lift << 4
	if f == 0xe and idx == 0:
		pitch = 0
	if f == 0xf and (idx == 1 or idx == 2):
		pitch = 0
	if f == 0x1b and idx == 2:
		pitch = 0
	if f == 0x26:
		if idx == 0:
			if lift < 0x800:
				lift = 0x800
		elif idx == 3:
			pitch = 0
	var roll: int = sk._s16(lift)
	var limit := -1
	if f == 0x24 or f == 0x29:
		if idx < 4:
			limit = 0x80095d14
	elif f == 0x1a:
		limit = 0x80095d10
	if limit >= 0:
		var hi: int = ram.s16(limit)
		var lo: int = ram.s16(limit + 2)
		if hi < pitch or pitch < lo:
			pitch = hi if hi < pitch else lo
		if not (roll <= hi and lo <= roll):
			roll = hi if roll > hi else lo
	var out: Array = sk.mat_mul(rest, sk.euler(0, pitch, roll))
	for i in 9:
		ram.w16(l + i * 2, out[i])
	return true
func _parent_slot(a: int, slot: int) -> int:
	return (ram.u32(a + BLOCKS + slot * BLOCK_SIZE + 0x40) - a - BLOCKS) / BLOCK_SIZE
func compose(a: int, idx: int) -> void:
	var slot := FIRST + idx
	var l: int = a + LOCALS + slot * LOCAL_SIZE
	var parent := _read_block(a, _parent_slot(a, slot))
	var local := local_matrix(a, idx)
	var pivot := [ram.s32(l + 0x14), ram.s32(l + 0x18), ram.s32(l + 0x1c)]
	_write_block(a, slot, sk.compose(parent, local, pivot))
