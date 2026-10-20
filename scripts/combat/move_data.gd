extends RefCounted
# Loads a fighter data record into RAM and fixes up its pointers the way the original loader does.
# Fields are read with ram.u8/u16/u32 at "actor + offset"; offsets are listed at the top of ram.gd.
const CHAR_PTR := 0x800adc20
const COMMON_PTR := 0x800adc28
const SLOT_BASE := [0x80300000, 0x80380000]
const COMMON_BASE := 0x80400000
const ENTRY_TABLE := 0x80017c10
const MOVE_IDS := 0xfb7
const ROW_SIZE := 0x38
static func place(ram, slot: int, bytes: PackedByteArray) -> int:
	var base: int = COMMON_BASE if slot == 2 else SLOT_BASE[slot]
	ram.load_bytes(base, bytes)
	for o in range(4, 0x38, 4):
		var v: int = ram.u32(base + o)
		ram.w32(base + o, v + base)
	ram.w32(COMMON_PTR if slot == 2 else CHAR_PTR + slot * 4, base)
	return base
static func relocate(ram, slot: int) -> void:
	var base: int = ram.u32(COMMON_PTR) if slot == 2 else ram.u32(CHAR_PTR + slot * 4)
	if ram.u8(base) != 0:
		return
	var common: int = ram.u32(COMMON_PTR)
	var row: int = ram.u32(base + 8)
	var count: int = ram.s16(base + 2)
	for r in count:
		var w0: int = ram.u32(row)
		var streams: int = ram.u32(base + 0x1c) if w0 < 0x40000000 else ram.u32(common + 0x1c) - 0x40000000
		var stream: int = (w0 + streams) & 0xffffffff
		ram.w32(row, stream)
		var w10: int = ram.u32(row + 0x28)
		ram.w8(row + 0x18, ram.u8(stream))
		ram.w32(row + 0xc, ram.u32(base + 4) + ram.u32(row + 0xc) * 12)
		if w10 < 0x80000000:
			var found := 0
			for i in 13:
				var e: int = ENTRY_TABLE + i * 8
				if ram.u16(e) == w10:
					found = ram.u32(e + 4)
					break
			ram.w32(row + 0x28, found if found != 0 else w10 - 4 + ram.u32(base + 0x28))
		var w8: int = ram.u32(row + 0x20)
		if w8 == 0xffffffff:
			ram.w32(row + 0x20, 0)
		else:
			ram.w32(row + 0x20, ram.u32(base + 0x14) + w8 * 4)
			ram.w16(row + 0x14, frame_total(ram, row))
		var w7: int = ram.u32(row + 0x1c)
		ram.w32(row + 0x1c, 0 if w7 == 0xffffffff else ram.u32(base + 0x10) + w7 * 2)
		row += ROW_SIZE
	if slot < 2:
		var table: int = ram.u32(base + 0xc)
		var rows: int = ram.u32(base + 8)
		var common_rows: int = ram.u32(common + 8)
		for i in MOVE_IDS:
			var v: int = ram.u32(table + i * 4)
			var origin: int = rows if v < 0x40000000 else common_rows
			ram.w32(table + i * 4, origin + (v - (0 if v < 0x40000000 else 0x40000000)) * ROW_SIZE)
	ram.w8(base, 1)
static func frame_total(ram, row: int) -> int:
	var list: int = ram.u32(row + 0x20)
	var total: int = ram.s16(row + 0x14)
	while ram.s16(list) != 0:
		if ram.u16(list + 2) >> 8 == 0xb:
			total = ((total + (ram.u16(list + 2) & 0xff)) << 16 >> 16)
		list += 4
	return total
static func merge_tables(ram) -> void:
	var base0: int = ram.u32(CHAR_PTR)
	var base1: int = ram.u32(CHAR_PTR + 4)
	var t0: int = ram.u32(base0 + 0xc)
	var t1: int = ram.u32(base1 + 0xc)
	var m0: int = ram.u32(base0 + 0x18)
	var m1: int = ram.u32(base1 + 0x18)
	var d0: int = ram.u32(t0 + 0xdc5 * 4)
	var d1: int = ram.u32(t1 + 0xdc5 * 4)
	var w0: int = ram.u16(m0) | 0x10000
	var w1: int = ram.u16(m1) | 0x10000
	var p0: int = m0 + 2
	var p1: int = m1 + 2
	for i in MOVE_IDS:
		if w0 & 1:
			ram.w32(t0 + i * 4, ram.u32(t1 + i * 4) if (w1 & 1) == 0 else d0)
		if w1 & 1:
			ram.w32(t1 + i * 4, ram.u32(t0 + i * 4) if (w0 & 1) == 0 else d1)
		w0 >>= 1
		w1 >>= 1
		if w0 == 1:
			w0 = ram.u16(p0) | 0x10000
			p0 += 2
			w1 = ram.u16(p1) | 0x10000
			p1 += 2
