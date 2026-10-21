extends SubViewportContainer
const Exe := preload("res://scripts/core/exe.gd")
const Fighter := preload("res://scripts/fighter/fighter.gd")
const Tim := preload("res://scripts/fighter/tim.gd")
const Sim := preload("res://scripts/force/force_sim.gd")
const Hud := preload("res://scripts/force/force_hud.gd")
const Sfx := preload("res://scripts/fight/sfx.gd")
const Impact := preload("res://scripts/fight/impact.gd")
const Hits := preload("res://scripts/combat/hits.gd")
const BNS := "res://assets/bns/"
const TICK := 1.0 / 60.0
const STREAM_SPAN := 0x6000
const PAD_BITS := {"up": 0x1000, "right": 0x2000, "down": 0x4000, "left": 0x8000, "lp": 0x80, "rp": 0x10, "lk": 0x40, "rk": 0x20}
signal stage_result(result: Dictionary)
signal game_over
signal quit
signal music(song: int)
var camera := Camera3D.new()
var exe
var sim
var viewport: SubViewport
var fighters: Array = [null, null, null]
var floor_node: MeshInstance3D
var hud
var sfx
var impact
var clock := 0.0
var paused := false
var previous := 0
var streams := {}
var intro := 0
var stage_index := 0
var pano_rows := 5
var intro_lines: Array = []
var forced := -1
var shown_names := ["", ""]
func _ready() -> void:
	if viewport != null:
		return
	stretch = true
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	viewport.add_child(camera)
	camera.fov = 51.3
	camera.near = 0.25
	camera.far = 400.0
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 25, 0)
	viewport.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.05, 0.08)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	viewport.add_child(env)
	exe = Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
func start(player_model: int, stage: int, time: int, score: int, keys: int) -> void:
	if viewport == null:
		_ready()
	stage_index = stage
	sim = Sim.new()
	sim.setup_force(exe.data, FileAccess.get_file_as_bytes(BNS + "279.bin"), player_model, stage, time, score, keys)
	sim.enemy_changed.connect(_enemy_changed)
	sim.boss_started.connect(_boss_started)
	sim.stage_done.connect(func(r): stage_result.emit(r))
	sim.game_over.connect(func(): game_over.emit())
	sim.popup.connect(func(text, world, kind): hud.add_popup(text, world, 0x7e15 if kind == "bonus" else 0x7e12))
	Hits.impacts.clear()
	impact = Impact.new()
	viewport.add_child(impact)
	_build_floor(stage)
	fighters[0] = _make_fighter(player_model, FileAccess.get_file_as_bytes("%s%03d.bin" % [BNS, player_model + 3]))
	_enemy_changed(0, sim.model_id_for_costume(Sim.Data.FIRST_ENEMY_COSTUME))
	_enemy_changed(1, sim.model_id_for_costume(Sim.Data.FIRST_ENEMY_COSTUME))
	if sim.final:
		_boss_started(sim.model_id_for_costume(Sim.FINAL_BOSS * 4), Sim.FINAL_BOSS)
	sfx = Sfx.new()
	add_child(sfx)
	sfx.setup([player_model, sim.model_id_for_costume(Sim.Data.FIRST_ENEMY_COSTUME), sim.model_id_for_costume(Sim.Data.FIRST_ENEMY_COSTUME)])
	hud = Hud.new()
	hud.sim = sim
	hud.camera = camera
	if not sim.script_entries.is_empty():
		hud.track_end = maxi(int(sim.script_entries.back()["at"]), 1)
	add_child(hud)
	intro = 0
	_present()
func _tim_bytes(model_id: int) -> PackedByteArray:
	var folder := "%s%03d/" % [BNS, model_id + 2]
	if FileAccess.file_exists(folder + "00.tim"):
		return FileAccess.get_file_as_bytes(folder + "00.tim")
	var archive := FileAccess.get_file_as_bytes(folder + "00.bin")
	var out := PackedByteArray()
	for i in archive.decode_u32(0):
		var o := archive.decode_u32(4 + i * 8)
		out.append_array(archive.slice(o, o + archive.decode_u32(8 + i * 8)))
	out.append_array(FileAccess.get_file_as_bytes(folder + "01.tim"))
	return out
func _make_fighter(model_id: int, character: PackedByteArray) -> Node3D:
	var f = Fighter.new()
	viewport.add_child(f)
	f.setup(exe, FileAccess.get_file_as_bytes("%s%03d.3dmk" % [BNS, model_id]), character, FileAccess.get_file_as_bytes(BNS + "279.bin"), _tim_bytes(model_id), model_id)
	return f
func _enemy_changed(slot: int, model_id: int) -> void:
	if fighters[slot + 1] != null:
		fighters[slot + 1].queue_free()
	fighters[slot + 1] = _make_fighter(model_id, FileAccess.get_file_as_bytes("%s%03d.bin" % [BNS, Sim.SOLDIER_DATA]))
	if sfx != null:
		sfx.models[slot + 1] = model_id
func _boss_started(model_id: int, _character: int) -> void:
	music.emit(sim.boss_song)
	streams.clear()
	if fighters[1] != null:
		fighters[1].queue_free()
	fighters[1] = _make_fighter(model_id, FileAccess.get_file_as_bytes("%s%03d.bin" % [BNS, model_id + 3]))
	if sfx != null:
		sfx.models[1] = model_id
const CORNERS := [0x0000, 0x003f, 0x3f00, 0x3f3f, 0x3f00, 0x0000, 0x3f3f, 0x003f, 0x3f3f, 0x3f00, 0x003f, 0x0000, 0x003f, 0x3f3f, 0x0000, 0x3f00]
const CELL := 1.8
const GRID := 10
const PIXEL := 0.2
const SCREEN_DISTANCE := 100.0
var pano_material: StandardMaterial3D
var pano_pixels := 1024
func _build_ground(stage: int) -> void:
	var table := FileAccess.get_file_as_bytes(sim.data.record(stage) + "01.bin")
	var vram := Tim.compose_absolute(sim.data.tile_images(stage))
	var atlas := Image.create(GRID * 64, GRID * 64, false, Image.FORMAT_RGBA8)
	for c in GRID * GRID:
		var w0 := table.decode_u32(4 + c * 8)
		var w1 := table.decode_u32(8 + c * 8)
		atlas.blit_rect(Tim.decode_region(vram, w0 >> 16 & 0x1ff, w1 >> 16, Rect2i(w0 & 0xff, w0 >> 8 & 0xff, 64, 64)), Rect2i(0, 0, 64, 64), Vector2i(c % GRID * 64, c / GRID * 64))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j in range(-4, 2):
		for i in range(-6, 7):
			var c := posmod(i, GRID) + (GRID - 1 - posmod(j, GRID)) * GRID
			var w0 := table.decode_u32(4 + c * 8)
			var base: Array = []
			for k in 4:
				base.append(CORNERS[(w0 >> 30) * 4 + k])
			var order: Array = [[0, 1, 2, 3], [1, 0, 3, 2], [2, 3, 0, 1], [3, 2, 1, 0]][w0 >> 25 & 3]
			var origin := Vector2(c % GRID * 64, c / GRID * 64)
			var x0 := (i - 0.5) * CELL
			var z0 := -(j - 0.5) * CELL
			var corner := [Vector3(x0, 0, z0), Vector3(x0 + CELL, 0, z0), Vector3(x0, 0, z0 - CELL), Vector3(x0 + CELL, 0, z0 - CELL)]
			for q in [0, 1, 2, 2, 1, 3]:
				var o: int = base[order[q]]
				verts.append(corner[q])
				uvs.append((origin + Vector2(o & 0xff, o >> 8 & 0xff) + Vector2(0.5, 0.5)) / float(GRID * 64))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(atlas)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	floor_node = MeshInstance3D.new()
	floor_node.mesh = mesh
	viewport.add_child(floor_node)
func _build_floor(stage: int) -> void:
	_build_ground(stage)
	var map: Dictionary = sim.data.floor_map(stage)
	var vram := Tim.compose_absolute(sim.data.tile_images(stage))
	var w: int = map["w"]
	var h: int = map["h"]
	pano_pixels = w * 64
	pano_rows = h
	var strip := Image.create(w * 64, h * 64, false, Image.FORMAT_RGBA8)
	for r in h:
		for c in w:
			var tile: int = map["tiles"][r * w + c]
			var clut: int = map["cluts"][r * w + c]
			var region := Rect2i((tile & 3) << 6, (tile & 0xc) << 4, 64, 64)
			strip.blit_rect(Tim.decode_region(vram, (tile >> 8) & 0x1f, clut, region), Rect2i(0, 0, 64, 64), Vector2i(c * 64, r * 64))
	pano_material = StandardMaterial3D.new()
	pano_material.albedo_texture = ImageTexture.create_from_image(strip)
	pano_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pano_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pano_material.texture_repeat = true
	pano_material.uv1_scale = Vector3(368.0 / pano_pixels, 1, 1)
	pano_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var quad := QuadMesh.new()
	quad.size = Vector2(368, h * 64) * PIXEL
	quad.material = pano_material
	var node := MeshInstance3D.new()
	node.mesh = quad
	node.name = "Panorama"
	camera.add_child(node)
func _pad() -> int:
	var bits := 0
	for name in PAD_BITS:
		if Input.is_action_pressed("p1_%s" % name):
			bits |= PAD_BITS[name]
	return bits
func _process(delta: float) -> void:
	if hud != null and hud.size != size:
		hud.size = size
	if sim == null or paused:
		return
	clock += minf(delta, 0.1)
	var stepped := false
	while clock >= TICK:
		clock -= TICK
		var bits: int = forced if forced >= 0 else _pad()
		sim.pads[0] = bits
		sim.edges[0] = bits & ~previous & 0xf0
		previous = bits
		sim.tick()
		intro += 1
		stepped = true
		_sound()
		_sparks()
		_texts()
	if stepped:
		_present()
func _sound() -> void:
	for event in sim.sounds:
		sfx.play_entry(event[0], event[1])
	sim.sounds.clear()
func _sparks() -> void:
	for hit in Hits.impacts:
		var victim: int = hit[3]
		var blocked: bool = sim.ram.u8(victim + 0xcf) != 0
		impact.burst(Vector3(hit[0], -hit[1], -hit[2]) * 0.001, blocked, 1.0)
	Hits.impacts.clear()
func _present() -> void:
	var ram = sim.ram
	for p in 3:
		var a: int = sim.actor(p)
		var f = fighters[p]
		if f == null:
			continue
		var visible_now: bool = ram.u8(a + 0xc3) != 0 or p == 0
		f.visible = visible_now
		if not visible_now:
			continue
		var row: int = ram.u32(a + 0x54)
		var ptr: int = ram.u32(row)
		if not streams.has(ptr):
			streams[ptr] = ram.m.slice(ptr - 0x80000000, ptr - 0x80000000 + STREAM_SPAN)
		f.stream_bytes = streams[ptr]
		f.stream_start = 0
		f.frames = ram.u8(row + 0x18)
		f.set_frame(clampi(ram.s16(a + 0x58) - 1, 0, maxi(f.frames - 1, 0)), sim.secondary_locals(p))
		f.position = Vector3(ram.s32(a), -ram.s32(a + 4), -ram.s32(a + 8)) * 0.001
		f.rotation.y = 3.0 * PI / 2.0 - ram.u16(a + 0x2c) * TAU / 65536.0
	_camera()
	var target: int = sim.actor(ram.u8(sim.actor(0) + 0x20))
	hud.refresh(target)
	if not hud.fills.is_empty():
		for pair in [[0, sim.actor(0)], [1, target]]:
			var costume: int = ram.s16(pair[1] + 0x14)
			var label: String = str(costume >> 2)
			if label != shown_names[pair[0]]:
				shown_names[pair[0]] = label
				hud.set_name_label(pair[0], costume >> 2, exe.cstring(exe.u32(exe.u32(0x80097d40 + (costume if costume <= 0x5c else 0x58) * 4))))
func _camera() -> void:
	var x: float = sim.cam_x * 0.001
	camera.position = Vector3(x, -sim.cam_y * 0.001, -sim.cam_z * 0.001)
	var pitch: float = deg_to_rad(sim.cam_pitch / 64.0 * 360.0 / 4096.0)
	camera.rotation = Vector3(-pitch, 0, deg_to_rad(sim.cam_rot * 360.0 / 4096.0))
	if floor_node != null:
		floor_node.position = Vector3(snappedf(x, CELL), -0.004, 0.0)
	if pano_material != null:
		var below: float = -sim.cam_y
		var ahead: float = 2500.0 - sim.cam_z
		var depth: float = below * sin(pitch) + ahead * cos(pitch)
		var up: float = -below * cos(pitch) + ahead * sin(pitch)
		var horizon: float = 240.0 - 500.0 * up / depth
		var node: Node3D = camera.get_node("Panorama")
		var centre: float = horizon - pano_rows * 32.0
		node.position = Vector3(0, (240.0 - centre) * PIXEL, -SCREEN_DISTANCE)
		pano_material.uv1_offset = Vector3(sim.cam_x / 20.0 / pano_pixels, 0, 0)
func banner(stage: int, place: String) -> void:
	intro_lines = ["TEKKEN FORCE", "STAGE %d" % (stage + 1) if stage < 4 else "FINAL STAGE", place]
func _clock(count: int) -> String:
	var seconds := count / 60
	return "%02d'%02d\"%02d" % [seconds / 60, seconds % 60, (count % 60) * 100 / 60]
func _texts() -> void:
	if sim.mode == Sim.Mode.TALLY:
		var t: int = sim.mode_timer
		var rows := ["", "", "", "", ""]
		if t > 0x1d:
			rows[0] = "STAGE BONUS : %5d" % sim.data.clear_bonus(sim.stage)
		if t > 0x3b:
			rows[1] = "CLEAR BONUS : %5d" % sim.clear_bonus_hp
		if t > 0x59:
			rows[2] = "CLEAR TIME : " + _clock(sim.boss_elapsed)
		if t > 0x77:
			if sim.stage < 3 and sim.par_left != 0:
				rows[3] = "BONUS TIME : " + _clock(sim.par_left)
			elif sim.key_awarded:
				rows[3] = "YOU GOT A KEY!!"
			elif sim.final_offer:
				rows[3] = "FINAL STAGE CHALLENGE!!"
		hud.show_lines(rows)
	elif intro < 120:
		hud.show_lines(intro_lines)
	else:
		hud.show_lines([])
