extends SubViewportContainer
const Exe := preload("res://scripts/core/exe.gd")
const Fighter := preload("res://scripts/fighter/fighter.gd")
const BNS := "res://assets/bns/"
var camera := Camera3D.new()
var exe
var fighters: Array = []
var clock := 0.0
func _ready() -> void:
	stretch = true
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	viewport.add_child(camera)
	camera.position = Vector3(0, 0.9, -4.2)
	camera.look_at_from_position(camera.position, Vector3(0, 0.8, 0))
	camera.fov = 45
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 25, 0)
	viewport.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.5, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	viewport.add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.32, 0.28)
	floor_mesh.material_override = mat
	viewport.add_child(floor_mesh)
	exe = Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
func start(ids: Array) -> void:
	for f in fighters:
		f.queue_free()
	fighters.clear()
	for i in ids.size():
		var f = Fighter.new()
		get_child(0).add_child(f)
		var id: int = ids[i]
		f.setup(exe, _file("%s%03d.3dmk" % [BNS, id]), _file("%s%03d.bin" % [BNS, id + 3]), _file(BNS + "279.bin"), _file("%s%03d/00.tim" % [BNS, id + 2]))
		var bottom := 0.0
		for mesh in f.meshes:
			bottom = minf(bottom, mesh["node"].mesh.get_aabb().position.y)
		f.position = Vector3(-0.9 if i == 0 else 0.9, -bottom, 0)
		f.rotation.y = 0.0 if i == 0 else PI
		fighters.append(f)
	clock = 0.0
func _file(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)
func _process(delta: float) -> void:
	clock += delta * 60.0
	for f in fighters:
		f.set_frame(int(clock) % f.frames)
