extends Control
const Movie := preload("res://scripts/menu/movie_screen.gd")
const Title := preload("res://scripts/menu/title.gd")
const CharacterSelect := preload("res://scripts/menu/character_select.gd")
const FightView := preload("res://scripts/fight/fight_view.gd")
const ROSTER_TO_CHARACTER := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 19, 17, 18, 20]
const PLAYABLE := ["ARCADE MODE", "VS MODE", "TEAM BATTLE MODE", "TIME ATTACK MODE", "SURVIVAL MODE", "PRACTICE MODE"]
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
var holder := AspectRatioContainer.new()
var widescreen := true
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	add_child(music)
	get_viewport().size_changed.connect(_aspect)
	_aspect()
	_intro()
func _aspect() -> void:
	var window := get_viewport().get_visible_rect().size
	holder.ratio = window.x / window.y if widescreen else 4.0 / 3.0
func _swap(next: Control) -> void:
	if current != null:
		current.queue_free()
	current = next
	holder.add_child(next)
func _intro() -> void:
	if not FileAccess.file_exists("res://assets/movies/20.ogv"):
		_title()
		return
	var movie := Movie.new()
	_swap(movie)
	movie.play(20)
	movie.finished.connect(_title)
func _title() -> void:
	music.play_track("title")
	var title := Title.new()
	title.chosen.connect(_mode)
	_swap(title)
func _mode(item: String) -> void:
	if item == "QUIT GAME":
		get_tree().quit()
	elif item == "THEATER MODE":
		_theater(0)
	elif item == "OPTION MODE":
		_title()
	elif item in PLAYABLE:
		mode = item
		ladder = 1
		_select()
func _select() -> void:
	music.play_track("select")
	var select := CharacterSelect.new()
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
func _theater(index: int) -> void:
	var movie := Movie.new()
	_swap(movie)
	movie.play(index)
	movie.finished.connect(func(): _theater((index + 1) % 22) if mode == "THEATER" else _title())
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
	match mode:
		"VS MODE":
			_fight(first, second, true)
		"PRACTICE MODE":
			_fight(first, second, false, true)
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
func _after(winner: int) -> void:
	var sim = current.sim
	frames += sim.elapsed
	match mode:
		"ARCADE MODE", "TIME ATTACK MODE":
			if winner == 0 and ladder < LADDER:
				ladder += 1
				_fight(picked[0], _opponent(), false, false)
			elif winner == 0:
				_summary(["CONGRATULATIONS", "TIME " + _clock(frames)] if mode == "TIME ATTACK MODE" else ["CONGRATULATIONS"], _title)
			else:
				_summary(["GAME OVER"], _title)
		"SURVIVAL MODE":
			if winner == 0:
				wins += 1
				carry[0] = minf(1.0, sim.fraction(0) + SURVIVAL_RECOVERY)
				_fight(picked[0], _random_opponent(), false, false, {"rounds": 1, "fractions": carry.duplicate()})
			else:
				_summary(["GAME OVER", "%d WINS" % wins], _title)
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
func _fight(first: int, second: int, versus: bool = false, practice: bool = false, options: Dictionary = {}) -> void:
	music.play_track("fight")
	var view := FightView.new()
	_swap(view)
	view.finished.connect(_after)
	var variant := 1 if mode in ["ARCADE MODE", "TIME ATTACK MODE"] and ladder == LADDER and second == 20 else 0
	view.start([_model_for(ROSTER_TO_CHARACTER[first]), _model_for(ROSTER_TO_CHARACTER[second], variant)], randi() % 15, [first, second], versus, practice, options)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		widescreen = not widescreen
		_aspect()
	if event.is_action_pressed("menu_back"):
		if current is FightView:
			_select()
		elif current is Movie and mode == "THEATER":
			mode = ""
			_title()
		elif current is CharacterSelect:
			_title()
