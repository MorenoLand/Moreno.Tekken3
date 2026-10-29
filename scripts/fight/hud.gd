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
var coin_label: TextureRect
var labels_hidden := false
var demo := false
var demo_labels: Array = []
var stage := 0
var base := 0
var last_clock := -1
var vram: PackedInt32Array
var lamp_off: ImageTexture
var lamp_on: ImageTexture
var plates: Array = []
var names_texture: ImageTexture
var digit_texture: ImageTexture
func _ready() -> void:
	get_child(0).queue_free()
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	names_texture = tim_texture(BNS + "009/p66.tim")
	digit_texture = tim_texture(BNS + "010/p03.tim")
	var tims := []
	for n in 90:
		var path := "%sp%02d.tim" % [BNS + "010/", n]
		if FileAccess.file_exists(path):
			tims.append_array(Tim.stream(FileAccess.get_file_as_bytes(path)))
	tims.append_array(Tim.stream(FileAccess.get_file_as_bytes(BNS + "009/p66.tim")))
	vram = Tim.compose_absolute(tims)
	lamp_off = _piece(Rect2i(240, 168, 15, 18), 0x7f19)
	lamp_on = _piece(Rect2i(240, 168, 15, 18), 0x7f18)
	var plate_clut := 0x7f11 if demo else 0x7f13
	for p in 2:
		var loss := _column(0x7ede)
		screen.add_child(loss)
		losses.append(loss)
		var fill := _column(0x7edc)
		screen.add_child(fill)
		fills.append(fill)
		for cap in [[224, BAR_X[p] - 2], [234, BAR_X[p] + 148]]:
			var sprite_cap := TextureRect.new()
			sprite_cap.texture = _piece(Rect2i(cap[0], 168, 6, 24), 0x7ede)
			sprite_cap.position = Vector2(cap[1], BAR_Y)
			sprite_cap.size = Vector2(6, 24)
			screen.add_child(sprite_cap)
		var plate := TextureRect.new()
		plate.texture = _piece(Rect2i(220, 168, 1, 10), plate_clut)
		plate.stretch_mode = TextureRect.STRETCH_SCALE
		screen.add_child(plate)
		plates.append(plate)
		var label := TextureRect.new()
		screen.add_child(label)
		labels.append(label)
		var at := [Vector2(137, 70), Vector2(151, 70)] if p == 0 else [Vector2(202, 70), Vector2(216, 70)]
		var pair := []
		for pos in at:
			var lamp := TextureRect.new()
			lamp.texture = lamp_off
			lamp.position = pos
			lamp.size = Vector2(15, 18)
			screen.add_child(lamp)
			pair.append(lamp)
		lamps.append(pair)
	for i in 2:
		var d := TextureRect.new()
		d.position = Vector2(169 + i * 15, 22)
		d.size = Vector2(16, 46)
		screen.add_child(d)
		digits.append(d)
	for banner in banners:
		screen.add_child(banner)
	for label in [stage_label, clock_label]:
		label.position = Vector2(19, 24)
		screen.add_child(label)
	clock_label.position = Vector2(94, 24)
func _piece(region: Rect2i, clut: int) -> ImageTexture:
	return ImageTexture.create_from_image(Tim.decode_region(vram, 0xd, clut, region))
func _column(clut: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _piece(Rect2i(232, 168, 1, 24), clut)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	rect.position = Vector2(0, BAR_Y)
	return rect
# Practice mode draws no health bars, names, lamps or clock (only its banner and attack data lines).
func hide_bars() -> void:
	for child in screen.get_children():
		if not child in banners:
			child.visible = false
func bind(match_sim, roster_indices: Array) -> void:
	sim = match_sim
	roster = roster_indices
	for p in 2:
		var label: TextureRect = labels[p]
		var index: int = roster[p]
		var region := Rect2i(0, index * 16, 128, 16) if index < NAMES_COLUMN else Rect2i(129, (index - NAMES_COLUMN) * 16, 127, 16)
		var image: Image = Tim.decode_region(vram, 0xb, 0x7f12, region)
		var left := region.size.x
		var right := 0
		for x in region.size.x:
			for y in 16:
				if image.get_pixel(x, y).a > 0.1:
					left = mini(left, x)
					right = maxi(right, x + 1)
		var width: int = maxi(right - left, 1)
		label.texture = ImageTexture.create_from_image(image.get_region(Rect2i(left, 0, width, 16)))
		label.size = Vector2(width, 16)
		var at := 14.0 if p == 0 else 354.0 - width
		label.position = Vector2(at, 66)
		plates[p].position = Vector2(at - 4, 75)
		plates[p].size = Vector2(width + 8, 10)
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
func show_coin() -> void:
	var tex: ImageTexture = font.render_clut("INSERT COIN", 0, 0x7e15)
	var label := TextureRect.new()
	label.texture = tex
	label.size = tex.get_size()
	label.position = Vector2(253, 24)
	screen.add_child(label)
	coin_label = label
func continue_labels() -> void:
	labels_hidden = true
	stage_label.visible = false
	clock_label.visible = false
	if coin_label != null:
		coin_label.visible = false
	for spec in [["PUSH P1 START", 0x7e15, 34], ["GAME OVER", 0x7e12, 240]]:
		var tex: ImageTexture = font.render_clut(spec[0], 0, spec[1])
		var label := TextureRect.new()
		label.texture = tex
		label.size = tex.get_size()
		label.position = Vector2(spec[2], 24)
		screen.add_child(label)
func start_demo() -> void:
	demo = true
	for plate in plates:
		plate.texture = _piece(Rect2i(220, 168, 1, 10), 0x7f11)
	for i in 2:
		var tex: ImageTexture = font.render_clut("PUSH P%d START" % (i + 1), 0, 0x7e15)
		var label := TextureRect.new()
		label.texture = tex
		label.size = tex.get_size()
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
	var tex: ImageTexture = font.render_clut("%02d'%02d\"%02d" % [seconds / 60, seconds % 60, (count % 60) * 100 / 60], 0, 0x7e15)
	clock_label.texture = tex
	clock_label.size = tex.get_size()
func _process(_delta: float) -> void:
	if sim == null:
		return
	if stage > 0:
		if stage_label.texture == null:
			var tex: ImageTexture = font.render_clut("STAGE %d" % stage, 0, 0x7e17)
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
		_place(losses[p], p, 1.0)
		for k in 2:
			lamps[p][k].texture = lamp_on if sim.wins[p] > k else lamp_off
func _place(rect: TextureRect, player: int, ratio: float) -> void:
	var w: float = BAR_WIDTH * clampf(ratio, 0.0, 1.0)
	rect.size.x = w
	rect.position.x = BAR_X[player] + (BAR_WIDTH - w if player == 0 else 0.0)
