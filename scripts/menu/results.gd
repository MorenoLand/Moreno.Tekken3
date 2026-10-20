extends "res://scripts/menu/menu_screen.gd"
signal done
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
var lines: Array = []
func show_lines(text: Array) -> void:
	lines = text
func _ready() -> void:
	var font := GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	for i in lines.size():
		var tex: ImageTexture = font.texture(lines[i], 2)
		var row := TextureRect.new()
		row.texture = tex
		row.size = tex.get_size()
		row.scale = Vector2(1, 0.7)
		row.position = Vector2(184 - tex.get_width() / 2.0, 120 + i * 34)
		screen.add_child(row)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_confirm") or event.is_action_pressed("menu_start"):
		blip(BLIP_CONFIRM)
		done.emit()
