extends "res://scripts/menu/menu_screen.gd"
signal chosen(item: String)
signal entered
signal idle
const PUSH_IDLE := 20.0
const MENU_IDLE := 30.0
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const ITEMS := ["ARCADE MODE", "QUIT GAME", "VS MODE", "TEAM BATTLE MODE", "TIME ATTACK MODE", "SURVIVAL MODE", "TEKKEN BALL MODE", "TEKKEN FORCE MODE", "PRACTICE MODE", "THEATER MODE", "OPTION MODE"]
const CLUTS := {"ARCADE MODE": 0x7e55, "QUIT GAME": 0x7e52, "VS MODE": 0x7e52, "TEAM BATTLE MODE": 0x7e57, "TIME ATTACK MODE": 0x7e56, "SURVIVAL MODE": 0x7e51, "TEKKEN BALL MODE": 0x7e54, "TEKKEN FORCE MODE": 0x7e58, "PRACTICE MODE": 0x7e50, "THEATER MODE": 0x7e5c, "OPTION MODE": 0x7e59}
const ROWS := [-3, -2, -1, 0, 1, 2, 3]
const ROW_TOP := 278
const ROW_STEP := 28
const SLIDE_DECAY := 0.7
var slide := 0.0
var overlays: Array = []
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
	var strip := Image.create(368, 28, false, Image.FORMAT_RGBA8)
	for x in 368:
		var across: float = clampf(1.0 - absf(x - 184.0) / 176.0, 0.0, 1.0)
		var line: float = clampf(1.0 - absf(x - 184.0) / 184.0, 0.0, 1.0) * 0.97
		for y in 28:
			var shade: float = line if y < 2 or y >= 26 else across * 0.75
			strip.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	bar.texture = ImageTexture.create_from_image(strip)
	bar.position = Vector2(0, 360)
	bar.size = Vector2(368, 28)
	screen.add_child(bar)
	_push_screen()
	for r in ROWS:
		var line := TextureRect.new()
		screen.add_child(line)
		rows.append(line)
	_refresh()
func _push_screen() -> void:
	var tex: ImageTexture = font.render_clut("PUSH P1 AND/OR P2 BUTTON", 0, 0x7e15)
	prompt.texture = tex
	prompt.size = tex.get_size()
	prompt.position = Vector2(184 - tex.get_width() / 2.0, 362)
	screen.add_child(prompt)
	var logo := sprite(BNS + "000/p06.tim", Vector2(184 - 36, 394))
	extras.append(logo)
	for i in 2:
		var line: ImageTexture = font.render_clut(["TM&@1994 1995 1996 1998 NAMCO LTD.", "ALL RIGHTS RESERVED"][i], 0, 0x7e16)
		var row := TextureRect.new()
		row.texture = line
		row.size = line.get_size()
		row.position = Vector2(184 - line.get_width() / 2.0, 424 + i * 18)
		screen.add_child(row)
		extras.append(row)
	extras.append(prompt)
func _process(delta: float) -> void:
	blink += delta
	if slide != 0.0:
		slide *= pow(SLIDE_DECAY, delta * 60.0)
		if absf(slide) < 0.5:
			slide = 0.0
		_place()
	waited += delta
	prompt.visible = not pushed and fmod(blink, 1.0) < 0.6
	if waited > (MENU_IDLE if pushed else PUSH_IDLE):
		waited = 0.0
		idle.emit()
const FADE := [0.0, 0.35, 1.0, 1.0, 1.0, 0.45, 0.0]
func _place() -> void:
	for i in rows.size():
		var y: float = ROW_TOP + i * ROW_STEP + slide
		rows[i].position.y = y
		var d: float = (y - 362.0) / ROW_STEP + 3.0
		var k := clampi(int(floor(d)), 0, FADE.size() - 2)
		var shade: float = lerpf(FADE[k], FADE[k + 1], clampf(d - k, 0.0, 1.0))
		rows[i].modulate = Color(1.0, 1.0, 1.0, shade)
func _refresh() -> void:
	for r in rows:
		r.visible = pushed
	bar.visible = pushed
	for e in extras:
		e.visible = not pushed
	for i in ROWS.size():
		var item: String = ITEMS[(selected + ROWS[i] + ITEMS.size() * 2) % ITEMS.size()]
		var tex: ImageTexture = font.render_clut(item, 1, CLUTS[item])
		var line: TextureRect = rows[i]
		line.texture = tex
		line.size = tex.get_size()
		line.position = Vector2(int(184.0 - item.length() * 13 / 2.0 + 0.5), ROW_TOP + i * ROW_STEP + slide)
	_place()
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
		slide = ROW_STEP
		blip(BLIP_CURSOR)
		_refresh()
	elif event.is_action_pressed("menu_up"):
		selected = (selected - 1 + ITEMS.size()) % ITEMS.size()
		slide = -ROW_STEP
		blip(BLIP_CURSOR)
		_refresh()
	elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("menu_start"):
		blip(BLIP_CONFIRM)
		chosen.emit(ITEMS[selected])
