extends "res://scripts/menu/menu_screen.gd"
# Music player of the theater. Track list from record 301 (28-byte entries at +0x2050, song
# index = entry number, name pointer in word 5); layout from the original draw list.
signal play(song: int, remixed: bool)
signal theater
signal back
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const BASE := 0x800b8d58
const LIST := 0x2050
const ROWS := 14
const ART := [[0x1f07c, 242, 90], [0x25e9c, 242, 346]]
const ICON := 0x10384
const BUTTONS := [["THEATER", Rect2(242, 192, 79, 28), "RETURN TO THEATER MODE SCREEN"], ["BGM SELECT", Rect2(242, 222, 106, 28), "SELECT MUSIC MODE"], ["DISC", Rect2(242, 252, 52, 28), "INSERT TEKKEN 1, 2, OR 3 DISC"], ["EXIT", Rect2(242, 282, 52, 28), "RETURN TO TITLE SCREEN"]]
var bytes: PackedByteArray
var font
var names: Array = []
var remixed := true
var cursor := 0
var top := 0
var button := -1
var title := TextureRect.new()
var highlight := ColorRect.new()
var rows: Array = []
var buttons: Array = []
var icon := TextureRect.new()
var name_label := TextureRect.new()
var mode_label := TextureRect.new()
var note := TextureRect.new()
func _init(start: int = 0, mode: bool = true) -> void:
	cursor = start
	remixed = mode
func _ready() -> void:
	bytes = FileAccess.get_file_as_bytes(BNS + "301.bin")
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	var at := LIST
	while bytes.decode_u16(at + 8) == 0xffff:
		var pointer := bytes.decode_u32(at + 20)
		names.append(bytes.slice(pointer - BASE).get_string_from_ascii())
		at += 28
	top = clampi(cursor - ROWS + 1, 0, maxi(names.size() - ROWS, 0))
	_background()
	_art()
	_frame()
	for i in ROWS:
		var row := TextureRect.new()
		row.position = Vector2(30, 80 + i * 20)
		screen.add_child(row)
		rows.append(row)
	title.position = Vector2(41, 34)
	screen.add_child(title)
	_buttons()
	_info()
	_refresh()
func _gradient(area: Rect2, top_color: Color, bottom_color: Color) -> TextureRect:
	var image := Image.create(1, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		image.set_pixel(0, y, top_color.lerp(bottom_color, y / 63.0))
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.position = area.position
	rect.size = area.size
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	return rect
func _box(area: Rect2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = area.position
	rect.size = area.size
	return rect
func _background() -> void:
	screen.add_child(_gradient(Rect2(0, 0, 368, 480), Color8(0, 0, 0x20), Color8(0, 0, 0x80)))
func _art() -> void:
	for piece in ART:
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(Tim.to_image(bytes.slice(piece[0])))
		rect.position = Vector2(piece[1], piece[2])
		rect.size = rect.texture.get_size()
		screen.add_child(rect)
func _frame() -> void:
	for edge in [Rect2(24, 72, 206, 2), Rect2(24, 360, 206, 2), Rect2(24, 72, 2, 290), Rect2(228, 72, 2, 290)]:
		screen.add_child(_box(edge, Color.WHITE))
	highlight.color = Color8(0x1e, 0x3d, 0xf6)
	highlight.size = Vector2(204, 18)
	highlight.z_index = -1
	screen.add_child(highlight)
func _buttons() -> void:
	for i in BUTTONS.size():
		var area: Rect2 = BUTTONS[i][1]
		screen.add_child(_box(Rect2(area.position + Vector2(0, 2), area.size - Vector2(0, 2)), Color8(0, 0, 0x80)))
		for edge in [Rect2(area.position.x, area.position.y + 2, area.size.x, 2), Rect2(area.position.x, area.end.y - 2, area.size.x, 2), Rect2(area.position.x, area.position.y + 2, 2, area.size.y - 2), Rect2(area.end.x - 2, area.position.y + 2, 2, area.size.y - 2)]:
			screen.add_child(_box(edge, Color.WHITE))
		var label := TextureRect.new()
		label.position = Vector2(area.position.x + 8, area.position.y + 8)
		screen.add_child(label)
		buttons.append(label)
func _info() -> void:
	screen.add_child(_gradient(Rect2(18, 374, 332, 82), Color8(0, 0, 0x80), Color8(0, 0, 0x20)))
	for edge in [Rect2(18, 374, 332, 4), Rect2(18, 452, 332, 4), Rect2(18, 374, 3, 82), Rect2(347, 374, 3, 82)]:
		screen.add_child(_box(edge, Color.WHITE))
	icon.texture = ImageTexture.create_from_image(Tim.to_image(bytes.slice(ICON)))
	icon.size = Vector2(20, 32)
	icon.position = Vector2(131, 386)
	for node in [icon, name_label, mode_label, note]:
		screen.add_child(node)
func _text(rect: TextureRect, text: String, size_class: int, clut: int, x: float, y: float, centered: bool = false) -> void:
	var texture: ImageTexture = font.render_clut(text, size_class, clut)
	rect.texture = texture
	rect.size = texture.get_size()
	rect.position = Vector2(x - texture.get_width() / 2 if centered else x, y)
func _refresh() -> void:
	_text(title, "TEKKEN 3 %s MUSIC" % ("REMIXED" if remixed else "ARCADE"), 1, 0x7e51 if remixed else 0x7e56, 41, 34)
	for i in ROWS:
		var index := top + i
		var visible: bool = index < names.size()
		rows[i].visible = visible
		if visible:
			var selected: bool = index == cursor and button < 0
			var clut := 0x7e15 if selected else (0x7e1b if remixed else 0x7e1a)
			_text(rows[i], "%2d:%s" % [index + 1, names[index]], 0, clut, 30, 80 + i * 20)
	highlight.visible = button < 0
	highlight.position = Vector2(25, 79 + (cursor - top) * 20)
	for i in BUTTONS.size():
		_text(buttons[i], BUTTONS[i][0], 0, 0x7e15 if i == button else 0x7e1a, buttons[i].position.x, buttons[i].position.y)
	var listing := button < 0
	icon.visible = listing
	name_label.visible = listing
	mode_label.visible = listing
	note.visible = not listing
	if listing:
		_text(name_label, names[cursor], 1, 0x7e56, 174, 380)
		icon.position.x = 174 - 30 - (name_label.size.x - 52) / 2.0
		name_label.position.x = icon.position.x + 43
		_text(mode_label, "REMIXED" if remixed else "ARCADE", 0, 0x7e15, 260, 422)
	else:
		_text(note, BUTTONS[button][2], 0, 0x7e16, 184, 400, true)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_back"):
		back.emit()
		return
	var moved := false
	if button < 0:
		if event.is_action_pressed("menu_down") or event.is_action_pressed("menu_up"):
			cursor = posmod(cursor + (1 if event.is_action_pressed("menu_down") else -1), names.size())
			top = clampi(top, maxi(cursor - ROWS + 1, 0), cursor)
			moved = true
		elif event.is_action_pressed("menu_right"):
			button = 0
			moved = true
		elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("menu_start"):
			blip(BLIP_CONFIRM)
			play.emit(cursor, remixed)
	else:
		if event.is_action_pressed("menu_down") or event.is_action_pressed("menu_up"):
			button = posmod(button + (1 if event.is_action_pressed("menu_down") else -1), BUTTONS.size())
			moved = true
		elif event.is_action_pressed("menu_left"):
			button = -1
			moved = true
		elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("menu_start"):
			blip(BLIP_CONFIRM)
			match button:
				0:
					theater.emit()
				1:
					remixed = not remixed
					_refresh()
				3:
					back.emit()
	if moved:
		blip(BLIP_CURSOR)
		_refresh()
