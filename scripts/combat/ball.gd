extends RefCounted
# Tekken Ball: the ball object, its hit rules and the per-frame update (overlay record 008 and the mode 7 hooks of the exe).
# The ball lives in emulated RAM like the actors; mode 7 is stored at 0x800afa88. Offsets used on the ball (BALL + offset):
#   +0x00 state (0 wait, 1 serve, 2 flight, 3 low, 4 smash, 5 hit, 6 reset, 7 landed, 8 pre-serve, 9 float)
#   +0x68/+0x6c/+0x70 position   +0x78/+0x7c/+0x80 velocity   +0x8c gravity   +0xa8 speed   +0xb0 heading   +0xb2 homing
#   +0xb8 previous position / sphere (radius at +0xc4, squared at +0xc8)   +0xd0 four path segments (0x18 each)
#   +0x130 owner actor   +0x134 other actor   +0x13c/+0x13e damage bars   +0x140 damage carried   +0x146 look   +0x147 timer
const Ram := preload("res://scripts/combat/ram.gd")
const FMath := preload("res://scripts/combat/fmath.gd")
const Hits := preload("res://scripts/combat/hits.gd")
const BodyPush := preload("res://scripts/combat/body_push.gd")
const SoundEvents := preload("res://scripts/combat/sound_events.gd")
const OVERLAY := 0x800b0548
const MODE := 0x800afa88
const MODE_BALL := 7
const POINTER := 0x800add74
const BALL := 0x80140000
const GHOST := 0x800ac340
const ACTORS := 0x800a9228
const STRIDE := 0x188c
const ROUND_STATE := 0x80096f2c
const ROUND_COUNT := 0x800afac0
const ROUND_LIMIT := 0x800afac4
const SERVE_SIDE := 0x800afac8
const KIND := 0x800afac9
const PARAMS := 0x800b5f9c
const P_B := 0x800b6610
const P_A := 0x800b6612
const P_GRAVITY := 0x800b6614
const P_HALF := 0x800b6616
const P_PERCENT := 0x800b6618
const GROUND_COUNTER := 0x800b661c
const SOUND_COOLDOWN := 0x800b6620
const AI_AXIS := 0x800b6628
const KO_PLAYER := 0x800b6684
const HIT_EVENT := 0x800b668c
const MOTION := 0x800b6678
const SEGMENT_OFFSETS := 0x800b6344
const COS16 := 0x8001f0c4
const SIN16 := 0x8001e8c4
var ram
var sounds: Array
var popups: Array = []
var cues: Array = []
var landed: Array = []
var stale_flags := 0
static func active(r) -> bool:
	return r.u8(MODE) == MODE_BALL
static func kind_params(r, kind: int) -> int:
	return PARAMS + kind * 0x18
func _init(r, sound_out: Array) -> void:
	ram = r
	sounds = sound_out
func setup(overlay: PackedByteArray, kind: int, side: int) -> void:
	ram.load_bytes(OVERLAY, overlay)
	ram.w8(MODE, MODE_BALL)
	ram.w32(POINTER, BALL)
	ram.w8(KIND, kind)
	ram.w8(SERVE_SIDE, side)
func s16(o: int) -> int:
	return ram.s16(BALL + o)
func s32(o: int) -> int:
	return ram.s32(BALL + o)
func u8(o: int) -> int:
	return ram.u8(BALL + o)
func w16(o: int, v: int) -> void:
	ram.w16(BALL + o, v)
func w32(o: int, v: int) -> void:
	ram.w32(BALL + o, v)
func w8(o: int, v: int) -> void:
	ram.w8(BALL + o, v)
func snd(id: int) -> void:
	SoundEvents.play_id(ram, sounds, 0, id)
func actor(p: int) -> int:
	return ACTORS + p * STRIDE
func hip(p: int) -> int:
	return actor(p) + 0xf68
func sin16(angle: int) -> int:
	return ram.s16(SIN16 + (angle & 0xfff) * 2)
func cos16(angle: int) -> int:
	return ram.s16(COS16 + (angle & 0xfff) * 2)
func load_params(kind: int) -> void:
	var p := PARAMS + kind * 0x18
	ram.w16(P_A, ram.s16(p))
	ram.w16(P_B, ram.s16(p + 4))
	ram.w16(P_GRAVITY, ram.s16(p + 8))
	ram.w16(P_PERCENT, ram.s16(p + 0x10))
	ram.w16(P_HALF, ram.s16(p + 0x14))
func update_segments() -> void:
	for i in 4:
		var e := BALL + 0xd0 + i * 0x18
		ram.w32(e, ram.u32(e + 12))
		ram.w32(e + 4, ram.u32(e + 16))
		ram.w32(e + 8, ram.u32(e + 20))
		ram.w32(e + 12, s32(0x68) + ram.s16(SEGMENT_OFFSETS + i * 8))
		ram.w32(e + 16, s32(0x6c) + ram.s16(SEGMENT_OFFSETS + i * 8 + 2))
		ram.w32(e + 20, s32(0x70) + ram.s16(SEGMENT_OFFSETS + i * 8 + 4))
func init_ball() -> void:
	var side: int = ram.u8(SERVE_SIDE)
	w16(0, 0)
	w16(2, 0)
	w8(0x147, 100 if ram.s32(0x80095484) == 1 else 0x28)
	var x: int = 0xd00 if side != 0 else -0xd00
	w32(0x68, x)
	w32(0x130, actor(side))
	w32(0x6c, -0x500)
	w16(0xa0, 0x20)
	w16(0xa2, 0x10)
	w32(0x70, 0)
	w32(0xa8, 0)
	w32(0xac, 0)
	for o in [0x13c, 0x13e, 0x140]:
		w16(o, 0)
	for o in [0x7c, 0x80, 0x78, 0x90, 0x88]:
		w32(o, 0)
	for o in [0x98, 0x9a, 0x9c, 0xb0, 0xb2, 0x14c, 0x14a, 0x148, 0x150]:
		w16(o, 0)
	w16(0xa4, 4)
	w8(0xcc, 0)
	w8(0xcd, 0)
	w8(0x144, 0)
	w32(0x134, actor(1 - side))
	w32(0x8c, ram.s16(P_GRAVITY))
	w16(0xc4, 0x260)
	w32(0xc8, 0x5a400)
	w32(0xb4, 0x800b5fe4)
	w32(0xb8, s32(0x68))
	w32(0xbc, s32(0x6c))
	w32(0xc0, s32(0x70))
	update_segments()
	update_segments()
func clear_motion(p: int) -> void:
	var e := MOTION + p * 6
	ram.w16(e, 0)
	for k in range(2, 6):
		ram.w8(e + k, 0)
func set_motion(a: int) -> void:
	var p: int = ram.s16(a + 0x12)
	clear_motion(p)
	var e := MOTION + p * 6
	var k: int = ram.u16(a + 0xa0) - 24
	if k < 0 or k > 9:
		return
	if k == 0 or k == 2:
		ram.w16(e, 0x8000)
		ram.w8(e + 2, 30)
		ram.w8(e + 3, 3)
		ram.w8(e + 4, 9)
	elif k == 6 or k == 8:
		ram.w16(e, 0x8000)
		ram.w8(e + 2, 150)
		ram.w8(e + 3, 5)
		ram.w8(e + 4, 12)
		ram.w8(e + 5, 18)
	elif k == 7 or k == 9:
		ram.w8(e + 5, 18)
func start_round() -> void:
	load_params(ram.u8(KIND))
	init_ball()
	for i in 2:
		var a: int = actor(i)
		ram.w32(a, 0x1400 if i == 1 else -0x1400)
		ram.w32(a + 8, 0)
		ram.w16(a + 0xe, 0xc000 if i == 1 else 0x4000)
	ram.w32(ROUND_COUNT, 0)
	ram.w32(ROUND_LIMIT, 2)
	ram.w32(SOUND_COOLDOWN, 0)
	landed.clear()
func spin_from(dest: int, vec: int) -> void:
	ram.w16(dest, 0)
	ram.w16(dest + 2, BodyPush.angle4096(ram, ram.s32(vec), ram.s32(vec + 8)))
	var x: int = ram.s32(vec)
	if x < 1:
		ram.w16(dest + 4, -BodyPush.angle4096(ram, x, ram.s32(vec + 4)))
	else:
		ram.w16(dest + 4, BodyPush.angle4096(ram, x, ram.s32(vec + 4)))
func popup(text: String, kind: int, size: int, frames: int) -> void:
	popups.append({"text": text, "x": s32(0x68), "y": s32(0x6c), "z": s32(0x70), "kind": kind, "size": size, "frames": frames})
func cue(kind: int, slot: int = -1) -> void:
	cues.append([kind, slot])
func attack_test(a0: int, a1: int, out: int) -> int:
	var flags := 0
	var bit := 2
	var a := a0
	for pass_index in 2:
		var list: int = ram.u32(ram.u32(a + 0x54) + 0x28)
		if ram.u8(list) < 0x18:
			var count: int = mini(ram.u8(a + 0xe3), 4)
			var seg := a + 0x1ac
			for i in count:
				if Hits.seg_sphere(ram, seg, BALL + 0xb8):
					ram.w32(out, ram.s32(seg + 12) - ram.s32(seg))
					ram.w32(out + 4, ram.s32(seg + 16) - ram.s32(seg + 4))
					ram.w32(out + 8, ram.s32(seg + 20) - ram.s32(seg + 8))
					flags |= bit
					break
				seg += 0x18
		else:
			flags |= 8
		bit = 1
		a = a1
	return flags
func body_test(a0: int, a1: int) -> int:
	var flags := 0
	var bit := 2
	var a := a0
	for pass_index in 2:
		var found := false
		for k in 14:
			var sphere := a + 0x20c + k * 0x14
			if ram.s16(sphere + 0xc) == 0:
				continue
			for j in 4:
				var seg := BALL + 0xd0 + j * 0x18
				if Hits.seg_sphere(ram, seg, sphere):
					ram.w16(a + 0x154, k)
					ram.w32(a + 0x13c, ram.u32(seg + 12))
					ram.w32(a + 0x140, ram.u32(seg + 16))
					ram.w32(a + 0x144, ram.u32(seg + 20))
					ram.w16(a + 0x14c, FMath.s16(ram.s16(seg + 12) - ram.s16(seg)))
					ram.w16(a + 0x14e, FMath.s16(ram.s16(seg + 16) - ram.s16(seg + 4)))
					ram.w16(a + 0x150, FMath.s16(ram.s16(seg + 20) - ram.s16(seg + 8)))
					flags |= bit
					found = true
					break
			if found:
				break
		bit = 1
		a = a1
	return flags
func copy_actor(from: int, to: int) -> void:
	for o in range(0, STRIDE, 4):
		ram.w32(to + o, ram.u32(from + o))
func put_state(v: int) -> void:
	w16(0, v)
func stop_speed() -> void:
	w32(0xa8, 0)
func damage_digits(v: int) -> String:
	return str(v)
func other_hip(p: int) -> int:
	return hip(p)
func update(a0: int, a1: int) -> void:
	if ram.s32(ROUND_STATE) == 1:
		ram.w32(ROUND_LIMIT, 2)
	if ram.s32(SOUND_COOLDOWN) > 0:
		ram.w32(SOUND_COOLDOWN, ram.s32(SOUND_COOLDOWN) - 1)
	if ram.s32(0x80095468) == 0 and ram.s32(0x80095494) == 0:
		if ram.s32(0x800954a4) == 0:
			step(a0, a1)
			post()
		elif (ram.u32(BALL + 0x144) & 0xffff0000) == 0x5020000:
			snd(0x4e6e)
	court_axes()
func step(a0: int, a1: int) -> void:
	var flag145: int = u8(0x145) if u8(0xcc) != 0 else 0
	w8(0x145, flag145)
	ram.w8(HIT_EVENT, 0)
	ram.w32(KO_PLAYER, 0)
	var state: int = s16(0)
	var kind: int = ram.u8(KIND)
	var grav: int = ram.s16(P_GRAVITY)
	var flags: int = stale_flags
	match state:
		0:
			var t: int = (u8(0x147) - 1) & 0xff
			w8(0x147, t)
			if t == 0:
				put_state(8)
				w8(0x147, 0x20)
				snd(0x4ce8)
		1, 8:
			var t: int = (u8(0x147) - 1) & 0xff
			w8(0x147, t)
			if t == 0:
				put_state(9 if state == 8 else 2)
				w32(0xa8, 0)
				w8(0xcc, 0)
				w16(0xb0, 0)
				w16(0xb2, 0)
				var x0: int = ram.s32(hip(0))
				var x1: int = ram.s32(hip(1))
				if 0 < x0:
					x0 = 0
				if x1 < 0:
					x1 = 0
				var z0: int = ram.s32(hip(0) + 8)
				var dx: int = x1 - x0
				var dz: int = ram.s32(hip(1) + 8) - z0
				if dx != 0:
					w32(0x70, z0 + FMath.tdiv((s32(0x68) - x0) * dz, dx))
				else:
					w32(0x68, x0)
		6:
			w16(0x140, 0)
			w8(0x144, 0)
			var t6: int = (u8(0x147) - 1) & 0xff
			w8(0x147, t6)
			if t6 == 0:
				put_state(1)
				w8(0x147, 0x20)
				w32(0x68, 0)
				w32(0x6c, -0xe40)
				var z0b: int = ram.s32(hip(0) + 8)
				var z1b: int = ram.s32(hip(1) + 8)
				for o in [0x90, 0x88, 0x80, 0x7c, 0x78]:
					w32(o, 0)
				for o in [0xa4, 0xa2, 0xa0]:
					w16(o, 0)
				w32(0x8c, grav >> 1)
				w32(0x70, (z0b + z1b) >> 1)
				update_segments()
				update_segments()
				if ram.s32(0x8009547c) == 0:
					snd(0x4ce9)
		7:
			w16(0x140, 0)
			w8(0x144, 0)
			var t7: int = (u8(0x147) - 1) & 0xff
			w8(0x147, t7)
			if t7 == 0:
				put_state(6)
				w8(0x147, 0x10)
		_:
			flags = flight(a0, a1, state, kind, grav)
			stale_flags = flags
func flight(a0: int, a1: int, state: int, kind: int, grav: int) -> int:
	var flags := 0
	var y: int = s32(0x6c)
	var run := false
	if state == 4:
		if y < -0x1400:
			w32(0x6c, -0x1400)
			put_state(2)
			w32(0x8c, grav)
			w32(0x130, ram.u32(BALL + 0x138))
			w32(0xa8, s16(0x142))
			w32(0x7c, FMath.tdiv(s16(0x142) << 1, 3) + 0x1000)
		else:
			run = true
	elif -0x2001 < y:
		run = true
	else:
		w32(0x6c, -0x2000)
		w32(0x7c, 0)
		w32(0x8c, grav)
	if run:
		var air := false
		if s32(0x6c) < -0x180 and absi(s32(0x68)) <= 0x2800:
			air = true
		if not air:
			var landing: int = ground(a0, a1, kind, grav)
			if landing == 1:
				air = true
			elif landing == 2:
				air = false
		if air:
			flags = in_air(a0, a1, state, grav)
	finish_motion(a0, a1, flags)
	return flags
func ground(a0: int, a1: int, kind: int, grav: int) -> int:
	w32(0x6c, -0x180)
	w32(0x8c, grav)
	if 0xd00 < s32(0x7c):
		snd(0x4e6e)
	if kind == 2:
		var vy: int = s32(0x7c)
		if vy > 0x3000:
			cue(1)
		elif vy > 0x1800:
			cue(0)
	var koed: int = ram.s32(0x8009547c)
	if absi(s32(0x68)) <= ram.s16(P_HALF):
		put_state(2)
		w32(0x7c, -s32(0x7c) >> 1)
		w16(0xa0, s16(0xa0) >> 1)
		w16(0xa2, s16(0xa2) >> 1)
		w16(0xa4, s16(0xa4) >> 1)
		return 1
	w32(0x7c, 0)
	w16(0xa8, 0)
	w16(0xaa, 0)
	if koed == 0 and s16(0) != 5:
		var target := a1
		if s32(0x68) >= 0:
			w16(0x13e, 0)
		else:
			w16(0x13c, 0)
			target = a0
		var hp: int = ram.s32(target + 0x3f4)
		ram.w32(target + 0x3f4, hp - 0x1e0000)
		ram.w8(target + 0x22, (ram.u8(target + 0x1e) + 1) & 1)
		if hp - 0x1e0000 < 0:
			ram.w32(target + 0x3f4, 0)
		put_state(7)
		w8(0x147, 5)
		ram.w32(KO_PLAYER, ram.u8(target + 0x1e) + 1 if ram.s32(0x800954a0) == 0 else 0)
		ram.w32(0x800ad2a8, s32(0x68))
		ram.w32(0x800ad2b0, s32(0x70))
		return 2
	put_state(6)
	w8(0x147, 0x10)
	return 2
func in_air(a0: int, a1: int, state: int, grav: int) -> int:
	var flags := 0
	if s32(0x6c) < -0x189:
		ram.w32(GROUND_COUNTER, 0)
	else:
		ram.w32(GROUND_COUNTER, ram.s32(GROUND_COUNTER) + 1)
		if ram.s32(GROUND_COUNTER) > 599:
			put_state(6)
			w8(0x147, 0x10)
			return 0
	if s16(0xb2) == 0:
		var speed: int = s32(0xa8) - 0x20
		w32(0xa8, speed)
		if speed < 0:
			w32(0xa8, 0)
	if u8(0xcc) != 0:
		w8(0xcc, (u8(0xcc) - 1) & 0xff)
		return 0
	w32(0xb8, s32(0x68))
	w32(0xbc, s32(0x6c))
	w32(0xc0, s32(0x70))
	var aux := BALL + 0x1500
	flags = attack_test(a0, a1, aux)
	if (flags & 7) == 0:
		touch_body(a0, a1, state, grav)
	else:
		touch_attack(a0, a1, flags, aux, grav)
	return flags
func touch_body(a0: int, a1: int, state: int, grav: int) -> void:
	var flags := 0
	if ram.u8(a0 + 0xc4) == 0 and ram.u8(a1 + 0xc4) == 0:
		flags = body_test(a0, a1)
	if ram.s32(ROUND_STATE) > 5:
		if ram.u8(a1 + 0xc3) == 0:
			flags &= 2
		elif ram.u8(a0 + 0xc3) == 0:
			flags &= 1
	if flags == 0:
		return
	var hitter := a1
	var other := a0
	if (flags & 2) != 0:
		hitter = a0
		other = a1
	if hitter == ram.u32(BALL + 0x130) and s16(0x140) != 0:
		return
	w16(0xac, 0)
	w16(0xae, 0)
	w16(0xb2, 0)
	if s16(0) != 3:
		put_state(2)
	var ox: int = ram.s32(hip(ram.u8(other + 0x1e)))
	var oz: int = ram.s32(hip(ram.u8(other + 0x1e)) + 8)
	w16(0xb0, BodyPush.angle4096(ram, ox - s32(0x68), oz - s32(0x70)))
	var dist: int = ram.u32(0x800afa3c)
	var k: int = (dist >> 7) + 0xc
	w32(0x8c, grav)
	w32(0x7c, ((-grav * k) >> 1) - (s32(0x6c) + 0x1000))
	var base := 0x400
	if 0x800 < dist:
		base = dist - 0x800
	w32(0xa8, FMath.tdiv(base << 8, k))
	if s16(0x140) == 0 or ram.u32(BALL + 0x130) == hitter:
		if ram.s32(SOUND_COOLDOWN) == 0:
			snd(0x704e)
			ram.w32(SOUND_COOLDOWN, 10)
		w32(0x130, hitter)
		w32(0x134, other)
		return
	ram.w16(GHOST + 0x5e, s16(0x140))
	w32(0x130, hitter)
	w32(0x134, other)
	put_state(2)
	ram.w8(HIT_EVENT, 1)
	w16(0x140, 0)
	ram.w8(GHOST + 0x83 + ram.u8(other + 0x1e), 1)
	ram.w8(GHOST + 0x88, 1)
	ram.w8(GHOST + 0xd1, 1)
	ram.w8(GHOST + 0x23, ram.u8(other + 0x1e))
	ram.w8(hitter + 0x87, 1)
	ram.w8(hitter + 0xce, 1)
	ram.w16(hitter + 0xee, ram.u8(ram.u32(GHOST + 0x54) + 0x2c))
	ram.w8(hitter + 0x15d, 1)
	ram.w8(hitter + 0x15c, 2)
	var carried: int = ram.s16(GHOST + 0x5e)
	if carried != 0 or ram.u8(hitter + 0xdb) != 0:
		ram.w16(hitter + 0x104, 4)
	if (ram.u16(hitter + 0x66) & ram.u16(GHOST + 0x64)) == 0:
		if carried > 99 or u8(0x146) == 9:
			cue(2, ram.u8(hitter + 0x1e))
			if ram.u8(KIND) == 2:
				ram.w32(ROUND_LIMIT, 6)
		w16(0xa8, 0)
		w16(0xaa, 0)
		w8(0x144, 0)
		w16(0x13c, 0)
		w16(0x13e, 0)
		put_state(5)
		w32(0x130, hitter)
		w32(0x134, hitter)
		w8(0xcc, 5)
		var g: int = ram.s16(P_GRAVITY)
		w32(0x7c, g * -0x25)
		w32(0x8c, g >> 1)
		snd(0x4e6d if carried < 0x32 else 0x4daf)
	else:
		snd(0x7043)
		if (carried > 99 or u8(0x146) == 9) and ram.s32(hitter + 0x3f4) <= (carried << 13):
			cue(2, ram.u8(hitter + 0x1e))
func bank(hitter: int, gain: int) -> void:
	var slot: int = ram.s16(hitter + 0x12)
	var v: int = FMath.s16(s16(0x13c + slot * 2) + gain)
	w16(0x13c + slot * 2, v)
	w16(0x140, v)
func gain_of(hitter: int) -> int:
	return FMath.tdiv(ram.s16(hitter + 0x5e) * ram.s16(P_PERCENT), 100)
func owner_color() -> int:
	return 2 if ram.u8(ram.u32(BALL + 0x130) + 0x1e) == 0 else 5
func other_z(other: int) -> int:
	return ram.s32(hip(ram.u8(other + 0x1e)) + 8)
func lunge(hitter: int, other: int, plus: int, cap: int, lift_shift: int, variant: int) -> void:
	var raw: int = ram.u16(hitter + 0x5e) + plus
	if s16(0x140) != 0:
		w8(0x145, 1)
		w8(0x144, u8(0x144) + 1)
	var gain: int = gain_of(hitter)
	bank(hitter, gain)
	popup(str(gain), owner_color(), 1, 0x1e)
	w16(0xb2, 1)
	var clamped: int = FMath.s16(raw)
	if clamped < cap + 1:
		if clamped < 0x14:
			clamped = 0x14
	else:
		clamped = cap
	var speed: int = (clamped + u8(0x144)) * ram.s16(P_A)
	if u8(0x145) != 0:
		speed += s32(0xa8) >> 4
	w32(0xa8, speed)
	w32(0x8c, ram.s16(P_GRAVITY) >> lift_shift)
	put_state(2)
	if variant == 1:
		w32(0x7c, (other_z(other) - s32(0x6c)) - ram.u32(0x800afa3c))
	else:
		w32(0x7c, (other_z(other) + s32(0x6c) * -2) - ram.u32(0x800afa3c))
func ballistic(hitter: int, plus: int) -> void:
	var g: int = ram.s16(P_GRAVITY)
	w32(0x8c, g)
	w32(0x7c, g * -0x25)
	var drag: int = s32(0xa8) >> 2
	var speed: int = (ram.s16(hitter + 0x5e) + plus) * ram.s16(P_B) + absi(s32(0x68)) - drag
	w32(0xa8, speed)
	if speed < 0:
		w16(0xa8, 0)
		w16(0xaa, 0)
	w16(0x140, 0)
	put_state(2)
func touch_attack(a0: int, a1: int, flags: int, aux: int, grav: int) -> void:
	var hitter := a1
	var other := a0
	if (flags & 2) != 0:
		hitter = a0
		other = a1
	if ram.u8(hitter + 0x85) != 0:
		return
	cue(5, ram.s16(hitter + 0x12))
	w16(0xac, 0)
	w16(0xae, 0)
	w32(0x130, hitter)
	w32(0x134, other)
	w16(0xb2, 0)
	copy_actor(hitter, GHOST)
	ram.w8(GHOST + 0x1e, 2)
	ram.w16(GHOST + 0x122, 1)
	ram.w16(GHOST + 0x64, 0xffff)
	ram.w8(GHOST + 0xdf, 1)
	ram.w8(hitter + 0x85, 1)
	ram.w8(hitter + 0x88, 1)
	ram.w8(hitter + 0xd1, 1)
	ram.w8(hitter + 0x23, 2)
	w8(0xcc, 5)
	var other_slot: int = ram.u8(other + 0x1e)
	w16(0xb0, BodyPush.angle4096(ram, ram.s32(hip(other_slot)) - s32(0x68), ram.s32(hip(other_slot) + 8) - s32(0x70)))
	spin_from(BALL + 0x148, aux)
	w8(0xcd, 1)
	var damage: int = ram.s16(hitter + 0x5e)
	w16(0x150, damage * 8 + 0x140)
	var move_class: int = ram.u16(hitter + 100)
	var pb: int = ram.s16(P_B)
	var pa: int = ram.s16(P_A)
	if (flags & 3) == 3:
		w16(0x140, 0)
		w16(0xa8, 0)
		w16(0xaa, 0)
		put_state(2)
		w32(0x7c, grav * -0x25)
		w32(0x8c, grav)
	elif ram.s16(hitter + 0x16) == 4 and (move_class == 0x607 or move_class == 0x706) and (flags & 8) == 0 and ram.s16(hitter + 0xa0) != 0x181:
		var hp: int = ram.s32(hitter + 0x3f4) + s16(0x13c + other_slot * 2) * -0x10000
		ram.w32(hitter + 0x3f4, hp)
		if hp < 0:
			ram.w32(hitter + 0x3f4, 0)
		w16(0x13e, 0)
		w16(0x13c, 0)
		put_state(7)
		w8(0x147, 5)
		ram.w32(KO_PLAYER, ram.u8(hitter + 0x1e) + 1)
	elif damage == 0:
		if s16(0x140) > 0:
			put_state(3)
			w32(0x7c, grav * -0x25)
			w32(0x8c, grav)
			w16(0x142, s16(0xa8) + pa * 5)
			var speed: int = (damage + 8) * pb + absi(s32(0x68)) - (s32(0xa8) >> 2)
			w32(0xa8, speed)
			if speed < 0:
				w16(0xa8, 0)
				w16(0xaa, 0)
			w16(0x140, 0)
			w8(0xcc, u8(0xcc) + 2)
			popup("!", 1, 1, 0x1e)
			snd(0x7082)
		else:
			ballistic(hitter, 10)
	elif move_class == 0x607 or move_class == 0x706:
		w16(0xb2, 1)
		w32(0xa8, pa * 0x3c)
		w32(0x8c, grav >> 2)
		w16(0x140, s16(0x13c + ram.s16(hitter + 0x12) * 2))
		put_state(2)
		w32(0x7c, (other_z(other) + s32(0x6c) * -2) - ram.u32(0x800afa3c))
		popup("!", 2, 1, 0x1e)
	elif ram.u8(hitter + 0xdb) == 0:
		if move_class == 799 or move_class == 0x217:
			lunge(hitter, other, 0x12, 0x2e, 2, 2)
		elif move_class == 0x10f or move_class == 0x51f:
			w32(0x7c, grav * -0x32)
			w32(0x8c, grav)
			w32(0xa8, (damage >> 2) * pb + absi(s32(0x68)))
			w16(0x140, 0)
			put_state(2)
		elif move_class == 0x412:
			if s16(0) != 3:
				w32(0x8c, grav)
				w32(0x7c, grav * -0x25)
				var drag: int = s32(0xa8) >> 2
				var spd: int = (damage + 10) * pb + absi(s32(0x68)) - drag
				w32(0xa8, spd)
				if spd < 0:
					w16(0xa8, 0)
					w16(0xaa, 0)
				w16(0x140, 0)
				put_state(2)
			else:
				put_state(4)
				w32(0x138, other)
				w32(0x7c, grav * -0x48)
				w32(0x8c, grav)
				w32(0xa8, pb * 10)
				snd(0x4daf)
				if s16(0x140) != 0:
					w8(0x145, 1)
					w8(0x144, u8(0x144) + 1)
				var gain: int = gain_of(hitter)
				bank(hitter, gain)
				popup(str(gain), owner_color(), 1, 0x1e)
				w16(0xb2, 1)
	else:
		lunge(hitter, other, 0xf, 0x28, 1, 1)
func finish_motion(a0: int, a1: int, flags: int) -> void:
	var heading: int = s16(0xb0) & 0xfff
	var speed: int = s32(0xa8)
	w32(0x78, (cos16(heading) * speed) >> 12)
	w32(0x80, (sin16(heading) * speed) >> 12)
	if s16(0) == 9:
		var v: int = ram.u16(SIN16 + (u8(0x147) & 0x7f) * 0x40)
		w8(0x147, (u8(0x147) + 1) & 0xff)
		var done: bool = ram.s32(0x80095460) > 599
		w32(0x6c, (FMath.s16(v) >> 4) - 0x500)
		if done:
			put_state(2)
			w32(0x7c, 0)
	else:
		w32(0x68, s32(0x68) + (s32(0x78) >> 8))
		w32(0x6c, s32(0x6c) + (s32(0x7c) >> 8))
		w32(0x70, s32(0x70) + (s32(0x80) >> 8))
	update_segments()
	w32(0x7c, s32(0x7c) + s32(0x8c))
	if flags != 0 and s16(0) != 3:
		var h: int = s16(0xb0)
		var shift: int = 0x13 if s16(0xb2) == 0 else 0x11
		w16(0xa4, (cos16(h) * s32(0xa8)) >> shift)
		w16(0xa0, s16(0xa4) >> 2)
		w16(0xa2, (sin16(h) * s32(0xa8)) >> 0x13)
	w16(0x98, s16(0x98) + s16(0xa0))
	w16(0x9a, s16(0x9a) + s16(0xa2))
	w16(0x9c, s16(0x9c) + s16(0xa4))
	var z: int = s32(0x70)
	var mid: int = (ram.s32(hip(0) + 8) + ram.s32(hip(1) + 8)) >> 1
	if 0x80 < z - mid:
		w32(0x70, mid + 0x80)
	if s32(0x70) - mid < -0x80:
		w32(0x70, mid - 0x80)
	w16(0x98, s16(0x98) + FMath.s16(s16(0x70) - FMath.s16(z)))
	var target: int = ram.u32(BALL + 0x134)
	var ti: int = ram.u8(ram.u32(BALL + 0x134) + 0x1e)
	var tx: int = ram.s32(hip(ti))
	var tz: int = ram.s32(hip(ti) + 8)
	if s16(0xb0) < -0x800:
		w16(0xb0, s16(0xb0) + 0x1000)
	if 0x800 < s16(0xb0):
		w16(0xb0, s16(0xb0) - 0x1000)
	if s16(0xb2) != 0:
		w16(0xb0, BodyPush.angle4096(ram, tx - s32(0x68), tz - s32(0x70)))
		if 0x1000 < s32(0xa8):
			var dx: int = s32(0x68) - tx
			var dz: int = s32(0x70) - tz
			var d: int = FMath.isqrt(dx * dx + dz * dz)
			var k: int = FMath.tdiv(d, s32(0xa8) >> 8)
			var vy: int = s32(0x7c)
			var inner: int = (vy + k * s32(0x8c)) >> 8
			var term: int = FMath.tdiv(vy + ((s32(0x6c) + inner) - ram.s32(target + 0x950)) * -0x100, k)
			w32(0x7c, ((vy * 0xd + term * 3) * 0x100) >> 12)
func post() -> void:
	if s16(0xb2) == 0:
		w16(0x150, s16(0x150) - ((s16(0x150) + 0x10) >> 4))
	elif s16(0x150) < 0x80:
		w8(0xcd, 0)
		spin_from(BALL + 0x148, BALL + 0x78)
		w16(0x14c, s16(0x14c) + 0x400)
		w16(0x150, FMath.tdiv(s16(0x150) << 1, 3) + FMath.tdiv(s32(0xa8) >> 6, 3))
	elif u8(0xcd) != 0:
		w16(0x150, s16(0x150) - ((s16(0x150) + 0x10) >> 4))
	var state: int = s16(0)
	var look := 0
	if state == 6:
		look = 1
	elif state == 7:
		look = 2
	elif state == 1 or state == 8:
		w8(0x146, 0)
		return
	elif s16(0x140) == 0:
		if u8(0xcc) == 0:
			w8(0x146, 3 if state != 3 else 4)
			return
		look = 5
	else:
		w8(0x147, ram.u8(ram.u32(BALL + 0x130) + 0x1e))
		if s16(0x140) < 100:
			if u8(0xcc) == 5:
				cue(6, u8(0x147))
			look = 6 if u8(0x147) == 0 else 7
		else:
			if u8(0xcc) == 5:
				cue(7, u8(0x147))
			look = 9
		w8(0x146, look)
		if u8(0xcc) == 0:
			return
		look = 8 if u8(0x145) != 0 else 5
	w8(0x146, look)
const CAPS := 0x80097a44
const RATES := 0x80097a50
const PAIR_FLAG := 0x80097a5c
const PAIR_LAST := 0x80097a60
const MoveStep := preload("res://scripts/combat/move_step.gd")
func cap_of(v: int, cap: int) -> int:
	if cap < absi(v):
		return -cap if v < 1 else cap
	return v
func constrain(a: int) -> void:
	var idx: int = ram.u8(a + 0x1e)
	var opp: int = MoveStep.opponent(ram, a)
	var cx := 0
	var cy := 0
	var cz := 0
	var z: int = ram.s32(a + 0xf70)
	var over: int = absi(z) - 0x100
	if over > 0:
		cz = -over if z > 0 else over
	var x: int = ram.s32(a + 0xf68)
	over = absi(x) - 0x1400
	if over > 0:
		cx = -over if x > 0 else over
	if (idx == 0 and x >= 0) or (idx == 1 and x <= 0):
		cx = -x
		if 1000 < absi(x):
			ram.w32(a + 0x60, 0x5000)
			ram.w8(a + 0x84, 0)
			ram.w8(a + 0x83, 0)
			ram.w8(a + 0xd9, 1)
	var lift: int = -0x1200 - ram.s32(a + 0xf6c)
	if 0 < lift:
		cy = lift
	if ram.s16(a + 0x74) < 0:
		ram.w32(CAPS + idx * 4, 0)
		ram.w32(RATES + idx * 4, 0)
	var cap: int = ram.s32(CAPS + idx * 4)
	var dx: int = cap_of(cx, cap)
	var dy: int = cap_of(cy, cap)
	var dz: int = cap_of(cz, cap)
	ram.w32(a, ram.s32(a) + dx)
	ram.w32(a + 8, ram.s32(a + 8) + dz)
	ram.w32(a + 4, ram.s32(a + 4) + dy)
	ram.w32(a + 0xf68, ram.s32(a + 0xf68) + dx)
	ram.w32(a + 0xf70, ram.s32(a + 0xf70) + dz)
	ram.w32(a + 0xf6c, ram.s32(a + 0xf6c) + dy)
	if ram.u8(a + 0xc4) != 0 and ram.u8(opp + 0xc4) != 0 and ram.s32(PAIR_FLAG) != 0:
		ram.w32(opp, ram.s32(opp) + dx)
		ram.w32(opp + 8, ram.s32(opp + 8) + dz)
		ram.w32(opp + 4, ram.s32(opp + 4) + dy)
		ram.w32(opp + 0xf68, ram.s32(opp + 0xf68) + dx)
		ram.w32(opp + 0xf70, ram.s32(opp + 0xf70) + dz)
		ram.w32(opp + 0xf6c, ram.s32(opp + 0xf6c) + dy)
func pair_count() -> int:
	var n := 0
	for p in 2:
		if ram.u8(actor(p) + 0xc4) != 0:
			n += 1
	return n
func after_pose() -> void:
	ram.w32(0x800954a0, pair_count())
	for p in 2:
		constrain(actor(p))
	var pairs: int = ram.s32(0x800954a0)
	if pairs < 2:
		ram.w32(PAIR_FLAG, 0)
	elif ram.s32(PAIR_LAST) != pairs:
		ram.w32(PAIR_FLAG, 1)
	ram.w32(PAIR_LAST, pairs)
	for p in 2:
		var a: int = actor(p)
		var opp: int = MoveStep.opponent(ram, a)
		if ram.u8(a + 0xc4) != 0 and ram.u8(opp + 0xc4) != 0 and ram.s16(a + 0x74) < 0 and ram.s32(PAIR_FLAG) != 0:
			ram.w32(a, ram.u32(opp))
			ram.w32(a + 8, ram.u32(opp + 8))
	for i in 3:
		var cap: int = ram.s32(CAPS + i * 4)
		if cap < 2000:
			ram.w32(CAPS + i * 4, cap + ram.s32(RATES + i * 4))
			ram.w32(RATES + i * 4, ram.s32(RATES + i * 4) + 2)
		if 2000 < ram.s32(CAPS + i * 4):
			ram.w32(CAPS + i * 4, 2000)
			ram.w32(RATES + i * 4, 2)
func court_axes() -> void:
	var a0x: int = ram.s32(hip(0))
	var a0z: int = ram.s32(hip(0) + 8)
	var a1x: int = ram.s32(hip(1))
	var a1z: int = ram.s32(hip(1) + 8)
	var dx: int = a1x - a0x
	var dz: int = a1z - a0z
	var ang: int = BodyPush.angle4096(ram, dx, dz)
	var c: int = cos16(-ang)
	var sn: int = sin16(-ang)
	var z0: int = a0z - FMath.tdiv(dz * a0x, dx)
	var out := [a0x * c - (a0z - z0) * sn, a1x * c - (a1z - z0) * sn, s32(0x68) * c - (s32(0x70) - z0) * sn, s32(0x68) * sn + (s32(0x70) - z0) * c]
	for i in 4:
		var v: int = out[i]
		out[i] = (v + 0xfff if v < 0 else v) >> 12
	ram.w32(AI_AXIS, out[0])
	ram.w32(AI_AXIS + 4, out[1])
	ram.w32(AI_AXIS + 8, out[2])
	ram.w32(AI_AXIS + 0xc, s32(0x6c))
	ram.w32(AI_AXIS + 0x10, out[3])
func court_distance(a: int) -> int:
	var d: int = ram.s32(AI_AXIS + ram.s16(a + 0x12) * 4) - ram.s32(AI_AXIS + 8)
	return FMath.isqrt(d * d + ram.s32(AI_AXIS + 0x10) * ram.s32(AI_AXIS + 0x10))
func ball_behind(slot: int) -> bool:
	if slot == 0:
		return ram.s32(AI_AXIS + 8) < ram.s32(AI_AXIS)
	return ram.s32(AI_AXIS + 4) < ram.s32(AI_AXIS + 8)
func ball_in_reach(slot: int) -> bool:
	var ball_x: int = ram.s32(AI_AXIS + 8)
	if slot == 0:
		var a0x: int = ram.s32(AI_AXIS)
		return a0x < ball_x and a0x + 2000 < ball_x
	var a1x: int = ram.s32(AI_AXIS + 4)
	return ball_x < a1x and a1x - 2000 < ball_x
