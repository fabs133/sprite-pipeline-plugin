extends "res://tests/test_case.gd"
## Consent dialogs: the answer, the token and the "Don't ask again" checkbox.

const ConsentGate := preload("res://addons/sprite_pipeline/remediation/consent_gate.gd")


func _parent() -> Node:
	var parent := Node.new()
	tree.root.add_child(parent)
	return parent


## Answer the dialog shown under parent on the next frame
func _answer_later(parent: Node, confirm: bool, dont_ask_again := false) -> void:
	await tree.process_frame
	var dialog: ConfirmationDialog = null
	for child in parent.get_children():
		if child is ConfirmationDialog:
			dialog = child
	if dialog == null:
		failures.append("no dialog shown")
		return
	if dont_ask_again:
		(dialog.find_child(ConsentGate.DONT_ASK_AGAIN_NODE, true, false) as CheckBox).button_pressed = true
	var button := dialog.get_ok_button() if confirm else dialog.get_cancel_button()
	button.pressed.emit()


func test_confirming_returns_a_usable_token() -> void:
	var gate := ConsentGate.new()
	var parent := _parent()
	_answer_later(parent, true)
	var token: String = await gate.request_consent("auth_reset", parent)
	check(not token.is_empty(), "token after OK")
	check(gate.consume_token("auth_reset", token), "token is valid")
	check(not gate.consume_token("auth_reset", token), "token is single use")
	parent.free()


func test_cancelling_returns_no_token() -> void:
	var gate := ConsentGate.new()
	var parent := _parent()
	_answer_later(parent, false)
	var answer: Dictionary = await gate.ask(ConsentGate.PROJECT_FILTER_NEAREST, parent)
	check_eq(answer["token"], "", "no token after Not now")
	check_eq(answer["dont_ask_again"], false, "checkbox left off")
	check(not gate.consume_token(ConsentGate.PROJECT_FILTER_NEAREST, answer["token"]), "empty token is rejected")
	parent.free()


func test_dont_ask_again_is_reported_with_either_answer() -> void:
	var gate := ConsentGate.new()
	var parent := _parent()
	_answer_later(parent, false, true)
	var declined: Dictionary = await gate.ask(ConsentGate.PROJECT_FILTER_NEAREST, parent)
	check_eq(declined["dont_ask_again"], true, "declined with the checkbox")

	_answer_later(parent, true, true)
	var accepted: Dictionary = await gate.ask(ConsentGate.PROJECT_FILTER_NEAREST, parent)
	check_eq(accepted["dont_ask_again"], true, "accepted with the checkbox")
	check(gate.consume_token(ConsentGate.PROJECT_FILTER_NEAREST, accepted["token"]), "accepted token is valid")
	parent.free()


func test_project_filter_dialog_texts() -> void:
	var dialog := ConsentGate.new().create_dialog(ConsentGate.PROJECT_FILTER_NEAREST)
	check_eq(dialog.get_ok_button().text, "Set to Nearest", "OK button")
	check_eq(dialog.get_cancel_button().text, "Not now", "cancel button")
	var label := dialog.find_child("Text", true, false) as Label
	check(label != null and label.text.begins_with("Your project uses Linear texture filtering, which blurs pixel art."), "dialog text")
	check(dialog.find_child(ConsentGate.DONT_ASK_AGAIN_NODE, true, false) is CheckBox, "Don't ask again checkbox")
	dialog.free()


func test_other_actions_keep_the_generated_text() -> void:
	var dialog := ConsentGate.new().create_dialog("auth_reset")
	check(dialog.dialog_text.contains("Risk Level: LOW"), "generated text")
	check_eq(dialog.get_ok_button().text, "I Understand, Proceed", "OK button")
	check(dialog.find_child(ConsentGate.DONT_ASK_AGAIN_NODE, true, false) == null, "no checkbox")
	dialog.free()
