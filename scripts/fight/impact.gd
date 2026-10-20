extends Node3D
# Hit and block sparks. The ember sprite and its 14 fading palettes are the original ones
# (010/p08 at VRAM page 15, cluts 0x7f92..0x7f9f, additive); the burst count, speed and
# lifetime are matched by eye against captured frames, not taken from the game code.
const Tim := preload("res://scripts/fighter/tim.gd")
const BNS := "res://assets/bns/010/"
const FIRST_CLUT := 0x7f92
const RAMP := 14
const LIFE := 0.3
static var ramp: Array = []
var embers: Array = []
var flashes: Array = []
func _ready() -> void:
	if ramp.is_empty():
		var tims := []
		for n in 130:
			var path := "%sp%02d.tim" % [BNS, n]
			if FileAccess.file_exists(path):
				tims.append_array(Tim.stream(FileAccess.get_file_as_bytes(path)))
		var vram := Tim.compose_absolute(tims)
		for i in RAMP:
			ramp.append(ImageTexture.create_from_image(Tim.decode_region(vram, 0x3f, FIRST_CLUT + i, Rect2i(128, 144, 16, 16))))
func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	return m
func burst(at: Vector3, blocked: bool, toward: float) -> void:
	var count := 8 if blocked else 20
	for i in count:
		var sprite := Sprite3D.new()
		sprite.texture = ramp[0]
		sprite.pixel_size = 0.006
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.double_sided = true
		sprite.no_depth_test = true
		sprite.transparent = true
		sprite.material_override = _material()
		sprite.material_override.albedo_texture = ramp[0]
		sprite.position = at
		add_child(sprite)
		var heading := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 1.0), randf_range(-1.0, 1.0)).normalized()
		heading.x += toward * 0.5
		embers.append({"node": sprite, "velocity": heading * randf_range(0.8, 2.6), "age": randf() * 0.04})
func _process(delta: float) -> void:
	for e in embers.duplicate():
		e["age"] += delta
		var node: Sprite3D = e["node"]
		if e["age"] >= LIFE:
			node.queue_free()
			embers.erase(e)
			continue
		e["velocity"].y -= 3.0 * delta
		node.position += e["velocity"] * delta
		var step := mini(int(e["age"] / LIFE * RAMP), RAMP - 1)
		node.material_override.albedo_texture = ramp[step]
