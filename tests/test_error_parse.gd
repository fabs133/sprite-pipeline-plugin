extends "res://tests/test_case.gd"

const PoolClient := preload("res://addons/sprite_pipeline/api/pool_client.gd")


func test_plugin_error_envelope() -> void:
	var parsed := PoolClient.parse_error_body('{"error": {"code": "QUOTA_EXCEEDED", "message": "No units left", "retryable": false, "stage": "admit"}}')
	check_eq(parsed.get("code"), "QUOTA_EXCEEDED", "code")
	check_eq(parsed.get("message"), "No units left", "message")
	check_eq(parsed.get("stage"), "admit", "stage")
	check_eq(parsed.get("retryable"), false, "retryable")


func test_fastapi_detail_envelope() -> void:
	var parsed := PoolClient.parse_error_body('{"detail": {"error": "job_failed", "message": "All sprites failed"}}')
	check_eq(parsed.get("code"), "job_failed", "code")
	check_eq(parsed.get("message"), "All sprites failed", "message")


func test_detail_without_message_keeps_the_code() -> void:
	var parsed := PoolClient.parse_error_body('{"detail": {"error": "job_not_finished", "status": "running"}}')
	check_eq(parsed.get("code"), "job_not_finished", "code")
	check(not parsed.has("message"), "no message")


func test_mask_validation_details_join_the_message() -> void:
	var parsed := PoolClient.parse_error_body('{"detail": {"error": "invalid_mask", "message": "Mask validation failed", "details": ["Item 0: frames must be a positive integer", "Queue is empty"]}}')
	check_eq(parsed.get("message"), "Mask validation failed: Item 0: frames must be a positive integer; Queue is empty", "message")


func test_plain_and_list_details() -> void:
	check_eq(PoolClient.parse_error_body('{"detail": "Not authenticated"}').get("message"), "Not authenticated", "string detail")
	check_eq(PoolClient.parse_error_body('{"detail": [{"loc": ["body"], "msg": "field required"}]}').get("message"), "field required", "validation list")


func test_unparseable_bodies_give_nothing() -> void:
	check(PoolClient.parse_error_body("<html>502 Bad Gateway</html>").is_empty(), "html body")
	check(PoolClient.parse_error_body("[1, 2]").is_empty(), "array body")
	check(PoolClient.parse_error_body("").is_empty(), "empty body")


func test_status_codes_map_and_keep_the_server_message() -> void:
	var client = PoolClient.new("")
	var quota: Dictionary = client._handle_error_response(402, '{"detail": {"error": "quota_exceeded", "message": "Monthly quota used up"}}', {})
	check_eq(quota["error"]["code"], "QUOTA_EXCEEDED", "402 code")
	check_eq(quota["error"]["message"], "Monthly quota used up", "402 message from the server")

	var gone: Dictionary = client._handle_error_response(410, '{"detail": {"error": "job_failed", "message": "Job cancelled"}}', {"x-request-id": "abc"})
	check_eq(gone["error"]["code"], "job_failed", "410 code from detail.error")
	check_eq(gone["error"]["message"], "Job cancelled", "410 message")
	check_eq(gone["error"]["request_id"], "abc", "request id header")

	var limited: Dictionary = client._handle_error_response(429, '{"detail": {"error": "concurrent_limit", "message": "Too many jobs"}}', {"retry-after": "7"})
	check_eq(limited["error"]["code"], "RATE_LIMITED", "429 code")
	check_eq(limited["error"]["retry_after_ms"], 7000, "retry-after")

	var upgrade: Dictionary = client._handle_error_response(426, "", {})
	check_eq(upgrade["error"]["code"], "UPGRADE_REQUIRED", "426 code")
	check_eq(upgrade["error"]["message"], "Plugin version too old. Please update.", "426 fallback message")
