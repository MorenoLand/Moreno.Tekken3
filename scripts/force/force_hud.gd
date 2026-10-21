extends "res://scripts/menu/menu_screen.gd"
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const Save := preload("res://scripts/core/save.gd")
var BAR_X := [10.0, 326.0]
var BAR_WIDTHS := [155.0, 32.0]
const SEGMENTS := [Color(0.2, 0.4, 0.75), Color(0.3, 0.65, 0.3), Color(0.8, 0.75, 0.2), Color(0.75, 0.2, 0.1)]
var stage_index := 0
const BAR_Y := 42.0
const BAR_HEIGHT := 20.0
var sim
var font
var vram: PackedInt32Array
var fills: Array = []
var losses: Array = []
var name_labels: Array = [TextureRect.new(), TextureRect.new()]
var digits: Array = []
var digit_texture: ImageTexture
var banner := TextureRect.new()
var lines: Array = []
var score_label := TextureRect.new()
var last_score := -1
var last_seconds := -1
var banner_text := ""
var pops: Array = []
var camera: Camera3D
var names_vram: PackedInt32Array
var plates: Array = []
var marker := ColorRect.new()
var score_title := TextureRect.new()
var hi_title := TextureRect.new()
var hi_label := TextureRect.new()
var track_end := 30720
func _ready() -> void:
	get_child(0).queue_free()
	if stage_index >= 4:
		BAR_X[1] = 203.0
		BAR_WIDTHS[1] = 155.0
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	digit_texture = tim_texture(BNS + "010/p03.tim")
	var tims := []
	for n in 90:
		var path := "%sp%02d.tim" % [BNS + "010/", n]
		if FileAccess.file_exists(path):
			tims.append_array(Tim.stream(FileAccess.get_file_as_bytes(path)))
	vram = Tim.compose_absolute(tims)
	var name_tims := tims.duplicate()
	name_tims.append_array(Tim.stream(FileAccess.get_file_as_bytes(BNS + "009/p66.tim")))
	names_vram = Tim.compose_absolute(name_tims)
	for p in 2:
		var loss := _column(0x7ede, p)
		screen.add_child(loss)
		losses.append(loss)
		var fill := _column(0x7edc, p)
		screen.add_child(fill)
		fills.append(fill)
		for cap in [[224, BAR_X[p] - 2], [234, BAR_X[p] + BAR_WIDTHS[p] - 4]]:
			var sprite_cap := TextureRect.new()
			sprite_cap.texture = _piece(Rect2i(cap[0], 168, 6, 24), 0x7ede)
			sprite_cap.position = Vector2(cap[1], BAR_Y)
			sprite_cap.size = Vector2(6, 24)
			screen.add_child(sprite_cap)
		var plate := TextureRect.new()
		plate.texture = _piece(Rect2i(220, 168, 1, 10), 0x7f13 if p == 0 else 0x7f11)
		plate.stretch_mode = TextureRect.STRETCH_SCALE
		screen.add_child(plate)
		plates.append(plate)
		screen.add_child(name_labels[p])
	for i in 2:
		var d := TextureRect.new()
		d.position = Vector2(169 + i * 15, 22)
		d.size = Vector2(16, 46)
		screen.add_child(d)
		digits.append(d)
	screen.add_child(banner)
	screen.add_child(score_label)
	screen.add_child(hi_label)
	for spec in [[score_title, "SCORE", 0x7e17, Vector2(20, 24)], [hi_title, "HI-SCORE", 0x7e13, Vector2(206, 24)]]:
		var tex: ImageTexture = font.render_clut(spec[1], 0, spec[2])
		spec[0].texture = tex
		spec[0].size = tex.get_size()
		spec[0].position = spec[3]
		screen.add_child(spec[0])
	var track := ColorRect.new()
	track.color = Color(0.1, 0.1, 0.12)
	track.position = Vector2(65, 437)
	track.size = Vector2(238, 15)
	screen.add_child(track)
	for i in mini(stage_index, 4):
		var done := ColorRect.new()
		done.color = SEGMENTS[i]
		done.position = Vector2(65 + 60 * i, 437)
		done.size = Vector2(60 if i < 3 else 58, 15)
		screen.add_child(done)
	for x in [123, 183, 243]:
		var divider := ColorRect.new()
		divider.color = Color(0.85, 0.85, 0.85)
		divider.position = Vector2(x, 437)
		divider.size = Vector2(1, 15)
		screen.add_child(divider)
	marker.color = Color(0.3, 0.5, 1.0)
	marker.size = Vector2(6, 12)
	marker.position = Vector2(62, 424)
	screen.add_child(marker)
	for i in 5:
		var row := TextureRect.new()
		screen.add_child(row)
		lines.append(row)
func _piece(region: Rect2i, clut: int) -> ImageTexture:
	return ImageTexture.create_from_image(Tim.decode_region(vram, 0xd, clut, region))
func _column(clut: int, side: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _piece(Rect2i(232, 168, 1, 24), clut)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = Vector2(BAR_WIDTHS[side], BAR_HEIGHT)
	rect.position = Vector2(0, BAR_Y)
	return rect
func _digit(n: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = digit_texture
	atlas.region = Rect2(n * 16, 0, 16, 46)
	return atlas
func set_name_label(slot: int, character: int, text: String = "") -> void:
	if character >= 21:
		var tex: ImageTexture = font.texture(text, 1)
		var plain: TextureRect = name_labels[slot]
		plain.texture = tex
		plain.size = tex.get_size()
		var spot: float = 14.0 if slot == 0 else 354.0 - tex.get_width()
		plain.position = Vector2(spot, 64)
		plates[slot].position = Vector2(spot - 4, 75)
		plates[slot].size = Vector2(tex.get_width() + 8, 10)
		return
	var region := Rect2i(0, character * 16, 128, 16) if character < 16 else Rect2i(129, (character - 16) * 16, 127, 16)
	var image: Image = Tim.decode_region(names_vram, 0xb, 0x7f12, region)
	var left := region.size.x
	var right := 0
	for x in region.size.x:
		for y in 16:
			if image.get_pixel(x, y).a > 0.1:
				left = mini(left, x)
				right = maxi(right, x + 1)
	var width: int = maxi(right - left, 1)
	var label: TextureRect = name_labels[slot]
	label.texture = ImageTexture.create_from_image(image.get_region(Rect2i(left, 0, width, 16)))
	label.size = Vector2(width, 16)
	var at: float = 14.0 if slot == 0 else 354.0 - width
	label.position = Vector2(at, 66)
	plates[slot].position = Vector2(at - 4, 75)
	plates[slot].size = Vector2(width + 8, 10)
func say(text: String, y: float = 112.0) -> void:
	if text == banner_text:
		return
	banner_text = text
	if text == "":
		banner.texture = null
		return
	var tex: ImageTexture = font.texture(text, 2)
	banner.texture = tex
	banner.size = tex.get_size()
	banner.position = Vector2(184 - tex.get_width() / 2.0, y)
func show_lines(texts: Array, clut: int = 0x7e15) -> void:
	for i in lines.size():
		var row: TextureRect = lines[i]
		if i < texts.size() and texts[i] != "":
			var tex: ImageTexture = font.render_clut(texts[i], 0, clut)
			row.texture = tex
			row.size = tex.get_size()
			row.position = Vector2(47, 180 + i * 34)
		else:
			row.texture = null
func _place(rect: TextureRect, side: int, ratio: float) -> void:
	var width: float = BAR_WIDTHS[side]
	var w: float = width * clampf(ratio, 0.0, 1.0)
	rect.size.x = w
	rect.position.x = BAR_X[side] + (width - w if side == 0 else 0.0)
func refresh(target_actor: int) -> void:
	if sim == null or fills.is_empty():
		return
	var p: int = sim.actor(0)
	_place(fills[0], 0, float(sim.ram.u32(p + 0x3f4)) / maxf(float(sim.ram.u32(p + 0x3f8)), 1.0))
	_place(losses[0], 0, 1.0)
	var e := target_actor
	_place(fills[1], 1, float(sim.ram.u32(e + 0x3f4)) / maxf(float(sim.ram.u32(e + 0x3f8)), 1.0))
	_place(losses[1], 1, 1.0)
	marker.position.x = 303.0 if stage_index >= 4 else 62.0 + 60.0 * stage_index + 60.0 * clampf(float(sim.progress()) / track_end, 0.0, 1.0)
	var seconds: int = clampi((sim.time_left + 59) / 60, 0, 99)
	if seconds != last_seconds:
		last_seconds = seconds
		digits[0].texture = _digit(seconds / 10)
		digits[1].texture = _digit(seconds % 10)
	if sim.score != last_score:
		last_score = sim.score
		var tex: ImageTexture = font.render_clut("%08d" % sim.score, 0, 0x7e15)
		score_label.texture = tex
		score_label.size = tex.get_size()
		score_label.position = Vector2(145 - tex.get_width(), 24)
		var best: int = Save.data["force_best"]
		var hi: ImageTexture = font.render_clut("%d" % maxi(best, sim.score), 0, 0x7e15)
		hi_label.texture = hi
		hi_label.size = hi.get_size()
		hi_label.position = Vector2(358 - hi.get_width(), 24)
	for pop in pops.duplicate():
		pop["age"] += 1
		if pop["age"] > 60:
			pop["node"].queue_free()
			pops.erase(pop)
			continue
		if camera != null:
			var at: Vector2 = camera.unproject_position(pop["world"])
			pop["node"].position = Vector2(at.x / size.x * 368.0, at.y / size.y * 480.0 - pop["age"] * 0.5)
func add_popup(text: String, world: Vector3, clut: int) -> void:
	var tex: ImageTexture = font.render_clut(text, 0, clut)
	var node := TextureRect.new()
	node.texture = tex
	node.size = tex.get_size()
	screen.add_child(node)
	pops.append({"node": node, "world": world, "age": 0})
var ready_label := TextureRect.new()
var ready_text := ""
func say_ready(text: String) -> void:
	if text == ready_text:
		return
	ready_text = text
	if ready_label.get_parent() == null:
		screen.add_child(ready_label)
	if text == "":
		ready_label.texture = null
		return
	var tex: ImageTexture = font.texture(text, 2)
	ready_label.texture = tex
	ready_label.size = tex.get_size()
	ready_label.position = Vector2(184 - tex.get_width() / 2.0, 228.0)
