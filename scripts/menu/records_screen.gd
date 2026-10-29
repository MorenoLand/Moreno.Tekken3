extends "res://scripts/menu/menu_screen.gd"
# Record pages of the attract loop (CHARACTER TIME RECORD, GREATEST SURVIVORS, CHARACTERS). Layout, colours
# and timing are from the original draw lists (30/60 Hz frame dumps): a stage backdrop, a list of ten ranks
# that scrolls down in two steps (ranks 6-10, then 1-5), and a header whose right end is two blended strips.
signal finished
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const Records := preload("res://scripts/core/records.gd")
const Stage := preload("res://scripts/fight/stage.gd")
const FRAME := 1.0 / 60.0
# The loop shows the pages in this order, one per pass, behind stage number (pass mod 15); title image (record 011) and cluts per page.
const TITLES := [0, 1, 2]
const RANK_CLUT := [0x7e58, 0x7e57, 0x7e52]
const VALUE_CLUT := [0x7e59, 0x7e55, 0x7e56]
const NAME_CLUT := 0x7e16
const CODE_CLUT := 0x7e56
const FADE_IN := 32
const SCROLL := 30
const HOLD_FIRST_END := 212
const FADE_OUT_START := 454
const FADE_OUT := 30
const STEP := 12.0
const ROW := 72
# Start angle of the turn per stage in degrees (read for stages 2, 3 and 4; the rest are assumed 0).
const START_ANGLE := [0.0, 0.0, 180.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
const CAMERA_H := 500.0
var page := 0
var stage_index := 0
var font
var vram: PackedInt32Array
var rows: Array = []
var list := Control.new()
var clip := Control.new()
var shade := ColorRect.new()
var clock := 0.0
var frame := 0
var viewport := SubViewport.new()
var camera := Camera3D.new()
var stage := Stage.new()
var rig := Node3D.new()
# The stage follows a counter of record pages shown; the attract loop also takes the page from it, a finished mode picks its own.
func _init(pass_index: int = 0, which: int = -1) -> void:
	page = pass_index % 3 if which < 0 else which
	stage_index = pass_index % 15
func _ready() -> void:
	var exe := Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
	font = GameFont.new(exe, BNS + "010/")
	var tims := []
	for n in 90:
		var path := "%s010/p%02d.tim" % [BNS, n]
		if FileAccess.file_exists(path):
			tims.append_array(Tim.stream(FileAccess.get_file_as_bytes(path)))
	tims.append_array(Tim.stream(FileAccess.get_file_as_bytes("%s011/p%02d.tim" % [BNS, TITLES[page]])))
	vram = Tim.compose_absolute(tims)
	font.vram = vram
	_backdrop()
	# The list is drawn in its own clip area (y 96..455); the backdrop in y 20..467.
	clip.position = Vector2(0, 96)
	clip.size = Vector2(368, 360)
	clip.clip_contents = true
	screen.add_child(clip)
	clip.add_child(list)
	_rows(exe)
	_header()
	shade.color = Color.BLACK
	shade.size = Vector2(368, 480)
	screen.add_child(shade)
	_tick()
func _backdrop() -> void:
	var frame_clip := Control.new()
	frame_clip.position = Vector2(0, 20)
	frame_clip.size = Vector2(368, 447)
	frame_clip.clip_contents = true
	screen.add_child(frame_clip)
	var container := SubViewportContainer.new()
	container.size = Vector2(368, 480)
	container.position = Vector2(0, -20)
	container.modulate = Color(1.0, 1.0, 1.0)
	container.stretch = true
	frame_clip.add_child(container)
	viewport.size = Vector2i(368, 480)
	viewport.own_world_3d = true
	container.add_child(viewport)
	stage.load_stage(stage_index)
	stage.load_floor(stage_index)
	viewport.add_child(rig)
	rig.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.05, 0.08)
	viewport.add_child(env)
	# The projection centre of the dumped polygons is at (190, 237.3) in the 368 x 480 picture (fitted: stage vertices land within a pixel).
	camera.near = 0.05
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_frustum(2.0 * camera.near * 240.0 / CAMERA_H, Vector2(-6.0 / CAMERA_H * camera.near, 2.7 / CAMERA_H * camera.near), camera.near, 100.0)
	viewport.add_child(camera)
	camera.current = true
	_camera(0)
# The backdrop is the stage turned about its own vertical axis (3 / 4096 of a turn per frame from a start angle that
# depends on the page), stretched 1.667 vertically and seen with H = 500: values read from the GTE of the original.
func _camera(f: int) -> void:
	var angle := deg_to_rad(START_ANGLE[stage_index] + 0.4) + TAU * 3.0 / 4096.0 * f
	var basis := Basis(Vector3.UP, angle) * Basis.from_scale(Vector3(1.0, 6826.0 / 4096.0, 1.0))
	rig.transform = Transform3D(basis, Vector3(0.0, -351.0 * Stage.SCALE, -624.0 * Stage.SCALE))
func _rows(exe) -> void:
	var table := _table()
	for i in table.size():
		var rank := i + 1
		var row := Control.new()
		row.position = Vector2(0, 112 + ROW * (rank - 6))
		list.add_child(row)
		var c: int = table[i]["character"]
		_text(row, _rank_label(rank), 1, RANK_CLUT[page], Vector2(12, 22))
		_icon(row, c)
		_text(row, _name(exe, c), 0, NAME_CLUT, Vector2(111, 0))
		row.add_child(_box(Rect2(70, 48, 298, 2), Color8(0x90, 0x90, 0x90)))
		row.add_child(_box(Rect2(8, 42, 62, 8), Color8(0x90, 0x90, 0x90)))
		_value(row, c, table[i]["value"])
		rows.append(row)
func _table() -> Array:
	match page:
		0:
			return Records.times()
		1:
			return Records.survivors()
	return Records.usage()
func _value(row: Control, c: int, value: int) -> void:
	if page == 2:
		var digits := str(value)
		_text(row, digits, 1, VALUE_CLUT[2], Vector2(309 - 13 * (digits.length() - 1), 22))
		_text(row, "%", 0, NAME_CLUT, Vector2(325, 26))
		return
	_text(row, Records.CODES[c], 1, CODE_CLUT, Vector2(299, 22))
	if page == 0:
		var parts := Records.clock(value)
		_text(row, "%02d" % parts[0], 1, VALUE_CLUT[0], Vector2(158, 22))
		_text(row, "'", 1, VALUE_CLUT[0], Vector2(182, 18))
		_text(row, "%02d" % parts[1], 1, VALUE_CLUT[0], Vector2(191, 22))
		_text(row, "\"", 1, VALUE_CLUT[0], Vector2(217, 18))
		_text(row, "%02d" % parts[2], 1, VALUE_CLUT[0], Vector2(227, 22))
	else:
		var word := "WIN" if value == 1 else "WINS"
		var x_word := 256 - 13 * word.length()
		var digits := str(value)
		_text(row, digits, 1, VALUE_CLUT[1], Vector2(x_word - 20 - 13 * (digits.length() - 1), 22))
		_text(row, word, 1, VALUE_CLUT[1], Vector2(x_word, 22))
func _rank_label(rank: int) -> String:
	var suffix := "TH"
	if rank == 1:
		suffix = "ST"
	elif rank == 2:
		suffix = "ND"
	elif rank == 3:
		suffix = "RD"
	return "%d%s" % [rank, suffix]
func _name(exe, character: int) -> String:
	var roster := Records.roster_of(character)
	return exe.cstring(exe.u32(exe.u32(0x80097d40 + roster * 16)))
func _text(parent: Control, text: String, which: int, clut: int, at: Vector2) -> void:
	var texture: ImageTexture = font.render_clut(text, which, clut)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.size = texture.get_size()
	rect.position = at
	parent.add_child(rect)
func _icon(row: Control, character: int) -> void:
	var region := Rect2i(128 + 32 * (character % 4), 24 + 58 * (character / 4), 32, 58)
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(Tim.decode_region(vram, 0x28e, 0x7810 + 0x40 * character, region))
	rect.size = Vector2(32, 58)
	rect.position = Vector2(76, -2)
	row.add_child(rect)
func _box(area: Rect2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = area.position
	rect.size = area.size
	rect.color = color
	return rect
# The right end of the title bar is a strip of the title image drawn twice, subtracted and then added, with a
# brightness that falls off to the right; the title text itself is three opaque sprites.
func _header() -> void:
	_strip(Rect2(256, 36, 112, 48), Rect2i(0, 96, 112, 48), 0x60, 0x10)
	_strip(Rect2(240, 36, 16, 48), Rect2i(112, 48, 16, 48), 0x80, 0x60)
	_sprite(Rect2(128, 52, 112, 32), Rect2i(0, 64, 112, 32))
	_sprite(Rect2(128, 36, 112, 16), Rect2i(0, 48, 112, 16))
	_sprite(Rect2(0, 36, 128, 48), Rect2i(0, 0, 128, 48))
func _sprite(area: Rect2, region: Rect2i) -> void:
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(Tim.decode_region(vram, 0x286, 0x7f50, region))
	rect.position = area.position
	rect.size = area.size
	screen.add_child(rect)
func _strip(area: Rect2, region: Rect2i, left: int, right: int) -> void:
	for pass_index in 2:
		var subtract: bool = pass_index == 0
		var image := Tim.decode_region(vram, 0x286, 0x7fd0 if subtract else 0x7f50, region)
		var poly := Polygon2D.new()
		poly.texture = ImageTexture.create_from_image(image)
		poly.polygon = PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
		poly.uv = PackedVector2Array([Vector2(0, 0), Vector2(region.size.x, 0), Vector2(region.size), Vector2(0, region.size.y)])
		var a := left / 128.0
		var b := right / 128.0
		poly.vertex_colors = PackedColorArray([Color(a, a, a), Color(b, b, b), Color(b, b, b), Color(a, a, a)])
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB if subtract else CanvasItemMaterial.BLEND_MODE_ADD
		poly.material = material
		screen.add_child(poly)
func _process(delta: float) -> void:
	clock += delta
	while clock >= FRAME:
		clock -= FRAME
		frame += 1
		_tick()
func _tick() -> void:
	var offset := 360.0
	var dark := 0.0
	if frame < FADE_IN:
		dark = 1.0 - frame * 8.0 / 255.0
		offset = -360.0
	elif frame <= FADE_IN + SCROLL:
		offset = -360.0 + STEP * (frame - FADE_IN)
	elif frame <= HOLD_FIRST_END:
		offset = 0.0
	elif frame <= HOLD_FIRST_END + SCROLL:
		offset = STEP * (frame - HOLD_FIRST_END)
	elif frame >= FADE_OUT_START:
		dark = (7.0 + 8.0 * (frame - FADE_OUT_START)) / 255.0
		if frame >= FADE_OUT_START + FADE_OUT:
			finished.emit()
			set_process(false)
	list.position.y = offset - 96.0
	shade.color = Color(0, 0, 0, clampf(dark, 0.0, 1.0))
	_camera(frame)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_start") or event.is_action_pressed("menu_confirm"):
		finished.emit()
		set_process(false)
