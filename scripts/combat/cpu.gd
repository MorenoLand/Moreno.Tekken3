extends RefCounted
var seed_value := 12345
var level := 1
var hold := 0
var plan := 0
var buttons := 0
func roll(n: int) -> int:
	seed_value = (seed_value * 1103515245 + 12345) & 0x7fffffff
	return (seed_value >> 8) % n
func think(sim, p: int) -> Array:
	var a: int = sim.actor(p)
	var ram = sim.ram
	if sim.phase != sim.Phase.FIGHT or ram.u32(a + 0x3f4) == 0:
		return [0, 0]
	var forward: int = 0x2000 if ram.u8(a + 0xc6) == 0 else 0x8000
	var back: int = 0x8000 if forward == 0x2000 else 0x2000
	var dist: int = ram.u32(a + 0xf8)
	var pad := 0
	var edge := 0
	if hold > 0:
		hold -= 1
		pad = plan
		return [pad, 0]
	if dist > 1500:
		plan = forward
		hold = 4 + roll(12)
	elif dist > 1000:
		var r: int = roll(10)
		if r < 7:
			plan = forward
			hold = 8
		elif r < 9:
			plan = [0x80, 0x10, 0x40, 0x20][roll(4)]
			edge = plan
			hold = 1
		else:
			plan = back
			hold = 10
	else:
		var r2: int = roll(12)
		if r2 < 3 + level * 3:
			plan = [0x80, 0x10, 0x40, 0x20][roll(4)]
			edge = plan
			hold = 1
		elif r2 < 9 + (level - 1):
			plan = back
			hold = 14 + roll(14)
		elif r2 < 10:
			plan = 0x4000 | back
			hold = 16
		else:
			plan = 0
			hold = 8
	return [plan if edge == 0 else plan, edge]
