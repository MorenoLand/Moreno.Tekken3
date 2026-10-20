extends AudioStreamPlayer
const Options := preload("res://scripts/core/options.gd")
const Exe := preload("res://scripts/core/exe.gd")
const TRACKS := {"title": "res://assets/audio/xa/c2_1.ogg"}
const SONG_TABLE := 0x80024fd0
const XA_TABLE := 0x80024d78
const XA_BASE := 604
const SELECT_SONG := 1
var playing_name := ""
var exe
var index := {}
func _exe():
	if exe == null:
		exe = Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02"))
		var text := FileAccess.get_file_as_string("res://assets/audio/xa/index.json").trim_prefix("﻿")
		index = JSON.parse_string(text) if text != "" else {}
	return exe
func _track_path(table_index: int) -> String:
	var e = _exe()
	var start: int = e.u32(XA_TABLE + table_index * 12) + XA_BASE
	var end: int = e.u32(XA_TABLE + table_index * 12 + 4) + XA_BASE
	for name in index:
		if absi(index[name][0] - start) <= 8 and absi(index[name][1] - end) <= 8:
			return "res://assets/audio/xa/%s.ogg" % name
	return ""
func play_song(song: int) -> void:
	var key := "song%d" % song
	if key == playing_name:
		return
	playing_name = key
	var e = _exe()
	var at: int = SONG_TABLE + song * 4 + (2 if Options.get_value("bgm") == 1 else 0)
	var entry: int = e.u8(at)
	var flags: int = e.u8(at + 1)
	if Options.get_value("bgm") == 2 or (entry & 0x80) != 0:
		stop()
		return
	_play(_track_path(entry), (flags & 0x7f) / 127.0)
func play_track(track: String) -> void:
	if track == "select":
		play_song(SELECT_SONG)
		return
	if track == playing_name:
		return
	playing_name = track
	if Options.get_value("bgm") == 2 or not TRACKS.has(track):
		stop()
		return
	_play(TRACKS[track], 1.0)
func _play(path: String, gain: float) -> void:
	if path == "" or not FileAccess.file_exists(path):
		stop()
		return
	var ogg := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	ogg.loop = true
	stream = ogg
	volume_db = linear_to_db(maxf(gain, 0.05))
	play()
