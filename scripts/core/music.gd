extends AudioStreamPlayer
const TRACKS := {"title": "res://assets/movies/20.ogg", "select": "res://assets/audio/xa/c3_4.ogg", "fight": "res://assets/audio/xa/c0_0.ogg"}
var playing_name := ""
func play_track(track: String) -> void:
	if track == playing_name:
		return
	playing_name = track
	var path: String = TRACKS[track]
	if not FileAccess.file_exists(path):
		stop()
		return
	var ogg := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	ogg.loop = true
	stream = ogg
	play()
