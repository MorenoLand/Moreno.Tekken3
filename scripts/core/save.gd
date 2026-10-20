extends RefCounted
const PATH := "user://save.cfg"
const ROSTER_TO_CHARACTER := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 19, 17, 18, 20]
# Keys are portrait/roster ids (exe name table order).
const LOCKED_AT_START := {16: 1, 15: 5, 17: 8, 19: 10}
static var data := {"endings": [], "usage": {}, "time_attack": {}, "survival": 0, "clears": 0, "unlock_all": false}
static var loaded := false
static func _load() -> void:
	if loaded:
		return
	loaded = true
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for key in data:
		data[key] = file.get_value("save", key, data[key])
static func save() -> void:
	var file := ConfigFile.new()
	for key in data:
		file.set_value("save", key, data[key])
	file.save(PATH)
static func endings() -> Array:
	_load()
	return data["endings"]
static func required(character: int) -> int:
	return LOCKED_AT_START.get(character, 0)
static func unlocked(roster: int) -> bool:
	_load()
	if data["unlock_all"]:
		return true
	var need := required(roster)
	return need == 0 or data["endings"].size() >= need
static func hint(roster: int) -> String:
	return "CLEAR ARCADE WITH %d CHARACTERS" % required(roster)
static func record_clear(character: int) -> Array:
	_load()
	var before := []
	for r in 21:
		before.append(unlocked(r))
	if not data["endings"].has(character):
		data["endings"].append(character)
	data["clears"] += 1
	data["usage"][str(character)] = int(data["usage"].get(str(character), 0)) + 1
	var fresh := []
	for r in 21:
		if unlocked(r) and not before[r]:
			fresh.append(r)
	save()
	return fresh
static func record_time(character: int, frames: int) -> bool:
	_load()
	var key := str(character)
	var best: int = int(data["time_attack"].get(key, 0))
	if best == 0 or frames < best:
		data["time_attack"][key] = frames
		save()
		return true
	return false
static func record_survival(wins: int) -> bool:
	_load()
	if wins > int(data["survival"]):
		data["survival"] = wins
		save()
		return true
	return false
