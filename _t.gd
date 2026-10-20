extends SceneTree
const Match := preload("res://scripts/combat/match.gd")
func _init():
	var m = Match.new()
	var exe := FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")
	var model := FileAccess.get_file_as_bytes("res://assets/bns/127.3dmk")
	m.setup(exe, FileAccess.get_file_as_bytes("res://assets/bns/279.bin"), FileAccess.get_file_as_bytes("res://assets/bns/130.bin"), FileAccess.get_file_as_bytes("res://assets/bns/134.bin"), model, model)
	m.round_over.connect(func(w): print("round over winner ", w, " wins ", m.wins))
	m.match_over.connect(func(w): print("match over winner ", w))
	var a: int = m.actor(0)
	var b: int = m.actor(1)
	var last := -999
	for i in 6000:
		m.pads[0] = 0
		m.edges[0] = 0
		if m.phase == m.Phase.FIGHT:
			m.pads[0] = 0x2000 if m.phase_frames < 40 else 0
			if m.phase_frames >= 60 and m.phase_frames % 25 == 0:
				m.pads[0] = 0x10
				m.edges[0] = 0x10
		m.tick()
		var idb: int = m.ram.s16(b + 0xa0)
		if idb != last:
			print(i, " ph ", m.phase, " p1 id ", idb, " hp1 ", m.ram.s32(b + 0x3f4) >> 16, " timer ", m.timer)
			last = idb
		if m.phase == m.Phase.MATCH_OVER:
			break
	quit()
