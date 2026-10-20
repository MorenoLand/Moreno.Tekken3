extends "res://scripts/menu/menu_screen.gd"
signal done
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const Options := preload("res://scripts/core/options.gd")
const Save := preload("res://scripts/core/save.gd")
const TOP := ["GAME OPTION", "SOUNDS", "KEY CONFIGURATION", "RECORDS", "DISPLAY ADJUST", "MEMORY CARD", "EXIT"]
const GAME_ROWS := [
	["DIFFICULTY LEVEL", "difficulty", ["EASY", "MEDIUM", "HARD"]],
	["FIGHT COUNT", "fights", ["1", "2", "3", "4", "5"]],
	["ROUND TIME", "time", ["60SEC", "50SEC", "40SEC", "30SEC", "20SEC"]],
	["CHARACTER CHANGE AT CONTINUE", "change", ["YES", "NO"]],
	["GUARD DAMAGE", "guard", ["YES", "NO"]],
	["SELECT CURSOR HOLD", "hold", ["YES", "NO"]],
	["QUICK SELECT", "quick", ["YES", "NO"]],
	["BGM SELECT", "bgm", ["ARCADE", "REMIXED"]],
	["SPEAKER OUT", "speaker", ["STEREO", "MONO"]],
]
const PREVIEW_LIT := [
	[1, 0, 1, 0, 0, 1, 1, 0], [1, 1, 0, 0, 0, 1, 0, 0], [1, 1, 1, 0, 0, 0, 0, 0], [1, 0, 0, 0, 0, 0, 0, 0],
	[1, 1, 1, 0, 0, 0, 0, 0], [1, 1, 0, 1, 1, 1, 1, 1], [1, 0, 0, 1, 1, 0, 1, 1], [1, 1, 1, 1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1, 1, 1, 1], [0, 0, 0, 0, 0, 0, 0, 0],
]
const PREVIEW_CLUTS := [0x7e55, 0x7e52, 0x7e57, 0x7e56, 0x7e51, 0x7e54, 0x7e58, 0x7e50]
const DEFAULT_RECORDS := [["XIAOYU", 7, 50], ["YOSHIMITSU", 4, 51], ["NINA", 5, 52], ["LAW", 1, 53], ["HWOARANG", 6, 54], ["EDDY", 8, 55], ["PAUL", 0, 56], ["KING", 3, 57], ["LEI", 2, 58], ["JIN", 9, 59]]
const KEY_BUTTONS := ["lp", "rp", "lk", "rk"]
var font
var vram: PackedInt32Array
var page := "top"
var selected := 0
var capturing := false
var capture_index := 0
var layer := Control.new()
var pulse := 0.0
var lit: ColorRect
var prompt := ""
func controls():
	return get_node("/root/Controls")
func _ready() -> void:
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	var tims := []
	for n in 140:
		var path := "%s010/p%02d.tim" % [BNS, n]
		if FileAccess.file_exists(path):
			tims.append_array(Tim.stream(FileAccess.get_file_as_bytes(path)))
	vram = Tim.compose_absolute(tims)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = Vector2(368, 480)
	screen.add_child(black)
	var field := ColorRect.new()
	field.color = Color8(0, 0, 0x60)
	field.position = Vector2(0, 20)
	field.size = Vector2(368, 450)
	screen.add_child(field)
	screen.add_child(_logo())
	screen.add_child(layer)
	_refresh()
func _logo() -> TextureRect:
	var image := Image.create(368, 480, false, Image.FORMAT_RGBA8)
	for r in 2:
		for c in 3:
			var piece := Tim.to_image(FileAccess.get_file_as_bytes("%s000/p%02d.tim" % [BNS, r * 3 + c]))
			image.blend_rect(piece, Rect2i(0, 0, piece.get_width(), piece.get_height()), Vector2i(c * 128, r * 256))
	for y in 480:
		for x in 368:
			var px := image.get_pixel(x, y)
			if px.a > 0.0:
				var lum: float = px.r * 0.3 + px.g * 0.5 + px.b * 0.2
				image.set_pixel(x, y, Color(0, 0, clampf(0.44 + lum * 0.4, 0.0, 0.82), 1.0))
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	return rect
func _text(text: String, f: int, clut: int, at: Vector2) -> TextureRect:
	var key := "%s@%d@%d" % [text, f, clut]
	if not cache.has(key):
		cache[key] = font.render_clut(text, f, clut)
	var rect := TextureRect.new()
	rect.texture = cache[key]
	rect.position = at
	rect.size = rect.texture.get_size()
	layer.add_child(rect)
	return rect
func _region(tpage: int, clut: int, region: Rect2i) -> ImageTexture:
	var key := Vector4i(tpage, clut, region.position.x * 1024 + region.position.y, region.size.x * 1024 + region.size.y)
	if not cache.has(key):
		cache[key] = ImageTexture.create_from_image(Tim.decode_region(vram, tpage, clut, region))
	return cache[key]
func _sprite(tpage: int, clut: int, at: Vector2, region: Rect2i) -> void:
	var rect := TextureRect.new()
	rect.texture = _region(tpage, clut, region)
	rect.position = at
	rect.size = Vector2(region.size)
	layer.add_child(rect)
func _block(at: Vector2, size: Vector2, color: Color) -> ColorRect:
	var block := ColorRect.new()
	block.position = at
	block.size = size
	block.color = color
	layer.add_child(block)
	return block
func _title(text: String, x: float) -> void:
	_text(text, 1, 0x7e56, Vector2(x if x >= 0.0 else int(184.0 - text.length() * 13 / 2.0 + 0.5), 40))
func _clear() -> void:
	for child in layer.get_children():
		child.queue_free()
		layer.remove_child(child)
	lit = null
func _refresh() -> void:
	_clear()
	match page:
		"top":
			_draw_top()
		"game":
			_draw_game()
		"sounds":
			_draw_sounds()
		"keys":
			_draw_keys()
		"records":
			_draw_records()
		"display":
			_draw_display()
		"card":
			_draw_card()
func _row(label: String, value: String, y: float, on: bool, width: float, value_clut: int = 0x7e11) -> void:
	if on:
		lit = _block(Vector2(17, y - 3), Vector2(width, 22), Color8(0x1f, 0x3e, 0xf7))
	_text(label, 0, 0x7e15 if on else 0x7e1a, Vector2(20, y))
	if value != "":
		_text(value, 0, value_clut, Vector2(344 - value.length() * 9, y))
func _draw_top() -> void:
	_title("OPTION MODE", -1.0)
	for i in TOP.size():
		_row(TOP[i], "", 100 + i * 34, i == selected, TOP[i].length() * 9 + 6)
func _draw_game() -> void:
	_title("GAME OPTION", 48.0)
	_block(Vector2(246, 40), Vector2(98, 116), Color8(0xc0, 0xc0, 0xc0))
	_block(Vector2(247, 42), Vector2(96, 112), Color.BLACK)
	for k in 8:
		_sprite(0xb, PREVIEW_CLUTS[k] if PREVIEW_LIT[selected][k] == 1 else 0x7e5e, Vector2(247, 42 + k * 14), Rect2i(0, k * 14, 96, 14))
	for i in GAME_ROWS.size():
		_row(GAME_ROWS[i][0], GAME_ROWS[i][2][Options.get_value(GAME_ROWS[i][1])], 170 + i * 27, i == selected, 330)
	_row("EXIT", "", 170 + GAME_ROWS.size() * 27, selected == GAME_ROWS.size(), 330)
func _pad_icons(at: Vector2) -> void:
	var x := at.x
	_block(Vector2(x + 1, at.y + 3), Vector2(9, 9), Color8(0xe0, 0x90, 0xd0))
	_block(Vector2(x + 3, at.y + 5), Vector2(5, 5), Color8(0x10, 0x10, 0x60))
	var triangle := Polygon2D.new()
	triangle.polygon = PackedVector2Array([Vector2(x + 24, at.y + 2), Vector2(x + 30, at.y + 13), Vector2(x + 18, at.y + 13)])
	triangle.color = Color8(0x40, 0xd0, 0x80)
	layer.add_child(triangle)
	var cross := Polygon2D.new()
	cross.polygon = PackedVector2Array([Vector2(x + 38, at.y + 2), Vector2(x + 41, at.y + 2), Vector2(x + 44, at.y + 6), Vector2(x + 47, at.y + 2), Vector2(x + 50, at.y + 2), Vector2(x + 46, at.y + 8), Vector2(x + 50, at.y + 14), Vector2(x + 47, at.y + 14), Vector2(x + 44, at.y + 10), Vector2(x + 41, at.y + 14), Vector2(x + 38, at.y + 14), Vector2(x + 42, at.y + 8)])
	cross.color = Color8(0x50, 0x80, 0xe8)
	layer.add_child(cross)
	var ring := Polygon2D.new()
	var points := PackedVector2Array()
	for k in 16:
		points.append(Vector2(x + 72 + cos(k * TAU / 16.0) * 6.0, at.y + 8 + sin(k * TAU / 16.0) * 6.0))
	ring.polygon = points
	ring.color = Color8(0xe0, 0x50, 0x40)
	layer.add_child(ring)
func _cancel_line(y: float) -> void:
	_text("CANCEL", 0, 0x7e15, Vector2(36, y))
	_text(": PUSH", 0, 0x7e16, Vector2(90, y))
	_pad_icons(Vector2(150, y))
	_text("OR", 0, 0x7e16, Vector2(240, y))
func _draw_display() -> void:
	_title("DISPLAY ADJUST", 92.0)
	layer.position = Vector2(Options.get_value("shift_x"), Options.get_value("shift_y"))
	for edge in [Rect2(138, 30, 92, 3), Rect2(138, 243, 92, 3), Rect2(138, 455, 92, 3), Rect2(183, 164, 2, 160), Rect2(6, 164, 2, 160), Rect2(360, 164, 2, 160)]:
		_block(edge.position, edge.size, Color8(0xe0, 0xe0, 0xe0))
	_text("DEFAULT", 0, 0x7e12, Vector2(36, 378))
	_text(": PUSH START", 0, 0x7e16, Vector2(36 + 63, 378))
	_text("EXIT", 0, 0x7e15, Vector2(62, 412))
	_text(": PUSH", 0, 0x7e16, Vector2(62 + 36, 412))
	_text("OR", 0, 0x7e16, Vector2(62 + 36 + 54 + 90, 412))
	_pad_icons(Vector2(62 + 36 + 54, 412))
func _draw_card() -> void:
	_title("MEMORY CARD", -1.0)
	layer.position = Vector2.ZERO
	var rows := ["CARD SAVE", "CARD LOAD", "AUTO SAVE", "EXIT"]
	for i in rows.size():
		var y := 100 + i * 40
		if i == 2:
			if selected == 2:
				lit = _block(Vector2(17, y - 3), Vector2(rows[i].length() * 9 + 6, 22), Color8(0x1f, 0x3e, 0xf7))
			_text(rows[i], 0, 0x7e15 if selected == 2 else 0x7e1a, Vector2(20, y))
			_text("YES" if Options.get_value("autosave") == 1 else "NO", 0, 0x7e11, Vector2(120, y))
		else:
			_row(rows[i], "", y, i == selected, rows[i].length() * 9 + 6)
	if prompt != "":
		_text(prompt, 0, 0x7e12, Vector2(36, 386))
		_text(": PUSH START", 0, 0x7e16, Vector2(36 + prompt.length() * 9 + 9, 386))
		_cancel_line(420)
func _draw_sounds() -> void:
	_title("SOUNDS", -1.0)
	_row("MUSIC VOLUME", str(Options.get_value("music")), 145, selected == 0, 330, 0x7e16)
	_row("SFX VOLUME", str(Options.get_value("sfx")), 193, selected == 1, 330, 0x7e16)
	_row("SAVE", "", 241, selected == 2, 330)
	_row("BACK", "", 289, selected == 3, 330)
func _key_name(player: int, button: String) -> String:
	var code: int = Options.key_for(player, button, controls().KEYS[player][button])
	return OS.get_keycode_string(code).to_upper()
func _draw_keys() -> void:
	_title("KEY CONFIGURATION", 74.0)
	for p in 2:
		var left: float = 20.0 + p * 184.0
		var pad := _region(0x86, 0x7ca0, Rect2i(0, 0, 144, 136))
		var rect := TextureRect.new()
		rect.texture = pad
		rect.position = Vector2(left, 136)
		rect.size = Vector2(144, 136)
		layer.add_child(rect)
		for k in 4:
			var name := _key_name(p, KEY_BUTTONS[k])
			var box_at := Vector2(left + 5 + (k % 2) * 78, 76 + (k / 2) * 20)
			_block(box_at, Vector2(64, 18), Color.WHITE)
			_block(box_at + Vector2(1, 1), Vector2(62, 16), Color.BLACK)
			_text(name.substr(0, 6), 0, 0x7e16, box_at + Vector2(2, 1))
		for k in 4:
			var tag: String = ["LP", "RP", "LK", "RK"][k]
			var colors := [Color(1, 0.25, 1), Color(0.5, 1, 0), Color(0.25, 0.5, 1), Color(1, 0.5, 0.25)]
			var at := Vector2(left + 10 + (k % 2) * 78, 281 + (k / 2) * 26)
			_block(at, Vector2(64, 22), colors[k])
			_block(at + Vector2(1, 2), Vector2(62, 18), Color.BLACK)
			_text(tag, 0, 0x7e16, at + Vector2(24, 3))
		_row_at(left, "SETTING", "", 340, selected == p * 4)
	for p in 2:
		var left: float = 20.0 + p * 184.0
		_text("VIBRATION", 0, 0x7e15 if selected == p * 4 + 1 else 0x7e1a, Vector2(left, 366))
		_text(["YES", "NO"][Options.get_value("vibration")], 0, 0x7e11, Vector2(left + 126 - 9 * 2, 366))
		_text("DEFAULT", 0, 0x7e15 if selected == p * 4 + 2 else 0x7e1a, Vector2(left, 392))
		_text("EXIT", 0, 0x7e15 if selected == p * 4 + 3 else 0x7e1a, Vector2(left, 418))
func _row_at(left: float, label: String, value: String, y: float, on: bool) -> void:
	if on:
		lit = _block(Vector2(left - 3, y - 3), Vector2(label.length() * 9 + 6, 22), Color8(0x1f, 0x3e, 0xf7))
	_text(label, 0, 0x7e15 if on else 0x7e1a, Vector2(left, y))
func _record_rows() -> Array:
	Save._load()
	var rows := []
	for entry in DEFAULT_RECORDS:
		rows.append([entry[0], entry[2] * 3600])
	for key in Save.data["time_attack"]:
		rows.append([_costume_name(int(key) * 4), int(Save.data["time_attack"][key])])
	rows.sort_custom(func(a, b): return a[1] < b[1])
	return rows.slice(0, 10)
func _costume_name(costume: int) -> String:
	var e = font.fonts[0]["exe"]
	return e.cstring(e.u32(e.u32(0x80097d40 + costume * 4)))
func _draw_records() -> void:
	_text("PAGE:1", 0, 0x7e16, Vector2(288, 36))
	_title("RECORDS", 139.0)
	_text("CHARACTER TIME ATTACK DATA", 0, 0x7e16, Vector2(67, 90))
	_text("TIME", 0, 0x7e16, Vector2(234, 126))
	_text("NAME", 0, 0x7e16, Vector2(297, 126))
	var rows := _record_rows()
	for i in rows.size():
		var y: float = 146 + i * 20
		var ranks := ["1ST", "2ND", "3RD"]
		_text(ranks[i] if i < 3 else "%dTH" % (i + 1), 0, 0x7e16, Vector2(27 if i < 9 else 18, y))
		var name: String = rows[i][0]
		_text(name, 0, 0x7e16, Vector2(126 - name.length() * 9 / 2.0, y))
		var f: int = rows[i][1]
		_text("%02d'%02d\"%02d" % [f / 3600, f / 60 % 60, (f % 60) * 100 / 60], 0, 0x7e16, Vector2(198, y))
		_text(name.substr(0, 3), 0, 0x7e16, Vector2(306, y))
	_text("NEXT", 0, 0x7e17, Vector2(63, 380))
	_text(": LEFT OR RIGHT", 0, 0x7e16, Vector2(99, 380))
	_text("EXIT", 0, 0x7e12, Vector2(63, 420))
	_text(": PUSH", 0, 0x7e16, Vector2(99, 420))
func _process(delta: float) -> void:
	pulse += delta * 3.0
	if lit != null:
		var k: float = 0.5 + 0.5 * sin(pulse)
		lit.color = Color8(int(lerpf(0x12, 0x1e, k)), int(lerpf(0x24, 0x3c, k)), int(lerpf(0x8f, 0xef, k)))
func _count() -> int:
	match page:
		"top":
			return TOP.size()
		"game":
			return GAME_ROWS.size() + 1
		"sounds":
			return 4
		"keys":
			return 8
		"card":
			return 4
	return 1
func _unhandled_input(event: InputEvent) -> void:
	if capturing:
		if event is InputEventKey and event.pressed and not event.echo:
			var player := selected / 4
			if event.keycode != KEY_ESCAPE:
				controls().rebind(player, KEY_BUTTONS[capture_index], event.physical_keycode)
				capture_index += 1
			if event.keycode == KEY_ESCAPE or capture_index >= KEY_BUTTONS.size():
				capturing = false
			_refresh()
			get_viewport().set_input_as_handled()
		return
	var up: bool = event.is_action_pressed("menu_up")
	var down: bool = event.is_action_pressed("menu_down")
	var left: bool = event.is_action_pressed("menu_left")
	var right: bool = event.is_action_pressed("menu_right")
	var confirm: bool = event.is_action_pressed("menu_confirm") or event.is_action_pressed("menu_start")
	if page == "display":
		var shift := Vector2i(Options.get_value("shift_x"), Options.get_value("shift_y"))
		if left or right or up or down:
			shift += Vector2i((1 if right else 0) - (1 if left else 0), (1 if down else 0) - (1 if up else 0)) * 2
			Options.set_value("shift_x", clampi(shift.x, -16, 16))
			Options.set_value("shift_y", clampi(shift.y, -16, 16))
			blip(BLIP_CURSOR)
			_refresh()
		elif event.is_action_pressed("menu_start"):
			Options.set_value("shift_x", 0)
			Options.set_value("shift_y", 0)
			blip(BLIP_CONFIRM)
			_refresh()
		elif event.is_action_pressed("menu_back") or event.is_action_pressed("menu_confirm"):
			layer.position = Vector2.ZERO
			page = "top"
			selected = 4
			blip(BLIP_CONFIRM)
			_refresh()
		return
	if page == "card" and prompt != "":
		if event.is_action_pressed("menu_start"):
			if prompt == "SAVE":
				Save.save()
				Options.save()
			else:
				Save.loaded = false
				Save._load()
			blip(BLIP_CONFIRM)
			prompt = ""
			_refresh()
		elif event.is_action_pressed("menu_back") or event.is_action_pressed("menu_confirm"):
			prompt = ""
			_refresh()
		return
	if page == "records":
		if confirm or event.is_action_pressed("menu_back"):
			page = "top"
			selected = 3
			blip(BLIP_CONFIRM)
			_refresh()
		return
	if down or up:
		selected = (selected + (1 if down else -1) + _count()) % _count()
		blip(BLIP_CURSOR)
		_refresh()
	elif left or right:
		_adjust(1 if right else -1)
	elif confirm:
		blip(BLIP_CONFIRM)
		_confirm()
	elif event.is_action_pressed("menu_back"):
		_leave()
func _adjust(step: int) -> void:
	if page == "game" and selected < GAME_ROWS.size():
		var row: Array = GAME_ROWS[selected]
		Options.set_value(row[1], (Options.get_value(row[1]) + step + row[2].size()) % row[2].size())
	elif page == "sounds" and selected < 2:
		var key := "music" if selected == 0 else "sfx"
		Options.set_value(key, clampi(Options.get_value(key) + step * 10, 0, 100))
	elif page == "keys" and selected % 4 == 1:
		Options.set_value("vibration", 1 - Options.get_value("vibration"))
	else:
		return
	blip(BLIP_CURSOR)
	_refresh()
func _confirm() -> void:
	match page:
		"top":
			match TOP[selected]:
				"GAME OPTION":
					page = "game"
				"SOUNDS":
					page = "sounds"
				"KEY CONFIGURATION":
					page = "keys"
				"RECORDS":
					page = "records"
				"DISPLAY ADJUST":
					page = "display"
				"MEMORY CARD":
					page = "card"
				"EXIT":
					done.emit()
					return
			selected = 0
		"game":
			if selected == GAME_ROWS.size():
				_leave()
				return
			_adjust(1)
			return
		"sounds":
			if selected >= 2:
				_leave()
				return
		"card":
			match selected:
				0:
					prompt = "SAVE"
				1:
					prompt = "LOAD"
				2:
					Options.set_value("autosave", 1 - Options.get_value("autosave"))
				3:
					_leave()
					return
			_refresh()
			return
		"keys":
			match selected % 4:
				0:
					capturing = true
					capture_index = 0
				1:
					_adjust(1)
					return
				2:
					controls().defaults()
				3:
					_leave()
					return
	_refresh()
func _leave() -> void:
	if page == "top":
		done.emit()
		return
	selected = TOP.find({"game": "GAME OPTION", "sounds": "SOUNDS", "keys": "KEY CONFIGURATION", "records": "RECORDS", "display": "DISPLAY ADJUST", "card": "MEMORY CARD"}.get(page, "EXIT"))
	page = "top"
	_refresh()
