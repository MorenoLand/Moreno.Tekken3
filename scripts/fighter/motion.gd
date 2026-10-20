extends RefCounted
const CHANNELS := 49
var exe
func _init(exe_data) -> void:
	exe = exe_data
func _s16(v: int) -> int:
	return ((v + 0x8000) & 0xFFFF) - 0x8000
func _s32(v: int) -> int:
	return ((v + 0x80000000) & 0xFFFFFFFF) - 0x80000000
func _spline(words: Array, i: int, count: int, shift: int) -> int:
	var last := count - 1
	var v3: int = words[0]
	var key: int = words[1]
	var ptr := 2
	var v2 := v3
	var v7 := ((key >> 5) << shift) + v3
	var end := 0
	var start := 0
	var v4 := 0
	var v5 := 0
	var v6 := 0
	while true:
		start = end
		v6 = v7
		v5 = v2
		v4 = v3
		end = start + (key & 31) + 1
		if end == last:
			break
		key = words[ptr]
		ptr += 1
		v7 = v6 + ((key >> 5) << shift)
		v3 = v5
		v2 = v6
		if not 0 < i - end:
			break
	var t := i - start
	var length := end - start
	var idx := 0
	if t != 0:
		idx = (exe.u8(0x800966F8 + length * 32 + t + 3) if length - 16 < 1 else exe.u8(0x80096B3C - length * 32 - t)) << 1
	var neg := -idx
	var carry := 0
	var mul := 0
	var acc := 0
	if start == 0:
		mul = exe.u16(0x80096C20 + neg)
		acc = exe.u16(0x80096A1C + neg) * (v7 - v5)
	else:
		var prev: int = exe.u16(0x8009691C + idx) * (v4 - v5)
		if end == last:
			mul = exe.u16(0x80096C20 + neg) + exe.u16(0x80096A1C + neg) + 0x2AAB
			acc = prev
		else:
			acc = exe.u16(0x80096A1C + neg) * (v7 - v5)
			mul = exe.u16(0x80096B1E + neg)
			carry = prev
	if start != 0 and end != last:
		acc += carry
	return (_s32(acc + mul * (v6 - v5)) >> 16) + v5
func frame(stream: PackedByteArray, start: int, frame_index: int) -> PackedInt32Array:
	var count := stream[start]
	var f := clampi(frame_index, 0, count - 1)
	var desc := PackedInt32Array([stream[start + 1]])
	for k in CHANNELS - 1:
		desc.append(stream[start + 2 + k])
	var pos := start + 50
	var out := PackedInt32Array()
	for k in CHANNELS:
		var n := desc[k]
		var i := f if k % 2 == 0 else count - (f + 1)
		var words: Array = []
		for w in n:
			words.append(stream.decode_s16(pos + w * 2))
		var v := 0
		if n == 1:
			v = words[0] << 1
		elif n == 2:
			v = words[1] * i
			v = v >> 5 if count > 9 else v
			v = ((words[0] & 0xFFFF) + v) << 1
		elif n == count:
			v = words[i] << 1
		elif n != 0:
			v = _spline(words, i, count, exe.u8(0x80096C24 + k)) << 1
		out.append(_s16(v))
		pos += n * 2
	return out
