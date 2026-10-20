extends RefCounted
const MoveStep := preload("res://scripts/combat/move_step.gd")
const FMath := preload("res://scripts/combat/fmath.gd")
const REACTION_A := 0x80010ce8
const REACTION_B := 0x800174c4
const REACTION_C := 0x800177dc
const DAMAGE_SCALE := 0x8001deec
static func carry_damage(ram, a: int) -> int:
	var kind: int = ram.u8(a + 0xe4)
	var total := 0
	if kind == 2:
		var d: int = ram.s16(a + 0xec)
		total = d if d != 0 else ram.s16(a + 0x5e)
		kind = ram.u8(a + 0xe4)
	if kind == 3:
		var d3: int = ram.s16(a + 0xec)
		total -= d3 if d3 != 0 else ram.s16(a + 0x5e)
	if ram.s16(a + 0x74) < 0:
		var o: int = MoveStep.opponent(ram, a)
		if ram.u8(o + 0xe4) == 1:
			var d1: int = ram.s16(o + 0xec)
			total += d1 if d1 != 0 else ram.s16(o + 0x5e)
	return total
static func classify(ram, victim: int, attacker: int, rec: int) -> void:
	if ram.s16(attacker + 0x5e) == 0:
		ram.w8(rec + 0x28, 1)
		return
	var tier: int = ram.u16(ram.u32(attacker + 0x54) + 0x34)
	if tier != 0 and ram.u32(0x800afa3c) < ram.s16(0x800177de + tier * 4):
		ram.w8(rec + 0x26, 1)
	if (ram.u16(victim + 0x66) & ram.u16(attacker + 100)) == 0 or ram.u16(victim + 0x30) > 0x3fff:
		ram.w8(rec + 0x24, 1)
		if (ram.s16(victim + 0x5e) != 0 and ram.s16(victim + 0x58) < ram.u8(ram.u32(victim + 0x54) + 0x2d)) or ram.s16(victim + 0x122) != 0 or ram.s16(attacker + 0x122) != 0:
			ram.w8(rec + 0x25, 1)
		if ram.u8(victim + 0xdb) != 0 or (ram.u32(ram.u32(victim + 0x54) + 4) & 0x400) != 0:
			ram.w8(rec + 0x27, 1)
	else:
		ram.w8(rec + 0x22, 1)
		if ram.s32(0x800afa58) != 0 or ram.s16(attacker + 0x122) != 0:
			ram.w8(rec + 0x23, 1)
static func scaled(ram, dmg: int, index: int) -> int:
	return FMath.s16(FMath.tdiv(dmg * ram.s16(DAMAGE_SCALE + index * 2), 100))
static func amount(ram, victim: int, attacker: int, rec: int) -> void:
	var base: int = ram.u16(attacker + 0x5e)
	ram.w16(rec + 0x1c, base)
	var result: int
	if ram.u8(rec + 0x22) == 0:
		var v: int
		if ram.u8(rec + 0x26) == 0:
			v = scaled(ram, FMath.s16(base), ram.s16(rec + 0x18))
		else:
			v = FMath.s16(base) + (FMath.s16(base) - (FMath.s16(base) >> 31) >> 1)
		if ram.u8(rec + 0x25) != 0:
			var d: int = absi(ram.s16(victim + 0x5e))
			var part: int = FMath.tdiv(d * 3, 10)
			if ram.s16(victim + 0x122) == 0 and ram.s16(attacker + 0x122) == 0:
				var win: int = ram.u8(ram.u32(victim + 0x54) + 0x2d)
				if win == 0 or win < ram.s16(victim + 0x58):
					win = ram.u16(victim + 0x58)
				part = FMath.tdiv(FMath.tdiv(FMath.s16(part) * 3, 10) * ram.s16(victim + 0x58), FMath.s16(win))
			v = part + FMath.tdiv(FMath.s16(v) * 0xc, 10)
		result = FMath.s16(v)
		if ram.u8(rec + 0x27) != 0:
			if ram.s16(victim + 0x94) == 0:
				result = FMath.s16(FMath.tdiv(result * 0x50, 100))
			else:
				result = FMath.s16((result - (result >> 31)) >> 1)
	elif ram.u8(rec + 0x23) == 0:
		result = 0
	else:
		result = FMath.s16(FMath.tdiv(FMath.s16(base), 10) + 2)
	ram.w16(rec + 0x1e, ram.s16(rec + 0x1e) + result)
static func best_record(ram, a: int) -> int:
	var first: int = a + 0x13c
	var second: int = a + 0x168
	var pick: int = first
	if ram.u8(second + 0x21) != 0:
		var wa: int = rank(ram, first)
		var wb: int = rank(ram, second)
		if wa < wb or (wa == wb and ram.s16(first + 0x1e) < ram.s16(second + 0x1e)):
			pick = second
	return pick
static func rank(ram, r: int) -> int:
	var v: int = 1 if ram.u8(r + 0x28) != 0 else 0
	for pair in [[0x22, 2], [0x23, 3], [0x26, 4], [0x24, 5], [0x25, 6], [0x27, 7]]:
		if ram.u8(r + pair[0]) != 0:
			v += pair[1]
	return v & 0xff
static func apply_flags(ram, a: int, rec: int) -> void:
	ram.w16(a + 0xe8, absi(ram.s16(rec + 0x1e)))
	ram.w8(a + 0xd4, ram.u8(rec + 0x26))
	ram.w8(a + 0xcf, ram.u8(rec + 0x22))
	ram.w8(a + 0xd0, ram.u8(rec + 0x24))
	ram.w8(a + 0xd3, ram.u8(rec + 0x25))
	ram.w8(a + 0x88, ram.u8(rec + 0x20))
static func reaction_table(ram, a: int, attacker: int) -> void:
	if ram.u8(a + 0xe7) != 0:
		ram.w32(a + 0x1a8, 0x8001dec0)
		return
	var row: int = ram.u32(attacker + 0x54)
	if ram.u8(a + 0xd4) == 0:
		var v: int = ram.u16(row + 0x32)
		ram.w32(a + 0x1a8, REACTION_B + ((v & 0xfff) << 1) if (v & 0xf000) != 0 else REACTION_A + v * 0x2a)
	else:
		var w: int = FMath.s16(ram.u16(REACTION_C + ram.u16(row + 0x34) * 4))
		if (w & 0xf000) == 0:
			ram.w32(a + 0x1a8, REACTION_A + (w & 0xffffffff) * 0x2a)
		else:
			ram.w32(a + 0x1a8, REACTION_B + ((ram.u16(REACTION_C + ram.u16(row + 0x34) * 4) & 0xfff) << 1))
static func resolve(ram, a: int) -> void:
	var total := 0
	var opp: int = MoveStep.PLAYER_BASE + MoveStep.opponent_index(ram, a) * MoveStep.PLAYER_SIZE
	var poison: int = carry_damage(ram, a)
	var attacker: int = opp
	for k in 2:
		var rec: int = a + 0x13c + k * 0x2c
		if ram.u8(rec + 0x21) != 0:
			attacker = MoveStep.PLAYER_BASE + ram.u8(rec + 0x20) * MoveStep.PLAYER_SIZE
			ram.w8(a + 0xc7, 0)
			MoveStep.face_opponent(ram, a, attacker)
			classify(ram, a, attacker, rec)
			amount(ram, a, attacker, rec)
			total += ram.s16(rec + 0x1e)
	var before: int = ram.s32(a + 0x3f4)
	if ram.u8(a + 0xce) != 0:
		var best: int = best_record(ram, a)
		ram.w32(a + 0x194, best)
		apply_flags(ram, a, best)
		ram.w32(a + 0x3dc, ram.u32(attacker + 0x3d0))
		ram.w32(a + 0x3e0, ram.u32(attacker + 0x3d4))
		ram.w32(a + 0x3e4, ram.u32(attacker + 0x3d8))
		reaction_table(ram, a, attacker)
	if ram.s32(0x8009547c) == 0 and ram.s32(0x800954b4) == 0:
		ram.w32(a + 0x3f4, before + (poison + total) * -0x10000)
	var hp: int = ram.s32(a + 0x3f4)
	if hp < 0:
		ram.w32(a + 0x3f4, 0)
		hp = 0
	if ram.s32(a + 0x3f8) < hp:
		ram.w32(a + 0x3f4, ram.s32(a + 0x3f8))
	if ram.s32(a + 0x3f4) == 0 and before != 0:
		ram.w8(a + 0xde, 1)
	if ram.u8(a + 0xde) != 0 and ram.u8(ram.u32(a + 0x194) + 0x23) != 0:
		ram.w8(a + 0xcf, 0)
		ram.w8(a + 0xd0, 1)
	ram.w16(a + 0xcc, poison)
