extends RefCounted
# Controller history ring and button edge tracking kept inside the actor, as the original does.
# Fields are read with ram.u8/u16/u32 at "actor + offset"; offsets are listed at the top of ram.gd.
const DIRECTIONS := 0x80010738
const HISTORY := 0x41c
const EDGE_HISTORY := 0x462
const HISTORY_SIZE := 0x3c
const HELD_DIR_MASK := 0x402
const PRESSED_BUTTONS := 0x404
const HELD_BUTTONS := 0x406
const HISTORY_INDEX := 0x40c
const COMBO_COUNT := 0x410
const COMBO_AGE := 0x414
const COMBO_TIMER := 0x418
const COMBO_BUFFER := 0x458
static func reset(ram, a: int) -> void:
	for i in HISTORY_SIZE:
		ram.w8(a + HISTORY + i, 5)
		ram.w16(a + EDGE_HISTORY + i * 2, 0)
	ram.w16(a + HELD_DIR_MASK, 5)
	ram.w32(a + COMBO_COUNT, 0xffffffff)
	ram.w32(a + COMBO_AGE, 0xffffffff)
	ram.w32(a + HISTORY_INDEX, 0)
	ram.w16(a + HELD_BUTTONS, 0)
	ram.w16(a + PRESSED_BUTTONS, 0)
	for o in [0x4dc, 0x4e0, 0x4e4, 0x4e8]:
		ram.w32(a + o, 0)
	ram.w16(a + 0x408, 0)
static func direction(ram, flip: int, held: int) -> int:
	if flip >= 2:
		return 5
	var table: int = DIRECTIONS + flip * 0x12
	for i in 9:
		if ram.u16(table + i * 2) == (held & 0xf000):
			return i + 1
	return 5
static func push(ram, a: int, flip: int, held: int, edge: int) -> void:
	var index: int = ram.u32(a + HISTORY_INDEX)
	index = index + 1 if index < 0x3b else 0
	ram.w32(a + HISTORY_INDEX, index)
	var dir := direction(ram, flip, held)
	var buttons: int = held >> 3 & 0x10
	if held & 0x10:
		buttons |= 0x20
	if held & 0x40:
		buttons |= 0x40
	if held & 0x20:
		buttons |= 0x80
	ram.w16(a + HELD_BUTTONS, buttons >> 4)
	var edges := 0
	if edge & 0x80:
		edges = 0x10
		ram.w32(a + 0x4dc, ram.s32(a + 0x4dc) + 1)
	if edge & 0x10:
		edges |= 0x20
		ram.w32(a + 0x4e0, ram.s32(a + 0x4e0) + 1)
	if edge & 0x40:
		edges |= 0x40
		ram.w32(a + 0x4e4, ram.s32(a + 0x4e4) + 1)
	if edge & 0x20:
		edges |= 0x80
		ram.w32(a + 0x4e8, ram.s32(a + 0x4e8) + 1)
	ram.w8(a + HISTORY + index, edges | dir)
	ram.w16(a + PRESSED_BUTTONS, edges >> 4)
	ram.w16(a + HELD_DIR_MASK, 1 << (dir + 4))
	var old: int = ram.u16(a + EDGE_HISTORY + index * 2)
	if old & 0x80:
		ram.w32(a + 0x4dc, ram.s32(a + 0x4dc) - 1)
	if old & 0x10:
		ram.w32(a + 0x4e0, ram.s32(a + 0x4e0) - 1)
	if old & 0x40:
		ram.w32(a + 0x4e4, ram.s32(a + 0x4e4) - 1)
	if old & 0x20:
		ram.w32(a + 0x4e8, ram.s32(a + 0x4e8) - 1)
	ram.w16(a + EDGE_HISTORY + index * 2, edge)
	if ram.u32(a + COMBO_COUNT) > 9:
		return
	if ram.s32(a + COMBO_TIMER) > 0:
		ram.w32(a + COMBO_TIMER, ram.s32(a + COMBO_TIMER) - 1)
	if edges == 0:
		return
	if ram.s32(a + COMBO_TIMER) > 0:
		var at: int = a + ram.u32(a + COMBO_COUNT)
		if (buttons & ~edges & 0xff) == (ram.u8(at + COMBO_BUFFER) & 0xf0):
			ram.w8(at + COMBO_BUFFER, buttons + dir)
			ram.w32(a + COMBO_TIMER, 3)
			return
	var next: int = ram.u32(a + COMBO_COUNT) + 1
	if ram.u32(a + COMBO_COUNT) > 8:
		return
	ram.w32(a + COMBO_COUNT, next)
	ram.w8(a + next + COMBO_BUFFER, buttons + dir)
	ram.w32(a + COMBO_TIMER, 3)
