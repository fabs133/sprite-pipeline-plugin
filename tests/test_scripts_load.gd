extends "res://tests/test_case.gd"

const ADDON_DIR := "res://addons/sprite_pipeline"


func test_every_addon_script_compiles() -> void:
	for path in _scripts_under(ADDON_DIR):
		var script := load(path) as GDScript
		check(script != null and script.can_instantiate(), "%s compiles" % path)


func _scripts_under(dir: String) -> Array[String]:
	var paths: Array[String] = []
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(".gd"):
			paths.append(dir.path_join(file_name))
	for sub_dir in DirAccess.get_directories_at(dir):
		paths.append_array(_scripts_under(dir.path_join(sub_dir)))
	return paths
