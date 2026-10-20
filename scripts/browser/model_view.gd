extends SubViewportContainer
const SCALE := 0.001
const PER_ROW := 6
var pivot := Node3D.new()
var camera := Camera3D.new()
var yaw := 0.0
var pitch := -0.3
var distance := 8.0
func _ready() -> void:
	stretch = true
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	viewport.add_child(pivot)
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	viewport.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.06, 0.07, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	viewport.add_child(env)
	_update_camera()
func show_model(path: String) -> void:
	for child in pivot.get_children():
		child.queue_free()
	var parts: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.78, 0.85)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sizes: Array[float] = []
	var meshes: Array = []
	for part in parts:
		var mesh := _build_part(part, material)
		if mesh != null:
			meshes.append(mesh)
			sizes.append(mesh.get_aabb().get_longest_axis_size())
	sizes.sort()
	var cell: float = sizes[int(sizes.size() * 0.8)]
	for i in meshes.size():
		var node := MeshInstance3D.new()
		node.mesh = meshes[i]
		var center: Vector3 = meshes[i].get_aabb().get_center()
		node.position = Vector3((i % PER_ROW) * cell * 1.2, -(i / PER_ROW) * cell * 1.2, 0) - center
		pivot.add_child(node)
	distance = cell * PER_ROW * 1.1
	pivot.position = Vector3(-cell * PER_ROW * 0.55, cell * 1.2, 0)
	_update_camera()
func _build_part(part: Dictionary, material: Material) -> ArrayMesh:
	var verts: Array = part["verts"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var added := 0
	for tri in part["tris"]:
		if tri[0] >= verts.size() or tri[1] >= verts.size() or tri[2] >= verts.size():
			continue
		for index in tri:
			var v: Array = verts[index]
			tool.add_vertex(Vector3(v[0], -v[1], v[2]) * SCALE)
		added += 1
	if added == 0:
		return null
	tool.generate_normals()
	tool.set_material(material)
	return tool.commit()
func _update_camera() -> void:
	camera.position = Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at_from_position(camera.position, Vector3.ZERO)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		yaw -= event.relative.x * 0.01
		pitch = clampf(pitch - event.relative.y * 0.01, -1.4, 1.4)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		distance *= 0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 1.0
		_update_camera()
