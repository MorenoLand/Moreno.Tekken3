extends "res://scripts/menu/menu_screen.gd"
# Ball choice shown after the fighter is picked: the ball turns on a black stage, left/right changes it (overlay record 008, FUN_800b51d8 / FUN_800b5478).
signal chosen(kind: int)
signal back
const Exe := preload("res://scripts/core/exe.gd")
const GameFont := preload("res://scripts/menu/font.gd")
const BallView := preload("res://scripts/fight/ball_view.gd")
const ORIGIN := 0x800b0548
const NAMES := 0x800b6464
const PERCENT := [60, 80, 100]
var kind := 0
var overlay: PackedByteArray
var font
var labels: Array = []
var ball := MeshInstance3D.new()
var spin := 0.0
func _ready() -> void:
	overlay = FileAccess.get_file_as_bytes(BNS + "008.bin")
	font = GameFont.new(Exe.new(FileAccess.get_file_as_bytes("res://assets/system/SLUS_004.02")), BNS + "010/")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(368, 300)
	viewport.transparent_bg = true
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, -2.2)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	viewport.add_child(camera)
	viewport.add_child(DirectionalLight3D.new())
	viewport.add_child(ball)
	screen.add_child(viewport)
	var shown := TextureRect.new()
	shown.texture = viewport.get_texture()
	shown.position = Vector2(0, 0)
	screen.add_child(shown)
	for i in 4:
		var label := TextureRect.new()
		screen.add_child(label)
		labels.append(label)
	_refresh()
func _cstring(va: int) -> String:
	var o := va - ORIGIN
	var e := o
	while overlay[e] != 0:
		e += 1
	return overlay.slice(o, e).get_string_from_ascii()
func _place(label: TextureRect, text: String, font_index: int, clut: int, centre: float, y: float) -> void:
	var tex: ImageTexture = font.render_clut(text, font_index, clut)
	label.texture = tex
	label.size = tex.get_size()
	label.position = Vector2(centre - tex.get_width() / 2.0 if centre >= 0.0 else -centre, y)
func _refresh() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array = []
	for i in 42:
		var at: int = 0x800b5fe4 - ORIGIN + i * 8
		verts.append(Vector3(overlay.decode_s16(at), -overlay.decode_s16(at + 2), -overlay.decode_s16(at + 4)) * 0.0035)
	var colors: Array = BallView.COLORS[kind]
	for k in 8:
		for f in [[0, 2 + (k + 1) % 8, 2 + k], [1, 34 + k, 34 + (k + 1) % 8]]:
			tool.set_color(colors[k % 3])
			for i in 3:
				tool.add_vertex(verts[f[i]])
	for band in 4:
		for k in 8:
			var a: int = 2 + band * 8 + k
			var b: int = 2 + band * 8 + (k + 1) % 8
			tool.set_color(colors[(k + band) % 3])
			for i in [a, b, a + 8, b, b + 8, a + 8]:
				tool.add_vertex(verts[i])
	tool.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tool.set_material(material)
	ball.mesh = tool.commit()
	var level := _cstring(overlay.decode_u32(NAMES - ORIGIN + kind * 8))
	var name := _cstring(overlay.decode_u32(NAMES - ORIGIN + kind * 8 + 4))
	_place(labels[0], level, 0, 0x7e1b, 184.0, 324.0)
	_place(labels[1], name, 1, 0x7e14, 184.0, 342.0)
	_place(labels[2], "BALL DAMAGE", 0, 0x7e15, -135.0, 414.0)
	_place(labels[3], "%3d%%" % PERCENT[kind], 0, 0x7e16, -160.0, 432.0)
func _process(delta: float) -> void:
	spin += delta
	ball.rotation = Vector3(spin * 0.8, spin * 1.7, 0)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_left") or event.is_action_pressed("menu_right"):
		kind = (kind + (1 if event.is_action_pressed("menu_right") else 2)) % 3
		blip(BLIP_CURSOR)
		_refresh()
	elif event.is_action_pressed("menu_confirm"):
		blip(BLIP_CONFIRM)
		chosen.emit(kind)
	elif event.is_action_pressed("menu_back"):
		back.emit()
