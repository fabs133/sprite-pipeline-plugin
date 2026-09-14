@tool
extends RefCounted
## BYOK (Bring Your Own Key) client for direct OpenAI API calls.
##
## Calls the OpenAI Images API with the user's own key; no server in between.
## Builds the same prompt and post-processes the sheet the same way as
## sprite-pipeline-backend, and writes a version 2 manifest.

signal generation_started(job_id: String)
signal generation_progress(stage: String, message: String)
signal generation_percent(percent: int, stage: String)
signal generation_completed(manifest: Dictionary)
signal generation_failed(error: Dictionary)

const ManifestPaths := preload("res://addons/sprite_pipeline/manifest_paths.gd")
const Prompting := preload("res://addons/sprite_pipeline/prompting.gd")
const Postprocess := preload("res://addons/sprite_pipeline/postprocess.gd")

const OPENAI_IMAGE_URL := "https://api.openai.com/v1/images/generations"
const DEFAULT_IMAGE_MODEL := "gpt-image-2"
const DEFAULT_IMAGE_QUALITY := "medium"
## Models offered in the dock; any other model name can be entered as a custom model
const IMAGE_MODELS := ["gpt-image-2", "gpt-image-1.5", "gpt-image-1-mini"]
## Quality tiers; higher quality costs more per image
const IMAGE_QUALITIES := ["low", "medium", "high"]
const MANIFEST_VERSION := 2
## Attempts per image while OpenAI answers 429, as in the backend's provider
const MAX_ATTEMPTS := 3
## Error text of a request rejected by OpenAI's safety system (the backend's keywords)
const CONTENT_POLICY_KEYWORDS := ["content_policy", "content policy", "safety system", "violat", "moderation"]

var _api_key: String = ""
var _image_model: String = DEFAULT_IMAGE_MODEL
var _image_quality: String = DEFAULT_IMAGE_QUALITY
var _is_cancelled: bool = false
var _current_job_id: String = ""

## Images API endpoint; tests point it at a local server
var api_url: String = OPENAI_IMAGE_URL
## Seconds before the first rate-limit retry; doubles with each further attempt
var retry_delay: float = 1.0


func _init(api_key: String) -> void:
	_api_key = api_key


## Validate API key format
func is_key_valid() -> bool:
	return _api_key.length() > 0 and _api_key.begins_with("sk-")


## Set model for image generation; an empty name keeps the default
func set_image_model(model: String) -> void:
	var name := model.strip_edges()
	_image_model = name if not name.is_empty() else DEFAULT_IMAGE_MODEL


## Set image quality: low, medium or high
func set_image_quality(quality: String) -> void:
	_image_quality = quality if quality in IMAGE_QUALITIES else DEFAULT_IMAGE_QUALITY


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
	return "byok_%s" % hex.substr(0, 16)


## Cancel current generation
func cancel() -> void:
	_is_cancelled = true


## Check if cancelled
func is_cancelled() -> bool:
	return _is_cancelled


## Reset for new generation
func reset() -> void:
	_is_cancelled = false
	_current_job_id = ""


## Generate sprites from queue (main entry point)
## queue_data: Array of sprite specifications
## output_root: Directory to save generated sprites
## global_style: Style directive for all sprites
func generate_sprites(queue_data: Array, output_root: String, global_style: String) -> void:
	reset()
	_current_job_id = _generate_job_id()
	generation_started.emit(_current_job_id)

	var manifest := {
		"version": MANIFEST_VERSION,
		"job_id": _current_job_id,
		"model": _image_model,
		"image_quality": _image_quality,
		"global_style": global_style,
		"output_root": output_root,
		"results": [],
		"errors": [],
		"total_succeeded": 0,
		"total_failed": 0,
		"safe_mode_count": 0,
		"inputs_hash": _compute_inputs_hash(queue_data, global_style),
		"started_at": Time.get_datetime_string_from_system(),
		"completed_at": ""
	}

	var total := queue_data.size()

	for i in range(total):
		if _is_cancelled:
			manifest["errors"].append({
				"sprite_key": "",
				"stage": "cancelled",
				"error": "Generation cancelled by user",
				"code": "CANCELLED"
			})
			break

		var spec: Dictionary = queue_data[i] if queue_data[i] is Dictionary else {}

		generation_progress.emit(
			"generating",
			"[%d/%d] Generating %s..." % [i + 1, total, _sprite_key(spec)]
		)

		var result := await _generate_single_sprite(spec, output_root, global_style)

		if result["success"]:
			manifest["results"].append(result["entry"])
		else:
			manifest["errors"].append(result["error"])

		generation_percent.emit(floori((i + 1) * 100.0 / total), "generating")

	manifest["total_succeeded"] = manifest["results"].size()
	manifest["total_failed"] = manifest["errors"].size()
	manifest["completed_at"] = Time.get_datetime_string_from_system()

	# Save manifest
	DirAccess.make_dir_recursive_absolute(output_root)
	var file := FileAccess.open(output_root.path_join("run_manifest.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()

	if _is_cancelled:
		generation_failed.emit({
			"code": "CANCELLED",
			"message": "Generation cancelled by user",
			"stage": "cancelled",
			"job_id": _current_job_id
		})
	elif manifest["errors"].size() > 0 and manifest["results"].size() == 0:
		generation_failed.emit({
			"code": "ALL_FAILED",
			"message": "All sprites failed to generate",
			"stage": "complete",
			"job_id": _current_job_id,
			"errors": manifest["errors"]
		})
	else:
		generation_completed.emit(manifest)


## Generate one sprite: prompt, image call, post-processing and files, like the backend's
## pipeline. Returns {success: true, entry} with a manifest v2 result, or
## {success: false, error: {sprite_key, stage, error, code}}.
func _generate_single_sprite(spec: Dictionary, output_root: String, global_style: String) -> Dictionary:
	var file_name := str(spec.get("file_name", "sprite.png"))
	var category := str(spec.get("category", "misc"))
	var sprite_key := _sprite_key(spec)
	var frames := _count(spec.get("frames"), 1)
	var rows := _count(spec.get("rows"), 1)
	var frame_w := _count(spec.get("frame_w"), 0)
	var frame_h := _count(spec.get("frame_h"), 0)

	# Same rule as the backend: the sheet lands exactly at output_root/<category>/<file_name>
	if not _is_safe_name(category) or not _is_safe_name(file_name):
		return _failure(sprite_key, "validation", "Invalid category or file_name", "INVALID_SPEC")
	if frames < 1 or rows < 1 or frame_w < 0 or frame_h < 0:
		return _failure(sprite_key, "validation", "frames, rows, frame_w and frame_h must be positive integers", "INVALID_SPEC")

	var brief := Prompting.build_prompt(spec, global_style)
	var prompt: String = brief["prompt"]
	var grid_size: int = brief["grid_size"]

	generation_progress.emit("generating_image", "Calling %s for %s..." % [_image_model, sprite_key])
	var image_result := await _call_image_api(prompt)
	if not image_result["success"]:
		return _failure(sprite_key, image_result.get("stage", "generation"), image_result.get("message", "Image generation failed"), image_result.get("code", "GENERATION_FAILED"))
	var png: PackedByteArray = image_result["png"]

	generation_progress.emit("saving", "Saving %s..." % sprite_key)
	var rel_path := "%s/%s" % [category, file_name]
	var entry := {
		"sprite_key": sprite_key,
		"file_name": file_name,
		"category": category,
		"file_path": rel_path,
		"sha256": "",
		"raw_path": null,
		"frame_paths": [],
		"frame_w": 0,
		"frame_h": 0,
		"frames": frames,
		"rows": rows,
		"layout": str(spec.get("layout", "row")),
		"grid_violation": false,
		"gutter_opaque_ratio": 0.0,
		"image_id": null,
		"status": "ok",
		"error": null,
		"prompt_text": prompt,
		"generated_at": Time.get_datetime_string_from_system()
	}

	# A queue item with a frame size gets a downscaled sheet plus single frames; without one
	# the raw sheet is the result, as in the backend
	if frame_w > 0 or frame_h > 0:
		var processed := Postprocess.postprocess_sheet(png, grid_size, rows, frames, frame_w if frame_w > 0 else frame_h, frame_h if frame_h > 0 else frame_w)
		if processed.is_empty():
			return _failure(sprite_key, "postprocess", "Generated image could not be processed", "POSTPROCESS_FAILED")

		var stem := file_name.get_basename()
		# An extensionless file_name is its own stem; keep the frames directory off the sheet's path
		var frames_dir := stem if stem != file_name else "%s_frames" % stem
		var raw_path := "%s/%s_raw.png" % [category, stem]
		if not _write(output_root.path_join(rel_path), processed["sheet_png"]) or not _write(output_root.path_join(raw_path), png):
			return _failure(sprite_key, "save", "Failed to write %s" % rel_path, "SAVE_FAILED")

		var columns: int = processed["columns"]
		var frames_png: Array = processed["frames_png"]
		var frame_paths := []
		for index in frames_png.size():
			var frame_path := "%s/%s/frame_%d_%d.png" % [category, frames_dir, floori(float(index) / columns), index % columns]
			if not _write(output_root.path_join(frame_path), frames_png[index]):
				return _failure(sprite_key, "save", "Failed to write %s" % frame_path, "SAVE_FAILED")
			frame_paths.append(frame_path)

		entry["sha256"] = sha256_hex(processed["sheet_png"])
		entry["raw_path"] = raw_path
		entry["frame_paths"] = frame_paths
		entry["frame_w"] = processed["frame_w"]
		entry["frame_h"] = processed["frame_h"]
		entry["grid_violation"] = processed["check"]["violated"]
		entry["gutter_opaque_ratio"] = processed["check"]["gutter_opaque_ratio"]
	else:
		if not _write(output_root.path_join(rel_path), png):
			return _failure(sprite_key, "save", "Failed to write %s" % rel_path, "SAVE_FAILED")
		# Raw sheet: each frame is a cell of the grid on the 1024x1024 canvas
		entry["sha256"] = sha256_hex(png)
		entry["frame_w"] = floori(1024.0 / grid_size)
		entry["frame_h"] = floori(1024.0 / grid_size)

	return {"success": true, "entry": entry}


## One image from the OpenAI Images API. A 429 answer is retried with backoff, honouring
## retry-after, up to MAX_ATTEMPTS attempts. Returns {success: true, png} or a failure
## from parse_image_response.
func _call_image_api(prompt: String) -> Dictionary:
	var body := JSON.stringify({
		"model": _image_model,
		"prompt": prompt,
		"size": "1024x1024",
		"quality": _image_quality,
		"background": "transparent",
		"output_format": "png",
		"moderation": "low",
		"n": 1
	})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _api_key
	])

	var result := {}
	for attempt in range(1, MAX_ATTEMPTS + 1):
		var response := await _post(api_url, headers, body)
		result = parse_image_response(response["result_code"], response["status_code"], response["headers"], response["body"])
		if result["success"] or result.get("code") != "RATE_LIMITED" or attempt == MAX_ATTEMPTS or _is_cancelled:
			return result
		var delay := maxf(result.get("retry_after_ms", 0) / 1000.0, retry_delay * pow(2.0, attempt - 1))
		generation_progress.emit("rate_limited", "Rate limited by OpenAI, retrying in %.1f s..." % delay)
		await Engine.get_main_loop().create_timer(delay).timeout
	return result


## POST a JSON body: {result_code, status_code, headers (lowercase names), body}
func _post(url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)

	var error := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		return {"result_code": HTTPRequest.RESULT_CANT_CONNECT, "status_code": 0, "headers": {}, "body": PackedByteArray()}

	var response: Array = await http.request_completed
	http.queue_free()

	var header_dict := {}
	for line in response[2]:
		var parts: PackedStringArray = line.split(":", true, 1)
		if parts.size() == 2:
			header_dict[parts[0].strip_edges().to_lower()] = parts[1].strip_edges()
	return {"result_code": response[0], "status_code": response[1], "headers": header_dict, "body": response[3]}


## Result of an Images API response: {success: true, png} for a b64_json image, or
## {success: false, stage, code, message, status_code} with retry_after_ms for a 429
static func parse_image_response(result_code: int, status_code: int, headers: Dictionary, body: PackedByteArray) -> Dictionary:
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"success": false, "stage": "generation", "code": "HTTP_FAILED", "message": "HTTP request failed with result: %d" % result_code, "status_code": 0}

	var json := JSON.new()
	var data: Dictionary = json.data if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary else {}

	if status_code != 200:
		var message := "API error: %d" % status_code
		var error_code := ""
		var api_error = data.get("error")
		if api_error is Dictionary:
			if api_error.get("message") is String:
				message = api_error["message"]
			if api_error.get("code") is String:
				error_code = api_error["code"]
		if status_code == 429:
			var retry_after := str(headers.get("retry-after", ""))
			return {
				"success": false, "stage": "generation", "code": "RATE_LIMITED", "message": message, "status_code": status_code,
				"retry_after_ms": int(retry_after.to_float() * 1000) if retry_after.is_valid_float() else 0
			}
		if status_code == 400 and is_content_policy_error("%s %s" % [message, error_code]):
			return {"success": false, "stage": "content_policy", "code": "CONTENT_POLICY", "message": message, "status_code": status_code}
		return {"success": false, "stage": "generation", "code": "API_ERROR", "message": message, "status_code": status_code}

	var images = data.get("data")
	var b64 = null
	if images is Array and not images.is_empty() and images[0] is Dictionary:
		b64 = images[0].get("b64_json")
	if not (b64 is String and not b64.is_empty()):
		return {"success": false, "stage": "generation", "code": "NO_IMAGE", "message": "No image data (b64_json) in response", "status_code": status_code}
	var png := Marshalls.base64_to_raw(b64)
	if png.is_empty():
		return {"success": false, "stage": "generation", "code": "NO_IMAGE", "message": "Image data is not valid base64", "status_code": status_code}
	return {"success": true, "png": png}


## True if an error text marks a request rejected by OpenAI's safety system
static func is_content_policy_error(text: String) -> bool:
	var lowered := text.to_lower()
	for keyword in CONTENT_POLICY_KEYWORDS:
		if keyword in lowered:
			return true
	return false


## Lowercase hex SHA-256 of a buffer
static func sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not data.is_empty():
		ctx.update(data)
	return ctx.finish().hex_encode()


static func _sprite_key(spec: Dictionary) -> String:
	return "%s/%s" % [str(spec.get("category", "misc")), str(spec.get("file_name", "sprite.png"))]


## A positive whole number from a queue field; default when the field is missing or null,
## -1 for anything else
static func _count(value: Variant, default: int) -> int:
	if value == null:
		return default
	if value is int and value > 0:
		return value
	if value is float and value > 0 and value == floorf(value):
		return int(value)
	return -1


## A category or file name that is exactly one path segment
static func _is_safe_name(name: String) -> bool:
	return name != "." and not "/" in name and ManifestPaths.is_safe_relative(name)


static func _failure(sprite_key: String, stage: String, message: String, code: String) -> Dictionary:
	return {"success": false, "error": {"sprite_key": sprite_key, "stage": stage, "error": message, "code": code}}


static func _write(path: String, content: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_buffer(content)
	file.close()
	return true


## Compute inputs hash for manifest
func _compute_inputs_hash(queue_data: Array, global_style: String) -> String:
	# Sort queue by category, then file_name for determinism
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

	# Build canonical representation
	var canonical := {
		"global_style": global_style,
		"queue": sorted
	}

	var json_str := JSON.stringify(canonical, "", false)  # No indent, sorted keys

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(json_str.to_utf8_buffer())
	return ctx.finish().hex_encode()
