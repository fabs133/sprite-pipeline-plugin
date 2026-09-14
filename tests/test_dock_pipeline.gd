extends "res://tests/test_case.gd"
## The dock's editor steps after a generation, with a stub in place of the editor.

const DockScene := preload("res://addons/sprite_pipeline/ui/main_dock.tscn")
const StubEditor := preload("res://tests/stub_editor.gd")
const SETTINGS_PATH := "user://sprite_pipeline_settings.cfg"
const ROOT := "res://assets/sprites"
const MANIFEST := {"version": 2, "errors": [], "results": [
	{"file_path": "characters/hero.png", "frame_paths": ["characters/hero/frame_0_0.png", "characters/hero/frame_0_1.png"], "frames": 2, "rows": 1, "frame_w": 32, "frame_h": 32},
]}


func _dock(stub: StubEditor) -> Node:
	var dock := DockScene.instantiate()
	tree.root.add_child(dock)
	dock._editor = stub
	dock._last_output_root = ROOT
	dock._pin_import_params = true
	# Keeps the texture filter dialog out of these tests
	dock._filter_prompt_dismissed = true
	return dock


func test_import_settings_are_pinned_after_the_scan() -> void:
	var stub := StubEditor.new()
	stub.pinned = PackedStringArray(["a.png", "b.png", "c.png"])
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	check_eq(str(stub.calls), str(["scan_and_wait", "pin_import_params"]), "scan, then pin")
	check_eq(stub.pin_requested, PackedStringArray([
		ROOT + "/characters/hero.png",
		ROOT + "/characters/hero/frame_0_0.png",
		ROOT + "/characters/hero/frame_0_1.png",
	]), "sheet and frames under the output root")
	check_eq(dock.status_text.text, "Generation complete! Import settings pinned for 3 files", "status")
	dock.free()


func test_status_unchanged_when_nothing_needed_pinning() -> void:
	var stub := StubEditor.new()
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	check_eq(dock.status_text.text, "Generation complete!", "status")
	dock.free()


func test_pinning_can_be_turned_off() -> void:
	var stub := StubEditor.new()
	var dock := _dock(stub)
	dock._pin_import_params = false
	await dock._on_generation_completed(MANIFEST)
	check_eq(str(stub.calls), str(["scan_and_wait"]), "scan only")
	dock.free()


func test_pin_setting_is_saved() -> void:
	var stub := StubEditor.new()
	var dock := _dock(stub)
	dock._pin_import_params = false
	dock._save_settings()
	var reloaded := DockScene.instantiate()
	tree.root.add_child(reloaded)
	check_eq(reloaded._pin_import_params, false, "loaded from the settings file")
	dock._pin_import_params = true
	dock._save_settings()
	reloaded.free()
	dock.free()


func test_results_show_while_the_editor_steps_run() -> void:
	var stub := StubEditor.new()
	var dock := _dock(stub)
	dock._is_generating = true
	# Not awaited: the stub's scan takes a frame, so the editor steps are still running
	dock._on_generation_completed(MANIFEST)
	check(dock.results_section.visible, "results visible during the scan")
	check(not dock._is_generating, "generation finished")
	check(dock.generate_button.visible, "Generate is available again")
	await _editor_steps_done()
	dock.free()


func test_a_new_generation_during_the_scan_stops_the_editor_steps() -> void:
	var stub := StubEditor.new()
	stub.pinned = PackedStringArray(["a.png"])
	var dock := _dock(stub)
	dock._on_generation_completed(MANIFEST)
	dock._is_generating = true
	await _editor_steps_done()
	check_eq(str(stub.calls), str(["scan_and_wait"]), "nothing pinned for the finished run")
	dock._is_generating = false
	dock.free()


## Wait for completion steps started without await: the stub's scan takes one frame
func _editor_steps_done() -> void:
	await tree.process_frame
	await tree.process_frame


func test_outside_the_editor_no_editor_steps() -> void:
	var stub := StubEditor.new()
	stub.editor = false
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	check_eq(str(stub.calls), str([]), "no calls")
	check_eq(dock.status_text.text, "Generation complete!", "status")
	dock.free()
