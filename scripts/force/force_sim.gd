extends "res://scripts/combat/match.gd"
const Data := preload("res://scripts/force/force_data.gd")
const Options := preload("res://scripts/core/options.gd")
const COUNT := 3
const BNS := "res://assets/bns/"
const SOLDIER_DATA := 262
const COSTUME_TO_MODEL := 0x800958c4
const SIN := 0x8001e8c4
const COS := 0x8001f0c4
const CAPS := 0x80097a44
const RATES := 0x80097a50
const AI_STAGE_LEVEL := [0, 3, 4, 5, 5]
const BOSS_LISTS := 0x800b6378
const TIME_CAP := 0x1734
const DEAD := 6
enum Mode {PLAY, WAIT, CLEAR_WAIT, LOADING, BOSS, TALLY, FINAL, ENDED}
enum Slot {INIT, FREE, LOAD, WAIT, READY, ALIVE, DYING, FADE}
signal enemy_changed(slot: int, model_id: int)
signal boss_started(model_id: int, character: int)
signal stage_done(result: Dictionary)
signal game_over
signal popup(text: String, world: Vector3, kind: String)
var data
var stage := 0
var final := false
var script_entries: Array = []
var cursor := 0
var mode := Mode.PLAY
var frame := 0
var frame_unpaused := 0
var mode_timer := 0
var cam_mode := 0
var cam_x := 0
var cam_y := -3500
var cam_z := -7000
var cam_pitch := 0x2aaa
var cam_pitch_goal := 0x2aaa
var cam_rot := 0
var cam_lo := 0
var cam_hi := 0
var cam_slack := 1
var cam_back := -100
var cam_start := 0
var cam_target := 0
var cam_screen := Vector2.ZERO
var slots: Array = []
var kills := 0
var kill_goal := 0
var group_on := false
var group_end := 0
var group_cursor := 0
var items: Array = []
var score := 0
var time_left := 0
var boss_active := false
var boss_start_time := 0
var par_left := 0
var boss_elapsed := 0
var clear_bonus_hp := 0
var keys := 0
var key_awarded := false
var boss_song := 1
var final_offer := false
var player_model_id := 0
var player_character := 0
var player_costume := 0
var kill_count := 0
var ended := false
var tally_lines: Array = []
var aim_cooldown := 0
var aim_sticky := 0
var target_toggle := 0
func _file(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)
func model_id_for_costume(costume: int) -> int:
	return 71 + 4 * ram.s8(COSTUME_TO_MODEL + costume)
func setup_force(exe: PackedByteArray, common: PackedByteArray, player_id: int, stage_index: int, carried_time: int, carried_score: int, key_count: int) -> void:
	data = Data.new()
	stage = stage_index
	final = stage >= Data.FINAL_STAGE
	keys = key_count
	score = carried_score
	player_model_id = player_id
	ram.load_bytes(0x80010000, exe.slice(0x800))
	ram.load_bytes(Data.OVERLAY, _file(BNS + "007.bin"))
	ram.w8(Ai.LEVEL, Options.get_value("difficulty"))
	ram.w8(Ai.STAGE_LEVEL, AI_STAGE_LEVEL[stage])
	ram.w16(Ai.DEMO_FLAG, 0)
	motion = Motion.new(Exe.new(exe))
	skeleton = Skeleton.new(Exe.new(exe))
	secondary = Secondary.new(ram, skeleton)
	var soldier_model := _file("%s%03d.3dmk" % [BNS, model_id_for_costume(Data.FIRST_ENEMY_COSTUME)])
	models = [_file("%s%03d.3dmk" % [BNS, player_id]), soldier_model, soldier_model]
	MoveData.place(ram, 2, common)
	MoveData.place(ram, 0, _file("%s%03d.bin" % [BNS, player_id + 3]))
	MoveData.place(ram, 1, _file("%s%03d.bin" % [BNS, SOLDIER_DATA]))
	MoveData.relocate(ram, 2)
	MoveData.relocate(ram, 0)
	MoveData.relocate(ram, 1)
	MoveData.merge_tables(ram)
	ram.w32(0x80095484, 1)
	ram.w8(0x800afa93, 1)
	ram.w8(0x800afa88, 8)
	ram.w16(0x800adc84, 15 + stage)
	for p in COUNT:
		var a := actor(p)
		ram.w8(a + 0x1e, p)
		ram.w8(a + 0x1f, 0 if p > 0 else 1)
		ram.w8(a + 0x20, 0 if p > 0 else 1)
		ram.w8(a + 0x21, 0)
		ram.w8(a + 0x22, 0)
		ram.w8(a + 0x23, 0)
		ram.w16(a + 0x12, mini(p, 1))
		ram.w8(a + 0xc5, 0 if p == 0 else 1)
		var scale: int = (models[p].decode_u32(4) << 12) / 100
		ram.w16(a + 0x4ec, scale)
		ram.w16(a + 0x4ee, scale)
		ram.w32(a + 0x3f4, MAX_HEALTH)
		ram.w32(a + 0x3f8, MAX_HEALTH)
		Pad.reset(ram, a)
	_set_costume(actor(0), _player_costume(player_id))
	player_character = ram.s16(actor(0) + 0x18)
	_set_costume(actor(1), Data.FIRST_ENEMY_COSTUME)
	_set_costume(actor(2), Data.FIRST_ENEMY_COSTUME)
	secondary.setup(actor(0), (player_id - 71) / 4, models[0])
	for p in COUNT:
		start_actor(p)
	ai = Ai.new(ram)
	ai.start_match()
	_ai_enemies()
	time_left = carried_time if carried_time > 0 else Options.round_frames()
	phase = Phase.FIGHT
	_place_start()
	_camera_init()
	_load_stage()
func start_actor(p: int, reset_position: bool = true) -> void:
	var a := actor(p)
	var b := actor(0 if p > 0 else 1)
	var x: int = ram.u32(a)
	var z: int = ram.u32(a + 8)
	var face: int = ram.u16(a + 0xe)
	if reset_position:
		x = -1000 if p == 0 else 1000
		z = 0
		face = 0x4000 if p == 0 else 0xc000
	ram.w8(a + 0x1f, ram.u8(b + 0x1e))
	ram.w32(a + 0x100, 1000)
	ram.w32(a + 0xfc, 1000)
	ram.w32(a + 0xf8, 1000)
	ram.w32(a + 0x12c, ram.u32(a))
	ram.w32(a + 0x130, ram.u32(a + 8))
	ram.w16(a + 0x1a0, 1)
	var row := MoveStep.slot_row(ram, a, 1)
	ram.w32(a + 0x54, row)
	ram.w32(a + 0x4c, row)
	ram.w32(a + 0x1a4, row)
	ram.w16(a + 0x58, 1)
	ram.w16(a + 0x198, 1)
	ram.w16(a + 0x19a, MoveStep.kind_of(ram, a, 0))
	ram.w16(a + 0x19c, 0)
	ram.w16(a + 0x19e, 0)
	ram.w8(a + 0xc3, 1)
	MoveStep.step(ram, a, b)
	ram.w16(a + 0x50, 1)
	ram.w16(a + 0x58, 1)
	ram.w16(a + 0x0e, face)
	ram.w32(a, x)
	ram.w32(a + 4, 0)
	ram.w32(a + 8, z)
	ram.w16(a + 0x0c, 0)
	ram.w16(a + 0x10, 0)
	ram.w16(a + 0x2c, face)
	ram.w16(a + 0x30, face)
	ram.w16(a + 0x1278, 176 + x / 10)
	ram.w32(a + 0x994, 0xfffffa6f)
	ram.w32(a + 0x950, 0xfffffbe5)
	ram.w32(a + 0xf68, x)
	ram.w32(a + 0xf70, z)
	ram.w32(a + 0x990, x)
	ram.w32(a + 0x998, z)
	ram.w32(a + 0x94c, x)
	ram.w32(a + 0x954, z)
	for o in [0x3e8, 0x3ec, 0x3f0]:
		ram.w32(a + o, 0)
	ram.w32(a + 0x3f4, ram.u32(a + 0x3f8))
	ram.w16(a + 0x6a, 0xffff)
	for o in [0x400, 0x76, 0x92, 0x94, 0x9a, 0x9c, 0x9e, 0x46, 0x48, 0x104, 0x106, 0x10a, 0x114, 0x116, 0x118, 0x11a, 0x124, 0x126, 0x122, 0x128, 0xcc, 0xe8, 0xec]:
		ram.w16(a + o, 0)
	for o in [0x82, 0xb5, 0x87, 0x89, 0x8a, 0xb7, 0x8c, 0xba, 0xbb, 0xbd, 0xb8, 0xd3, 0xd4, 0xcf, 0xd0, 0xde, 0xdb, 0xbe, 0xbf, 0xc0, 0xc1, 0xc2, 0xc4, 0xc9, 0xc7]:
		ram.w8(a + o, 0)
	ram.w8(a + 0xc3, 1)
	ram.w16(a + 0x1868, 0)
	ram.w16(a + 0x186a, 0)
	ram.w16(a + 0x186c, 0)
	ram.w16(a + 0x186e, 0)
	ram.w32(a + 0x1870, 0)
	ram.w32(a + 0x1878, 0)
	Hits.reset_hits(ram, a)
	ram.w32(a + 0x194, a + 0x13c)
	MoveStep.clear_events(ram, a)
	Volumes.set_radii(ram, a)
	ram.w32(a + 0x3b8, ram.u32(a + 0xf68))
	ram.w32(a + 0x3bc, ram.u32(a + 0xf6c))
	ram.w32(a + 0x3c0, ram.u32(a + 0xf70))
func _player_costume(model_id: int) -> int:
	var f: int = (model_id - 71) / 4
	for c in 92:
		if ram.s8(COSTUME_TO_MODEL + c) == f:
			return c
	return 0
func _set_costume(a: int, costume: int) -> void:
	var info: int = ram.u32(0x80097d40 + (costume if costume <= 0x5c else 0x58) * 4)
	ram.w16(a + 0x14, costume)
	ram.w16(a + 0x16, ram.u8(info + 9))
	ram.w16(a + 0x18, costume >> 2)
	ram.w16(a + 0x1a, ram.u8(info + 8))
	ram.w16(a + 0x1c, ram.s8(COSTUME_TO_MODEL + costume) if costume < 0x5c else -1)
func _ai_enemies() -> void:
	ram.w8(actor(0) + 0x1886, 0xff)
	ram.w8(actor(0) + 0x1887, 0xff)
	for i in [1, 2]:
		_ai_enemy(i)
func _ai_enemy(i: int) -> void:
	var e := actor(i)
	var slot: int = 2 - i
	ram.w8(e + 0x1886, slot)
	ram.w8(e + 0x1887, 0xff)
	var st: int = Ai.STATES + slot * Ai.STATE_SIZE
	ram.w16(st + 2, slot)
	ram.w16(st, slot)
	ram.w16(st + 6, 0)
	ram.w16(st + 4, 0)
	ram.w32(st + 0x10, actor(0))
	var table: int = ram.u32(ram.u32(0x800adc20 + 4) + 0xc)
	ram.w32(st + 0xc, table)
	ram.w32(Ai.MOVE_TABLES + slot * 4, table)
	ai.bind(e)
	ai.start_round(e, 0, -1, -1)
func _place_start() -> void:
	for p in COUNT:
		var a := actor(p)
		for o in [0, 8, 0xf68, 0xf70, 0x990, 0x998, 0x94c, 0x954, 0x12c, 0x130, 0x3b8, 0x3c0]:
			ram.w32(a + o, 0)
		ram.w16(a + 0x0e, 0x4000)
		ram.w16(a + 0x2c, 0x4000)
		ram.w16(a + 0x30, 0x4000)
		ram.w32(a + 4, 0)
	if final:
		ram.w32(actor(0), -1000)
		ram.w32(actor(0) + 0xf68, -1000)
		ram.w32(actor(0) + 0x990, -1000)
		ram.w32(actor(0) + 0x94c, -1000)
		ram.w32(actor(0) + 0x12c, -1000)
		ram.w32(actor(0) + 0x3b8, -1000)
		ram.w16(actor(0) + 0x0e, 0x4000)
		for p in [1, 2]:
			var a := actor(p)
			for o in [0, 0xf68, 0x990, 0x94c, 0x12c, 0x3b8]:
				ram.w32(a + o, 1000)
			ram.w16(a + 0x0e, 0xc000)
			ram.w16(a + 0x2c, 0xc000)
			ram.w16(a + 0x30, 0xc000)
	for p in [1, 2]:
		var e := actor(p)
		ram.w8(e + 0xc3, 0)
		ram.w8(e + 0xc2, 1)
		ram.w32(e + 0x3f4, 0)
	slots.clear()
	for i in 2:
		slots.append({"actor": actor(i + 1), "state": Slot.INIT, "a": 0, "level": 0, "id": i, "want": i, "timer": 0, "death": 0, "popup": 0, "bonus": 0, "pos": Vector3.ZERO})
	items = [{"state": 0, "x": 0, "z": 0, "t": 0}, {"state": 0, "x": 0, "z": 0, "t": 0}]
func _load_stage() -> void:
	script_entries = data.script(stage) if not final else []
	cursor = 0
	frame = 0
	frame_unpaused = 0
	kills = 0
	kill_goal = 0
	group_on = false
	mode = Mode.FINAL if final else Mode.PLAY
	boss_active = false
	if final:
		time_left = 0xe10
		_final_setup()
func _camera_init() -> void:
	cam_rot = 0x82 if stage == 3 else 0
	cam_slack = 1
	cam_y = -3500
	cam_z = -7000
	cam_mode = 0
	cam_x = 0
	cam_pitch = 0x2aaa
	cam_pitch_goal = 0x2aaa
	cam_target = 0
	cam_start = cam_x
	if stage == 3 or final:
		pass
func set_camera_mode(m: int) -> void:
	if m == 0:
		cam_slack = 1
	elif m == 2:
		cam_back = -100
		cam_slack = 0x3c
		cam_lo = cam_x - 5000
		cam_hi = cam_x + 5000
	cam_mode = m
func camera_step() -> void:
	var a := actor(0)
	var idx: int = (-cam_rot) & 0xfff
	var c: int = ram.s16(COS + idx * 2)
	var s: int = ram.s16(SIN + idx * 2)
	var dx: int = ram.s32(a + 0xf68) - cam_x
	var dz: int = ram.s32(a + 0xf70) - cam_z
	var x1: int = c * dx - s * -cam_y
	var y1: int = s * dx + c * -cam_y
	x1 = (x1 + 0xfff if x1 < 0 else x1) >> 12
	y1 = (y1 + 0xfff if y1 < 0 else y1) >> 12
	var pitch_index: int = (((-cam_pitch) + 0x3f if -cam_pitch < 0 else -cam_pitch) >> 5) & 0x1ffe
	var s2: int = ram.s16(SIN + pitch_index)
	var c2: int = ram.s16(COS + pitch_index)
	var depth: int = c2 * dz - s2 * y1
	var height: int = s2 * dz + c2 * y1
	depth = (depth + 0xfff if depth < 0 else depth) >> 12
	height = (height + 0xfff if height < 0 else height) >> 12
	if depth == 0:
		depth = 1
	var sy: int = FMath.tdiv(FMath.tdiv(height * 0x9c4, depth), 3)
	var sx: int = FMath.tdiv(x1 * 500, depth)
	cam_screen = Vector2(sx, sy)
	cam_target = cam_x
	if cam_mode != 1:
		if cam_mode == 2 and sx < cam_back:
			cam_target = cam_x + (cam_back - sx) * -5
		if cam_slack < sx:
			cam_target = cam_x + (sx - cam_slack) * 5
	if (sx > 0 and cam_x < cam_target) or (sx < 0 and cam_target < cam_x):
		cam_x = cam_target
	if cam_mode == 2:
		cam_x = clampi(cam_x, cam_lo, cam_hi)
	if sy >= 0xd5:
		cam_pitch_goal = cam_pitch + 0x2d8
	elif sy < 0xbc:
		cam_pitch_goal = cam_pitch - 0x2d8
	if cam_pitch != cam_pitch_goal:
		var d: int = cam_pitch - cam_pitch_goal
		cam_pitch -= (d + 7 if d < 0 else d) >> 3
	cam_pitch = clampi(cam_pitch, 0x2aaa, 0x10000)
func progress() -> int:
	return cam_x - cam_start
func free_slot() -> int:
	for i in 2:
		if slots[i]["state"] == Slot.FREE:
			return i
	return -1
func _slot_free_for_far(i: int) -> bool:
	return slots[i]["state"] == Slot.FREE and not boss_active
func select_targets() -> Array:
	var player := actor(0)
	var first := actor(1)
	var second := actor(2)
	var current := first if ram.u8(player + 0x20) == 1 else second
	var other := second if current == first else first
	var on_current: bool = (ram.u16(current + 0x1278) - 1) & 0xffff < 399
	var on_other: bool = (ram.u16(other + 0x1278) - 1) & 0xffff < 399
	var chosen: int = pick_target(player, current, other, on_current, on_other)
	var leftover: int = other if chosen == current else current
	if ram.u8(current + 0xc2) == 0 or ram.u8(other + 0xc2) == 0:
		ram.w8(player + 0xc7, 0)
	else:
		ram.w8(player + 0xc7, 1)
	ram.w8(player + 0xc8, 0)
	ram.w8(player + 0x20, ram.u8(chosen + 0x1e))
	ram.w8(chosen + 0x20, 0)
	ram.w8(leftover + 0x20, 0)
	for a in [player, first, second]:
		ram.w8(a + 0x1f, MoveStep.opponent_index(ram, a))
	return [player, chosen, leftover]
func pick_target(player: int, current: int, other: int, on_current: bool, on_other: bool) -> int:
	aim_cooldown = maxi(aim_cooldown - 1, 0)
	var result: int = current
	if ram.u8(current + 0xc2) == 0:
		if ram.u8(other + 0xc2) != 0:
			return current
		if on_current:
			if on_other and aim_cooldown == 0:
				var d_cur: int = _distance(player, current)
				var d_oth: int = _distance(player, other)
				if d_cur < 0x9c4 or d_oth < 0x9c4:
					var diff: int = d_cur - d_oth
					if absi(diff) < 400:
						MoveStep.face_opponent(ram, player, current)
						var cur_side: int = ram.s16(player + 0x32)
						var cur_off: int = ram.s16(player + 0x30)
						MoveStep.face_opponent(ram, player, other)
						var oth_side: int = ram.s16(player + 0x32)
						var oth_off: int = ram.s16(player + 0x30)
						if cur_side == oth_side:
							var limit: int = 0x3000
							if cur_side == 0:
								limit = 0x1000
							elif cur_side == 2:
								limit = 0x2000
							if absi(cur_off - oth_off) >= limit:
								result = other if cur_off < oth_off else current
						else:
							result = current
					else:
						result = other if diff > 0 else current
				if result != current:
					aim_cooldown = 0x78
			return result
		if on_other:
			return other
		return current
	return other if ram.u8(other + 0xc2) == 0 else current
func _distance(p: int, q: int) -> int:
	return ram.u32(MoveStep.distance_entry(ram, ram.u8(p + 0x1e), ram.u8(q + 0x1e)))
func _flip_flags() -> void:
	for p in COUNT:
		var a := actor(p)
		var b := MoveStep.opponent(ram, a)
		if ram.u8(a + 0xc7) == 0:
			ram.w8(a + 0xc6, 1 if ram.s16(b + 0x1278) <= ram.s16(a + 0x1278) else 0)
		else:
			ram.w8(a + 0xc6, ram.u8(a + 0xc8))
func _update_distances() -> void:
	var far := [0, 0, 0]
	for p in COUNT:
		var a := actor(p)
		far[p] = 1 if ram.u16(a + 0x1278) >= 0x191 else 0
		if p > 0 and ram.u8(a + 0xc5) != 0 and _slot_free_for_far(p - 1):
			far[p] = 1
	for pair in [[0, 1], [0, 2], [1, 2]]:
		var a: int = actor(pair[0])
		var b: int = actor(pair[1])
		var dx: int = ram.s32(b + 0xf68) - ram.s32(a + 0xf68)
		var dz: int = ram.s32(b + 0xf70) - ram.s32(a + 0xf70)
		var e: int = MoveStep.distance_entry(ram, pair[1], pair[0])
		ram.w32(e, FMath.isqrt(dx * dx + dz * dz))
		ram.w32(e + 4, dx)
		ram.w32(e + 8, dz)
		ram.w16(e + 12, FMath.atan2(ram, dz, dx))
	for p in COUNT:
		var a := actor(p)
		var idx: int = MoveStep.opponent_index(ram, a)
		var entry: int = MoveStep.distance_entry(ram, p, idx)
		var opp: int = MoveStep.opponent(ram, a)
		ram.w32(a + 0x12c, ram.u32(a + 0xf68))
		ram.w32(a + 0x130, ram.u32(a + 0xf70))
		var dist: int = ram.u32(entry)
		ram.w32(a + 0xf8, dist)
		var n := 0
		if ram.s16(a + 0x18) == 0xb or ram.s16(a + 0x18) == 0x14:
			n = 1
		if ram.s16(opp + 0x18) == 0xb or ram.s16(opp + 0x18) == 0x14:
			n += 1
		ram.w32(a + 0xf4, dist - 40 * n)
		ram.w32(a + 0xfc, ram.u32(entry + 4))
		ram.w32(a + 0x100, ram.u32(entry + 8))
		var ang: int = ram.s16(entry + 12)
		if idx >= p:
			ang -= 0x8000
		if ram.u8(a + 0xc7) == 0 and far[idx] == 0:
			ram.w16(a + 0x2a, ang)
		else:
			var side: int = 0xb4 - ram.s16(a + 0x1278)
			side = absi(side)
			side = absi(0xb4 - side)
			ram.w16(a + 0x2a, 0x4000 if ram.u8(a + 0xc8) == 0 else -0x4000)
			ram.w32(a + 0xf8, side * 10)
			ram.w32(a + 0xfc, side * 10)
			ram.w16(a + 0x100, 0)
			ram.w16(a + 0x102, 0)
	ram.w32(0x800afa3c, ram.u32(actor(0) + 0xf8))
func _bounds(p: int) -> void:
	var a := actor(p)
	var x: int = ram.s32(a + 0xf68)
	var z: int = ram.s32(a + 0xf70)
	var dx := 0
	var dz := 0
	var t: int = z - 0x8fc
	if t > 0:
		dz = -t
	var low: int = z + 0x898
	if stage == 3:
		low = z - _slope_edge(x - cam_x)
	if low < 0:
		dz = -low
	var rel: int = x - cam_x
	if ram.u8(a + 0xc5) == 0:
		var left: int = _edge(0, z)
		var right: int = _edge(1, z)
		var u: int = rel - left
		if u < 0:
			dx = -u
		var v: int = rel - right
		if v > 0:
			dx = -v
	else:
		var u2: int = x + 0x1068 - cam_x
		if u2 < 0:
			dx = -u2
		var v2: int = x - 0x1068 - cam_x
		if v2 > 0:
			dx = -v2
	var cap: int = ram.s32(CAPS + p * 4)
	dx = clampi(dx, -cap, cap)
	dz = clampi(dz, -cap, cap)
	for o in [0, 0xf68]:
		ram.w32(a + o, ram.s32(a + o) + dx)
	for o in [8, 0xf70]:
		ram.w32(a + o, ram.s32(a + o) + dz)
func _edge(side: int, z: int) -> int:
	var stage_three: bool = stage == 3
	var k: int
	var off: int
	if side == 0:
		k = -375 if stage_three else -323
		off = -2445 if stage_three else -2553
	else:
		k = 333 if stage_three else 329
		off = 2175 if stage_three else 1971
	return FMath.tdiv(k * z, 1000) + off
func _slope_edge(rel: int) -> int:
	var k := -259 if rel < 0 else 0
	return FMath.tdiv(-259 * rel, 1000) + -2285
func _cap_ramp() -> void:
	for p in COUNT:
		var cap: int = ram.s32(CAPS + p * 4)
		var rate: int = ram.s32(RATES + p * 4)
		if cap < 2000:
			ram.w32(CAPS + p * 4, cap + rate)
			ram.w32(RATES + p * 4, rate + 2)
		if ram.s32(CAPS + p * 4) > 2000:
			ram.w32(CAPS + p * 4, 2000)
			ram.w32(RATES + p * 4, 2)
func tick() -> void:
	ram.w32(Ai.FRAME_COUNTER, ram.u32(Ai.FRAME_COUNTER) + 1)
	var order: Array = select_targets()
	_flip_flags()
	for p in COUNT:
		Volumes.end_frame(ram, actor(p))
	for p in COUNT:
		var a := actor(p)
		MoveStep.step(ram, a, actor(ram.u8(a + 0x1f)))
	_update_distances()
	for p in COUNT:
		MovePhysics.run(ram, actor(p))
	for p in COUNT:
		_bounds(p)
	_cap_ramp()
	for p in COUNT:
		var a := actor(p)
		for k in 3:
			ram.w32(0x8009e6f8 + p * 0x10 + 4 + k * 4, ram.u32(a + 0xf68 + k * 4))
	for p in COUNT:
		place_root(p)
		update_joints(p)
	for p in COUNT:
		var a := actor(p)
		ram.w32(a + 0x3c4, ram.s32(a + 0xf68) - ram.s32(a + 0x3b8))
		ram.w32(a + 0x3c8, ram.s32(a + 0xf6c) - ram.s32(a + 0x3bc))
		ram.w32(a + 0x3b8, ram.u32(a + 0xf68))
		ram.w32(a + 0x3cc, ram.s32(a + 0xf70) - ram.s32(a + 0x3c0))
		ram.w32(a + 0x3bc, ram.u32(a + 0xf6c))
		ram.w32(a + 0x3c0, ram.u32(a + 0xf70))
		Volumes.set_radii(ram, a)
		Volumes.body_spheres(ram, a)
		push_radii(a)
		if ram.s16(a + 0x58) < ram.u8(ram.u32(a + 0x54) + 0x2d) or ram.u8(ram.u32(a + 0x54) + 0x2e) < ram.s16(a + 0x58):
			Volumes.limb_segments(ram, a)
		else:
			Volumes.window_segments(ram, a)
	for p in COUNT:
		var a := actor(p)
		ram.w8(a + 0xd5, 0)
		ram.w8(a + 0xd9, 0)
		for k in 3:
			ram.w8(a + 0xd6 + k, 0)
	for p in COUNT:
		var a := actor(p)
		if ram.s16(a + 0x74) != 0:
			ram.w8(a + 0xd9, 1)
			ram.w8(actor(ram.u8(a + 0x21)) + 0xd9, 1)
	for pair in [[0, 1], [0, 2], [1, 2]]:
		BodyPush.apply(ram, actor(pair[0]), actor(pair[1]))
	for p in COUNT:
		Hits.reset_hits(ram, actor(p))
	Hits.detect(ram, order[0], order[1])
	Hits.detect(ram, order[1], order[0])
	Hits.detect(ram, order[2], order[0])
	for p in COUNT:
		var a := actor(p)
		ram.w32(a + 0x3d0, ram.s32(a + 0x1b8) - ram.s32(a + 0x1ac))
		ram.w32(a + 0x3d4, ram.s32(a + 0x1bc) - ram.s32(a + 0x1b0))
		ram.w32(a + 0x3d8, ram.s32(a + 0x1c0) - ram.s32(a + 0x1b4))
	for p in COUNT:
		var a := actor(p)
		MoveStep.react_pick(ram, a, MoveStep.opponent(ram, a))
	for p in COUNT:
		var a := actor(p)
		ram.w16(a + 0xe8, 0)
		for o in [0xd4, 0xcf, 0xd0, 0xd3, 0xde]:
			ram.w8(a + o, 0)
	for p in COUNT:
		Damage.resolve(ram, actor(p))
		_score_hits(actor(p))
	for p in COUNT:
		var a := actor(p)
		SoundEvents.run(ram, a, MoveStep.opponent(ram, a), sounds)
	for p in COUNT:
		var a := actor(p)
		ram.w16(a + 0x1278, 176 + ram.s32(a + 0xf68) / 10)
	for p in COUNT:
		_control(p)
	_logic()
	camera_step()
func _score_hits(a: int) -> void:
	if ram.u8(a + 0xc5) == 0 or ram.u8(a + 0xce) == 0:
		return
	var gain := 0
	for k in 2:
		var rec: int = a + 0x13c + k * 0x2c
		if ram.u8(rec + 0x21) != 0:
			var by: int = actor(0) if ram.u8(rec + 0x20) == 0 else -1
			if by != -1 or ram.u8(actor(ram.u8(rec + 0x20)) + 0xe6) != 0:
				gain += ram.s16(rec + 0x1c)
	var combo: int = ram.s16(a + 0xcc)
	if combo > 0:
		gain += combo * 2
	if gain != 0:
		score = mini(score + gain * 10, 0x5f5e0f6)
func _control(p: int) -> void:
	var a := actor(p)
	var live: bool = mode != Mode.ENDED
	var flip: int = ram.u8(a + 0xc6)
	var pad: int = pads[0] if p == 0 else 0
	var edge: int = edges[0] if p == 0 else 0
	if p > 0:
		flip = 0
		if ram.u8(a + 0xc2) == 0 and ram.u8(a + 0xc3) != 0 and ram.u32(a + 0x3f4) != 0 and slots[p - 1]["state"] == Slot.ALIVE:
			var out: Array = ai.step(a)
			pad = out[0]
			edge = out[1]
	Pad.push(ram, a, flip, pad if live else 0, edge if live else 0)
	MoveStep.choose_next(ram, a)
func _logic() -> void:
	frame_unpaused += 1
	frame += 1
	var progress_now: int = progress()
	match mode:
		Mode.PLAY:
			_run_script(progress_now)
		Mode.WAIT:
			_wait_step()
		Mode.CLEAR_WAIT:
			if frame_unpaused > mode_timer:
				mode = Mode.LOADING
				mode_timer = frame_unpaused + 2
		Mode.LOADING:
			if frame_unpaused > mode_timer:
				_start_boss()
		Mode.BOSS:
			_boss_step()
		Mode.TALLY:
			_tally_step()
		Mode.FINAL:
			_final_step()
	_group_step(progress_now)
	for i in 2:
		_slot_step(i)
	_items_step()
	if mode != Mode.TALLY and mode != Mode.ENDED:
		time_left -= 1
	time_left = mini(time_left, TIME_CAP)
	if ram.u32(actor(0) + 0x3f4) == 0 and mode != Mode.ENDED:
		_player_down()
func _player_down() -> void:
	if ended:
		return
	ended = true
	mode = Mode.ENDED
	game_over.emit()
func _run_script(progress_now: int) -> void:
	while cursor < script_entries.size() and script_entries[cursor]["at"] <= progress_now:
		var e: Dictionary = script_entries[cursor]
		cursor += 1
		match e["type"]:
			0:
				set_camera_mode(e["p"])
			1:
				_spawn(e["p"], e["q"], e["x"], e["z"])
			2:
				group_on = true
				group_end = e["q"] & 0xffff
				if e["p"] < 0x31:
					group_cursor = e["p"]
			3:
				kills = 0
				kill_goal = e["p"]
				mode = Mode.WAIT
				return
			4:
				_spawn_item(cam_x + e["x"], e["z"])
			6:
				_end_stage()
				return
func _wait_step() -> void:
	if kill_goal < 0:
		if slots[0]["state"] == Slot.FREE and slots[1]["state"] == Slot.FREE:
			mode = Mode.PLAY
	elif kills >= kill_goal:
		mode = Mode.PLAY
func _spawn(id: int, level: int, x: int, z: int) -> void:
	var i := free_slot()
	if i < 0:
		return
	var slot: Dictionary = slots[i]
	var a: int = slot["actor"]
	if slot["id"] == id:
		slot["state"] = Slot.READY
	else:
		slot["state"] = Slot.LOAD
		slot["want"] = id
	slot["level"] = level % 5
	ram.w32(a, cam_x + x)
	ram.w32(a + 0xf68, cam_x + x)
	ram.w32(a + 8, z)
	ram.w32(a + 0xf70, z)
func _group_step(progress_now: int) -> void:
	if not group_on:
		return
	if progress_now >= group_end:
		group_on = false
		return
	var entry: Vector2i = data.group_entry(group_cursor)
	if entry.x == 99:
		return
	var i := free_slot()
	if i < 0:
		return
	_spawn(entry.x, entry.y, 5000, 0)
	group_cursor += 1
func _slot_step(i: int) -> void:
	var slot: Dictionary = slots[i]
	var a: int = slot["actor"]
	match slot["state"]:
		Slot.INIT:
			ram.w8(a + 0xc3, 0)
			ram.w32(a + 0x3f4, 0)
			ram.w8(a + 0xc2, 1)
			slot["state"] = Slot.FREE
		Slot.LOAD:
			ram.w8(a + 0xc3, 0)
			slot["state"] = Slot.WAIT
			slot["timer"] = frame + 2
		Slot.WAIT:
			if int(slot["timer"]) < frame:
				slot["id"] = slot["want"]
				var costume: int = data.costume(stage, slot["want"])
				_set_costume(a, costume)
				models[i + 1] = _file("%s%03d.3dmk" % [BNS, model_id_for_costume(costume)])
				var scale: int = (models[i + 1].decode_u32(4) << 12) / 100
				ram.w16(a + 0x4ec, scale)
				ram.w16(a + 0x4ee, scale)
				enemy_changed.emit(i, model_id_for_costume(costume))
				slot["state"] = Slot.READY
		Slot.READY:
			ram.w8(a + 0xc3, 1)
			var hp: int = data.health(stage, slot["level"])
			ram.w8(a + 0xc2, 0)
			ram.w32(a + 0x3f8, hp)
			ram.w32(a + 0x3f4, hp)
			slot["state"] = Slot.ALIVE
			_stand(a)
			ram.w32(a + 4, 0)
			ram.w16(a + 0x92, 0)
			ram.w8(a + 0xb8, 0)
		Slot.ALIVE:
			if ram.s32(a + 0x3f4) < 1:
				slot["state"] = Slot.DYING
				slot["timer"] = frame + 0x3c
				var by_player: bool = ram.u8(a + 0x22) == 0 or ram.u8(a + 0xe7) != 0
				if by_player:
					var seconds: int = data.kill_seconds(slot["level"])
					time_left = (time_left / 60) * 60 + 0x3b + seconds * 60
					slot["bonus"] = seconds
					slot["popup"] = frame + 0x3c
					kill_count += 1
					popup.emit("+%d" % seconds, Vector3(ram.s32(a + 0x990), -ram.s32(a + 0x994) + 300, -ram.s32(a + 0x998)) * 0.001, "bonus")
				else:
					slot["bonus"] = 0
		Slot.DYING:
			if int(slot["timer"]) < frame and ram.u8(a + 0xc4) == 0:
				slot["state"] = Slot.FADE
				slot["timer"] = frame + 0x28
				ram.w8(a + 0xc2, 1)
			elif ram.u8(a + 0xce) != 0 and ram.u8(a + 0x22) == 0:
				slot["timer"] = frame + 0x3c
		Slot.FADE:
			ram.w8(a + 0xc3, frame & 1)
			if int(slot["timer"]) < frame:
				kills += 1
				ram.w8(a + 0xc3, 0)
				slot["state"] = Slot.FREE
func _stand(a: int) -> void:
	ram.w16(a + 0x1a0, 3)
	var row: int = MoveStep.slot_row(ram, a, 3)
	ram.w32(a + 0x54, row)
	ram.w32(a + 0x4c, row)
	ram.w32(a + 0x1a4, row)
	ram.w16(a + 0x58, 1)
	ram.w16(a + 0x198, 1)
	ram.w16(a + 0x19a, MoveStep.kind_of(ram, a, 0))
func _spawn_item(x: int, z: int) -> void:
	for it in items:
		if it["state"] == 0:
			it["x"] = x
			it["z"] = z
			it["state"] = 1
			return
func _items_step() -> void:
	var player := actor(0)
	for it in items:
		if it["state"] == 1:
			if it["x"] < cam_x - 5000:
				it["state"] = 0
				continue
			var dx: int = absi(ram.s32(player + 0xf68) - it["x"])
			var dz: int = absi(ram.s32(player + 0xf70) - it["z"])
			if dx < 0x1f5 and dz < 0x1f5 and ram.s32(player + 0x3f4) > 0 and ram.u8(player + 0xdb) == 0:
				ram.w32(player + 0x3f4, ram.s32(player + 0x3f4) + Data.ITEM_HEAL)
				cue(0x4e6a)
				it["state"] = 2
				it["t"] = frame + 0x3c
				popup.emit("+LIFE!", Vector3(ram.s32(player + 0x990), -ram.s32(player + 0x994) + 300, -ram.s32(player + 0x998)) * 0.001, "life")
		elif it["state"] == 2:
			if frame == int(it["t"]) - 0xf:
				cue(0x87c0)
			if int(it["t"]) < frame:
				it["state"] = 0
func _end_stage() -> void:
	for slot in slots:
		var a: int = slot["actor"]
		ram.w32(a + 0x3f4, 0)
		ram.w8(a + 0xc3, 0)
		ram.w8(a + 0xc2, 1)
		slot["state"] = Slot.FREE
	mode = Mode.CLEAR_WAIT
	mode_timer = frame_unpaused + 0x3c
func _boss_pair() -> Vector2i:
	var list: int = ram.u32(BOSS_LISTS + player_costume_index() * 4)
	var at: int = list + (stage & 3) * 4
	return Vector2i(ram.u16(at), ram.s16(at + 2))
func player_costume_index() -> int:
	return ram.s16(actor(0) + 0x14)
func boss_choice() -> Vector2i:
	var pair: Vector2i = _boss_pair()
	var variant: int = pair.y
	if variant == -1:
		var player_costume_now: int = player_costume_index()
		if ram.s16(actor(0) + 0x18) == pair.x:
			variant = 1 if (player_costume_now & 3) == 0 else 0
		else:
			variant = 1 if (player_costume_now & 3) != 0 else 0
	return Vector2i(pair.x, variant)
func _start_boss() -> void:
	var choice: Vector2i = boss_choice()
	var costume: int = choice.x * 4 + choice.y
	var mid: int = model_id_for_costume(costume)
	MoveData.place(ram, 0, _file("%s%03d.bin" % [BNS, player_model_id + 3]))
	MoveData.place(ram, 1, _file("%s%03d.bin" % [BNS, mid + 3]))
	MoveData.relocate(ram, 0)
	MoveData.relocate(ram, 1)
	MoveData.merge_tables(ram)
	var a := actor(1)
	_set_costume(a, costume)
	boss_song = ram.u8(ram.u32(0x80097d40 + costume * 4) + 11)
	models[1] = _file("%s%03d.3dmk" % [BNS, mid])
	var scale: int = (models[1].decode_u32(4) << 12) / 100
	ram.w16(a + 0x4ec, scale)
	ram.w16(a + 0x4ee, scale)
	secondary.setup(a, (mid - 71) / 4, models[1])
	boss_started.emit(mid, choice.x)
	_ai_enemy(1)
	var slot: Dictionary = slots[0]
	slot["state"] = Slot.ALIVE
	slot["level"] = 4
	var hp: int = data.health(stage, 4)
	ram.w32(a + 0x3f8, hp)
	ram.w32(a + 0x3f4, hp)
	ram.w8(a + 0xc3, 1)
	ram.w8(a + 0xc2, 0)
	var x: int = cam_x + 1500
	ram.w32(a, x)
	ram.w32(a + 0xf68, x)
	ram.w32(a + 8, 0)
	ram.w32(a + 0xf70, 0)
	ram.w16(a + 0x0e, 0xc000)
	_stand(a)
	ram.w32(a + 4, 0)
	ram.w16(a + 0x92, 0)
	ram.w8(a + 0xb8, 0)
	set_camera_mode(1)
	boss_active = true
	boss_start_time = time_left
	mode = Mode.BOSS
func _boss_step() -> void:
	boss_elapsed = boss_start_time - time_left
	par_left = maxi(data.par_time(stage) - boss_elapsed, 0)
	var boss_hp: int = ram.s32(actor(1) + 0x3f4)
	if boss_hp < 1 or time_left < 1:
		_boss_done(boss_hp < 1)
func _boss_done(won: bool) -> void:
	if not won:
		_player_down()
		return
	mode = Mode.TALLY
	mode_timer = 0
	clear_bonus_hp = (ram.s32(actor(0) + 0x3f4) >> 16) * 100
	tally_lines.clear()
func _tally_step() -> void:
	mode_timer += 1
	if mode_timer == 0x1e:
		score += data.clear_bonus(stage)
	if mode_timer == 0x3c:
		score += clear_bonus_hp
	if mode_timer == 0x78:
		var award := false
		if stage < 3 and par_left != 0:
			time_left += par_left
		elif stage == 3:
			if keys < 3 and not _doctor_unlocked():
				keys += 1
				key_awarded = true
			elif keys >= 3 and not _doctor_unlocked():
				final_offer = true
	if mode_timer > 0xb4:
		stage_done.emit({"stage": stage, "score": score, "time": time_left, "keys": keys, "key": key_awarded, "final": final_offer})
		mode = Mode.ENDED
func _doctor_unlocked() -> bool:
	return false
func _final_setup() -> void:
	set_camera_mode(1)
	boss_active = true
	var a := actor(1)
	var choice := Vector2i(19, 0)
	var costume: int = choice.x * 4 + choice.y
	var mid: int = model_id_for_costume(costume)
	boss_song = ram.u8(ram.u32(0x80097d40 + costume * 4) + 11)
	MoveData.place(ram, 1, _file("%s%03d.bin" % [BNS, mid + 3]))
	MoveData.relocate(ram, 1)
	MoveData.merge_tables(ram)
	_set_costume(a, costume)
	models[1] = _file("%s%03d.3dmk" % [BNS, mid])
	var scale: int = (models[1].decode_u32(4) << 12) / 100
	ram.w16(a + 0x4ec, scale)
	ram.w16(a + 0x4ee, scale)
	secondary.setup(a, (mid - 71) / 4, models[1])
	boss_started.emit(mid, choice.x)
	_ai_enemy(1)
	slots[0]["state"] = Slot.ALIVE
	slots[0]["level"] = 4
	var hp: int = data.health(stage, 4)
	ram.w32(a + 0x3f8, hp)
	ram.w32(a + 0x3f4, hp)
	ram.w8(a + 0xc3, 1)
	ram.w8(a + 0xc2, 0)
	_stand(a)
	boss_start_time = time_left
func _final_step() -> void:
	var boss_hp: int = ram.s32(actor(1) + 0x3f4)
	if boss_hp < 1:
		mode = Mode.ENDED
		stage_done.emit({"stage": stage, "score": score, "time": time_left, "keys": keys, "key": false, "final": false, "won": true})
	elif time_left < 1:
		_player_down()
