extends "res://scripts/menu/menu_screen.gd"
# Movie theater menu. Layout from the original draw list; entries come from the table in
# record 301 (28 bytes each at +0x1400, strings addressed from VA 0x800b8d58).
signal play(movie: int)
signal back
signal music
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const Save := preload("res://scripts/core/save.gd")
const BASE := 0x800b8d58
const TABLE := 0x1400
const ROWS := [[40, 72, 6], [40, 136, 6], [40, 200, 6], [88, 264, 4]]
const MOVIES := [20, 21, 9, 0, 1, 3, 4, 5, 2, 8, 6, 7, 11, 10, 16, 15, 17, 12, 13, 14, 19, 18]
const ALTERNATE_NAMES := ["YOSHIMITSU,DOCTOR B.", "KUMA, PANDA", "GUN JACK -BAD-", "OGRE, TRUE OGRE"]
const BUTTONS := [["DISC", Rect2(74, 336, 52, 28), "INSERT TEKKEN 1, 2, OR 3 DISC"], ["MUSIC", Rect2(154, 336, 61, 28), "SELECT MUSIC MODE"], ["EXIT", Rect2(244, 336, 52, 28), "RETURN TO TITLE SCREEN"]]
var bytes: PackedByteArray
var font
var items: Array = []
var cells: Array = []
var cursor := 0
var button := -1
var thumbnail := TextureRect.new()
var title := TextureRect.new()
var lines := [TextureRect.new(), TextureRect.new()]
var marker: Array = []
var button_labels: Array = []
var note := TextureRect.new()
func _init(start: int = 0) -> void:
	cursor = start
func _ready() -> void:
	bytes = FileAccess.get_file_as_bytes(BNS + "301.bin")
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	_read_entries()
	_background()
	_place(font.render_clut("TEKKEN 3 MOVIE THEATER", 1, 0x7e56), Vector2(41, 34))
	_grid()
	_buttons()
	_info_box()
	_refresh()
func _string(pointer: int) -> String:
	if pointer < BASE or pointer - BASE >= bytes.size():
		return ""
	return bytes.slice(pointer - BASE).get_string_from_ascii()
func _read_entries() -> void:
	var entries := []
	for k in 24:
		var at := TABLE + k * 28
		entries.append({"first": bytes.decode_u32(at), "second": bytes.decode_u32(at + 4), "thumb": bytes.decode_u16(at + 12), "mask": bytes.decode_u32(at + 16), "name": bytes.decode_u32(at + 24), "sentinel": bytes.decode_u16(at + 8) == 0xfffe})
	for k in 23:
		if entries[k]["sentinel"]:
			continue
		var e: Dictionary = entries[k]
		var next: Dictionary = entries[k + 1]
		var name: String = _string(e["name"])
		if e["name"] < 4:
			name = ALTERNATE_NAMES[e["name"]]
		var text := []
		for pointer in [next["first"], next["second"]]:
			var s := _string(pointer)
			if s != "":
				text.append(s)
		items.append({"thumb": e["thumb"], "mask": e["mask"], "name": name, "lines": text})
func _unlocked(item: Dictionary) -> bool:
	if item["mask"] == 0 or Save.data["unlock_all"]:
		return true
	for c in 21:
		if item["mask"] >> c & 1 and Save.endings().has(c):
			return true
	return false
func _background() -> void:
	screen.add_child(_gradient(Rect2(0, 0, 368, 480), Color8(0, 0, 0x20), Color8(0, 0, 0x80)))
func _gradient(area: Rect2, top: Color, bottom: Color) -> TextureRect:
	var image := Image.create(1, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		image.set_pixel(0, y, top.lerp(bottom, y / 63.0))
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.position = area.position
	rect.size = area.size
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	return rect
func _place(texture: ImageTexture, at: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.size = texture.get_size()
	rect.position = at
	screen.add_child(rect)
	return rect
func _box(area: Rect2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = area.position
	rect.size = area.size
	return rect
func _grid() -> void:
	var index := 0
	for r in ROWS.size():
		for c in ROWS[r][2]:
			var at := Vector2(ROWS[r][0] + 48 * c, ROWS[r][1])
			cells.append({"row": r, "column": c, "at": at})
			var item: Dictionary = items[index]
			var picture := TextureRect.new()
			picture.texture = _thumbnail(item)
			picture.position = at
			picture.size = Vector2(48, 64)
			screen.add_child(picture)
			var film := TextureRect.new()
			film.texture = tim_texture(BNS + "301/p61.tim")
			film.position = at
			film.size = Vector2(48, 64)
			screen.add_child(film)
			index += 1
	for i in 4:
		var line := ColorRect.new()
		line.color = Color8(0xff, 0, 0)
		marker.append(line)
		screen.add_child(line)
func _thumbnail(item: Dictionary) -> ImageTexture:
	if not _unlocked(item):
		return ImageTexture.create_from_image(Image.create(48, 64, false, Image.FORMAT_RGBA8))
	return tim_texture("%s301/p%02d.tim" % [BNS, item["thumb"]])
func _buttons() -> void:
	for i in BUTTONS.size():
		var area: Rect2 = BUTTONS[i][1]
		var holder := Control.new()
		holder.add_child(_box(Rect2(area.position + Vector2(0, 2), area.size - Vector2(0, 2)), Color8(0, 0, 0x80)))
		for edge in [Rect2(area.position.x, area.position.y + 2, area.size.x, 2), Rect2(area.position.x, area.end.y - 2, area.size.x, 2), Rect2(area.position.x, area.position.y + 2, 2, area.size.y - 2), Rect2(area.end.x - 2, area.position.y + 2, 2, area.size.y - 2)]:
			holder.add_child(_box(edge, Color.WHITE))
		screen.add_child(holder)
		var label := _place(font.render_clut(BUTTONS[i][0], 0, 0x7e1a), Vector2(area.position.x + (area.size.x - BUTTONS[i][0].length() * 9) / 2, 344))
		button_labels.append(label)
func _info_box() -> void:
	screen.add_child(_gradient(Rect2(18, 374, 332, 82), Color8(0, 0, 0x80), Color8(0, 0, 0x20)))
	for edge in [Rect2(18, 374, 332, 4), Rect2(18, 452, 332, 4), Rect2(18, 374, 3, 82), Rect2(347, 374, 3, 82)]:
		screen.add_child(_box(edge, Color.WHITE))
	thumbnail.position = Vector2(30, 384)
	thumbnail.size = Vector2(48, 64)
	screen.add_child(thumbnail)
	screen.add_child(title)
	for line in lines:
		screen.add_child(line)
	screen.add_child(note)
func _centered(rect: TextureRect, texture: ImageTexture, y: float) -> void:
	rect.texture = texture
	rect.size = texture.get_size()
	rect.position = Vector2(213 - texture.get_width() / 2, y)
func _refresh() -> void:
	var item: Dictionary = items[cursor]
	var open := _unlocked(item)
	thumbnail.texture = _thumbnail(item)
	_centered(title, font.render_clut(item["name"] if open else "???", 1, 0x7e56), 386)
	var text: Array = item["lines"] if open else []
	for i in 2:
		lines[i].texture = null
	var first := 2 - text.size()
	for i in text.size():
		_centered(lines[first + i], font.render_clut(text[i], 0, 0x7e15), 413 + (first + i) * 18)
	var at: Vector2 = cells[cursor]["at"]
	var show := button < 0
	var frame := [Rect2(at.x - 2, at.y - 3, 52, 4), Rect2(at.x - 2, at.y + 63, 52, 4), Rect2(at.x - 2, at.y - 3, 3, 70), Rect2(at.x + 47, at.y - 3, 3, 70)]
	for i in 4:
		marker[i].visible = show
		marker[i].position = frame[i].position
		marker[i].size = frame[i].size
	for i in button_labels.size():
		button_labels[i].texture = font.render_clut(BUTTONS[i][0], 0, 0x7e15 if button == i else 0x7e1a)
	for node in [thumbnail, title, lines[0], lines[1]]:
		node.visible = button < 0
	note.visible = button >= 0
	if button >= 0:
		_centered(note, font.render_clut(BUTTONS[button][2], 0, 0x7e16), 400)
		return
func _neighbour(row: int, column: int) -> int:
	var best := -1
	var gap := 99
	for i in cells.size():
		if cells[i]["row"] == row:
			var d: int = absi(cells[i]["column"] + (1 if row == 3 else 0) - column)
			if d < gap:
				gap = d
				best = i
	return best
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_back"):
		back.emit()
		return
	if event.is_action_pressed("menu_right") or event.is_action_pressed("menu_left"):
		var step := 1 if event.is_action_pressed("menu_right") else -1
		if button >= 0:
			button = clampi(button + step, 0, BUTTONS.size() - 1)
		else:
			var next: int = cursor + step
			if next >= 0 and next < cells.size() and cells[next]["row"] == cells[cursor]["row"]:
				cursor = next
		blip(BLIP_CURSOR)
		_refresh()
	elif event.is_action_pressed("menu_down") or event.is_action_pressed("menu_up"):
		var down := event.is_action_pressed("menu_down")
		if button >= 0:
			if not down:
				button = -1
		else:
			var row: int = cells[cursor]["row"]
			var column: int = cells[cursor]["column"] + (1 if row == 3 else 0)
			var target := row + (1 if down else -1)
			if down and row == ROWS.size() - 1:
				button = 0
			elif target >= 0 and target < ROWS.size():
				cursor = _neighbour(target, column)
		blip(BLIP_CURSOR)
		_refresh()
	elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("menu_start"):
		blip(BLIP_CONFIRM)
		if button == 2:
			back.emit()
		elif button == 1:
			music.emit()
		elif button < 0 and _unlocked(items[cursor]):
			play.emit(MOVIES[cursor])
