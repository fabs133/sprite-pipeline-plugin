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


## Arguments of the last scan_and_wait call
var wait_requested := PackedStringArray()


## Takes a frame, like a real scan
func scan_and_wait(imported_paths := PackedStringArray(), _timeout_msec := 0) -> void:
	calls.append("scan_and_wait")
	wait_requested = imported_paths
	await (Engine.get_main_loop() as SceneTree).process_frame


func reimport(_paths: PackedStringArray) -> void:
	calls.append("reimport")


func pin_import_params(png_paths: PackedStringArray) -> PackedStringArray:
	calls.append("pin_import_params")
	pin_requested = png_paths
	return pinned


## Returned by write_spriteframes: {path: SpriteFramesWriter action}
var spriteframes := {}
## write_spriteframes returns null, as a call that failed with a script error would
var fail_spriteframes := false
## Arguments of the last write_spriteframes call: [output_root, fps, loop, overwrite]
var spriteframes_args := []
var navigated := ""


func write_spriteframes(_manifest: Dictionary, output_root: String, fps: float, loop: bool, overwrite := false):
	calls.append("write_spriteframes")
	spriteframes_args = [output_root, fps, loop, overwrite]
	return null if fail_spriteframes else spriteframes


func navigate_to(path: String) -> void:
	calls.append("navigate_to")
	navigated = path
