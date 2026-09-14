extends RefCounted
## Stand-in for editor_integration.gd in dock tests: records the dock's calls in order and
## returns canned results. The project filter starts at Linear.

var editor := true
var filter := 1
## Returned by pin_import_params
var pinned := PackedStringArray()
## Arguments of the last pin_import_params call
var pin_requested := PackedStringArray()
var calls: Array[String] = []


func is_editor() -> bool:
	return editor


func project_filter() -> int:
	return filter


func project_filter_is_nearest() -> bool:
	return filter == 0 or filter == 3


func set_project_filter_nearest() -> Error:
	calls.append("set_project_filter_nearest")
	filter = 0
	return OK


func scan() -> void:
	calls.append("scan")


## Takes a frame, like a real scan
func scan_and_wait(_timeout_msec := 0) -> void:
	calls.append("scan_and_wait")
	await (Engine.get_main_loop() as SceneTree).process_frame


func reimport(_paths: PackedStringArray) -> void:
	calls.append("reimport")


func pin_import_params(png_paths: PackedStringArray) -> PackedStringArray:
	calls.append("pin_import_params")
	pin_requested = png_paths
	return pinned
