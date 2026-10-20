extends RefCounted
const Tim := preload("res://scripts/fighter/tim.gd")
const SHEETS := [[0, 4, 224], [1, 172, 0], [2, 0, 0]]
var fonts: Array = []
func _init(exe, menu_records: String) -> void:
	for f in 3:
		var d: int = 0x80021D64 + f * 16
		var table: int = exe.u32(d)
		var cell: int = exe.u32(d + 8)
		var image := Tim.to_image(FileAccess.get_file_as_bytes("%sp%02d.tim" % [menu_records, SHEETS[f][0]]))
		fonts.append({"image": image, "table": table, "cell": Vector2i(cell & 0xFFFF, cell >> 16), "advance": exe.s16(d + 4), "line": exe.s16(d + 6), "origin": Vector2i(SHEETS[f][1], SHEETS[f][2]), "exe": exe})
func size_of(text: String, font: int) -> Vector2i:
	return Vector2i(text.length() * fonts[font]["advance"], fonts[font]["line"])
func render(text: String, font: int) -> Image:
	var f: Dictionary = fonts[font]
	var img := Image.create(maxi(1, text.length() * f["advance"]), f["line"], false, Image.FORMAT_RGBA8)
	for i in text.length():
		var code := text.unicode_at(i)
		var uv: int = f["exe"].u16(f["table"] + code * 2)
		var src := Rect2i(Vector2i(uv & 0xFF, uv >> 8) - f["origin"], f["cell"])
		if src.position.x < 0 or src.position.y < 0 or code == 32:
			continue
		img.blend_rect(f["image"], src, Vector2i(i * f["advance"], 0))
	return img
func texture(text: String, font: int) -> ImageTexture:
	return ImageTexture.create_from_image(render(text, font))
