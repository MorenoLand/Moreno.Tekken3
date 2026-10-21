extends Node
# Runs a Tekken Force attempt: stage after stage, the key and final stage rules, scores and the save updates.
const View := preload("res://scripts/force/force_view.gd")
const Intro := preload("res://scripts/force/force_intro.gd")
const Save := preload("res://scripts/core/save.gd")
const Options := preload("res://scripts/core/options.gd")
const Exe := preload("res://scripts/core/exe.gd")
signal done
var host
var player_model := 0
var character := 0
var roster := 0
var stage := 0
var time := 0
var score := 0
var view
func begin(main_node, model_id: int, character_index: int, roster_index: int) -> void:
	roster = roster_index
	host = main_node
	player_model = model_id
	character = character_index
	stage = 0
	time = 0
	score = 0
	_stage()
func _stage() -> void:
	var intro := Intro.new()
	intro.setup([roster, roster], [character, character], mini(stage + 1, 5))
	intro.place = Intro.NAMES[stage]
	host._swap(intro)
	host.music.play_song(_stage_song())
	intro.finished.connect(_play)
func _play() -> void:
	view = View.new()
	host._swap(view)
	view.stage_result.connect(_cleared)
	view.game_over.connect(_over)
	view.quit.connect(func(): done.emit())
	view.music.connect(func(song): host.music.play_song(song))
	host.music.play_song(_stage_song())
	view.start(player_model, stage, time, score, Save.force_keys())
func _stage_song() -> int:
	if stage >= 4:
		return 0x19
	var exe := Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
	return exe.u8(exe.u32(0x80097d40 + character * 16) + 11)
func _cleared(result: Dictionary) -> void:
	score = result["score"]
	time = result["time"]
	var lines := []
	if result.get("won", false):
		var fresh := Save.record_force_clear(score)
		lines = ["YOU SAVED DR.BOSKONOVITCH!"]
		if fresh:
			lines.append("NEW CHARACTER")
			lines.append("DOCTOR B.")
		_summary(lines)
		return
	if result["key"]:
		Save.add_force_key()
	if stage == 3 and not result["final"]:
		Save.record_force_score(score)
		_summary(["TEKKEN FORCE", "STAGE CLEAR", "SCORE %d" % score])
		return
	stage += 1
	_stage()
func _over() -> void:
	Save.record_force_score(score)
	_summary(["GAME OVER", "SCORE %d" % score])
func _summary(lines: Array) -> void:
	host._summary(lines, func(): done.emit())
