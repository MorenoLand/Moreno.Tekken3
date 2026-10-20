extends "res://scripts/menu/menu_screen.gd"
signal decided(again: bool)
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const COUNT_FRAMES := 90
var font
var view
var row := TextureRect.new()
var lose := TextureRect.new()
var count := 9
var frames := 0
func _ready() -> void:
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	if view != null:
		backdrop.visible = false
	screen.add_child(row)
	_show()
func _show() -> void:
	var tex: ImageTexture = font.render_clut("CONTINUE? %d" % count, 2, 0x7e99)
	row.texture = tex
	row.size = tex.get_size()
	row.position = Vector2(185 - tex.get_width() / 2.0, 200)
	if lose.texture == null:
		var text: ImageTexture = font.render_clut("YOU LOSE", 2, 0x7e95)
		lose.texture = text
		lose.size = text.get_size()
		lose.position = Vector2(185 - text.get_width() / 2.0, 368)
		screen.add_child(lose)
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
