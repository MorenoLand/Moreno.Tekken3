extends Control
const Tim := preload("res://scripts/fighter/tim.gd")
const BNS := "res://assets/bns/"
const PIXEL_ASPECT := 640.0 / 368.0
var screen := Control.new()
const Sfx := preload("res://scripts/fight/sfx.gd")
const BLIP_START := [0x4007, 0.4]
const BLIP_CURSOR := [0x4035, 0.44]
const BLIP_CONFIRM := [0x4034, 0.31]
var cache := {}
var backdrop: ColorRect
var blips
func cue(id: int) -> void:
	if blips == null:
		blips = Sfx.new()
		add_child(blips)
		blips.pool(4)
	blips.play_id(id)
func blip(kind: Array) -> void:
	if blips == null:
		blips = Sfx.new()
		add_child(blips)
		blips.pool(4)
	blips.play_entry(0, kind[0], kind[1])
func _enter_tree() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	clip_contents = true
	backdrop = ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	add_child(screen)
	resized.connect(_layout)
	_layout()
func _layout() -> void:
	screen.scale = Vector2(size.x / 368.0, size.y / 480.0)
	screen.position = Vector2.ZERO
func tim_texture(path: String, gain: float = 1.0, bands: int = 0) -> ImageTexture:
	var key := "%s@%s@%d" % [path, gain, bands]
	if not cache.has(key):
		var image := Tim.to_image(FileAccess.get_file_as_bytes(path), bands)
		if gain != 1.0:
			for y in image.get_height():
				for x in image.get_width():
					var c := image.get_pixel(x, y)
					image.set_pixel(x, y, Color(minf(c.r * gain, 1.0), minf(c.g * gain, 1.0), minf(c.b * gain, 1.0), c.a))
		cache[key] = ImageTexture.create_from_image(image)
	return cache[key]
func sprite(path: String, pos: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tim_texture(path)
	rect.position = pos
	rect.size = rect.texture.get_size()
	rect.stretch_mode = TextureRect.STRETCH_KEEP
	screen.add_child(rect)
	return rect
