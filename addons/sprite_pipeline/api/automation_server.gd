@tool
extends RefCounted
## Dev-only automation server for deterministic testing.
##
## Listens on localhost TCP port for JSON commands from test runner.
## SECURITY: Only binds to localhost; dev-only toggle required.

signal command_received(command: String, args: Dictionary, request_id: String)
signal event_emitted(event: Dictionary)

const DEFAULT_PORT := 19876
const MAX_MESSAGE_SIZE := 1024 * 1024  # 1MB

# Allowlisted commands (no arbitrary file ops)
const ALLOWED_COMMANDS := [
	"ping",
	"get_state",
	"get_last_error_context",
	"get_doctor_report",
	"run_doctor",
	"start_generate",
	"cancel_generate",
	"import_only",
	"apply_fix",
	"verify_fix",
	"get_events",
	"clear_events",
	"get_manifest",
	"get_config",
	"set_config",
]

var _server: TCPServer
var _clients: Array[StreamPeerTCP] = []
var _enabled: bool = false
var _port: int = DEFAULT_PORT

# Event buffer (ring buffer for flight recorder)
var _events: Array[Dictionary] = []
var _max_events: int = 1000
var _event_seq: int = 0

# State tracking
var _last_error_context: Dictionary = {}
var _last_manifest: Dictionary = {}
var _current_run_id: String = ""
var _current_state: String = "idle"  # idle, generating, importing, error


func _init() -> void:
	_server = TCPServer.new()


## Enable the automation server (dev-only)
func enable(port: int = DEFAULT_PORT) -> Error:
	if _enabled:
		return OK

	_port = port
	var err := _server.listen(_port, "127.0.0.1")  # Localhost only!

	if err != OK:
		push_error("[AutomationServer] Failed to listen on port %d: %s" % [_port, error_string(err)])
		return err

	_enabled = true
	print_debug("[AutomationServer] Listening on 127.0.0.1:%d" % _port)
	return OK


## Disable the server
func disable() -> void:
	if not _enabled:
		return

	_server.stop()
	for client in _clients:
		client.disconnect_from_host()
	_clients.clear()
	_enabled = false
	print_debug("[AutomationServer] Stopped")


## Check if enabled
func is_enabled() -> bool:
	return _enabled


## Poll for new connections and messages (call from _process)
func poll() -> void:
	if not _enabled:
		return

	# Accept new connections
	while _server.is_connection_available():
		var client := _server.take_connection()
		_clients.append(client)
		print_debug("[AutomationServer] Client connected")

	# Process existing clients
	var to_remove: Array[int] = []

	for i in range(_clients.size()):
		var client := _clients[i]
		client.poll()

		match client.get_status():
			StreamPeerTCP.STATUS_CONNECTED:
				# Check for incoming data
				if client.get_available_bytes() > 0:
					_handle_client_data(client)
			StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR:
				to_remove.append(i)

	# Remove disconnected clients (reverse order)
	for i in range(to_remove.size() - 1, -1, -1):
		_clients.remove_at(to_remove[i])


## Handle incoming data from a client
func _handle_client_data(client: StreamPeerTCP) -> void:
	var available := client.get_available_bytes()
	if available <= 0:
		return

	# Read length-prefixed message (4 bytes length + JSON)
	if available < 4:
		return

	var length_bytes := client.get_data(4)
	if length_bytes[0] != OK:
		return

	var length := (length_bytes[1] as PackedByteArray).decode_u32(0)
	if length > MAX_MESSAGE_SIZE:
		_send_error(client, "MESSAGE_TOO_LARGE", "Message exceeds max size")
		return

	# Wait for full message
	var attempts := 0
	while client.get_available_bytes() < length and attempts < 100:
		OS.delay_msec(10)
		client.poll()
		attempts += 1

	if client.get_available_bytes() < length:
		_send_error(client, "INCOMPLETE_MESSAGE", "Message not fully received")
		return

	var body_result := client.get_data(length)
	if body_result[0] != OK:
		return

	var body_text := (body_result[1] as PackedByteArray).get_string_from_utf8()

	# Parse JSON
	var json := JSON.new()
	if json.parse(body_text) != OK:
		_send_error(client, "INVALID_JSON", "Failed to parse JSON")
		return

	var message: Dictionary = json.get_data()
	_handle_command(client, message)


## Handle a parsed command
func _handle_command(client: StreamPeerTCP, message: Dictionary) -> void:
	var command: String = message.get("command", "")
	var args: Dictionary = message.get("args", {})
	var request_id: String = message.get("request_id", _generate_id())

	print_debug("[AutomationServer] Received command: %s" % command)

	# Validate command is allowed
	if command not in ALLOWED_COMMANDS:
		_send_error(client, "COMMAND_NOT_ALLOWED", "Command not in allowlist: %s" % command, request_id)
		return

	# Emit signal for main dock to handle
	print_debug("[AutomationServer] Emitting command_received signal for: %s" % command)
	command_received.emit(command, args, request_id)

	# Handle built-in commands
	var response: Dictionary

	match command:
		"ping":
			response = _cmd_ping(args)
		"get_state":
			response = _cmd_get_state(args)
		"get_last_error_context":
			response = _cmd_get_last_error_context(args)
		"get_events":
			response = _cmd_get_events(args)
		"clear_events":
			response = _cmd_clear_events(args)
		"get_manifest":
			response = _cmd_get_manifest(args)
		_:
			# Other commands handled by main dock via signal
			response = {"status": "delegated", "message": "Command delegated to handler"}

	response["request_id"] = request_id
	_send_response(client, response)


## Send response to client
func _send_response(client: StreamPeerTCP, response: Dictionary) -> void:
	var json_str := JSON.stringify(response)
	var body := json_str.to_utf8_buffer()
	var length := body.size()

	var length_bytes := PackedByteArray()
	length_bytes.resize(4)
	length_bytes.encode_u32(0, length)

	client.put_data(length_bytes)
	client.put_data(body)


## Send error response
func _send_error(client: StreamPeerTCP, code: String, message: String, request_id: String = "") -> void:
	_send_response(client, {
		"status": "error",
		"error": {
			"code": code,
			"message": message
		},
		"request_id": request_id
	})


## Generate unique ID
func _generate_id() -> String:
	return "auto_%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000]


# ============================================================================
# Event Emission (Flight Recorder)
# ============================================================================

## Emit an event with correlation fields
func emit_event(event_type: String, data: Dictionary = {}) -> void:
	_event_seq += 1

	var event := {
		"seq": _event_seq,
		"timestamp": Time.get_datetime_string_from_system(),
		"unix_time": Time.get_unix_time_from_system(),
		"type": event_type,
		"run_id": _current_run_id,
		"state": _current_state,
		"data": data
	}

	# Add to ring buffer
	if _events.size() >= _max_events:
		_events.pop_front()
	_events.append(event)

	# Emit signal for external listeners
	event_emitted.emit(event)


## Set correlation fields for current run
func set_run_context(run_id: String, state: String) -> void:
	_current_run_id = run_id
	_current_state = state

	emit_event("state_change", {"new_state": state})


## Store last error context
func set_last_error_context(error: Dictionary) -> void:
	_last_error_context = error.duplicate(true)
	emit_event("error_context", {"error": _redact_error(error)})


## Store last manifest
func set_last_manifest(manifest: Dictionary) -> void:
	_last_manifest = manifest.duplicate(true)
	emit_event("manifest_received", {
		"results_count": manifest.get("results", []).size(),
		"errors_count": manifest.get("errors", []).size(),
		"safe_mode_count": manifest.get("safe_mode_count", 0),
		"inputs_hash": manifest.get("inputs_hash", "")
	})


## Get events since a sequence number
func get_events_since(since_seq: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in _events:
		if event["seq"] > since_seq:
			result.append(event)
	return result


## Redact sensitive data from error for logging
func _redact_error(error: Dictionary) -> Dictionary:
	var redacted := error.duplicate(true)

	# Never include tokens, keys, absolute paths, or emails
	var sensitive_keys := ["api_key", "access_token", "refresh_token", "authorization"]
	for key in sensitive_keys:
		if redacted.has(key):
			redacted[key] = "[REDACTED]"

	# Redact absolute paths
	if redacted.has("message"):
		var msg: String = redacted["message"]
		# Simple path redaction (Windows + Unix)
		msg = msg.replace("C:\\Users\\", "[USER]/")
		msg = msg.replace("/home/", "[HOME]/")
		msg = msg.replace("/Users/", "[USER]/")
		redacted["message"] = msg

	return redacted


# ============================================================================
# Built-in Command Handlers
# ============================================================================

func _cmd_ping(_args: Dictionary) -> Dictionary:
	return {
		"status": "ok",
		"message": "pong",
		"timestamp": Time.get_unix_time_from_system(),
		"plugin_version": "0.1.0",
		"protocol_version": "1"
	}


func _cmd_get_state(_args: Dictionary) -> Dictionary:
	return {
		"status": "ok",
		"state": _current_state,
		"run_id": _current_run_id,
		"event_count": _events.size(),
		"last_seq": _event_seq
	}


func _cmd_get_last_error_context(_args: Dictionary) -> Dictionary:
	if _last_error_context.is_empty():
		return {
			"status": "ok",
			"has_error": false
		}

	return {
		"status": "ok",
		"has_error": true,
		"error_context": _redact_error(_last_error_context)
	}


func _cmd_get_events(args: Dictionary) -> Dictionary:
	var since_seq: int = args.get("since_seq", 0)
	var limit: int = args.get("limit", 100)

	var events := get_events_since(since_seq)
	if events.size() > limit:
		events = events.slice(events.size() - limit)

	return {
		"status": "ok",
		"events": events,
		"total_count": _events.size(),
		"last_seq": _event_seq
	}


func _cmd_clear_events(_args: Dictionary) -> Dictionary:
	var count := _events.size()
	_events.clear()
	_event_seq = 0

	return {
		"status": "ok",
		"cleared_count": count
	}


func _cmd_get_manifest(_args: Dictionary) -> Dictionary:
	if _last_manifest.is_empty():
		return {
			"status": "ok",
			"has_manifest": false
		}

	# Return summary only (full manifest might be large)
	return {
		"status": "ok",
		"has_manifest": true,
		"manifest_summary": {
			"version": _last_manifest.get("version", ""),
			"job_id": _last_manifest.get("job_id", ""),
			"inputs_hash": _last_manifest.get("inputs_hash", ""),
			"results_count": _last_manifest.get("results", []).size(),
			"errors_count": _last_manifest.get("errors", []).size(),
			"safe_mode_count": _last_manifest.get("safe_mode_count", 0),
			"output_root": _last_manifest.get("output_root", "")
		}
	}
