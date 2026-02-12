@tool
extends RefCounted
## BYOK (Bring Your Own Key) client for direct OpenAI API calls.
##
## This client calls OpenAI directly without going through a backend server.
## The user provides their own API key.

signal generation_started(job_id: String)
signal generation_progress(stage: String, message: String)
signal generation_completed(manifest: Dictionary)
signal generation_failed(error: Dictionary)

const OPENAI_CHAT_URL := "https://api.openai.com/v1/chat/completions"
const OPENAI_IMAGE_URL := "https://api.openai.com/v1/images/generations"

const PLUGIN_VERSION := "0.1.0"
const PROTOCOL_VERSION := "1"

var _api_key: String = ""
var _model: String = "gpt-4o"
var _image_model: String = "dall-e-3"
var _is_cancelled: bool = false
var _current_job_id: String = ""


func _init(api_key: String) -> void:
	_api_key = api_key


## Validate API key format
func is_key_valid() -> bool:
	return _api_key.length() > 0 and _api_key.begins_with("sk-")


## Set model for text generation
func set_model(model: String) -> void:
	_model = model


## Set model for image generation
func set_image_model(model: String) -> void:
	_image_model = model


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
		"version": "1.0.0",
		"job_id": _current_job_id,
		"model": _model,
		"image_model": _image_model,
		"global_style": global_style,
		"output_root": output_root,
		"results": [],
		"errors": [],
		"safe_mode_count": 0,
		"inputs_hash": _compute_inputs_hash(queue_data, global_style),
		"started_at": Time.get_datetime_string_from_system(),
		"completed_at": ""
	}

	var total := queue_data.size()
	var completed := 0

	for i in range(total):
		if _is_cancelled:
			manifest["errors"].append({
				"file_name": "N/A",
				"stage": "cancelled",
				"message": "Generation cancelled by user",
				"code": "CANCELLED"
			})
			break

		var spec: Dictionary = queue_data[i]
		var file_name: String = spec.get("file_name", "sprite_%d.png" % i)

		generation_progress.emit(
			"generating",
			"[%d/%d] Generating %s..." % [i + 1, total, file_name]
		)

		var result := await _generate_single_sprite(spec, output_root, global_style)

		if result["success"]:
			manifest["results"].append(result["entry"])
			if result["entry"].get("safe_mode", false):
				manifest["safe_mode_count"] += 1
		else:
			manifest["errors"].append(result["error"])

		completed += 1

	manifest["completed_at"] = Time.get_datetime_string_from_system()

	# Save manifest
	var manifest_path := output_root.path_join("run_manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
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


## Generate a single sprite
func _generate_single_sprite(spec: Dictionary, output_root: String, global_style: String) -> Dictionary:
	var file_name: String = spec.get("file_name", "sprite.png")
	var category: String = spec.get("category", "misc")
	var frame_w: int = spec.get("frame_w", 64)
	var frame_h: int = spec.get("frame_h", 64)
	var frames: int = spec.get("frames", 1)
	var layout: String = spec.get("layout", "row")

	# Calculate expected dimensions
	var sheet_w := frame_w * frames if layout == "row" else frame_w
	var sheet_h := frame_h if layout == "row" else frame_h * frames

	# Build prompt
	var prompt := _build_generation_prompt(spec, global_style)

	generation_progress.emit("prompting", "Building prompt for %s..." % file_name)

	# Generate image via DALL-E
	generation_progress.emit("generating_image", "Calling DALL-E for %s..." % file_name)

	var image_result := await _call_dalle(prompt, sheet_w, sheet_h)

	if not image_result["success"]:
		return {
			"success": false,
			"error": {
				"file_name": file_name,
				"stage": image_result.get("stage", "hook_generate"),
				"message": image_result.get("message", "Image generation failed"),
				"code": image_result.get("code", "GENERATION_FAILED"),
				"details": image_result.get("details", {})
			}
		}

	# Save image
	generation_progress.emit("saving", "Saving %s..." % file_name)

	var output_dir := output_root.path_join(category)
	DirAccess.make_dir_recursive_absolute(output_dir)

	var output_path := output_dir.path_join(file_name)
	var save_result: Dictionary = await _save_image_from_url(image_result["url"], output_path)

	if not save_result["success"]:
		return {
			"success": false,
			"error": {
				"file_name": file_name,
				"stage": "save",
				"message": save_result.get("message", "Failed to save image"),
				"code": "SAVE_FAILED"
			}
		}

	# Build manifest entry
	var entry := {
		"sprite_key": "%s/%s" % [category, file_name.get_basename()],
		"file_path": output_path,
		"sha256": save_result.get("sha256", ""),
		"frame_w": frame_w,
		"frame_h": frame_h,
		"frames": frames,
		"layout": layout,
		"prompt_text": prompt,
		"safe_mode": false,  # BYOK doesn't use safe mode currently
		"generated_at": Time.get_datetime_string_from_system()
	}

	return {
		"success": true,
		"entry": entry
	}


## Build generation prompt from spec
func _build_generation_prompt(spec: Dictionary, global_style: String) -> String:
	var file_name: String = spec.get("file_name", "sprite")
	var frame_w: int = spec.get("frame_w", 64)
	var frame_h: int = spec.get("frame_h", 64)
	var frames: int = spec.get("frames", 1)
	var layout: String = spec.get("layout", "row")
	var description: String = spec.get("description", file_name.get_basename().replace("_", " "))

	var prompt := "%s\n\n" % global_style
	prompt += "Create a sprite sheet for: %s\n" % description
	prompt += "- Each frame: %dx%d pixels\n" % [frame_w, frame_h]
	prompt += "- Total frames: %d\n" % frames

	if frames > 1:
		if layout == "row":
			prompt += "- Layout: horizontal strip (%dx%d total)\n" % [frame_w * frames, frame_h]
		else:
			prompt += "- Layout: vertical strip (%dx%d total)\n" % [frame_w, frame_h * frames]
		prompt += "- Animation: smooth transitions between frames\n"

	prompt += "- Background: transparent\n"
	prompt += "- Style: clean pixel art, game-ready asset"

	return prompt


## Call DALL-E API
func _call_dalle(prompt: String, width: int, height: int) -> Dictionary:
	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)

	# DALL-E 3 only supports specific sizes
	var dalle_size := "1024x1024"
	if width > height * 1.2:
		dalle_size = "1792x1024"
	elif height > width * 1.2:
		dalle_size = "1024x1792"

	var body := {
		"model": _image_model,
		"prompt": prompt,
		"size": dalle_size,
		"quality": "standard",
		"n": 1
	}

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _api_key
	])

	var error := http.request(
		OPENAI_IMAGE_URL,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

	if error != OK:
		http.queue_free()
		return {
			"success": false,
			"stage": "hook_generate",
			"message": "Failed to start HTTP request: %d" % error,
			"code": "REQUEST_FAILED"
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
			"stage": "hook_generate",
			"message": "HTTP request failed with result: %d" % result_code,
			"code": "HTTP_FAILED"
		}

	var body_text := response_body.get_string_from_utf8()

	if status_code != 200:
		# Parse error
		var json := JSON.new()
		var error_msg := "API error: %d" % status_code
		var error_code := "API_ERROR"

		if json.parse(body_text) == OK:
			var data: Dictionary = json.get_data()
			if data.has("error"):
				var err: Dictionary = data["error"]
				error_msg = err.get("message", error_msg)
				if "content policy" in error_msg.to_lower() or "safety" in error_msg.to_lower():
					error_code = "CONTENT_POLICY"
					return {
						"success": false,
						"stage": "content_policy",
						"message": error_msg,
						"code": error_code
					}

		return {
			"success": false,
			"stage": "hook_generate",
			"message": error_msg,
			"code": error_code,
			"status_code": status_code
		}

	# Parse success response
	var json := JSON.new()
	if json.parse(body_text) != OK:
		return {
			"success": false,
			"stage": "hook_generate",
			"message": "Failed to parse API response",
			"code": "PARSE_FAILED"
		}

	var data: Dictionary = json.get_data()
	if not data.has("data") or data["data"].size() == 0:
		return {
			"success": false,
			"stage": "hook_generate",
			"message": "No image data in response",
			"code": "NO_IMAGE"
		}

	var image_data: Dictionary = data["data"][0]
	var url: String = image_data.get("url", "")

	if url.is_empty():
		return {
			"success": false,
			"stage": "hook_generate",
			"message": "No image URL in response",
			"code": "NO_URL"
		}

	return {
		"success": true,
		"url": url,
		"revised_prompt": image_data.get("revised_prompt", "")
	}


## Download and save image from URL
func _save_image_from_url(url: String, output_path: String) -> Dictionary:
	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)

	var error := http.request(url)
	if error != OK:
		http.queue_free()
		return {
			"success": false,
			"message": "Failed to start download: %d" % error
		}

	var response: Array = await http.request_completed
	http.queue_free()

	var result_code: int = response[0]
	var status_code: int = response[1]
	var response_body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS or status_code != 200:
		return {
			"success": false,
			"message": "Download failed: result=%d, status=%d" % [result_code, status_code]
		}

	# Save to file
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if not file:
		return {
			"success": false,
			"message": "Cannot open file for writing: %s" % output_path
		}

	file.store_buffer(response_body)
	file.close()

	# Compute SHA256
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(response_body)
	var hash_bytes := ctx.finish()
	var sha256 := hash_bytes.hex_encode()

	return {
		"success": true,
		"sha256": sha256,
		"size": response_body.size()
	}


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
