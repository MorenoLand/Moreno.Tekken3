extends Control
signal finished
var player := VideoStreamPlayer.new()
func play(index: int) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var stream := VideoStreamTheora.new()
	stream.file = "res://assets/movies/%02d.ogv" % index
	player.stream = stream
	player.expand = true
	player.finished.connect(finished.emit)
	player.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(player)
	player.play()
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_start") or event.is_action_pressed("menu_confirm"):
		player.stop()
		finished.emit()
