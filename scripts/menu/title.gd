extends "res://scripts/menu/menu_screen.gd"
signal chosen(item: String)
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const ITEMS := ["ARCADE MODE", "QUIT GAME", "VS MODE", "TEAM BATTLE MODE", "TIME ATTACK MODE", "SURVIVAL MODE", "TEKKEN BALL MODE", "TEKKEN FORCE MODE", "PRACTICE MODE", "THEATER MODE", "OPTION MODE"]
const TINTS := [Color(1.0, 0.72, 0.25), Color(0.35, 0.9, 1.0), Color(0.9, 0.2, 0.15), Color(0.6, 0.15, 0.1)]
const ROWS := [-2, -1, 0, 1, 2]
var font
var rows: Array = []
var selected := 0
func _ready() -> void:
	var exe = Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
	font = GameFont.new(exe, BNS + "010/")
	for r in 2:
		for c in 3:
			sprite(BNS + "000/p%02d.tim" % (r * 3 + c), Vector2(c * 128, r * 256))
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.25)
	bar.position = Vector2(-400, 358)
	bar.size = Vector2(1200, 34)
	screen.add_child(bar)
	for r in ROWS:
		var line := TextureRect.new()
		screen.add_child(line)
		rows.append(line)
	_refresh()
func _refresh() -> void:
	for i in ROWS.size():
		var item: String = ITEMS[(selected + ROWS[i] + ITEMS.size()) % ITEMS.size()]
		var tex: ImageTexture = font.texture(item, 2)
		var line: TextureRect = rows[i]
		line.texture = tex
		line.size = tex.get_size()
		line.scale = Vector2(1, 0.55)
		line.position = Vector2(184 - tex.get_width() / 2, 376 + ROWS[i] * 27 - tex.get_height() * 0.55 / 2)
		line.modulate = TINTS[mini(absi(ROWS[i]), 3)] if ROWS[i] == 0 else TINTS[mini(absi(ROWS[i]) + 1, 3)]
		line.modulate.a = 1.0 if absi(ROWS[i]) < 2 else 0.5
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_down"):
		selected = (selected + 1) % ITEMS.size()
		_refresh()
	elif event.is_action_pressed("menu_up"):
		selected = (selected - 1 + ITEMS.size()) % ITEMS.size()
		_refresh()
	elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("menu_start"):
		chosen.emit(ITEMS[selected])
