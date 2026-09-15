extends "res://tests/test_case.gd"
## The dock's editor steps after a generation, with a stub in place of the editor.

const DockScene := preload("res://addons/sprite_pipeline/ui/main_dock.tscn")
const StubEditor := preload("res://tests/stub_editor.gd")
const Writer := preload("res://addons/sprite_pipeline/spriteframes_writer.gd")
const SETTINGS_PATH := "user://sprite_pipeline_settings.cfg"
const ROOT := "res://assets/sprites"
const MANIFEST := {"version": 2, "errors": [], "results": [
	{"file_path": "characters/hero.png", "frame_paths": ["characters/hero/frame_0_0.png", "characters/hero/frame_0_1.png"], "frames": 2, "rows": 1, "frame_w": 32, "frame_h": 32},
]}


## A dock with default editor settings that never shows the texture filter dialog
func _dock(stub: StubEditor) -> Node:
	var dock := DockScene.instantiate()
	tree.root.add_child(dock)
	dock._editor = stub
	dock._last_output_root = ROOT
	dock._pin_import_params = true
	dock._spriteframes_loop = true
	dock._overwrite_spriteframes = false
	dock.write_spriteframes_check.set_pressed_no_signal(true)
	dock.spriteframes_fps_spin.set_value_no_signal(8.0)
	dock._filter_prompt_dismissed = true
	return dock


## Wait for completion steps started without await: the stub's scan takes one frame
func _editor_steps_done() -> void:
	await tree.process_frame
	await tree.process_frame


func test_import_settings_are_pinned_after_the_scan() -> void:
	var stub := StubEditor.new()
	stub.pinned = PackedStringArray(["a.png", "b.png", "c.png"])
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	check_eq(str(stub.calls), str(["scan_and_wait", "pin_import_params", "write_spriteframes"]), "scan, pin, then SpriteFrames")
	check_eq(stub.pin_requested, PackedStringArray([
		ROOT + "/characters/hero.png",
		ROOT + "/characters/hero/frame_0_0.png",
		ROOT + "/characters/hero/frame_0_1.png",
	]), "sheet and frames under the output root")
	check_eq(stub.wait_requested, stub.pin_requested, "the scan waits for the import of the files it pins")
	check_eq(dock.status_text.text, "Generation complete! Import settings pinned for 3 files", "status")
	dock.free()


func test_status_unchanged_when_nothing_needed_pinning() -> void:
	var stub := StubEditor.new()
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	check_eq(dock.status_text.text, "Generation complete!", "status")
	check_eq(dock.results_label.text, "Results: 1 success, 0 errors", "results")
	dock.free()


func test_pinning_can_be_turned_off() -> void:
	var stub := StubEditor.new()
	var dock := _dock(stub)
	dock._pin_import_params = false
	await dock._on_generation_completed(MANIFEST)
	check_eq(str(stub.calls), str(["scan_and_wait", "write_spriteframes"]), "no pinning")
	dock.free()


func test_spriteframes_are_written_scanned_and_linked() -> void:
	var stub := StubEditor.new()
	stub.spriteframes = {
		ROOT + "/characters/hero.tres": Writer.WRITE,
		ROOT + "/monsters/slime.tres": Writer.UPDATE,
		ROOT + "/monsters/bat.generated.tres": Writer.GENERATED,
	}
	var dock := _dock(stub)
	dock.spriteframes_fps_spin.set_value_no_signal(12.0)
	dock._spriteframes_loop = false
	dock._overwrite_spriteframes = true
	await dock._on_generation_completed(MANIFEST)
	check_eq(str(stub.calls), str(["scan_and_wait", "pin_import_params", "write_spriteframes", "scan"]), "scan again after writing")
	check_eq(str(stub.spriteframes_args), str([ROOT, 12.0, false, true]), "output root, fps, loop, overwrite")
	check_eq(dock.results_label.text, "Results: 1 success, 0 errors, 3 SpriteFrames saved", "results")
	check_eq(dock.status_text.text, "Generation complete! SpriteFrames: 1 written, 1 updated, 1 written as .generated.tres next to a .tres the plugin didn't write", "status")
	var links: Array[Node] = dock.spriteframes_links.get_children()
	check_eq(links.size(), 3, "one link per file")
	if links.size() == 3:
		check_eq(links[0].text, "characters/hero.tres", "link text relative to the output root")
		links[2].pressed.emit()
		check_eq(stub.navigated, ROOT + "/monsters/bat.generated.tres", "a link selects its file in the FileSystem dock")
	dock.free()


func test_a_regeneration_reports_updated_spriteframes() -> void:
	var stub := StubEditor.new()
	stub.spriteframes = {ROOT + "/characters/hero.tres": Writer.UPDATE}
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	check_eq(dock.results_label.text, "Results: 1 success, 0 errors, 1 SpriteFrames saved", "results")
	check_eq(dock.status_text.text, "Generation complete! SpriteFrames: 1 updated", "status")
	dock.free()


func test_spriteframes_can_be_turned_off() -> void:
	var stub := StubEditor.new()
	stub.spriteframes = {ROOT + "/characters/hero.tres": Writer.WRITE}
	var dock := _dock(stub)
	dock.write_spriteframes_check.set_pressed_no_signal(false)
	await dock._on_generation_completed(MANIFEST)
	check_eq(str(stub.calls), str(["scan_and_wait", "pin_import_params"]), "no SpriteFrames")
	check_eq(dock.spriteframes_links.get_child_count(), 0, "no links")
	dock.free()


func test_a_failed_spriteframes_write_keeps_the_results() -> void:
	var stub := StubEditor.new()
	stub.pinned = PackedStringArray(["a.png"])
	stub.fail_spriteframes = true
	var dock := _dock(stub)
	dock._filter_prompt_dismissed = false
	await dock._on_generation_completed(MANIFEST)
	check(dock.results_section.visible, "results shown")
	check_eq(dock.results_label.text, "Results: 1 success, 0 errors", "results")
	check_eq(dock.status_text.text, "Generation complete! Import settings pinned for 1 files", "status")
	check(not stub.calls.has("scan"), "nothing to rescan")
	check(dock.filter_row.visible, "the steps after it still ran")
	for child in dock.get_children():
		if child is ConfirmationDialog:
			child.get_cancel_button().pressed.emit()
	await tree.process_frame
	dock._filter_prompt_dismissed = true
	dock.free()


func test_the_next_generation_clears_the_links() -> void:
	var stub := StubEditor.new()
	stub.spriteframes = {ROOT + "/characters/hero.tres": Writer.WRITE}
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	check_eq(dock.spriteframes_links.get_child_count(), 1, "link after the first run")
	stub.spriteframes = {}
	await dock._on_generation_completed(MANIFEST)
	check_eq(dock.spriteframes_links.get_child_count(), 0, "no stale link after the second run")
	dock.free()


func test_editor_settings_are_saved_and_loaded() -> void:
	var stub := StubEditor.new()
	var dock := _dock(stub)
	dock._pin_import_params = false
	dock._spriteframes_loop = false
	dock._overwrite_spriteframes = true
	dock.write_spriteframes_check.set_pressed_no_signal(false)
	dock.spriteframes_fps_spin.set_value_no_signal(15.0)
	dock._save_settings()

	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	check_eq(config.get_value("editor", "spriteframes_fps"), 15.0, "fps in the settings file")
	var reloaded := DockScene.instantiate()
	tree.root.add_child(reloaded)
	check_eq(reloaded._pin_import_params, false, "pin_import_params")
	check_eq(reloaded._spriteframes_loop, false, "spriteframes_loop")
	check_eq(reloaded._overwrite_spriteframes, true, "overwrite_spriteframes")
	check_eq(reloaded.write_spriteframes_check.button_pressed, false, "write_spriteframes")
	check_eq(reloaded.spriteframes_fps_spin.value, 15.0, "spriteframes_fps")
	reloaded.free()

	# Put the defaults back for the other tests
	dock.free()
	dock = _dock(stub)
	dock._save_settings()
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
	check_eq(str(stub.calls), str(["scan_and_wait"]), "nothing pinned or written for the finished run")
	dock._is_generating = false
	dock.free()


func test_outside_the_editor_no_editor_steps() -> void:
	var stub := StubEditor.new()
	stub.editor = false
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	check_eq(str(stub.calls), str([]), "no calls")
	check_eq(dock.status_text.text, "Generation complete!", "status")
	dock.free()
