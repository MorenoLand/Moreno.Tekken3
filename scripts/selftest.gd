extends SceneTree

const WavLoader := preload("res://scripts/wav_loader.gd")


func _init() -> void:
	var s = WavLoader.load_file("res://assets/audio/cdda/track02.wav")
	print("track02 length ", s.get_length() if s else -1)
	var v = WavLoader.load_file("res://assets/audio/vab/072/01.wav")
	print("vab sample length ", v.get_length() if v else -1)
	quit()
