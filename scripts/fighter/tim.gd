extends RefCounted
static func stream(b: PackedByteArray) -> Array:
	var out := []
	var o := 0
	while o + 20 <= b.size() and b.decode_u32(o) == 0x10 and b.decode_u32(o + 4) in [0, 1, 2, 3, 8, 9, 10, 11]:
		var t := _parse(b, o)
		out.append(t)
		o = t["end"]
	return out
static func _parse(b: PackedByteArray, start: int) -> Dictionary:
	var flags := b.decode_u32(start + 4)
	var o := start + 8
	var clut := PackedInt32Array()
	var clut_rect := []
	if flags & 8:
		var size := b.decode_u32(o)
		var cw := b.decode_u16(o + 8)
		var ch := b.decode_u16(o + 10)
		clut_rect = [b.decode_u16(o + 4), b.decode_u16(o + 6), cw, ch]
		for i in cw * ch:
			clut.append(b.decode_u16(o + 12 + i * 2))
		o += size
	var size2 := b.decode_u32(o)
	return {"x": b.decode_u16(o + 4), "y": b.decode_u16(o + 6), "words": b.decode_u16(o + 8), "height": b.decode_u16(o + 10), "data": b.slice(o + 12, o + size2), "clut": clut, "clut_rect": clut_rect, "end": o + size2}
static func compose_vram(tims: Array, page_y: int = 0) -> PackedInt32Array:
	var vram := PackedInt32Array()
	vram.resize(1024 * 512)
	for t in tims:
		var w: int = t["words"]
		for r in t["height"]:
			var base: int = (page_y + t["y"] + r) * 1024 + 384 + t["x"]
			for c in w:
				vram[base + c] = t["data"].decode_u16((r * w + c) * 2)
		if not t["clut_rect"].is_empty():
			var cr: Array = t["clut_rect"]
			for r in cr[3]:
				for c in cr[2]:
					vram[(504 + cr[1] + r) * 1024 + cr[0] + c] = t["clut"][r * cr[2] + c]
	return vram
static func _rgba(c: int) -> Color:
	return Color8((c & 31) * 255 / 31, (c >> 5 & 31) * 255 / 31, (c >> 10 & 31) * 255 / 31, 0 if c == 0 else 255)
static func decode_page(vram: PackedInt32Array, page: int, clut: int) -> Image:
	var tpage := page + 6
	var px := (tpage & 15) * 64
	var py := (tpage >> 4 & 1) * 256
	var mode := tpage >> 7 & 3
	var cx := (clut & 63) * 16
	var cy := 504 + (clut >> 6)
	var pal: Array = []
	for i in (16 if mode == 0 else 256):
		pal.append(_rgba(vram[cy * 1024 + cx + i]))
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		var row := (py + y) * 1024 + px
		if mode == 0:
			for i in 64:
				var w := vram[row + i]
				for n in 4:
					img.set_pixel(i * 4 + n, y, pal[w >> (n * 4) & 15])
		else:
			for i in 128:
				var w2 := vram[row + i]
				img.set_pixel(i * 2, y, pal[w2 & 255])
				img.set_pixel(i * 2 + 1, y, pal[w2 >> 8])
	return img
static func to_image(b: PackedByteArray) -> Image:
	var t := _parse(b, 0)
	var mode := b.decode_u32(4) & 3
	var w: int = t["words"] * (4 if mode == 0 else 2 if mode == 1 else 1)
	var h: int = t["height"]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var data: PackedByteArray = t["data"]
	var pal: Array = []
	var colors := 16 if mode == 0 else 256
	for i in colors:
		pal.append(_rgba(t["clut"][i]) if t["clut"].size() > i else Color8(i * 255 / (colors - 1), i * 255 / (colors - 1), i * 255 / (colors - 1)))
	for y in h:
		for x in w:
			if mode == 0:
				img.set_pixel(x, y, pal[data[y * (w / 2) + x / 2] >> (4 * (x & 1)) & 15])
			elif mode == 1:
				img.set_pixel(x, y, pal[data[y * w + x]])
			else:
				img.set_pixel(x, y, _rgba(data.decode_u16((y * w + x) * 2)))
	return img
