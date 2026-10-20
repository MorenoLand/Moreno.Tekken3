extends RefCounted
# Beach background of Tekken Ball (stage 0x13 = BNS record 55): 261 TIMs (member 0) land in VRAM and the 32 x 8 map (member 2) picks a
# 32 x 32 sprite per cell (u/v/page from the first layer, CLUT from the second layer), as drawn by overlay FUN_800b5a48.
const Tim := preload("res://scripts/fighter/tim.gd")
const BNS := "res://assets/bns/055/"
const TILE := 32
static func vram() -> PackedInt32Array:
	var pack := FileAccess.get_file_as_bytes(BNS + "00.bin")
	var tims := []
	for i in pack.decode_u32(0):
		var offset: int = pack.decode_u32(4 + i * 8)
		var size: int = pack.decode_u32(8 + i * 8)
		tims.append_array(Tim.stream(pack.slice(offset, offset + size)))
	return Tim.compose_absolute(tims)
static func floor_table() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(BNS + "01.bin")
static func panorama(vram: PackedInt32Array) -> Image:
	var map := FileAccess.get_file_as_bytes(BNS + "02.bin")
	var cols: int = map.decode_u16(0)
	var rows: int = map.decode_u16(2)
	var image := Image.create(cols * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	for r in rows:
		for c in cols:
			var info: int = map.decode_u16(4 + (r * cols + c) * 2)
			var clut: int = map.decode_u16(4 + (cols * rows + r * cols + c) * 2)
			var page: int = (info >> 8) & 0x1f
			var tile := Tim.decode_region(vram, page, clut, Rect2i((info & 7) << 5, (info & 0x38) << 2, TILE, TILE))
			image.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(c * TILE, r * TILE))
	return image
