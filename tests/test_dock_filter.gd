extends "res://tests/test_case.gd"
## The offer to set the project's texture filter to Nearest, with a stub in place of the editor.

const DockScene := preload("res://addons/sprite_pipeline/ui/main_dock.tscn")
const MainDock := preload("res://addons/sprite_pipeline/ui/main_dock.gd")
const ConsentGate := preload("res://addons/sprite_pipeline/remediation/consent_gate.gd")
const SETTINGS_PATH := "user://sprite_pipeline_settings.cfg"
const MANIFEST := {"version": 2, "results": [], "errors": []}


## Records the dock's editor calls; the project filter starts at Linear
class StubEditor extends RefCounted:
	var editor := true
	var filter := 1
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


func _dock(stub: StubEditor) -> Node:
	var dock := DockScene.instantiate()
	tree.root.add_child(dock)
	dock._editor = stub
	dock._filter_prompt_dismissed = false
	return dock


## The consent dialog open under the dock, or null
func _dialog(dock: Node) -> ConfirmationDialog:
	for child in dock.get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion():
			return child
	return null


func test_completion_offers_nearest_and_applies_it() -> void:
	var stub := StubEditor.new()
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	check(dock.filter_row.visible, "filter row shown in the editor")
	check_eq(dock.filter_label.text, "Pixel-art filtering: Linear ⚠", "label before")
	var dialog := _dialog(dock)
	check(dialog != null and dialog.visible, "dialog shown")
	if dialog:
		dialog.get_ok_button().pressed.emit()
	check(stub.calls.has("set_project_filter_nearest"), "setting applied")
	check_eq(dock.status_text.text, "Project texture filter set to Nearest", "status")
	check_eq(dock.filter_label.text, "Pixel-art filtering: Nearest ✓", "label after")
	check(not dock.filter_button.visible, "button hidden once Nearest")
	dock.free()


func test_not_now_leaves_the_project_alone() -> void:
	var stub := StubEditor.new()
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	var dialog := _dialog(dock)
	check(dialog != null, "dialog shown")
	if dialog:
		dialog.get_cancel_button().pressed.emit()
	check(not stub.calls.has("set_project_filter_nearest"), "setting untouched")
	check(not dock._filter_prompt_dismissed, "asks again next time")
	await tree.process_frame
	await dock._on_generation_completed(MANIFEST)
	check(_dialog(dock) != null, "offered again after the next generation")
	dock.free()


func test_dont_ask_again_is_saved_and_the_button_still_asks() -> void:
	var stub := StubEditor.new()
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	var dialog := _dialog(dock)
	check(dialog != null, "dialog shown")
	if dialog:
		(dialog.find_child(ConsentGate.DONT_ASK_AGAIN_NODE, true, false) as CheckBox).button_pressed = true
		dialog.get_cancel_button().pressed.emit()
	check(dock._filter_prompt_dismissed, "dismissed")
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	check_eq(config.get_value("editor", "filter_prompt_dismissed", false), true, "saved to the settings file")

	await tree.process_frame
	await dock._on_generation_completed(MANIFEST)
	check(_dialog(dock) == null, "not offered after the next generation")
	check(dock.filter_button.visible, "button still there")
	dock._on_filter_button_pressed()
	dialog = _dialog(dock)
	check(dialog != null, "button opens the dialog anyway")
	if dialog:
		dialog.get_cancel_button().pressed.emit()

	dock._filter_prompt_dismissed = false
	dock._save_settings()
	dock.free()


func test_no_offer_outside_the_editor_or_when_already_nearest() -> void:
	var stub := StubEditor.new()
	stub.editor = false
	var dock := _dock(stub)
	await dock._on_generation_completed(MANIFEST)
	check(_dialog(dock) == null, "no dialog outside the editor")
	check(not dock.filter_row.visible, "no filter row outside the editor")

	stub.editor = true
	stub.filter = 3
	await dock._on_generation_completed(MANIFEST)
	check(_dialog(dock) == null, "no dialog with Nearest Mipmap")
	check_eq(dock.filter_label.text, "Pixel-art filtering: Nearest Mipmap ✓", "label")
	dock.free()


func test_filter_status_text() -> void:
	check_eq(MainDock.filter_status_text(0), "Pixel-art filtering: Nearest ✓", "Nearest")
	check_eq(MainDock.filter_status_text(1), "Pixel-art filtering: Linear ⚠", "Linear")
	check_eq(MainDock.filter_status_text(2), "Pixel-art filtering: Linear Mipmap ⚠", "Linear Mipmap")
	check_eq(MainDock.filter_status_text(9), "Pixel-art filtering: Unknown ⚠", "out of range")
