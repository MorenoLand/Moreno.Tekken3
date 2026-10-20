extends "res://scripts/menu/menu_screen.gd"
signal chosen(item: String)
signal entered
signal idle
const PUSH_IDLE := 20.0
const MENU_IDLE := 30.0
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const ITEMS := ["ARCADE MODE", "QUIT GAME", "VS MODE", "TEAM BATTLE MODE", "TIME ATTACK MODE", "SURVIVAL MODE", "TEKKEN BALL MODE", "TEKKEN FORCE MODE", "PRACTICE MODE", "THEATER MODE", "OPTION MODE"]
const TINTS := [Color(1.0, 0.72, 0.25), Color(0.35, 0.9, 1.0), Color(0.9, 0.2, 0.15), Color(0.6, 0.15, 0.1)]
const ROWS := [-2, -1, 0, 1, 2]
var font
var rows: Array = []
var bar := TextureRect.new()
var selected := 0
var pushed := false
var blink := 0.0
var waited := 0.0
var extras: Array = []
var prompt := TextureRect.new()
func _ready() -> void:
	var exe = Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
	font = GameFont.new(exe, BNS + "010/")
	for r in 2:
		for c in 3:
			sprite(BNS + "000/p%02d.tim" % (r * 3 + c), Vector2(c * 128, r * 256))
	var strip := Image.create(400, 32, false, Image.FORMAT_RGBA8)
	for x in 400:
		var edge: float = absf(x / 400.0 - 0.5) * 2.0
		var shade: float = 0.1 + 0.7 * pow(1.0 - edge, 1.4)
		for y in 32:
			var line: float = 1.0 if y < 2 or y > 29 else (0.85 + 0.15 * sin(y * 0.2))
			strip.set_pixel(x, y, Color(shade * line, shade * line, shade * line, 0.95 if y > 1 and y < 30 else 0.6))
	bar.texture = ImageTexture.create_from_image(strip)
	bar.position = Vector2(-16, 361)
	bar.size = Vector2(400, 32)
	screen.add_child(bar)
	_push_screen()
	for r in ROWS:
		var line := TextureRect.new()
		screen.add_child(line)
		rows.append(line)
	_refresh()
func _push_screen() -> void:
	var tex: ImageTexture = font.texture("PUSH P1 AND/OR P2 BUTTON", 0)
	prompt.texture = tex
	prompt.size = tex.get_size()
	prompt.position = Vector2(184 - tex.get_width() / 2.0, 362)
	prompt.modulate = Color(1.0, 0.8, 0.1)
	screen.add_child(prompt)
	var logo := sprite(BNS + "000/p06.tim", Vector2(184 - 36, 394))
	extras.append(logo)
	for i in 2:
		var line: ImageTexture = font.texture(["TM&@1994 1995 1996 1998 NAMCO LTD.", "ALL RIGHTS RESERVED"][i], 0)
		var row := TextureRect.new()
		row.texture = line
		row.size = line.get_size()
		row.position = Vector2(184 - line.get_width() / 2.0, 424 + i * 18)
		screen.add_child(row)
		extras.append(row)
	extras.append(prompt)
func _process(delta: float) -> void:
	blink += delta
	waited += delta
	prompt.visible = not pushed and fmod(blink, 1.0) < 0.6
	if waited > (MENU_IDLE if pushed else PUSH_IDLE):
		waited = 0.0
		idle.emit()
func _refresh() -> void:
	for r in rows:
		r.visible = pushed
	bar.visible = pushed
	for e in extras:
		e.visible = not pushed
	for i in ROWS.size():
		var item: String = ITEMS[(selected + ROWS[i] + ITEMS.size()) % ITEMS.size()]
		var tex: ImageTexture = font.texture(item, 1)
		var line: TextureRect = rows[i]
		line.texture = tex
		line.size = tex.get_size()
		line.scale = Vector2(1, 1)
		line.position = Vector2(184 - tex.get_width() / 2, 376 + ROWS[i] * 28 - tex.get_height() / 2.0)
		line.modulate = TINTS[mini(absi(ROWS[i]), 3)] if ROWS[i] == 0 else TINTS[mini(absi(ROWS[i]) + 1, 3)]
		line.modulate.a = 1.0 if absi(ROWS[i]) < 2 else 0.5
func _unhandled_input(event: InputEvent) -> void:
	waited = 0.0
	if not pushed:
		for a in ["menu_start", "menu_confirm", "p1_start", "p2_start", "p1_lk", "p2_lk", "p1_lp", "p2_lp", "p1_rp", "p2_rp", "p1_rk", "p2_rk"]:
			if event.is_action_pressed(a):
				pushed = true
				blip(BLIP_CONFIRM)
				entered.emit()
				_refresh()
				return
		return
	if event.is_action_pressed("menu_down"):
		selected = (selected + 1) % ITEMS.size()
		blip(BLIP_CURSOR)
		_refresh()
	elif event.is_action_pressed("menu_up"):
		selected = (selected - 1 + ITEMS.size()) % ITEMS.size()
		blip(BLIP_CURSOR)
		_refresh()
	elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("menu_start"):
		blip(BLIP_CONFIRM)
		chosen.emit(ITEMS[selected])
