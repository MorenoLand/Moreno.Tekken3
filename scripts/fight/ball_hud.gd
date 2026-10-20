extends RefCounted
# Ball damage gauges at the bottom of the fight screen (overlay FUN_800b49a8): 76 px wide, caps at both ends, the trail shrinks behind the fill.
const WIDTH := 0x4c
const POSITIONS := [Vector2(10, 434), Vector2(278, 434)]
const MIRRORED := [true, false]
var hud
var fills: Array = []
var trails: Array = []
var empties: Array = []
var stored := [0, 0]
var width := [0, 0]
var mid := [0, 0]
var trail := [0, 0]
func setup(hud_node) -> void:
	hud = hud_node
	for side in 2:
		var origin: Vector2 = POSITIONS[side]
		for cap in [[0xe0, origin.x - 6.0], [0xea, origin.x + WIDTH]]:
			var rect := TextureRect.new()
			rect.texture = hud._piece(Rect2i(cap[0], 0xa8, 6, 24), 0x7ede)
			rect.position = Vector2(cap[1], origin.y)
			rect.size = Vector2(6, 24)
			hud.screen.add_child(rect)
		for kind in [[0x7e1d + side, fills], [0x7edc, trails], [0x7edf, empties]]:
			var column: TextureRect = hud._column(kind[0])
			column.size = Vector2(0, 24)
			column.position = Vector2(origin.x, origin.y)
			hud.screen.add_child(column)
			kind[1].append(column)
func update(first: int, second: int) -> void:
	var gauges := [first, second]
	for side in 2:
		var gauge: int = gauges[side]
		var target: int = width[side]
		if stored[side] != gauge:
			stored[side] = gauge
			target = gauge * WIDTH / 100
		target = mini(target, WIDTH)
		var grown: int = target if (target <= mid[side] or target < mid[side] + 3) else mid[side] + 3
		var tail: int = mid[side]
		if mid[side] < trail[side]:
			tail = trail[side] - ((trail[side] - mid[side]) + 0xf >> 4)
		var gap: int = tail - grown
		if tail < grown:
			gap = 0
			tail = grown
		width[side] = target
		mid[side] = grown
		trail[side] = tail
		var origin: Vector2 = POSITIONS[side]
		var parts := [grown, gap, WIDTH - tail]
		var at: float = origin.x + (WIDTH if MIRRORED[side] else 0.0)
		for i in 3:
			var rect: TextureRect = [fills, trails, empties][i][side]
			rect.size.x = parts[i]
			if MIRRORED[side]:
				at -= parts[i]
				rect.position.x = at
			else:
				rect.position.x = at
				at += parts[i]
