extends RefCounted
const PATH := "user://options.cfg"
const DEFAULTS := {"difficulty": 1, "fights": 1, "time": 2, "guard": 1, "change": 1, "hold": 1, "quick": 1, "speaker": 0, "bgm": 0, "music": 100, "sfx": 100, "vibration": 1}
const TIMES := [60, 50, 40, 30, 20]
static var values := {}
static var keys := {}
static var loaded := false
static func _load() -> void:
	if loaded:
		return
	loaded = true
	values = DEFAULTS.duplicate()
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for key in DEFAULTS:
		values[key] = int(file.get_value("game", key, DEFAULTS[key]))
	for section in file.get_sections():
		if section.begins_with("keys"):
			keys[section] = {}
			for name in file.get_section_keys(section):
				keys[section][name] = int(file.get_value(section, name))
static func get_value(key: String) -> int:
	_load()
	return values[key]
static func set_value(key: String, value: int) -> void:
	_load()
	values[key] = value
	save()
static func key_for(player: int, name: String, fallback: int) -> int:
	_load()
	return keys.get("keys%d" % player, {}).get(name, fallback)
static func set_key(player: int, name: String, code: int) -> void:
	_load()
	if not keys.has("keys%d" % player):
		keys["keys%d" % player] = {}
	keys["keys%d" % player][name] = code
	save()
static func reset_keys() -> void:
	_load()
	keys.clear()
	save()
static func save() -> void:
	var file := ConfigFile.new()
	for key in values:
		file.set_value("game", key, values[key])
	for section in keys:
		for name in keys[section]:
			file.set_value(section, name, keys[section][name])
	file.save(PATH)
static func rounds_to_win() -> int:
	return get_value("fights") + 1
static func round_frames() -> int:
	return TIMES[get_value("time")] * 60
