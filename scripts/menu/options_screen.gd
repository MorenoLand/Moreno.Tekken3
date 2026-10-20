extends "res://scripts/menu/menu_screen.gd"
signal done
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const Options := preload("res://scripts/core/options.gd")
const Save := preload("res://scripts/core/save.gd")
const WINDOW := 8
const BUTTON_NAMES := ["up", "down", "left", "right", "lp", "rp", "lk", "rk", "start"]
const GAME_ROWS := [
	["DIFFICULTY LEVEL", "difficulty", ["EASY", "MEDIUM", "HARD"]],
	["FIGHT COUNT", "fights", ["1", "2", "3", "4", "5"]],
	["ROUND TIME", "time", ["60SEC", "50SEC", "40SEC", "30SEC", "20SEC"]],
	["GUARD DAMAGE", "guard", ["ON", "OFF"]],
	["CHARACTER CHANGE AT CONTINUE", "change", ["YES", "NO"]],
	["SPEAKER OUT", "speaker", ["STEREO", "MONO"]],
	["BGM SELECT", "bgm", ["ARCADE", "REMIXED", "SILENT"]],
]
var font
var page := "top"
var selected := 0
var capturing := false
func controls():
	return get_node("/root/Controls")
var labels: Array = []
func _ready() -> void:
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	for r in 2:
		for c in 3:
			sprite(BNS + "000/p%02d.tim" % (r * 3 + c), Vector2(c * 128, r * 256)).modulate = Color(0.35, 0.35, 0.4)
	for i in WINDOW + 2:
		var row := TextureRect.new()
		screen.add_child(row)
		labels.append(row)
	_refresh()
func _rows() -> Array:
	var rows: Array = []
	match page:
		"top":
			rows = [["GAME OPTION", ""], ["KEY CONFIGURATION", ""], ["RECORDS", ""], ["EXIT", ""]]
		"game":
			for r in GAME_ROWS:
				rows.append([r[0], r[2][Options.get_value(r[1])]])
			rows.append(["EXIT", ""])
		"records":
			Save._load()
			rows = [["ARCADE CLEARS", str(Save.data["clears"])], ["ENDINGS SEEN", str(Save.data["endings"].size())], ["SURVIVAL BEST", str(Save.data["survival"])], ["UNLOCK ALL", "ON" if Save.data["unlock_all"] else "OFF"]]
			for key in Save.data["time_attack"]:
				var costume := int(key) * 4
				var f: int = Save.data["time_attack"][key]
				rows.append([_name(costume), "%02d'%02d\"%02d" % [f / 3600, f / 60 % 60, (f % 60) * 100 / 60]])
			rows.append(["EXIT", ""])
		"keys":
			for p in 2:
				for name in BUTTON_NAMES:
					var code: int = Options.key_for(p, name, controls().KEYS[p][name])
					rows.append(["P%d %s" % [p + 1, name.to_upper()], "..." if capturing and rows.size() == selected else OS.get_keycode_string(code).to_upper()])
			rows.append(["DEFAULT", ""])
			rows.append(["EXIT", ""])
	return rows
func _name(costume: int) -> String:
	var exe = font.fonts[0]["exe"]
	return exe.cstring(exe.u32(exe.u32(0x80097d40 + costume * 4)))
func _refresh() -> void:
	var rows := _rows()
	var first := clampi(selected - WINDOW / 2, 0, maxi(rows.size() - WINDOW, 0))
	for i in labels.size():
		var node: TextureRect = labels[i]
		var index := first + i
		if i >= WINDOW or index >= rows.size():
			node.texture = null
			continue
		var text: String = rows[index][0] if rows[index][1] == "" else "%s  %s" % [rows[index][0], rows[index][1]]
		var tex: ImageTexture = font.texture(text, 2)
		node.texture = tex
		node.size = tex.get_size()
		node.scale = Vector2(0.8, 0.5)
		node.position = Vector2(184 - tex.get_width() * 0.4, 130 + i * 28)
		node.modulate = Color(1.0, 0.72, 0.25) if index == selected else Color(0.8, 0.25, 0.2)
func _unhandled_input(event: InputEvent) -> void:
	if capturing:
		if event is InputEventKey and event.pressed and not event.echo:
			capturing = false
			if event.keycode != KEY_ESCAPE:
				var player := selected / BUTTON_NAMES.size()
				controls().rebind(player, BUTTON_NAMES[selected % BUTTON_NAMES.size()], event.physical_keycode)
			_refresh()
			get_viewport().set_input_as_handled()
		return
	var rows := _rows()
	if event.is_action_pressed("menu_down"):
		selected = (selected + 1) % rows.size()
		blip(BLIP_CURSOR)
		_refresh()
	elif event.is_action_pressed("menu_up"):
		selected = (selected - 1 + rows.size()) % rows.size()
		blip(BLIP_CURSOR)
		_refresh()
	elif page == "game" and (event.is_action_pressed("menu_left") or event.is_action_pressed("menu_right")) and selected < GAME_ROWS.size():
		var row: Array = GAME_ROWS[selected]
		var step := 1 if event.is_action_pressed("menu_right") else -1
		Options.set_value(row[1], (Options.get_value(row[1]) + step + row[2].size()) % row[2].size())
		blip(BLIP_CURSOR)
		_refresh()
	elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("menu_start"):
		blip(BLIP_CONFIRM)
		_confirm(rows)
	elif event.is_action_pressed("menu_back"):
		_leave()
func _confirm(rows: Array) -> void:
	var label: String = rows[selected][0]
	if label == "EXIT":
		_leave()
	elif label == "GAME OPTION":
		page = "game"
		selected = 0
	elif label == "RECORDS":
		page = "records"
		selected = 0
	elif label == "UNLOCK ALL":
		Save.data["unlock_all"] = not Save.data["unlock_all"]
		Save.save()
	elif label == "KEY CONFIGURATION":
		page = "keys"
		selected = 0
	elif label == "DEFAULT":
		controls().defaults()
	elif page == "keys":
		capturing = true
	elif page == "game" and selected < GAME_ROWS.size():
		var row: Array = GAME_ROWS[selected]
		Options.set_value(row[1], (Options.get_value(row[1]) + 1) % row[2].size())
	_refresh()
func _leave() -> void:
	if page == "top":
		done.emit()
	else:
		page = "top"
		selected = 0
		_refresh()
