extends RefCounted
# The three record pages of the attract loop. Ranks are by character index (the header of the
# character data), the order of the codes below.
const Save := preload("res://scripts/core/save.gd")
const CODES := ["PAU", "LAW", "LEI", "KIN", "YOS", "NIN", "HWO", "XIA", "EDD", "JIN", "JUL", "KUM", "BRY", "HEI", "OGR", "MOK", "GUN", "GON", "ANN", "TIG", "OGR"]
# Fresh save (exe table at 0x80097f4c, value then code, 8 bytes each): best clear time in frames.
const DEFAULT_TIMES := [201600, 190800, 208800, 205200, 183600, 187200, 194400, 180000, 198000, 212400]
const NO_TIME := 359999
# Fresh save (table at 0x80097ff8: character, wins, code): best survival wins, in rank order.
const DEFAULT_SURVIVORS := [[7, 5], [4, 5], [5, 4], [1, 4], [6, 3], [8, 3], [0, 2], [3, 2], [2, 1], [9, 1]]
const PAGES := ["time", "survivors", "characters"]
static func character_of(roster: int) -> int:
	return Save.ROSTER_TO_CHARACTER[roster]
static func roster_of(character: int) -> int:
	return Save.ROSTER_TO_CHARACTER.find(character)
# Every row is {"character": index, "value": number}, best first, at most ten.
static func times() -> Array:
	Save._load()
	var rows := []
	for c in 21:
		var best: int = DEFAULT_TIMES[c] if c < DEFAULT_TIMES.size() else NO_TIME
		var mine: int = int(Save.data["time_attack"].get(str(roster_of(c)), 0))
		if mine > 0 and mine < best:
			best = mine
		rows.append({"character": c, "value": best})
	rows.sort_custom(func(a, b): return a["value"] < b["value"])
	return rows.slice(0, 10)
# A high score table of runs, not a best per character: a run is inserted before the first entry with fewer wins
# (so an equal score ranks below the older one) and the tenth falls off (exe 0x800b47dc).
static func survivors() -> Array:
	Save._load()
	var rows := []
	for entry in DEFAULT_SURVIVORS:
		rows.append({"character": entry[0], "value": entry[1]})
	for run in Save.data["survivor_runs"]:
		var at := 0
		while at < rows.size() and rows[at]["value"] >= int(run[1]):
			at += 1
		if at < rows.size():
			rows.insert(at, {"character": character_of(int(run[0])), "value": int(run[1])})
			rows.pop_back()
	return rows
# Share of all arcade clears, in percent, per character.
static func usage() -> Array:
	Save._load()
	var total := 0
	for key in Save.data["usage"]:
		total += int(Save.data["usage"][key])
	var rows := []
	for c in 21:
		var count := int(Save.data["usage"].get(str(roster_of(c)), 0))
		rows.append({"character": c, "value": 0 if total == 0 else count * 100 / total, "count": count})
	var indexed := []
	for i in rows.size():
		indexed.append([rows[i], i])
	indexed.sort_custom(func(a, b): return a[0]["count"] > b[0]["count"] or (a[0]["count"] == b[0]["count"] and a[1] < b[1]))
	return indexed.map(func(pair): return pair[0]).slice(0, 10)
static func clock(frames: int) -> Array:
	var seconds := frames / 60
	return [seconds / 60, seconds % 60, (frames % 60) * 100 / 60]
