extends SubViewportContainer
const Exe := preload("res://scripts/core/exe.gd")
const Fighter := preload("res://scripts/fighter/fighter.gd")
const Stage := preload("res://scripts/fight/stage.gd")
const Match := preload("res://scripts/combat/match.gd")
const BNS := "res://assets/bns/"
var camera := Camera3D.new()
var exe
var fighters: Array = []
var clock := 0.0
var stage_node
var sim
var previous := [0, 0]
var streams := {}
const STREAM_SPAN := 0x6000
const TICK := 1.0 / 60.0
const PAD_BITS := {"up": 0x1000, "right": 0x2000, "down": 0x4000, "left": 0x8000, "lp": 0x80, "rp": 0x10, "lk": 0x40, "rk": 0x20}
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
	env.environment.background_color = Color(0.5, 0.52, 0.58)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	viewport.add_child(env)
	exe = Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
func start(ids: Array, stage_index: int = 0) -> void:
	if stage_node != null:
		stage_node.queue_free()
	stage_node = Stage.new()
	get_child(0).add_child(stage_node)
	stage_node.load_stage(stage_index)
	stage_node.load_floor(stage_index)

	for f in fighters:
		f.queue_free()
	fighters.clear()
	sim = Match.new()
	sim.setup(exe.data, _file(BNS + "279.bin"), _file("%s%03d.bin" % [BNS, ids[0] + 3]), _file("%s%03d.bin" % [BNS, ids[1] + 3]), _file("%s%03d.3dmk" % [BNS, ids[0]]), _file("%s%03d.3dmk" % [BNS, ids[1]]))
	for i in ids.size():
		var f = Fighter.new()
		get_child(0).add_child(f)
		var id: int = ids[i]
		f.setup(exe, _file("%s%03d.3dmk" % [BNS, id]), _file("%s%03d.bin" % [BNS, id + 3]), _file(BNS + "279.bin"), _file("%s%03d/00.tim" % [BNS, id + 2]))
		fighters.append(f)
	clock = 0.0
	_present()
func _file(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)
func _pad(player: int) -> int:
	var bits := 0
	for name in PAD_BITS:
		if Input.is_action_pressed("p%d_%s" % [player + 1, name]):
			bits |= PAD_BITS[name]
	return bits
func _process(delta: float) -> void:
	if sim == null:
		return
	clock += delta
	var stepped := false
	while clock >= TICK:
		clock -= TICK
		for p in 2:
			var bits := _pad(p)
			sim.pads[p] = bits
			sim.edges[p] = bits & ~previous[p] & 0xf0
			previous[p] = bits
		sim.tick()
		stepped = true
	if stepped:
		_present()
func _present() -> void:
	for p in 2:
		var a: int = sim.actor(p)
		var ram = sim.ram
		var f = fighters[p]
		var row: int = ram.u32(a + 0x54)
		var ptr: int = ram.u32(row)
		if not streams.has(ptr):
			streams[ptr] = ram.m.slice(ptr - 0x80000000, ptr - 0x80000000 + STREAM_SPAN)
		f.stream_bytes = streams[ptr]
		f.stream_start = 0
		f.frames = ram.u8(row + 0x18)
		f.set_frame(clampi(ram.s16(a + 0x58) - 1, 0, maxi(f.frames - 1, 0)))
		f.position = Vector3(-ram.s32(a), -ram.s32(a + 4), -ram.s32(a + 8)) * 0.001
		f.rotation.y = ram.u16(a + 0x2c) * TAU / 65536.0 + 3.0 * PI / 2.0
