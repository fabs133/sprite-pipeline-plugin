@tool
class_name SpritePipelineClient
extends RefCounted
## HTTP client for Sprite Pipeline API calls.
##
## Handles both BYOK (direct OpenAI) and Pool (backend server) modes.
## Includes proper error handling, retries, and header management.

signal request_completed(response: Dictionary)
signal request_failed(error: Dictionary)
signal progress_updated(stage: String, percent: int)

const OPENAI_API_BASE := "https://api.openai.com/v1"

# Protocol constants
const PROTOCOL_VERSION := "1"
const PLUGIN_VERSION := "0.1.0"

# Timeout settings
const DEFAULT_TIMEOUT := 120.0  # 2 minutes for image generation
const CONNECT_TIMEOUT := 10.0

# Retry settings
const MAX_RETRIES := 3
const RETRY_BACKOFF_BASE := 1.0

var _http: HTTPRequest
var _mode: String = "byok"  # "byok" or "pool"
var _api_key: String = ""
var _server_url: String = ""
var _access_token: String = ""

# Current request tracking
var _current_job_id: String = ""
var _current_idempotency_key: String = ""
var _is_cancelled: bool = false


func _init() -> void:
	pass


## Configure for BYOK mode (direct OpenAI)
func configure_byok(api_key: String) -> void:
	_mode = "byok"
	_api_key = api_key
	_server_url = ""
	_access_token = ""


## Configure for Pool mode (backend server)
func configure_pool(server_url: String, access_token: String) -> void:
	_mode = "pool"
	_api_key = ""
	_server_url = server_url.trim_suffix("/")
	_access_token = access_token


## Check if client is configured
func is_configured() -> bool:
	if _mode == "byok":
		return _api_key.length() > 0 and _api_key.begins_with("sk-")
	else:
		return _server_url.length() > 0 and _access_token.length() > 0


## Get current mode
func get_mode() -> String:
	return _mode


## Generate a unique client job ID
func generate_job_id() -> String:
	var uuid := []
	for i in range(16):
		uuid.append(randi() % 256)
	# Set version (4) and variant bits
	uuid[6] = (uuid[6] & 0x0f) | 0x40
	uuid[8] = (uuid[8] & 0x3f) | 0x80
	var hex := ""
	for b in uuid:
		hex += "%02x" % b
	return "job_%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12)
	]


## Generate idempotency key from inputs
func generate_idempotency_key(queue_hash: String, style: String) -> String:
	var data := "%s|%s|%s" % [queue_hash, style, Time.get_unix_time_from_system()]
	return "idem_%s" % data.sha256_text().substr(0, 32)


## Build common headers for requests
func _build_headers(include_auth: bool = true) -> PackedStringArray:
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Plugin-Version: %s" % PLUGIN_VERSION,
		"X-Protocol-Version: %s" % PROTOCOL_VERSION,
	])

	if _current_job_id:
		headers.append("X-Client-Job-Id: %s" % _current_job_id)

	if _current_idempotency_key:
		headers.append("X-Idempotency-Key: %s" % _current_idempotency_key)

	if include_auth:
		if _mode == "byok":
			headers.append("Authorization: Bearer %s" % _api_key)
		elif _access_token:
			headers.append("Authorization: Bearer %s" % _access_token)

	return headers


## Parse error response into structured format
func _parse_error(status_code: int, body: String, headers: Dictionary) -> Dictionary:
	var error := {
		"code": "UNKNOWN_ERROR",
		"status_code": status_code,
		"message": "Unknown error occurred",
		"stage": "unknown",
		"retryable": false,
		"retry_after_ms": 0,
		"request_id": headers.get("x-request-id", ""),
		"client_job_id": _current_job_id,
		"idempotency_key": _current_idempotency_key,
		"protocol_version": PROTOCOL_VERSION,
		"plugin_version": PLUGIN_VERSION,
		"details": {}
	}

	# Parse JSON body if available
	if body.length() > 0:
		var json := JSON.new()
		if json.parse(body) == OK:
			var data: Dictionary = json.get_data()
			if data.has("error"):
				var err_data: Dictionary = data["error"]
				error["code"] = err_data.get("code", error["code"])
				error["message"] = err_data.get("message", error["message"])
				error["stage"] = err_data.get("stage", error["stage"])
				error["retryable"] = err_data.get("retryable", error["retryable"])
				error["details"] = err_data.get("details", {})

	# Handle specific HTTP status codes
	match status_code:
		426:
			error["code"] = "UPGRADE_REQUIRED"
			error["message"] = "Plugin version too old. Please update to continue."
			error["retryable"] = false
		429:
			error["code"] = "RATE_LIMITED"
			error["message"] = "Too many requests. Please wait before trying again."
			error["retryable"] = true
			# Parse Retry-After header
			var retry_after := headers.get("retry-after", "60")
			if retry_after.is_valid_int():
				error["retry_after_ms"] = int(retry_after) * 1000
		402:
			error["code"] = "QUOTA_EXCEEDED"
			error["message"] = "Quota exhausted. Please add more credits or wait for reset."
			error["retryable"] = false
		403:
			error["code"] = "UNAUTHORIZED"
			error["message"] = "Authentication failed. Please check your credentials."
			error["retryable"] = false
		401:
			error["code"] = "INVALID_AUTH"
			error["message"] = "Invalid authentication token."
			error["retryable"] = false

	# Check for content policy in message
	if "content policy" in error["message"].to_lower() or "safety" in error["message"].to_lower():
		error["code"] = "CONTENT_POLICY"
		error["stage"] = "content_policy"
		error["retryable"] = false

	return error


## Format error for clipboard copy
func format_error_summary(error: Dictionary) -> String:
	var lines := PackedStringArray([
		"=== Sprite Pipeline Error Summary ===",
		"",
		"Error Code: %s" % error.get("code", "UNKNOWN"),
		"Status: %d" % error.get("status_code", 0),
		"Message: %s" % error.get("message", "No message"),
		"Stage: %s" % error.get("stage", "unknown"),
		"",
		"Request ID: %s" % error.get("request_id", "N/A"),
		"Client Job ID: %s" % error.get("client_job_id", "N/A"),
		"Idempotency Key: %s" % error.get("idempotency_key", "N/A"),
		"",
		"Plugin Version: %s" % error.get("plugin_version", PLUGIN_VERSION),
		"Protocol Version: %s" % error.get("protocol_version", PROTOCOL_VERSION),
		"Mode: %s" % _mode,
		"",
		"Retryable: %s" % ("Yes" if error.get("retryable", false) else "No"),
	])

	if error.get("retry_after_ms", 0) > 0:
		lines.append("Retry After: %d seconds" % (error["retry_after_ms"] / 1000))

	if error.get("details", {}).size() > 0:
		lines.append("")
		lines.append("Details: %s" % JSON.stringify(error["details"]))

	lines.append("")
	lines.append("Generated: %s" % Time.get_datetime_string_from_system())
	lines.append("================================")

	return "\n".join(lines)


## Cancel current request
func cancel() -> void:
	_is_cancelled = true
	if _http:
		_http.cancel_request()


## Check if request was cancelled
func is_cancelled() -> bool:
	return _is_cancelled


## Reset cancellation state
func reset_cancellation() -> void:
	_is_cancelled = false
