@tool
class_name RemediationCleanCache
extends RefCounted
## Remediation action: Clean plugin cache.
##
## Deletes all cached data in user:// directory related to the plugin.
## Use when: Corrupted state, fresh start needed, troubleshooting.

const ACTION_ID := "clean_cache"

## Files to clean
const CACHE_FILES := [
	"user://sprite_pipeline_settings.cfg",
	"user://sprite_pipeline_last_manifest.json",
	"user://sprite_pipeline_events.jsonl"
]


## Execute the cache clean action
## Returns: {success: bool, message: String, details: Dictionary}
func execute(consent_token: String, consent_gate: ConsentGate) -> Dictionary:
	# Validate consent
	if not consent_gate.consume_token(ACTION_ID, consent_token):
		return {
			"success": false,
			"message": "Invalid or expired consent token",
			"details": {"error": "consent_invalid"}
		}

	var deleted := []
	var failed := []
	var not_found := []

	for file_path in CACHE_FILES:
		if FileAccess.file_exists(file_path):
			var err := DirAccess.remove_absolute(file_path)
			if err == OK:
				deleted.append(file_path)
			else:
				failed.append({"path": file_path, "error": error_string(err)})
		else:
			not_found.append(file_path)

	var all_success := failed.is_empty()

	# Verify action
	var verification := verify()

	return {
		"success": all_success,
		"message": "Cache cleaned successfully" if all_success else "Some files could not be deleted",
		"details": {
			"deleted": deleted,
			"failed": failed,
			"not_found": not_found,
			"verification": verification
		}
	}


## Verify the action was successful
func verify() -> Dictionary:
	var remaining := []

	for file_path in CACHE_FILES:
		if FileAccess.file_exists(file_path):
			remaining.append(file_path)

	return {
		"verified": remaining.is_empty(),
		"reason": "All cache files removed" if remaining.is_empty() else "Some files remain",
		"remaining_files": remaining
	}
