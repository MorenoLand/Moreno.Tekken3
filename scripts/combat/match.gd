extends RefCounted
const Ram := preload("res://scripts/combat/ram.gd")
const MoveData := preload("res://scripts/combat/move_data.gd")
const Pad := preload("res://scripts/combat/pad.gd")
const MoveStep := preload("res://scripts/combat/move_step.gd")
const FMath := preload("res://scripts/combat/fmath.gd")
const MovePhysics := preload("res://scripts/combat/move_physics.gd")
const Exe := preload("res://scripts/core/exe.gd")
const Motion := preload("res://scripts/fighter/motion.gd")
const ACTORS := 0x800a9228
const STRIDE := 0x188c
const MAX_HEALTH := 0x820000
var ram = Ram.new()
var pads := [0, 0]
var edges := [0, 0]
var motion
func actor(p: int) -> int:
	return ACTORS + p * STRIDE
func setup(exe: PackedByteArray, common: PackedByteArray, first: PackedByteArray, second: PackedByteArray) -> void:
	ram.load_bytes(0x80010000, exe.slice(0x800))
	motion = Motion.new(Exe.new(exe))
	MoveData.place(ram, 2, common)
	MoveData.place(ram, 0, first)
	MoveData.place(ram, 1, second)
	MoveData.relocate(ram, 2)
	MoveData.relocate(ram, 0)
	MoveData.relocate(ram, 1)
	MoveData.merge_tables(ram)
	ram.w32(0x80095484, 1)
	ram.w8(0x800afa93, 1)
	for p in 2:
		var a := actor(p)
		ram.w8(a + 0x1e, p)
		ram.w8(a + 0x1f, 1 - p)
		ram.w8(a + 0x20, 1 - p)
		ram.w16(a + 0x12, p)
		ram.w32(a + 0x3f4, MAX_HEALTH)
		ram.w32(a + 0x3f8, MAX_HEALTH)
		Pad.reset(ram, a)
	for p in 2:
		start_actor(p)
func start_actor(p: int) -> void:
	var a := actor(p)
	var b := actor(1 - p)
	var x: int = -1000 if p == 0 else 1000
	var face: int = 0x4000 if p == 0 else 0xc000
	ram.w32(a + 0x100, 1000)
	ram.w32(a + 0xfc, 1000)
	ram.w32(a + 0xf8, 1000)
	ram.w32(a + 0x12c, ram.u32(a))
	ram.w32(a + 0x130, ram.u32(a + 8))
	ram.w16(a + 0x1a0, 1)
	var row := MoveStep.slot_row(ram, a, 1)
	ram.w32(a + 0x54, row)
	ram.w32(a + 0x4c, row)
	ram.w32(a + 0x1a4, row)
	ram.w16(a + 0x58, 1)
	ram.w16(a + 0x198, 1)
	ram.w16(a + 0x19a, MoveStep.kind_of(ram, a, 0))
	ram.w16(a + 0x19c, 0)
	ram.w16(a + 0x19e, 0)
	ram.w8(a + 0xc3, 1)
	MoveStep.step(ram, a, b)
	ram.w16(a + 0x50, 1)
	ram.w16(a + 0x58, 1)
	ram.w16(a + 0x0e, face)
	ram.w32(a, x)
	ram.w32(a + 4, 0)
	ram.w32(a + 8, 0)
	ram.w16(a + 0x2c, face)
	ram.w16(a + 0x30, face)
	ram.w16(a + 0x1278, 76 if p == 0 else 276)
	ram.w32(a + 0xf68, x)
	ram.w32(a + 0xf70, 0)
func place_root(p: int) -> void:
	var a := actor(p)
	var prev: int = ram.u32(a + 0x4c)
	var frame: int = ram.s16(a + 0x50) - 1
	var stream: int = ram.u32(prev)
	var pose: PackedInt32Array = motion.frame(ram.m, stream - Ram.BASE, maxi(frame, 0))
	ram.w16(a + 0x24, pose[0])
	ram.w16(a + 0x26, pose[1])
	ram.w16(a + 0x28, pose[2])
	var wx: int = ram.s32(a)
	var wy: int = ram.s32(a + 4)
	var wz: int = ram.s32(a + 8)
	var mode: int = ram.u8(a + 0xb8)
	if mode == 0:
		var idx: int = (0x8000 - ram.s16(a + 0xe)) >> 4 & 0xfff
		var c: int = ram.s16(FMath.COS_TABLE + idx * 2)
		var s: int = ram.s16(FMath.SIN_TABLE + idx * 2)
		var x: int = ram.s16(a + 0x24)
		var z: int = ram.s16(a + 0x28)
		var u: int = x * c - z * s
		var v: int = x * s + z * c
		wx += (u + 0xfff if u < 0 else u) >> 12
		wy += ram.s16(a + 0x26)
		wz += (v + 0xfff if v < 0 else v) >> 12
	elif mode == 2:
		wy += ram.s16(a + 0x26)
	ram.w32(a + 0xf68, wx)
	ram.w32(a + 0xf6c, wy)
	ram.w32(a + 0xf70, wz)
func tick() -> void:
	for p in 2:
		var a := actor(p)
		var b := MoveStep.opponent(ram, a)
		ram.w8(a + 0xc6, 1 if ram.s16(b + 0x1278) <= ram.s16(a + 0x1278) else 0)
	for p in 2:
		var a := actor(p)
		MoveStep.step(ram, a, actor(ram.u8(a + 0x1f)))
	MoveStep.update_distances(ram)
	for p in 2:
		MovePhysics.run(ram, actor(p))
	for p in 2:
		place_root(p)
	for p in 2:
		var a := actor(p)
		ram.w16(a + 0x1278, 176 + ram.s32(a + 0xf68) / 10)
	for p in 2:
		var a := actor(p)
		Pad.push(ram, a, ram.u8(a + 0xc6), pads[p], edges[p])
		MoveStep.choose_next(ram, a)
