extends "res://scripts/menu/menu_screen.gd"
signal chosen(first: int, second: int)
const GRID := [[7, 4, 5, 1, 6, 8, 0, 3, 2, 9], [19, 12, 11, 13, 14, 17, 10, 16, 15, 18]]
const ICONS := [[16, 13, 14, 10, 15, 17, 9, 12, 11, 18], [28, 21, 20, 22, 23, 26, 19, 25, 24, 27]]
const NAMES_COLUMN := 16
var cursor := [Vector2i(0, 0), Vector2i(0, 0)]
var locked := [false, false]
var portrait_nodes: Array = []
var name_nodes: Array = []
var frames: Array = []
var names_texture: ImageTexture
func _ready() -> void:
	for y in 5:
		for x in range(-6, 14):
			sprite(BNS + "009/p43.tim", Vector2(x * 48, y * 64)).modulate = Color(0.55, 0.55, 0.6)
	for x in range(-2, 4):
		sprite(BNS + "009/p%d.tim" % (40 + x % 2), Vector2(x * 184, 288))
	var floor_fill := ColorRect.new()
	floor_fill.color = Color(0.1, 0.09, 0.11)
	floor_fill.position = Vector2(-400, 322)
	floor_fill.size = Vector2(1200, 200)
	screen.add_child(floor_fill)
	for p in 2:
		var portrait := TextureRect.new()
		portrait.position = Vector2(33 + p * 175, 30)
		portrait.size = Vector2(126, 252)
		screen.add_child(portrait)
		portrait_nodes.append(portrait)
		var tint := ColorRect.new()
		tint.color = Color(0.45, 0.1, 0.28) if p == 0 else Color(0.18, 0.18, 0.22)
		tint.position = portrait.position
		tint.size = portrait.size
		tint.material = CanvasItemMaterial.new()
		tint.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		screen.add_child(tint)
		sprite(BNS + "009/p%d.tim" % (30 + p), Vector2(24 + p * 175, 286))
		var label := TextureRect.new()
		label.position = Vector2(40 + p * 175, 290)
		screen.add_child(label)
		name_nodes.append(label)
	names_texture = tim_texture(BNS + "009/p66.tim")
	for p in 2:
		frames.append(sprite(BNS + "009/p%d.tim" % (52 + p), Vector2.ZERO))
	for r in 2:
		for c in 10:
			sprite(BNS + "010/p%02d.tim" % ICONS[r][c], Vector2(11 + 35 * c, 336 + 62 * r))
	_refresh()
func _name_rect(index: int) -> Rect2:
	return Rect2(0, index * 16, 128, 16) if index < NAMES_COLUMN else Rect2(129, (index - NAMES_COLUMN) * 16, 127, 16)
func _refresh() -> void:
	for p in 2:
		var roster: int = GRID[cursor[p].y][cursor[p].x]
		portrait_nodes[p].texture = tim_texture(BNS + "009/p%02d.tim" % roster, 1.5)
		var atlas := AtlasTexture.new()
		atlas.atlas = names_texture
		atlas.region = _name_rect(roster)
		name_nodes[p].texture = atlas
		name_nodes[p].size = atlas.get_size()
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
