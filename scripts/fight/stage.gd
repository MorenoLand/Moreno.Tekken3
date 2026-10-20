extends Node3D
const Tim := preload("res://scripts/fighter/tim.gd")
const SCALE := 0.004
const ATLAS := 2048
const FLAT := Vector2i(-1, -1)
const TILE := 64
const CELL := 1.8
const GRID := 10
const CORNERS := [0x0000, 0x003f, 0x3f00, 0x3f3f, 0x3f00, 0x0000, 0x3f3f, 0x003f, 0x3f3f, 0x3f00, 0x003f, 0x0000, 0x003f, 0x3f3f, 0x0000, 0x3f00]
const REACH := 4
var walls: MeshInstance3D
var ground: MeshInstance3D
func load_stage(index: int) -> void:
	var model := FileAccess.get_file_as_bytes("res://assets/bns/%03d.bin" % (56 + index))
	var vram := Tim.compose_absolute(Tim.stream(FileAccess.get_file_as_bytes("res://assets/bns/%03d/00.tim" % (36 + index))))
	var polys := []
	var boxes := {}
	for r in model.decode_u32(8):
		var base := 12 + r * 28
		var vertex_start := 12 + model.decode_u32(base)
		var o := 12 + model.decode_u32(base + 16)
		for k in model.decode_u32(base + 12):
			var code := model[o + 3]
			var flat := code == 0x28
			var size := 8 if flat else 20
			var count := 3 if code == 0x24 else 4
			var corners := []
			for i in count:
				var p := vertex_start + model[o + size - 4 + i] * 8
				corners.append(Vector3(model.decode_s16(p), -model.decode_s16(p + 2), -model.decode_s16(p + 4)) * SCALE)
			var shade := Color(model[o] / 128.0, model[o + 1] / 128.0, model[o + 2] / 128.0)
			if flat:
				polys.append({"key": FLAT, "uv": [0, 0, 0, 0], "pos": corners, "shade": shade})
			else:
				var uv0 := model.decode_u32(o + 4)
				var uv1 := model.decode_u32(o + 8)
				var uv23 := model.decode_u32(o + 12)
				var uvs := [uv0 & 0xFFFF, uv1 & 0xFFFF, uv23 & 0xFFFF, uv23 >> 16]
				var key := Vector2i(uv1 >> 16, uv0 >> 16)
				polys.append({"key": key, "uv": uvs, "pos": corners, "shade": shade})
				var box: Rect2i = boxes.get(key, Rect2i(uvs[0] & 0xFF, uvs[0] >> 8, 1, 1))
				for u in uvs.slice(0, count):
					box = box.expand(Vector2i(u & 0xFF, u >> 8))
				boxes[key] = box
			o += size
	_separate_coplanar(polys)
	var placed := {}
	var atlas := Image.create(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
	atlas.set_pixel(ATLAS - 1, ATLAS - 1, Color.WHITE)
	var x := 0
	var y := 0
	var row := 0
	for key in boxes:
		var box: Rect2i = boxes[key]
		var size := box.size + Vector2i.ONE
		if x + size.x > ATLAS:
			x = 0
			y += row
			row = 0
		var region := Rect2i(box.position, size)
		atlas.blit_rect(Tim.decode_region(vram, key.x, key.y, region), Rect2i(Vector2i.ZERO, size), Vector2i(x, y))
		placed[key] = Vector2i(x, y) - box.position
		x += size.x
		row = maxi(row, size.y)
	var verts := PackedVector3Array()
	var uvs_out := PackedVector2Array()
	var colors := PackedColorArray()
	for poly in polys:
		var flat: bool = poly["key"] == FLAT
		var shift: Vector2i = Vector2i(ATLAS - 1, ATLAS - 1) if flat else placed[poly["key"]]
		for i in ([0, 1, 2, 2, 1, 3] if poly["pos"].size() == 4 else [0, 1, 2]):
			verts.append(poly["pos"][i])
			var u: int = 0 if flat else poly["uv"][i]
			uvs_out.append(((Vector2(shift) if flat else Vector2(u & 0xFF, u >> 8) + Vector2(shift)) + Vector2(0.5, 0.5)) / float(ATLAS))
			colors.append(poly["shade"])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs_out
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(atlas)
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	add_child(node)
	walls = node
# The original draws in list order with no depth buffer, so overlapping coplanar polygons
# (decals, trims) never fight. Here each later one is lifted a hair toward the viewer side.
func _separate_coplanar(polys: Array) -> void:
	var groups := {}
	for poly in polys:
		var c: Array = poly["pos"]
		var n: Vector3 = (c[1] - c[0]).cross(c[2] - c[0])
		if n.length() < 1e-9:
			continue
		n = n.normalized()
		var centre: Vector3 = (c[0] + c[1] + c[2]) / 3.0
		if absf(n.y) > 0.5:
			n = n if n.y > 0.0 else -n
		elif n.dot(-centre) < 0.0:
			n = -n
		poly["normal"] = n
		var key := Vector4i(roundi(n.x * 50.0), roundi(n.y * 50.0), roundi(n.z * 50.0), roundi(n.dot(c[0]) / 0.002))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(poly)
	for key in groups:
		var list: Array = groups[key]
		for i in range(1, list.size()):
			var rank := 0
			for j in i:
				if _boxes_overlap(list[i]["pos"], list[j]["pos"]):
					rank += 1
			if rank > 0:
				for k in list[i]["pos"].size():
					list[i]["pos"][k] += list[i]["normal"] * 0.0004 * rank
func _boxes_overlap(a: Array, b: Array) -> bool:
	var box_a := AABB(a[0], Vector3.ZERO)
	var box_b := AABB(b[0], Vector3.ZERO)
	for v in a:
		box_a = box_a.expand(v)
	for v in b:
		box_b = box_b.expand(v)
	return box_a.grow(0.0005).intersects(box_b.grow(0.0005))
func load_floor(index: int) -> void:
	var table := FileAccess.get_file_as_bytes("res://assets/bns/%03d/01.bin" % (36 + index))
	var vram := Tim.compose_absolute(Tim.stream(FileAccess.get_file_as_bytes("res://assets/bns/%03d/00.tim" % (36 + index))))
	var atlas := Image.create(GRID * TILE, GRID * TILE, false, Image.FORMAT_RGBA8)
	for c in GRID * GRID:
		var w0 := table.decode_u32(4 + c * 8)
		var w1 := table.decode_u32(8 + c * 8)
		atlas.blit_rect(Tim.decode_region(vram, w0 >> 16 & 0x1ff, w1 >> 16, Rect2i(w0 & 0xff, w0 >> 8 & 0xff, TILE, TILE)), Rect2i(0, 0, TILE, TILE), Vector2i(c % GRID * TILE, c / GRID * TILE))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j in range(-REACH, REACH + 1):
		for i in range(-REACH, REACH + 1):
			var c := posmod(i, GRID) + (GRID - 1 - posmod(j, GRID)) * GRID
			var w0 := table.decode_u32(4 + c * 8)
			var set := (w0 >> 30) * 4
			var base: Array = []
			for k in 4:
				base.append(CORNERS[set + k])
			var order: Array = [[0, 1, 2, 3], [1, 0, 3, 2], [2, 3, 0, 1], [3, 2, 1, 0]][w0 >> 25 & 3]
			var origin := Vector2(c % GRID * TILE, c / GRID * TILE)
			var x0 := (i - 0.5) * CELL
			var z0 := -(j - 0.5) * CELL
			var corner := [Vector3(x0, 0, z0), Vector3(x0 + CELL, 0, z0), Vector3(x0, 0, z0 - CELL), Vector3(x0 + CELL, 0, z0 - CELL)]
			for q in [0, 1, 2, 2, 1, 3]:
				var o: int = base[order[q]]
				verts.append(corner[q])
				uvs.append((origin + Vector2(o & 0xff, o >> 8 & 0xff) + Vector2(0.5, 0.5)) / float(GRID * TILE))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(atlas)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	add_child(node)
	ground = node
func follow(mid: Vector3) -> void:
	if walls != null:
		walls.position = Vector3(mid.x, 0.0, mid.z)
	if ground != null:
		ground.position = Vector3(snappedf(mid.x, CELL), -0.004, snappedf(mid.z, CELL))
