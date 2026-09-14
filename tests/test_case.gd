extends RefCounted
## Base class for headless tests: checks record failures instead of stopping the run.

var failures: Array[String] = []
## The runner's SceneTree, for timers and nodes in async tests
var tree: SceneTree


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected %s, got %s" % [message, var_to_str(expected), var_to_str(actual)])


## A fresh empty directory under user://tests/ for this test's files
func make_temp_dir(prefix: String) -> String:
	var path := "user://tests/%s_%d" % [prefix, randi()]
	DirAccess.make_dir_recursive_absolute(path)
	return path


## Delete a directory and everything below it
func remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(path):
		remove_dir(path.path_join(dir_name))
	DirAccess.remove_absolute(path)
