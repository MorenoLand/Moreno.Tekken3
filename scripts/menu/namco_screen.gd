extends "res://scripts/menu/menu_screen.gd"
signal finished
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const SHOW_SECONDS := 3.0
var shown := 0.0
func _ready() -> void:
	var font := GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	var first: ImageTexture = font.render_clut("NAMCO ", 0, 0x7e12)
	var second: ImageTexture = font.render_clut("PRESENTS.", 0, 0x7e16)
	var total: float = first.get_width() + second.get_width()
	var left := TextureRect.new()
	left.texture = first
	left.size = first.get_size()
	left.position = Vector2(117, 240)
	screen.add_child(left)
	var right := TextureRect.new()
	right.texture = second
	right.size = second.get_size()
	right.position = Vector2(171, 240)
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
