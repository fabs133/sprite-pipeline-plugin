extends "res://tests/test_case.gd"
## BYOK client against a stubbed Images API.

const BYOKClient := preload("res://addons/sprite_pipeline/api/byok_client.gd")
const Prompting := preload("res://addons/sprite_pipeline/prompting.gd")


class StubByok extends "res://addons/sprite_pipeline/api/byok_client.gd":
	var responses: Array = []
	var bodies: Array = []

	func _post(_url: String, _headers: PackedStringArray, body: String) -> Dictionary:
		bodies.append(JSON.parse_string(body))
		if responses.is_empty():
			return {"result_code": HTTPRequest.RESULT_SUCCESS, "status_code": 500, "headers": {}, "body": PackedByteArray()}
		return responses.pop_front()


func _reply(status_code: int, payload: Dictionary, headers := {}) -> Dictionary:
	return {"result_code": HTTPRequest.RESULT_SUCCESS, "status_code": status_code, "headers": headers, "body": JSON.stringify(payload).to_utf8_buffer()}


func _image_reply(png: PackedByteArray) -> Dictionary:
	return _reply(200, {"created": 0, "data": [{"b64_json": Marshalls.raw_to_base64(png)}]})


## 1024x1024 transparent PNG on a grid_size grid with a square in each active cell
func _grid_png(grid_size: int, rows: int, frames: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(1024 * 1024 * 4)
	data.fill(0)
	var image := Image.create_from_data(1024, 1024, false, Image.FORMAT_RGBA8, data)
	var cell := floori(1024.0 / grid_size)
	var pad := floori(cell / 4.0)
	for row in rows:
		for column in frames:
			image.fill_rect(Rect2i(column * cell + pad, row * cell + pad, cell - 2 * pad, cell - 2 * pad), Color8(40 + 50 * column, 120, 200, 255))
	return image.save_png_to_buffer()


func _record(client) -> Dictionary:
	var events := {"progress": [], "percents": [], "completed": [], "failed": []}
	client.generation_progress.connect(func(stage, message): events["progress"].append([stage, message]))
	client.generation_percent.connect(func(percent, stage): events["percents"].append([percent, stage]))
	client.generation_completed.connect(func(manifest): events["completed"].append(manifest))
	client.generation_failed.connect(func(error): events["failed"].append(error))
	return events


func test_request_body_and_rate_limit_retry() -> void:
	var png := _grid_png(1, 1, 1)
	var client := StubByok.new("sk-test")
	client.retry_delay = 0.01
	client.set_image_model("gpt-image-1-mini")
	client.set_image_quality("low")
	client.responses = [_reply(429, {"error": {"message": "Rate limit reached"}}, {"retry-after": "0.01"}), _image_reply(png)]
	var result: Dictionary = await client._call_image_api("a prompt")
	check(result["success"], "succeeds after the retry: %s" % result)
	check_eq(result.get("png"), png, "decoded PNG")
	check_eq(client.bodies.size(), 2, "one retry after 429")
	check_eq(client.bodies[1], {"model": "gpt-image-1-mini", "prompt": "a prompt", "size": "1024x1024", "quality": "low", "background": "transparent", "output_format": "png", "moderation": "low", "n": 1.0}, "request body")


func test_rate_limit_gives_up_after_three_attempts() -> void:
	var client := StubByok.new("sk-test")
	client.retry_delay = 0.01
	var limited := _reply(429, {"error": {"message": "Rate limit reached"}})
	client.responses = [limited, limited, limited, limited]
	var result: Dictionary = await client._call_image_api("a prompt")
	check_eq(result.get("code"), "RATE_LIMITED", "code")
	check_eq(client.bodies.size(), 3, "three attempts")


func test_parse_image_response() -> void:
	var png := PackedByteArray([137, 80, 78, 71])
	var ok := BYOKClient.parse_image_response(HTTPRequest.RESULT_SUCCESS, 200, {}, JSON.stringify({"data": [{"b64_json": Marshalls.raw_to_base64(png)}]}).to_utf8_buffer())
	check_eq(ok, {"success": true, "png": png}, "b64_json image")

	var limited := BYOKClient.parse_image_response(HTTPRequest.RESULT_SUCCESS, 429, {"retry-after": "2"}, "{}".to_utf8_buffer())
	check_eq([limited["code"], limited["retry_after_ms"]], ["RATE_LIMITED", 2000], "429 with retry-after")

	var blocked := BYOKClient.parse_image_response(HTTPRequest.RESULT_SUCCESS, 400, {}, JSON.stringify({"error": {"message": "Your request was rejected by the safety system.", "code": "moderation_blocked"}}).to_utf8_buffer())
	check_eq([blocked["stage"], blocked["code"]], ["content_policy", "CONTENT_POLICY"], "moderation rejection")

	var bad_key := BYOKClient.parse_image_response(HTTPRequest.RESULT_SUCCESS, 401, {}, JSON.stringify({"error": {"message": "Incorrect API key provided"}}).to_utf8_buffer())
	check_eq([bad_key["code"], bad_key["message"]], ["API_ERROR", "Incorrect API key provided"], "API error message")

	var url_only := BYOKClient.parse_image_response(HTTPRequest.RESULT_SUCCESS, 200, {}, JSON.stringify({"data": [{"url": "https://example.com/a.png"}]}).to_utf8_buffer())
	check_eq(url_only["code"], "NO_IMAGE", "a URL response has no image data")

	var offline := BYOKClient.parse_image_response(HTTPRequest.RESULT_CANT_CONNECT, 0, {}, PackedByteArray())
	check_eq(offline["code"], "HTTP_FAILED", "no connection")


func test_generation_writes_frames_raw_sheet_and_manifest_v2() -> void:
	var root := make_temp_dir("byok_generate")
	var client := StubByok.new("sk-test")
	var events := _record(client)
	var hero_png := _grid_png(4, 1, 4)
	var coin_png := _grid_png(1, 1, 1)
	client.responses = [_image_reply(hero_png), _image_reply(coin_png)]
	var queue := [
		{"file_name": "hero.png", "category": "characters", "prompt": "knight idle", "frames": 4, "frame_w": 32, "frame_h": 32, "layout": "row"},
		{"file_name": "coin.png", "category": "items", "frames": 1, "layout": "row"},
	]

	await client.generate_sprites(queue, root, "pixel art")

	check_eq(events["completed"].size(), 1, "generation_completed")
	if events["completed"].is_empty():
		remove_dir(root)
		return
	var manifest: Dictionary = events["completed"][0]
	check_eq([manifest["version"], manifest["total_succeeded"], manifest["total_failed"]], [2, 2, 0], "manifest version and totals")
	var hero: Dictionary = manifest["results"][0]
	check_eq(hero["sprite_key"], "characters/hero.png", "sprite_key keeps the extension")
	check_eq([hero["file_path"], hero["raw_path"]], ["characters/hero.png", "characters/hero_raw.png"], "relative paths")
	check_eq(hero["frame_paths"], ["characters/hero/frame_0_0.png", "characters/hero/frame_0_1.png", "characters/hero/frame_0_2.png", "characters/hero/frame_0_3.png"], "frame paths")
	check_eq([hero["frame_w"], hero["frame_h"], hero["frames"], hero["rows"], hero["layout"]], [32, 32, 4, 1, "row"], "frame fields")
	check_eq([hero["grid_violation"], hero["image_id"], hero["status"], hero["error"]], [false, null, "ok", null], "status fields")
	check_eq(hero["prompt_text"], Prompting.build_prompt(queue[0], "pixel art")["prompt"], "backend prompt recorded")
	check_eq(client.bodies[0]["prompt"], hero["prompt_text"], "backend prompt sent")

	var sheet := Image.load_from_file(root.path_join("characters/hero.png"))
	check_eq(sheet.get_size(), Vector2i(128, 32), "sheet size")
	check_eq(hero["sha256"], BYOKClient.sha256_hex(FileAccess.get_file_as_bytes(root.path_join("characters/hero.png"))), "sheet sha256")
	check_eq(FileAccess.get_file_as_bytes(root.path_join("characters/hero_raw.png")), hero_png, "raw sheet as generated")
	for frame_path in hero["frame_paths"]:
		check_eq(Image.load_from_file(root.path_join(frame_path)).get_size(), Vector2i(32, 32), "%s size" % frame_path)

	var coin: Dictionary = manifest["results"][1]
	check_eq([coin["file_path"], coin["raw_path"], coin["frame_paths"], coin["frame_w"]], ["items/coin.png", null, [], 1024], "without a frame size the raw sheet is the result")
	check_eq(FileAccess.get_file_as_bytes(root.path_join("items/coin.png")), coin_png, "coin written unchanged")
	check_eq(events["percents"], [[50, "generating"], [100, "generating"]], "percent after each sprite")
	check(FileAccess.file_exists(root.path_join("run_manifest.json")), "run_manifest.json")
	remove_dir(root)


func test_invalid_items_fail_validation_without_a_request() -> void:
	var root := make_temp_dir("byok_invalid")
	var client := StubByok.new("sk-test")
	var events := _record(client)
	await client.generate_sprites([
		{"file_name": "../evil.png", "category": "misc", "frames": 1, "layout": "row"},
		{"file_name": "ok.png", "category": "a/b", "frames": 1, "layout": "row"},
		{"file_name": "ok.png", "category": "misc", "frames": "four", "layout": "row"},
	], root, "pixel art")
	check(client.bodies.is_empty(), "no API call")
	check_eq(events["failed"].size(), 1, "generation_failed")
	if events["failed"].size() == 1:
		var stages := []
		for error in events["failed"][0]["errors"]:
			stages.append(error["stage"])
		check_eq(stages, ["validation", "validation", "validation"], "each item rejected")
	check(not FileAccess.file_exists(root.get_base_dir().path_join("evil.png")), "nothing written outside output_root")
	remove_dir(root)


func test_content_policy_rejection_is_reported() -> void:
	var root := make_temp_dir("byok_blocked")
	var client := StubByok.new("sk-test")
	var events := _record(client)
	client.responses = [_reply(400, {"error": {"message": "Your request was rejected by the safety system.", "code": "moderation_blocked"}})]
	await client.generate_sprites([{"file_name": "bad.png", "category": "misc", "prompt": "something", "frames": 1, "layout": "row"}], root, "pixel art")
	check_eq(events["failed"].size(), 1, "generation_failed")
	if events["failed"].size() == 1:
		check_eq(events["failed"][0]["errors"][0]["stage"], "content_policy", "stage")
	remove_dir(root)
