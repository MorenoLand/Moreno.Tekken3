extends Node
# Practice mode: the MODE SELECT box and its settings pages, the training dummy and the attack data lines.
# Layout, colours and values are from the original's draw lists and screenshots; behaviour that was not
# observed (counter attacks, hit analysis, combo replay and the combo training strips) is only stored.
signal player_select
signal command_list
const Records := preload("res://scripts/core/records.gd")
const FRAME_BANNER := 90
const DUMMIES := ["STAND", "CROUCH", "STAND GUARD", "CROUCH GUARD", "GUARD ALL", "AUTO GUARD", "QUICK ROLL u", "QUICK ROLL d", "CONTROLLER"]
const DIFFICULTIES := ["EASY", "MEDIUM", "HARD"]
const LEVELS := ["STAGE 1", "STAGE 2", "STAGE 3", "STAGE 4", "STAGE 5", "STAGE 6", "STAGE 7", "STAGE 8", "STAGE 9", "FINAL STAGE"]
const MODES := ["1P FREESTYLE", "VS CPU", "COMBO TRAINING", "PLAYER SELECT", "RESET"]
const TITLES := ["1P FREESTYLE", "VS.CPU", "COMBO TRAINING"]
const TITLE_CLUT := 0x7e5a
const ROW_CLUT := 0x7e1b
const CURSOR_CLUT := 0x7e1a
const PAD_UP := 0x1000
const PAD_RIGHT := 0x2000
const PAD_DOWN := 0x4000
const PAD_LEFT := 0x8000
var view
var sim
var hud
var layer := Control.new()
var attack_layer := Control.new()
var state := "banner"
var page := "mode"
var cursor := 0
var kind := 0
var dummy := 0
var counter_attacks := false
var attack_data := true
var hit_analysis := false
var combo_replay := false
var cpu_difficulty := 1
var cpu_level := 2
var combo_player := 0
var combo_type := 1
var frames := 0
var last_health := [0, 0]
var combo_total := [0, 0]
var idle_frames := [0, 0]
var last_damage := [0, 0]
func setup(owner_view) -> void:
	view = owner_view
	sim = view.sim
	hud = view.hud
	hud.hide_bars()
	hud.screen.add_child(layer)
	hud.screen.add_child(attack_layer)
	sim.phase = sim.Phase.FIGHT
	sim.phase_frames = 0
	for p in 2:
		last_health[p] = sim.ram.u32(sim.actor(p) + 0x3f4)
	hud.say("PRACTICE MODE", 0)
func step() -> void:
	if state == "banner":
		frames += 1
		if frames >= FRAME_BANNER:
			hud.say("", 0)
			_open("mode")
		return
	_track_damage()
	if state == "play" and sim.phase == sim.Phase.ROUND_OVER and sim.phase_frames > 150:
		reset_round()
func reset_round() -> void:
	sim.begin_round()
	sim.phase = sim.Phase.FIGHT
	sim.phase_frames = 0
	hud.say("", 0)
	hud.say("", 1)
	hud.say("", 2)
	for p in 2:
		last_health[p] = sim.ram.u32(sim.actor(p) + 0x3f4)
		combo_total[p] = 0
		last_damage[p] = 0
	_refresh_attack()
# What the training dummy (player 2) does this frame; the pad word is absolute, "back" depends on the side.
func pad(player_two: int) -> int:
	if state != "play" or kind == 1:
		return 0 if state != "play" else player_two
	var a: int = sim.actor(1)
	var back: int = PAD_RIGHT if sim.ram.u8(a + 0xc6) == 1 else PAD_LEFT
	match dummy:
		0:
			return 0
		1:
			return PAD_DOWN
		2:
			return back
		3:
			return back | PAD_DOWN
		4:
			return back
		5:
			var foe: int = sim.actor(0)
			return back if sim.ram.s16(foe + 0xa0) > 0x100 and _near() else 0
		6:
			return PAD_UP if _down() else 0
		7:
			return PAD_DOWN if _down() else 0
	return player_two
func _near() -> bool:
	return absi(sim.ram.s16(sim.actor(0) + 0x1278) - sim.ram.s16(sim.actor(1) + 0x1278)) < 140
func _down() -> bool:
	return sim.ram.u32(sim.actor(1) + 0x3f4) > 0 and sim.ram.s16(sim.actor(1) + 0x74) < 0
func _track_damage() -> void:
	for p in 2:
		var hp: int = sim.ram.u32(sim.actor(p) + 0x3f4)
		var lost: int = last_health[p] - hp
		if lost > 0:
			var points: int = int(round(lost / 65536.0))
			last_damage[1 - p] = points
			combo_total[1 - p] += points
			idle_frames[p] = 0
			_refresh_attack()
		else:
			idle_frames[p] += 1
			if idle_frames[p] == 90 and combo_total[1 - p] != 0:
				combo_total[1 - p] = 0
				_refresh_attack()
		last_health[p] = hp
func _refresh_attack() -> void:
	for child in attack_layer.get_children():
		child.queue_free()
	if not attack_data:
		return
	for p in 2:
		_text(attack_layer, "TOTAL DMG:%d" % combo_total[p], 0, 0x7e11, Vector2(9 if p == 0 else 207, 54))
	var share: int = last_damage[0] * 100 / 130
	_text(attack_layer, "DMG:%03d(%03d%%)" % [last_damage[0], share], 0, 0x7e16, Vector2(9, 72))
func input(event: InputEvent) -> bool:
	if state == "banner":
		return false
	if state == "play":
		if event.is_action_pressed("menu_start"):
			_open("page")
			return true
		return false
	var rows := _rows()
	if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
		cursor = (cursor + (1 if event.is_action_pressed("menu_down") else rows.size() - 1)) % rows.size()
		_draw()
		return true
	var step_by: int = 1 if (event.is_action_pressed("menu_right") or event.is_action_pressed("menu_confirm")) else (-1 if event.is_action_pressed("menu_left") else 0)
	if step_by != 0:
		_activate(rows[cursor], step_by, event.is_action_pressed("menu_confirm"))
		return true
	return event.is_action_pressed("menu_back") or event.is_action_pressed("menu_start")
func _rows() -> Array:
	if page == "mode":
		return MODES
	match kind:
		0:
			return ["ok", "command", "dummy", "counter", "attack", "hit", "replay", "return"]
		1:
			return ["ok", "command", "difficulty", "level", "attack", "hit", "replay", "return"]
	return ["ok", "command", "player", "type", "attack", "hit", "replay", "return"]
func _activate(row, step_by: int, confirm: bool) -> void:
	if page == "mode":
		if not confirm:
			return
		match cursor:
			0, 1, 2:
				kind = cursor
				page = "page"
				cursor = 0
				_apply_kind()
			3:
				player_select.emit()
				return
			4:
				_close()
				reset_round()
				return
		_draw()
		return
	match row:
		"ok":
			if confirm:
				_close()
				return
		"command":
			if confirm:
				command_list.emit()
				return
		"return":
			if confirm:
				page = "mode"
				cursor = kind
		"dummy":
			dummy = posmod(dummy + step_by, DUMMIES.size())
		"counter":
			counter_attacks = not counter_attacks
		"attack":
			attack_data = not attack_data
			_refresh_attack()
		"hit":
			hit_analysis = not hit_analysis
		"replay":
			combo_replay = not combo_replay
		"difficulty":
			cpu_difficulty = posmod(cpu_difficulty + step_by, DIFFICULTIES.size())
			_apply_kind()
		"level":
			cpu_level = posmod(cpu_level + step_by, LEVELS.size())
			_apply_kind()
		"player":
			combo_player = posmod(combo_player + step_by, 21)
		"type":
			combo_type = posmod(combo_type - 1 + step_by, 6) + 1
	_draw()
# VS CPU lets the computer fight player 2 at the chosen difficulty and level; the other kinds keep the dummy.
func _apply_kind() -> void:
	sim.ai_practice = kind == 1
	sim.computer[1] = kind == 1
	sim.ram.w8(sim.actor(1) + 0xc5, 1 if kind == 1 else 0)
	if kind == 1:
		sim.ram.w8(sim.Ai.LEVEL, cpu_difficulty)
		sim.ram.w8(sim.Ai.STAGE_LEVEL, cpu_level)
		sim.ai.start_match()
func _open(which: String) -> void:
	state = "menu"
	page = which
	if which == "mode":
		cursor = kind
	else:
		page = "page"
		cursor = 0
	view.paused = true
	_draw()
func _close() -> void:
	state = "play"
	view.paused = false
	for child in layer.get_children():
		child.queue_free()
	_refresh_attack()
func _draw() -> void:
	for child in layer.get_children():
		child.queue_free()
		layer.remove_child(child)
	if page == "mode":
		_box(Rect2(7, 38, 174, 196), Rect2(8, 40, 172, 192))
		_text(layer, "MODE SELECT", 1, TITLE_CLUT, Vector2(16, 56))
		for i in MODES.size():
			_text(layer, MODES[i], 0, CURSOR_CLUT if i == cursor else ROW_CLUT, Vector2(16, 110 + 22 * i))
		return
	_box(Rect2(63, 38, 242, 320), Rect2(64, 40, 240, 316))
	_text(layer, TITLES[kind], 1, TITLE_CLUT, Vector2(72, 56))
	var rows := _rows()
	var y := 110
	for i in rows.size():
		var clut: int = CURSOR_CLUT if i == cursor else ROW_CLUT
		match rows[i]:
			"ok":
				_text(layer, "OK", 0, clut, Vector2(72, 110))
			"command":
				_text(layer, "COMMAND LIST", 0, clut, Vector2(72, 132))
			"dummy":
				_text(layer, "TRAINING DUMMY", 0, clut, Vector2(72, 162))
				_value(DUMMIES[dummy], 184, clut)
			"counter":
				_row("COUNTER ATTACKS", "ON" if counter_attacks else "OFF", 206, clut)
			"difficulty":
				_row("CPU DIFFICULTY", DIFFICULTIES[cpu_difficulty], 162, clut)
			"level":
				_row("CPU LEVEL", LEVELS[cpu_level], 184, clut)
			"player":
				_row("COMBO PLAYER %d-%s" % [combo_player + 1, _character_name(combo_player)], "", 162, clut)
			"type":
				_row("COMBO TYPE", str(combo_type), 184, clut)
			"attack":
				_row("ATTACK DATA", "ON" if attack_data else "OFF", _row_y(kind, 4), clut)
			"hit":
				_row("HIT ANALYSIS", "ON" if hit_analysis else "OFF", _row_y(kind, 5), clut)
			"replay":
				_row("COMBO REPLAY", "ON" if combo_replay else "OFF", _row_y(kind, 6), clut)
			"return":
				_text(layer, "RETURN TO MODE SELECT", 0, clut, Vector2(72, 328))
func _row_y(which: int, index: int) -> int:
	return (228 if which == 0 else 206) + 22 * (index - 4)
func _row(label: String, value: String, y: int, clut: int) -> void:
	_text(layer, label, 0, clut, Vector2(72, y))
	if value != "":
		_value(value, y, clut)
func _value(value: String, y: int, clut: int) -> void:
	_text(layer, value, 0, clut, Vector2(297 - 9 * value.length(), y))
func _character_name(character: int) -> String:
	var roster: int = Records.roster_of(character)
	return view._roster_name(roster)
func _box(outer: Rect2, inner: Rect2) -> void:
	var edge := ColorRect.new()
	edge.position = outer.position
	edge.size = outer.size
	edge.color = Color8(0xe0, 0xe0, 0xe0)
	layer.add_child(edge)
	var fill := ColorRect.new()
	fill.position = inner.position
	fill.size = inner.size
	fill.color = Color8(0x00, 0x10, 0x30)
	layer.add_child(fill)
func _text(parent: Control, text: String, which: int, clut: int, at: Vector2) -> void:
	var texture: ImageTexture = hud.font.render_clut(text, which, clut)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.size = texture.get_size()
	rect.position = at
	parent.add_child(rect)
