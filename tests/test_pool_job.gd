extends "res://tests/test_case.gd"
## Pool job flow against a stubbed server: polling, downloads, cache.

const PoolClient := preload("res://addons/sprite_pipeline/api/pool_client.gd")
const SpriteCache := preload("res://addons/sprite_pipeline/cache/sprite_cache.gd")

const HASH := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"


class StubClient extends "res://addons/sprite_pipeline/api/pool_client.gd":
	var responses: Array = []
	var requests: Array = []
	var files: Dictionary = {}  # url -> PackedByteArray
	var downloads: Array = []

	func _make_request(method: int, endpoint: String, body: Dictionary = {}) -> Dictionary:
		requests.append({"method": method, "endpoint": endpoint, "body": body})
		if responses.is_empty():
			return {"success": false, "error": {"code": "NO_STUB", "message": "no stubbed response", "status_code": 499}}
		return responses.pop_front()

	func _download_file(url: String) -> Dictionary:
		downloads.append(url)
		if files.has(url):
			return {"success": true, "status_code": 200, "body": files[url]}
		return {"success": false, "status_code": 404, "body": PackedByteArray()}


class Recorder:
	var progress: Array = []
	var percents: Array = []
	var completed: Array = []
	var failed: Array = []

	func attach(client) -> void:
		client.generation_progress.connect(func(stage, message): progress.append([stage, message]))
		client.generation_percent.connect(func(percent, stage): percents.append([percent, stage]))
		client.generation_completed.connect(func(manifest): completed.append(manifest))
		client.generation_failed.connect(func(error): failed.append(error))


func _client() -> StubClient:
	var client := StubClient.new("http://localhost:8000")
	client.initial_poll_interval = 0.01
	return client


func _ok(data: Dictionary) -> Dictionary:
	return {"success": true, "status_code": 200, "data": data}


func _fail(status_code: int) -> Dictionary:
	return {"success": false, "error": {"code": "HTTP_FAILED" if status_code == 0 else "API_ERROR", "message": "failed", "status_code": status_code}}


## An asset entry served by the stub; sha256 defaults to the body's hash
func _serve(client: StubClient, path: String, kind: String, body: PackedByteArray, sha256 := "") -> Dictionary:
	var url := "http://localhost:8000/v1/assets/job/%s?sig=x" % path
	client.files[url] = body
	return {
		"path": path,
		"url": url,
		"sha256": sha256 if not sha256.is_empty() else PoolClient.sha256_hex(body),
		"bytes": body.size(),
		"kind": kind,
		"sprite_key": "characters/hero.png",
	}


func test_downloads_are_verified_and_raw_sheets_skipped() -> void:
	var root := make_temp_dir("pool_download")
	var client := _client()
	var recorder := Recorder.new()
	recorder.attach(client)
	var sheet := "sheet".to_utf8_buffer()
	var assets := [
		_serve(client, "characters/hero.png", "sheet", sheet),
		_serve(client, "characters/hero/frame_0_0.png", "frame", "frame".to_utf8_buffer(), PoolClient.sha256_hex("other".to_utf8_buffer())),
		_serve(client, "characters/hero_raw.png", "raw", "raw".to_utf8_buffer()),
	]

	await client._handle_sync_response({"manifest": {"version": 2, "results": []}, "assets": assets}, root)

	check_eq(FileAccess.get_file_as_bytes(root.path_join("characters/hero.png")), sheet, "sheet written")
	check(not FileAccess.file_exists(root.path_join("characters/hero/frame_0_0.png")), "frame with a wrong sha256 not written")
	check(not FileAccess.file_exists(root.path_join("characters/hero_raw.png")), "raw sheet skipped by default")
	check_eq(client.downloads.size(), 2, "raw sheet not downloaded")
	check_eq(recorder.completed.size(), 1, "generation_completed")
	if recorder.completed.size() == 1:
		check_eq(recorder.completed[0].get("download_errors"), [{"path": "characters/hero/frame_0_0.png", "reason": "sha256_mismatch"}], "download_errors in the manifest")
	check(["download_warnings", "1 assets skipped"] in recorder.progress, "download warning progress")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("run_manifest.json")))
	check(saved is Dictionary and saved.has("download_errors"), "run_manifest.json lists the download errors")
	remove_dir(root)


func test_raw_sheets_download_when_enabled() -> void:
	var root := make_temp_dir("pool_download_raw")
	var client := _client()
	client.download_raw = true
	var raw := "raw".to_utf8_buffer()
	var assets := [_serve(client, "characters/hero_raw.png", "raw", raw)]
	await client._handle_sync_response({"manifest": {"version": 2, "results": []}, "assets": assets}, root)
	check_eq(FileAccess.get_file_as_bytes(root.path_join("characters/hero_raw.png")), raw, "raw sheet written")
	remove_dir(root)


func test_unsafe_assets_are_neither_downloaded_nor_written() -> void:
	var root := make_temp_dir("pool_download_unsafe")
	var client := _client()
	var recorder := Recorder.new()
	recorder.attach(client)
	var assets := [
		_serve(client, "../escape.png", "sheet", "x".to_utf8_buffer()),
		{"path": "characters/hero.png", "url": "file:///etc/passwd", "kind": "sheet"},
	]
	await client._handle_sync_response({"manifest": {"version": 2, "results": []}, "assets": assets}, root)
	check(client.downloads.is_empty(), "nothing downloaded")
	check(not FileAccess.file_exists(root.get_base_dir().path_join("escape.png")), "nothing written outside output_root")
	check_eq(recorder.completed[0]["download_errors"].size(), 2, "both assets reported")
	remove_dir(root)


func test_cache_keeps_relative_paths_and_restores_them() -> void:
	var root := make_temp_dir("pool_cache_out")
	var restored_root := make_temp_dir("pool_cache_restored")
	var cache_root := make_temp_dir("pool_cache")
	var cache := SpriteCache.new(cache_root, 100.0)
	check_eq(cache.initialize(), OK, "cache initializes")
	var client := _client()
	client.set_sprite_cache(cache)
	client._current_inputs_hash = HASH
	var hero_frame := "hero frame".to_utf8_buffer()
	var sword_frame := "sword frame".to_utf8_buffer()
	var assets := [
		_serve(client, "characters/hero/frame_0_0.png", "frame", hero_frame),
		_serve(client, "items/sword/frame_0_0.png", "frame", sword_frame),
	]
	var manifest := {"version": 2, "results": [{"file_path": "characters/hero.png"}]}
	await client._handle_sync_response({"manifest": manifest, "assets": assets}, root)

	var cached := cache.get_cached_files(HASH)
	check_eq(cached.size(), 2, "both frames cached although they share a file name")

	check(client._restore_cached_sprites(HASH, manifest, restored_root), "restore succeeds")
	check_eq(FileAccess.get_file_as_bytes(restored_root.path_join("characters/hero/frame_0_0.png")), hero_frame, "hero frame restored")
	check_eq(FileAccess.get_file_as_bytes(restored_root.path_join("items/sword/frame_0_0.png")), sword_frame, "sword frame restored")
	check(FileAccess.file_exists(restored_root.path_join("run_manifest.json")), "manifest restored")

	if cached.size() == 2:
		DirAccess.remove_absolute(cached[0]["abs"])
		check(not client._restore_cached_sprites(HASH, manifest, restored_root), "restore fails when a cached file is missing")

	cache.remove_entry(HASH)
	check(not DirAccess.dir_exists_absolute(cache_root.path_join(HASH.substr(0, 16))), "entry directory removed with its subdirectories")
	for dir in [root, restored_root, cache_root]:
		remove_dir(dir)


func test_incomplete_downloads_are_not_cached() -> void:
	var root := make_temp_dir("pool_cache_partial")
	var cache_root := make_temp_dir("pool_cache_partial_cache")
	var cache := SpriteCache.new(cache_root, 100.0)
	cache.initialize()
	var client := _client()
	client.set_sprite_cache(cache)
	client._current_inputs_hash = HASH
	var assets := [_serve(client, "characters/hero.png", "sheet", "a".to_utf8_buffer(), PoolClient.sha256_hex("b".to_utf8_buffer()))]
	await client._handle_sync_response({"manifest": {"version": 2, "results": []}, "assets": assets}, root)
	check(not cache.has_cached(HASH), "a result with skipped assets is not cached")
	remove_dir(root)
	remove_dir(cache_root)


func test_poll_retries_transient_failures_then_completes() -> void:
	var root := make_temp_dir("pool_poll")
	var client := _client()
	var recorder := Recorder.new()
	recorder.attach(client)
	client.responses = [
		_fail(0),
		_fail(502),
		_ok({"status": "running", "progress_stage": null, "stage": null, "progress_percent": null}),
		_ok({"status": "running", "progress_stage": "generating", "stage": "generating", "progress_percent": 40.0}),
		_ok({"status": "completed", "progress_stage": "completed", "stage": "completed", "progress_percent": 100.0}),
		_ok({"job_id": "j1", "manifest": {"version": 2, "results": []}, "assets": []}),
	]
	await client._poll_job_status("j1", root)
	check(recorder.failed.is_empty(), "no failure: %s" % str(recorder.failed))
	check_eq(recorder.completed.size(), 1, "completes after two transient failures")
	check([0, "running"] in recorder.percents, "missing progress falls back to 0 and the status")
	check([40, "generating"] in recorder.percents, "percent from progress_percent and progress_stage")
	check_eq(client.requests.size(), 6, "five status polls, then the result")
	if client.requests.size() == 6:
		check_eq(client.requests[5]["endpoint"], "/v1/jobs/j1/result", "result endpoint")
	remove_dir(root)


func test_poll_gives_up_after_three_transient_failures() -> void:
	var client := _client()
	var recorder := Recorder.new()
	recorder.attach(client)
	client.responses = [_fail(0), _fail(503), _fail(0), _fail(0)]
	await client._poll_job_status("j1", "user://tests/unused")
	check_eq(client.requests.size(), 4, "first try plus three retries")
	check_eq(recorder.failed.size(), 1, "generation_failed")
	check(recorder.completed.is_empty(), "not completed")


func test_poll_fails_at_once_on_client_errors() -> void:
	var client := _client()
	var recorder := Recorder.new()
	recorder.attach(client)
	client.responses = [_fail(404)]
	await client._poll_job_status("j1", "user://tests/unused")
	check_eq(client.requests.size(), 1, "no retry on 404")
	check_eq(recorder.failed.size(), 1, "generation_failed")


func test_failed_and_cancelled_jobs_fail_the_generation() -> void:
	var cases := {
		"failed": {"status": "failed", "error_message": "All sprites failed: characters/hero.png: content policy", "progress_stage": "failed"},
		"cancelled": {"status": "cancelled", "error_message": null, "progress_stage": "cancelled"},
	}
	var expected_codes := {"failed": "JOB_FAILED", "cancelled": "CANCELLED"}
	for status in cases:
		var client := _client()
		var recorder := Recorder.new()
		recorder.attach(client)
		client.responses = [_ok(cases[status])]
		await client._poll_job_status("j1", "user://tests/unused")
		check_eq(recorder.failed.size(), 1, "%s fails" % status)
		if recorder.failed.size() == 1:
			check_eq(recorder.failed[0]["code"], expected_codes[status], "%s code" % status)
	# The failed job's message reaches the dock
	var client := _client()
	var recorder := Recorder.new()
	recorder.attach(client)
	client.responses = [_ok(cases["failed"])]
	await client._poll_job_status("j1", "user://tests/unused")
	check_eq(recorder.failed[0]["message"], cases["failed"]["error_message"], "failure message")


func test_user_cancel_cancels_the_server_job() -> void:
	var client := _client()
	var recorder := Recorder.new()
	recorder.attach(client)
	client.cancel()
	client.responses = [_ok({"status": "cancelled", "units_charged": 1})]
	await client._poll_job_status("j1", "user://tests/unused")
	check_eq(client.requests.size(), 1, "one request")
	if client.requests.size() == 1:
		check_eq(client.requests[0]["endpoint"], "/v1/jobs/j1/cancel", "cancel endpoint")
	check_eq(recorder.failed.size(), 1, "generation_failed")
	if recorder.failed.size() == 1:
		check_eq(recorder.failed[0]["code"], "CANCELLED", "code")
		check_eq(recorder.failed[0]["units_charged"], 1, "units charged for the cancel")


func test_second_identical_run_is_a_cache_hit() -> void:
	var root := make_temp_dir("pool_generate")
	var cache_root := make_temp_dir("pool_generate_cache")
	var cache := SpriteCache.new(cache_root, 100.0)
	cache.initialize()
	var client := _client()
	client.set_sprite_cache(cache)
	var recorder := Recorder.new()
	recorder.attach(client)
	var sheet := "sheet bytes".to_utf8_buffer()
	var asset := _serve(client, "characters/hero.png", "sheet", sheet)
	var queue := [{"file_name": "hero.png", "category": "characters", "frames": 4, "layout": "row", "frame_w": 32, "frame_h": 32}]
	client.responses = [
		{"success": true, "status_code": 202, "data": {"job_id": "j1", "request_id": "r1", "units_reserved": 1}},
		_ok({"status": "completed", "progress_stage": "completed", "stage": "completed", "progress_percent": 100.0}),
		_ok({"job_id": "j1", "manifest": {"version": 2, "results": [{"file_path": "characters/hero.png"}]}, "assets": [asset]}),
	]
	await client.generate_sprites(queue, root, "pixel art")
	check_eq(client.requests[0]["endpoint"], "/v1/generate", "submits to /v1/generate")
	check_eq(client.requests[0]["body"].get("queue"), queue, "queue in the body")
	check_eq(recorder.completed.size(), 1, "first run completes")

	DirAccess.remove_absolute(root.path_join("characters/hero.png"))
	var hits := []
	client.cache_hit.connect(func(inputs_hash): hits.append(inputs_hash))
	await client.generate_sprites(queue, root, "pixel art")
	check_eq(hits.size(), 1, "second run is a cache hit")
	check_eq(client.requests.size(), 3, "no further requests")
	check_eq(FileAccess.get_file_as_bytes(root.path_join("characters/hero.png")), sheet, "sheet restored byte for byte")
	check_eq(recorder.completed.size(), 2, "second run completes")
	remove_dir(root)
	remove_dir(cache_root)
