extends RefCounted
const Ram := preload("res://scripts/combat/ram.gd")
const MoveData := preload("res://scripts/combat/move_data.gd")
const Pad := preload("res://scripts/combat/pad.gd")
const MoveStep := preload("res://scripts/combat/move_step.gd")
const FMath := preload("res://scripts/combat/fmath.gd")
const MovePhysics := preload("res://scripts/combat/move_physics.gd")
const Exe := preload("res://scripts/core/exe.gd")
const Motion := preload("res://scripts/fighter/motion.gd")
const Skeleton := preload("res://scripts/fighter/skeleton.gd")
const Volumes := preload("res://scripts/combat/hit_volumes.gd")
const Hits := preload("res://scripts/combat/hits.gd")
const BodyPush := preload("res://scripts/combat/body_push.gd")
const Damage := preload("res://scripts/combat/damage.gd")
const ACTORS := 0x800a9228
const STRIDE := 0x188c
const MAX_HEALTH := 0x820000
var ram = Ram.new()
var pads := [0, 0]
var edges := [0, 0]
var motion
var computer := [false, true]
var trace := false
var skeleton
var models: Array = []
const JOINTS := 0x8f4
const JOINT_SIZE := 0x44
func actor(p: int) -> int:
	return ACTORS + p * STRIDE
func setup(exe: PackedByteArray, common: PackedByteArray, first: PackedByteArray, second: PackedByteArray, first_model: PackedByteArray, second_model: PackedByteArray) -> void:
	ram.load_bytes(0x80010000, exe.slice(0x800))
	motion = Motion.new(Exe.new(exe))
	skeleton = Skeleton.new(Exe.new(exe))
	models = [first_model, second_model]
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
		ram.w8(a + 0xc5, 1 if computer[p] else 0)
		var scale: int = (models[p].decode_u32(4) << 12) / 100
		ram.w16(a + 0x4ec, scale)
		ram.w16(a + 0x4ee, scale)
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
	var scale: int = ram.s16(a + 0x4ee)
	ram.w16(a + 0x24, pose[0] * scale >> 12)
	ram.w16(a + 0x26, pose[1] * scale >> 12)
	ram.w16(a + 0x28, pose[2] * scale >> 12)
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
func update_joints(p: int) -> void:
	var a := actor(p)
	var row: int = ram.u32(a + 0x54)
	var frame: int = maxi(ram.s16(a + 0x58) - 1, 0)
	var pose: PackedInt32Array = motion.frame(ram.m, ram.u32(row) - Ram.BASE, frame)
	var psi: int = (ram.s16(a + 0x2c) - 0x8000) >> 4 & 0xfff
	var c: int = ram.s16(FMath.COS_TABLE + psi * 2)
	var s: int = ram.s16(FMath.SIN_TABLE + psi * 2)
	var world: Dictionary = skeleton.world(models[p], pose, [c, 0, s, 0, 4096, 0, -s, 0, c], [ram.s32(a + 0xf68), ram.s32(a + 0xf6c), ram.s32(a + 0xf70)])
	for slot in 18:
		var at: int = a + JOINTS + slot * JOINT_SIZE
		var m: Array = world[slot][0]
		for i in 9:
			ram.w16(at + i * 2, m[i])
		var t: Array = world[slot][1]
		for i in 3:
			ram.w32(at + 0x14 + i * 4, t[i])
func push_radii(a: int) -> void:
	var row: int = ram.u32(a + 0x54)
	var rule: int = ram.u16(row + 0x30)
	var table: int = ram.u32(0x80096f60 + ram.s16(a + 0x18) * 4)
	var set_all := false
	var low: int = rule & 0xf
	var radii: Array = []
	for k in 8:
		radii.append(ram.s16(table + k * 2))
	if low == 0:
		var off := false
		if (rule >> 12 & 1) == 0 or ram.u8(row + 0x2d) == 0:
			off = true
		elif ram.u8(row + 0x2d) - 8 < ram.s16(a + 0x58):
			off = ram.s16(a + 0x58) < ram.u8(row + 0x2e)
		for k in 8:
			if off and ((FMath.s16(rule) >> (k + 4)) & 1) != 0:
				ram.w16(a + 0x330 + k * 0x10, 0)
			else:
				ram.w16(a + 0x330 + k * 0x10, radii[k])
	else:
		match low:
			1:
				for k in 8:
					if k == 0:
						ram.w16(a + 0x330, radii[0])
					elif k == 3:
						ram.w16(a + 0x360, ram.s16(table + 6))
					else:
						ram.w16(a + 0x330 + k * 0x10, 1)
			2:
				for k in 8:
					ram.w16(a + 0x330 + k * 0x10, 1)
			3:
				for k in 8:
					ram.w16(a + 0x330 + k * 0x10, radii[k] >> 1)
			4:
				for k in 8:
					ram.w16(a + 0x330 + k * 0x10, 0)
			5:
				for k in 8:
					if k == 0:
						ram.w16(a + 0x330, radii[0] >> 1)
					elif k == 3:
						ram.w16(a + 0x360, ram.s16(table + 6) >> 1)
					else:
						ram.w16(a + 0x330 + k * 0x10, 1)
			6:
				for k in 8:
					if k == 0:
						ram.w16(a + 0x330, radii[0] + 0x3c)
					elif k == 4 or k == 5 or k == 6 or k == 7:
						ram.w16(a + 0x330 + k * 0x10, 1)
					else:
						ram.w16(a + 0x330 + k * 0x10, radii[k])
			7:
				for k in 8:
					ram.w16(a + 0x330 + k * 0x10, radii[k] + 100)
			_:
				for k in 8:
					ram.w16(a + 0x330 + k * 0x10, radii[k])
	var rowflags: int = ram.u32(row + 0x24) >> 8
	for k in 8:
		var weight: int = k - 6 + 0
		if ram.u8(row + 0x2d) == 0:
			if ram.u8(a + 0xdb) == 0 or ram.u8(a + 0x87) == 0:
				if (rowflags & 0x200) != 0 and (k == 6 or k == 7 or k == 4 or k == 5):
					ram.w16(a + 0x330 + k * 0x10, 0)
			elif k == 6 or k == 7:
				ram.w16(a + 0x330 + k * 0x10, 0)
		elif k == 1 or k == 2:
			ram.w16(a + 0x330 + k * 0x10, 0)
func tick() -> void:
	for p in 2:
		var a := actor(p)
		var b := MoveStep.opponent(ram, a)
		ram.w8(a + 0xc6, 1 if ram.s16(b + 0x1278) <= ram.s16(a + 0x1278) else 0)
	for p in 2:
		Volumes.end_frame(ram, actor(p))
	for p in 2:
		var a := actor(p)
		MoveStep.step(ram, a, actor(ram.u8(a + 0x1f)))
	MoveStep.update_distances(ram)
	for p in 2:
		MovePhysics.run(ram, actor(p))
	for p in 2:
		var a := actor(p)
		for k in 3:
			ram.w32(0x8009e6f8 + p * 0x10 + 4 + k * 4, ram.u32(a + 0xf68 + k * 4))
	for p in 2:
		place_root(p)
		update_joints(p)
	for p in 2:
		var a := actor(p)
		ram.w32(a + 0x3c4, ram.s32(a + 0xf68) - ram.s32(a + 0x3b8))
		ram.w32(a + 0x3c8, ram.s32(a + 0xf6c) - ram.s32(a + 0x3bc))
		ram.w32(a + 0x3b8, ram.u32(a + 0xf68))
		ram.w32(a + 0x3cc, ram.s32(a + 0xf70) - ram.s32(a + 0x3c0))
		ram.w32(a + 0x3bc, ram.u32(a + 0xf6c))
		ram.w32(a + 0x3c0, ram.u32(a + 0xf70))
		Volumes.set_radii(ram, a)
		Volumes.body_spheres(ram, a)
		push_radii(a)
		if ram.s16(a + 0x58) < ram.u8(ram.u32(a + 0x54) + 0x2d) or ram.u8(ram.u32(a + 0x54) + 0x2e) < ram.s16(a + 0x58):
			Volumes.limb_segments(ram, a)
		else:
			Volumes.window_segments(ram, a)
	for p in 2:
		var a := actor(p)
		ram.w8(a + 0xd5, 0)
		ram.w8(a + 0xd9, 0)
		for k in 3:
			ram.w8(a + 0xd6 + k, 0)
	for p in 2:
		var a := actor(p)
		if ram.s16(a + 0x74) != 0:
			ram.w8(a + 0xd9, 1)
			ram.w8(actor(ram.u8(a + 0x21)) + 0xd9, 1)
	BodyPush.apply(ram, actor(0), actor(1))
	for p in 2:
		Hits.reset_hits(ram, actor(p))
	Hits.detect(ram, actor(0), actor(1))
	Hits.detect(ram, actor(1), actor(0))
	for p in 2:
		var a := actor(p)
		ram.w32(a + 0x3d0, ram.s32(a + 0x1b8) - ram.s32(a + 0x1ac))
		ram.w32(a + 0x3d4, ram.s32(a + 0x1bc) - ram.s32(a + 0x1b0))
		ram.w32(a + 0x3d8, ram.s32(a + 0x1c0) - ram.s32(a + 0x1b4))
	if trace:
		for p in 2:
			var a := actor(p)
			print("p", p, " flags60 ", "%x" % ram.u32(a + 0x60), " 66 ", "%x" % ram.u16(a + 0x66), " 64 ", "%x" % ram.u16(a + 0x64), " 30 ", ram.s16(a + 0x30), " row24 ", "%x" % ram.u32(ram.u32(a + 0x54) + 0x24), " ca ", ram.u8(a + 0xca), " b6 ", ram.u8(a + 0xb6))
			print("after detect p", p, " ce ", ram.u8(a + 0xce), " d1 ", ram.u8(a + 0xd1), " recs ", ram.u8(a + 0x15d), ram.u8(a + 0x189), " limbs ", ram.u8(a + 0xe3))
	for p in 2:
		var a := actor(p)
		MoveStep.react_pick(ram, a, MoveStep.opponent(ram, a))
	if trace:
		for p in 2:
			var a := actor(p)
			print("after react p", p, " ce ", ram.u8(a + 0xce), " recs ", ram.u8(a + 0x15d), ram.u8(a + 0x189), " next ", ram.s16(a + 0x1a0), " hp ", ram.s32(a + 0x3f4) >> 16)
	for p in 2:
		var a := actor(p)
		ram.w16(a + 0xe8, 0)
		for o in [0xd4, 0xcf, 0xd0, 0xd3, 0xde]:
			ram.w8(a + o, 0)
	for p in 2:
		Damage.resolve(ram, actor(p))
	if trace:
		for p in 2:
			var a := actor(p)
			print("after damage p", p, " hp ", ram.s32(a + 0x3f4), " rec1 ", ram.s16(a + 0x168 + 0x1c), ram.s16(a + 0x168 + 0x1e), " flags22 ", ram.u8(a + 0x168 + 0x22), ram.u8(a + 0x168 + 0x24), ram.u8(a + 0x168 + 0x25), " dmg_atk ", ram.s16(actor(1 - p) + 0x5e), " sphere ", ram.s16(a + 0x168 + 0x18))
	for p in 2:
		var a := actor(p)
		ram.w16(a + 0x1278, 176 + ram.s32(a + 0xf68) / 10)
	for p in 2:
		var a := actor(p)
		Pad.push(ram, a, ram.u8(a + 0xc6), pads[p], edges[p])
		MoveStep.choose_next(ram, a)
