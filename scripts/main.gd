extends Control
const Movie := preload("res://scripts/menu/movie_screen.gd")
const Title := preload("res://scripts/menu/title.gd")
const CharacterSelect := preload("res://scripts/menu/character_select.gd")
const FightView := preload("res://scripts/fight/fight_view.gd")
const ROSTER_TO_CHARACTER := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 19, 17, 18, 20]
const PLAYABLE := ["ARCADE MODE", "VS MODE", "TEAM BATTLE MODE", "TIME ATTACK MODE", "SURVIVAL MODE", "PRACTICE MODE", "TEKKEN BALL MODE", "TEKKEN FORCE MODE"]
const Music := preload("res://scripts/core/music.gd")
var music := Music.new()
var current: Control
var mode := ""
var ladder := 1
var picked := [0, 0]
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
func _model_for(character: int) -> int:
	for id in range(71, 276, 4):
		var file := FileAccess.open("res://assets/bns/%03d.bin" % (id + 3), FileAccess.READ)
		file.seek(1)
		if file.get_8() == character:
			return id
	return 71
func _theater(index: int) -> void:
	var movie := Movie.new()
	_swap(movie)
	movie.play(index)
	movie.finished.connect(func(): _theater((index + 1) % 22) if mode == "THEATER" else _title())
	mode = "THEATER"
func _start_fight(first: int, second: int) -> void:
	picked = [first, second]
	_fight(first, second, mode == "VS MODE", mode == "PRACTICE MODE")
func _after(winner: int) -> void:
	if mode == "ARCADE MODE" and winner == 0 and ladder < 8:
		ladder += 1
		_fight(picked[0], randi() % 21)
	else:
		_title()
func _fight(first: int, second: int, versus: bool = false, practice: bool = false) -> void:
	music.play_track("fight")
	var view := FightView.new()
	_swap(view)
	view.finished.connect(_after)
	view.start([_model_for(ROSTER_TO_CHARACTER[first]), _model_for(ROSTER_TO_CHARACTER[second])], randi() % 15, [first, second], versus, practice)
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
