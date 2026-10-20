extends SubViewportContainer
const Exe := preload("res://scripts/core/exe.gd")
const Fighter := preload("res://scripts/fighter/fighter.gd")
const Stage := preload("res://scripts/fight/stage.gd")
const Match := preload("res://scripts/combat/match.gd")
const Hud := preload("res://scripts/fight/hud.gd")
const Sfx := preload("res://scripts/fight/sfx.gd")
const Options := preload("res://scripts/core/options.gd")
const Impact := preload("res://scripts/fight/impact.gd")
const Hits := preload("res://scripts/combat/hits.gd")
const BNS := "res://assets/bns/"
var camera := Camera3D.new()
var exe
var fighters: Array = []
var clock := 0.0
var stage_node
signal finished(winner: int)
signal quit
var sim
var paused := false
var orbit := -1.0
var sfx
var camera_ready := false
var axis := Vector2(1, 0)
var hud
var impact
var pause_box: Control
var pause_items: Array = []
var pause_index := 0
const PAUSE_ITEMS := ["CANCEL", "COMMAND", "RESET"]
var title := ""
var names: Array = []
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
	camera.near = 0.25
	camera.far = 400.0
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
func start(ids: Array, stage_index: int = 0, roster: Array = [0, 1], versus: bool = false, practice: bool = false, options: Dictionary = {}) -> void:
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
	sim.demo = options.get("demo", false)
	sim.ai_level = Options.get_value("difficulty")
	sim.ai_stage = options.get("ai_stage", 0)
	Hits.impacts.clear()
	if impact != null:
		impact.queue_free()
	impact = Impact.new()
	get_child(0).add_child(impact)
	sim.setup(exe.data, _file(BNS + "279.bin"), _file("%s%03d.bin" % [BNS, ids[0] + 3]), _file("%s%03d.bin" % [BNS, ids[1] + 3]), _file("%s%03d.3dmk" % [BNS, ids[0]]), _file("%s%03d.3dmk" % [BNS, ids[1]]), ids)
	for i in ids.size():
		var f = Fighter.new()
		get_child(0).add_child(f)
		var id: int = ids[i]
		f.setup(exe, _file("%s%03d.3dmk" % [BNS, id]), _file("%s%03d.bin" % [BNS, id + 3]), _file(BNS + "279.bin"), _file("%s%03d/00.tim" % [BNS, id + 2]), id)
		fighters.append(f)
	sim.match_over.connect(func(w): finished.emit.call_deferred(w))
	sim.computer = [false, not versus]
	for p in 2:
		sim.ram.w8(sim.actor(p) + 0xc5, 1 if sim.computer[p] else 0)
	if sfx != null:
		sfx.queue_free()
	sfx = Sfx.new()
	add_child(sfx)
	sfx.setup(ids)
	sim.practice = practice
	sim.rounds_to_win = options.get("rounds", Options.rounds_to_win())
	sim.round_time = Options.round_frames()
	sim.timer = sim.round_time
	var fractions: Array = options.get("fractions", [1.0, 1.0])
	for p in 2:
		sim.ram.w32(sim.actor(p) + 0x3f4, int(sim.ram.u32(sim.actor(p) + 0x3f8) * fractions[p]))
	clock = 0.0
	if hud != null:
		hud.queue_free()
	hud = Hud.new()
	add_child(hud)
	names = [_name(ids[0]), _name(ids[1])]
	title = options.get("title", "")
	hud.stage = options.get("stage", 0)
	hud.base = options.get("base", 0)
	hud.bind(sim, roster)
	if options.get("stage", 0) > 0 or options.get("solo", false):
		hud.show_coin()
	if options.get("demo", false):
		hud.start_demo()
		sim.computer = [true, true]
		for p in 2:
			sim.ram.w8(sim.actor(p) + 0xc5, 1)
	_present()
func _file(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)
func _pad(player: int) -> int:
	var bits := 0
	for name in PAD_BITS:
		if Input.is_action_pressed("p%d_%s" % [player + 1, name]):
			bits |= PAD_BITS[name]
	return bits
func _unhandled_input(event: InputEvent) -> void:
	if sim == null or hud == null or hud.demo:
		return
	if event.is_action_pressed("menu_start") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		if paused and event.is_action_pressed("menu_start") == false:
			_set_pause(false)
		else:
			_set_pause(not paused)
		get_viewport().set_input_as_handled()
		return
	if not paused:
		return
	if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
		pause_index = (pause_index + (1 if event.is_action_pressed("menu_down") else PAUSE_ITEMS.size() - 1)) % PAUSE_ITEMS.size()
		_pause_refresh()
	elif event.is_action_pressed("menu_confirm"):
		match pause_index:
			0:
				_set_pause(false)
			2:
				_set_pause(false)
				quit.emit()
	get_viewport().set_input_as_handled()
func _set_pause(on: bool) -> void:
	paused = on
	pause_index = 0
	if pause_box == null:
		_build_pause()
	pause_box.visible = on
	_pause_refresh()
func _build_pause() -> void:
	pause_box = Control.new()
	pause_box.visible = false
	var frame := ColorRect.new()
	frame.color = Color.WHITE
	frame.position = Vector2(144, 97)
	frame.size = Vector2(80, 72)
	pause_box.add_child(frame)
	var fill := ColorRect.new()
	fill.color = Color(0.03, 0.06, 0.3)
	fill.position = Vector2(146, 99)
	fill.size = Vector2(76, 68)
	pause_box.add_child(fill)
	for i in PAUSE_ITEMS.size():
		var row := TextureRect.new()
		row.position = Vector2(152, 105 + i * 20)
		pause_box.add_child(row)
		pause_items.append(row)
	hud.screen.add_child(pause_box)
func _pause_refresh() -> void:
	for i in PAUSE_ITEMS.size():
		var clut := 0x7e12 if i == pause_index else 0x7e16
		var tex: ImageTexture = hud.font.render_clut(PAUSE_ITEMS[i], 0, clut)
		pause_items[i].texture = tex
		pause_items[i].size = tex.get_size()
		pause_items[i].modulate = Color(1, 1, 1, 0.45 if i == 1 else 1.0)
func continue_scene() -> void:
	paused = true
	orbit = 0.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	stage_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fighters[1].visible = false
	hud.say("", 0)
	hud.say("", 1)
	hud.say("", 2)
	hud.continue_labels()
func _orbit(delta: float) -> void:
	orbit += delta * 0.5
	var target: Vector3 = fighters[0].position + Vector3(0, 0.9, 0)
	camera.position = target + Vector3(sin(orbit) * 2.6, 0.5 + 0.6 * sin(orbit * 0.7), -cos(orbit) * 2.6)
	camera.look_at(target)
	stage_node.follow(fighters[0].position)
func _process(delta: float) -> void:
	if hud != null and hud.size != size:
		hud.size = size
	if orbit >= 0.0:
		_orbit(delta)
# One simulation tick per physics frame (60 Hz). The tick and the pose/mesh maths for the next
# picture run on a worker thread while the main thread draws the previous one; the main thread
# only joins, applies the meshes and reads the results. Fighters, stage and camera are
# physics-interpolated, so the picture stays smooth whatever the display refresh rate is.
var job := -1
func _physics_process(_delta: float) -> void:
	if sim == null or orbit >= 0.0:
		return
	_join()
	if paused:
		return
	var bits := [_pad(0), _pad(1)]
	for p in 2:
		sim.pads[p] = bits[p]
		sim.edges[p] = bits[p] & ~previous[p] & 0xf0
		previous[p] = bits[p]
	job = WorkerThreadPool.add_task(_step)
func _step() -> void:
	sim.tick()
	_compute()
func _join() -> void:
	if job == -1:
		return
	WorkerThreadPool.wait_for_task_completion(job)
	job = -1
	_apply()
	_banner()
	_sound()
	_sparks()
func _exit_tree() -> void:
	if job != -1:
		WorkerThreadPool.wait_for_task_completion(job)
		job = -1
func _sparks() -> void:
	for hit in Hits.impacts:
		var victim: int = hit[3]
		var blocked: bool = sim.ram.u8(victim + 0xcf) != 0
		var at := Vector3(hit[0], -hit[1], -hit[2]) * 0.001
		var side: float = 1.0 if fighters[0].position.x < fighters[1].position.x else -1.0
		impact.burst(at, blocked, side)
	Hits.impacts.clear()
func _sound() -> void:
	for event in sim.sounds:
		sfx.play_entry(event[0], event[1])
	sim.sounds.clear()
func _banner() -> void:
	var final: bool = sim.round_number >= sim.rounds_to_win * 2 - 1
	match sim.phase:
		sim.Phase.INTRO:
			var first: bool = sim.round_number == 1
			hud.say(title if title != "" else ("FINAL ROUND" if final else "ROUND %d" % sim.round_number), 0) if sim.phase_frames >= (61 if first else 1) else hud.say("", 0)
			hud.say("READY?" if sim.phase_frames >= (106 if first else 46) else "", 1)
		sim.Phase.FIGHT:
			hud.say("", 0)
			hud.say("", 1)
		sim.Phase.ROUND_OVER:
			var down := [sim.ram.u32(sim.actor(0) + 0x3f4) == 0, sim.ram.u32(sim.actor(1) + 0x3f4) == 0]
			if down[0] and down[1]:
				hud.say("DOUBLE K.O.")
			elif not down[0] and not down[1]:
				hud.say("TIME UP")
			elif sim.fraction(1 if down[0] else 0) >= 1.0:
				hud.say("PERFECT!")
			else:
				hud.say("K.O.")
			hud.say(_result() if sim.phase_frames > 60 else "", 2)
		sim.Phase.MATCH_OVER:
			hud.say("")
		_:
			hud.say("")
func _name(model: int) -> String:
	var file := FileAccess.open("%s%03d.bin" % [BNS, model + 3], FileAccess.READ)
	file.seek(1)
	var costume: int = file.get_8() * 4
	return exe.cstring(exe.u32(exe.u32(0x80097d40 + costume * 4)))
func _result() -> String:
	if sim.practice or (sim.wins[0] < sim.rounds_to_win and sim.wins[1] < sim.rounds_to_win):
		return ""
	if sim.wins[0] == sim.wins[1]:
		return "DRAW"
	var winner: int = 0 if sim.wins[0] > sim.wins[1] else 1
	if sim.computer[1] and not sim.computer[0]:
		return "YOU WIN!" if winner == 0 else "YOU LOSE"
	return "%s WINS!" % names[winner]
func _present() -> void:
	_compute()
	_apply()
func _compute() -> void:
	var tasks := []
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
		tasks.append(WorkerThreadPool.add_task(f.compute_frame.bind(clampi(ram.s16(a + 0x58) - 1, 0, maxi(f.frames - 1, 0)), sim.secondary_locals(p))))
	for task in tasks:
		WorkerThreadPool.wait_for_task_completion(task)
func _apply() -> void:
	var ram = sim.ram
	for p in 2:
		var a: int = sim.actor(p)
		var f = fighters[p]
		f.apply_frame()
		f.position = Vector3(ram.s32(a), -ram.s32(a + 4), -ram.s32(a + 8)) * 0.001
		f.rotation.y = 3.0 * PI / 2.0 - ram.u16(a + 0x2c) * TAU / 65536.0
	_follow()
func _follow() -> void:
	var first: Vector3 = fighters[0].position
	var second: Vector3 = fighters[1].position
	var between := Vector2(second.x - first.x, second.z - first.z)
	var gap := between.length()
	if gap > 0.9 or not camera_ready:
		var turn := 0.0
		if between.x > 0.5:
			turn = clampf(atan2(between.y, between.x), -0.3, 0.3)
		elif between.x < -0.5:
			turn = clampf(atan2(-between.y, -between.x), -0.3, 0.3)
		axis = Vector2(cos(turn), sin(turn))
	var right := axis
	var forward := Vector3(right.y, 0.0, -right.x)
	var mid := (first + second) * 0.5
	var distance := clampf(2.6 + gap * 0.8, 4.4, 6.4)
	stage_node.follow(mid)
	var target := mid + Vector3(0, 0.85 + maxf(mid.y - 0.3, 0.0) * 0.6, 0)
	var wanted := target - forward * distance + Vector3(0, 0.2, 0)
	camera.position = camera.position.lerp(wanted, 0.2) if camera_ready else wanted
	camera_ready = true
	camera.look_at(target)
