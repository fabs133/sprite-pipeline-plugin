@tool
extends RefCounted
## Pool mode client for backend server API calls.
##
## Uses shared credits via a backend server. Includes device authentication,
## quota management, and proper error handling. Integrates with SpriteCache
## to avoid redundant API calls.
##
## Speaks protocol 2.0.0 of sprite-pipeline-backend: submit a job, poll its status,
## fetch the result, then download and verify every asset.

signal auth_started(device_code: String, user_code: String, verification_uri: String)
signal auth_completed(access_token: String)
signal auth_failed(error: Dictionary)
signal quota_updated(quota: Dictionary)
signal generation_started(job_id: String)
signal generation_progress(stage: String, message: String)
signal generation_percent(percent: int, stage: String)
signal generation_completed(manifest: Dictionary)
signal generation_failed(error: Dictionary)
signal cache_hit(inputs_hash: String)

const Version := preload("res://addons/sprite_pipeline/version.gd")
const ManifestPaths := preload("res://addons/sprite_pipeline/manifest_paths.gd")

# Preload cache class
const SpriteCacheClass = preload("res://addons/sprite_pipeline/cache/sprite_cache.gd")

# Input validation functions
static func _validate_url(url: String) -> bool:
	"""Validate server URL: HTTPS for any host, plain HTTP only for local or private-network hosts."""
	if url.is_empty():
		return false
	var is_https := url.begins_with("https://")
	if not is_https and not url.begins_with("http://"):
		push_error("Server URL must start with https:// (or http:// for a local backend)")
		return false
	var host := get_url_host(url)
	if host.is_empty():
		push_error("Server URL has no valid host")
		return false
	if not is_https and not _is_local_host(host):
		push_error("Plain http:// is only allowed for localhost or private-network addresses; use https://")
		return false
	return true

static func get_url_host(url: String) -> String:
	"""Return the lowercase host of an http(s) URL, or "" if it is malformed or contains credentials."""
	var scheme_end := url.find("://")
	if scheme_end == -1:
		return ""
	var authority := url.substr(scheme_end + 3)
	for separator in ["/", "?", "#"]:
		var separator_pos := authority.find(separator)
		if separator_pos != -1:
			authority = authority.substr(0, separator_pos)
	if authority.is_empty() or "@" in authority or " " in authority:
		return ""
	if authority.begins_with("["):
		var bracket_end := authority.find("]")
		return authority.substr(1, bracket_end - 1).to_lower() if bracket_end != -1 else ""
	var port_sep := authority.rfind(":")
	if port_sep != -1:
		authority = authority.substr(0, port_sep)
	return authority.to_lower()

static func _is_local_host(host: String) -> bool:
	"""True for localhost, loopback, and private-network (RFC 1918) IPv4 addresses."""
	if host == "localhost" or host == "::1":
		return true
	var octets := host.split(".")
	if octets.size() != 4 or not host.is_valid_ip_address():
		return false
	var first := octets[0].to_int()
	var second := octets[1].to_int()
	return first == 127 or first == 10 or (first == 192 and second == 168) or (first == 172 and second >= 16 and second <= 31)

static func _sanitize_job_id(job_id: String) -> String:
	"""Sanitize job ID to only allow safe characters."""
	var sanitized := ""
	for i in range(job_id.length()):
		var c = job_id[i]
		if c.is_valid_identifier() or c == "-" or c == "_":
			sanitized += c
	return sanitized

# Endpoints
const ENDPOINT_DEVICE_START := "/v1/auth/device-start"
const ENDPOINT_DEVICE_POLL := "/v1/auth/device-poll"
const ENDPOINT_REFRESH := "/v1/auth/refresh"
const ENDPOINT_QUOTA := "/v1/quota"
const ENDPOINT_GENERATE := "/v1/generate"
const ENDPOINT_JOB_STATUS := "/v1/jobs/%s"
const ENDPOINT_JOB_CANCEL := "/v1/jobs/%s/cancel"
const ENDPOINT_JOB_RESULT := "/v1/jobs/%s/result"

# Messages for device-poll statuses that end the login
const DEVICE_STATUS_MESSAGES := {
	"expired": "The device code expired. Click Login to get a new code.",
	"denied": "The login was denied.",
}

## Transient failures in a row (no response, or a 5xx answer) a job poll retries before giving up
const MAX_POLL_RETRIES := 3

var _server_url: String = ""
var _access_token: String = ""
var _refresh_token: String = ""
var _token_expires_at: int = 0

var _is_cancelled: bool = false
var _current_job_id: String = ""
var _current_idempotency_key: String = ""
var _current_inputs_hash: String = ""

# Sprite cache reference (optional, set externally)
var _sprite_cache = null  # SpriteCache

# Quota cache for reducing API calls
var _quota_cache: Dictionary = {}
var quota_cache_ttl: int = 300  # 5 minutes

## Also download each sprite's unprocessed sheet (assets of kind "raw")
var download_raw: bool = false
## Seconds before the second job status poll; the interval backs off to 10 s
var initial_poll_interval: float = 1.0


func _init(server_url: String) -> void:
	# An empty URL just means "not configured yet"; only malformed URLs are errors
	if server_url.is_empty():
		return
	if not _validate_url(server_url):
		push_error("Invalid server URL provided to PoolClient")
		return
	_server_url = server_url.trim_suffix("/")


## Set sprite cache instance
func set_sprite_cache(cache) -> void:
	_sprite_cache = cache


## Set authentication tokens
func set_tokens(access_token: String, refresh_token: String, expires_at: int) -> void:
	_access_token = access_token
	_refresh_token = refresh_token
	_token_expires_at = expires_at


## Check if authenticated
func is_authenticated() -> bool:
	return _access_token.length() > 0


## Check if token is expired (with 5 minute buffer)
func is_token_expired() -> bool:
	if _token_expires_at == 0:
		return true
	return Time.get_unix_time_from_system() > (_token_expires_at - 300)


## Get server URL
func get_server_url() -> String:
	return _server_url


## Generate a UUID-style job ID
func _generate_job_id() -> String:
	var uuid := []
	for i in range(16):
		uuid.append(randi() % 256)
	uuid[6] = (uuid[6] & 0x0f) | 0x40
	uuid[8] = (uuid[8] & 0x3f) | 0x80
	var hex := ""
	for b in uuid:
		hex += "%02x" % b
	return "pool_%s" % hex.substr(0, 16)


## Generate idempotency key
func _generate_idempotency_key(inputs_hash: String) -> String:
	var data := "%s|%d" % [inputs_hash, Time.get_unix_time_from_system()]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data.to_utf8_buffer())
	return "idem_%s" % ctx.finish().hex_encode().substr(0, 32)


## Build common headers
func _build_headers() -> PackedStringArray:
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Plugin-Version: %s" % Version.PLUGIN,
		"X-Protocol-Version: %s" % Version.PROTOCOL,
	])

	if _current_job_id:
		headers.append("X-Client-Job-Id: %s" % _current_job_id)

	if _current_idempotency_key:
		headers.append("X-Idempotency-Key: %s" % _current_idempotency_key)

	if _access_token:
		headers.append("Authorization: Bearer %s" % _access_token)

	return headers


## Make HTTP request and handle common errors
func _make_request(method: int, endpoint: String, body: Dictionary = {}) -> Dictionary:
	if _server_url.is_empty():
		return {
			"success": false,
			"error": {
				"code": "NO_SERVER_URL",
				"message": "No valid server URL configured",
				"status_code": 0
			}
		}

	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)

	var url := _server_url + endpoint
	var headers := _build_headers()

	var body_str := ""
	if body.size() > 0:
		body_str = JSON.stringify(body)

	var error: int
	if method == HTTPClient.METHOD_GET:
		error = http.request(url, headers, method)
	else:
		error = http.request(url, headers, method, body_str)

	if error != OK:
		http.queue_free()
		return {
			"success": false,
			"error": {
				"code": "REQUEST_FAILED",
				"message": "Failed to start request: %d" % error,
				"status_code": 0
			}
		}

	var response: Array = await http.request_completed
	http.queue_free()

	var result_code: int = response[0]
	var status_code: int = response[1]
	var response_headers: PackedStringArray = response[2]
	var response_body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {
			"success": false,
			"error": {
				"code": "HTTP_FAILED",
				"message": "HTTP request failed: %d" % result_code,
				"status_code": 0
			}
		}

	var body_text := response_body.get_string_from_utf8()

	# Parse response headers into dictionary
	var header_dict := {}
	for h in response_headers:
		var parts := h.split(":", true, 1)
		if parts.size() == 2:
			header_dict[parts[0].to_lower().strip_edges()] = parts[1].strip_edges()

	# Handle error status codes
	if status_code >= 400:
		return _handle_error_response(status_code, body_text, header_dict)

	# Parse success response
	var json := JSON.new()
	if json.parse(body_text) != OK:
		return {
			"success": true,
			"status_code": status_code,
			"data": {},
			"raw": body_text
		}

	return {
		"success": true,
		"status_code": status_code,
		"data": json.get_data(),
		"headers": header_dict
	}


## Handle error response
func _handle_error_response(status_code: int, body_text: String, headers: Dictionary) -> Dictionary:
	var error := {
		"code": "API_ERROR",
		"message": "API error: %d" % status_code,
		"status_code": status_code,
		"stage": "unknown",
		"retryable": false,
		"retry_after_ms": 0,
		"request_id": headers.get("x-request-id", ""),
		"client_job_id": _current_job_id,
		"inputs_hash": "",
		"protocol_version": Version.PROTOCOL,
		"plugin_version": Version.PLUGIN
	}

	var parsed := parse_error_body(body_text)
	error.merge(parsed, true)

	# Handle specific status codes; a message from the server wins over the fallback text
	match status_code:
		426:
			error["code"] = "UPGRADE_REQUIRED"
			error["retryable"] = false
			if not parsed.has("message"):
				error["message"] = "Plugin version too old. Please update."
		429:
			error["code"] = "RATE_LIMITED"
			error["retryable"] = true
			var retry_after: String = headers.get("retry-after", "60")
			if retry_after.is_valid_int():
				error["retry_after_ms"] = int(retry_after) * 1000
		402:
			error["code"] = "QUOTA_EXCEEDED"
			error["retryable"] = false
			if not parsed.has("message"):
				error["message"] = "Quota exhausted. Add credits or wait for reset."
		403:
			error["code"] = "FORBIDDEN"
			error["retryable"] = false
		401:
			error["code"] = "UNAUTHORIZED"
			error["retryable"] = false

	return {
		"success": false,
		"error": error
	}


## Fields of an error response body. Reads the {"error": {...}} envelope of the plugin
## protocol and FastAPI's {"detail": ...}, where the backend puts
## {"error": "<code>", "message": "..."}. Returns only the fields found.
static func parse_error_body(body_text: String) -> Dictionary:
	var parsed := {}
	var json := JSON.new()
	if json.parse(body_text) != OK or not json.data is Dictionary:
		return parsed
	var data: Dictionary = json.data

	var envelope = data.get("error")
	if envelope is Dictionary:
		for key in ["code", "message", "stage", "retryable", "retry_after_ms", "inputs_hash", "docs_key"]:
			if envelope.has(key):
				parsed[key] = envelope[key]
		return parsed

	var detail = data.get("detail")
	if detail is Dictionary:
		if detail.get("error") is String:
			parsed["code"] = detail["error"]
		if detail.get("message") is String:
			parsed["message"] = detail["message"]
		# A rejected queue lists each problem (422 invalid_mask)
		var problems = detail.get("details")
		if problems is Array and not problems.is_empty():
			var lines := PackedStringArray()
			for problem in problems:
				lines.append(str(problem))
			parsed["message"] = "%s: %s" % [parsed.get("message", "Invalid request"), "; ".join(lines)]
	elif detail is String:
		parsed["message"] = detail
	elif detail is Array:
		# FastAPI request validation: [{"loc": [...], "msg": "..."}]
		var messages := PackedStringArray()
		for item in detail:
			if item is Dictionary and item.get("msg") is String:
				messages.append(item["msg"])
		if not messages.is_empty():
			parsed["message"] = "; ".join(messages)
	return parsed


## Cancel current operation
func cancel() -> void:
	_is_cancelled = true


## Reset cancellation
func reset() -> void:
	_is_cancelled = false
	_current_job_id = ""
	_current_idempotency_key = ""


# ==================== Device Authentication ====================

## Start device authentication flow
func start_device_auth() -> Dictionary:
	var result := await _make_request(HTTPClient.METHOD_POST, ENDPOINT_DEVICE_START)

	if not result["success"]:
		auth_failed.emit(result["error"])
		return result

	var data: Dictionary = result["data"]
	auth_started.emit(
		data.get("device_code", ""),
		data.get("user_code", ""),
		data.get("verification_url", data.get("verification_uri", ""))
	)

	return result


## Poll for device authentication completion.
## The backend answers 200 {"status": "pending"} until the code is approved and
## then 200 with tokens; "expired" and "denied" end the login.
func poll_device_auth(device_code: String) -> Dictionary:
	var body := {"device_code": device_code}
	var result := await _make_request(HTTPClient.METHOD_POST, ENDPOINT_DEVICE_POLL, body)

	if not result["success"]:
		auth_failed.emit(result["error"])
		return result

	var data: Dictionary = result["data"]
	var access_token = data.get("access_token")
	if not (access_token is String and not access_token.is_empty()):
		var status := str(data.get("status", "unknown"))
		var error := {"code": "authorization_pending", "message": "Waiting for authorization"}
		if status != "pending":
			error = {
				"code": "device_code_%s" % status,
				"message": DEVICE_STATUS_MESSAGES.get(status, "Unexpected device login status: %s" % status)
			}
			auth_failed.emit(error)
		return {"success": false, "error": error}

	_apply_token_response(data)
	auth_completed.emit(_access_token)
	return result


## Refresh access token
func refresh_auth() -> Dictionary:
	if _refresh_token.is_empty():
		return {
			"success": false,
			"error": {
				"code": "NO_REFRESH_TOKEN",
				"message": "No refresh token available"
			}
		}

	var body := {"refresh_token": _refresh_token}
	var result := await _make_request(HTTPClient.METHOD_POST, ENDPOINT_REFRESH, body)

	if not result["success"]:
		auth_failed.emit(result["error"])
		return result

	_apply_token_response(result["data"])
	return result


## Store the tokens of a device-poll or refresh response
func _apply_token_response(data: Dictionary) -> void:
	_access_token = data.get("access_token", "")
	_refresh_token = data.get("refresh_token", _refresh_token)
	_token_expires_at = token_expiry(data, int(Time.get_unix_time_from_system()))


## Unix time a token response expires at. The backend sends a lifetime in seconds
## (expires_in); an absolute expires_at is accepted too. 0 means unknown.
static func token_expiry(data: Dictionary, now: int) -> int:
	var expires_in = data.get("expires_in")
	if expires_in is int or expires_in is float:
		return now + int(expires_in)
	var expires_at = data.get("expires_at")
	if expires_at is int or expires_at is float:
		return int(expires_at)
	return 0


# ==================== Quota ====================

## Get current quota (with memory caching)
func get_quota(force_refresh: bool = false) -> Dictionary:
	# Check memory cache first
	if not force_refresh and _quota_cache.has("data"):
		var now := Time.get_unix_time_from_system()
		var cache_age: int = now - _quota_cache.get("timestamp", 0)
		if cache_age < quota_cache_ttl:
			print_debug("[PoolClient] Using cached quota (age: %ds)" % cache_age)
			quota_updated.emit(_quota_cache["data"])
			return {"success": true, "data": _quota_cache["data"], "cached": true}

	var result := await _make_request(HTTPClient.METHOD_GET, ENDPOINT_QUOTA)

	if result["success"]:
		# Update cache
		_quota_cache = {
			"data": result["data"],
			"timestamp": Time.get_unix_time_from_system()
		}
		quota_updated.emit(result["data"])

	return result


## Invalidate quota cache (call after generation)
func invalidate_quota_cache() -> void:
	_quota_cache.clear()


# ==================== Generation ====================

## Generate sprites via backend (with cache support)
func generate_sprites(queue_data: Array, output_root: String, global_style: String) -> void:
	reset()
	_current_job_id = _generate_job_id()

	# Compute inputs hash for idempotency and cache lookup
	var inputs_hash := _compute_inputs_hash(queue_data, global_style)
	_current_inputs_hash = inputs_hash
	_current_idempotency_key = _generate_idempotency_key(inputs_hash)

	# Check cache first
	if _sprite_cache and _sprite_cache.enabled:
		generation_progress.emit("cache_check", "Checking local cache...")
		var cached_manifest = _sprite_cache.get_from_cache(inputs_hash)
		if cached_manifest:
			if _restore_cached_sprites(inputs_hash, cached_manifest, output_root):
				print_debug("[PoolClient] Cache HIT for %s" % inputs_hash.substr(0, 16))
				cache_hit.emit(inputs_hash)
				generation_completed.emit(cached_manifest)
				return
			push_warning("[PoolClient] Cached files for %s are missing; generating again" % inputs_hash.substr(0, 16))
			_sprite_cache.remove_entry(inputs_hash)

	generation_started.emit(_current_job_id)

	# Prepare request body
	var body := {
		"queue": queue_data,
		"global_style": global_style,
		"output_root": output_root
	}

	generation_progress.emit("submitting", "Submitting generation request...")

	var result := await _make_request(HTTPClient.METHOD_POST, ENDPOINT_GENERATE, body)

	if not result["success"]:
		generation_failed.emit(result["error"])
		return

	var data: Dictionary = result["data"]

	# A server that answers synchronously sends the result right away
	if data.has("manifest"):
		await _handle_sync_response(data, output_root)
		return

	# Async job - poll for completion
	var server_job_id: String = str(data.get("job_id", ""))
	if server_job_id.is_empty():
		generation_failed.emit({
			"code": "NO_JOB_ID",
			"message": "Server did not return job ID",
			"stage": "submit"
		})
		return

	await _poll_job_status(server_job_id, output_root)


## Download a finished job's assets and verify them, then save the manifest and cache the result
func _handle_sync_response(data: Dictionary, output_root: String) -> void:
	var manifest: Dictionary = data["manifest"] if data.get("manifest") is Dictionary else {}
	var assets: Array = data["assets"] if data.get("assets") is Array else []
	var written: Array = []  # {abs, rel} of each file written under output_root
	var download_errors: Array = []

	if not assets.is_empty():
		generation_progress.emit("downloading", "Downloading %d assets..." % assets.size())

	for asset in assets:
		if not asset is Dictionary:
			continue
		if asset.get("kind") == "raw" and not download_raw:
			continue
		var asset_path: String = asset["path"] if asset.get("path") is String else ""
		var asset_url: String = asset["url"] if asset.get("url") is String else ""

		# Both values come from the server; never write outside output_root
		var full_path := ManifestPaths.resolve(output_root, asset_path) if ManifestPaths.is_safe_relative(asset_path) else ""
		if full_path.is_empty() or not _validate_url(asset_url):
			push_warning("[PoolClient] Skipping asset with an unsafe path or URL: %s" % asset_path)
			download_errors.append({"path": asset_path, "reason": "unsafe_path_or_url"})
			continue

		var download: Dictionary = await _download_file(asset_url)
		if not download.get("success", false):
			download_errors.append({"path": asset_path, "reason": "download_failed"})
			continue

		var content: PackedByteArray = download["body"]
		var expected_sha256: String = asset["sha256"] if asset.get("sha256") is String else ""
		if not expected_sha256.is_empty() and sha256_hex(content) != expected_sha256.to_lower():
			push_warning("[PoolClient] Skipping asset whose SHA-256 does not match: %s" % asset_path)
			download_errors.append({"path": asset_path, "reason": "sha256_mismatch"})
			continue

		DirAccess.make_dir_recursive_absolute(full_path.get_base_dir())
		var file := FileAccess.open(full_path, FileAccess.WRITE)
		if not file:
			download_errors.append({"path": asset_path, "reason": "write_failed"})
			continue
		file.store_buffer(content)
		file.close()
		written.append({"abs": full_path, "rel": asset_path})

	if not download_errors.is_empty():
		generation_progress.emit("download_warnings", "%d assets skipped" % download_errors.size())
		manifest["download_errors"] = download_errors

	_save_manifest(manifest, output_root)

	# Cache complete results only, so a cache hit never restores a partial download
	if _sprite_cache and _sprite_cache.enabled and _current_inputs_hash and download_errors.is_empty():
		generation_progress.emit("caching", "Saving to local cache...")
		var cache_err: Error = _sprite_cache.add_to_cache(_current_inputs_hash, manifest, written)
		if cache_err == OK:
			print_debug("[PoolClient] Cached generation result: %s" % _current_inputs_hash.substr(0, 16))
		else:
			push_warning("[PoolClient] Failed to cache result: %s" % error_string(cache_err))

	# Invalidate quota cache since we just used credits
	invalidate_quota_cache()

	generation_completed.emit(manifest)


## Copy a cached result into output_root. Returns false, before copying anything,
## if a cached file is missing.
func _restore_cached_sprites(inputs_hash: String, manifest: Dictionary, output_root: String) -> bool:
	generation_progress.emit("restoring", "Restoring cached sprites...")

	var cached_files: Array = _sprite_cache.get_cached_files(inputs_hash) if _sprite_cache else []
	for cached in cached_files:
		if ManifestPaths.resolve(output_root, cached["rel"]).is_empty() or not FileAccess.file_exists(cached["abs"]):
			return false

	for cached in cached_files:
		var dest_path := ManifestPaths.resolve(output_root, cached["rel"])
		DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
		var dest := FileAccess.open(dest_path, FileAccess.WRITE)
		if not dest:
			return false
		dest.store_buffer(FileAccess.get_file_as_bytes(cached["abs"]))
		dest.close()

	_save_manifest(manifest, output_root)
	return true


## Write the manifest to output_root/run_manifest.json
func _save_manifest(manifest: Dictionary, output_root: String) -> void:
	DirAccess.make_dir_recursive_absolute(output_root)
	var file := FileAccess.open(output_root.path_join("run_manifest.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()


## Poll job status until the job finishes. A lost connection or a 5xx answer is
## retried MAX_POLL_RETRIES times in a row at the current interval; any other
## error ends the generation.
func _poll_job_status(job_id: String, output_root: String) -> void:
	var poll_interval := initial_poll_interval
	var max_interval := 10.0
	var backoff := 1.5
	var transient_failures := 0

	generation_progress.emit("polling", "Waiting for job %s..." % job_id)

	while not _is_cancelled:
		var endpoint := ENDPOINT_JOB_STATUS % job_id
		var result := await _make_request(HTTPClient.METHOD_GET, endpoint)

		if not result["success"]:
			if is_transient_failure(result["error"]) and transient_failures < MAX_POLL_RETRIES:
				transient_failures += 1
				generation_progress.emit("polling", "Server not reachable, retry %d of %d..." % [transient_failures, MAX_POLL_RETRIES])
				await Engine.get_main_loop().create_timer(poll_interval).timeout
				continue
			generation_failed.emit(result["error"])
			return
		transient_failures = 0

		var data: Dictionary = result["data"]
		var status := str(data.get("status", "unknown"))
		generation_percent.emit(_progress_percent(data), _progress_stage(data, status))

		match status:
			"completed":
				generation_progress.emit("fetching", "Fetching results...")
				await _fetch_job_result(job_id, output_root)
				return
			"failed":
				generation_failed.emit({
					"code": "JOB_FAILED",
					"message": _text_or(data.get("error_message"), "Job failed"),
					"stage": _progress_stage(data, "unknown"),
					"job_id": job_id
				})
				return
			"cancelled":
				generation_failed.emit({
					"code": "CANCELLED",
					"message": _text_or(data.get("error_message"), "Job was cancelled"),
					"job_id": job_id
				})
				return
			_:
				# Still running - wait and poll again
				await Engine.get_main_loop().create_timer(poll_interval).timeout
				poll_interval = min(poll_interval * backoff, max_interval)

	# Cancelled by user
	var cancel_result := await cancel_job(job_id)
	var units_charged := 0
	if cancel_result.get("success", false) and cancel_result.get("data") is Dictionary:
		var charged = cancel_result["data"].get("units_charged")
		units_charged = int(charged) if charged is int or charged is float else 0
	generation_failed.emit({
		"code": "CANCELLED",
		"message": "Cancelled by user" if units_charged == 0 else "Cancelled by user (%d units charged)" % units_charged,
		"job_id": job_id,
		"units_charged": units_charged
	})


## Fetch job result
func _fetch_job_result(job_id: String, output_root: String) -> void:
	var endpoint := ENDPOINT_JOB_RESULT % job_id
	var result := await _make_request(HTTPClient.METHOD_GET, endpoint)

	if not result["success"]:
		generation_failed.emit(result["error"])
		return

	var data: Dictionary = result["data"]
	await _handle_sync_response(data, output_root)


## Cancel a job on the server
func cancel_job(job_id: String) -> Dictionary:
	var endpoint := ENDPOINT_JOB_CANCEL % job_id
	return await _make_request(HTTPClient.METHOD_POST, endpoint)


## Download a URL into memory: {success, status_code, body}
func _download_file(url: String) -> Dictionary:
	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)

	var error := http.request(url)
	if error != OK:
		http.queue_free()
		return {"success": false, "status_code": 0, "body": PackedByteArray()}

	var response: Array = await http.request_completed
	http.queue_free()

	var result_code: int = response[0]
	var status_code: int = response[1]
	var success := result_code == HTTPRequest.RESULT_SUCCESS and status_code == 200
	return {"success": success, "status_code": status_code, "body": response[3] if success else PackedByteArray()}


## True for failures worth retrying: no response at all, or a server error (5xx)
static func is_transient_failure(error: Dictionary) -> bool:
	var status_code = error.get("status_code", 0)
	if not (status_code is int or status_code is float):
		return false
	return int(status_code) == 0 or int(status_code) >= 500


## Lowercase hex SHA-256 of a buffer, as the backend reports it for each asset
static func sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not data.is_empty():
		ctx.update(data)
	return ctx.finish().hex_encode()


static func _progress_percent(data: Dictionary) -> int:
	var percent = data.get("progress_percent")
	return int(percent) if percent is int or percent is float else 0


## The job's progress_stage, then stage, then the fallback
static func _progress_stage(data: Dictionary, fallback: String) -> String:
	for key in ["progress_stage", "stage"]:
		var value = data.get(key)
		if value is String and not value.is_empty():
			return value
	return fallback


static func _text_or(value: Variant, fallback: String) -> String:
	return value if value is String and not value.is_empty() else fallback


## Compute inputs hash
func _compute_inputs_hash(queue_data: Array, global_style: String) -> String:
	var sorted := queue_data.duplicate()
	sorted.sort_custom(func(a, b):
		var cat_a: String = a.get("category", "")
		var cat_b: String = b.get("category", "")
		if cat_a != cat_b:
			return cat_a < cat_b
		var name_a: String = a.get("file_name", "")
		var name_b: String = b.get("file_name", "")
		return name_a < name_b
	)

	var canonical := {
		"global_style": global_style,
		"queue": sorted
	}

	var json_str := JSON.stringify(canonical, "", false)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(json_str.to_utf8_buffer())
	return ctx.finish().hex_encode()
