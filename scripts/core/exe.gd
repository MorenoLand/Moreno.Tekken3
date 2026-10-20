extends RefCounted
var data: PackedByteArray
func _init(bytes: PackedByteArray) -> void:
	data = bytes
func off(va: int) -> int:
	return va - 0x80010000 + 0x800
func u8(va: int) -> int:
	return data[off(va)]
func u16(va: int) -> int:
	return data.decode_u16(off(va))
func s16(va: int) -> int:
	return data.decode_s16(off(va))
func s32(va: int) -> int:
	return data.decode_s32(off(va))
func s16s(va: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	for i in count:
		out[i] = s16(va + i * 2)
	return out
func s32s(va: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	for i in count:
		out[i] = s32(va + i * 4)
	return out
