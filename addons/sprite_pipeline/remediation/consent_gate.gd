@tool
class_name ConsentGate
extends RefCounted
## Manages consent tokens for remediation actions.
##
## Before executing any remediation action that modifies user data,
## the user must explicitly consent. This prevents accidental or
## unauthorized changes.

signal consent_granted(action_id: String, token: String)
signal consent_denied(action_id: String)
## A consent dialog was answered or closed; carries the dialog's instance id
signal _dialog_closed(dialog_id: int)

## Active consent tokens: action_id -> {token, expires_at, action_name}
var _active_consents: Dictionary = {}

## Token validity duration (5 minutes)
const TOKEN_VALIDITY_MS := 5 * 60 * 1000

## Action changing the project's default 2D texture filter (project.godot)
const PROJECT_FILTER_NEAREST := "project_filter_nearest"
## Name of the "Don't ask again" checkbox in dialogs of actions with dont_ask_again
const DONT_ASK_AGAIN_NODE := "DontAskAgain"

## Action catalog with metadata. Optional dialog keys: title, dialog_text (replaces the
## generated text), ok_text, cancel_text, dont_ask_again (adds a checkbox).
const ACTION_CATALOG := {
	PROJECT_FILTER_NEAREST: {
		"name": "Set Project Texture Filter to Nearest",
		"description": "Set the project's default 2D texture filter to Nearest so pixel art stays sharp",
		"risk_level": "low",
		"requires_consent": true,
		"changes": ["Sets rendering/textures/canvas_textures/default_texture_filter in project.godot", "Affects all 2D textures"],
		"title": "Pixel-Art Filtering",
		"dialog_text": "Your project uses Linear texture filtering, which blurs pixel art. Set the project default to Nearest? This adds a texture-filter setting to project.godot and affects all 2D textures. (You can change it back under Project Settings → Rendering → Textures.)",
		"ok_text": "Set to Nearest",
		"cancel_text": "Not now",
		"dont_ask_again": true,
	},
	"auth_reset": {
		"name": "Reset Authentication",
		"description": "Clear stored tokens and restart login flow",
		"risk_level": "low",
		"requires_consent": true,
		"changes": ["Clears access token", "Clears refresh token", "Requires re-login"]
	},
	"refresh_token": {
		"name": "Refresh Access Token",
		"description": "Request new access token using refresh token",
		"risk_level": "none",
		"requires_consent": false,
		"changes": ["Updates access token"]
	},
	"reimport_manifest": {
		"name": "Re-import Assets",
		"description": "Re-import assets from last successful manifest",
		"risk_level": "low",
		"requires_consent": true,
		"changes": ["May overwrite existing sprite files", "Triggers Godot reimport"]
	},
	"clean_cache": {
		"name": "Clean Plugin Cache",
		"description": "Delete cached data in user:// directory",
		"risk_level": "medium",
		"requires_consent": true,
		"changes": ["Deletes sprite_pipeline_settings.cfg", "Clears cached manifests", "Requires reconfiguration"]
	},
	"toggle_safe_mode": {
		"name": "Toggle Safe Mode",
		"description": "Enable/disable safe mode fallback for content policy",
		"risk_level": "low",
		"requires_consent": true,
		"changes": ["Modifies generation behavior"]
	}
}


## Request consent for an action
## Returns a consent token if user approves, empty string if denied
func request_consent(action_id: String, parent_node: Node) -> String:
	var answer: Dictionary = await ask(action_id, parent_node)
	return answer["token"]


## Show the consent dialog for an action under parent_node and wait for the answer.
## Returns {token, dont_ask_again}: token is empty unless the user confirmed;
## dont_ask_again is the state of the dialog's checkbox (false without one).
func ask(action_id: String, parent_node: Node) -> Dictionary:
	var answer := {"token": "", "dont_ask_again": false}
	if action_id not in ACTION_CATALOG:
		push_error("[ConsentGate] Unknown action: %s" % action_id)
		return answer

	# No consent needed for safe actions
	if not ACTION_CATALOG[action_id].get("requires_consent", true):
		answer["token"] = _generate_token(action_id)
		return answer

	var dialog := create_dialog(action_id)
	parent_node.add_child(dialog)
	var dialog_id := dialog.get_instance_id()
	# Captured by reference: lambdas copy local variables, but not the dictionaries they point to
	var state := {"confirmed": false}
	# Deferred, so the caller resumes after the button's signal and the dialog's own hide
	# have finished: it may then free the dialog's parent or open the next dialog
	dialog.confirmed.connect(func():
		state["confirmed"] = true
		_dialog_closed.emit(dialog_id)
	, CONNECT_DEFERRED)
	dialog.canceled.connect(func(): _dialog_closed.emit(dialog_id), CONNECT_DEFERRED)
	dialog.popup_centered()

	# AcceptDialog hides itself before it emits confirmed, so waiting for the dialog to
	# become invisible would miss the answer
	var closed_id: int = await _dialog_closed
	while closed_id != dialog_id:
		closed_id = await _dialog_closed

	if is_instance_valid(dialog):
		var checkbox := dialog.find_child(DONT_ASK_AGAIN_NODE, true, false) as CheckBox
		answer["dont_ask_again"] = checkbox != null and checkbox.button_pressed
		dialog.queue_free()
	if state["confirmed"]:
		answer["token"] = _generate_token(action_id)
		consent_granted.emit(action_id, answer["token"])
	else:
		consent_denied.emit(action_id)
	return answer


## The consent dialog for an action, not yet added to the tree
func create_dialog(action_id: String) -> ConfirmationDialog:
	var action_info: Dictionary = ACTION_CATALOG.get(action_id, {})
	var dialog := ConfirmationDialog.new()
	dialog.title = action_info.get("title", "Confirm Action: %s" % action_info.get("name", action_id))
	dialog.ok_button_text = action_info.get("ok_text", "I Understand, Proceed")
	dialog.cancel_button_text = action_info.get("cancel_text", "Cancel")
	var text: String = action_info.get("dialog_text", _build_consent_text(action_info))

	if not action_info.get("dont_ask_again", false):
		dialog.dialog_text = text
		return dialog

	# A dialog lays every child Control over its text, so text and checkbox share a container
	var content := VBoxContainer.new()
	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	content.add_child(label)
	var checkbox := CheckBox.new()
	checkbox.name = DONT_ASK_AGAIN_NODE
	checkbox.text = "Don't ask again"
	content.add_child(checkbox)
	dialog.add_child(content)
	return dialog


## Validate a consent token
func validate_token(action_id: String, token: String) -> bool:
	if token.is_empty():
		return false

	if action_id not in _active_consents:
		return false

	var consent: Dictionary = _active_consents[action_id]
	if consent["token"] != token:
		return false

	# Check expiration
	if Time.get_ticks_msec() > consent["expires_at"]:
		_active_consents.erase(action_id)
		return false

	return true


## Consume a consent token (single use)
func consume_token(action_id: String, token: String) -> bool:
	if not validate_token(action_id, token):
		return false

	_active_consents.erase(action_id)
	return true


## Get action info from catalog
func get_action_info(action_id: String) -> Dictionary:
	return ACTION_CATALOG.get(action_id, {})


## List all available actions
func get_available_actions() -> Array:
	return ACTION_CATALOG.keys()


## Generate a consent token
func _generate_token(action_id: String) -> String:
	var token := "consent_%s_%d_%d" % [
		action_id,
		Time.get_ticks_msec(),
		randi() % 10000
	]

	_active_consents[action_id] = {
		"token": token,
		"expires_at": Time.get_ticks_msec() + TOKEN_VALIDITY_MS,
		"created_at": Time.get_datetime_string_from_system()
	}

	return token


## Build consent dialog text
func _build_consent_text(action_info: Dictionary) -> String:
	var lines := PackedStringArray()

	lines.append(action_info.get("description", ""))
	lines.append("")
	lines.append("Risk Level: %s" % action_info.get("risk_level", "unknown").to_upper())
	lines.append("")
	lines.append("This action will:")

	for change in action_info.get("changes", []):
		lines.append("  - %s" % change)

	lines.append("")
	lines.append("Do you want to proceed?")

	return "\n".join(lines)
