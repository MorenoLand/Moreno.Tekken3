extends "res://scripts/menu/menu_screen.gd"
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const BAR_X := [12.0, 204.0]
const BAR_WIDTH := 152.0
const BAR_Y := 40.0
const BAR_HEIGHT := 24.0
const FILL := [Color(0.62, 1.0, 1.0), Color(0.12, 0.8, 0.82), Color(0.02, 0.42, 0.45)]
const LOSS := [Color(1.0, 0.55, 0.5), Color(0.85, 0.12, 0.1), Color(0.45, 0.02, 0.02)]
const NAMES_COLUMN := 16
var sim
var font
var roster: Array = []
var fills: Array = []
var losses: Array = []
var shown := [1.0, 1.0]
var trail := [1.0, 1.0]
var digits: Array = []
var lamps: Array = []
var labels: Array = []
var banners: Array = [TextureRect.new(), TextureRect.new(), TextureRect.new()]
var stage_label := TextureRect.new()
var clock_label := TextureRect.new()
var demo := false
var demo_labels: Array = []
var stage := 0
var base := 0
var last_clock := -1
var names_texture: ImageTexture
var digit_texture: ImageTexture
func _ready() -> void:
	get_child(0).queue_free()
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	names_texture = tim_texture(BNS + "009/p66.tim")
	digit_texture = tim_texture(BNS + "010/p03.tim")
	for p in 2:
		var frame := ColorRect.new()
		frame.color = Color(0.04, 0.05, 0.08, 0.85)
		frame.position = Vector2(BAR_X[p] - 2, BAR_Y - 2)
		frame.size = Vector2(BAR_WIDTH + 4, BAR_HEIGHT + 4)
		screen.add_child(frame)
		var loss := _gradient_rect(LOSS)
		screen.add_child(loss)
		losses.append(loss)
		var fill := _gradient_rect(FILL)
		screen.add_child(fill)
		fills.append(fill)
		var label := TextureRect.new()
		screen.add_child(label)
		labels.append(label)
		lamps.append([_lamp(Vector2(137, 70)), _lamp(Vector2(151, 70))] if p == 0 else [_lamp(Vector2(202, 70)), _lamp(Vector2(216, 70))])
	for i in 2:
		var d := TextureRect.new()
		d.position = Vector2(169 + i * 15, 22)
		d.size = Vector2(16, 46)
		screen.add_child(d)
		digits.append(d)
	for banner in banners:
		screen.add_child(banner)
	for label in [stage_label, clock_label]:
		label.scale = Vector2(0.75, 0.55)
		label.position = Vector2(16, 24)
		screen.add_child(label)
	clock_label.position = Vector2(96, 24)
	clock_label.scale = Vector2(0.58, 0.55)
	stage_label.scale = Vector2(0.73, 0.55)
	stage_label.modulate = Color(1.0, 0.5, 0.1)
func _gradient_rect(colors: Array) -> TextureRect:
	var image := Image.create(1, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		image.set_pixel(0, y, colors[0] if y < 4 else (colors[1] if y < 15 else colors[2]))
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	rect.position = Vector2(0, BAR_Y)
	return rect
func _lamp(at: Vector2) -> ColorRect:
	var lamp := ColorRect.new()
	lamp.position = at
	lamp.size = Vector2(12, 14)
	lamp.color = Color(0.25, 0.25, 0.3, 0.8)
	screen.add_child(lamp)
	return lamp
func bind(match_sim, roster_indices: Array) -> void:
	sim = match_sim
	roster = roster_indices
	for p in 2:
		var label: TextureRect = labels[p]
		var index: int = roster[p]
		var atlas := AtlasTexture.new()
		atlas.atlas = names_texture
		atlas.region = Rect2(0, index * 16, 128, 16) if index < NAMES_COLUMN else Rect2(129, (index - NAMES_COLUMN) * 16, 127, 16)
		label.texture = atlas
		label.size = atlas.region.size
		label.position = Vector2(12, 66) if p == 0 else Vector2(356 - atlas.region.size.x, 66)
func _digit(n: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = digit_texture
	atlas.region = Rect2(n * 16, 0, 16, 46)
	return atlas
func say(text: String, slot: int = 1) -> void:
	if demo and slot == 2:
		return
	var label: TextureRect = banners[slot]
	if text == "":
		label.texture = null
		return
	if label.get_meta("text", "") == text:
		return
	label.set_meta("text", text)
	var tex: ImageTexture = font.texture(text, 2)
	label.texture = tex
	label.size = tex.get_size()
	label.position = Vector2(184 - tex.get_width() / 2, [112, 228, 368][slot])
func start_demo() -> void:
	demo = true
	for i in 2:
		var tex: ImageTexture = font.texture("PUSH P%d START" % (i + 1), 0)
		var label := TextureRect.new()
		label.texture = tex
		label.size = tex.get_size()
		label.modulate = Color(1.0, 0.8, 0.1)
		label.position = Vector2(30 if i == 0 else 226, 22)
		screen.add_child(label)
		demo_labels.append(label)
	var over: ImageTexture = font.texture("GAME OVER", 2)
	banners[2].texture = over
	banners[2].size = over.get_size()
	banners[2].modulate = Color(0.9, 0.1, 0.12)
	banners[2].position = Vector2(184 - over.get_width() / 2.0, 270)
func _clock(count: int) -> void:
	if count == last_clock:
		return
	last_clock = count
	var seconds := count / 60
	var tex: ImageTexture = font.texture("%02d'%02d\"%02d" % [seconds / 60, seconds % 60, (count % 60) * 100 / 60], 1)
	clock_label.texture = tex
	clock_label.size = tex.get_size()
func _process(_delta: float) -> void:
	if sim == null:
		return
	if stage > 0:
		if stage_label.texture == null:
			var tex: ImageTexture = font.texture("STAGE %d" % stage, 1)
			stage_label.texture = tex
			stage_label.size = tex.get_size()
		_clock(base + sim.elapsed)
	var seconds: int = clampi((sim.timer + 59) / 60, 0, 99)
	digits[0].texture = _digit(seconds / 10)
	digits[1].texture = _digit(seconds % 10)
	for p in 2:
		var a: int = sim.actor(p)
		var ratio: float = float(sim.ram.u32(a + 0x3f4)) / maxf(float(sim.ram.u32(a + 0x3f8)), 1.0)
		shown[p] = ratio
		trail[p] = maxf(ratio, trail[p] - 0.004)
		_place(fills[p], p, shown[p])
		_place(losses[p], p, trail[p])
		for k in 2:
			lamps[p][k].color = Color(1.0, 0.8, 0.2) if sim.wins[p] > k else Color(0.25, 0.25, 0.3, 0.8)
func _place(rect: TextureRect, player: int, ratio: float) -> void:
	var w: float = BAR_WIDTH * clampf(ratio, 0.0, 1.0)
	rect.size.x = w
	rect.position.x = BAR_X[player] + (BAR_WIDTH - w if player == 0 else 0.0)
