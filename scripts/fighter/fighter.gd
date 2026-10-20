extends Node3D
const Motion := preload("res://scripts/fighter/motion.gd")
const Skeleton := preload("res://scripts/fighter/skeleton.gd")
const Tim := preload("res://scripts/fighter/tim.gd")
const SCALE := 0.001
var model: PackedByteArray
var rows: Array = []
var motion
var skeleton
var character: PackedByteArray
var common: PackedByteArray
var stream_bytes: PackedByteArray
var stream_start := 0
var frames := 1
var move_count := 0
var meshes: Array = []
var materials := {}
var tables: Array = []
var root_matrix: Array = Skeleton.FACING
func setup(exe, model_bytes: PackedByteArray, character_bytes: PackedByteArray, common_bytes: PackedByteArray, tim_bytes: PackedByteArray) -> void:
	character = character_bytes
	common = common_bytes
	model = model_bytes
	motion = Motion.new(exe)
	skeleton = Skeleton.new(exe)
	var count := model.decode_u32(0)
	for r in count:
		var row := []
		for w in 14:
			row.append(model.decode_u32(24 + r * 56 + w * 4))
		rows.append(row)
	move_count = character.decode_u16(2)
	select_move(0)
	var vram := Tim.compose_vram(Tim.stream(tim_bytes))
	_collect_meshes(vram)
	tables = [_blank_table(), _blank_table()]
	for i in 2:
		set_frame(0)
func select_move(index: int) -> void:
	var ptr := character.decode_u32(character.decode_u32(8) + index * 56)
	stream_bytes = common if ptr >= 0x40000000 else character
	ptr = ptr - 0x40000000 if ptr >= 0x40000000 else ptr
	stream_start = stream_bytes.decode_u32(0x1C) + ptr
	frames = stream_bytes[stream_start]
func _blank_table() -> Array:
	var t := []
	t.resize(256)
	t.fill(Vector3i.ZERO)
	return t
func _u32(o: int) -> int:
	return model.decode_u32(o)
func _poly_indices(quad: bool, v: int) -> Array:
	var out := [(v & 0x1FC) >> 2, (v >> 7 & 0x1FC) >> 2, (v >> 14 & 0x1FC) >> 2]
	if quad:
		out.append((v >> 23 & 0x1FC) >> 2)
	return out
func _read_polys(poly_row: Array) -> Dictionary:
	var o: int = poly_row[1]
	var lists := []
	for words in [2, 2, 2, 3]:
		var count := _u32(o)
		o += 4
		var recs := []
		for i in count:
			recs.append(_u32(o))
			o += 4 * words
		lists.append(recs)
	var c: int = poly_row[2]
	var pool6 := c + model.decode_u16(c)
	var p := pool6 + model.decode_u16(pool6)
	var surfaces := {}
	var names := [false, true, false, true]
	for li in 4:
		var count2 := model[p]
		p += 1
		var quad: bool = names[li]
		var stride := 5 if quad else 4
		for i in count2:
			var cp := model.decode_u16(c + 2 * (model[p] + 1))
			var key := [cp >> 8, cp & 0xFF]
			var uvs := []
			for k in stride - 1:
				var uvw := model.decode_u16(pool6 + 2 * (model[p + 1 + k] + 1))
				uvs.append(Vector2(uvw & 0xFF, uvw >> 8) / 256.0)
			var v := _poly_indices(quad, lists[li][i])
			var order := [0, 1, 2, 2, 1, 3] if quad else [0, 1, 2]
			if not surfaces.has(key):
				surfaces[key] = {"idx": PackedInt32Array(), "uv": PackedVector2Array()}
			for k in order:
				surfaces[key]["idx"].append(v[k])
				surfaces[key]["uv"].append(uvs[k])
			p += stride
	return surfaces
func _bytes_list(o: Array) -> Array:
	var n := _u32(o[0])
	o[0] += 4
	var out := []
	var buf := 0
	while out.size() < n:
		if buf == 0:
			buf = _u32(o[0])
			o[0] += 4
		out.append(buf & 0xFF)
		buf >>= 8
	return out
func _nine_list(o: Array) -> Array:
	var n := _u32(o[0])
	o[0] += 4
	var out := []
	var buf := 0
	while out.size() < n:
		if buf == 0:
			buf = _u32(o[0])
			o[0] += 4
		out.append([buf & 0xFF, buf >> 8 & 1])
		buf >>= 9
	return out
func _two_list(o: Array) -> Array:
	var n := _u32(o[0])
	o[0] += 4
	var out := []
	var buf := 0
	while out.size() < n:
		if buf == 0:
			buf = _u32(o[0])
			o[0] += 4
		out.append(buf & 3)
		buf >>= 2
	return out
func _read_stream(start: int) -> Dictionary:
	var o := [start + 4]
	var s := {"slot": _u32(start)}
	s["copy"] = [_bytes_list(o), _bytes_list(o)]
	var n := _u32(o[0])
	o[0] += 4
	var raw := []
	for i in n:
		raw.append(Vector3i(model.decode_s16(o[0] + i * 8), model.decode_s16(o[0] + i * 8 + 2), model.decode_s16(o[0] + i * 8 + 4)))
	o[0] += 8 * n
	s["raw"] = raw
	s["sum"] = _nine_list(o)
	s["pair_a"] = [_nine_list(o), _nine_list(o)]
	s["pair_b"] = [_nine_list(o), _nine_list(o)]
	s["half"] = _two_list(o)
	return s
func _collect_meshes(vram: PackedInt32Array) -> void:
	for part in 18:
		var r: int = Skeleton.PART_ROWS[part]
		if r != 0 and rows[r][1] != 0 and rows[r - 1][12] != 0:
			meshes.append(_new_mesh(part, r - 1, r, vram))
		if part in Skeleton.SECOND_MESH and rows[r + 1][1] != 0 and rows[r][12] != 0:
			meshes.append(_new_mesh(part, r, r + 1, vram))
func _new_mesh(part: int, stream_row: int, poly_row: int, vram: PackedInt32Array) -> Dictionary:
	var surfaces := _read_polys(rows[poly_row])
	var node := MeshInstance3D.new()
	add_child(node)
	var list := []
	for key in surfaces:
		if not materials.has(key):
			var m := StandardMaterial3D.new()
			m.albedo_texture = ImageTexture.create_from_image(Tim.decode_page(vram, key[0], key[1]))
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			materials[key] = m
		list.append({"key": key, "idx": surfaces[key]["idx"], "uv": surfaces[key]["uv"]})
	return {"part": part, "stream": _read_stream(rows[stream_row][12]), "surfaces": list, "node": node}
func _half(v: Vector3i) -> Vector3i:
	return Vector3i(v.x >> 1, v.y >> 1, v.z >> 1)
func _transform(pose: Array, v: Vector3i) -> Vector3i:
	var r: Array = pose[0]
	var t: Array = pose[1]
	return Vector3i((r[0] * v.x + r[1] * v.y + r[2] * v.z >> 12) + t[0], (r[3] * v.x + r[4] * v.y + r[5] * v.z >> 12) + t[1], (r[6] * v.x + r[7] * v.y + r[8] * v.z >> 12) + t[2])
func _run(mesh: Dictionary, pose: Array) -> Array:
	var t0: Array = tables[0]
	var t1: Array = tables[1]
	var s: Dictionary = mesh["stream"]
	var pos := 0
	for byte in s["copy"][0]:
		t0[pos] = t0[byte / 2 - 1]
		pos += 1
	for byte in s["copy"][1]:
		t0[pos] = t1[byte / 2]
		pos += 1
	for raw in s["raw"]:
		t0[pos] = _transform(pose, raw)
		pos += 1
	var d: int = s["slot"] / 2 - 1
	for e in s["sum"]:
		var i: int = e[0] / 2
		t0[d] = (_half(t0[d]) if e[1] else t0[d]) + t1[i]
		t1[i] = t0[d]
		d += 1
	for k in 2:
		for e in s["pair_a"][k]:
			var i2: int = e[0] / 2
			t0[d] = (t1[i2] if k == 0 else t0[i2 - 1]) + (_half(t0[d]) if e[1] else t0[d])
			d += 1
	for k in 2:
		for e in s["pair_b"][k]:
			var i3: int = e[0] / 2
			var val: Vector3i = _half(t0[d]) if e[1] else t0[d]
			t0[d] = val
			if k == 0:
				t1[i3] = val
			else:
				t0[i3 - 1] = val
			d += 1
	for e in s["half"]:
		if e != 1:
			t0[d] = _half(t0[d])
		d += 1
	return t0.slice(0, pos)
func set_frame(frame_index: int) -> void:
	var pose: PackedInt32Array = motion.frame(stream_bytes, stream_start, frame_index)
	var world: Dictionary = skeleton.world(model, pose, root_matrix, [0, 0, 0])
	for mesh in meshes:
		var slot: int = Skeleton.PART_SLOTS[mesh["part"]]
		var verts := _run(mesh, world[slot])
		var node: MeshInstance3D = mesh["node"]
		var am := ArrayMesh.new()
		for surf in mesh["surfaces"]:
			var idx: PackedInt32Array = surf["idx"]
			var vs := PackedVector3Array()
			var ns := PackedVector3Array()
			for i in idx.size():
				var v: Vector3i = verts[idx[i]]
				vs.append(Vector3(v.x, -v.y, v.z) * SCALE)
			for t in idx.size() / 3:
				var n := (vs[t * 3 + 1] - vs[t * 3]).cross(vs[t * 3 + 2] - vs[t * 3]).normalized()
				ns.append_array([n, n, n])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vs
			arrays[Mesh.ARRAY_NORMAL] = ns
			arrays[Mesh.ARRAY_TEX_UV] = surf["uv"]
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			am.surface_set_material(am.get_surface_count() - 1, materials[surf["key"]])
		node.mesh = am
