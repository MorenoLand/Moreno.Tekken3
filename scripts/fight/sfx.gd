extends Node
const LEVELS := [45, 70, 77, 81, 84, 88, 92, 96, 100, 104, 108, 112, 115, 119, 123, 127]
var models: Array = []
var voices: Array = []
var tones := {}
var streams := {}
func setup(ids: Array) -> void:
	models = ids
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)
func _folder(player: int, bank: int) -> String:
	return "res://assets/audio/common/%d/" % bank if bank < 3 else "res://assets/audio/vab/%03d/" % (models[player] + 1)
func _tones(folder: String) -> Array:
	if not tones.has(folder):
		var file := FileAccess.open(folder + "tones.json", FileAccess.READ)
		tones[folder] = JSON.parse_string(file.get_as_text()) if file != null else []
	return tones[folder]
func _stream(path: String) -> AudioStreamWAV:
	if not streams.has(path):
		streams[path] = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
	return streams[path]
func play_entry(player: int, entry: int) -> void:
	var bank: int = (entry >> 14) & 3
	if bank == 0:
		return
	var folder := _folder(player, bank)
	var list := _tones(folder)
	var program: int = (entry >> 4) & 3
	var note: int = 0x3c + (entry & 15)
	if program >= list.size():
		return
	for tone in list[program]:
		if note >= tone["min"] and note <= tone["max"]:
			var stream := _stream(folder + "%02d.wav" % int(tone["vag"]))
			if stream == null:
				return
			for v in voices:
				if not v.playing:
					v.stream = stream
					v.pitch_scale = clampf(pow(2.0, (note - int(tone["center"]) + int(tone["shift"]) / 128.0) / 12.0), 0.05, 8.0)
					v.volume_db = linear_to_db(LEVELS[(entry >> 6) & 15] / 127.0 * int(tone["vol"]) / 127.0)
					v.play()
					return
			return
