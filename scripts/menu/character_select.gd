extends "res://scripts/menu/menu_screen.gd"
signal chosen(first: int, second: int)
const Layout := preload("res://scripts/menu/select_layout.gd")
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const Save := preload("res://scripts/core/save.gd")
const GRID := [[7, 4, 5, 1, 6, 8, 0, 3, 2, 9], [19, 12, 11, 13, 14, 17, 10, 16, 15, 18]]
const ICONS := [[16, 13, 14, 10, 15, 17, 9, 12, 11, 18], [28, 21, 20, 22, 23, 26, 19, 25, 24, 27]]
const NAMES_COLUMN := 16
const SELECT_SECONDS := 20
const PORTRAIT_POSITION := [Vector2(33, 14), Vector2(209, 14)]
const NAME_CENTER := [97, 273]
const SILHOUETTE := 21
var solo := false
var cursor := [Vector2i(0, 0), Vector2i(0, 0)]
var locked := [false, false]
var vram: PackedInt32Array
var font
var portraits: Array = []
var names: Array = []
var cursors: Array = []
var digits: Array = []
var shown := [-1, -1]
var fade := [1.0, 1.0]
var countdown := float(SELECT_SECONDS)
var coin := TextureRect.new()
var elapsed := 0.0
# The original redraws this screen at 30 Hz: the steel background scrolls up 8 px per frame (8 tiles, 512 px
# period) and thin light streaks rise 16 px per frame, fading out, while the 1P tags pulse.
const FRAME := 1.0 / 30.0
const TILE_PAGE := 536
const SCROLL_PER_FRAME := 8.0
const STREAK_PER_FRAME := 16.0
var tile_rows := {}
var strips: Array = []
var scroll := 0.0
var streak_layer: Control
var streaks: Array = []
var streak_clock := 0.0
var frame_clock := 0.0
var tags: Array = []
func _ready() -> void:
	var tims := []
	for spec in [["000", 7], ["009", 70], ["010", 110]]:
		for n in spec[1]:
			if spec[0] == "009" and n < 22:
				continue
			var path := "%s%s/p%02d.tim" % [BNS, spec[0], n]
			if FileAccess.file_exists(path):
				tims.append_array(Tim.stream(FileAccess.get_file_as_bytes(path)))
	vram = Tim.compose_absolute(tims)
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	for entry in Layout.ORDER:
		if not (entry is String) and not (entry[0] is String) and entry[0] == TILE_PAGE:
			tile_rows[entry[1]] = tile_rows.get(entry[1], {})
			tile_rows[entry[1]][entry[2]] = entry
	var built := false
	var streaked := false
	for entry in Layout.ORDER:
		if entry is String:
			_dynamic(entry)
		elif entry[0] is String:
			if entry[0] == "poly" and entry[4] - entry[2] == 1 and entry[5] - entry[3] == 160:
				if not streaked:
					streaked = true
					streak_layer = Control.new()
					screen.add_child(streak_layer)
				continue
			_static_shape(entry)
		elif entry[0] == TILE_PAGE:
			if not built:
				built = true
				_build_scroll()
		else:
			_piece(entry[0], Vector2(entry[1], entry[2]), Vector2(entry[3], entry[4]), Vector2i(entry[5], entry[6]), entry[7])
	for p in 2:
		_fit_name(p, GRID[cursor[p].y][cursor[p].x])
	_refresh()
func _build_scroll() -> void:
	var clip := Control.new()
	clip.position = Vector2(0, 20)
	clip.size = Vector2(368, 440)
	clip.clip_contents = true
	screen.add_child(clip)
	for x in tile_rows:
		var rows: Dictionary = tile_rows[x]
		var width: int = rows[76][3]
		var top: Array = rows[20]
		var sequence := [
			[top[5] - 48 if x != 0 else top[5] - 48, 64, 31974],
			[top[5], 64, top[7]],
			[top[5], 64, top[7]],
			[rows[76][5], rows[76][6], rows[76][7]],
			[rows[140][5], rows[140][6], rows[140][7]],
			[rows[204][5], rows[204][6], rows[204][7]],
			[rows[268][5], rows[268][6], rows[268][7]],
			[rows[332][5], rows[332][6], rows[332][7]]]
		var image := Image.create(width, 64 * 8 * 3, false, Image.FORMAT_RGBA8)
		for rep in 3:
			for i in 8:
				var tile: Array = sequence[i]
				image.blit_rect(Tim.decode_region(vram, TILE_PAGE, tile[2], Rect2i(tile[0], tile[1], width, 64)), Rect2i(0, 0, width, 64), Vector2i(0, (rep * 8 + i) * 64))
		var strip := TextureRect.new()
		strip.texture = ImageTexture.create_from_image(image)
		strip.size = Vector2(width, image.get_height())
		strip.position = Vector2(x, -136)
		clip.add_child(strip)
		strips.append(strip)
func _step_frame() -> void:
	scroll = fmod(scroll + SCROLL_PER_FRAME, 512.0)
	for strip in strips:
		strip.position.y = -136.0 - scroll
	for line in streaks.duplicate():
		line["y"] -= STREAK_PER_FRAME
		var level: float = 0.375 * line["y"] - 18.0
		if level <= 1.0:
			line["node"].queue_free()
			streaks.erase(line)
		else:
			line["node"].position.y = line["y"]
			line["node"].modulate = Color(level / 128.0, level / 128.0, level / 128.0, 1.0)
	streak_clock += 1.0
	if streak_clock >= 4.0 and streak_layer != null:
		streak_clock = 0.0
		var node := TextureRect.new()
		node.texture = _streak_texture()
		node.size = Vector2(1, 160)
		node.position = Vector2(40 + randi() % 290, 288)
		node.material = CanvasItemMaterial.new()
		node.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		node.modulate = Color(90.0 / 128.0, 90.0 / 128.0, 90.0 / 128.0, 1.0)
		streak_layer.add_child(node)
		streaks.append({"node": node, "y": 288.0})
func _streak_texture() -> ImageTexture:
	if not cache.has("streak"):
		var image := Image.create(1, 160, false, Image.FORMAT_RGBA8)
		for y in 160:
			image.set_pixel(0, y, Color(1.0, 1.0 - y / 159.0, 1.0 - y / 159.0, 1.0))
		cache["streak"] = ImageTexture.create_from_image(image)
	return cache["streak"]
func _texture(tpage: int, clut: int, region: Rect2i) -> ImageTexture:
	var key := Vector4i(tpage, clut, region.position.x * 256 + region.position.y, region.size.x * 256 + region.size.y)
	if not cache.has(key):
		cache[key] = ImageTexture.create_from_image(Tim.decode_region(vram, tpage, clut, region))
	return cache[key]
func _piece(tpage: int, at: Vector2, size: Vector2, uv: Vector2i, clut: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _texture(tpage, clut, Rect2i(uv, Vector2i(size)))
	rect.position = at
	rect.size = size
	screen.add_child(rect)
	return rect
func _channels(c: int) -> Color:
	return Color((c & 255) / 255.0, (c >> 8 & 255) / 255.0, (c >> 16 & 255) / 255.0, 1.0)
func _static_shape(entry: Array) -> void:
	if entry[0] == "fill":
		var block := ColorRect.new()
		block.position = Vector2(entry[1], entry[2])
		block.size = Vector2(entry[3], entry[4])
		block.color = _channels(entry[5])
		screen.add_child(block)
		return
	var width: int = maxi(entry[4] - entry[2], 1)
	var height: int = maxi(entry[5] - entry[3], 1)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var corner := [_channels(entry[6]), _channels(entry[7]), _channels(entry[8]), _channels(entry[9])]
	for y in height:
		var ty: float = y / maxf(height - 1.0, 1.0)
		for x in width:
			var tx: float = x / maxf(width - 1.0, 1.0)
			image.set_pixel(x, y, corner[0].lerp(corner[1], tx).lerp(corner[2].lerp(corner[3], tx), ty))
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.position = Vector2(entry[2], entry[3])
	rect.size = Vector2(width, height)
	if entry[1] == 1:
		rect.material = CanvasItemMaterial.new()
		rect.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	screen.add_child(rect)
func _dynamic(kind: String) -> void:
	match kind:
		"text":
			var tex: ImageTexture = font.render_clut("INSERT COIN", 0, 0x7e1a)
			coin.texture = tex
			coin.size = tex.get_size()
			coin.position = Vector2(222, 34)
			screen.add_child(coin)
		"icons":
			for r in 2:
				for c in 10:
					var icon := sprite(BNS + "010/p%02d.tim" % ICONS[r][c], Vector2(11 + 35 * c, 336 + 62 * r))
					if not Save.unlocked(GRID[r][c]):
						icon.modulate = Color(0.08, 0.08, 0.1)
		"digits":
			for i in 2:
				var d := TextureRect.new()
				d.position = Vector2(169 + i * 15, 200)
				d.size = Vector2(16, 46)
				screen.add_child(d)
				digits.append(d)
		"name1":
			for p in 2:
				var label := TextureRect.new()
				screen.add_child(label)
				names.append(label)
		"portrait1":
			for p in 2:
				var portrait := TextureRect.new()
				portrait.position = PORTRAIT_POSITION[p]
				portrait.size = Vector2(126, 252)
				screen.add_child(portrait)
				portraits.append(portrait)
		"cursor1":
			for p in 2:
				var holder := Control.new()
				for half in [[9, 120], [27, 138]]:
					var piece := TextureRect.new()
					piece.texture = _texture(0x219, 0x7ca0 + p, Rect2i(half[1], 128, 18, 62))
					piece.position = Vector2(half[0] - 9, 6)
					piece.size = Vector2(18, 62)
					holder.add_child(piece)
				var tag := TextureRect.new()
				tag.texture = _texture(0x20e, 0x7f1e + p, Rect2i(216, 0, 20, 16))
				tag.size = Vector2(20, 16)
				holder.add_child(tag)
				tags.append(tag)
				screen.add_child(holder)
				cursors.append(holder)
func _portrait_image(roster: int, silhouette: bool, mirrored: bool) -> ImageTexture:
	var key := Vector3i(roster, 99, (1 if silhouette else 0) + (2 if mirrored else 0))
	if not cache.has(key):
		Tim.semi_alpha = 1.0
		var image := Tim.to_image(FileAccess.get_file_as_bytes(BNS + "009/p%02d.tim" % roster), 4)
		Tim.semi_alpha = 1.0
		for y in image.get_height():
			var shade := 1.0
			var cover := 1.0
			if silhouette and y < 30:
				cover = y / 30.0
			elif y > 206:
				shade = lerpf(1.0, 0.06, (y - 206) / 46.0)
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				image.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade, c.a * cover))
		if mirrored:
			image.flip_x()
		cache[key] = ImageTexture.create_from_image(image)
	return cache[key]
func _fit_name(p: int, roster: int) -> void:
	var region := Rect2i(0, roster * 16, 128, 16) if roster < NAMES_COLUMN else Rect2i(129, (roster - NAMES_COLUMN) * 16, 127, 16)
	var image: Image = Tim.decode_region(vram, 0xb, 0x7ca5, region)
	var left := region.size.x
	var right := 0
	for x in region.size.x:
		for y in 16:
			if image.get_pixel(x, y).a > 0.1:
				left = mini(left, x)
				right = maxi(right, x + 1)
	var width: int = maxi(right - left, 1)
	names[p].texture = ImageTexture.create_from_image(image.get_region(Rect2i(left, 0, width, 16)))
	names[p].size = Vector2(width, 16)
	names[p].position = Vector2(NAME_CENTER[p] - width / 2, 288)
func _refresh() -> void:
	for p in 2:
		var roster: int = GRID[cursor[p].y][cursor[p].x]
		if shown[p] != roster:
			shown[p] = roster
			fade[p] = 0.0
			portraits[p].texture = _portrait_image(SILHOUETTE if solo and p == 1 else roster, solo and p == 1, p == 0)
			if solo and p == 1 and portraits[p].material == null:
				portraits[p].material = CanvasItemMaterial.new()
				portraits[p].material.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
			if not (solo and p == 1):
				_fit_name(p, roster)
		cursors[p].position = Vector2(9 + 35 * cursor[p].x, 328 + 62 * cursor[p].y)
		cursors[p].visible = not (solo and p == 1)
		names[p].visible = not (solo and p == 1)
func _process(delta: float) -> void:
	elapsed += delta
	frame_clock += delta
	while frame_clock >= FRAME:
		frame_clock -= FRAME
		_step_frame()
	for tag in tags:
		tag.modulate = Color.WHITE * lerpf(0.3, 1.0, absf(fmod(elapsed, 1.0) * 2.0 - 1.0))
	for p in 2:
		fade[p] = minf(fade[p] + delta * 5.0, 1.0)
		portraits[p].modulate = Color(1, 1, 1, fade[p])
	if not (locked[0] and (locked[1] or solo)):
		countdown = maxf(countdown - delta, 0.0)
		var seconds := ceili(countdown)
		for i in 2:
			var n: int = seconds / 10 if i == 0 else seconds % 10
			digits[i].texture = _texture(0xe, 0x7ca7, Rect2i(n * 16, 208, 16, 46))
		if countdown <= 0.0:
			for p in 2:
				locked[p] = true
			_finish()
	coin.visible = solo and fmod(elapsed, 2.0) < 1.5
func _finish() -> void:
	chosen.emit(GRID[cursor[0].y][cursor[0].x], GRID[cursor[1].y][cursor[1].x])
func _unhandled_input(event: InputEvent) -> void:
	for p in 2:
		if locked[p] or (solo and p == 1):
			continue
		var step := Vector2i.ZERO
		for d in [["left", Vector2i.LEFT], ["right", Vector2i.RIGHT], ["up", Vector2i.UP], ["down", Vector2i.DOWN]]:
			if event.is_action_pressed("p%d_%s" % [p + 1, d[0]]):
				step = d[1]
		if step != Vector2i.ZERO:
			cursor[p] = Vector2i((cursor[p].x + step.x + 10) % 10, (cursor[p].y + step.y + 2) % 2)
			blip(BLIP_CURSOR)
			_refresh()
		var pressed: bool = event.is_action_pressed("p%d_lk" % (p + 1)) or event.is_action_pressed("p%d_start" % (p + 1)) or (p == 0 and event.is_action_pressed("menu_confirm"))
		if pressed and Save.unlocked(GRID[cursor[p].y][cursor[p].x]):
			locked[p] = true
			blip(BLIP_CONFIRM)
	if locked[0] and (locked[1] or solo):
		_finish()
