extends Control
# The web build cannot read the extracted game data from the file system: the page preloads it as assets.pck (see web_shell.html) and it is mounted here.
signal ready_to_run
const PACK := "/assets.pck"
func start() -> void:
	if OS.has_feature("web") and not ProjectSettings.load_resource_pack(PACK):
		var label := Label.new()
		label.text = "Could not load the game data."
		add_child(label)
		return
	ready_to_run.emit()
