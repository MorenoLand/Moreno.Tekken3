extends SceneTree
# Packs the extracted game data (without the movies) into assets.pck for the web build.
# Usage: redot --headless --path . --script tools/build_web_pack.gd -- <output.pck>
func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var packer := PCKPacker.new()
	packer.pck_start(out)
	var count := _add(packer, "res://assets")
	packer.flush()
	print("packed ", count, " files")
	quit()
func _add(packer: PCKPacker, dir: String) -> int:
	var count := 0
	for name in DirAccess.get_directories_at(dir):
		if name != "movies":
			count += _add(packer, dir + "/" + name)
	for name in DirAccess.get_files_at(dir):
		if name != ".gdignore":
			packer.add_file(dir + "/" + name, dir + "/" + name)
			count += 1
	return count
