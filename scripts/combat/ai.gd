extends RefCounted
# Computer opponent: port of FUN_80059890 and its helpers. All AI state lives in RAM at the original addresses.
# Per slot state block S = 0x8009f318 + slot * 0x330 (slot = byte at actor + 0x1886); offsets used below are relative to S:
#   +0x04 pad word produced this frame   +0x06 pad word of the previous frame   +0x08 pointer to the rest of a queued input sequence
#   +0x0c move row table                 +0x10 opponent actor                   +0x14 threat zone 0..5 (from the distance bands)
#   +0x18 distance zone 1..5             +0x1c distance                         +0x58 move row the candidate list was built from
#   +0x64 condition bits                 +0x70 candidate count                  +0x72 candidates marked this frame
#   +0x74/+0x78 character hooks          +0x238.. difficulty parameters (percent-like thresholds against 12-bit rolls)
# Candidate list: 12-byte records at 0x8009f978 (+0 move row, +4 cancel entry, +8 mark: 0 free, 1 taken, 0xffff excluded).
# Fields are read with ram.u8/u16/u32 at "actor + offset"; offsets are listed at the top of ram.gd.
const Commands := preload("res://scripts/combat/commands.gd")
const STATES := 0x8009f318
const STATE_SIZE := 0x330
const LIST := 0x8009f978
const LIST_COUNT := 180
const SCRATCH := 0x800a01e8
const SHARED_ENTRIES := 0x80017c78
const REACH := 0x80098230
const RNG := 0x800adca0
const RNG_HW := 0x800a39b8
const SELF_PTR := 0x800afa5c
const OPP_PTR := 0x800a867c
const MOVE_TABLES := 0x8009f2e8
const DEMO_FLAG := 0x800aded4
const DEMO_SKIP := 0x8009f2fc
const FRAME_COUNTER := 0x800afa4c
const LEVEL := 0x800ae208
const STAGE_LEVEL := 0x800ae211
const END := 0xc000
const SHARED := 0xc00c
var ram
var S := 0
var A := 0
var B := 0
var row_a := 0
var row_b := 0
var a_start := 0
var a_end := 0
var fa := 0
var b_start := 0
var b_end := 0
var fb := 0
func _init(r) -> void:
	ram = r
func h(o: int) -> int:
	return ram.s16(S + o)
func hu(o: int) -> int:
	return ram.u16(S + o)
func w(o: int) -> int:
	return ram.s32(S + o)
func wu(o: int) -> int:
	return ram.u32(S + o)
func b(o: int) -> int:
	return ram.u8(S + o)
func sh(o: int, v: int) -> void:
	ram.w16(S + o, v)
func sw(o: int, v: int) -> void:
	ram.w32(S + o, v)
func sb(o: int, v: int) -> void:
	ram.w8(S + o, v)
func s16w(v: int) -> int:
	return ((v + 0x8000) & 0xffff) - 0x8000
func roll(mask: int) -> int:
	var s: int = ram.u32(RNG)
	ram.w32(RNG, s * 5 + 3)
	return s & mask
func hw_rand() -> int:
	var s: int = (ram.u32(RNG_HW) * 0x41c64e6d + 0x3039) & 0xffffffff
	ram.w32(RNG_HW, s)
	return s >> 16 & 0x7fff
func roll_scaled(n: int) -> int:
	var r: int = hw_rand()
	var s: int = ram.u32(RNG)
	ram.w32(RNG, s * 5 + 3)
	return ((r + s) & 0x7fff) * n >> 15
func cmd_pad(v: int) -> int:
	var p: int = 0x80 if v & 0x100 else 0
	if v & 0x200:
		p |= 0x10
	if v & 0x400:
		p |= 0x40
	if v & 0x800:
		p |= 0x20
	return p | ram.u16(0x8002301c + (v & 0xf) * 2)
func stance_ok(code: int) -> bool:
	if code == 0:
		return true
	if code < 0x18:
		return ram.s16(A + 0x16) == code - 1
	if code < 0x2f:
		return ram.s16(A + 0x16) != code - 0x18
	if code < 0x46:
		return ram.s16(B + 0x16) == code - 0x2f
	if code <= 0x5c:
		return ram.s16(A + 0x18) == code - 0x46
	if code > 0x73:
		return false
	return ram.s16(A + 0x18) != code - 0x5d
func cond_ok(entry: int) -> bool:
	var code: int = ram.u8(entry + 3)
	var f: int = wu(0x64)
	match code:
		0:
			return true
		0x24:
			return (f & 1) != 0
		0x25:
			return (f & 2) != 0
		0x26:
			return (f & 4) != 0
		0x30:
			return (f & 8) != 0
		0x27:
			return (f & 0x10) != 0
	return Commands.condition(ram, entry, A, B)
func entries(row: int) -> Array:
	var out: Array = []
	var p: int = ram.u32(row + 0xc)
	while ram.s16(p) != -0x4000:
		if ram.s16(p) == -0x3ff4:
			var base: int = SHARED_ENTRIES + ram.u16(p + 6) * 12
			for j in ram.u8(p + 0xb):
				out.append(base + j * 12)
		else:
			out.append(p)
		p += 12
	return out
func reach(row: int, zone: int) -> bool:
	var t: int = ram.u32(row + 8) & 0xffff0000
	if (ram.u32(row + 8) & 0x1c0000) == 0:
		t |= 0xc0000
	return (t & ram.u32(REACH + zone * 4)) != 0
func rec_row(i: int) -> int:
	return ram.u32(LIST + i * 12)
func rec_entry(i: int) -> int:
	return ram.u32(LIST + i * 12 + 4)
func rec_mark(i: int) -> int:
	return ram.s16(LIST + i * 12 + 8)
func set_mark(i: int, v: int) -> void:
	ram.w16(LIST + i * 12 + 8, v)
func build(skip_default: bool) -> int:
	var frame: int = ram.s16(A + 0x58)
	var table: int = wu(0xc)
	var n: int = 0
	var full: bool = false
	var end: int = ram.u32(wu(0x58) + 0xc)
	var p: int = end
	while ram.u16(p) != END and not full:
		if ram.u16(p) == SHARED:
			var base: int = SHARED_ENTRIES + ram.u16(p + 6) * 12
			for j in ram.u8(p + 0xb):
				var e: int = base + j * 12
				if frame < ram.u8(e + 9) or ram.u8(e + 10) < frame:
					continue
				if not stance_ok(ram.u8(e + 2)) or not cond_ok(e):
					continue
				if n < LIST_COUNT:
					ram.w32(LIST + n * 12, ram.u32(table + ram.u16(e + 6) * 4))
					ram.w32(LIST + n * 12 + 4, e)
					ram.w16(LIST + n * 12 + 8, 0)
					n += 1
				else:
					full = true
			if full:
				break
		else:
			if frame >= ram.u8(p + 9) and frame <= ram.u8(p + 10) and stance_ok(ram.u8(p + 2)) and cond_ok(p):
				if n >= LIST_COUNT:
					break
				ram.w32(LIST + n * 12, ram.u32(table + ram.u16(p + 6) * 4))
				ram.w32(LIST + n * 12 + 4, p)
				ram.w16(LIST + n * 12 + 8, 0)
				n += 1
		p += 12
	end = p
	if not skip_default:
		if ram.u8(end + 9) <= frame and frame <= ram.u8(end + 10):
			var target: int = ram.u32(table + ram.u16(end + 6) * 4)
			if target != ram.u32(A + 0x54) and ram.u16(ram.u32(target + 0xc)) != END:
				n = build_default(ram.u32(target + 0xc), n, table, frame)
	for i in n:
		if (ram.u32(rec_row(i) + 4) & 0x800000) != 0:
			set_mark(i, 0xffff)
	if wu(0x7c) != 0:
		sh(0x70, n)
		cull_listed()
	return n
func build_default(list: int, n: int, table: int, frame: int) -> int:
	var p: int = list
	var full: bool = false
	while ram.u16(p) != END and not full:
		if ram.u16(p) == SHARED:
			var base: int = SHARED_ENTRIES + ram.u16(p + 6) * 12
			for j in ram.u8(p + 0xb):
				var e: int = base + j * 12
				if ram.u8(e + 9) >= 2 or ram.u8(e + 10) < frame:
					continue
				if not stance_ok(ram.u8(e + 2)) or not default_cond(e, e):
					continue
				if n < LIST_COUNT:
					ram.w32(LIST + n * 12, ram.u32(table + ram.u16(e + 6) * 4))
					ram.w32(LIST + n * 12 + 4, e)
					ram.w16(LIST + n * 12 + 8, 0)
					n += 1
				else:
					full = true
		else:
			if ram.u8(p + 9) < 2 and frame <= ram.u8(p + 10) and stance_ok(ram.u8(p + 2)) and default_cond(p, list):
				if n >= LIST_COUNT:
					break
				ram.w32(LIST + n * 12, ram.u32(table + ram.u16(p + 6) * 4))
				ram.w32(LIST + n * 12 + 4, p)
				ram.w16(LIST + n * 12 + 8, 0)
				n += 1
		p += 12
	return n
func default_cond(entry: int, subject: int) -> bool:
	var code: int = ram.u8(entry + 3)
	var f: int = wu(0x64)
	if code == 0 or code == 0x26 or code == 0x30 or code == 0x27:
		return true
	if code == 0x24:
		return (f & 1) != 0
	if code == 0x25:
		return (f & 2) != 0
	return Commands.condition(ram, subject, A, B)
func mark(pred: Callable) -> int:
	var got: int = 0
	for i in h(0x70):
		if rec_mark(i) == 0 and pred.call(rec_row(i), rec_entry(i)):
			set_mark(i, 1)
			got += 1
	sh(0x72, h(0x72) + got)
	return got
func p_572a4(r: int, e: int) -> bool:
	var f4: int = ram.u32(r + 4)
	var f8: int = ram.u32(r + 8)
	if not (ram.u8(r + 0x19) == 0 or (f4 & 0x80000) != 0 or (f8 & 0x200000) != 0):
		return false
	if ram.s16(e) == -0x3fff or (f4 & 0x80000) != 0:
		return true
	if ram.u8(r + 0x2d) == 0 or (f8 & 0x400000) != 0 or (f4 & 0x20000) != 0:
		return false
	return reach(r, w(0x14)) or (f4 & 0x10000) != 0
func p_573f4(r: int, e: int) -> bool:
	var f4: int = ram.u32(r + 4)
	var f8: int = ram.u32(r + 8)
	if not (ram.u8(r + 0x19) == 0 or (f4 & 0x80000) != 0 or (f8 & 0x200000) != 0):
		return false
	if ram.u8(r + 0x2d) == 0 or (f8 & 0xffff) == 0x412 or (f8 & 0xffff) == 0x706:
		return false
	if (f8 & 0x400000) != 0 or (f4 & 0x20000) != 0:
		return false
	return reach(r, w(0x14)) or (f4 & 0x10000) != 0
func p_57538(r: int, e: int) -> bool:
	var f4: int = ram.u32(r + 4)
	var f8: int = ram.u32(r + 8)
	if ram.s16(r + 0x14) <= 0 or ram.u8(r + 0x2d) == 0 or ram.u8(r + 0x19) != 0 or (f8 & 0x400000) != 0 or ram.u8(r + 0x2d) >= 14 or (f4 & 0x20000) != 0:
		return false
	return reach(r, w(0x14)) or (f4 & 0x10000) != 0
func p_5766c(r: int, e: int) -> bool:
	var f4: int = ram.u32(r + 4)
	var f8: int = ram.u32(r + 8)
	if (f4 & 0x20000) != 0 or ram.u8(r + 0x2d) == 0 or (f8 & 0x400000) != 0 or ram.u8(r + 0x19) != 0 or ram.s16(r + 0x14) < 0:
		return false
	if not reach(r, w(0x14)):
		return false
	var s: int = wu(0x230)
	var id: int = f8 & 0xffff
	if s & 2:
		return id != 0x412
	if s & 1:
		return id != 0x412 and id != 0x10f
	if s & 4:
		return id != 0x412 and id != 0x217
	return true
func p_577dc(r: int, e: int) -> bool:
	return p_stance_pick(r, false)
func p_579a0(r: int, e: int) -> bool:
	return p_stance_pick(r, true)
func p_stance_pick(r: int, skip_grab: bool) -> bool:
	var f8: int = ram.u32(r + 8)
	var id: int = f8 & 0xffff
	if ram.u8(r + 0x2d) == 0 or ram.u8(r + 0x19) != 0 or (skip_grab and id == 0x412) or (f8 & 0x400000) != 0 or (ram.u32(r + 4) & 0x20000) != 0:
		return false
	if not reach(r, w(0x14)):
		return false
	var s: int = wu(0x230)
	if (s & 0xffff) == 0x4c02:
		return true
	if s & 0x400:
		return id == 0x217 or id == 799 or (not skip_grab and id == 0x412)
	if s & 4:
		return id == 0x10f or id == 0x51f
	if s & 1:
		return id == 0x217 or id == 0x10f
	if s & 2:
		return id == 0x10f or id == 0x217 or id == 0x412
	return false
func p_57b60(r: int, e: int) -> bool:
	return ram.u8(r + 0x2d) != 0 and (ram.u16(e) & 0x3fe0) == 0 and (ram.u32(r + 4) & 0x20000) == 0 and ram.s16(r + 0x14) >= 0 and (ram.u32(r + 8) & 0x400000) == 0 and ram.u8(r + 0x19) == 0 and reach(r, w(0x14))
func p_57d58(r: int, e: int) -> bool:
	var f4: int = ram.u32(r + 4)
	return (ram.u32(r + 8) & 0x400000) == 0 and ram.s16(r + 0x14) > 0 and ram.u8(r + 0x2d) != 0 and (ram.u8(r + 0x19) == 0 or (f4 & 0x80000) != 0) and ram.u8(r + 0x2d) < h(0x20a) and (f4 & 0x20000) == 0 and reach(r, w(0x14))
func p_57e94(r: int, e: int) -> bool:
	return (ram.u32(r + 8) & 0x400000) == 0 and ram.s16(r + 0x14) > 0 and ram.u8(r + 0x2d) != 0 and ram.u8(r + 0x2d) < h(0x20a) and (ram.u32(r + 8) & 0xffff) != 0x412 and (ram.u32(r + 4) & 0x20000) == 0 and reach(r, w(0x14))
func p_strike(r: int, e: int) -> bool:
	return (ram.u32(r + 4) & 1) == 1 and ram.u8(r + 0x2d) == 0
func p_input(input: int) -> Callable:
	return func(r: int, e: int) -> bool: return ram.s16(e) == input
func move_pad(input: int, row: int) -> void:
	if (input & 0xc000) == 0:
		var m: int = input >> 5 & 0x1ff
		var i: int = 9
		while (ram.u16(0x8002303c + i * 2) & m) == 0:
			i -= 1
			if i <= 0:
				break
		var p: int = 0
		var bits: int = input
		for k in 4:
			if bits & 1:
				p |= ram.u16(0x80023064 + k * 2)
			bits = (bits & 0xffff) >> 1
		sh(4, ram.u16(0x80023050 + i * 2) | p)
	else:
		var seq: int = sequence_of(input & 0xffff)
		var v: int = ram.u16(seq + 2)
		sw(8, 0 if ram.u16(seq + 4) == 0 else seq + 4)
		sh(4, cmd_pad(v))
	sw(0x5c, row)
func sequence_of(v: int) -> int:
	if v < 0xc00e:
		if v == 0xc001:
			return 0x8001006c
		if v == 0xc002:
			return 0x80010078
	elif v < 0xc7ff:
		if v - 0xc00e < 0x3f:
			return ram.u32(0x800954d0 + (v - 0xc00e) * 4)
	elif v - 0xc7ff < 0x29:
		return ram.u32(0x800955cc + (v - 0xc7ff) * 4)
	return 0
func pick() -> int:
	var cnt: int = h(0x72)
	if cnt <= 0:
		return -1
	var k: int = roll_scaled(cnt)
	var n: int = h(0x70)
	var idx: int
	var s0: int = 0
	if hu(2) & 1:
		idx = -1
		var found: bool = false
		while s0 < n:
			var fl: int = rec_mark(s0)
			s0 += 1
			if fl > 0:
				k -= 1
				if k <= 0:
					idx = s0 - 1
					found = true
					break
		if not found:
			idx = s0 - 1
	else:
		s0 = n - 1
		while s0 >= 0:
			var fl: int = rec_mark(s0)
			s0 -= 1
			if fl > 0:
				k -= 1
				if k < 0:
					break
		idx = s0 + 1
	if idx < 0:
		return -1
	var entry: int = rec_entry(idx)
	move_pad(ram.u16(entry), rec_row(idx))
	picked(entry)
	return idx
func picked(entry: int) -> void:
	var row: int = ram.u32(ram.u32(MOVE_TABLES + ram.u8(A + 0x1886) * 4) + ram.u16(entry + 6) * 4)
	if (ram.u32(row + 8) & 0x400000) != 0:
		sh(0x96, h(0x96) + 1)
	if ram.u8(row + 0x2d) != 0:
		var r: int = roll(3)
		sh(0x68, h(0x23c) + h(0x23e + r * 2))
		sh(0x44, 0xffff)
		if h(0x46) > 0:
			sh(0x46, 0xffff)
		sh(0x3a, 0)
		sh(0x38, 0)
		sh(0x40, 0x28)
		sh(0x48, 0xffff)
func reset_wait() -> void:
	sh(0x40, 0x28)
	sh(0x3a, 0)
	sh(0x38, 0)
	sh(0x48, 0xffff)
func reaches(target: int) -> bool:
	var frame: int = ram.s16(A + 0x58)
	var table: int = ram.u32(MOVE_TABLES + ram.u8(A + 0x1886) * 4)
	var found: bool = false
	var cur: int = ram.u32(ram.u32(A + 0x54) + 0xc)
	var p: int = cur
	while ram.s16(p) != -0x4000:
		var list: int = p
		var count: int = 1
		if ram.s16(p) == -0x3ff4:
			count = ram.u8(p + 0xb)
			list = SHARED_ENTRIES + ram.u16(p + 6) * 12
		cur = list
		for j in count:
			var e: int = list + j * 12
			if ram.u16(e + 6) == target and ram.u8(e + 9) <= frame and frame <= ram.u8(e + 10) and stance_ok(ram.u8(e + 2)) and cond_ok(e):
				found = true
			cur = e + 12
		p += 12
	if found:
		return true
	var next_row: int = ram.u32(table + ram.u16(cur + 6) * 4)
	if next_row != ram.u32(A + 0x54) and ram.u8(cur + 9) <= frame and frame <= ram.u8(cur + 10):
		for e in entries(next_row):
			if ram.u16(e + 6) == target and ram.u8(e + 9) == 1 and ram.u8(e + 9) <= frame and frame <= ram.u8(e + 10) and stance_ok(ram.u8(e + 2)) and cond_ok(e):
				found = true
	return found
func bind(a: int) -> void:
	A = a
	S = STATES + ram.u8(a + 0x1886) * STATE_SIZE
	B = ram.u32(S + 0x10)
	ram.w32(SELF_PTR, A)
	ram.w32(OPP_PTR, B)
func start_match() -> void:
	ram.w32(DEMO_SKIP, 1 if ram.u16(DEMO_FLAG) != 0 else 0)
	for o in [0x8009f300, 0x8009f304, 0x8009f308, 0x8009f30c]:
		ram.w32(o, 0xffffffff)
	ram.w8(0x800a9228 + 2 * 0x188c + 0x1886, 0xff)
	ram.w8(0x800a9228 + 2 * 0x188c + 0x1887, 0xff)
	for i in 2:
		var a: int = 0x800a9228 + i * 0x188c
		var opp: int = 0x800a9228 + (1 - i) * 0x188c
		ram.w8(a + 0x1886, i)
		ram.w8(a + 0x1887, 1 - i)
		var s: int = STATES + i * STATE_SIZE
		ram.w16(s + 2, i)
		ram.w16(s, i)
		ram.w32(s + 0x10, opp)
		var table: int = ram.u32(ram.u32(0x800adc20 + i * 4) + 0xc)
		ram.w32(s + 0xc, table)
		ram.w32(MOVE_TABLES + i * 4, table)
		ram.w16(s + 6, 0)
		ram.w16(s + 4, 0)
		bind(a)
		start_round(a, 0, -1, -1)
func start_round(a: int, level: int, stage: int, extra: int) -> void:
	bind(a)
	sh(0x34, 0xffff)
	sh(0x36, 0)
	sh(0x3c, 0)
	sh(0x4a, 0xffff)
	sh(0x4c, 0)
	sh(0x8a, 0xffff)
	sh(0x48, 0xffff)
	sh(0x38, 0xffff)
	sh(0x3a, 0)
	sw(0x58, 0)
	sw(0xa0, 0)
	sh(0x54, 0xffff)
	sh(0x3e, 0)
	sh(0x46, 0xffff)
	sh(0x44, 0xffff)
	sh(0x4e, 0xffff)
	sh(0x2c, 0)
	sh(0x2a, 0)
	sh(0x42, 0xffff)
	sw(0x60, 0)
	sh(0x8c, 0xffff)
	sh(0x1fe, 0xffff)
	sh(0x6c, 0xffff)
	sh(0x6a, 0)
	sh(0x72, 0)
	sh(0x70, 0)
	sh(0xc0, 0)
	sh(0xc2, 0)
	sw(0x30, ram.u32(A + 0x3f4))
	sh(0xd4, 0)
	sh(0xd8, 0)
	sh(0xda, 0)
	sh(0x19c, 0)
	sh(0x1cc, 0)
	sh(0x1a0, 0)
	sh(0x1a2, 0)
	sh(0x1ce, 0)
	sh(0x1d2, 0)
	sh(0x96, 0)
	sh(0x98, 0)
	sh(0x9c, 0xffff)
	sw(0xbc, 0)
	sh(0x6e, 0)
	sw(8, 0)
	sh(0x216, 0xffff)
	sh(0x1fc, 0)
	for k in 8:
		sw(0x1dc + k * 4, 0)
	for o in range(0x8e, 0x95):
		sb(o, 0)
	load_params(level, stage, extra)
	sw(0x74, hook_of(1, ram.s16(B + 0x16)))
	sw(0x78, hook_of(0, ram.s16(A + 0x16)))
	if ram.u16(DEMO_FLAG) != 0:
		for o in [0x23e, 0x240, 0x242, 0x244]:
			sh(o, h(o) / 2)
		sh(0x254, h(0x254) / 4)
	sh(0x68, h(0x23e))
	sh(0x40, roll_scaled(0x1e) + 0x1e)
	for k in LIST_COUNT:
		ram.w16(LIST + k * 12 + 8, 0xffff)
func load_params(level: int, stage: int, extra: int) -> void:
	if level < 1:
		level = ram.u8(LEVEL)
	if stage < 1:
		stage = ram.u8(STAGE_LEVEL)
	sh(0x21e, extra)
	if ram.u16(DEMO_FLAG) != 0:
		stage = 4
	if level > 2:
		level = 2
	if stage > 9:
		stage = 9
	copy(0x800231ac + stage * 0x6e + level * 0x44c, S + 0x238, 0x6e)
	copy(0x80023e22, S + 0x2a6, 0x6e)
	copy(0x80098260 + ram.s16(A + 0x18) * 12, S + 0x314, 12)
	copy(0x80098260 + ram.s16(B + 0x18) * 12, S + 0x320, 12)
	sh(0x1d4, h(0x26a) if h(0x26e) < h(0x26a) else h(0x26e))
func copy(src: int, dst: int, n: int) -> void:
	for i in n:
		ram.w8(dst + i, ram.u8(src + i))
func hook_of(which: int, id: int) -> int:
	for i in 10:
		var t: int = 0x80023134 + i * 12
		if ram.u16(t) == (id & 0xffff):
			return ram.u32(t + (4 if which == 1 else 8))
	return 0
func step(a: int) -> Array:
	bind(a)
	header()
	if not queued():
		decide()
	return finish()
func header() -> void:
	sw(0x5c, 0)
	var frame: int = ram.s16(A + 0x58)
	var last: int = h(0x34)
	sh(0x34, frame)
	if frame != last:
		sh(2, h(2) + 1)
	var row_a: int = ram.u32(A + 0x54)
	var row_b: int = ram.u32(B + 0x54)
	var yaw: int = ram.u16(A + 0x2e)
	sw(0x224, ram.u32(row_a + 4))
	sw(0x220, ram.u32(row_a + 8))
	sw(0x228, ram.u16(row_a + 8))
	sw(0x230, ram.u32(row_b + 4))
	sw(0x22c, ram.u32(row_b + 8))
	sw(0x234, ram.u16(row_b + 8))
	sw(0x1c, ram.u32(A + 0xf8))
	var f: int = 1 if ram.s16(A + 0x30) > 0x4000 else 0
	sh(0x2e, ram.s16(A + 0x30))
	if ((yaw - 0x4e38) & 0xffffffff) < 0x31c8:
		f |= 2
	if ((yaw + 0x8000) & 0xffff) < 0x31c7:
		f |= 4
	if ram.s16(B + 0x64) == 0x412 and ram.s16(B + 0x58) <= ram.u8(row_b + 0x2e) and ram.u32(0x800afa3c) < 0x700:
		f |= 8
	if ram.s16(A + 0x32) == 0:
		f |= 0x10
	sb(0x201, 0)
	sb(0x200, 0)
	sw(0x64, f)
	if ram.s16(B + 0x16) == 0xe and ram.s8(ram.u32(row_b + 0x28)) == 0x18:
		sb(0x200, 1)
	elif ram.s16(B + 0x16) == 0x13 and ram.s8(ram.u32(row_b + 0x28)) == 0x1a:
		sb(0x201, 1)
		sw(0x22c, wu(0x22c) | 0x10000)
func queued() -> bool:
	var p: int = wu(8)
	if p != 0:
		var v: int = ram.s16(p)
		sw(8, p + 2)
		if ram.s16(p + 2) == 0:
			sw(8, 0)
		sh(4, cmd_pad(v))
		return true
	if h(0x21e) == 0:
		sh(4, 0)
		return true
	if h(0x21e) == 1:
		sh(4, (wu(0x224) & 4) << 10)
		return true
	if ram.u32(DEMO_SKIP) != 0 and (ram.u32(FRAME_COUNTER) & hu(0) & 1) != 0:
		sh(4, hu(6) & 0xf000)
		return true
	return false
func finish() -> Array:
	var f: int = wu(0x224)
	var picked_row: int = wu(0x5c)
	sh(0x3c, 1 if (f & 0x205) == 1 else 0)
	if picked_row != 0 and h(0x48) < 0 and ram.u8(picked_row + 0x19) != 0:
		sh(0x48, ram.u8(picked_row + 0x19))
	for o in [0x48, 0x38, 0x40, 0x54, 0x46, 0x44, 0x42, 0x8a, 0x8c]:
		if h(o) > -1:
			sh(o, h(o) - 1)
	if h(0x1fe) == 0:
		load_params(-1, -1, -1)
	if h(0x1fe) > -1:
		sh(0x1fe, h(0x1fe) - 1)
	var low: int = f & 0xffff
	sh(0x212, h(0x20c))
	var grab: bool = low == 0x1052 or low == 0x2829
	if h(0x3e) == 0:
		sh(0x3e, 1 if grab else 0)
		sb(0x93, 0)
	else:
		sh(0x3e, 1 if grab else 0)
		if not grab and b(0x93) != 0:
			sb(0x93, 0)
	if ram.u8(A + 0xce) != 0:
		reset_wait()
		sh(0xd8, 0)
		sh(0xc0, 0)
		sh(0x1a0, 0)
		sh(0x98, 0)
	if ram.u8(A + 0xd2) != 0 and w(0x18) < 3:
		sh(0x54, 0x1e)
	if ram.u8(B + 0xd2) != 0 and w(0x14) < 2 and roll(0xfff) < h(0x258):
		sh(0x68, h(0x68) - 3)
	if ram.s32(A + 0x3f4) < w(0x30):
		var v: int = roll(0xfff)
		if h(0x27e) <= v:
			sh(0x68, h(0x68) - 3)
			var row: int = ram.u32(B + 0x54)
			var count: int = 0
			if ram.u32(DEMO_SKIP) == 0:
				sh(0x202, 0)
				for k in 8:
					if wu(0x1dc + k * 4) == row:
						count += 1
				if count > 1:
					if h(0x1fe) < 1:
						load_params(0, 9, -1)
					sh(0x1fe, 600)
					sh(0x202, 1)
				sw(0x1dc + hu(0x1fc) * 4, row)
				sh(0x1fc, (hu(0x1fc) + 1) & 7)
	sw(0x30, ram.u32(A + 0x3f4))
	if ram.u8(A + 0xce) != 0 and ram.u16(DEMO_FLAG) == 0:
		reset_wait()
		var q: int = s16w(h(0x254) + 10)
		sh(0x254, q)
		sh(0x258, h(0x258) + 10)
		sh(0x254, h(0x256) if h(0x256) < h(0x254) else q)
		sh(0x258, h(0x25a) if h(0x25a) < h(0x258) else h(0x258))
		if h(0x216) > 0:
			var t: int = s16w(h(0x262) + 0x28)
			sh(0x262, t)
			sh(0x25e, h(0x25e) + 0x14)
			sh(0x262, h(0x264) if h(0x264) < h(0x262) else t)
			sh(0x25e, h(0x260) if h(0x260) < h(0x25e) else h(0x25e))
	var pad: int = hu(4)
	var edge: int = pad & (pad ^ hu(6))
	sh(6, pad)
	return [pad, edge]
func decide() -> void:
	track()
	if ram.s16(A + 0x74) != 0:
		stunned()
		return
	sw(0xa0, 0)
	sh(0x96, 0)
	sh(0x9c, 0xffff)
	sw(0xbc, 0)
	if row_pick():
		return
	if ram.u32(A + 0x1a4) != 0:
		return
	if guard():
		return
	if carry():
		return
	if collect():
		return
	if reaction():
		return
	var strategy: int = choose()
	if strategize(strategy):
		return
	engage()
func track() -> void:
	row_a = ram.u32(A + 0x54)
	row_b = ram.u32(B + 0x54)
	a_start = ram.u8(row_a + 0x2d)
	a_end = ram.u8(row_a + 0x2e)
	fa = ram.s16(A + 0x58)
	b_start = ram.u8(row_b + 0x2d)
	b_end = ram.u8(row_b + 0x2e)
	fb = ram.s16(B + 0x58)
	sw(0x7c, 0)
	if (ram.u32(row_a + 0x24) >> 8 & 0x20) == 0:
		sh(0xd4, 0)
	var v: int = b(0x8e)
	var u: int = b(0x90)
	sb(0x8e, 0)
	sb(0x90, 0)
	sb(0x8f, v)
	sb(0x91, u)
	if ram.s32(B + 0x3f4) <= int(ram.s32(B + 0x3f8) / 10):
		sh(0x250, 0)
		sh(0x252, 0)
		sh(0x258, 0)
		sh(0x25a, 0)
	var r: int = roll(0xfff)
	if h(0x27e) <= r and h(0x2e) > 0x1fff and ram.s16(A + 0x3e) < 0x6001 and w(0x18) < 3:
		sb(0x8f, 1)
	sh(0x28, 1 if (row_a != wu(0x58) or fa < h(0x4e)) else 0)
	sh(0x204, 1 if (row_b != wu(0x1d8) or fb < h(0x206)) else 0)
	sh(0x2c, h(0x2c) + 1)
	if wu(0x58) != row_a:
		sw(0x58, row_a)
		sh(0x2c, 0)
	sh(0x4e, fa)
	if (wu(0x224) & 0x400000) != 0:
		reset_wait()
	if a_start == 0:
		if (wu(0x220) & 0x80000) == 0 and ram.u8(B + 0x87) == 0:
			sh(0x1d2, 0)
	elif a_start == fa:
		sh(0x1d2, h(0x1d2) + 1)
	if b_start == 0:
		if (wu(0x22c) & 0x80000) == 0 and ram.u8(A + 0x87) == 0:
			sh(0x216, 0xffff)
	elif b_start == fb:
		sh(0x216, h(0x216) + 1)
		if h(0x216) > 10:
			sh(0x216, 10)
	var dist: int = w(0x1c)
	ram.w32(0x8009f2f8, 0)
	var last: int = w(0x20)
	sw(0x20, dist)
	var band: int = dist - h(0x32a) - 0x80
	sw(0x24, dist - last)
	if band < h(0x314):
		if ram.u32(A + 0x3e8) == 0 and ram.u32(A + 0x3ec) == 0 and ram.u32(A + 0x3f0) == 0 and ram.u32(B + 0x3e8) == 0 and ram.u32(B + 0x3ec) == 0 and ram.u32(B + 0x3f0) == 0:
			sw(0x14, 1)
		else:
			sw(0x14, 0)
			if h(0x50) == 0:
				sh(0x68, h(0x68) - 1)
		if h(0x50) == 0:
			sh(0x68, h(0x68) - 1)
		sh(0x2a, 0)
	elif band < h(0x316):
		sw(0x14, 2)
		sh(0x2a, 0)
	elif band < h(0x318):
		sw(0x14, 3)
		sh(0x2a, 0)
	else:
		var extra: int
		var base: int
		if band < h(0x31a):
			sw(0x14, 4)
			extra = hw_rand()
			extra = ((extra + ram.u32(RNG)) & 0x7fff) * 2
			base = h(0x2a) + 4
		else:
			sw(0x14, 5)
			extra = hw_rand()
			extra = ((extra + ram.u32(RNG)) & 0x7fff) * 3
			base = h(0x2a) + 5
		ram.w32(RNG, ram.u32(RNG) * 5 + 3)
		sh(0x2a, base + (extra >> 15))
	if h(0x50) == 0 or ram.u8(B + 0xdb) != 0:
		sh(0x68, h(0x68) - 1)
	var span: int = w(0x1c) - h(0x31e)
	if w(0x24) < 0:
		span += w(0x24)
	var zone: int = 1
	if h(0x320) + 0x80 <= span:
		zone = 2
		if h(0x322) + 0x100 <= span:
			zone = 3
			if h(0x324) + 0x200 <= span:
				zone = 4
				if h(0x326) + 0x280 <= span:
					zone = 5
	sw(0x18, zone)
	if b_start != 0 or (wu(0x230) & 0x80000) == 0:
		sh(0x20e, 0)
	else:
		sh(0x20e, h(0x20e) + 1)
		if ram.u16(row_b + 0x10) == ram.s16(B + 0xa0):
			sh(0x20e, 0)
	sh(0x20c, 1 if (h(0x20e) > 0 or (b_start != 0 and fb <= b_end + 1)) else 0)
	if h(0x20c) == 0 or fb >= b_start - 3:
		sw(0x80, 0)
	else:
		sw(0x80, w(0x80) + 1)
	if a_start == 0 or fb <= b_end + 1:
		sw(0x84, 0)
	else:
		sw(0x84, w(0x84) + 1)
	if h(0x20c) == 0:
		sh(0x6c, -1)
	elif h(0x6c) > 0:
		sh(0x6c, h(0x6c) - 1)
	if h(0x20c) == 0 and (wu(0x230) & 0x200000) != 0:
		sh(0x20c, 1)
	if (wu(0x230) & 0x80000) == 0:
		sh(0x210, 0)
	else:
		sh(0x210, h(0x210) + 1)
	sh(0x214, 1 if ((wu(0x22c) & 0x400000) != 0 and (b_start == 0 or fb <= b_end)) else 0)
	if h(0x20c) == 0 and h(0x214) == 0:
		sh(0x20a, 999)
		sb(0x92, 0)
	elif b_start == 0:
		sh(0x20a, ram.u8(ram.u32(row_b + 0xc) + 10) - fb + 1)
	else:
		var tag: int = 0x3e5
		var keep: bool = false
		if fb <= b_end:
			sh(0x20a, b_start - fb)
			if s16w(b_start - fb) < 0x65:
				keep = true
			else:
				tag = 0x3e6
		if not keep:
			sh(0x214, 0)
			sh(0x20c, 0)
			sh(0x20a, tag)
	sh(0x21a, 1 if ram.s32(B + 0x994) < -0xc1b else 0)
	if ram.s16(A + 0x3e) > 0x3000 or ((wu(0x230) & 0x200000) == 0 and w(0x234) != 0x607 and w(0x234) != 0x706):
		sb(0x94, 0)
	if h(0x54) > -1 and w(0x18) < 2:
		if h(0x27e) <= roll(0xfff):
			sb(0x92, 1)
	var cover: int = 0
	if (wu(0x230) & 0x204) != 0 and (wu(0x230) & 0xffff) != 0x4c02:
		cover = 1 if ram.u8(B + 0xdb) == 0 else 0
	sh(0x208, cover)
	var low_hit: int = 0
	if ram.s16(B + 0x16) == 4:
		low_hit = 1 if ram.s16(B + 0xa0) == 0x456 else 0
	sh(0x88, low_hit)
	if low_hit != 0:
		sh(0x216, 0xffff)
	expect_guard()
	if (wu(0x224) & 1) == 0:
		sh(0x4a, -1)
	elif h(0x3c) > 0:
		sh(0x4a, h(0x4a) - 1)
	elif (ram.u32(row_a + 0x24) >> 8 & 0x10) == 0:
		var x: int = roll(7)
		var y: int = roll(0xf)
		var z: int = roll(7)
		sh(0x4a, x + y + 0x14 + z)
	sh(0x50, 0 if a_start == 0 else 1)
	var live: int = 0
	if (ram.u32(row_a + 4) & 0x200000) != 0 and (ram.u32(row_a + 8) & 0x200000) != 0:
		live = 1 if not (a_end < fa) else 0
	sh(0x52, live)
func expect_guard() -> void:
	var mine: int = wu(0x224) & 0xffff
	var id: int = w(0x234)
	var v: int = 0
	if w(0x1c) < 0xb87 and h(0x88) == 0:
		if h(0x214) == 0:
			if h(0x20c) == 0 or h(0x2e) > 0x3000:
				v = 0
			elif id == 0x412:
				v = 1 if (mine == 0x2021 or mine == 0x2829 or mine == 0x1052) else 0
			elif id == 0x217:
				v = 1 if mine == 0x1052 else 0
			elif id == 0x10f:
				v = 1 if mine == 0x2829 else 0
			elif id == 799:
				v = 1 if (mine == 0x2829 or mine == 0x1052) else 0
			elif id == 0x706:
				v = 1 if (mine == 0x2829 or mine == 0x2021) else 0
		elif id != 0x217:
			v = 1 if (mine == 0x2021 or mine == 0x2829) else 0
	sh(0x6a, v)
func scratch_entries(row: int, limit: int) -> Array:
	var all: Array = entries(row)
	return all.slice(0, limit)
func stunned() -> void:
	reset_wait()
	var row: int = ram.u32(A + 0x54)
	if ram.s16(A + 0x74) < 1:
		if row == wu(0xa0):
			sh(4, 0)
			return
		sh(0x96, h(0x96) - 1)
		sw(0xa0, row)
		var id: int = ram.s16(B + 0xa0)
		var cls: int = ram.s16(B + 0x16)
		var special: bool = id == 0x189 or id == 0x18e or id == 0x17f or id == 0x181 or (cls == 9 and id == 0x172) or (cls == 0 and id == 0x172) or (cls == 3 and id == 0x152)
		if special or roll(0xfff) < h(0x24a):
			var list: Array = scratch_entries(row, 48)
			var code: int = 0
			if list.size() > 0:
				var e: int = list[roll_scaled(list.size())]
				var c: int = ram.u8(e + 3)
				if c == 0x3a:
					code = 1
				elif c == 0x3b:
					code = 2
				elif c == 0x3c:
					code = 1
				else:
					code = ram.s16(e)
			if code != 0:
				move_pad(code & 0xffff, 0)
				return
		else:
			return
		sh(4, 0)
		return
	var chosen: Array = []
	if row != wu(0xa0) and h(0x96) > -1 and h(0x96) < h(0x246) - 1:
		if roll(0xfff) < h(0x24c):
			for e in entries(row):
				if not stance_ok(ram.u8(e + 2)):
					continue
				var v: int = roll(0x70)
				var target: int = ram.s16(e + 6)
				var cls_a: int = ram.s16(A + 0x16)
				var ok: bool = true
				if target == 0x3a7:
					ok = false
				elif target == 0xd41:
					ok = v != 0 if cls_a == 4 else true
				elif target == 0xd24 or target == 0xd32:
					ok = v == 0 if (cls_a == 0 or cls_a == 0xd) else true
				elif target == 0xde2:
					ok = not (cls_a == 0 and v != 0)
				elif target == 0xd25 or target == 0xd34:
					ok = not (cls_a == 0 or cls_a == 0xd)
				if ok and (ram.u8(e + 3) == 0 or Commands.condition(ram, e, A, B)):
					chosen.append(e)
					if chosen.size() > 5:
						break
			if chosen.size() < 1:
				sh(0x96, 0xffff)
				sh(0x9c, 0xffff)
				sw(0xbc, 0)
			else:
				sw(0xa0, ram.u32(A + 0x54))
				sh(0x96, h(0x96) + 1)
				var pick_e: int = chosen[roll_scaled(chosen.size())]
				sh(0x9c, ram.u8(pick_e + 9) + 1)
				sw(0xbc, pick_e)
	if ram.s16(A + 0x58) != h(0x9c):
		sh(4, 0)
		return
	var entry: int = wu(0xbc)
	move_pad(ram.u16(entry), ram.u32(ram.u32(MOVE_TABLES + ram.u8(A + 0x1886) * 4) + ram.u16(entry + 6) * 4))
func row_pick() -> bool:
	if (wu(0x224) & 0xffff) != 0x4c02 or ram.u8(row_a + 0x2d) != 0:
		return false
	reset_wait()
	sh(0x72, 0)
	sw(0x58, ram.u32(A + 0x54))
	var n: int = build(true)
	sh(0x70, n)
	if n > 0 and roll(0xfff) < h(0x29a):
		var got: int = 0
		for i in n:
			if rec_mark(i) == 0 and ((ram.u8(rec_entry(i) + 8) - 0x1c) & 0xff) < 2:
				set_mark(i, 1)
				got += 1
		sh(0x72, h(0x72) + got)
		if got > 0:
			pick()
			return true
	sh(4, 0)
	return true
func guard() -> bool:
	var done: bool = false
	if ram.u8(A + 0xdb) != 0 or (wu(0x224) & 0x404) == 0:
		sh(0x36, 0)
	else:
		var found: bool = false
		for e in entries(ram.u32(A + 0x54)):
			if ram.u8(e + 3) == 0x31:
				found = true
				break
		if found:
			var c: int = h(0x6e)
			sh(0x36, 1)
			sh(0x6e, c - 1)
			if h(0x6e) >= 0:
				sh(4, 0)
			else:
				var v: int = b(0x238 + roll(3))
				sh(4, 0x10)
				sh(0x6e, v)
			done = true
		else:
			sh(0x72, 0)
			sw(0x58, ram.u32(A + 0x54))
			var n: int = build(true)
			sh(0x70, n)
			if n < 1:
				sh(4, 0)
				done = true
			else:
				done = defend()
	if done:
		return true
	return hook_roll(0) or hook_roll(1)
func defend() -> bool:
	sh(0x36, 1)
	sh(0x40, 0x28)
	sh(0x48, 0xffff)
	sh(0x3a, 0)
	sh(0x38, 0)
	sh(0x8a, 0x10)
	if b(0x201) != 0 and (ram.u32(A + 0x60) & 0x200) != 0:
		sh(4, 0x8000)
		return true
	var window: bool = ram.s16(B + 0x58) < ram.u8(ram.u32(B + 0x54) + 0x2e)
	if (((wu(0x230) & 0x200000) != 0 and ram.u8(ram.u32(B + 0x54) + 0x2d) == 0) or (w(0x234) == 0x607 and (wu(0x22c) & 0x10000) == 0 and h(0x20a) < 0x1d)) and window:
		sh(4, 0)
		return true
	var m: int = 0
	if ram.u8(ram.u32(B + 0x54) + 0x2d) == 0:
		if w(0x14) > 2:
			m = 7 if w(0x18) >= 4 else 0x3f
			sh(0x36, 0)
		else:
			m = 0
			if hu(2) & 1:
				sh(0x36, 0)
				if h(0x68) < 0 and roll(0x3f) == 0:
					sh(0x36, 0)
					m = 0x38
				else:
					m = 7
	elif h(0x20a) < 0xc and ram.s16(B + 0x58) <= ram.u8(ram.u32(B + 0x54) + 0x2e):
		if w(0x234) == 0x10f or (wu(0x22c) & 0x10000) != 0:
			if (hu(2) & 1) == 0:
				m = 0
			else:
				sh(0x36, 0)
				if roll(2) == 0:
					var again: bool = ram.u8(row_b + 0x19) != 0 or h(0x2e) > 0x4000
					if not again:
						m = 4
						again = (wu(0x230) & 0x200000) != 0
					if again:
						m = 4 if roll(0x3f) == 0 else 2
				else:
					m = 0x38
		else:
			if w(0x18) < 3 and (w(0x18) < 2 or w(0x24) < 0xb):
				m = 0x3f if roll(0xf) != 0 else 0
			else:
				m = 1
			sh(0x36, 0)
	else:
		m = 0
		if w(0x14) < 2:
			m = 0x38 if (wu(0x230) & 2) != 0 else 0x28
			sh(0x36, 0)
	if m == 0x80:
		sh(4, 0)
		return hook_roll(0) or hook_roll(1)
	if m == 0:
		sh(4, 0)
		return true
	var code: int
	while true:
		var r: int = hw_rand()
		var s: int = ram.u32(RNG)
		ram.w32(RNG, s * 5 + 3)
		code = ram.u16(0x80022e74 + (((r + s) & 0x7fff) * 6 >> 15) * 2)
		if (m & code) != 0:
			break
	match code:
		1:
			sh(4, 0x1000)
			return true
		2:
			sh(4, 0x4080 if (hu(2) & 7) == 0 else 0x80)
			return true
		4:
			sh(4, 0x2000 if ram.s16(A + 0x16) == 0x12 else 0x8000)
			return true
		8:
			mark(p_572a4)
		0x10:
			mark(func(r: int, e: int) -> bool: return (ram.u32(r + 8) & 0x10000) != 0 or (ram.u32(r + 8) & 0xffff) == 0x10f)
		0x20:
			mark(func(r: int, e: int) -> bool: return true if ram.s16(e) == -0x3fff else ((ram.u32(r + 4) & 0xa0000) == 0x80000 and (ram.u32(r + 4) & 0x600000) == 0))
	if h(0x72) > 0:
		pick()
	return true
func hook_roll(which: int) -> bool:
	if h(0x8a) >= 0:
		return false
	if roll(0xfff) >= h(0x272):
		return false
	var ptr: int = wu(0x74) if which == 0 else wu(0x78)
	if ptr == 0:
		return false
	var ret: int = call_hook(ptr)
	if ret == -2:
		return true
	if ret == -3:
		return h(0x72) > 0 and pick() >= 0
	if ret == -1:
		return false
	if ret == 0x2000 or ret == 0x8000:
		sh(0x38, 0x10)
		sh(0x3a, 0)
		sh(0x40, 0x38)
	sh(4, ret)
	return true
func carry() -> bool:
	var level: int = ram.u8(LEVEL)
	if ram.u8(B + 0xd2) == 0 or h(0x258) + h(0x216) * level * 0x1e <= roll(0xfff):
		var start: int = ram.u8(ram.u32(B + 0x54) + 0x2d)
		if (h(0x6c) > -1 or start == 0 or start - 0x1e < ram.s16(B + 0x58)) and h(0x6a) != 0:
			sh(4, hu(6) & 0xf000)
			return true
	else:
		sb(0x8f, 1)
	return false
func collect() -> bool:
	var done: bool = false
	sh(0x72, 0)
	sh(0x70, 0)
	if h(0x28) != 0:
		sw(0x58, ram.u32(A + 0x54))
		sh(0x4e, ram.s16(A + 0x58))
		if h(0xc0) < 1:
			if h(0xd8) < 1:
				if h(0x52) == 0:
					done = collect_chain()
			else:
				done = collect_moves()
		else:
			done = collect_hits()
	sh(0x4e, ram.s16(A + 0x58))
	if not done:
		sh(0x70, build(false))
		if h(0x2c) > 0xdc:
			var got: int = mark(func(r: int, e: int) -> bool: return true)
			if got > 0:
				pick()
				done = true
	return done
func collect_chain() -> bool:
	var n: int = 0
	if ram.u8(ram.u32(A + 0x54) + 0x2d) == 0:
		sh(0x1a2, 0)
		sh(0xda, 0)
		sh(0xc2, 0)
		sh(0x1a0, 0)
		sh(0xd8, 0)
		sh(0xc0, 0)
		sh(0x98, 0)
		return false
	var param: int = h(0x27e)
	if h(0x1cc) == 0:
		sh(0x1d0, 0)
		var table: int = ram.u32(MOVE_TABLES + ram.u8(A + 0x1886) * 4)
		for e in entries(wu(0x58)):
			if ram.u8(e + 9) == 1 and ram.u8(e + 10) == ram.u8(e + 11) and stance_ok(ram.u8(e + 2)):
				var row: int = ram.u32(table + ram.u16(e + 6) * 4)
				if (ram.u32(row + 0x24) >> 8 & 0x20) == 0 or param <= roll(0xfff):
					sw(0x1a4 + n * 4, e)
					if ram.u8(e + 10) < 0x3c and h(0x1d0) < ram.u8(e + 10):
						sh(0x1d0, ram.u8(e + 10))
					n += 1
					if n > 9:
						break
		sh(0x1a2, n)
	else:
		sh(0x1cc, 0)
	if n < 1:
		sh(0x1a2, 0)
		sh(0x1a0, 0)
	else:
		sh(4, hu(6) & 0xf000)
		sh(0x1a0, h(0x1a0) + 1)
	return true
func collect_moves() -> bool:
	var n: int = 0
	var table: int = wu(0xc)
	var blocked: int = h(0x208)
	var chance: int = h(0x24e)
	roll(0)
	var mask: int = ram.u32(REACH + w(0x14) * 4)
	for e in entries(wu(0x58)):
		if not stance_ok(ram.u8(e + 2)):
			continue
		var row: int = ram.u32(table + ram.u16(e + 6) * 4)
		if not ((blocked == 0 or (ram.u32(row + 8) & 0x400000) == 0) and (ram.u32(row + 4) & 0x20000) == 0):
			continue
		var f8: int = ram.u32(row + 8)
		if (f8 & 0x200000) == 0 and (ram.u32(row + 4) & 0x80000) == 0:
			if (f8 & 0x400000) == 0 or roll(0x7fff) <= chance:
				continue
		var t: int = f8 & 0xffff0000
		if (f8 & 0x1c0000) == 0:
			t |= 0xc0000
		if (t & mask) != 0:
			sw(0xdc + n * 4, e)
			n += 1
			if n > 0x2f:
				break
	sh(0xda, n)
	if n < 1:
		sh(0xda, 0)
		sh(0xd8, 0)
	else:
		sh(4, hu(6) & 0xf000)
	return true
func collect_hits() -> bool:
	var n: int = 0
	var table: int = ram.u32(MOVE_TABLES + ram.u8(A + 0x1886) * 4)
	for e in entries(wu(0x58)):
		if stance_ok(ram.u8(e + 2)) and (ram.u32(ram.u32(table + ram.u16(e + 6) * 4) + 0x24) >> 8 & 0x20) != 0:
			sw(0xc4 + n * 4, e)
			n += 1
			if n > 3:
				break
	sh(0xc2, n)
	if n < 1:
		sh(0xc2, 0)
		sh(0xc0, 0)
	else:
		sh(4, hu(6) & 0xf000)
	return true
func sidestep(p: int) -> void:
	if p == -1:
		var left: int = 1 if ram.s16(B + 0x1278) < ram.s16(A + 0x1278) else 0
		var ang: int = ram.u16(A + 0x3c)
		p = 0
		if ((ang - 257) & 0xffffffff) < 0x7eff:
			p = 0
		elif ((ang + 0x7fff) & 0xffff) < 0x7efe:
			p = 1
		else:
			p = hw_rand() >> 4 & 1
		if left != 0:
			p = 1 - p
	var t: int = 0x8002306e + p * 24
	var v: int = ram.u16(t)
	sw(8, 0 if ram.s16(t + 2) == 0 else t + 2)
	sh(4, cmd_pad(v))
	reset_wait()
func mark_free() -> int:
	return mark(func(r: int, e: int) -> bool: return true)
func reaction() -> bool:
	var done: bool = false
	if h(0x52) != 0 and h(0x70) != 0 and b(0x200) == 0:
		if h(0x20a) < a_start - ram.s16(A + 0x58) or w(0x14) > 2 or ram.s16(A + 0x32) == 2:
			var got: int = mark_free()
			if got > 0 and pick() > -1:
				sh(0x68, 0xffff)
		done = true
	if done:
		return true
	if h(0x20c) != 0 and h(0x216) > -1 and w(0x18) < 4:
		if b(0x8f) != 0 or roll(0xfff) < h(0x25e):
			var d: int = h(0x20a)
			if d < 0x1e and d > 1:
				var got: int = mark(p_57d58)
				if got > 0:
					var idx: int = pick()
					done = true
					if idx > -1:
						return true
		if h(0x50) == 0:
			var near: bool = (h(0x22c) != 0 and h(0x22c) != 0x607) or h(0x20e) > 0
			if near and (b(0x92) != 0 or roll(0xfff) < h(0x262)):
				var p: int = 0
				if ram.s16(A + 0x32) == 0:
					p = 0xc000
					reset_wait()
					if w(0x234) == 0x217:
						p = 0x8000
				sh(4, p)
				return true
		done = false
		var gate: bool = false
		if roll(0xfff) < h(0x25c):
			if ((hu(0x20a) - 9) & 0xffff) < 3 and h(0x2e) < 0x4000:
				gate = (wu(0x224) & 0x400000) == 0
			if gate and w(0x18) > 1:
				sidestep(-1)
				sh(0x68, h(0x68) - 10)
				done = true
	return done
func opp_hittable() -> bool:
	if h(0x20c) != 0 and h(0x6a) == 0 and ram.s16(A + 0x3e) < 0x5000:
		if w(0x1c) < 0xb87:
			return reach(row_b_now(), w(0x18))
	return false
func row_b_now() -> int:
	return ram.u32(B + 0x54)
func choose() -> int:
	if h(0x216) > -1:
		return 0
	if h(0x88) != 0:
		return 0
	if h(0x6c) == 0 and h(0x50) == 0:
		return 2
	if b(0x94) == 0 and not (h(0x20c) != 0 and w(0x18) < 4):
		return 0
	return choose_big()
func choose_big() -> int:
	var rb: int = row_b_now()
	if (ram.u8(rb + 0x2d) != 0 and ram.u8(rb + 0x2e) < ram.s16(B + 0x58)) or ram.s16(A + 0x40) == 2:
		sb(0x94, 2)
	if b(0x94) == 0 and (w(0x234) == 0x607 or w(0x234) == 0x706 or (wu(0x230) & 0x200000) != 0) and roll(0xfff) < h(0x272):
		sb(0x94, 1)
	if h(0x8c) < 0 and b(0x94) != 2 and b(0x94) != 0:
		return 3
	var id20a: int = hu(0x20a)
	var cls: int = ram.s16(A + 0x16)
	if ((id20a - 8) & 0xffff) < 2 and w(0x228) == 0 and ram.u8(A + 0xdb) == 0 and ram.s16(0x80022d14 + cls * 0x10) != 0 and (ram.u32(rb + 0x24) >> 8 & 8) == 0 and ram.u8(B + 0xdb) == 0:
		if opp_hittable() and roll(0xfff) < h(0x292):
			return 5
	if cls == 9 and h(0x20a) < 0x1b and h(0x20a) > 0x15 and w(0x228) == 0 and ram.u8(A + 0xdb) == 0:
		if opp_hittable() and roll(0xfff) < h(0x292):
			return 6
	if ((id20a - 4) & 0xffff) < 7 and w(0x228) == 0 and ram.u8(A + 0xdb) == 0 and ram.u8(B + 0xdb) == 0:
		if opp_hittable() and roll(0xfff) < h(0x292):
			var id: int = w(0x234)
			if id == 0x412 or id == 0x217 or id == 0x607 or id == 0x706:
				if ram.s32(0x80022d18 + cls * 0x10) != 0:
					return 7
				id = w(0x234)
			if id == 0x10f and ram.s32(0x80022d1c + cls * 0x10) != 0:
				return 8
	if (wu(0x22c) & 0x400000) != 0:
		var tid: int = ram.s16(B + 0xa0)
		var bc: int = ram.s16(B + 0x16)
		var tell: bool = tid == 0x189 or tid == 0x18e or tid == 0x17f or tid == 0x181 or (bc == 9 and tid == 0x172) or (bc == 0 and tid == 0x172) or (bc == 3 and tid == 0x152)
		if tell and roll(0xfff) < h(0x272):
			return 1
		if h(0x20a) <= 0x1d and roll(0xfff) < h(0x296):
			sb(0x92, 2)
			return 2
	return choose_tail()
func choose_tail() -> int:
	if (h(0x22c) != 0 and h(0x22c) != 0x607) or h(0x20e) > 0:
		if h(0x6a) != 0 or h(0x50) != 0:
			return 0
		if b(0x92) != 0:
			return 2
		if roll(0xfff) < h(0x254) or (h(0x20e) > 0x1e and roll(0xfff) < h(0x256)):
			sb(0x92, 5)
			return 2
	if (h(0x6c) > 8 and roll(0x1f) == 0) or (h(0x202) != 0 and roll(0xf) == 0):
		return 1
	var reached: bool
	if row_b_now() == wu(0x1dc) and h(0x88) != 0:
		reached = false
	elif row_b_now() == wu(0x1dc) and roll(0xfff) < h(0x25a):
		return 1
	else:
		reached = h(0x88) == 0 and roll(0xfff) < h(0x258)
	if not reached:
		if h(0x20e) < 0x1f or h(0x25a) <= roll(0xfff):
			var near: bool = false
			if ((hu(0x20a) - 9) & 0xffff) < 3 and h(0x2e) < 0x4000:
				near = (wu(0x224) & 0x400000) == 0
			if not near:
				return 0
			if w(0x18) != 2:
				return 0
			if (wu(0x224) & 1) != 0 or ram.u8(A + 0xdb) != 0 or h(0x50) != 0 or w(0x234) != 0x412:
				return 0
			if h(0x25c) <= roll(0xfff):
				return 0
			return 4
	if w(0x234) != 0x412:
		return 1
	return 9 if roll(0x3f) == 0 else 1
func queue_seq(ptr: int) -> void:
	sw(8, 0 if ram.u16(ptr + 2) == 0 else ptr + 2)
	sh(4, cmd_pad(ram.u16(ptr)))
func strategize(s: int) -> bool:
	var count: int = 0
	match s:
		0:
			return false
		1:
			if h(0x20c) == 0:
				count = mark(p_57538)
			elif w(0x234) == 0x607 or w(0x234) == 0x706 or (wu(0x230) & 0x200001) != 0:
				count = mark(p_57e94)
			else:
				count = mark(p_57d58)
			if w(0x234) == 0x412:
				count += mark(func(r: int, e: int) -> bool: return ram.u8(r + 0x2d) != 0 and (ram.u32(r + 4) & 0x20001) == 1 and reach(r, w(0x14)))
		2:
			var n: int = pick_all_range()
			if n < 1:
				var p: int = 0
				if ram.s16(A + 0x32) == 0:
					p = 0xc000
					reset_wait()
					if w(0x234) == 0x217:
						p = 0x8000
				sh(4, p)
			elif pick() >= 0:
				reset_wait()
			return true
		3:
			return rush()
		4:
			sidestep(-1)
			sh(0x68, h(0x68) - 10)
			return true
		5:
			count = mark(func(r: int, e: int) -> bool: return ram.s16(e + 6) == 0x1ee or ram.s16(e + 6) == 0x6a3)
		6:
			count = mark(func(r: int, e: int) -> bool: return ram.s16(e + 6) == 0x22c)
		7:
			queue_seq(ram.u32(0x80022d18 + ram.s16(A + 0x16) * 0x10))
			return true
		8:
			queue_seq(ram.u32(0x80022d1c + ram.s16(A + 0x16) * 0x10))
			return true
		9:
			count = mark(p_strike)
			if count > 0:
				sb(0x8e, 1)
				sh(0x68, 0xffff)
	var done: bool = count > 0
	if done and pick() >= 0:
		reset_wait()
	return done
func mark_double_tap() -> int:
	return mark(func(r: int, e: int) -> bool: return ram.s16(e) == -0x3ffe)
func pick_all_range() -> int:
	var t1: int = 0
	if w(0x1c) >= 0xb87:
		return 0
	if h(0x214) != 0:
		if w(0x234) != 0x217:
			t1 = mark(p_strike)
		if w(0x18) < 3:
			return t1
		return t1 + mark_double_tap()
	if h(0x20c) != 0:
		var id: int = w(0x234)
		var low: int = 0
		match id:
			0x31f:
				t1 = mark(func(r: int, e: int) -> bool: return ram.s16(e) != -0x3ffe and (ram.u32(r + 4) & 0x100) == 0 and ((ram.u32(r + 4) & 0xffff) == 0x1052 or (ram.u32(r + 4) & 0xffff) == 0x2829))
			0x10f:
				t1 = mark(func(r: int, e: int) -> bool: return (ram.u32(r + 4) & 0xffff) == 0x2829)
				if w(0x18) >= 3:
					t1 += mark_double_tap()
			0x217:
				t1 = mark(func(r: int, e: int) -> bool: return ram.s16(e) != -0x3ffe and (ram.u32(r + 4) & 0xffff) == 0x1052)
			0x412:
				var hold: int = ram.u16(A + 0x60)
				if hold == 0x2021 or hold == 0x2829:
					t1 = mark(p_strike)
				else:
					t1 = mark(func(r: int, e: int) -> bool: return ram.s16(e) != -0x3ffe and (ram.u32(r + 4) & 0xffff) == 0x1052)
					if roll(0xfff) % 50 == 0:
						t1 += mark(p_strike)
					if w(0x18) >= 3:
						t1 += mark_double_tap()
			0x706:
				t1 = mark(p_strike)
				if w(0x18) >= 3:
					t1 += mark_double_tap()
	return pick_tail(t1)
func pick_tail(t1: int) -> int:
	if w(0x24) < -70 and w(0x18) < 3:
		return mark_double_tap()
	return t1
func rush() -> bool:
	if h(0x21a) != 0:
		return false
	var dist: int = w(0x1c)
	if b(0x94) == 1:
		var table_pick: bool = true
		if w(0x14) < 3:
			table_pick = roll(0xfff) < h(0x27e)
		if table_pick:
			sb(0x94, ram.u8(0x80022e80 + roll_scaled(7) * 2))
		else:
			sb(0x94, 3)
	if ram.s16(B + 0x16) == 4:
		dist -= 300
	var st: int = b(0x94)
	if (st - 1 >= 2 or st - 1 < 0) and dist >= 2951:
		sb(0x94, 0)
		sh(4, 0)
		return true
	var a3e: int = ram.s16(A + 0x3e)
	match st:
		3:
			reset_wait()
			var rb: int = ram.u32(B + 0x54)
			if ram.u8(rb + 0x2d) != 0 and ram.u8(rb + 0x2e) < ram.s16(B + 0x58):
				return false
			var d: int = h(0x20a)
			if d >= 29:
				if w(0x14) < 3:
					return mark(p_573f4) <= 0
				sh(4, reset_pad())
				sh(0x68, roll(0xf))
				return true
			if d >= 9:
				if dist >= 2951:
					sh(4, 0)
					return true
				if w(0x14) < 3:
					if mark(p_573f4) <= 0:
						return true
					sh(0x68, 0xffff)
					return false
				if a3e >= 0x4000:
					return false
				sb(0x94, 4)
				sh(4, 0x8000)
				return true
			if dist >= 2951:
				sh(4, 0)
			else:
				sh(4, 0x8000 if a3e < 0x4000 else 0)
			return true
		4:
			reset_wait()
			if a3e > 0x4000 and w(0x18) >= 2:
				sh(4, 0x2000)
				return true
			if dist >= 2951:
				sh(4, 0)
				return true
			if h(0x20a) < 9 or w(0x14) >= 2:
				queue_seq(0x80022c46)
				return true
			if mark(p_573f4) <= 0:
				return true
			sh(0x68, 0xffff)
			return false
		5:
			if (wu(0x224) & 0x400000) != 0 or roll(7) != 0 or h(0x20a) < 7:
				sh(4, 0x2000)
				return false
			if a3e >= 0x4000:
				sb(0x94, 3)
			sidestep(-1)
			return true
		6:
			reset_wait()
			if dist >= 2951:
				sh(4, 0)
				return true
			var d6: int = h(0x20a)
			if d6 >= 29:
				sh(4, 0x8000 if w(0x18) > 0 else 0)
				return true
			if w(0x18) >= 2 or d6 < 8:
				queue_seq(0x80022c46)
				return true
			sh(4, 0x3000)
			sh(0x48, 0x14)
			return true
	return false
func reset_pad() -> int:
	reset_wait()
	return 0x2000 if (hu(2) & 1) == 0 else 0
func resolve_lists() -> void:
	var f: int = wu(0x64)
	var frame: int = ram.s16(A + 0x58)
	if h(0xc0) > 0:
		var m: int = 0
		for k in maxi(h(0xc2), 0):
			var e: int = wu(0xc4 + k * 4)
			if listed_ok(e, frame):
				ram.w32(SCRATCH + m * 4, e)
				m += 1
		sh(0xc0, 0)
		sh(0xc2, 0)
		sh(0xd4, 1)
	if h(0xd8) > 0:
		var m: int = 0
		for k in maxi(h(0xda), 0):
			var e: int = wu(0xdc + k * 4)
			if listed_ok(e, frame):
				ram.w32(SCRATCH + m * 4, e)
				m += 1
		sh(0xd8, 0)
		sh(0xda, 0)
	if h(0x1a0) > -1:
		for k in maxi(h(0x1a2), 0):
			var e: int = wu(0x1a4 + k * 4)
			if listed_ok(e, frame):
				ram.w32(SCRATCH, e)
		sh(0x1a0, 0)
		sh(0x1a2, 0)
func listed_ok(e: int, frame: int) -> bool:
	return ram.u8(e + 9) <= frame and frame <= ram.u8(e + 10) and stance_ok(ram.u8(e + 2)) and cond_ok(e)
func approach() -> bool:
	if h(0x50) != 0:
		return false
	var c1: bool = ram.u8(row_b_now() + 0x19) == 0 or w(0x18) > 1 or roll(0xfff) >= h(0x280)
	var pad: int = 0
	var c2: bool = h(0x2e) > 0x3fff
	if not c2:
		pad = 0x6000
		c2 = w(0x24) > -0xb
	var c3: bool = ram.u8(row_b_now() + 0x1a) - ram.s16(B + 0x58) < 0x15
	if not c3:
		pad = 0x2000
		c3 = h(0x2e) < 0x4001
	if not (c1 or (c2 and c3)):
		sh(4, pad)
		return true
	if h(0x2e) < 0x6001 or w(0x18) > 1:
		if h(0x2e) > 0x1000:
			var v: int = roll(0x7fff)
			if v < h(0x2e):
				var w2: int = roll(0xfff)
				if h(0x27e) <= w2:
					sh(0x38, 8)
					sh(0x3a, 0)
					sh(0x40, 0x30)
					if ram.s16(A + 0x16) == 7:
						sh(4, 0x8000 if h(0x2e) > 0x3fff else 0x2000)
						return true
					var p: int
					if h(0x20c) == 0 or roll(7) != 0:
						p = 0x2000
						if w(0x18) < 3:
							p = 0x2000 if (hu(2) & 1) == 0 else 0x8000
					else:
						p = 0
						if ram.s16(A + 0x32) == 0:
							p = 0xc000
							reset_wait()
							if w(0x234) == 0x217:
								p = 0x8000
					sh(4, p)
					return true
		return false
	if ram.u8(B + 0xdb) == 0:
		if h(0x208) == 0:
			if h(0x27e) <= roll(0xfff):
				sh(0x68, 0xfffe)
				return false
			if ram.s16(A + 0x16) == 7:
				sh(4, 0x8000 if h(0x2e) > 0x3fff else 0x2000)
			else:
				sh(4, 0x2000)
		else:
			sh(4, 0x4040 if (hu(2) & 1) != 0 else 0x4020)
	else:
		sh(4, 0)
	return true
func mark_input(input: int) -> int:
	return mark(func(r: int, e: int) -> bool: return ram.s16(e) == input)
func p_cover_a(r: int, e: int) -> bool:
	var f8: int = ram.u32(r + 8)
	if ram.u8(r + 0x2d) >= 0x51:
		return false
	return ((f8 & 0x10000) != 0 or (f8 & 0xffff) == 0x51f) and (f8 & 0x400000) == 0
func p_cover_b(r: int, e: int) -> bool:
	var f8: int = ram.u32(r + 8)
	if ram.u8(r + 0x2d) >= 0x51:
		return false
	return ((f8 & 0x10000) != 0 or (f8 & 0xffff) == 0x51f or (f8 & 0xffff) == 0x10f) and (f8 & 0x400000) == 0
func p_hold(r: int, e: int) -> bool:
	return (ram.u32(r + 8) & 0x10000) != 0 and ram.u8(r + 0x2d) == 0 and ram.u8(r + 0x19) == 0
func p_mixup(r: int, e: int) -> bool:
	return ram.s16(e) == -0x3fff or ((ram.u32(r + 4) & 0xa0000) == 0x80000 and (ram.u32(r + 4) & 0x600000) == 0)
func p_launch(r: int, e: int) -> bool:
	return ram.u8(r + 0x19) != 0 and (ram.u32(r + 4) & 0x20000) == 0 and ((ram.u32(r + 4) & 0x80000) != 0 or (ram.u32(r + 8) & 0x200000) != 0)
func p_plain(r: int, e: int) -> bool:
	return ram.u8(r + 0x2d) == 0 and ram.u8(r + 0x19) == 0 and (ram.u32(r + 4) & 0x20000) == 0 and ram.s16(e + 6) != 0x1ee and ram.s16(e + 6) != 0x6a3
func p_chain(r: int, e: int) -> bool:
	return ram.u8(r + 0x2d) != 0 and ((ram.u32(r + 4) & 0x80000) != 0 or (ram.u32(r + 8) & 0x200000) != 0) and (ram.u32(r + 4) & 0x20000) == 0
func p_low(r: int, e: int) -> bool:
	return (ram.u32(r + 4) & 0xa0000) == 0x80000 and ram.u8(r + 0x19) == 0
func engage() -> void:
	resolve_lists()
	if approach():
		return
	if h(0x4c) >= 1:
		sh(0x4c, h(0x4c) - 1)
		sh(4, hu(6) & 0xf000)
		return
	if h(0x44) >= 5:
		sh(4, hu(6) & 0xf000)
		return
	var done: bool = false
	if w(0x14) < 4 and h(0x21a) == 0 and h(0x1d2) < h(0x1d4):
		var skip: bool = false
		if w(0x14) > 2 and roll_scaled(12) != 0:
			skip = true
		if not skip and w(0x14) > 1 and roll_scaled(8) == 0:
			skip = true
		if not skip:
			if h(0x3a) == 0:
				done = attack_decision()
			elif h(0x6c) < 1 and (h(0x20c) == 0 or w(0x18) > 3):
				if (wu(0x230) & 4) != 0 and roll_scaled(0x1000) < 0x100:
					done = false
				else:
					done = attack_decision()
			else:
				sh(4, 0x8000)
				done = true
	if done:
		return
	finale()
func attack_decision() -> bool:
	var intent: int = h(0x68)
	var urge: int = h(0x248)
	if h(0xd4) != 0:
		var gone: int = 0
		for i in maxi(h(0x70), 0):
			if rec_mark(i) > -1 and (ram.u32(rec_row(i) + 0x24) >> 8 & 0x20) != 0:
				if rec_mark(i) > 0:
					gone += 1
				set_mark(i, 0xffff)
		sh(0x72, h(0x72) - gone)
	var wait: int
	if w(0x80) < 0x1a:
		wait = h(0x6c)
	else:
		wait = h(0x6c)
		if wait < 0:
			if h(0x6a) == 0:
				var span: int = h(0x20a) - (roll(7) + 4)
				if span < 3:
					span = 3
				sh(0x6c, span)
			wait = h(0x6c)
	var count: int = 0
	if wait < 1:
		var rush_up: bool = b(0x8f) != 0 or b(0x91) != 0
		if not rush_up and w(0x80) > 0x19:
			rush_up = h(0x27e) / 2 <= roll(0xfff)
		if not rush_up and w(0x84) - 1 >= 0 and w(0x84) - 1 < 0x13:
			rush_up = h(0x27e) <= roll(0xfff)
		if rush_up:
			intent = -1
		var v: int = roll(0xfff)
		if v < h(0x280) and ram.u8(B + 0xdb) != 0 and h(0x230) != 0x4c02:
			var late: int = ram.u8(row_b_now() + 0x1a)
			var early: int = ram.u8(row_b_now() + 0x19)
			var mid: int = early + int((late - early) / 2)
			if mid <= ram.s16(B + 0x58) and ram.s16(B + 0x58) <= late and h(0x2e) < 0x4001 and w(0x14) == 2:
				sh(0x68, 0xffff)
		if ram.s16(B + 0xa0) == 6 and w(0x14) < 3 and roll(0xfff) < h(0x258):
			sh(0x68, h(0x68) - 2)
		if (wu(0x230) & 0x605) != 0 or ram.u8(B + 0xdb) != 0 or ram.u8(B + 0xdf) != 0 or ram.s16(B + 0x16) == 0x13 or h(0x20a) < 10:
			urge = 0
			sb(0x91, 0)
		var r: Array = decide_low(intent, urge)
		if r[0] == 1:
			return post(r[1])
		count = r[1]
	else:
		count = 0
		return post(0)
	return pick_and_go()
func post(count: int) -> bool:
	if count == 0 and w(0x18) > 2 and ram.s16(A + 0x122) == 0 and ram.s32(A + 0x3f4) <= int(ram.s32(A + 0x3f8) / 10) and roll(3) == 0 and roll(0xfff) < h(0x258):
		count = mark(func(r: int, e: int) -> bool: return (ram.u32(r + 0x24) >> 8 & 0x100) != 0)
	if count < 0:
		reset_wait()
		return true
	return pick_and_go()
func pick_and_go() -> bool:
	var idx: int = pick()
	if idx < 0:
		return false
	reset_wait()
	var row: int = rec_row(idx)
	if ram.u16(DEMO_FLAG) == 0 and (ram.u32(row + 0x24) >> 8 & 0x20) != 0:
		sh(0xc0, 1)
	elif ((wu(0x224) & 0x80000) != 0 and roll(0x3f) < 0x20) or ((ram.u32(row + 4) & 0x80000) != 0 and roll(0x3f) < 0x30):
		sh(0xd8, 1)
	var seen: int = 0
	if wu(0x5c) != 0:
		seen = ram.s16(wu(0x5c) + 4)
	if seen == 0x2021 or seen == 0x2829:
		sh(0x4c, 0xc)
	if ram.u8(row + 0x2d) == 0 and (ram.u32(row + 4) & 0x80000) == 0:
		return true
	sw(0x60, row)
	return true
func f587d8() -> int:
	var got: int = 0
	var v: int = ram.u32(RNG) >> 1 & 0xfff
	roll(0)
	var z: int = w(0x14)
	if z == 2:
		if v < 0x20:
			got = mark_input(-0x3fff)
	elif z == 3 and v < 0x400:
		got = mark_input(-0x3fff)
	if (wu(0x230) & 1) == 0:
		return got + mark(p_57d58)
	return got + mark(p_57e94)
func decide_low(intent: int, urge: int) -> Array:
	var count: int = 0
	if h(0x208) != 0 and h(0x88) == 0:
		if h(0x50) == 0:
			if h(0x27e) <= roll(0xfff):
				intent = -1
			if h(0x2e) < 0x4001 or roll(0xf) != 0:
				if intent < 0:
					var v: int = roll(0xfff)
					if v < 0x334:
						count = mark(func(r: int, e: int) -> bool: return ram.u8(ram.u32(r + 0xc) + 3) == 0x35 and (ram.u32(r + 8) & 0x400000) == 0)
					elif v < 0x3af:
						sidestep(v & 1)
						count = -1
					elif v < 0x6e2:
						count = mark(p_cover_a)
					elif v < 0x75d and (wu(0x224) & 1) == 0:
						count = mark(p_strike)
					elif v < 0x829:
						count = mark_double_tap()
					elif w(0x14) - 2 >= 0 and w(0x14) - 2 < 2 and v < 0x9c3:
						queue_seq(0x80022c2a)
						count = -1
					else:
						count = mark(p_cover_b)
			else:
				count = mark(func(r: int, e: int) -> bool: return (ram.u32(r + 4) & 0x20000) != 0)
		return [1, count if count >= 0 else -1]
	if h(0x230) == 0x4c02 and roll(0xfff) < h(0x274):
		if w(0x14) < 3:
			if w(0x14) > 1:
				if roll(0xf) == 0:
					count = mark_input(-0x3fff)
				else:
					count = mark(p_hold)
		else:
			var held: bool = false
			if w(0x24) < 0x33 and roll(7) == 0:
				count = mark(p_hold)
				held = true
			if not held:
				count = mark_input(-0x3fff)
				if count > 0:
					sh(0x3a, 2)
					sh(0x38, 0xfa)
					sh(0x40, 0x136)
		if w(0x14) < 4 and h(0x21a) == 0 and h(0x27e) <= roll(0xfff):
			sh(0x68, 0xffff)
			if ram.u8(B + 0xdb) == 0 and roll(0x3f) < 0x20 and w(0x7c) == 0:
				count += mark(p_579a0)
			else:
				count += mark(p_577dc)
		return [1, count]
	if h(0x46) > -1:
		count = mark(p_chain)
		if count > 0:
			sh(0x46, 0xffff)
		return [1, count]
	if h(0x20e) != 0:
		if b(0x8f) == 0 and roll(0xfff) >= h(0x258):
			if intent < 1:
				count = mark(p_573f4) if (wu(0x230) & 1) != 0 else mark(p_572a4)
		else:
			count = f587d8()
		return [1, count]
	if (h(0x20c) != 0 or h(0x214) != 0) and h(0x88) == 0:
		if b(0x8f) != 0 or roll(0xfff) < h(0x258):
			count = f587d8()
		elif intent < 1:
			count = mark(p_573f4) if (wu(0x230) & 1) != 0 else mark(p_572a4)
		return [1, count]
	if intent < 1:
		return [1, chase(urge)]
	if w(0x14) > 2 or (wu(0x224) & 1) != 0 or roll(0xfff) > 3:
		return [1, 0]
	var n: int = mark(p_strike)
	if n < 1:
		return [1, 0]
	return [0, n]
func chase(urge: int) -> int:
	var count: int = 0
	var taken: bool = false
	if h(0x44) < 0:
		if (b(0x91) != 0 or roll(0xfff) < urge) and w(0x14) < 2 and ram.s16(B + 0x16) != 0x13:
			if roll(0xfff) < h(0x24e):
				count = mark(func(r: int, e: int) -> bool: return (ram.u32(r + 8) & 0x400000) != 0 and (ram.u16(e) & 0xc200) != 0x200)
				if count < 1 and w(0x14) < 2:
					count = mark(func(r: int, e: int) -> bool: return (ram.u32(r + 8) & 0x400000) != 0 and (ram.u16(e) & 0xffe0) == 0)
				else:
					sh(0x98, 1)
			elif w(0x14) < 2:
				count = mark(func(r: int, e: int) -> bool: return (ram.u32(r + 8) & 0x400000) != 0 and (ram.u16(e) & 0xffe0) == 0)
			if count > 0:
				return count
		var tbl: int = ram.u32(0x80022d20 + ram.s16(A + 0x16) * 16)
		if h(0x42) < 0 and tbl != 0 and h(0x50) == 0 and (wu(0x224) & 1) == 0 and ram.s16(A + 0xa0) != ram.s16(tbl + 2) and h(0x2e) < 0x2001 and ram.u8(A + 0xdb) == 0 and w(0x14) < 3 and h(0x208) == 0:
			var v: int = roll(0xfff)
			var p: int = tbl
			while true:
				if v <= ram.s16(p):
					if reaches(ram.s16(p + 2)):
						queue_seq(ram.u32(p + 4) + 2)
						taken = true
						sh(0xd8, 1)
						sh(0x42, roll(0xf) + 0x1c)
					break
				p += 8
				if ram.s16(p) < 0:
					break
		if not taken:
			return chase_free()
		return -1
	count = mark(p_low)
	sh(0x44, 0xffff)
	return count
func chase_free() -> int:
	if w(0x14) < 3 and ram.u8(A + 0xdb) == 0 and (wu(0x224) & 1) == 0 and roll(0x3f) < 0xe:
		return mark(p_strike)
	var count: int = 0
	if roll(0x3f) < 0x20:
		if roll(1) != 0:
			return mark(p_mixup)
		return mark(p_577dc)
	if h(0x44) < 0 and h(0x46) < 0 and (wu(0x224) & 1) == 0 and ram.u8(A + 0xdb) == 0 and roll(0xfff) < 0x200:
		count = mark(p_strike)
		if count > 0:
			sh(0x44, 0x12)
			sh(0x68, 0xffff)
			return count
	count = mark(p_mixup)
	if roll(0xfff) < h(0x250):
		return count + mark(p_5766c)
	if roll(0xfff) < h(0x252):
		return count + mark(p_57538)
	if (wu(0x230) & 1) == 0 or roll(0xfff) < h(0x27e):
		if roll(0x3f) < 10:
			return count + mark(p_57b60)
		if ram.u8(A + 0xdb) == 0 and h(0x46) < 0:
			if roll_scaled(0x1000) < 0x200:
				count = mark(p_launch)
				if count > 0:
					var a: int = roll_scaled(4)
					var b2: int = roll_scaled(4)
					var c: int = roll_scaled(4)
					sh(0x46, a + b2 + c + 1)
					return count
		if roll_scaled(0x1000) < 10:
			return count + mark(p_plain)
		return count + mark(p_572a4)
	return count + mark(p_573f4)
func default_pad() -> void:
	if h(0x4a) < 0:
		sh(4, 0 if h(0x48) < 0 else hu(6) & 0xf000)
	else:
		sh(4, 0x4000)
func finale() -> void:
	var u: int = 0
	if h(0x8a) < 0:
		if h(0x38) < 0:
			if h(0x50) == 0 and h(0x4a) < 0 and h(0x48) < 0 and h(0x46) < 0:
				u = finale_y()
		elif (b(0x200) == 0 or w(0x1c) > 7000) and w(0x14) > 0:
			var s: int = finale_x()
			if s < 0:
				reset_wait()
				u = finale_y()
			else:
				u = s
		else:
			reset_wait()
			u = finale_y()
	if u == 0:
		default_pad()
func finale_x() -> int:
	if h(0x27e) <= roll(0xfff):
		var hittable: bool = false
		if h(0x20c) != 0 and h(0x6a) == 0 and ram.s16(A + 0x3e) < 0x5000:
			if w(0x1c) < 0xb87:
				var f8: int = ram.u32(row_b_now() + 8)
				var t: int = f8 & 0xffff0000
				if (f8 & 0x1c0000) == 0:
					t |= 0xc0000
				hittable = (t & ram.u32(0x80098248 + w(0x18) * 4)) != 0
		if hittable:
			return -1
	if h(0x3a) == 2:
		var pad: int
		if b(0x200) == 0 or w(0x1c) > 7000:
			if w(0x18) < 3 and roll(0xfff) < 0x20:
				reset_wait()
				pad = 0x8000
			else:
				pad = 0x2000
		else:
			reset_wait()
			pad = 0x8000
		sh(4, pad)
		return 1
	if h(0x68) < 0x24 and w(0x18) == 2 and roll(0xf) == 0:
		if mark_input(-0x3fff) > 0:
			if pick() > -1:
				sh(0x3a, 0)
				sh(0x38, 0)
				sh(0x40, 0x28)
				return 1
	sh(4, hu(6) & 0xf000)
	return 1
func finale_y() -> int:
	if not (h(0x40) < 0 and h(0x48) < 0):
		return 0
	var r: int = roll_scaled(0x1000)
	var t: int = 0
	if b(0x200) != 0:
		return dispatch_move(0)
	if h(0x68) < 0x24:
		match w(0x14):
			0, 1:
				if r < 0x14:
					t = 3
			2:
				if r < 0x7a:
					t = 5
				elif r < 0x1eb:
					t = 1
				elif r < 0x214:
					t = 3
				elif r < h(0x25c) * 4096 / 1000:
					t = 8
			3:
				if r < 0x666:
					t = 2
				elif r < 0xb33:
					t = 1
			4:
				if r < 0xcc:
					t = 2
				elif r < 0x599:
					t = 4
				else:
					t = 1
			5:
				t = 4
				if h(0x2a) < 0x2d1 and h(0x208) == 0 and 0x11d < r:
					t = 1
	else:
		match w(0x18):
			0, 1:
				if r < 0x199:
					t = 6
				elif r < 0x333:
					t = 3
			2:
				if r <= 0x27:
					t = 2
				elif r < 0x170:
					t = 3
			3:
				if r < 0x1eb:
					t = 2
				elif r < 0x214:
					t = 5
				elif r < 0x218:
					t = 3
				elif r < 0x22d:
					t = 1
				elif r < 0x241 and (wu(0x224) & 2) != 0:
					t = 8
			4:
				if r < 0x80:
					t = 2
				elif r < 0x90:
					t = 5
				elif r < 0xc0:
					t = 8
				elif r < 0x3c0:
					t = 1
			5:
				if h(0x2a) < 0x2d1 and h(0x208) == 0 and 0x50 < r:
					if r < 0xcc:
						t = 2
					elif r < 0x400:
						t = 1
					elif r < 0x5eb:
						t = 5
				else:
					t = 4
		if (t == 3 or t == 6) and h(0x284) <= roll(0xfff):
			t = 0
	if (t == 3 or t == 6) and ((wu(0x230) & 0x80000) != 0 or w(0x234) != 0) and roll(0xfff) < h(0x27e):
		t = 0
	return dispatch_move(t)
func dispatch_move(t: int) -> int:
	match t:
		0:
			return 0
		1:
			if mark_input(-0x3fff) > 0:
				sh(0x3a, 0)
				sh(0x38, 0)
				sh(0x40, 0x28)
				return 1 if pick() >= 0 else 0
			var z: int = w(0x14)
			var lo: int
			var hi: int
			if z < 0 or z > 3:
				var q: int = roll_scaled(0xf)
				lo = q + 0xf
				hi = q + 0x37
			elif z < 3:
				var q: int = roll_scaled(8)
				lo = q + 4
				hi = q + 0x2c
			else:
				var q: int = roll_scaled(10)
				lo = q + 10
				hi = q + 0x32
			sh(0x3a, 0)
			sh(0x38, lo)
			sh(0x40, hi)
			sh(4, 0x6000 if h(0x3c) > 0 else 0x2000)
			return 1
		2:
			var z2: int = w(0x14)
			var lo2: int
			var hi2: int
			if z2 >= 0 and z2 < 3:
				var q2: int = roll_scaled(8)
				lo2 = q2 + 4
				hi2 = q2 + 0x2c
			elif z2 == 3:
				var q2: int = roll_scaled(10)
				lo2 = q2 + 10
				hi2 = q2 + 0x32
			else:
				var q2: int = roll_scaled(0xf)
				lo2 = q2 + 0xf
				hi2 = q2 + 0x37
			sh(0x3a, 0)
			sh(0x38, lo2)
			sh(0x40, hi2)
			sh(4, 0x6000 if h(0x3c) > 0 else 0x2000)
			return 1
		3:
			var q3: int = roll_scaled(5)
			sh(0x38, q3 + 0x14)
			sh(0x3a, 0)
			sh(0x40, q3 + 0x3c)
			sh(4, 0xc000 if h(0x3c) > 0 else 0x8000)
			return 1
		4:
			if mark_input(-0x3fff) < 1:
				var q4: int = roll_scaled(0x14)
				sh(0x38, q4 + 0x28)
				sh(0x3a, 0)
				sh(0x40, q4 + 0x50)
				sh(4, 0x6000 if h(0x3c) > 0 else 0x2000)
				return 1
			sh(0x3a, 2)
			sh(0x38, 0xfa)
			sh(0x40, 0x136)
			return 1 if pick() >= 0 else 0
		5:
			var q5: int = roll_scaled(0x14)
			sh(0x38, q5 + 0x28)
			sh(0x3a, 0)
			sh(0x40, q5 + 0x50)
			sh(4, 0x6000 if h(0x3c) > 0 else 0x2000)
			return 1
		6:
			if mark_double_tap() < 1:
				var q6: int = roll_scaled(5)
				sh(0x38, q6 + 0x14)
				sh(0x3a, 0)
				sh(0x40, q6 + 0x3c)
				sh(4, 0xc000 if h(0x3c) > 0 else 0x8000)
				return 1
			sh(0x40, 0x3c)
			return 1 if pick() >= 0 else 0
		8:
			if w(0x18) > 2 or h(0x20a) > 10:
				sidestep(-1)
			return 1 if pick() >= 0 else 0
	return 1 if pick() >= 0 else 0
func install_cull() -> void:
	sw(0x7c, 0x800613cc)
func cull_listed() -> int:
	var got: int = 0
	for i in h(0x70):
		if rec_mark(i) >= 0:
			var f8: int = ram.u32(rec_row(i) + 8)
			if (f8 & 0x10000) != 0 or (f8 & 0xffff) == 0x10f:
				if rec_mark(i) > 0:
					got += 1
				set_mark(i, 0xffff)
	sh(0x72, h(0x72) - got)
	return got
func side_pick() -> int:
	if (ram.u32(row_a_now() + 4) & 0x400000) != 0 or w(0x1c) >= 7001:
		return -1
	var left: int = 1 if ram.s16(B + 0x1278) < ram.s16(A + 0x1278) else 0
	var ang: int = ram.u16(A + 0x3c)
	var s: int
	if ((ang - 257) & 0xffffffff) < 32511:
		s = 0
	elif ((ang + 0x7fff) & 0xffff) < 32510:
		s = 1
	else:
		return -1
	return 1 - s if left != 0 else s
func row_a_now() -> int:
	return ram.u32(A + 0x54)
func f57018() -> bool:
	var frame: int = ram.s16(A + 0x58)
	var table: int = wu(0xc)
	var found: bool = false
	for e in entries(row_a_now()):
		if ram.u8(e + 9) <= frame and frame <= ram.u8(e + 10) and stance_ok(ram.u8(e + 2)) and cond_ok(e):
			if (ram.u32(ram.u32(table + ram.u16(e + 6) * 4) + 8) & 0x400000) != 0:
				found = true
	return found
func call_hook(ptr: int) -> int:
	match ptr:
		0x800628c4:
			if ram.s16(B + 0xa0) == 0x2c7 and w(0x18) < 3:
				if ram.s16(B + 0x58) < 16:
					sh(0x68, 0xffff)
					return -1
				return 0x8000
			return -1
		0x80062928, 0x80062930, 0x80062938, 0x80062994:
			return -1
		0x8006299c:
			if ram.s16(A + 0xa0) == 0xde3 and (((ram.u16(A + 0x58) - 0xd) & 0xffffffff) > 4 or h(0x20a) > 9):
				return -1 if (hw_rand() & 0xf) == 0 else 0x2000
			return -1
		0x80062940:
			return hook_19()
		0x80061b88:
			return hook_4()
		0x80061ef0:
			return hook_14()
		0x8006251c:
			return hook_3()
	return -1
func hook_3() -> int:
	var v: int = roll(0xfff)
	if h(0x68) > 0 or v >= h(0x24e):
		return -1
	if ram.s16(B + 0x16) != 0x13 and (wu(0x230) & 2) != 0 and w(0x14) < 3 and ram.u8(B + 0xdb) == 0 and ram.u8(B + 0xdf) == 0 and ram.u8(row_a_now() + 0x2d) == 0 and h(0x20a) >= 9 and ram.s16(A + 0x32) == 0 and ram.s16(A + 0x40) == 0 and (hw_rand() & 7) == 0 and reaches(0x15):
		queue_seq(0x800230de + (hw_rand() & 0xfff) % 3 * 14)
		sh(0xd8, 1)
		return -2
	if (wu(0x230) & 1) != 0 and w(0x14) < 2 and ram.u8(B + 0xdf) == 0 and ram.u8(row_a_now() + 0x2d) == 0 and h(0x20a) >= 9 and ram.s16(A + 0x32) == 0 and ram.s16(A + 0x40) == 0 and f57018():
		queue_seq(0x800230c2 + (hw_rand() & 1) * 14)
		return -2
	if h(0x208) == 0 or w(0x14) >= 2:
		return -1
	if ram.s16(A + 0x40) != 0 and ram.s16(A + 0x40) != 2:
		return -1
	if ram.s16(A + 0x32) != 0 or ram.u8(B + 0xdf) != 0 or ram.u8(row_a_now() + 0x2d) != 0 or h(0x20a) < 9 or h(0x88) != 0:
		return -1
	if not f57018():
		return -1
	queue_seq(0x800230a6 + (hw_rand() & 1) * 14)
	return -2
func hook_4() -> int:
	var id: int = ram.s16(B + 0xa0)
	var frame: int = ram.s16(B + 0x58)
	var dist: int = w(0x1c)
	var t1: int = h(0x20a)
	var a3e: int = ram.s16(A + 0x3e)
	if id == 0x16f:
		if w(0x18) < 3:
			sh(0x68, 0xffff)
		return -1
	if id == 0x456:
		if w(0x18) >= 3:
			return 0x2000
		sh(0x8c, 4)
		install_cull()
		sh(0x68, 0xffff)
		return -1
	if id >= 0x459 and id <= 0x45b:
		if w(0x14) <= 0:
			var rb: int = ram.u32(B + 0x54)
			if frame >= ram.u8(rb + 0x2d) and ram.u8(rb + 0x2e) >= frame:
				return 0
			install_cull()
			sh(0x68, 0xffff)
			sh(0x8c, 4)
			return -2
		if ((ram.u16(A + 0x30) - 0x2000) & 0xffffffff) < 16385:
			sh(0x8c, 20)
			if w(0x14) < 2:
				install_cull()
				sh(0x68, 0xffff)
				return -1
			return 0x2000
		if w(0x14) < 3:
			if (hw_rand() & 7) != 0:
				return 0
			if (wu(0x224) & 0x400001) != 0:
				return 0
			sidestep(-1)
			return -2
		sh(0x8c, 10)
		return 0x2000
	if id == 0x472:
		return -1
	if id == 0x16a or id == 0x43a:
		var rb2: int = ram.u32(B + 0x54)
		if ram.u8(rb2 + 0x2d) != 0 and ram.u8(rb2 + 0x2e) < frame:
			sh(0x68, 0xffff)
			return 0
		if a3e > 0x1000:
			return 0x2000 if w(0x18) >= 2 else -1
		if w(0x18) >= 3 and dist < 2701:
			queue_seq(0x80022c46)
			return -2
		if w(0x18) < 2 and t1 >= 11:
			return -1
		if w(0x18) >= 3 or t1 < 11:
			return 0
		sidestep(hw_rand() & 1)
		return -2
	if id == 0x458 or id == 0x49c or id == 0x49d or id == 0x49e:
		if a3e >= 0x4000:
			if w(0x14) < 2:
				sh(0x68, 0xffff)
			return -1
		if w(0x14) < 2:
			sh(0x68, 1)
			return 0
		if w(0x14) >= 3:
			return 0x2000
		install_cull()
		sh(0x68, 0xffff)
		return -1
	return -1
func hook_14() -> int:
	var id: int = ram.s16(B + 0xa0)
	var frame: int = ram.s16(B + 0x58)
	var rb: int = ram.u32(B + 0x54)
	var start: int = ram.u8(rb + 0x2d)
	var end: int = ram.u8(rb + 0x2e)
	var a30: int = ram.s16(A + 0x30)
	if id == 3556:
		sh(0x8c, 8)
		if ((frame - 9) & 0xffffffff) < 5 and w(0x14) < 2 and (hw_rand() & 0x1f) == 0:
			install_cull()
			sh(0x68, 0xffff)
			return 0x2000
		if frame < start - 30:
			if w(0x14) < 2:
				sh(0x68, 0xffff)
				return 0x2000
			if w(0x14) < 3:
				sh(0x68, h(0x68) - 4)
				return 0x2000
			return side_move()
		if frame < start - 20:
			if a30 < 14336:
				if w(0x14) < 3:
					return 0
				return 0x2000 if w(0x14) < 4 else rand_pad()
			if w(0x14) < 3:
				return 0x2000
			return side_move()
		if frame < end:
			if a30 >= 24576:
				sh(0x68, 8)
				return 0x8000
			if a30 >= 14336:
				if w(0x14) < 2:
					sh(0x68, 8)
					return 0
				return 0x2000
			var s: int = side_pick()
			if s != -1:
				sidestep(s)
				return -2
			return 0x2000 if ram.s16(A + 0x32) == 0 else 0
		if frame < start + 40:
			if w(0x14) < 2:
				sh(0x68, 0xffff)
				return 0x2000
			return rand_pad()
		if w(0x14) < 3:
			sh(0x68, 0xffff)
			return 0x2000
		return rand_pad()
	if id != 366:
		return -1
	sh(0x8c, 8)
	if frame < start - 8:
		var s2: int = -1
		if ((ram.u16(A + 0x2e) + 0x2000) & 0xffff) < 16385 and (ram.u32(row_a_now() + 4) & 0x400000) == 0:
			if w(0x1c) < 7001:
				s2 = 1 if ram.s16(A + 0x1278) < ram.s16(B + 0x1278) else 0
		if w(0x14) <= 0:
			sh(0x68, 0xffff)
			return 0x2000
		if w(0x14) < 3:
			return 0x2000
		if (hw_rand() & 7) != 0:
			return rand_pad()
		if ram.s16(A + 0x32) != 0 or s2 < 0 or s2 > 1:
			return rand_pad()
		sidestep(s2)
		return -2
	if frame >= end:
		return -1
	if ram.s16(A + 0x32) == 0:
		return 0x6000 if w(0x1c) < 7001 else 0
	var z: int = w(0x14)
	if z < 2:
		return ram.u16(0x8002309c + (hw_rand() & 3) * 2)
	if z == 2:
		return 0x6000
	return rand_pad()
func side_move() -> int:
	var s: int = side_pick()
	if s == -1:
		return 0x2000
	sidestep(s)
	return -2
func rand_pad() -> int:
	return 0x2000 if (hw_rand() & 7) == 0 else 0
func hook_19() -> int:
	if ram.s16(B + 0xa0) != 0x137:
		return -1
	var z: int = w(0x18)
	if z < 2:
		sh(0x68, 0xffff)
		return -2
	if z >= 4:
		return 0x8000
	return -1
