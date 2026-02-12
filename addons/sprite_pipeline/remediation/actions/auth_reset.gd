@tool
class_name RemediationAuthReset
extends RefCounted
## Remediation action: Reset authentication state.
##
## Clears all stored tokens and requires the user to re-authenticate.
## Use when: Token corruption, need to switch accounts, security concern.

const ACTION_ID := "auth_reset"
const SETTINGS_PATH := "user://sprite_pipeline_settings.cfg"


## Execute the auth reset action
## Returns: {success: bool, message: String, details: Dictionary}
func execute(consent_token: String, consent_gate: ConsentGate) -> Dictionary:
	# Validate consent
	if not consent_gate.consume_token(ACTION_ID, consent_token):
		return {
			"success": false,
			"message": "Invalid or expired consent token",
			"details": {"error": "consent_invalid"}
		}

	var cleared := {
		"access_token": false,
		"refresh_token": false,
		"config_file": false
	}

	# Load current config
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)

	if err == OK:
		# Clear pool tokens
		if config.has_section_key("pool", "access_token"):
			config.set_value("pool", "access_token", "")
			cleared["access_token"] = true

		if config.has_section_key("pool", "refresh_token"):
			config.set_value("pool", "refresh_token", "")
			cleared["refresh_token"] = true

		if config.has_section_key("pool", "token_expires_at"):
			config.set_value("pool", "token_expires_at", 0)

		# Save changes
		err = config.save(SETTINGS_PATH)
		if err == OK:
			cleared["config_file"] = true

	# Verify action
	var verification := verify()

	return {
		"success": cleared["config_file"],
		"message": "Authentication reset. Please login again." if cleared["config_file"] else "Failed to save config",
		"details": {
			"cleared": cleared,
			"verification": verification
		}
	}


## Verify the action was successful
func verify() -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)

	if err != OK:
		return {"verified": true, "reason": "Config file not found (clean state)"}

	var access_token: String = config.get_value("pool", "access_token", "")
	var refresh_token: String = config.get_value("pool", "refresh_token", "")

	var is_clean := access_token.is_empty() and refresh_token.is_empty()

	return {
		"verified": is_clean,
		"reason": "Tokens cleared" if is_clean else "Tokens still present",
		"has_access_token": not access_token.is_empty(),
		"has_refresh_token": not refresh_token.is_empty()
	}
