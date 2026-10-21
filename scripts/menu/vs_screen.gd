extends "res://scripts/menu/menu_screen.gd"
# The pre-fight screen: lightning background, "STAGE n" bar, both portraits sliding in
# with the names and VS. Layout from the original draw list; colour table at exe 0x800214cc.
signal finished
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const COLORS := 0x800214cc
const TILE_COLUMNS := [0, 69, 137, 206, 274, 343, 411]
const PANEL_POSITION := [Vector2(14, 106), Vector2(228, 216)]
const NAME_Y := [106, 390]
# 30 Hz like the original: black lead-in, 8 slide frames (portraits 20 px, names 29 px per frame), then the full scene.
const FRAME := 1.0 / 30.0
const LEAD_FRAMES := 15
const SLIDE_FRAMES := 8
const SHOW_SECONDS := 3.4
var first_roster := 0
var second_roster := 0
var first_character := 0
var second_character := 0
var stage := 0
var variant := 0
var elapsed := 0.0
var movers: Array = []
var late: Array = []
func setup(roster: Array, characters: Array, stage_number: int, attract: bool = false) -> void:
	variant = 1 if attract else 0
	first_roster = roster[0]
	second_roster = roster[1]
	first_character = characters[0]
	second_character = characters[1]
	stage = stage_number
func _ready() -> void:
	var exe := Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
	var font := GameFont.new(exe, BNS + "010/")
	var tims := []
	for n in 42:
		tims.append_array(Tim.stream(FileAccess.get_file_as_bytes("%s%s/p%02d.tim" % [BNS, "013" if variant == 1 else "012", n])))
	var vram := Tim.compose_absolute(tims)
	var first_late := screen.get_child_count()
	_tiles(vram)
	var tile_end := screen.get_child_count()
	if stage > 0:
		_header(font)
	var header_end := screen.get_child_count()
	for p in 2:
		_panel(p, exe)
	for p in 2:
		_name(p, exe, font)
	var versus: ImageTexture = font.render_clut("VS", 2, 0x7e90)
	var vs_node := _place(versus, Vector2(162, 250))
	for i in range(first_late, header_end):
		late.append(screen.get_child(i))
	late.append(vs_node)
	_set_late(false)
func _tiles(vram: PackedInt32Array) -> void:
	for k in 42:
		var clut: int = 0x7d00 + k if k < 16 else (0x7d40 + k - 16 if k < 32 else 0x7d80 + k - 32)
		var column: int = k % 6
		var row: int = k / 6
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(Tim.decode_region(vram, 0xd, clut, Rect2i(column * 32, row * 32, 32, 32)))
		rect.position = Vector2(TILE_COLUMNS[column], 20 + row * 64)
		rect.size = Vector2(TILE_COLUMNS[column + 1] - TILE_COLUMNS[column], 64)
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		screen.add_child(rect)
func _header_color() -> Color:
	return Color8(0xd8, 0, 0x08) if variant == 1 else Color8(0x68, 0, 0x80)
func _header_clear() -> Color:
	var c := _header_color()
	return Color(c.r, c.g, c.b, 0.0)
func _header(font) -> void:
	screen.add_child(_gradient(Vector2(106, 36), Vector2(110, 36), _header_color(), _header_clear(), _header_color(), _header_clear(), false))
	var bar := ColorRect.new()
	bar.color = _header_color()
	bar.position = Vector2(0, 36)
	bar.size = Vector2(106, 36)
	screen.add_child(bar)
	var label: ImageTexture = font.render_clut("STAGE %d" % stage, 1, 0x7e56)
	_place(label, Vector2(28, 42))
func _gradient(at: Vector2, size: Vector2, top_left: Color, top_right: Color, bottom_left: Color, bottom_right: Color, additive: bool) -> TextureRect:
	var image := Image.create(maxi(int(size.x), 1), maxi(int(size.y), 1), false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		var ty: float = y / maxf(image.get_height() - 1.0, 1.0)
		for x in image.get_width():
			var tx: float = x / maxf(image.get_width() - 1.0, 1.0)
			image.set_pixel(x, y, top_left.lerp(top_right, tx).lerp(bottom_left.lerp(bottom_right, tx), ty))
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.position = at
	rect.size = size
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	if additive:
		rect.material = CanvasItemMaterial.new()
		rect.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return rect
func _place(texture: ImageTexture, at: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.size = texture.get_size()
	rect.position = at
	screen.add_child(rect)
	return rect
func _panel(p: int, exe) -> void:
	var character: int = first_roster if p == 0 else second_roster
	var rgb := Color8(exe.u8(COLORS + character * 4 + 1), exe.u8(COLORS + character * 4 + 2), exe.u8(COLORS + character * 4 + 3))
	var holder := Control.new()
	var origin: Vector2 = PANEL_POSITION[p]
	holder.add_child(_gradient(origin, Vector2(126, 106), Color.BLACK, Color.BLACK, rgb, rgb, true))
	holder.add_child(_gradient(origin + Vector2(0, 106), Vector2(126, 106), rgb, rgb, Color8(0xc0, 0xc0, 0xc0), Color8(0xc0, 0xc0, 0xc0), true))
	Tim.semi_alpha = 1.0
	var image := Tim.to_image(FileAccess.get_file_as_bytes("%s009/p%02d.tim" % [BNS, first_roster if p == 0 else second_roster]), 4)
	Tim.semi_alpha = 1.0
	if p == 1:
		image.flip_x()
	var portrait := TextureRect.new()
	portrait.texture = ImageTexture.create_from_image(image.get_region(Rect2i(0, 20, 126, 212)))
	portrait.position = origin
	portrait.size = Vector2(126, 212)
	holder.add_child(portrait)
	for edge in [Rect2(-2, 0, 2, 212), Rect2(126, 0, 2, 212), Rect2(-2, -6, 130, 6), Rect2(-2, 212, 130, 6)]:
		var line := ColorRect.new()
		line.color = Color8(0xe8, 0xe8, 0xe8)
		line.position = origin + edge.position
		line.size = edge.size
		holder.add_child(line)
	screen.add_child(holder)
	movers.append([holder, -140.0 if p == 0 else 140.0, 0.0, 20.0])
func _name(p: int, exe, font) -> void:
	var character: int = first_roster if p == 0 else second_roster
	var text: String = exe.cstring(exe.u32(exe.u32(0x80097d40 + character * 16)))
	var texture: ImageTexture = font.render_clut(text, 2, 0x7e98)
	var width: int = (text.length() - 1) * 21 + 24
	var rect := TextureRect.new()
	rect.texture = texture
	rect.size = texture.get_size()
	rect.position = Vector2(149 if p == 0 else 222 - width, NAME_Y[p])
	screen.add_child(rect)
	movers.append([rect, -203.0 if p == 0 else 203.0, rect.position.x, 29.0])
func _set_late(on: bool) -> void:
	for node in late:
		node.visible = on
func _process(delta: float) -> void:
	elapsed += delta
	var frame: int = int(elapsed / FRAME) - LEAD_FRAMES
	var step: int = clampi(frame, 0, SLIDE_FRAMES - 1)
	for m in movers:
		var distance: float = m[3] * (SLIDE_FRAMES - 1 - step)
		m[0].position.x = m[2] + (-distance if m[1] < 0.0 else distance)
		m[0].visible = frame >= 0
	_set_late(frame >= SLIDE_FRAMES - 1)
	if elapsed > SHOW_SECONDS:
		set_process(false)
		finished.emit()
func _unhandled_input(event: InputEvent) -> void:
	if elapsed > 0.8 and (event.is_action_pressed("menu_start") or event.is_action_pressed("menu_confirm")):
		set_process(false)
		finished.emit()
