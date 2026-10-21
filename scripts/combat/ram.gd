# Emulated main RAM of the original game, addressed exactly like the console (0x80000000 base).
# The fight code keeps its state at the original addresses so values can be compared with the real game.
# u8/s8/u16/s16/u32/s32 read little-endian values, w8/w16/w32 write them (values are masked to size).
#
# Actor structs (0x188c bytes each, player 0 at 0x800a9228, player 1 right after). Offsets used by the code:
#   +0x00/+0x04/+0x08 position x/y/z    +0x12 move-set slot     +0x1a character index
#   +0x1e own player index              +0x1f opponent index    +0x2c facing angle (65536 = full turn)
#   +0x54 pointer to the current move row   +0x58 frame inside the move   +0x1a0 next move id
#   +0x3f4 health (16.16 fixed)         +0x3f8 maximum health   +0xc5 1 = computer controlled
#   +0xf68/+0xf6c/+0xf70 hip position in the world   +0x8f4 joint matrices   +0x13c hit records
# Move rows (0x38 bytes) hold: +0x18 frame count, +0x24 flags, +0x28 limb bytes, +0x2d/+0x2e hit window.
extends RefCounted
const BASE := 0x80000000
# Console address mirrors (KUSEG / KSEG0 / KSEG1) all reach the same RAM, so stray low pointers read RAM like on hardware.
const MASK := 0x1fffffff
var m := PackedByteArray()
func _init(size: int = 0x800000) -> void:
	m.resize(size)
func u8(a: int) -> int:
	return m[a & MASK]
func s8(a: int) -> int:
	var v := m[a & MASK]
	return v - 256 if v > 127 else v
func u16(a: int) -> int:
	return m.decode_u16(a & MASK)
func s16(a: int) -> int:
	return m.decode_s16(a & MASK)
func u32(a: int) -> int:
	return m.decode_u32(a & MASK)
func s32(a: int) -> int:
	return m.decode_s32(a & MASK)
func w8(a: int, v: int) -> void:
	m[a & MASK] = v & 0xff
func w16(a: int, v: int) -> void:
	m.encode_u16(a & MASK, v & 0xffff)
func w32(a: int, v: int) -> void:
	if ((a & MASK) - 0xa9228) % 0x188c == 0x1a4 and (v & 0xffffffff) >= 0x80300000 and (v & 0xffffffff) < 0x80400000 and ((v - 0x80300000) % 0x38) != 0 and false:
		pass
	m.encode_u32(a & MASK, v & 0xffffffff)
func load_bytes(a: int, b: PackedByteArray) -> void:
	var o := a & MASK
	m = m.slice(0, o) + b + m.slice(o + b.size())
