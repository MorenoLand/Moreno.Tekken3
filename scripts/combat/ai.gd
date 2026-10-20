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
				if not stance_ok(ram.u8(e + 2)) or not default_cond(e):
					continue
				if n < LIST_COUNT:
					ram.w32(LIST + n * 12, ram.u32(table + ram.u16(e + 6) * 4))
					ram.w32(LIST + n * 12 + 4, e)
					ram.w16(LIST + n * 12 + 8, 0)
					n += 1
				else:
					full = true
		else:
			if ram.u8(p + 9) < 2 and frame <= ram.u8(p + 10) and stance_ok(ram.u8(p + 2)) and default_cond(p):
				if n >= LIST_COUNT:
					break
				ram.w32(LIST + n * 12, ram.u32(table + ram.u16(p + 6) * 4))
				ram.w32(LIST + n * 12 + 4, p)
				ram.w16(LIST + n * 12 + 8, 0)
				n += 1
		p += 12
	return n
func default_cond(entry: int) -> bool:
	var code: int = ram.u8(entry + 3)
	var f: int = wu(0x64)
	if code == 0 or code == 0x26 or code == 0x30 or code == 0x27:
		return true
	if code == 0x24:
		return (f & 1) != 0
	if code == 0x25:
		return (f & 2) != 0
	return Commands.condition(ram, entry, A, B)
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
