extends "res://scripts/menu/vs_screen.gd"
const NAMES := ["BACKSTREETS", "BADLANDS", "DARKNESS", "MISHIMA", "UNDERGROUND FORTRESS"]
const CLUTS := [0x7e90, 0x7e94, 0x7e95, 0x7e91, 0x7e99]
var place := ""
func _ready() -> void:
	var exe := Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
	var font := GameFont.new(exe, BNS + "010/")
	var tims := []
	for n in 42:
		tims.append_array(Tim.stream(FileAccess.get_file_as_bytes("%s012/p%02d.tim" % [BNS, n])))
	_tiles(Tim.compose_absolute(tims))
	screen.add_child(_gradient(Vector2(106, 36), Vector2(110, 36), _header_color(), _header_clear(), _header_color(), _header_clear(), false))
	var bar := ColorRect.new()
	bar.color = _header_color()
	bar.position = Vector2(0, 36)
	bar.size = Vector2(106, 36)
	screen.add_child(bar)
	_place(font.render_clut("TEKKEN FORCE", 1, 0x7e56), Vector2(28, 42))
	_place(font.render_clut("STAGE %d" % stage if stage < 5 else "FINAL STAGE", 1, 0x7e56), Vector2(32, 90))
	var title: ImageTexture = font.render_clut(place, 2, CLUTS[clampi(stage - 1, 0, 4)])
	_place(title, Vector2(184 - title.get_width() / 2.0, 140))
	_panel(0, exe)
	movers[0][0].position.y = 108
	_name(0, exe, font)
	movers[1][0].position.y = 392 - NAME_Y[0]
