extends "res://scripts/menu/menu_screen.gd"
signal decided(again: bool)
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const COUNT_FRAMES := 90
var font
var row := TextureRect.new()
var count := 9
var frames := 0
func _ready() -> void:
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	screen.add_child(row)
	_show()
func _show() -> void:
	var tex: ImageTexture = font.texture("CONTINUE? %d" % count, 2)
	row.texture = tex
	row.size = tex.get_size()
	row.scale = Vector2(1, 0.7)
	row.position = Vector2(184 - tex.get_width() / 2.0, 200)
	cue(0x1017 if count == 0 else 0x1004 + count)
func _process(_delta: float) -> void:
	frames += 1
	if frames >= COUNT_FRAMES:
		frames = 0
		count -= 1
		if count < 0:
			decided.emit(false)
			set_process(false)
			return
		_show()
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_start") or event.is_action_pressed("menu_confirm"):
		set_process(false)
		decided.emit(true)
