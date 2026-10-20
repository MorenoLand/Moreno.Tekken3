extends RefCounted
# Turns move events (hits, blocks, voices, footsteps) into sound ids for the sfx player.
# Fields are read with ram.u8/u16/u32 at "actor + offset"; offsets are listed at the top of ram.gd.
const ID_TABLE := 0x80097050
const VOICE_TABLES := 0x8001ad54
const SCRIPTS := 0x800971f8
const COOL_IDLE := 0x800971e8
const COOL_HIT := 0x800971dc
const FOOT_LOCK := 0x800971f0
static func entry_of(ram, id: int) -> int:
	var index := id & 0xfff
	return 0 if index == 0 else ram.u16(ID_TABLE + index * 2)
static func play_id(ram, out: Array, player: int, id: int) -> void:
	var e := entry_of(ram, id)
	if e != 0:
		out.append([player, e])
static func voice(ram, out: Array, player: int, character: int, word: int) -> void:
	var table: int = ram.u32(VOICE_TABLES + character * 24)
	var category := (word >> 12) - 2
	if category < 0 or category > 3 or (word & 0xfff) >= ram.s16(table + category * 2):
		return
	var offset := 0
	for k in category:
		offset += ram.s16(table + k * 2)
	var e: int = ram.u16(table + (offset + (word & 0xfff) + 4) * 2)
	if e != 0:
		out.append([player, e])
static func hit_id(ram, a: int, b: int) -> int:
	var level: int = ram.u8(ram.u32(ram.u32(a + 0x54) + 0x28))
	var damage: int = ram.s16(a + 0x5e)
	var pick := randi() & 2
	if level >= 0xc:
		return 0x7045 if damage < 0xd else (0x7046 if damage < 0x17 else (0x7047 if damage < 0x21 else 0x7048))
	var kind: int = ram.s16(a + 0x18)
	var base := 0x8001a6fc if kind == 5 or kind == 7 or kind == 10 or kind == 0x12 else 0x8001a710
	if damage < 0xd:
		return ram.u16(base + pick)
	return ram.u16(base + (8 if damage < 0x17 else (12 if damage < 0x21 else 16)))
static func run(ram, a: int, b: int, out: Array) -> void:
	var p: int = ram.s16(a + 0x12)
	var q: int = ram.s16(b + 0x12)
	var ch: int = ram.s16(a + 0x1a)
	var row: int = ram.u32(a + 0x54)
	var frame: int = ram.s16(a + 0x58)
	ram.w16(FOOT_LOCK + p * 2, 0)
	var spoke := false
	var koed := false
	if ram.u8(a + 0xde) != 0:
		var shouts: int = ram.u32(VOICE_TABLES + ch * 24)
		voice(ram, out, p, ch, 0x4000 | ((randi() & 0xff) * ram.s16(shouts + 4) >> 8))
		spoke = true
	if ram.u32(b + 0x3f4) == 0 and ram.u8(b + 0xd0) != 0:
		play_id(ram, out, p, 0x7044 if ram.u8(ram.u32(row + 0x28)) < 0xb else 0x7048)
		koed = true
	var list: int = ram.u32(row + 0x1c)
	if list != 0:
		for k in 3:
			var w: int = ram.u16(list + k * 2)
			if w == 0xffff:
				break
			match w >> 12:
				1, 7:
					if ram.u8(a + 0xd1) != 0 and not koed and ram.u8(b + 0xcf) == 0:
						if ram.s16(b + 0x18) != 0x10 and (w == 0x7000 or w == 0x7041 or w == 0x7042 or w == 0x7045):
							play_id(ram, out, p, hit_id(ram, a, b))
						elif ram.s16(b + 0x18) != 0x10:
							play_id(ram, out, p, w)
					elif ram.u8(a + 0xd1) != 0 and not koed:
						play_id(ram, out, q, 0x704d if ram.u8(ram.u32(row + 0x28)) < 0xc else 0x704e)
				2:
					if frame == 1 and ram.u32(a + 0x3f4) != 0 and ram.s16(COOL_IDLE + p * 2) == 0 and not spoke:
						voice(ram, out, p, ch, w)
						ram.w16(COOL_IDLE + p * 2, ram.s16(0x8001ad60 + ch * 0x18))
				3:
					if frame == 1 and ram.u32(a + 0x3f4) != 0 and ram.s16(COOL_IDLE + p * 2) == 0 and not spoke:
						voice(ram, out, p, ch, w)
						spoke = true
				4, 5:
					if frame == 1:
						play_id(ram, out, p, w)
				8:
					if (w & 0xfff) != 0 and ram.s16(a + 0x72) != (w & 0xfff):
						ram.w16(a + 0x70, w & 0xfff)
						ram.w16(a + 0x72, w & 0xfff)
						ram.w16(a + 0x11e, 0)
						ram.w16(a + 0x120, frame - 1)
	var scripted := false
	if ram.s16(a + 0x70) != -1:
		scripted = true
		ram.w16(a + 0x120, ram.s16(a + 0x120) + 1)
		var table: int = ram.u32(SCRIPTS + ram.s16(a + 0x70) * 4)
		while true:
			var e: int = ram.u32(table + ram.s16(a + 0x11e) * 4)
			var at := e & 0xfff
			if at == 0:
				break
			var now: int = ram.s16(a + 0x120)
			if now < at:
				break
			if now == at:
				var w := e >> 16
				match (e >> 12) & 15:
					1:
						if (w >> 12) - 2 < 4 and (w >> 12) >= 2:
							voice(ram, out, p, ch, w)
						else:
							play_id(ram, out, p, w)
					2:
						if (w >> 12) - 2 < 4 and (w >> 12) >= 2:
							voice(ram, out, q, ch, w)
						else:
							play_id(ram, out, q, w)
			ram.w16(a + 0x11e, ram.s16(a + 0x11e) + 1)
		if ram.s16(a + 0x11e) >= 0 and ram.u32(table + ram.s16(a + 0x11e) * 4) & 0xfff == 0:
			ram.w16(a + 0x70, 0xffff)
			ram.w16(a + 0x72, 0)
			ram.w16(a + 0x11e, 0)
			ram.w16(a + 0x120, 0)
	if not scripted:
		if not spoke and ram.u32(a + 0x3f4) != 0 and ram.u8(a + 0xd0) != 0 and ram.s32(COOL_HIT + p * 4) == 0:
			var hurt: int = ram.u32(VOICE_TABLES + 8 + ch * 24)
			var base := 2
			var count: int = ram.s16(hurt)
			if ram.s16(b + 0x5e) >= 0x14:
				count = ram.s16(hurt + 2)
				base = ram.s16(hurt) + 2
			if count != 0:
				voice(ram, out, p, ch, ram.u16(hurt + (base + ((randi() & 0xff) * count >> 8)) * 2))
				ram.w32(COOL_HIT + p * 4, 0x28)
				spoke = true
		if ram.s16(COOL_IDLE + p * 2) == 0 and not spoke and ram.s16(a + 0x5e) != 0 and ram.s16(a + 0x74) == 0 and ram.u8(a + 0xda) != 0 and (randi() & 3) == 0:
			var grunt: int = ram.u32(VOICE_TABLES + 4 + ch * 24)
			voice(ram, out, p, ch, ram.u16(grunt + (((ram.s16(grunt) * (randi() & 0xff)) >> 8) + 1) * 2))
			ram.w16(COOL_IDLE + p * 2, ram.s16(0x8001ad60 + ch * 0x18))
		if ram.s16(FOOT_LOCK + p * 2) == 0:
			if frame == ram.u8(row + 0x19) and frame != 1:
				play_id(ram, out, p, 0x1053)
			if ram.u8(a + 0xdc) != 0:
				play_id(ram, out, p, 0x1054)
			if ram.u8(a + 0xdd) != 0:
				play_id(ram, out, p, 0x104f)
	if ram.s16(COOL_IDLE + p * 2) > 0:
		ram.w16(COOL_IDLE + p * 2, ram.s16(COOL_IDLE + p * 2) - 1)
	if ram.s32(COOL_HIT + p * 4) > 0:
		ram.w32(COOL_HIT + p * 4, ram.s32(COOL_HIT + p * 4) - 1)
