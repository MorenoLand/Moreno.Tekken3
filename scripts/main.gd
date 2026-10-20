extends Control
const CharacterSelect := preload("res://scripts/menu/character_select.gd")
const FightView := preload("res://scripts/fight/fight_view.gd")
const ROSTER_TO_CHARACTER := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 19, 17, 18, 20]
var current: Control
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_select()
func _swap(next: Control) -> void:
	if current != null:
		current.queue_free()
	current = next
	next.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(next)
func _select() -> void:
	var select := CharacterSelect.new()
	select.chosen.connect(_fight)
	_swap(select)
func _model_for(character: int) -> int:
	for id in range(71, 276, 4):
		var file := FileAccess.open("res://assets/bns/%03d.bin" % (id + 3), FileAccess.READ)
		file.seek(1)
		if file.get_8() == character:
			return id
	return 71
func _fight(first: int, second: int) -> void:
	var view := FightView.new()
	_swap(view)
	view.start([_model_for(ROSTER_TO_CHARACTER[first]), _model_for(ROSTER_TO_CHARACTER[second])])
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_back") and current is FightView:
		_select()
