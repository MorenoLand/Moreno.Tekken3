extends SubViewportContainer
const SCALE := 0.001
var pivot := Node3D.new()
var camera := Camera3D.new()
var yaw := 0.0
var pitch := -0.15
var distance := 6.0
var center := Vector3.ZERO
func _ready() -> void:
	stretch = true
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	viewport.add_child(pivot)
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 30, 0)
	viewport.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.06, 0.07, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.65, 0.65, 0.7)
	viewport.add_child(env)
	_update_camera()
func show_model(folder: String) -> void:
	for child in pivot.get_children():
		child.queue_free()
	var parts: Array = JSON.parse_string(FileAccess.get_file_as_string(folder + "/model.json"))
	var textures := {}
	var bounds := AABB()
	var first := true
	for part in parts:
		var mesh := _build_part(part, folder, textures)
		if mesh == null:
			continue
		var node := MeshInstance3D.new()
		node.mesh = mesh
		pivot.add_child(node)
		bounds = mesh.get_aabb() if first else bounds.merge(mesh.get_aabb())
		first = false
	center = bounds.get_center()
	distance = bounds.get_longest_axis_size() * 1.6
	_update_camera()
func _material(folder: String, tex: int, textures: Dictionary) -> StandardMaterial3D:
	if not textures.has(tex):
		var material := StandardMaterial3D.new()
		var image := Image.new()
		image.load_png_from_buffer(FileAccess.get_file_as_bytes("%s/surface_%02d.png" % [folder, tex]))
		material.albedo_texture = ImageTexture.create_from_image(image)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		textures[tex] = material
	return textures[tex]
func _build_part(part: Dictionary, folder: String, textures: Dictionary) -> ArrayMesh:
	var verts: Array = part["verts"]
	var mesh := ArrayMesh.new()
	for surface in part["surfaces"]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var idx: Array = surface["idx"]
		var uv: Array = surface["uv"]
		for i in idx.size():
			var v: Array = verts[idx[i]]
			tool.set_uv(Vector2(uv[i * 2], uv[i * 2 + 1]) / 256.0)
			tool.add_vertex(Vector3(v[0], -v[1], v[2]) * SCALE)
		tool.generate_normals()
		tool.set_material(_material(folder, surface["tex"], textures))
		tool.commit(mesh)
	return mesh if mesh.get_surface_count() > 0 else null
func _update_camera() -> void:
	camera.position = center + Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at_from_position(camera.position, center)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		yaw -= event.relative.x * 0.01
		pitch = clampf(pitch - event.relative.y * 0.01, -1.4, 1.4)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		distance *= 0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 1.0
		_update_camera()
