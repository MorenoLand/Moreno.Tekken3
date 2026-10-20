extends SubViewportContainer
const Exe := preload("res://scripts/core/exe.gd")
const Fighter := preload("res://scripts/fighter/fighter.gd")
const BNS := "res://assets/bns/"
var camera := Camera3D.new()
var fighter
var exe
var yaw := 0.0
var pitch := -0.15
var distance := 3.0
var center := Vector3(0, 0.6, 0)
var clock := 0.0
var move := SpinBox.new()
var info := Label.new()
func _ready() -> void:
	stretch = true
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
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
	move.min_value = 0
	move.value_changed.connect(_select_move)
	move.position = Vector2(8, 8)
	add_child(move)
	info.position = Vector2(8, 44)
	add_child(info)
	exe = Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
	_update_camera()
func show_model(id: int) -> void:
	if fighter != null:
		fighter.queue_free()
	fighter = Fighter.new()
	get_child(0).add_child(fighter)
	fighter.setup(exe, _file("%s%03d.3dmk" % [BNS, id]), _file("%s%03d.bin" % [BNS, id + 3]), _file(BNS + "279.bin"), _file("%s%03d/00.tim" % [BNS, id + 2]))
	clock = 0.0
	move.max_value = fighter.move_count - 1
	move.value = 0
	_select_move(0)
	var bounds := AABB()
	for mesh in fighter.meshes:
		bounds = bounds.merge(mesh["node"].mesh.get_aabb()) if bounds.size != Vector3.ZERO else mesh["node"].mesh.get_aabb()
	center = bounds.get_center()
	distance = bounds.get_longest_axis_size() * 1.3
	_update_camera()
func _select_move(index: float) -> void:
	if fighter == null:
		return
	fighter.select_move(int(index))
	clock = 0.0
	info.text = "move %d, %d frames" % [int(index), fighter.frames]
func _file(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)
func _process(delta: float) -> void:
	if fighter == null:
		return
	clock += delta * 60.0
	fighter.set_frame(int(clock) % fighter.frames)
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
