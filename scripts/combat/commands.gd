extends RefCounted
# Cancel-list evaluation: which input, stance and condition code lets a move chain into another.
# Fields are read with ram.u8/u16/u32 at "actor + offset"; offsets are listed at the top of ram.gd.
const Pad := preload("res://scripts/combat/pad.gd")
const SHARED_ENTRIES := 0x80017c78
const PATTERN_TABLE_A := 0x800954d0
const PATTERN_TABLE_B := 0x800955cc
const HIT_KIND := 0x80095764
const END := 0xc000
const SHARED := 0xc00c
const REPEAT := 0xc00d
static func reset_hit_kind(ram, player: int) -> void:
	ram.w32(HIT_KIND + player * 4, 0)
static func input_matches(ram, a: int, entry: int, held_dir: int, pressed: int) -> bool:
	var v: int = ram.u16(entry)
	if v < 0xc000:
		if (v & held_dir) == 0 and (v & 0x3fe0) != 0:
			return false
		if (v & 0x1f) != 0x10:
			if v & 0x10:
				return (v & 0xf & pressed & 0xffff) != 0
			var low: int = v & 0xf
			if low != 0 or (pressed & 0xffff) != 0:
				if (low & pressed & 0xffff) == 0:
					return false
				return low == (ram.u16(a + Pad.HELD_BUTTONS) & low)
		return true
	if v < 0xc00e:
		if v == 0xc001:
			return double_tap(ram, a, 6)
		if v == 0xc002:
			return double_tap(ram, a, 4)
		return false
	if v < 0xc7ff:
		var i: int = v - 0xc00e
		if i < 0x3f:
			return pattern(ram, a, ram.u32(PATTERN_TABLE_A + i * 4))
	else:
		var j: int = v - 0xc7ff
		if j < 0x29:
			return pattern(ram, a, ram.u32(PATTERN_TABLE_B + j * 4))
	return false
static func double_tap(ram, a: int, dir: int) -> bool:
	var h: int = ram.s32(a + Pad.HISTORY_INDEX)
	if (ram.u8(a + Pad.HISTORY + h) & 0xf) != dir:
		return false
	var i: int = 0x3b if h <= 0 else h - 1
	if (ram.u8(a + Pad.HISTORY + i) & 0xf) != 5:
		return false
	var n := 0x13
	var j := 0
	while true:
		j = 0x3b if i <= 0 else i - 1
		var c: int = ram.u8(a + Pad.HISTORY + j) & 0xf
		if c != 5:
			if c != dir:
				return false
			break
		n -= 1
		i = j
		if n <= 0:
			break
	if n <= 0:
		return false
	while true:
		var k: int = 0x3b if j <= 0 else j - 1
		if (ram.u8(a + Pad.HISTORY + k) & 0xf) == dir:
			n -= 1
			j = k
			if n <= 0:
				break
		else:
			break
	return n > 0
static func pattern(ram, a: int, seq: int) -> bool:
	var h: int = ram.u32(a + Pad.HISTORY_INDEX)
	var window: int = ram.s16(seq)
	var end: int = seq + 2
	if ram.u16(end) != 0:
		end += 2
		while ram.u16(end) != 0:
			end += 2
	var at: int = end - 2
	var want: int = ram.u16(at)
	var pos: int
	if (want & 0xf) == want:
		pos = 0 if h >= 0x3b else h + 1
	else:
		var hi: int = want >> 8
		if (want & 0xf) != (ram.u8(a + Pad.HISTORY + h) & 0xf):
			return false
		var pressed: int = ram.u16(a + Pad.PRESSED_BUTTONS)
		var ok := false
		if (hi & 0x1f) == 0x10:
			ok = true
		elif (hi & 0x10) == 0:
			var m: int = hi & 0xf
			if m == 0 and pressed == 0:
				ok = true
			else:
				ok = (pressed & m) != 0 and m == (ram.u16(a + Pad.HELD_BUTTONS) & m)
		else:
			ok = (pressed & hi & 0xf) != 0
		if not ok:
			return false
		at = end - 4
		if at == seq:
			return true
		want = ram.u16(at)
		pos = h
	while true:
		if window < 1:
			return false
		var prev: int = 0x3b if pos <= 0 else pos - 1
		var rec: int = ram.u8(a + Pad.HISTORY + prev)
		var hit := false
		if (want & 0xf) == (rec & 0xf):
			var bits: int = want >> 8
			if (bits & 0x1f) == 0x10:
				hit = true
			else:
				hit = (bits & (rec >> 4)) != 0
				if (bits & 0x10) == 0:
					hit = (bits & 0xf) == (rec >> 4)
		if not hit:
			if (rec >> 4) != 0:
				return false
		else:
			at -= 2
			if at == seq:
				return true
			want = ram.u16(at)
		window -= 1
		pos = prev
	return false
static func by_quadrant(q: int, kinds: Array) -> int:
	return kinds[q] if q >= 0 and q < 4 else -1
static func hit_kind(ram, player: int, a: int, b: int) -> int:
	var kind := -1
	if ram.u8(a + 0xd1) != 0 and ram.u8(b + 0xdb) == 0 and ram.u8(b + 0xdf) == 0:
		var q: int = ram.s16(a + 0x40)
		var flags: int = ram.u32(b + 0x60)
		if ram.s16(a + 0x30) < 0x2aaa:
			if (flags & 0x80) == 0:
				if (flags & 0x40) != 0:
					kind = by_quadrant(q, [2, 4, 3, 5])
				elif (flags & 0x20) != 0:
					kind = by_quadrant(q, [6, 8, 7, 9])
			elif (flags & 0x200) == 0:
				kind = by_quadrant(q, [10, 12, 11, 13])
			else:
				kind = by_quadrant(q, [14, 16, 15, 17])
		elif ram.s16(a + 0x30) > 0x5555 and (flags & 2) != 0:
			kind = 18 if q == 0 else 19 if q == 2 else -1
	ram.w32(HIT_KIND + player * 4, kind)
	return kind
static func condition(ram, entry: int, a: int, b: int) -> bool:
	var code: int = ram.u8(entry + 3)
	var player: int = ram.u8(a + 0x1e)
	var u: int = 0
	match code:
		0:
			return true
		1:
			return ram.u8(a + 0xd1) != 0
		2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19:
			if ram.s32(HIT_KIND + player * 4) == 0:
				hit_kind(ram, player, a, b)
			if ram.u32(a + 0xf4) <= ram.u16(entry + 4):
				return code == ram.s32(HIT_KIND + player * 4)
			return false
		20, 21, 22, 23:
			if ram.s32(HIT_KIND + player * 4) == 0:
				hit_kind(ram, player, a, b)
			if ram.u16(entry + 4) < ram.u32(a + 0xf4):
				return false
			var k: int = ram.s32(HIT_KIND + player * 4)
			return k == [2, 3, 4, 5][code - 20] or k == [6, 7, 8, 9][code - 20]
		24:
			return ram.u32(a + 0xf8) <= ram.u16(entry + 4)
		25:
			return ram.u32(a + 0xf8) >= ram.u16(entry + 4)
		26:
			if ram.u8(a + 0xd1) != 0:
				return (ram.u16(a + 100) & ram.u16(b + 0x66)) == 0
			return false
		27:
			return ram.u8(b + 0xcf) != 0
		28:
			return ram.u8(a + 0xd2) != 0
		29:
			return ram.s16(b + 0x19a) != 0x21
		30:
			return ram.s16(b + 0x5e) != 0
		31:
			if ram.s16(b + 0x5e) == 0:
				return false
			return (ram.u16(b + 0x60) & 7) == 2
		32:
			if ram.s16(b + 0x5e) == 0:
				return false
			return (ram.u16(b + 0x60) & 7) == 1
		33:
			return ram.s16(b + 0x5e) == 0
		34:
			return (ram.u32(b + 0x60) & 0x407) == 2
		35:
			return (ram.u32(b + 0x60) & 0x407) == 1
		36:
			return not (ram.s16(a + 0x30) < 0x4001)
		37:
			return ((ram.u16(a + 0x2e) - 0x4e38) & 0xffff) < 0x31c8
		38:
			return ram.u16(a + 0x2e) > 0x7fff and ram.u16(a + 0x2e) <= 0xb1c6
		39:
			return ram.s16(a + 0x32) == 0
		40:
			return ram.s16(a + 0x32) == 1
		41:
			return ram.s16(a + 0x32) == 3
		42:
			return ram.s16(a + 0x32) == 2
		43:
			return ram.s16(a + 0x40) == 0
		44:
			return ram.s16(a + 0x40) == 1
		45:
			return ram.s16(a + 0x40) == 3
		46:
			return ram.s16(a + 0x40) == 2
		47:
			return false
		48:
			return ram.s16(b + 100) == 0x412 and ram.s16(b + 0x58) <= ram.u8(ram.u32(b + 0x54) + 0x2e) and ram.u32(a + 0xf8) < 0x700
		49:
			return ram.s32(a + 0x118) == 0
		50:
			return ram.s32(a + 0x118) != 0
		51:
			return ram.u8(a + 0xd5) != 0
		52:
			return ram.u8(a + 0xd5) != 0 and ram.u8(b + 0xdb) == 0 and (ram.u32(b + 0x60) & 4) == 0
		53:
			return (ram.u32(b + 0x60) & 4) != 0
		54:
			return (ram.u32(b + 0x60) >> 2 & 1) == 0
		55:
			if (ram.u32(b + 0x60) & 4) == 0:
				return false
			if ram.u8(ram.u32(b + 0x54) + 0x19) != 0:
				return false
			return ram.u32(a + 0xf8) <= ram.u16(entry + 4)
		56:
			return (ram.u32(b + 0x60) & 4) != 0 and not (ram.s16(a + 0x30) < 0x4000)
		57:
			return ram.u8(b + 0xd3) != 0 and ram.u8(b + 0xdb) == 0
		58, 59, 60:
			ram.w8(a + 0x8c, 1)
			return ram.u8(a + 0xe0 + code - 58) != 0
		61:
			return ram.s32(a + 0x3f4) == 0
		62:
			return ram.u8(a + 0xc6) == 0
		63:
			return ram.u8(a + 0xc6) != 0
		64:
			return ram.u8(a + 0xc6) == 0 and not (ram.s16(a + 0x30) < 0x4001)
		65:
			return ram.u8(a + 0xc6) != 0 and not (ram.s16(a + 0x30) < 0x4001)
		66:
			return ram.s16(a + 0x8e) == 0 and ram.s32(a + 0x3f4) != 0
		67:
			return ram.s16(a + 0x122) != 0
		68:
			return ram.s16(a + 0x122) == 0
	return false
static func stance_ok(ram, entry: int, a: int, b: int) -> bool:
	var v: int = ram.u8(entry + 2)
	if v == 0:
		return true
	if v >= 0x5d:
		return (v - 0x5d) != ram.s16(a + 0x18)
	if v >= 0x46:
		return v - 0x46 == ram.s16(a + 0x18)
	if v >= 0x2f:
		return v - 0x2f == ram.s16(b + 0x16)
	if v >= 0x18:
		return (v - 0x18) != ram.s16(a + 0x16)
	return v - 1 == ram.s16(a + 0x16)
static func entry_ok(ram, cur: int, frame: int, a: int, b: int, held: int, pressed: int) -> bool:
	return input_matches(ram, a, cur, held, pressed) and ram.u8(cur + 9) <= frame and frame <= ram.u8(cur + 10) and stance_ok(ram, cur, a, b) and ram.u8(cur + 3) < 0x45 and (ram.u8(cur + 3) == 0 or condition(ram, cur, a, b))
static func find_move(ram, list: int, frame: int, a: int, b: int) -> int:
	var held: int = ram.u16(a + Pad.HELD_DIR_MASK)
	var pressed: int = ram.u16(a + Pad.PRESSED_BUTTONS)
	reset_hit_kind(ram, ram.u8(a + 0x1e))
	var pos: int = list
	var caller := 0
	while true:
		var result: int = pos
		var resume: int = pos
		while ram.u16(pos) != END:
			var type: int = ram.u16(pos)
			if type == REPEAT:
				pos = caller + 12
				continue
			var cur: int = pos
			if type == SHARED:
				caller = pos
				cur = SHARED_ENTRIES + ram.u16(pos + 6) * 12
			if entry_ok(ram, cur, frame, a, b, held, pressed):
				result = cur
				resume = cur + 12
				break
			pos = cur + 12
		var kind: int = ram.u8(result + 8)
		if ram.u16(pos) == END:
			result = pos
			kind = ram.u8(pos + 8)
		elif kind == 0x2c:
			var tail: int = pos
			while ram.u16(tail) != END:
				tail += 12
			result = tail
			kind = ram.u8(tail + 8)
		var skip: bool = kind == 0x1c and ram.u16(result) != END and ram.s16(a + 0x128) != 0
		if not skip:
			return result
		pos = resume
	return 0
static func find_reaction(ram, list: int, frame: int, a: int, b: int) -> int:
	var held: int = ram.u16(a + Pad.HELD_DIR_MASK)
	var pressed: int = ram.u16(a + Pad.PRESSED_BUTTONS)
	var pos: int = list
	var caller := 0
	while ram.u16(pos) != END:
		var type: int = ram.u16(pos)
		if type == REPEAT:
			pos = caller + 12
			continue
		var cur: int = pos
		if type == SHARED:
			caller = pos
			cur = SHARED_ENTRIES + ram.u16(pos + 6) * 12
		if ram.u8(cur + 9) <= frame and frame <= ram.u8(cur + 10) and input_matches(ram, a, cur, held, pressed) and stance_ok(ram, cur, a, b) and ram.u8(cur + 3) > 0x44 and reaction_condition(ram, cur, a, b):
			return cur
		pos = cur + 12
	return pos
static func reaction_condition(ram, entry: int, a: int, b: int) -> bool:
	var code: int = ram.u8(entry + 3)
	var brow: int = ram.u32(b + 0x54)
	match code:
		0x45:
			if ram.u8(a + 0xce) == 0:
				return false
			return ram.s16(a + 0x30) < 0x2aaa and ram.s16(b + 0x30) < 0x2aaa
		0x46, 0x47, 0x48, 0x49:
			if (ram.u32(brow + 0x24) >> 8 & 8) != 0:
				return false
			if ram.s16(a + 0x30) > 0x2aa9 or ram.s16(b + 0x30) > 0x2aa9:
				return false
			var want: int = {0x46: 0x412, 0x47: 0x217, 0x48: 0x10f, 0x49: 0x412}[code]
			if code == 0x49:
				if ram.s16(b + 100) != 0x412:
					if ram.s16(b + 100) != 0x217:
						return false
					return list_has(ram, b, ram.s16(entry + 4))
			elif ram.s16(b + 100) != want:
				return false
			return list_has(ram, b, ram.s16(entry + 4))
		0x4a:
			if ram.u16(entry + 4) != ram.s16(b + 0xa0):
				return false
			return ram.s16(a + 0x30) < 0x2aaa and ram.s16(b + 0x30) < 0x2aaa
		0x4b:
			if ram.s16(a + 0x30) < 0x2aaa and ram.s16(b + 0x30) < 0x2aaa:
				return sequence_has(ram, ram.u32(ram.u32(b + 0x54)), ram.s16(entry + 4))
			return false
	return false
static func list_has(ram, b: int, id: int) -> bool:
	var flags: int = ram.u32(ram.u32(b + 0x54) + 0x28)
	if id == 0:
		return true
	for i in 4:
		if ram.u8(flags + i) == id:
			return true
	return false
static func sequence_has(ram, stream_head: int, index: int) -> bool:
	var table: int = ram.u32(0x80095694 + ((index << 16) >> 14))
	var v: int = ram.s16(table)
	var p: int = table
	while v >= 1:
		p += 2
		if ram.s16(stream_head - 2) == v:
			return true
		v = ram.s16(p)
	return false
