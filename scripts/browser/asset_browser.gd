extends Control
const ASSETS := "res://assets"
const ModelView := preload("res://scripts/browser/model_view.gd")
const FightView := preload("res://scripts/fight/fight_view.gd")
var tabs: TabContainer
var player: AudioStreamPlayer
var image_view: TextureRect
var status: Label
func _ready() -> void:
	player = AudioStreamPlayer.new()
	add_child(player)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	status = Label.new()
	root.add_child(status)
	_add_tab("Textures", ASSETS + "/textures", ".png", true)
	_add_tab("Music", ASSETS + "/audio/cdda", ".wav", false)
	_add_tab("Sounds", ASSETS + "/audio/vab", ".wav", false)
	_add_model_tab()
	_add_fight_tab()
func _collect(dir: String, ext: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, ext, out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			out.append(dir + "/" + f)
func _add_tab(title: String, dir: String, ext: String, is_image: bool) -> void:
	var files: Array[String] = []
	_collect(dir, ext, files)
	files.sort()
	var split := HSplitContainer.new()
	split.name = title
	tabs.add_child(split)
	var list := ItemList.new()
	list.custom_minimum_size.x = 260
	split.add_child(list)
	for f in files:
		list.add_item(f.trim_prefix(dir + "/"))
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(holder)
	if is_image:
		var view := TextureRect.new()
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		holder.add_child(view)
		list.item_selected.connect(func(i: int) -> void: view.texture = _load_image(files[i]))
	else:
		var stop := Button.new()
		stop.text = "Stop"
		stop.pressed.connect(player.stop)
		holder.add_child(stop)
		list.item_selected.connect(func(i: int) -> void: _play(files[i]))
	if files.is_empty():
		status.text = "Missing %s. Run: python tools/extract.py <disc.cue>" % dir
func _add_model_tab() -> void:
	var ids: Array[int] = []
	for f in DirAccess.get_files_at(ASSETS + "/bns"):
		if f.ends_with(".3dmk"):
			ids.append(f.get_basename().to_int())
	ids.sort()
	var split := HSplitContainer.new()
	split.name = "Fighters"
	tabs.add_child(split)
	var list := ItemList.new()
	list.custom_minimum_size.x = 260
	split.add_child(list)
	for id in ids:
		list.add_item("Fighter %d (record %d)" % [(id - 71) / 4, id])
	var view := ModelView.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(view)
	list.item_selected.connect(func(i: int) -> void: view.show_model(ids[i]))
func _add_fight_tab() -> void:
	var ids: Array[int] = []
	for f in DirAccess.get_files_at(ASSETS + "/bns"):
		if f.ends_with(".3dmk"):
			ids.append(f.get_basename().to_int())
	ids.sort()
	var box := VBoxContainer.new()
	box.name = "Fight"
	tabs.add_child(box)
	var bar := HBoxContainer.new()
	box.add_child(bar)
	var picks: Array[OptionButton] = []
	for n in 2:
		var pick := OptionButton.new()
		for id in ids:
			pick.add_item("Fighter %d" % [(id - 71) / 4])
		pick.select(15 if n == 0 else 17)
		bar.add_child(pick)
		picks.append(pick)
	var view := FightView.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(view)
	var go := Button.new()
	go.text = "Start"
	go.pressed.connect(func() -> void: view.start([ids[picks[0].selected], ids[picks[1].selected]]))
	bar.add_child(go)
func _load_image(path: String) -> ImageTexture:
	var img := Image.new()
	img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	return ImageTexture.create_from_image(img)
func _play(path: String) -> void:
	var stream := load_wav(path)
	if stream == null:
		status.text = "Cannot read " + path
		return
	player.stream = stream
	player.play()
	status.text = "%s  %.1fs" % [path.get_file(), stream.get_length()]
func load_wav(path: String) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var channels := bytes.decode_u16(22)
	var rate := bytes.decode_u32(24)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = channels == 2
	stream.mix_rate = rate
	stream.data = bytes.slice(44)
	return stream
