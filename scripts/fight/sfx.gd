extends Node
var banks: Array = []
var voices: Array = []
func load_bank(model_id: int) -> Array:
	var out: Array = []
	for i in range(1, 19):
		var path := "res://assets/audio/vab/%03d/%02d.wav" % [model_id + 1, i]
		if FileAccess.file_exists(path):
			out.append(AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path)))
	return out
func setup(ids: Array) -> void:
	for id in ids:
		banks.append(load_bank(id))
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)
func play(player: int, first: int, last: int) -> void:
	var bank: Array = banks[player]
	if bank.is_empty():
		return
	var index := first + randi() % maxi(1, mini(last, bank.size() - 1) - first + 1)
	for v in voices:
		if not v.playing:
			v.stream = bank[mini(index, bank.size() - 1)]
			v.play()
			return
