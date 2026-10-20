extends Node3D
# Draws the Tekken Ball ball (42-vertex sphere of the overlay: 8 segments, 6 rings, caps) and its floor shadow from the emulated RAM.
const SCALE := 0.001
const RING_SIZE := 8
const COLORS := [[Color(0.95, 0.35, 0.3), Color(0.98, 0.9, 0.35), Color(0.35, 0.55, 0.95)], [Color(0.95, 0.5, 0.75), Color(0.98, 0.7, 0.85), Color(0.85, 0.4, 0.65)], [Color(0.42, 0.44, 0.48), Color(0.55, 0.57, 0.62), Color(0.3, 0.32, 0.36)]]
var ball
var mesh_node := MeshInstance3D.new()
var shadow := MeshInstance3D.new()
var backdrop := MeshInstance3D.new()
const Arena := preload("res://scripts/fight/ball_arena.gd")
const BACKDROP_RADIUS := 60.0
const BACKDROP_SPAN := 2.6
const BACKDROP_HEIGHT := 22.0
func setup(ball_logic) -> void:
	ball = ball_logic
	var ram = ball.ram
	var verts: Array = []
	for i in 42:
		var at: int = 0x800b5fe4 + i * 8
		verts.append(Vector3(ram.s16(at), -ram.s16(at + 2), -ram.s16(at + 4)) * SCALE)
	var kind: int = ram.u8(ball.KIND)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces: Array = []
	for k in RING_SIZE:
		faces.append([0, 2 + (k + 1) % RING_SIZE, 2 + k])
		faces.append([1, 34 + k, 34 + (k + 1) % RING_SIZE])
	for band in 4:
		for k in RING_SIZE:
			var a: int = 2 + band * RING_SIZE + k
			var b: int = 2 + band * RING_SIZE + (k + 1) % RING_SIZE
			faces.append([a, b, a + RING_SIZE])
			faces.append([b, b + RING_SIZE, a + RING_SIZE])
	for f in faces:
		var segment: int = (f[0] + f[1] + f[2]) % 3
		tool.set_color(COLORS[kind][segment])
		for i in 3:
			tool.add_vertex(verts[f[i]])
	tool.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tool.set_material(material)
	mesh_node.mesh = tool.commit()
	add_child(mesh_node)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.38
	disc.bottom_radius = 0.38
	disc.height = 0.002
	shadow.mesh = disc
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0, 0, 0, 0.45)
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = dark
	add_child(shadow)
var floaters: Array = []
func refresh() -> void:
	for p in ball.popups:
		var label := Label3D.new()
		label.text = p["text"]
		label.font_size = 96
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = [Color.WHITE, Color(1, 0.9, 0.2), Color(0.4, 0.8, 1.0), Color.WHITE, Color.WHITE, Color(1, 0.4, 0.4)][clampi(p["kind"], 0, 5)]
		label.position = Vector3(p["x"], -p["y"], -p["z"]) * SCALE + Vector3(0, 0.5, 0)
		add_child(label)
		floaters.append([label, p["frames"]])
	ball.popups.clear()
	for f in floaters.duplicate():
		f[0].position.y += 0.01
		f[1] -= 1
		if f[1] <= 0:
			f[0].queue_free()
			floaters.erase(f)
	var x: int = ball.s32(0x68)
	var y: int = ball.s32(0x6c)
	var z: int = ball.s32(0x70)
	mesh_node.position = Vector3(x, -y, -z) * SCALE
	var turn := TAU / 4096.0
	mesh_node.rotation = Vector3(ball.s16(0x98) * turn, ball.s16(0x9a) * turn, ball.s16(0x9c) * turn)
	var state: int = ball.s16(0)
	mesh_node.visible = state != 10
	shadow.position = Vector3(x * SCALE, 0.01, -z * SCALE)
	var height: float = maxf(-y * SCALE, 0.0)
	shadow.scale = Vector3.ONE * clampf(1.0 - height * 0.15, 0.4, 1.0)
func build_backdrop(vram: PackedInt32Array) -> void:
	var texture := ImageTexture.create_from_image(Arena.panorama(vram))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 32
	for i in steps:
		var a0: float = -BACKDROP_SPAN / 2.0 + BACKDROP_SPAN * i / steps
		var a1: float = -BACKDROP_SPAN / 2.0 + BACKDROP_SPAN * (i + 1) / steps
		var u0: float = float(i) / steps
		var u1: float = float(i + 1) / steps
		var p0 := Vector3(sin(a0) * BACKDROP_RADIUS, 0.0, cos(a0) * BACKDROP_RADIUS)
		var p1 := Vector3(sin(a1) * BACKDROP_RADIUS, 0.0, cos(a1) * BACKDROP_RADIUS)
		var up := Vector3(0, BACKDROP_HEIGHT, 0)
		for v in [[p0 + up, Vector2(u0, 0)], [p0, Vector2(u0, 1)], [p1, Vector2(u1, 1)], [p0 + up, Vector2(u0, 0)], [p1, Vector2(u1, 1)], [p1 + up, Vector2(u1, 0)]]:
			tool.set_uv(v[1])
			tool.add_vertex(v[0])
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	tool.set_material(material)
	backdrop.mesh = tool.commit()
	add_child(backdrop)
