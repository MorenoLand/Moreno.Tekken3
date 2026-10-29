extends Control
const RecordsScreen := preload("res://scripts/menu/records_screen.gd")
const Pack := preload("res://scripts/core/asset_pack.gd")
const Movie := preload("res://scripts/menu/movie_screen.gd")
const Title := preload("res://scripts/menu/title.gd")
const CharacterSelect := preload("res://scripts/menu/character_select.gd")
const FightView := preload("res://scripts/fight/fight_view.gd")
const TheaterScreen := preload("res://scripts/menu/theater_screen.gd")
const MusicPlayer := preload("res://scripts/menu/music_player.gd")
const VsScreen := preload("res://scripts/menu/vs_screen.gd")
const BallSelect := preload("res://scripts/menu/ball_select.gd")
# Disc movie per portrait id (oracle theater reads: Gon 18, Anna 17, Doctor B shares Yoshimitsu's, True Ogre Ogre's).
const ENDING_MOVIE := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 17, 4, 14]
const ROSTER_TO_CHARACTER := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 19, 17, 18, 20]
const PLAYABLE := ["ARCADE MODE", "VS MODE", "TEAM BATTLE MODE", "TIME ATTACK MODE", "SURVIVAL MODE", "PRACTICE MODE", "TEKKEN BALL MODE", "TEKKEN FORCE MODE"]
const ForceFlow := preload("res://scripts/force/force_flow.gd")
var ball_kind := 0
var attract_page := 0
const Save := preload("res://scripts/core/save.gd")
const NamcoScreen := preload("res://scripts/menu/namco_screen.gd")
const Exe := preload("res://scripts/core/exe.gd")
const OptionsScreen := preload("res://scripts/menu/options_screen.gd")
const ContinueScreen := preload("res://scripts/menu/continue_screen.gd")
const Results := preload("res://scripts/menu/results.gd")
const Music := preload("res://scripts/core/music.gd")
const TEAM_SIZE := 4
const SURVIVAL_RECOVERY := 0.25
const LADDER := 10
var music := Music.new()
var current: Control
var mode := ""
var ladder := 1
var picked := [0, 0]
var teams: Array = [[], []]
var members := [0, 0]
var carry := [1.0, 1.0]
var frames := 0
var wins := 0
var used: Array = []
var opponent := 0
var exe
var holder := AspectRatioContainer.new()
var widescreen := true
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	add_child(music)
	get_viewport().size_changed.connect(_aspect)
	_aspect()
	var pack := Pack.new()
	holder.add_child(pack)
	pack.ready_to_run.connect(func(): pack.queue_free(); _intro())
	pack.start()
func _aspect() -> void:
	var window := get_viewport().get_visible_rect().size
	holder.ratio = window.x / window.y if widescreen else 4.0 / 3.0
func _swap(next: Control) -> void:
	if current != null:
		current.queue_free()
	current = next
	holder.add_child(next)
func _intro() -> void:
	var namco := NamcoScreen.new()
	_swap(namco)
	namco.finished.connect(_movie)
func _movie() -> void:
	if not FileAccess.file_exists("res://assets/movies/20.ogv"):
		_title()
		return
	var movie := Movie.new()
	_swap(movie)
	movie.play(20)
	movie.finished.connect(_title)
func _title() -> void:
	if mode == "ATTRACT":
		mode = ""
	music.play_track("title")
	var title := Title.new()
	title.chosen.connect(_mode)
	title.entered.connect(func(): music.play_track("none"))
	title.idle.connect(_attract)
	_swap(title)
func _attract() -> void:
	var first := randi() % 20
	var second := randi() % 20
	mode = "ATTRACT"
	var home := _home(second)
	music.play_track("title")
	var intro := VsScreen.new()
	intro.setup([first, second], [ROSTER_TO_CHARACTER[first], ROSTER_TO_CHARACTER[second]], 1, true)
	_swap(intro)
	intro.finished.connect(func():
		var view := FightView.new()
		_swap(view)
		view.finished.connect(func(_w): _records())
		view.start([_model_for(ROSTER_TO_CHARACTER[first]), _model_for(ROSTER_TO_CHARACTER[second])], home["stage"] % 15, [first, second], true, false, {"demo": true}))
func _records() -> void:
	music.preview(6, false)
	var page := RecordsScreen.new(attract_page)
	attract_page += 1
	page.finished.connect(_namco_again)
	_swap(page)
func _namco_again() -> void:
	music.play_track("none")
	var namco := NamcoScreen.new()
	_swap(namco)
	namco.finished.connect(_title)
func _mode(item: String) -> void:
	if item == "QUIT GAME":
		get_tree().quit()
	elif item == "THEATER MODE":
		_theater_menu(0)
	elif item == "OPTION MODE":
		var options := OptionsScreen.new()
		options.done.connect(_title)
		_swap(options)
	elif item in PLAYABLE:
		mode = item
		ladder = 1
		teams = [[], []]
		_select()
func _select() -> void:
	music.play_track("select")
	var select := CharacterSelect.new()
	select.solo = mode in ["ARCADE MODE", "TIME ATTACK MODE", "SURVIVAL MODE", "TEKKEN BALL MODE", "TEKKEN FORCE MODE"]
	select.chosen.connect(_start_fight)
	_swap(select)
func _model_for(character: int, variant: int = 0) -> int:
	var seen := 0
	for id in range(71, 276, 4):
		var file := FileAccess.open("res://assets/bns/%03d.bin" % (id + 3), FileAccess.READ)
		file.seek(1)
		if file.get_8() == character:
			if seen == variant:
				return id
			seen += 1
	return 71
func _theater_menu(start: int) -> void:
	mode = "THEATER"
	var menu := TheaterScreen.new(start)
	menu.back.connect(_leave_theater)
	menu.music.connect(_music_player.bind(0, true))
	menu.play.connect(func(movie: int): _theater(movie, menu.cursor))
	_swap(menu)
func _music_player(start: int, remixed: bool) -> void:
	var player := MusicPlayer.new(start, remixed)
	player.play.connect(func(song: int, mode: bool): music.preview(song, mode))
	player.theater.connect(func(): music.play_track("none"); _theater_menu(0))
	player.back.connect(func(): music.play_track("none"); _leave_theater())
	_swap(player)
func _leave_theater() -> void:
	mode = ""
	_title()
func _theater(index: int, cursor: int = 0) -> void:
	var movie := Movie.new()
	_swap(movie)
	movie.play(index)
	movie.finished.connect(func(): _theater_menu(cursor))
	mode = "THEATER"
func _start_fight(first: int, second: int) -> void:
	if mode == "TEAM BATTLE MODE":
		_team_pick(first, second)
		return
	picked = [first, second]
	ladder = 1
	frames = 0
	wins = 0
	carry = [1.0, 1.0]
	used = [first]
	if mode in ["ARCADE MODE", "TIME ATTACK MODE", "SURVIVAL MODE"]:
		Save.record_play(first)
	match mode:
		"VS MODE":
			_fight(first, second, true)
		"PRACTICE MODE":
			_fight(first, second, false, true)
		"TEKKEN BALL MODE":
			var pick := BallSelect.new()
			pick.chosen.connect(func(kind: int): ball_kind = kind; _fight(first, _random_opponent(), false, false, {"ball": kind}))
			pick.back.connect(_select)
			_swap(pick)
		"TEKKEN FORCE MODE":
			var run := ForceFlow.new()
			add_child(run)
			run.done.connect(func(): run.queue_free(); _title())
			run.begin(self, _model_for(ROSTER_TO_CHARACTER[first]), ROSTER_TO_CHARACTER[first], first)
		"SURVIVAL MODE":
			_fight(first, _random_opponent(), false, false, {"rounds": 1})
		_:
			_fight(first, _opponent(), false, false)
func _random_opponent() -> int:
	var pool := range(20).filter(func(c): return not used.has(c))
	if pool.is_empty():
		used = [picked[0]]
		pool = range(20).filter(func(c): return c != picked[0])
	var pick: int = pool[randi() % pool.size()]
	used.append(pick)
	return pick
func _opponent() -> int:
	return 20 if ladder >= LADDER - 1 else _random_opponent()
func _team_pick(first: int, second: int) -> void:
	teams[0].append(first)
	teams[1].append(second)
	if teams[0].size() < TEAM_SIZE:
		_select()
		return
	members = [0, 0]
	carry = [1.0, 1.0]
	_team_fight()
func _team_fight() -> void:
	_fight(teams[0][members[0]], teams[1][members[1]], true, false, {"rounds": 1, "fractions": carry.duplicate()})
func _summary(lines: Array, next: Callable) -> void:
	var screen := Results.new()
	screen.show_lines(lines)
	screen.done.connect(next)
	_swap(screen)
func _clock(count: int) -> String:
	var seconds := count / 60
	return "%02d'%02d\"%02d" % [seconds / 60, seconds % 60, (count % 60) * 100 / 60]
func _finish_run() -> void:
	var character: int = picked[0]
	var ending: int = ENDING_MOVIE[picked[0]]
	var lines := ["CONGRATULATIONS"]
	if mode == "TIME ATTACK MODE":
		lines.append("TIME " + _clock(frames))
		if Save.record_time(character, frames):
			lines.append("NEW RECORD")
	var fresh := Save.record_clear(character)
	for r in fresh:
		lines.append("NEW CHARACTER")
		lines.append(_roster_name(r))
	var after := func(): _summary(lines, _title)
	if FileAccess.file_exists("res://assets/movies/%02d.ogv" % ending):
		var movie := Movie.new()
		_swap(movie)
		movie.play(ending)
		movie.finished.connect(after)
	else:
		after.call()
func _roster_name(roster: int) -> String:
	if exe == null:
		exe = Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
	return exe.cstring(exe.u32(exe.u32(0x80097d40 + roster * 16)))
func _after(winner: int) -> void:
	var sim = current.sim
	frames += sim.elapsed
	match mode:
		"ARCADE MODE", "TIME ATTACK MODE":
			if winner == 0 and ladder < LADDER:
				ladder += 1
				_fight(picked[0], _opponent(), false, false)
			elif winner == 0:
				_finish_run()
			else:
				var again := ContinueScreen.new()
				again.view = current
				again.decided.connect(func(go: bool):
					again.queue_free()
					_fight(picked[0], opponent, false, false) if go else _summary(["GAME OVER"], _title))
				current.continue_scene()
				holder.add_child(again)
		"SURVIVAL MODE":
			if winner == 0:
				wins += 1
				carry[0] = minf(1.0, sim.fraction(0) + SURVIVAL_RECOVERY)
				_fight(picked[0], _random_opponent(), false, false, {"rounds": 1, "fractions": carry.duplicate()})
			else:
				var lines := ["GAME OVER", "%d WINS" % wins]
				if Save.record_survival(wins, picked[0]):
					lines.append("NEW RECORD")
				_summary(lines, _title)
		"TEAM BATTLE MODE":
			var loser := 1 - winner if winner >= 0 else 0
			carry[winner] = maxf(sim.fraction(winner), 0.05)
			members[loser] += 1
			carry[loser] = 1.0
			if members[loser] >= TEAM_SIZE:
				_summary(["PLAYER %d WINS" % (winner + 1)], _title)
			else:
				_team_fight()
		_:
			_title()
func _home(roster: int) -> Dictionary:
	if exe == null:
		exe = Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
	var record: int = exe.u32(0x80097d40 + roster * 16)
	return {"stage": exe.u8(record + 10), "song": exe.u8(record + 11)}
func _fight(first: int, second: int, versus: bool = false, practice: bool = false, options: Dictionary = {}) -> void:
	if mode == "ATTRACT":
		_begin_fight(first, second, versus, practice, options)
		return
	var screen := VsScreen.new()
	screen.setup([first, second], [ROSTER_TO_CHARACTER[first], ROSTER_TO_CHARACTER[second]], ladder if mode in ["ARCADE MODE", "TIME ATTACK MODE"] else 0)
	_swap(screen)
	screen.finished.connect(func(): _begin_fight(first, second, versus, practice, options))
func _begin_fight(first: int, second: int, versus: bool, practice: bool, options: Dictionary) -> void:
	opponent = second
	if mode == "ARCADE MODE" or mode == "TIME ATTACK MODE":
		options["stage"] = ladder
		options["base"] = frames
	var home := _home(second)
	if mode in ["ARCADE MODE", "TIME ATTACK MODE", "SURVIVAL MODE"]:
		options["solo"] = true
	music.play_song(home["song"])
	var view := FightView.new()
	_swap(view)
	view.finished.connect(_after)
	view.quit.connect(_select)
	var variant := 1 if mode in ["ARCADE MODE", "TIME ATTACK MODE"] and ladder == LADDER and second == 20 else 0
	view.start([_model_for(ROSTER_TO_CHARACTER[first]), _model_for(ROSTER_TO_CHARACTER[second], variant)], home["stage"] % 15, [first, second], versus, practice, options)
func _unhandled_input(event: InputEvent) -> void:
	if mode == "ATTRACT" and (current is FightView or current is VsScreen) and event.is_pressed() and not event.is_echo() and (event is InputEventKey or event is InputEventJoypadButton):
		mode = ""
		_title()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		widescreen = not widescreen
		_aspect()
	if event.is_action_pressed("menu_back"):
		if current is FightView:
			return
		elif current is Movie and mode == "THEATER":
			_theater_menu(0)
		elif current is CharacterSelect:
			_title()
