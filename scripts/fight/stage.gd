extends Node3D
const Tim := preload("res://scripts/fighter/tim.gd")
const SCALE := 0.004
const ATLAS := 2048
const FLAT := Vector2i(-1, -1)
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
				corners.append(Vector3(model.decode_s16(p), -model.decode_s16(p + 2), model.decode_s16(p + 4)) * SCALE)
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
