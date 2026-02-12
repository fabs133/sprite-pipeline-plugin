@tool
extends RefCounted
## Pool mode client for backend server API calls.
##
## Uses shared credits via a backend server. Includes device authentication,
## quota management, and proper error handling. Integrates with SpriteCache
## to avoid redundant API calls.

signal auth_started(device_code: String, user_code: String, verification_uri: String)
signal auth_completed(access_token: String)
signal auth_failed(error: Dictionary)
signal quota_updated(quota: Dictionary)
signal generation_started(job_id: String)
signal generation_progress(stage: String, message: String)
signal generation_completed(manifest: Dictionary)
signal generation_failed(error: Dictionary)
signal cache_hit(inputs_hash: String)

const PLUGIN_VERSION := "1.0.0"
const PROTOCOL_VERSION := "1"

# Preload cache class
const SpriteCacheClass = preload("res://addons/sprite_pipeline/cache/sprite_cache.gd")

# Input validation functions
static func _validate_url(url: String) -> bool:
	"""Validate that URL uses HTTPS and has valid format."""
	if url.is_empty():
		return false
	if not url.begins_with("https://") and not url.begins_with("http://localhost"):
		push_error("Server URL must use HTTPS (or localhost for testing)")
		return false
	return true

static func _validate_path(path: String) -> bool:
	"""Validate file path to prevent directory traversal."""
	if path.is_empty():
		return false
	if ".." in path or path.begins_with("/") or path.begins_with("\\"):
		push_error("Invalid path: directory traversal not allowed")
		return false
	if not path.begins_with("res://") and not path.begins_with("user://"):
		push_error("Path must start with res:// or user://")
		return false
	return true

static func _sanitize_job_id(job_id: String) -> String:
	"""Sanitize job ID to only allow safe characters."""
	var sanitized := ""
	for i in range(job_id.length()):
		var c = job_id[i]
		if c.is_valid_identifier() or c == "-" or c == "_":
			sanitized += c
	return sanitized

# Endpoints
const ENDPOINT_DEVICE_START := "/v1/auth/device/start"
const ENDPOINT_DEVICE_POLL := "/v1/auth/device/poll"
const ENDPOINT_REFRESH := "/v1/auth/refresh"
const ENDPOINT_QUOTA := "/v1/quota"
const ENDPOINT_GENERATE := "/v1/generate"
const ENDPOINT_JOB_STATUS := "/v1/jobs/%s"
const ENDPOINT_JOB_CANCEL := "/v1/jobs/%s/cancel"
const ENDPOINT_JOB_RESULT := "/v1/jobs/%s/result"

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


func _init(server_url: String) -> void:
	if not _validate_url(server_url):
		push_error("Invalid server URL provided to PoolClient")
		_server_url = ""
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
		"X-Plugin-Version: %s" % PLUGIN_VERSION,
		"X-Protocol-Version: %s" % PROTOCOL_VERSION,
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
		"protocol_version": PROTOCOL_VERSION,
		"plugin_version": PLUGIN_VERSION
	}

	# Parse JSON body
	var json := JSON.new()
	if json.parse(body_text) == OK:
		var data: Dictionary = json.get_data()
		if data.has("error"):
			var err: Dictionary = data["error"]
			error["code"] = err.get("code", error["code"])
			error["message"] = err.get("message", error["message"])
			error["stage"] = err.get("stage", error["stage"])
			error["retryable"] = err.get("retryable", error["retryable"])
			error["retry_after_ms"] = err.get("retry_after_ms", 0)
			error["inputs_hash"] = err.get("inputs_hash", "")
			error["docs_key"] = err.get("docs_key", "")

	# Handle specific status codes
	match status_code:
		426:
			error["code"] = "UPGRADE_REQUIRED"
			error["message"] = "Plugin version too old. Please update."
			error["retryable"] = false
		429:
			error["code"] = "RATE_LIMITED"
			error["retryable"] = true
			var retry_after := headers.get("retry-after", "60")
			if retry_after.is_valid_int():
				error["retry_after_ms"] = int(retry_after) * 1000
		402:
			error["code"] = "QUOTA_EXCEEDED"
			error["message"] = "Quota exhausted. Add credits or wait for reset."
			error["retryable"] = false
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
		data.get("verification_uri", "")
	)

	return result


## Poll for device authentication completion
func poll_device_auth(device_code: String) -> Dictionary:
	var body := {"device_code": device_code}
	var result := await _make_request(HTTPClient.METHOD_POST, ENDPOINT_DEVICE_POLL, body)

	if not result["success"]:
		# "authorization_pending" is expected while waiting
		if result["error"].get("code") == "authorization_pending":
			return result
		auth_failed.emit(result["error"])
		return result

	var data: Dictionary = result["data"]
	_access_token = data.get("access_token", "")
	_refresh_token = data.get("refresh_token", "")
	_token_expires_at = data.get("expires_at", 0)

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

	var data: Dictionary = result["data"]
	_access_token = data.get("access_token", "")
	_refresh_token = data.get("refresh_token", _refresh_token)
	_token_expires_at = data.get("expires_at", 0)

	return result


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
			print_debug("[PoolClient] Cache HIT for %s" % inputs_hash.substr(0, 16))
			cache_hit.emit(inputs_hash)
			# Restore cached sprites to output directory
			await _restore_cached_sprites(inputs_hash, cached_manifest, output_root)
			generation_completed.emit(cached_manifest)
			return

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

	# Check if synchronous response with manifest
	if data.has("manifest"):
		await _handle_sync_response(data, output_root)
		return

	# Async job - poll for completion
	var server_job_id: String = data.get("job_id", "")
	if server_job_id.is_empty():
		generation_failed.emit({
			"code": "NO_JOB_ID",
			"message": "Server did not return job ID",
			"stage": "submit"
		})
		return

	await _poll_job_status(server_job_id, output_root)


## Handle synchronous response with manifest
func _handle_sync_response(data: Dictionary, output_root: String) -> void:
	var manifest: Dictionary = data["manifest"]
	var downloaded_sprites: Array = []

	# Download and save assets
	if data.has("assets"):
		generation_progress.emit("downloading", "Downloading assets...")
		for asset in data["assets"]:
			var asset_path: String = asset.get("path", "")
			var asset_url: String = asset.get("url", "")
			if asset_path and asset_url:
				var full_path := output_root.path_join(asset_path)
				DirAccess.make_dir_recursive_absolute(full_path.get_base_dir())
				var success := await _download_file(asset_url, full_path)
				if success:
					downloaded_sprites.append(full_path)

	# Save manifest
	var manifest_path := output_root.path_join("run_manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()

	# Store to cache if available
	if _sprite_cache and _sprite_cache.enabled and _current_inputs_hash:
		generation_progress.emit("caching", "Saving to local cache...")
		var cache_err: Error = _sprite_cache.add_to_cache(_current_inputs_hash, manifest, downloaded_sprites)
		if cache_err == OK:
			print_debug("[PoolClient] Cached generation result: %s" % _current_inputs_hash.substr(0, 16))
		else:
			push_warning("[PoolClient] Failed to cache result: %s" % error_string(cache_err))

	# Invalidate quota cache since we just used credits
	invalidate_quota_cache()

	generation_completed.emit(manifest)


## Restore cached sprites to output directory
func _restore_cached_sprites(inputs_hash: String, manifest: Dictionary, output_root: String) -> void:
	generation_progress.emit("restoring", "Restoring cached sprites...")

	# Get cached entry directory
	var cache_dir: String = _sprite_cache.cache_dir if _sprite_cache else "user://sprite_cache"
	var entry_dir := cache_dir.path_join(inputs_hash.substr(0, 16))

	# Copy sprites from cache to output
	if manifest.has("results"):
		for result in manifest["results"]:
			var file_path: String = result.get("file_path", "")
			if file_path.is_empty():
				continue

			# Determine cached file name
			var sprite_name := file_path.get_file()
			var cached_path := entry_dir.path_join(sprite_name)

			if FileAccess.file_exists(cached_path):
				# Copy to output
				var dest_path := output_root.path_join(file_path.replace(output_root, "").trim_prefix("/"))
				if dest_path == file_path or file_path.begins_with(output_root):
					dest_path = file_path
				else:
					dest_path = output_root.path_join(sprite_name)

				DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())

				var source := FileAccess.open(cached_path, FileAccess.READ)
				if source:
					var dest := FileAccess.open(dest_path, FileAccess.WRITE)
					if dest:
						dest.store_buffer(source.get_buffer(source.get_length()))
						dest.close()
					source.close()

	# Save manifest to output
	var manifest_path := output_root.path_join("run_manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()


## Poll job status until completion
func _poll_job_status(job_id: String, output_root: String) -> void:
	var poll_interval := 1.0  # seconds
	var max_interval := 10.0
	var backoff := 1.5

	while not _is_cancelled:
		generation_progress.emit("polling", "Waiting for job %s..." % job_id)

		var endpoint := ENDPOINT_JOB_STATUS % job_id
		var result := await _make_request(HTTPClient.METHOD_GET, endpoint)

		if not result["success"]:
			generation_failed.emit(result["error"])
			return

		var data: Dictionary = result["data"]
		var status: String = data.get("status", "unknown")

		match status:
			"completed":
				generation_progress.emit("fetching", "Fetching results...")
				await _fetch_job_result(job_id, output_root)
				return
			"failed":
				generation_failed.emit({
					"code": "JOB_FAILED",
					"message": data.get("error_message", "Job failed"),
					"stage": data.get("stage", "unknown"),
					"job_id": job_id
				})
				return
			"cancelled":
				generation_failed.emit({
					"code": "CANCELLED",
					"message": "Job was cancelled",
					"job_id": job_id
				})
				return
			_:
				# Still running - wait and poll again
				await Engine.get_main_loop().create_timer(poll_interval).timeout
				poll_interval = min(poll_interval * backoff, max_interval)

	# Cancelled by user
	await cancel_job(job_id)
	generation_failed.emit({
		"code": "CANCELLED",
		"message": "Cancelled by user",
		"job_id": job_id
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


## Download file from URL
func _download_file(url: String, output_path: String) -> bool:
	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)

	var error := http.request(url)
	if error != OK:
		http.queue_free()
		return false

	var response: Array = await http.request_completed
	http.queue_free()

	var result_code: int = response[0]
	var status_code: int = response[1]
	var response_body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS or status_code != 200:
		return false

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if not file:
		return false

	file.store_buffer(response_body)
	file.close()
	return true


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
