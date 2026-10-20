extends Control
const Tim := preload("res://scripts/fighter/tim.gd")
const BNS := "res://assets/bns/"
const PIXEL_ASPECT := 640.0 / 368.0
var screen := Control.new()
var cache := {}
func _enter_tree() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	clip_contents = true
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	add_child(screen)
	resized.connect(_layout)
	_layout()
func _layout() -> void:
	var k := size.y / 480.0
	screen.scale = Vector2(k * PIXEL_ASPECT, k)
	screen.position = Vector2((size.x - 368.0 * k * PIXEL_ASPECT) / 2.0, 0.0)
func tim_texture(path: String, gain: float = 1.0) -> ImageTexture:
	var key := "%s@%s" % [path, gain]
	if not cache.has(key):
		var image := Tim.to_image(FileAccess.get_file_as_bytes(path))
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
