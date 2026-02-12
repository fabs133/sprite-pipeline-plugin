@tool
class_name MockResponses
extends RefCounted
## Mock HTTP responses for plugin integration testing.
##
## Use these to simulate various server responses without making real API calls.

# Success responses
static func success_device_start() -> Dictionary:
	return {
		"status_code": 200,
		"body": {
			"device_code": "mock_device_code_123",
			"user_code": "TEST-1234",
			"verification_uri": "https://example.com/activate",
			"expires_in": 600
		}
	}


static func success_device_poll_pending() -> Dictionary:
	return {
		"status_code": 400,
		"body": {
			"error": {
				"code": "authorization_pending",
				"message": "Waiting for user to authorize"
			}
		}
	}


static func success_device_poll_authorized() -> Dictionary:
	return {
		"status_code": 200,
		"body": {
			"status": "authorized",
			"access_token": "mock_access_token_abc123",
			"refresh_token": "mock_refresh_token_def456",
			"expires_at": int(Time.get_unix_time_from_system()) + 3600
		}
	}


static func success_quota() -> Dictionary:
	return {
		"status_code": 200,
		"body": {
			"units_remaining": 75,
			"units_total": 100,
			"reset_date": "2025-02-01T00:00:00Z",
			"period_type": "monthly"
		}
	}


static func success_generate_sync() -> Dictionary:
	return {
		"status_code": 200,
		"body": {
			"job_id": "mock_job_123",
			"manifest": {
				"version": "1.0.0",
				"job_id": "mock_job_123",
				"results": [
					{
						"sprite_key": "characters/hero",
						"file_path": "res://assets/sprites/characters/hero.png",
						"sha256": "abc123def456",
						"frame_w": 64,
						"frame_h": 64,
						"frames": 4,
						"layout": "row",
						"safe_mode": false
					}
				],
				"errors": [],
				"safe_mode_count": 0,
				"inputs_hash": "sha256_mock_hash"
			}
		}
	}


static func success_generate_with_safe_mode() -> Dictionary:
	var resp := success_generate_sync()
	resp["body"]["manifest"]["results"][0]["safe_mode"] = true
	resp["body"]["manifest"]["safe_mode_count"] = 1
	return resp


# Error responses
static func error_upgrade_required_protocol() -> Dictionary:
	return {
		"status_code": 426,
		"headers": {"x-protocol-version": "2"},
		"body": {
			"error": {
				"code": "UPGRADE_REQUIRED",
				"message": "Protocol version 1 not supported. Required: 2",
				"stage": "protocol",
				"docs_key": "E-426-PROTOCOL"
			}
		}
	}


static func error_upgrade_required_version() -> Dictionary:
	return {
		"status_code": 426,
		"body": {
			"error": {
				"code": "UPGRADE_REQUIRED",
				"message": "Plugin version 0.1.0 too old. Minimum required: 0.2.0",
				"stage": "version",
				"docs_key": "E-426-VERSION"
			}
		}
	}


static func error_rate_limited(retry_after_seconds: int = 60) -> Dictionary:
	return {
		"status_code": 429,
		"headers": {"retry-after": str(retry_after_seconds)},
		"body": {
			"error": {
				"code": "RATE_LIMITED",
				"message": "Too many requests. Please wait before trying again.",
				"stage": "rate_limit",
				"retryable": true,
				"retry_after_ms": retry_after_seconds * 1000,
				"docs_key": "E-429-RATE"
			}
		}
	}


static func error_quota_exceeded() -> Dictionary:
	return {
		"status_code": 402,
		"body": {
			"error": {
				"code": "QUOTA_EXCEEDED",
				"message": "Insufficient quota. Need 5 units, have 0.",
				"stage": "quota_check",
				"retryable": false,
				"charged_units": 0,
				"charge_status": "not_charged",
				"docs_key": "E-402-QUOTA"
			}
		}
	}


static func error_unauthorized() -> Dictionary:
	return {
		"status_code": 401,
		"body": {
			"error": {
				"code": "INVALID_AUTH",
				"message": "Missing or invalid Authorization header",
				"stage": "auth",
				"docs_key": "E-401-AUTH"
			}
		}
	}


static func error_token_expired() -> Dictionary:
	return {
		"status_code": 401,
		"body": {
			"error": {
				"code": "TOKEN_EXPIRED",
				"message": "Access token has expired",
				"stage": "auth",
				"docs_key": "E-401-EXPIRED"
			}
		}
	}


static func error_content_policy() -> Dictionary:
	return {
		"status_code": 400,
		"body": {
			"error": {
				"code": "CONTENT_POLICY",
				"message": "Your prompt was rejected due to content policy violation",
				"stage": "content_policy",
				"retryable": false,
				"charged_units": 0,
				"charge_status": "not_charged",
				"docs_key": "E-400-CONTENT"
			}
		}
	}


static func error_generation_failed() -> Dictionary:
	return {
		"status_code": 500,
		"body": {
			"error": {
				"code": "GENERATION_FAILED",
				"message": "Image generation failed: timeout after 120s",
				"stage": "generation",
				"retryable": true,
				"request_id": "req_mock_123",
				"docs_key": "E-500-GEN"
			}
		}
	}


static func error_backend_unavailable() -> Dictionary:
	return {
		"status_code": 503,
		"body": {
			"error": {
				"code": "SERVICE_UNAVAILABLE",
				"message": "Backend temporarily unavailable",
				"stage": "connectivity",
				"retryable": true,
				"docs_key": "E-503-BACKEND"
			}
		}
	}


# Helper to create a full mock manifest
static func create_mock_manifest(sprite_count: int = 3, error_count: int = 0, safe_mode_count: int = 0) -> Dictionary:
	var results := []
	var errors := []

	for i in range(sprite_count):
		var safe_mode := i < safe_mode_count
		results.append({
			"sprite_key": "category_%d/sprite_%d" % [i % 3, i],
			"file_path": "res://assets/sprites/category_%d/sprite_%d.png" % [i % 3, i],
			"sha256": "sha256_mock_%d" % i,
			"frame_w": 64,
			"frame_h": 64,
			"frames": 1 + (i % 4),
			"layout": "row",
			"safe_mode": safe_mode,
			"generated_at": Time.get_datetime_string_from_system()
		})

	for i in range(error_count):
		errors.append({
			"file_name": "failed_sprite_%d.png" % i,
			"stage": "generation",
			"message": "Mock generation failure",
			"code": "GENERATION_FAILED"
		})

	return {
		"version": "1.0.0",
		"job_id": "mock_job_%d" % randi(),
		"model": "gpt-4o",
		"image_model": "dall-e-3",
		"global_style": "pixel art game sprite, test style",
		"output_root": "res://assets/sprites",
		"results": results,
		"errors": errors,
		"safe_mode_count": safe_mode_count,
		"inputs_hash": "sha256_mock_inputs_hash",
		"started_at": Time.get_datetime_string_from_system(),
		"completed_at": Time.get_datetime_string_from_system()
	}
