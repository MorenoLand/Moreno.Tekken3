extends RefCounted
const BASE := 0x80000000
var m := PackedByteArray()
func _init(size: int = 0x800000) -> void:
	m.resize(size)
func u8(a: int) -> int:
	return m[a - BASE]
func s8(a: int) -> int:
	var v := m[a - BASE]
	return v - 256 if v > 127 else v
func u16(a: int) -> int:
	return m.decode_u16(a - BASE)
func s16(a: int) -> int:
	return m.decode_s16(a - BASE)
func u32(a: int) -> int:
	return m.decode_u32(a - BASE)
func s32(a: int) -> int:
	return m.decode_s32(a - BASE)
func w8(a: int, v: int) -> void:
	m[a - BASE] = v & 0xff
func w16(a: int, v: int) -> void:
	m.encode_u16(a - BASE, v & 0xffff)
func w32(a: int, v: int) -> void:
	m.encode_u32(a - BASE, v & 0xffffffff)
func load_bytes(a: int, b: PackedByteArray) -> void:
	var o := a - BASE
	m = m.slice(0, o) + b + m.slice(o + b.size())
