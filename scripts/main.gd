extends Control

const ASSETS := "res://assets/textures"

var list: ItemList
var view: TextureRect
var files: Array[String] = []
var filter_linear := false


func _ready() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)
	list = ItemList.new()
	list.custom_minimum_size.x = 260
	list.item_selected.connect(_show)
	split.add_child(list)
	view = TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(view)
	_scan(ASSETS)
	files.sort()
	for f in files:
		list.add_item(f.trim_prefix(ASSETS + "/"))
	if files.size() > 0:
		list.select(0)
		_show(0)
	else:
		var l := Label.new()
		l.text = "No textures found. Run: python tools/extract.py <disc.cue>"
		view.add_child(l)


func _scan(dir: String) -> void:
	for d in DirAccess.get_directories_at(dir):
		_scan(dir + "/" + d)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			files.append(dir + "/" + f)


func _show(i: int) -> void:
	var img := Image.new()
	img.load_png_from_buffer(FileAccess.get_file_as_bytes(files[i]))
	view.texture = ImageTexture.create_from_image(img)
