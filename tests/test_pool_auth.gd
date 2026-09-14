extends "res://tests/test_case.gd"

const PoolClient := preload("res://addons/sprite_pipeline/api/pool_client.gd")


class StubClient extends "res://addons/sprite_pipeline/api/pool_client.gd":
	var responses: Array = []
	var requests: Array = []

	func _make_request(method: int, endpoint: String, body: Dictionary = {}) -> Dictionary:
		requests.append({"method": method, "endpoint": endpoint, "body": body})
		return responses.pop_front()


func _ok(data: Dictionary) -> Dictionary:
	return {"success": true, "status_code": 200, "data": data}


func test_device_login_uses_backend_paths() -> void:
	check_eq(PoolClient.ENDPOINT_DEVICE_START, "/v1/auth/device-start", "start path")
	check_eq(PoolClient.ENDPOINT_DEVICE_POLL, "/v1/auth/device-poll", "poll path")


func test_pending_poll_is_not_a_failure() -> void:
	var client := StubClient.new("http://localhost:8000")
	var auth_errors := []
	client.auth_failed.connect(func(error): auth_errors.append(error))
	client.responses = [_ok({"status": "pending"})]
	var result: Dictionary = await client.poll_device_auth("ABCD-1234")
	check_eq(result["success"], false, "success")
	check_eq(result["error"]["code"], "authorization_pending", "code")
	check(auth_errors.is_empty(), "no auth_failed while pending")
	check_eq(client.requests[0]["body"], {"device_code": "ABCD-1234"}, "poll body")


func test_approved_poll_stores_tokens_with_expiry() -> void:
	var client := StubClient.new("http://localhost:8000")
	var completed := []
	client.auth_completed.connect(func(token): completed.append(token))
	client.responses = [_ok({"access_token": "acc", "refresh_token": "ref", "expires_in": 3600.0, "token_type": "bearer"})]
	var now := int(Time.get_unix_time_from_system())
	await client.poll_device_auth("ABCD-1234")
	check_eq(completed, ["acc"], "auth_completed")
	check_eq(client._refresh_token, "ref", "refresh token")
	check(absi(client._token_expires_at - (now + 3600)) <= 2, "expires about an hour from now")
	check(not client.is_token_expired(), "a fresh token is not expired")


func test_expired_and_denied_codes_fail() -> void:
	for status in ["expired", "denied"]:
		var client := StubClient.new("http://localhost:8000")
		var auth_errors := []
		client.auth_failed.connect(func(error): auth_errors.append(error))
		client.responses = [_ok({"status": status})]
		await client.poll_device_auth("ABCD-1234")
		check_eq(auth_errors.size(), 1, "%s emits auth_failed" % status)
		if auth_errors.size() == 1:
			check_eq(auth_errors[0]["code"], "device_code_%s" % status, "%s code" % status)


func test_refresh_rotates_tokens() -> void:
	var client := StubClient.new("http://localhost:8000")
	client.set_tokens("old", "old-refresh", 0)
	client.responses = [_ok({"access_token": "new", "refresh_token": "new-refresh", "expires_in": 60})]
	var result: Dictionary = await client.refresh_auth()
	check(result["success"], "refresh succeeds")
	check_eq(client.requests[0]["body"], {"refresh_token": "old-refresh"}, "refresh body")
	check_eq(client._access_token, "new", "access token")
	check_eq(client._refresh_token, "new-refresh", "refresh token")


func test_token_expiry() -> void:
	check_eq(PoolClient.token_expiry({"expires_in": 3600}, 1000), 4600, "expires_in")
	check_eq(PoolClient.token_expiry({"expires_in": 60.0}, 1000), 1060, "float expires_in")
	check_eq(PoolClient.token_expiry({"expires_at": 5000}, 1000), 5000, "expires_at")
	check_eq(PoolClient.token_expiry({}, 1000), 0, "unknown")
