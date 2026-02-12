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

## Active consent tokens: action_id -> {token, expires_at, action_name}
var _active_consents: Dictionary = {}

## Token validity duration (5 minutes)
const TOKEN_VALIDITY_MS := 5 * 60 * 1000

## Action catalog with metadata
const ACTION_CATALOG := {
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
	if action_id not in ACTION_CATALOG:
		push_error("[ConsentGate] Unknown action: %s" % action_id)
		return ""

	var action_info: Dictionary = ACTION_CATALOG[action_id]

	# No consent needed for safe actions
	if not action_info.get("requires_consent", true):
		return _generate_token(action_id)

	# Show consent dialog
	var dialog := AcceptDialog.new()
	dialog.title = "Confirm Action: %s" % action_info["name"]
	dialog.dialog_text = _build_consent_text(action_info)
	dialog.ok_button_text = "I Understand, Proceed"
	dialog.add_cancel_button("Cancel")

	parent_node.add_child(dialog)

	var result := ""

	dialog.confirmed.connect(func():
		result = _generate_token(action_id)
		consent_granted.emit(action_id, result)
	)

	dialog.canceled.connect(func():
		consent_denied.emit(action_id)
	)

	dialog.popup_centered()

	# Wait for dialog to close
	await dialog.visibility_changed
	if dialog.visible == false:
		dialog.queue_free()

	return result


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
