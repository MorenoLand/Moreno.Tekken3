extends RefCounted
# Tekken Force data read from the disc: the mode overlay (archive record 7, loaded by the game at 0x800b0548),
# the stage archives (records 51..55) and the exe tables the overlay code indexes.
const BNS := "res://assets/bns/"
const OVERLAY := 0x800b0548
const STAGE_COUNT := 4
const FINAL_STAGE := 4
const FIRST_STAGE_RECORD := 51
const GROUP_TABLE := 0x800b0548
const KILL_SECONDS := 0x800b0672
const HEALTH_TABLE := 0x800b0684
const COSTUME_TABLE := 0x800b06e8
const PAR_TIME := 0x800b06f4
const CLEAR_BONUS := 0x800b0708
const FIRST_ENEMY_COSTUME := 0x54
const ITEM_HEAL := 0x320000
var overlay := PackedByteArray()
func _init() -> void:
	overlay = FileAccess.get_file_as_bytes(BNS + "007.bin")
func s16(va: int) -> int:
	return overlay.decode_s16(va - OVERLAY)
func u16(va: int) -> int:
	return overlay.decode_u16(va - OVERLAY)
func s32(va: int) -> int:
	return overlay.decode_s32(va - OVERLAY)
func u32(va: int) -> int:
	return overlay.decode_u32(va - OVERLAY)
func record(stage: int) -> String:
	return "%s%03d/" % [BNS, FIRST_STAGE_RECORD + stage]
func health(stage: int, level: int) -> int:
	return u32(HEALTH_TABLE + stage * 20 + level * 4)
func kill_seconds(level: int) -> int:
	return u16(KILL_SECONDS + level * 4)
func costume(stage: int, id: int) -> int:
	return FIRST_ENEMY_COSTUME + overlay[COSTUME_TABLE + (stage & 3) * 2 + (id & 1) - OVERLAY]
func par_time(stage: int) -> int:
	return s32(PAR_TIME + stage * 4)
func clear_bonus(stage: int) -> int:
	return s32(CLEAR_BONUS + stage * 4)
func group_entry(index: int) -> Vector2i:
	return Vector2i(s16(GROUP_TABLE + index * 6), s16(GROUP_TABLE + index * 6 + 2))
func script(stage: int) -> Array:
	var raw := FileAccess.get_file_as_bytes(record(stage) + "03.bin")
	var out := []
	for i in raw.size() / 20:
		var o := i * 20
		var e := {"at": raw.decode_s32(o), "type": raw.decode_u16(o + 4), "x": raw.decode_s16(o + 6), "z": raw.decode_s16(o + 10), "p": raw.decode_s16(o + 14), "q": raw.decode_s16(o + 16)}
		out.append(e)
		if e["type"] == 6:
			break
	return out
func floor_map(stage: int) -> Dictionary:
	var raw := FileAccess.get_file_as_bytes(record(stage) + "02.bin")
	var w := raw.decode_u16(0)
	var h := raw.decode_u16(2)
	var tiles := PackedInt32Array()
	var cluts := PackedInt32Array()
	for i in w * h:
		tiles.append(raw.decode_u16(4 + i * 2))
		cluts.append(raw.decode_u16(4 + (w * h + i) * 2))
	return {"w": w, "h": h, "tiles": tiles, "cluts": cluts}
func tile_images(stage: int) -> Array:
	var raw := FileAccess.get_file_as_bytes(record(stage) + "00.bin")
	var count := raw.decode_u32(0)
	return Tim.stream(raw.slice(raw.decode_u32(4)))
const Tim := preload("res://scripts/fighter/tim.gd")
