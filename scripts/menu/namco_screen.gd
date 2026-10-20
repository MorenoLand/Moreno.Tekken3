extends "res://scripts/menu/menu_screen.gd"
signal finished
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const SHOW_SECONDS := 3.0
var shown := 0.0
func _ready() -> void:
	var font := GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	var first: ImageTexture = font.texture("NAMCO ", 0)
	var second: ImageTexture = font.texture("PRESENTS.", 0)
	var total: float = first.get_width() + second.get_width()
	var left := TextureRect.new()
	left.texture = first
	left.size = first.get_size()
	left.modulate = Color(1.0, 0.1, 0.1)
	left.position = Vector2(184 - total / 2.0, 232)
	screen.add_child(left)
	var right := TextureRect.new()
	right.texture = second
	right.size = second.get_size()
	right.position = Vector2(184 - total / 2.0 + first.get_width(), 232)
	screen.add_child(right)
func _process(delta: float) -> void:
	shown += delta
	if shown > SHOW_SECONDS:
		set_process(false)
		finished.emit()
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_start") or event.is_action_pressed("menu_confirm"):
		set_process(false)
		finished.emit()
