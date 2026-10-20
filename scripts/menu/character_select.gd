extends Control
signal chosen(first: int, second: int)
const Tim := preload("res://scripts/fighter/tim.gd")
const BNS := "res://assets/bns/"
const GRID := [[7, 4, 5, 1, 6, 8, 0, 3, 2, 9], [19, 12, 11, 13, 14, 17, 10, 16, 15, 18]]
const ICONS := [[16, 13, 14, 10, 15, 17, 9, 12, 11, 18], [28, 21, 20, 22, 23, 26, 19, 25, 24, 27]]
const NAMES_COLUMN := 16
var screen := Control.new()
var cursor := [Vector2i(0, 0), Vector2i(0, 0)]
var locked := [false, false]
var portraits: Array = []
var portrait_nodes: Array = []
var plate_nodes: Array = []
var frames: Array = []
var names_texture: ImageTexture
var cache := {}
func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(368, 480)
	viewport.disable_3d = true
	add_child(viewport)
	viewport.add_child(screen)
	var ratio := AspectRatioContainer.new()
	ratio.ratio = 4.0 / 3.0
	ratio.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ratio)
	var view := TextureRect.new()
	view.texture = viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ratio.add_child(view)
	_build()
	_refresh()
func _tim(path: String) -> ImageTexture:
	if not cache.has(path):
		cache[path] = ImageTexture.create_from_image(Tim.to_image(FileAccess.get_file_as_bytes(path)))
	return cache[path]
func _sprite(path: String, pos: Vector2, parent: Node = null) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _tim(path)
	rect.position = pos
	rect.size = rect.texture.get_size()
	rect.stretch_mode = TextureRect.STRETCH_KEEP
	(parent if parent != null else screen).add_child(rect)
	return rect
func _build() -> void:
	var back := ColorRect.new()
	back.color = Color(0.1, 0.09, 0.11)
	back.size = Vector2(368, 480)
	screen.add_child(back)
	for y in 5:
		for x in 8:
			var tile := _sprite(BNS + "009/p43.tim", Vector2(x * 48, y * 64))
			tile.modulate = Color(0.55, 0.55, 0.6)
	_sprite(BNS + "009/p40.tim", Vector2(0, 288))
	_sprite(BNS + "009/p41.tim", Vector2(184, 288))
	for p in 2:
		var tint := ColorRect.new()
		tint.color = Color(0.85, 0.2, 0.4, 0.35) if p == 0 else Color(0.5, 0.5, 0.55, 0.3)
		tint.position = Vector2(33 + p * 175, 30)
		tint.size = Vector2(126, 252)
		screen.add_child(tint)
		var portrait := TextureRect.new()
		portrait.position = Vector2(33 + p * 175, 30)
		portrait.size = Vector2(126, 252)
		screen.add_child(portrait)
		portrait_nodes.append(portrait)
		plate_nodes.append(_sprite(BNS + "009/p%d.tim" % (30 + p), Vector2(24 + p * 175, 286)))
		var name_label := TextureRect.new()
		name_label.position = Vector2(40 + p * 175, 290)
		screen.add_child(name_label)
		plate_nodes.append(name_label)
	var names := _tim(BNS + "009/p66.tim")
	names_texture = names
	for p in 2:
		frames.append(_sprite(BNS + "009/p%d.tim" % (52 + p), Vector2.ZERO))
	for r in 2:
		for c in 10:
			_sprite(BNS + "010/p%02d.tim" % ICONS[r][c], Vector2(11 + 35 * c, 336 + 62 * r))
func _name_rect(index: int) -> Rect2:
	return Rect2(0, index * 16, 128, 16) if index < NAMES_COLUMN else Rect2(129, (index - NAMES_COLUMN) * 16, 127, 16)
func _refresh() -> void:
	for p in 2:
		var roster: int = GRID[cursor[p].y][cursor[p].x]
		portrait_nodes[p].texture = _tim(BNS + "009/p%02d.tim" % roster)
		var label: TextureRect = plate_nodes[p * 2 + 1]
		var atlas := AtlasTexture.new()
		atlas.atlas = names_texture
		atlas.region = _name_rect(roster)
		label.texture = atlas
		label.size = atlas.get_size()
		frames[p].position = Vector2(9 + 35 * cursor[p].x, 327 + 62 * cursor[p].y)
func _unhandled_input(event: InputEvent) -> void:
	for p in 2:
		if locked[p]:
			continue
		var step := Vector2i.ZERO
		for d in [["left", Vector2i.LEFT], ["right", Vector2i.RIGHT], ["up", Vector2i.UP], ["down", Vector2i.DOWN]]:
			if event.is_action_pressed("p%d_%s" % [p + 1, d[0]]):
				step = d[1]
		if step != Vector2i.ZERO:
			cursor[p] = Vector2i((cursor[p].x + step.x + 10) % 10, (cursor[p].y + step.y + 2) % 2)
			_refresh()
		if event.is_action_pressed("p%d_lk" % (p + 1)):
			locked[p] = true
	if locked[0] and locked[1]:
		chosen.emit(GRID[cursor[0].y][cursor[0].x], GRID[cursor[1].y][cursor[1].x])
