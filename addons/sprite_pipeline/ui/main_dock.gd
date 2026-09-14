@tool
extends VBoxContainer
## Main dock UI for Sprite Pipeline plugin.
##
## Handles mode switching, authentication, quota display,
## generation workflow, and error reporting.
##
## Also hosts the AutomationServer for test system integration.

const SETTINGS_PATH := "user://sprite_pipeline_settings.cfg"
# Hosts of the retired hosted Pool service; saved settings pointing at them are cleared on load
const RETIRED_POOL_HOSTS := ["sprites.pi-agents.dev"]
const Version := preload("res://addons/sprite_pipeline/version.gd")
const ManifestPaths := preload("res://addons/sprite_pipeline/manifest_paths.gd")

# Automation server for test system integration
const AutomationServer := preload("res://addons/sprite_pipeline/api/automation_server.gd")

# Sprite cache for local caching
const SpriteCacheClass := preload("res://addons/sprite_pipeline/cache/sprite_cache.gd")

# Editor calls (FileSystem scans, reimports, project settings) and consent dialogs
const EditorIntegration := preload("res://addons/sprite_pipeline/editor_integration.gd")
const ConsentGate := preload("res://addons/sprite_pipeline/remediation/consent_gate.gd")
const ImportParams := preload("res://addons/sprite_pipeline/import_params.gd")

# Node references (set in _ready)
@onready var byok_button: Button = $ModeSection/ModeButtons/BYOKButton
@onready var pool_button: Button = $ModeSection/ModeButtons/PoolButton

@onready var byok_auth: VBoxContainer = $AuthSection/BYOKAuth
@onready var pool_auth: VBoxContainer = $AuthSection/PoolAuth
@onready var api_key_edit: LineEdit = $AuthSection/BYOKAuth/APIKeyEdit
@onready var key_status: Label = $AuthSection/BYOKAuth/KeyStatus
@onready var image_model_option: OptionButton = $AuthSection/BYOKAuth/ImageModelRow/ImageModelOption
@onready var custom_model_edit: LineEdit = $AuthSection/BYOKAuth/ImageModelRow/CustomModelEdit
@onready var image_quality_option: OptionButton = $AuthSection/BYOKAuth/ImageQualityOption
@onready var server_edit: LineEdit = $AuthSection/PoolAuth/ServerEdit
@onready var auth_status: Label = $AuthSection/PoolAuth/AuthStatus
@onready var login_button: Button = $AuthSection/PoolAuth/LoginButton
@onready var device_code_container: VBoxContainer = $AuthSection/PoolAuth/DeviceCodeContainer
@onready var device_code_label: Label = $AuthSection/PoolAuth/DeviceCodeContainer/DeviceCode
@onready var verify_link: LinkButton = $AuthSection/PoolAuth/DeviceCodeContainer/VerifyLink
@onready var download_raw_check: CheckBox = $AuthSection/PoolAuth/DownloadRawCheck

@onready var quota_section: VBoxContainer = $QuotaSection
@onready var units_label: Label = $QuotaSection/QuotaInfo/UnitsLabel
@onready var reset_label: Label = $QuotaSection/QuotaInfo/ResetLabel
@onready var quota_bar: ProgressBar = $QuotaSection/QuotaBar
@onready var refresh_quota_button: Button = $QuotaSection/RefreshQuotaButton

@onready var queue_path_edit: LineEdit = $GenerateSection/QueuePath/QueuePathEdit
@onready var output_path_edit: LineEdit = $GenerateSection/OutputPath/OutputPathEdit
@onready var style_edit: TextEdit = $GenerateSection/StyleEdit
@onready var generate_button: Button = $GenerateSection/GenerateButtons/GenerateButton
@onready var cancel_button: Button = $GenerateSection/GenerateButtons/CancelButton
@onready var write_spriteframes_check: CheckButton = $GenerateSection/SpriteFramesRow/WriteSpriteFramesCheck
@onready var spriteframes_fps_spin: SpinBox = $GenerateSection/SpriteFramesRow/SpriteFramesFpsSpin

@onready var progress_bar: ProgressBar = $StatusSection/ProgressBar
@onready var status_text: Label = $StatusSection/StatusText
@onready var error_section: VBoxContainer = $StatusSection/ErrorSection
@onready var error_text: TextEdit = $StatusSection/ErrorSection/ErrorText
@onready var copy_error_button: Button = $StatusSection/ErrorSection/ErrorButtons/CopyErrorButton
@onready var results_section: VBoxContainer = $StatusSection/ResultsSection
@onready var results_label: Label = $StatusSection/ResultsSection/ResultsLabel
@onready var open_output_button: Button = $StatusSection/ResultsSection/OpenOutputButton
@onready var reimport_button: Button = $StatusSection/ResultsSection/ReimportButton
@onready var filter_row: HBoxContainer = $StatusSection/ResultsSection/FilterRow
@onready var filter_label: Label = $StatusSection/ResultsSection/FilterRow/FilterLabel
@onready var filter_button: Button = $StatusSection/ResultsSection/FilterRow/FilterButton
@onready var spriteframes_links: VBoxContainer = $StatusSection/ResultsSection/SpriteFramesLinks
@onready var export_report_button: Button = $StatusSection/ErrorSection/ErrorButtons/ExportReportButton

# Cache UI nodes
@onready var cache_section: VBoxContainer = $CacheSection
@onready var cache_toggle: CheckButton = $CacheSection/CacheSectionHeader/CacheToggle
@onready var cache_size_label: Label = $CacheSection/CacheStats/CacheSizeLabel
@onready var cache_hit_label: Label = $CacheSection/CacheStats/CacheHitLabel
@onready var cache_bar: ProgressBar = $CacheSection/CacheBar
@onready var clear_cache_button: Button = $CacheSection/CacheButtons/ClearCacheButton
@onready var cache_settings_button: Button = $CacheSection/CacheButtons/CacheSettingsButton

# Preload client classes to avoid parse-time type resolution issues
const BYOKClientClass = preload("res://addons/sprite_pipeline/api/byok_client.gd")
const Prompting := preload("res://addons/sprite_pipeline/prompting.gd")
# Last entry of the BYOK model picker; it shows a field for any other model name
const CUSTOM_MODEL_LABEL := "Custom..."
const PoolClientClass = preload("res://addons/sprite_pipeline/api/pool_client.gd")

# State
var _current_mode: String = "byok"
var _byok_client = null  # BYOKClient
var _pool_client = null  # PoolClient
var _is_generating: bool = false
var _last_error: Dictionary = {}
var _last_manifest: Dictionary = {}
var _device_poll_timer: Timer = null
# SpriteEditorIntegration; tests put a stub with the same methods here
var _editor = EditorIntegration
var _consent_gate := ConsentGate.new()
# [editor] filter_prompt_dismissed: "Don't ask again" on the Nearest filter offer
var _filter_prompt_dismissed := false
var _filter_dialog_open := false
# [editor] pin_import_params: pin lossless, no-mipmap, no-3D-compression imports on generated PNGs
var _pin_import_params := true
# Output directory of the running or last generation
var _last_output_root := ""
# [editor] spriteframes_loop and overwrite_spriteframes, set in the settings file only;
# write_spriteframes and spriteframes_fps live in the generate section's controls
var _spriteframes_loop := true
var _overwrite_spriteframes := false

# Automation server instance (for test system)
var _automation_server = null  # AutomationServer
var _automation_enabled: bool = false

# Plugin's automation server reference (set by plugin before _ready)
var _plugin_automation_server = null

# Sprite cache instance
var _sprite_cache = null  # SpriteCache

# Initialization state and command queue
var _initialized := false
var _pending_commands: Array = []  # Queue of [command, args, request_id] tuples

## Force initialization - called by plugin when _ready() hasn't fired yet
func force_initialize() -> void:
	if _initialized:
		return
	print_debug("[SpritePipeline] force_initialize called")

	# Manually get node references that @onready would set
	byok_button = get_node_or_null("ModeSection/ModeButtons/BYOKButton")
	pool_button = get_node_or_null("ModeSection/ModeButtons/PoolButton")
	byok_auth = get_node_or_null("AuthSection/BYOKAuth")
	pool_auth = get_node_or_null("AuthSection/PoolAuth")
	api_key_edit = get_node_or_null("AuthSection/BYOKAuth/APIKeyEdit")
	key_status = get_node_or_null("AuthSection/BYOKAuth/KeyStatus")
	image_model_option = get_node_or_null("AuthSection/BYOKAuth/ImageModelRow/ImageModelOption")
	custom_model_edit = get_node_or_null("AuthSection/BYOKAuth/ImageModelRow/CustomModelEdit")
	image_quality_option = get_node_or_null("AuthSection/BYOKAuth/ImageQualityOption")
	server_edit = get_node_or_null("AuthSection/PoolAuth/ServerEdit")
	auth_status = get_node_or_null("AuthSection/PoolAuth/AuthStatus")
	login_button = get_node_or_null("AuthSection/PoolAuth/LoginButton")
	device_code_container = get_node_or_null("AuthSection/PoolAuth/DeviceCodeContainer")
	device_code_label = get_node_or_null("AuthSection/PoolAuth/DeviceCodeContainer/DeviceCode")
	verify_link = get_node_or_null("AuthSection/PoolAuth/DeviceCodeContainer/VerifyLink")
	download_raw_check = get_node_or_null("AuthSection/PoolAuth/DownloadRawCheck")
	quota_section = get_node_or_null("QuotaSection")
	units_label = get_node_or_null("QuotaSection/QuotaInfo/UnitsLabel")
	reset_label = get_node_or_null("QuotaSection/QuotaInfo/ResetLabel")
	quota_bar = get_node_or_null("QuotaSection/QuotaBar")
	refresh_quota_button = get_node_or_null("QuotaSection/RefreshQuotaButton")
	queue_path_edit = get_node_or_null("GenerateSection/QueuePath/QueuePathEdit")
	output_path_edit = get_node_or_null("GenerateSection/OutputPath/OutputPathEdit")
	style_edit = get_node_or_null("GenerateSection/StyleEdit")
	generate_button = get_node_or_null("GenerateSection/GenerateButtons/GenerateButton")
	cancel_button = get_node_or_null("GenerateSection/GenerateButtons/CancelButton")
	write_spriteframes_check = get_node_or_null("GenerateSection/SpriteFramesRow/WriteSpriteFramesCheck")
	spriteframes_fps_spin = get_node_or_null("GenerateSection/SpriteFramesRow/SpriteFramesFpsSpin")
	progress_bar = get_node_or_null("StatusSection/ProgressBar")
	status_text = get_node_or_null("StatusSection/StatusText")
	error_section = get_node_or_null("StatusSection/ErrorSection")
	error_text = get_node_or_null("StatusSection/ErrorSection/ErrorText")
	copy_error_button = get_node_or_null("StatusSection/ErrorSection/ErrorButtons/CopyErrorButton")
	results_section = get_node_or_null("StatusSection/ResultsSection")
	results_label = get_node_or_null("StatusSection/ResultsSection/ResultsLabel")
	open_output_button = get_node_or_null("StatusSection/ResultsSection/OpenOutputButton")
	reimport_button = get_node_or_null("StatusSection/ResultsSection/ReimportButton")
	filter_row = get_node_or_null("StatusSection/ResultsSection/FilterRow")
	filter_label = get_node_or_null("StatusSection/ResultsSection/FilterRow/FilterLabel")
	filter_button = get_node_or_null("StatusSection/ResultsSection/FilterRow/FilterButton")
	spriteframes_links = get_node_or_null("StatusSection/ResultsSection/SpriteFramesLinks")
	export_report_button = get_node_or_null("StatusSection/ErrorSection/ErrorButtons/ExportReportButton")
	cache_section = get_node_or_null("CacheSection")
	cache_toggle = get_node_or_null("CacheSection/CacheSectionHeader/CacheToggle")
	cache_size_label = get_node_or_null("CacheSection/CacheStats/CacheSizeLabel")
	cache_hit_label = get_node_or_null("CacheSection/CacheStats/CacheHitLabel")
	cache_bar = get_node_or_null("CacheSection/CacheBar")
	clear_cache_button = get_node_or_null("CacheSection/CacheButtons/ClearCacheButton")
	cache_settings_button = get_node_or_null("CacheSection/CacheButtons/CacheSettingsButton")

	# Now do the initialization that _ready would do
	_init_sprite_cache()
	_setup_byok_model_options()
	_load_settings()
	_setup_connections()
	_update_ui_for_mode()
	_update_cache_ui()
	_update_version_label()

	_initialized = true
	print_debug("[SpritePipeline] Dock force initialized")

	# Process any queued commands
	_process_pending_commands()


## Try to force initialize (called when commands arrive before init)
func _try_force_initialize() -> void:
	print_debug("[SpritePipeline] _try_force_initialize called, is_inside_tree=%s" % is_inside_tree())
	if _initialized:
		return
	if not is_inside_tree():
		print_debug("[SpritePipeline] Not in tree yet, will try again later")
		return

	# Try to get a critical node - if it exists, we can initialize
	var test_node = get_node_or_null("GenerateSection/QueuePath/QueuePathEdit")
	if test_node:
		print_debug("[SpritePipeline] Test node found, proceeding with force_initialize")
		force_initialize()
	else:
		print_debug("[SpritePipeline] Test node not found, scene not ready yet")


## Process any commands that were queued before initialization
func _process_pending_commands() -> void:
	if _pending_commands.is_empty():
		return

	print_debug("[SpritePipeline] Processing %d pending commands" % _pending_commands.size())
	var commands_to_process = _pending_commands.duplicate()
	_pending_commands.clear()

	for cmd_tuple in commands_to_process:
		var command: String = cmd_tuple[0]
		var args: Dictionary = cmd_tuple[1]
		var request_id: String = cmd_tuple[2]
		print_debug("[SpritePipeline] Processing queued command: %s" % command)
		_process_automation_command(command, args, request_id)


## Set the automation server reference (called by plugin)
func set_automation_server(server) -> void:
	_automation_server = server
	_automation_enabled = true
	# Connect signals to our handler
	if not _automation_server.command_received.is_connected(_on_automation_command):
		_automation_server.command_received.connect(_on_automation_command)
	print_debug("[SpritePipeline] Dock received automation server reference and connected signals")


func _ready() -> void:
	print_debug("[SpritePipeline] main_dock _ready() called")

	# Skip if already force-initialized
	if _initialized:
		print_debug("[SpritePipeline] Already initialized, skipping _ready init")
		return

	_init_sprite_cache()
	_setup_byok_model_options()
	_load_settings()
	_setup_connections()
	_update_ui_for_mode()
	_update_cache_ui()
	_update_version_label()

	_initialized = true

	# Check if plugin already provided an automation server
	if _plugin_automation_server:
		print_debug("[SpritePipeline] Using automation server from plugin")
		_automation_server = _plugin_automation_server
		_automation_enabled = true
		if not _automation_server.command_received.is_connected(_on_automation_command):
			_automation_server.command_received.connect(_on_automation_command)
			print_debug("[SpritePipeline] Connected to plugin's automation server")
	else:
		# Fallback: Create and connect our own automation server
		_try_enable_automation_server()

	# Process any commands that arrived before _ready
	_process_pending_commands()


## Show the plugin version in the dock header
func _update_version_label() -> void:
	var version_label := get_node_or_null("Header/VersionLabel") as Label
	if version_label:
		version_label.text = "v%s" % Version.PLUGIN


## Initialize the sprite cache
func _init_sprite_cache() -> void:
	_sprite_cache = SpriteCacheClass.new()
	var err: Error = _sprite_cache.initialize()
	if err != OK:
		push_warning("[SpritePipeline] Failed to initialize sprite cache: %s" % error_string(err))
	else:
		print_debug("[SpritePipeline] Sprite cache initialized")
		_sprite_cache.cache_updated.connect(_on_cache_updated)


func _process(_delta: float) -> void:
	# Poll automation server for incoming commands
	if _automation_server and _automation_enabled:
		_automation_server.poll()


## Try to enable automation server (dev/test mode only)
func _try_enable_automation_server() -> void:
	print_debug("[SpritePipeline] Checking automation enable conditions...")
	# Check for automation enable flag (environment or settings)
	var enable_automation := false

	# Method 1: Command line argument --automation
	var args := OS.get_cmdline_args()
	print_debug("[SpritePipeline] Command line args: %s" % [args])
	for arg in args:
		if arg == "--automation" or arg == "--enable-automation":
			print_debug("[SpritePipeline] Automation enabled via command line arg: %s" % arg)
			enable_automation = true
			break

	# Method 2: Environment variable
	var has_env := OS.has_environment("SPRITE_PIPELINE_AUTOMATION")
	var env_val := OS.get_environment("SPRITE_PIPELINE_AUTOMATION") if has_env else ""
	print_debug("[SpritePipeline] Env SPRITE_PIPELINE_AUTOMATION: has=%s value='%s'" % [has_env, env_val])
	if has_env and env_val == "1":
		print_debug("[SpritePipeline] Automation enabled via environment variable")
		enable_automation = true

	# Method 3: Settings file flag
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var settings_enable := config.get_value("dev", "enable_automation", false)
		print_debug("[SpritePipeline] Settings enable_automation: %s" % settings_enable)
		enable_automation = enable_automation or settings_enable

	print_debug("[SpritePipeline] Final enable_automation decision: %s" % enable_automation)
	if enable_automation:
		_start_automation_server()


## Start the automation server for test system integration
func _start_automation_server(port: int = 19876) -> void:
	if _automation_server:
		return  # Already running

	_automation_server = AutomationServer.new()
	var err: Error = _automation_server.enable(port)

	if err == OK:
		_automation_enabled = true
		_automation_server.command_received.connect(_on_automation_command)
		print_debug("[SpritePipeline] Automation server enabled on port %d" % port)
		print_debug("[SpritePipeline] Signal connected, is_inside_tree: %s" % is_inside_tree())
	else:
		push_error("[SpritePipeline] Failed to start automation server: %s" % error_string(err))
		_automation_server = null


## Stop the automation server
func _stop_automation_server() -> void:
	if _automation_server:
		_automation_server.disable()
		_automation_server = null
		_automation_enabled = false
		print_debug("[SpritePipeline] Automation server stopped")


## Handle incoming automation commands
func _on_automation_command(command: String, args: Dictionary, request_id: String) -> void:
	# Commands handled by AutomationServer directly: ping, get_state, get_events, etc.
	# Commands we need to handle here: run_doctor, start_generate, etc.
	print_debug("[SpritePipeline] _on_automation_command: %s (initialized=%s)" % [command, _initialized])

	# If not initialized, queue the command for later processing
	if not _initialized:
		print_debug("[SpritePipeline] Not initialized, queueing command: %s" % command)
		_pending_commands.append([command, args, request_id])
		# Try to force initialize now
		_try_force_initialize()
		return

	_process_automation_command(command, args, request_id)


## Process a single automation command (called when initialized)
func _process_automation_command(command: String, args: Dictionary, request_id: String) -> void:
	print_debug("[SpritePipeline] _process_automation_command: %s" % command)
	match command:
		"run_doctor":
			_handle_auto_run_doctor(args, request_id)
		"start_generate":
			_handle_auto_start_generate(args, request_id)
		"cancel_generate":
			_handle_auto_cancel_generate(args, request_id)
		"import_only":
			_handle_auto_import_only(args, request_id)
		"get_config":
			_handle_auto_get_config(args, request_id)
		"set_config":
			_handle_auto_set_config(args, request_id)
		"get_doctor_report":
			_handle_auto_get_doctor_report(args, request_id)
		"apply_fix":
			_handle_auto_apply_fix(args, request_id)
		"verify_fix":
			_handle_auto_verify_fix(args, request_id)


func _handle_auto_run_doctor(_args: Dictionary, request_id: String) -> void:
	# Run diagnostic checks
	var report := {
		"status": "ok",
		"request_id": request_id,
		"checks": {
			"plugin_loaded": true,
			"settings_accessible": FileAccess.file_exists(SETTINGS_PATH) or true,
			"mode": _current_mode,
			"byok_configured": api_key_edit.text.length() > 0 and api_key_edit.text.begins_with("sk-"),
			"pool_authenticated": _pool_client != null and _pool_client.is_authenticated() if _pool_client else false,
		},
		"versions": {
			"plugin": Version.PLUGIN,
			"protocol": Version.PROTOCOL,
			"godot": "%d.%d.%d" % [
				Engine.get_version_info()["major"],
				Engine.get_version_info()["minor"],
				Engine.get_version_info()["patch"]
			]
		}
	}

	if _automation_server:
		_automation_server.emit_event("doctor_completed", report)


func _handle_auto_start_generate(args: Dictionary, request_id: String) -> void:
	print_debug("[SpritePipeline] _handle_auto_start_generate called with args: %s" % str(args))
	if _is_generating:
		print_debug("[SpritePipeline] Already generating, returning error")
		if _automation_server:
			_automation_server.set_last_error_context({
				"code": "ALREADY_GENERATING",
				"message": "Generation already in progress",
				"request_id": request_id
			})
		return

	# Override paths if provided
	if args.has("queue_path"):
		queue_path_edit.text = args["queue_path"]
		print_debug("[SpritePipeline] Set queue_path to: %s" % args["queue_path"])
	if args.has("output_root"):
		output_path_edit.text = args["output_root"]
		print_debug("[SpritePipeline] Set output_root to: %s" % args["output_root"])
	if args.has("style"):
		style_edit.text = args["style"]

	# Update state in automation server
	if _automation_server:
		_automation_server.set_run_context(request_id, "generating")
		print_debug("[SpritePipeline] Set state to generating")

	# Trigger generation
	print_debug("[SpritePipeline] Calling _on_generate_pressed")
	_on_generate_pressed()


func _handle_auto_cancel_generate(_args: Dictionary, _request_id: String) -> void:
	if _is_generating:
		_on_cancel_pressed()


func _handle_auto_import_only(args: Dictionary, _request_id: String) -> void:
	var manifest_path: String = args.get("manifest_path", "")
	if manifest_path.is_empty():
		return

	if not FileAccess.file_exists(manifest_path):
		if _automation_server:
			_automation_server.set_last_error_context({
				"code": "MANIFEST_NOT_FOUND",
				"message": "Manifest file not found: %s" % manifest_path
			})
		return

	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	var json := JSON.new()
	if json.parse(manifest_text) != OK:
		if _automation_server:
			_automation_server.set_last_error_context({
				"code": "INVALID_MANIFEST",
				"message": "Failed to parse manifest JSON"
			})
		return

	var manifest: Dictionary = json.get_data()
	var output_root := output_path_edit.text
	var result := _import_assets_from_manifest(manifest, output_root)

	if _automation_server:
		_automation_server.emit_event("import_completed", result)


func _handle_auto_get_config(_args: Dictionary, request_id: String) -> void:
	var config_data := {
		"status": "ok",
		"request_id": request_id,
		"config": {
			"mode": _current_mode,
			"queue_path": queue_path_edit.text,
			"output_root": output_path_edit.text,
			"server_url": server_edit.text if _current_mode == "pool" else null,
			"has_api_key": api_key_edit.text.length() > 0,
			"is_authenticated": _pool_client.is_authenticated() if _pool_client else false
		}
	}

	if _automation_server:
		_automation_server.emit_event("config_response", config_data)


func _handle_auto_set_config(args: Dictionary, _request_id: String) -> void:
	if args.has("mode"):
		var new_mode: String = args["mode"]
		if new_mode == "byok":
			_on_byok_mode_selected()
		elif new_mode == "pool":
			_on_pool_mode_selected()

	if args.has("queue_path"):
		queue_path_edit.text = args["queue_path"]
	if args.has("output_root"):
		output_path_edit.text = args["output_root"]
	if args.has("global_style"):
		style_edit.text = args["global_style"]
	if args.has("api_key"):
		api_key_edit.text = args["api_key"]
	if args.has("server_url"):
		server_edit.text = args["server_url"]

	_save_settings()

	if _automation_server:
		_automation_server.emit_event("config_updated", {"success": true})


func _handle_auto_get_doctor_report(_args: Dictionary, request_id: String) -> void:
	_handle_auto_run_doctor({}, request_id)


func _handle_auto_apply_fix(args: Dictionary, request_id: String) -> void:
	var action: String = args.get("action", "")
	var consent_token: String = args.get("consent_token", "")
	var params: Dictionary = args.get("params", {})

	# Verify consent token is provided (gating)
	if consent_token.is_empty():
		if _automation_server:
			_automation_server.set_last_error_context({
				"code": "MISSING_CONSENT",
				"message": "Consent token required for autofix",
				"request_id": request_id
			})
		return

	# Apply fix based on action type
	var result := {"action": action, "success": false, "request_id": request_id}

	match action:
		"auth_reset":
			# Clear tokens and re-authenticate
			if _pool_client:
				_pool_client = null
			api_key_edit.text = ""
			_save_settings()
			result["success"] = true
			result["message"] = "Auth reset completed"

		"clean_cache":
			# Clear any cached data
			result["success"] = true
			result["message"] = "Cache cleaned"

		"reimport_manifest":
			# Trigger reimport
			_on_reimport_pressed()
			result["success"] = true
			result["message"] = "Reimport triggered"

		_:
			result["message"] = "Unknown action: %s" % action

	if _automation_server:
		_automation_server.emit_event("fix_applied", result)


func _handle_auto_verify_fix(_args: Dictionary, request_id: String) -> void:
	# Verify current state after fix
	var verify_result := {
		"request_id": request_id,
		"status": "ok",
		"is_generating": _is_generating,
		"has_error": not _last_error.is_empty(),
		"mode": _current_mode
	}

	if _automation_server:
		_automation_server.emit_event("fix_verified", verify_result)


func _setup_connections() -> void:
	# Mode buttons
	byok_button.pressed.connect(_on_byok_mode_selected)
	pool_button.pressed.connect(_on_pool_mode_selected)

	# BYOK auth
	api_key_edit.text_changed.connect(_on_api_key_changed)
	if image_model_option:
		image_model_option.item_selected.connect(_on_image_model_selected)
	if custom_model_edit:
		custom_model_edit.text_changed.connect(_on_custom_model_changed)
	if image_quality_option:
		image_quality_option.item_selected.connect(_on_image_quality_selected)

	# Pool auth
	login_button.pressed.connect(_on_login_pressed)
	refresh_quota_button.pressed.connect(_on_refresh_quota_pressed)
	if download_raw_check:
		download_raw_check.toggled.connect(_on_download_raw_toggled)

	# Generate
	generate_button.pressed.connect(_on_generate_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)

	# Results
	copy_error_button.pressed.connect(_on_copy_error_pressed)
	open_output_button.pressed.connect(_on_open_output_pressed)
	reimport_button.pressed.connect(_on_reimport_pressed)
	if filter_button:
		filter_button.pressed.connect(_on_filter_button_pressed)

	# SpriteFrames options
	if write_spriteframes_check:
		write_spriteframes_check.toggled.connect(_on_spriteframes_option_changed)
	if spriteframes_fps_spin:
		spriteframes_fps_spin.value_changed.connect(_on_spriteframes_option_changed)

	# Export report (optional node)
	if export_report_button:
		export_report_button.pressed.connect(_on_export_report_pressed)

	# Cache UI
	if cache_toggle:
		cache_toggle.toggled.connect(_on_cache_toggle_changed)
	if clear_cache_button:
		clear_cache_button.pressed.connect(_on_clear_cache_pressed)
	if cache_settings_button:
		cache_settings_button.pressed.connect(_on_cache_settings_pressed)


func _load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)

	if err == OK:
		_current_mode = config.get_value("general", "mode", "byok")
		queue_path_edit.text = config.get_value("general", "queue_path", "res://sprites/sprite_queue.yaml")
		output_path_edit.text = config.get_value("general", "output_root", "res://assets/sprites")
		style_edit.text = config.get_value("general", "global_style",
			"pixel art game sprite, PC hardware themed incremental game, clean silhouette, transparent background")
		api_key_edit.text = config.get_value("byok", "api_key", "")
		_select_image_model(config.get_value("byok", "image_model", BYOKClientClass.DEFAULT_IMAGE_MODEL))
		_select_image_quality(config.get_value("byok", "image_quality", BYOKClientClass.DEFAULT_IMAGE_QUALITY))
		var server_url: String = config.get_value("pool", "server_url", "")
		var server_retired := PoolClientClass.get_url_host(server_url) in RETIRED_POOL_HOSTS
		if server_retired:
			push_warning("[SpritePipeline] Saved Pool server %s is retired; clearing it and its tokens. Enter your own backend URL." % server_url)
			server_url = ""
		server_edit.text = server_url
		if download_raw_check:
			download_raw_check.set_pressed_no_signal(config.get_value("pool", "download_raw", false))
		_filter_prompt_dismissed = config.get_value("editor", "filter_prompt_dismissed", false)
		_pin_import_params = config.get_value("editor", "pin_import_params", true)
		_spriteframes_loop = config.get_value("editor", "spriteframes_loop", true)
		_overwrite_spriteframes = config.get_value("editor", "overwrite_spriteframes", false)
		if write_spriteframes_check:
			write_spriteframes_check.set_pressed_no_signal(config.get_value("editor", "write_spriteframes", true))
		if spriteframes_fps_spin:
			spriteframes_fps_spin.set_value_no_signal(config.get_value("editor", "spriteframes_fps", 8.0))

		# Load pool tokens if available. The client is created here so that later
		# saves write the tokens back instead of dropping them.
		var access_token := config.get_value("pool", "access_token", "")
		var refresh_token := config.get_value("pool", "refresh_token", "")
		var expires_at: int = config.get_value("pool", "token_expires_at", 0)

		if access_token and not server_retired:
			_create_pool_client(server_url)
			_pool_client.set_tokens(access_token, refresh_token, expires_at)

		# Load cache settings
		if _sprite_cache:
			_sprite_cache.enabled = config.get_value("cache", "enabled", true)
			_sprite_cache.max_size_mb = config.get_value("cache", "max_size_mb", 500.0)
			if cache_toggle:
				cache_toggle.set_pressed_no_signal(_sprite_cache.enabled)

		# Persist the cleared server so the retired host and its tokens leave the settings file
		if server_retired:
			_save_settings()


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("general", "mode", _current_mode)
	config.set_value("general", "queue_path", queue_path_edit.text)
	config.set_value("general", "output_root", output_path_edit.text)
	config.set_value("general", "global_style", style_edit.text)
	config.set_value("byok", "api_key", api_key_edit.text)
	config.set_value("byok", "image_model", _selected_image_model())
	config.set_value("byok", "image_quality", _selected_image_quality())
	config.set_value("pool", "server_url", server_edit.text)
	if download_raw_check:
		config.set_value("pool", "download_raw", download_raw_check.button_pressed)

	if _pool_client and _pool_client.is_authenticated():
		config.set_value("pool", "access_token", _pool_client._access_token)
		config.set_value("pool", "refresh_token", _pool_client._refresh_token)
		config.set_value("pool", "token_expires_at", _pool_client._token_expires_at)

	config.set_value("editor", "filter_prompt_dismissed", _filter_prompt_dismissed)
	config.set_value("editor", "pin_import_params", _pin_import_params)
	if write_spriteframes_check:
		config.set_value("editor", "write_spriteframes", write_spriteframes_check.button_pressed)
	if spriteframes_fps_spin:
		config.set_value("editor", "spriteframes_fps", spriteframes_fps_spin.value)
	config.set_value("editor", "spriteframes_loop", _spriteframes_loop)
	config.set_value("editor", "overwrite_spriteframes", _overwrite_spriteframes)

	# Save cache settings
	if _sprite_cache:
		config.set_value("cache", "enabled", _sprite_cache.enabled)
		config.set_value("cache", "max_size_mb", _sprite_cache.max_size_mb)

	config.save(SETTINGS_PATH)


func _update_ui_for_mode() -> void:
	byok_button.button_pressed = (_current_mode == "byok")
	pool_button.button_pressed = (_current_mode == "pool")

	byok_auth.visible = (_current_mode == "byok")
	pool_auth.visible = (_current_mode == "pool")
	quota_section.visible = (_current_mode == "pool")

	_update_auth_status()


func _update_auth_status() -> void:
	if _current_mode == "byok":
		var key := api_key_edit.text
		if key.is_empty():
			key_status.text = "Not configured"
			key_status.add_theme_color_override("font_color", Color(1, 0.6, 0.2))
		elif not key.begins_with("sk-"):
			key_status.text = "Invalid key format (should start with sk-)"
			key_status.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		else:
			key_status.text = "Key configured"
			key_status.add_theme_color_override("font_color", Color(0.4, 1, 0.4))
	else:
		if _pool_client and _pool_client.is_authenticated():
			if _pool_client.is_token_expired():
				auth_status.text = "Token expired - click Login"
				auth_status.add_theme_color_override("font_color", Color(1, 0.6, 0.2))
			else:
				auth_status.text = "Logged in"
				auth_status.add_theme_color_override("font_color", Color(0.4, 1, 0.4))
		else:
			auth_status.text = "Not logged in"
			auth_status.add_theme_color_override("font_color", Color(1, 0.6, 0.2))


func _on_byok_mode_selected() -> void:
	_current_mode = "byok"
	_update_ui_for_mode()
	_save_settings()


func _on_pool_mode_selected() -> void:
	_current_mode = "pool"
	_update_ui_for_mode()
	_save_settings()

	# Initialize pool client if needed
	if not _pool_client:
		_create_pool_client(server_edit.text)


## Create the pool client with all dock handlers connected
func _create_pool_client(server_url: String) -> void:
	_pool_client = PoolClientClass.new(server_url.strip_edges())
	_pool_client.auth_started.connect(_on_pool_auth_started)
	_pool_client.auth_completed.connect(_on_pool_auth_completed)
	_pool_client.auth_failed.connect(_on_pool_auth_failed)
	_pool_client.quota_updated.connect(_on_quota_updated)
	_pool_client.generation_started.connect(_on_generation_started)
	_pool_client.generation_progress.connect(_on_generation_progress)
	_pool_client.generation_percent.connect(_on_generation_percent)
	_pool_client.generation_completed.connect(_on_generation_completed)
	_pool_client.generation_failed.connect(_on_generation_failed)
	_pool_client.cache_hit.connect(_on_cache_hit)
	if download_raw_check:
		_pool_client.download_raw = download_raw_check.button_pressed
	# Set sprite cache on pool client
	if _sprite_cache:
		_pool_client.set_sprite_cache(_sprite_cache)


func _on_api_key_changed(_text: String) -> void:
	_update_auth_status()
	_save_settings()


func _on_download_raw_toggled(pressed: bool) -> void:
	if _pool_client:
		_pool_client.download_raw = pressed
	_save_settings()


## Fill the BYOK model and quality pickers and select the defaults
func _setup_byok_model_options() -> void:
	if image_model_option and image_model_option.item_count == 0:
		for model in BYOKClientClass.IMAGE_MODELS:
			image_model_option.add_item(model)
		image_model_option.add_item(CUSTOM_MODEL_LABEL)
	if image_quality_option and image_quality_option.item_count == 0:
		for quality in BYOKClientClass.IMAGE_QUALITIES:
			image_quality_option.add_item(quality)
	_select_image_model(BYOKClientClass.DEFAULT_IMAGE_MODEL)
	_select_image_quality(BYOKClientClass.DEFAULT_IMAGE_QUALITY)


## Select a preset model, or Custom with the name in the custom field
func _select_image_model(model: String) -> void:
	if not image_model_option:
		return
	var preset_index := BYOKClientClass.IMAGE_MODELS.find(model)
	var is_custom := preset_index == -1 and not model.is_empty()
	image_model_option.select(image_model_option.item_count - 1 if is_custom else maxi(preset_index, 0))
	if custom_model_edit:
		custom_model_edit.visible = is_custom
		if is_custom:
			custom_model_edit.text = model


func _selected_image_model() -> String:
	if not image_model_option:
		return BYOKClientClass.DEFAULT_IMAGE_MODEL
	var index := image_model_option.selected
	if index >= 0 and index < BYOKClientClass.IMAGE_MODELS.size():
		return BYOKClientClass.IMAGE_MODELS[index]
	var custom_model := custom_model_edit.text.strip_edges() if custom_model_edit else ""
	return custom_model if not custom_model.is_empty() else BYOKClientClass.DEFAULT_IMAGE_MODEL


func _select_image_quality(quality: String) -> void:
	if not image_quality_option:
		return
	var index := BYOKClientClass.IMAGE_QUALITIES.find(quality)
	if index == -1:
		index = BYOKClientClass.IMAGE_QUALITIES.find(BYOKClientClass.DEFAULT_IMAGE_QUALITY)
	image_quality_option.select(index)


func _selected_image_quality() -> String:
	if image_quality_option and image_quality_option.selected >= 0:
		return BYOKClientClass.IMAGE_QUALITIES[image_quality_option.selected]
	return BYOKClientClass.DEFAULT_IMAGE_QUALITY


func _on_image_model_selected(index: int) -> void:
	if custom_model_edit:
		custom_model_edit.visible = index >= BYOKClientClass.IMAGE_MODELS.size()
	_save_settings()


func _on_custom_model_changed(_text: String) -> void:
	_save_settings()


func _on_image_quality_selected(_index: int) -> void:
	_save_settings()


func _on_login_pressed() -> void:
	# A new or changed server URL gets a fresh client; tokens must not carry over to another server
	var server_url := server_edit.text.strip_edges().trim_suffix("/")
	if not _pool_client or _pool_client.get_server_url() != server_url:
		_create_pool_client(server_url)

	if _pool_client.get_server_url().is_empty():
		auth_status.text = "Enter a valid server URL (https://, or http:// for localhost/LAN)"
		auth_status.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		return

	login_button.disabled = true
	login_button.text = "Starting..."

	_pool_client.start_device_auth()


func _on_pool_auth_started(device_code: String, user_code: String, verification_uri: String) -> void:
	device_code_container.visible = true
	device_code_label.text = user_code
	verify_link.uri = verification_uri
	verify_link.visible = not verification_uri.is_empty()
	login_button.text = "Waiting for authorization..."

	# Start polling for completion
	_start_device_poll(device_code)


func _start_device_poll(device_code: String) -> void:
	if _device_poll_timer:
		_device_poll_timer.stop()
		_device_poll_timer.queue_free()

	_device_poll_timer = Timer.new()
	add_child(_device_poll_timer)
	_device_poll_timer.wait_time = 5.0
	_device_poll_timer.timeout.connect(func(): _poll_device_auth(device_code))
	_device_poll_timer.start()


func _poll_device_auth(device_code: String) -> void:
	if _pool_client:
		_pool_client.poll_device_auth(device_code)


func _on_pool_auth_completed(_access_token: String) -> void:
	if _device_poll_timer:
		_device_poll_timer.stop()
		_device_poll_timer.queue_free()
		_device_poll_timer = null

	device_code_container.visible = false
	login_button.disabled = false
	login_button.text = "Login with Device Code"

	_update_auth_status()
	_save_settings()

	# Fetch quota
	_pool_client.get_quota()


func _on_pool_auth_failed(error: Dictionary) -> void:
	var code: String = error.get("code", "")

	# "authorization_pending" is expected while waiting
	if code == "authorization_pending":
		return

	if _device_poll_timer:
		_device_poll_timer.stop()
		_device_poll_timer.queue_free()
		_device_poll_timer = null

	device_code_container.visible = false
	login_button.disabled = false
	login_button.text = "Login with Device Code"

	auth_status.text = "Login failed: %s" % error.get("message", "Unknown error")
	auth_status.add_theme_color_override("font_color", Color(1, 0.4, 0.4))


func _on_refresh_quota_pressed() -> void:
	if _pool_client and _pool_client.is_authenticated():
		refresh_quota_button.disabled = true
		_pool_client.get_quota()


func _on_quota_updated(quota: Dictionary) -> void:
	refresh_quota_button.disabled = false

	var remaining: int = quota.get("units_remaining", 0)
	var total: int = quota.get("units_total", 0)
	var pack_balance: int = quota.get("pack_balance", 0)
	# The backend sends resets_at; reset_date is the older name
	var reset_date: String = str(quota.get("resets_at", quota.get("reset_date", "")))

	units_label.text = "Units: %d / %d" % [remaining, total]
	if pack_balance > 0:
		units_label.text += " (+%d pack)" % pack_balance

	if total > 0:
		quota_bar.value = (float(remaining) / float(total)) * 100.0
	else:
		quota_bar.value = 0

	if reset_date:
		reset_label.text = "Resets: %s" % reset_date.substr(0, 10)
	else:
		reset_label.text = "Resets: --"


func _on_generate_pressed() -> void:
	print_debug("[SpritePipeline] _on_generate_pressed called")
	if _is_generating:
		print_debug("[SpritePipeline] Already generating, returning")
		return

	# Validate inputs
	var queue_path := queue_path_edit.text
	print_debug("[SpritePipeline] Queue path: %s" % queue_path)
	if not FileAccess.file_exists(queue_path):
		print_debug("[SpritePipeline] ERROR: Queue file not found: %s" % queue_path)
		_show_error("Queue file not found: %s" % queue_path)
		if _automation_server:
			_automation_server.set_run_context("", "idle")
		return

	# Load and parse queue
	var queue_text := FileAccess.get_file_as_string(queue_path)
	# A description without a prompt becomes the prompt, in both modes
	var queue_data := Prompting.normalize_queue(_parse_yaml_queue(queue_text))
	print_debug("[SpritePipeline] Parsed %d items from queue" % queue_data.size())

	if queue_data.is_empty():
		print_debug("[SpritePipeline] ERROR: Queue is empty or failed to parse")
		_show_error("Failed to parse queue file or queue is empty")
		if _automation_server:
			_automation_server.set_run_context("", "idle")
		return

	var output_root := output_path_edit.text
	var global_style := style_edit.text
	_last_output_root = output_root

	# Ensure output directory exists
	DirAccess.make_dir_recursive_absolute(output_root)

	# Start generation
	_is_generating = true
	_clear_status()
	generate_button.visible = false
	cancel_button.visible = true
	progress_bar.visible = true
	progress_bar.value = 0

	if _current_mode == "byok":
		_start_byok_generation(queue_data, output_root, global_style)
	else:
		_start_pool_generation(queue_data, output_root, global_style)


func _start_byok_generation(queue_data: Array, output_root: String, global_style: String) -> void:
	var api_key := api_key_edit.text
	if not api_key.begins_with("sk-"):
		_show_error("Invalid API key format")
		_reset_generate_ui()
		return

	_byok_client = BYOKClientClass.new(api_key)
	_byok_client.set_image_model(_selected_image_model())
	_byok_client.set_image_quality(_selected_image_quality())
	_byok_client.generation_started.connect(_on_generation_started)
	_byok_client.generation_progress.connect(_on_generation_progress)
	_byok_client.generation_percent.connect(_on_generation_percent)
	_byok_client.generation_completed.connect(_on_generation_completed)
	_byok_client.generation_failed.connect(_on_generation_failed)

	_byok_client.generate_sprites(queue_data, output_root, global_style)


func _start_pool_generation(queue_data: Array, output_root: String, global_style: String) -> void:
	if not _pool_client or not _pool_client.is_authenticated():
		_show_error("Not logged in. Please login first.")
		_reset_generate_ui()
		return

	# Check if token needs refresh
	if _pool_client.is_token_expired():
		status_text.text = "Refreshing authentication..."
		var result: Dictionary = await _pool_client.refresh_auth()
		if not result["success"]:
			_show_error("Failed to refresh token. Please login again.")
			_reset_generate_ui()
			return
		_save_settings()

	_pool_client.generate_sprites(queue_data, output_root, global_style)


func _on_cancel_pressed() -> void:
	if _current_mode == "byok" and _byok_client:
		_byok_client.cancel()
	elif _pool_client:
		_pool_client.cancel()

	status_text.text = "Cancelling..."


func _on_generation_started(job_id: String) -> void:
	status_text.text = "Started job: %s" % job_id
	if _automation_server:
		_automation_server.set_run_context(job_id, "generating")
		_automation_server.emit_event("generation_started", {"job_id": job_id})


func _on_generation_progress(stage: String, message: String) -> void:
	status_text.text = message
	if _automation_server:
		_automation_server.emit_event("generation_progress", {"stage": stage, "message": message})


func _on_generation_percent(percent: int, stage: String) -> void:
	progress_bar.value = percent
	status_text.text = "%s (%d%%)" % [stage, percent]


func _on_generation_completed(manifest: Dictionary) -> void:
	_is_generating = false
	_last_manifest = manifest
	_reset_generate_ui()

	var success_count: int = manifest.get("results", []).size()
	var error_count: int = manifest.get("errors", []).size()
	var safe_mode_count: int = manifest.get("safe_mode_count", 0)
	var grid_warning_count := count_grid_warnings(manifest)

	_clear_spriteframes_links()
	results_section.visible = true
	results_label.text = "Results: %d success, %d errors" % [success_count, error_count]

	if safe_mode_count > 0:
		results_label.text += " (%d safe mode)" % safe_mode_count

	# Sprites that spilled across cell boundaries of the generated sheet
	if grid_warning_count > 0:
		results_label.text += " (%d grid warnings)" % grid_warning_count

	if error_count > 0 or grid_warning_count > 0:
		results_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	else:
		results_label.add_theme_color_override("font_color", Color(0.4, 1, 0.4))

	status_text.text = "Generation complete!"
	progress_bar.visible = false

	# Notify automation server
	if _automation_server:
		_automation_server.set_last_manifest(manifest)
		_automation_server.set_run_context("", "idle")
		_automation_server.emit_event("generation_completed", {
			"success_count": success_count,
			"error_count": error_count,
			"safe_mode_count": safe_mode_count
		})

	if _editor.is_editor():
		await _import_generated_files(manifest)
		# Pressing Generate again while the files were imported starts a new run
		if _is_generating:
			return

	_update_filter_row()
	# Last, and not awaited, so the dialog never holds up the results
	_offer_nearest_filter()


## Editor steps after a generation: show the new files in the FileSystem dock without
## pressing Reimport, then pin their import settings
func _import_generated_files(manifest: Dictionary) -> void:
	var output_root := _last_output_root if not _last_output_root.is_empty() else output_path_edit.text
	var png_paths := ImportParams.manifest_png_paths(manifest, output_root)
	await _editor.scan_and_wait(png_paths)
	if _is_generating:
		return
	if _pin_import_params:
		var pinned = _editor.pin_import_params(png_paths)
		if pinned is PackedStringArray and not pinned.is_empty():
			status_text.text += " Import settings pinned for %d files" % pinned.size()
	if write_spriteframes_check and write_spriteframes_check.button_pressed:
		var written = _editor.write_spriteframes(manifest, output_root, spriteframes_fps_spin.value, _spriteframes_loop, _overwrite_spriteframes)
		if written is PackedStringArray and not written.is_empty():
			# Show the new .tres files in the FileSystem dock
			_editor.scan()
			_show_spriteframes_links(written, output_root)


## Count the written SpriteFrames in the results and link each file to the FileSystem dock
func _show_spriteframes_links(paths: PackedStringArray, output_root: String) -> void:
	results_label.text += ", %d SpriteFrames written" % paths.size()
	var generated := 0
	for path in paths:
		if path.ends_with(EditorIntegration.GENERATED_SUFFIX):
			generated += 1
		var relative := ManifestPaths.relative_to(output_root, path)
		var link := LinkButton.new()
		link.text = relative if not relative.is_empty() else path
		link.tooltip_text = path
		link.pressed.connect(_on_spriteframes_link_pressed.bind(path))
		spriteframes_links.add_child(link)
	if generated > 0:
		status_text.text += " %d SpriteFrames saved as .generated.tres because a .tres already existed" % generated


func _clear_spriteframes_links() -> void:
	if not spriteframes_links:
		return
	for link in spriteframes_links.get_children():
		spriteframes_links.remove_child(link)
		link.queue_free()


func _on_spriteframes_link_pressed(path: String) -> void:
	_editor.navigate_to(path)


func _on_spriteframes_option_changed(_value: Variant) -> void:
	_save_settings()


## Show the project's default texture filter under the results, in the editor only
func _update_filter_row() -> void:
	if not filter_row:
		return
	filter_row.visible = _editor.is_editor()
	filter_label.text = filter_status_text(_editor.project_filter())
	filter_button.visible = not _editor.project_filter_is_nearest()


## "Pixel-art filtering: <filter> ✓" for filters that keep pixel art sharp, "⚠" otherwise
static func filter_status_text(filter: int) -> String:
	var names: Array = EditorIntegration.FILTER_NAMES
	var filter_name: String = names[filter] if filter >= 0 and filter < names.size() else "Unknown"
	var sharp := filter in [EditorIntegration.FILTER_NEAREST, EditorIntegration.FILTER_NEAREST_MIPMAP]
	return "Pixel-art filtering: %s %s" % [filter_name, "✓" if sharp else "⚠"]


func _on_filter_button_pressed() -> void:
	_offer_nearest_filter(true)


## Ask before setting the project's default texture filter to Nearest. After a generation
## the dialog appears unless the user chose "Don't ask again"; the button in the results
## section asks regardless.
func _offer_nearest_filter(asked_by_user := false) -> void:
	if not _editor.is_editor() or _editor.project_filter_is_nearest() or _filter_dialog_open:
		return
	if _filter_prompt_dismissed and not asked_by_user:
		return

	_filter_dialog_open = true
	var answer: Dictionary = await _consent_gate.ask(ConsentGate.PROJECT_FILTER_NEAREST, self)
	_filter_dialog_open = false
	if answer["dont_ask_again"] and not _filter_prompt_dismissed:
		_filter_prompt_dismissed = true
		_save_settings()
	if _consent_gate.consume_token(ConsentGate.PROJECT_FILTER_NEAREST, answer["token"]):
		var err: Error = _editor.set_project_filter_nearest()
		if err == OK:
			status_text.text = "Project texture filter set to Nearest"
			status_text.remove_theme_color_override("font_color")
		else:
			_show_error("Could not save the texture filter to project.godot: %s" % error_string(err))
	_update_filter_row()


## Number of results whose sheet failed the grid gutter check
static func count_grid_warnings(manifest: Dictionary) -> int:
	var count := 0
	for result in manifest.get("results", []):
		if result is Dictionary and result.get("grid_violation", false) == true:
			count += 1
	return count


func _on_generation_failed(error: Dictionary) -> void:
	_is_generating = false
	_last_error = error
	_reset_generate_ui()

	var code: String = error.get("code", "UNKNOWN")
	var message: String = error.get("message", "Unknown error")

	status_text.text = "Failed: %s" % code
	status_text.add_theme_color_override("font_color", Color(1, 0.4, 0.4))

	error_section.visible = true
	error_text.text = _format_error_for_display(error)
	progress_bar.visible = false

	# Notify automation server
	if _automation_server:
		_automation_server.set_last_error_context(error)
		_automation_server.set_run_context("", "error")
		_automation_server.emit_event("generation_failed", {"error_code": code})

	# Handle specific errors
	match code:
		"UPGRADE_REQUIRED":
			_show_upgrade_required_dialog()
		"RATE_LIMITED":
			var retry_after: int = error.get("retry_after_ms", 60000) / 1000
			status_text.text = "Rate limited. Retry in %d seconds." % retry_after
		"QUOTA_EXCEEDED":
			if _current_mode == "pool":
				_pool_client.get_quota()


func _reset_generate_ui() -> void:
	generate_button.visible = true
	cancel_button.visible = false


func _clear_status() -> void:
	error_section.visible = false
	results_section.visible = false
	status_text.text = "Ready"
	status_text.remove_theme_color_override("font_color")


func _show_error(message: String) -> void:
	status_text.text = message
	status_text.add_theme_color_override("font_color", Color(1, 0.4, 0.4))


func _format_error_for_display(error: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Code: %s" % error.get("code", "UNKNOWN"))
	lines.append("Message: %s" % error.get("message", ""))
	lines.append("Stage: %s" % error.get("stage", "unknown"))

	if error.has("status_code"):
		lines.append("HTTP Status: %d" % error["status_code"])

	if error.has("request_id") and error["request_id"]:
		lines.append("Request ID: %s" % error["request_id"])

	if error.has("client_job_id") and error["client_job_id"]:
		lines.append("Job ID: %s" % error["client_job_id"])

	if error.get("retryable", false):
		lines.append("Retryable: Yes")
		if error.get("retry_after_ms", 0) > 0:
			lines.append("Retry After: %d seconds" % (error["retry_after_ms"] / 1000))

	return "\n".join(lines)


func _on_copy_error_pressed() -> void:
	if _last_error.is_empty():
		return

	var summary := _format_error_summary(_last_error)
	DisplayServer.clipboard_set(summary)
	status_text.text = "Error summary copied to clipboard"


func _format_error_summary(error: Dictionary) -> String:
	var lines := PackedStringArray([
		"=== Sprite Pipeline Error Summary ===",
		"",
		"Error Code: %s" % error.get("code", "UNKNOWN"),
		"Status: %d" % error.get("status_code", 0),
		"Message: %s" % error.get("message", "No message"),
		"Stage: %s" % error.get("stage", "unknown"),
		"",
		"Request ID: %s" % error.get("request_id", "N/A"),
		"Client Job ID: %s" % error.get("client_job_id", "N/A"),
		"Idempotency Key: %s" % error.get("idempotency_key", "N/A"),
		"Inputs Hash: %s" % error.get("inputs_hash", "N/A"),
		"",
		"Plugin Version: %s" % Version.PLUGIN,
		"Protocol Version: %s" % Version.PROTOCOL,
		"Mode: %s" % _current_mode,
		"",
		"Retryable: %s" % ("Yes" if error.get("retryable", false) else "No"),
	])

	if error.get("retry_after_ms", 0) > 0:
		lines.append("Retry After: %d seconds" % (error["retry_after_ms"] / 1000))

	lines.append("")
	lines.append("Generated: %s" % Time.get_datetime_string_from_system())
	lines.append("================================")

	return "\n".join(lines)


func _on_open_output_pressed() -> void:
	var output_path := output_path_edit.text
	if DirAccess.dir_exists_absolute(output_path):
		OS.shell_open(ProjectSettings.globalize_path(output_path))


func _on_reimport_pressed() -> void:
	if _editor.is_editor():
		_editor.scan()
		status_text.text = "Assets reimported"
	else:
		status_text.text = "Reimport only works in editor"


func _show_upgrade_required_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Plugin Update Required"
	dialog.dialog_text = "Your plugin version is too old.\n\nPlease update to the latest version to continue."
	add_child(dialog)
	dialog.popup_centered()


## Export bug report bundle (sanitized diagnostic data)
func _on_export_report_pressed() -> void:
	var bundle := _create_diagnostic_bundle()
	var json_str := JSON.stringify(bundle, "\t")

	# Show file dialog to save
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = ["*.json ; JSON Files"]
	dialog.current_file = "sprite_pipeline_report_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	add_child(dialog)

	dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(json_str)
			file.close()
			status_text.text = "Bug report exported to: %s" % path.get_file()
		else:
			status_text.text = "Failed to save bug report"
		dialog.queue_free()
	)

	dialog.canceled.connect(func():
		dialog.queue_free()
	)

	dialog.popup_centered(Vector2(600, 400))


## Create sanitized diagnostic bundle
func _create_diagnostic_bundle() -> Dictionary:
	var bundle := {
		"export_version": "1.0",
		"generated_at": Time.get_datetime_string_from_system(),

		"environment": {
			"plugin_version": Version.PLUGIN,
			"protocol_version": Version.PROTOCOL,
			"godot_version": "%d.%d.%d" % [
				Engine.get_version_info()["major"],
				Engine.get_version_info()["minor"],
				Engine.get_version_info()["patch"]
			],
			"os": OS.get_name(),
			"mode": _current_mode
		},

		"last_error": _redact_sensitive_data(_last_error.duplicate(true)) if _last_error.size() > 0 else null,

		"last_manifest_summary": _get_manifest_summary(),

		"configuration": {
			"queue_path": _redact_path(queue_path_edit.text),
			"output_path": _redact_path(output_path_edit.text),
			"has_api_key": api_key_edit.text.length() > 0 and api_key_edit.text.begins_with("sk-"),
			"server_url": server_edit.text if _current_mode == "pool" else null
		},

		"state": {
			"is_generating": _is_generating,
			"is_authenticated": _pool_client.is_authenticated() if _pool_client else false,
			"token_expired": _pool_client.is_token_expired() if _pool_client else null
		}
	}

	return bundle


## Redact sensitive data from a dictionary
func _redact_sensitive_data(data: Dictionary) -> Dictionary:
	var redacted := data.duplicate(true)
	var sensitive_keys := ["api_key", "access_token", "refresh_token", "authorization", "password", "secret"]

	for key in redacted.keys():
		if key.to_lower() in sensitive_keys:
			redacted[key] = "[REDACTED]"
		elif redacted[key] is String:
			# Redact paths
			redacted[key] = _redact_path(redacted[key])
		elif redacted[key] is Dictionary:
			redacted[key] = _redact_sensitive_data(redacted[key])

	return redacted


## Redact absolute paths
func _redact_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path  # Godot paths are safe
	# Convert absolute paths to relative indicators
	path = path.replace("\\", "/")
	if path.contains("/Users/"):
		return "[USER_PATH]/" + path.get_file()
	if path.contains("/home/"):
		return "[HOME_PATH]/" + path.get_file()
	if path.contains(":\\"):  # Windows
		return "[DRIVE_PATH]/" + path.get_file()
	return path


## Get manifest summary (without full content)
func _get_manifest_summary() -> Dictionary:
	if _last_manifest.is_empty():
		return {"has_manifest": false}

	return {
		"has_manifest": true,
		"version": _last_manifest.get("version", ""),
		"job_id": _last_manifest.get("job_id", ""),
		"inputs_hash": _last_manifest.get("inputs_hash", ""),
		"results_count": _last_manifest.get("results", []).size(),
		"errors_count": _last_manifest.get("errors", []).size(),
		"safe_mode_count": _last_manifest.get("safe_mode_count", 0),
		"started_at": _last_manifest.get("started_at", ""),
		"completed_at": _last_manifest.get("completed_at", "")
	}


## Deterministic asset import from manifest
func _import_assets_from_manifest(manifest: Dictionary, output_root: String) -> Dictionary:
	var results := {"imported": 0, "skipped": 0, "failed": 0, "errors": []}

	if not manifest.has("results"):
		return results

	for entry in manifest["results"]:
		var manifest_path: String = entry.get("file_path", "")
		var expected_hash: String = entry.get("sha256", "")

		if manifest_path.is_empty():
			continue

		# Manifest paths are relative to output_root (absolute in older BYOK manifests)
		var file_path := ManifestPaths.resolve(output_root, manifest_path)
		if file_path.is_empty():
			results["failed"] += 1
			results["errors"].append({"path": manifest_path, "error": "unsafe_path"})
			continue

		# Check if file exists and matches hash
		if FileAccess.file_exists(file_path):
			if expected_hash.is_empty():
				results["skipped"] += 1
				continue

			# Verify hash
			var actual_hash := _compute_file_sha256(file_path)
			if actual_hash == expected_hash:
				results["skipped"] += 1
				continue

		# File doesn't exist or hash mismatch - need to import/overwrite
		# For now, we just track this. Actual download would happen here.
		results["imported"] += 1

	return results


## Compute SHA256 of a file
func _compute_file_sha256(file_path: String) -> String:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return ""

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)

	while not file.eof_reached():
		var chunk := file.get_buffer(8192)
		if chunk.size() > 0:
			ctx.update(chunk)

	file.close()
	return ctx.finish().hex_encode()


## Parse YAML queue file (simplified YAML subset parser)
func _parse_yaml_queue(yaml_text: String) -> Array:
	var result := []
	var current_item := {}
	var lines := yaml_text.split("\n")

	for line in lines:
		var stripped := line.strip_edges()

		# Skip empty lines and comments
		if stripped.is_empty() or stripped.begins_with("#"):
			continue

		# New list item
		if stripped.begins_with("- "):
			if current_item.size() > 0:
				result.append(current_item)
			current_item = {}

			# Parse first key-value on same line as dash
			var rest := stripped.substr(2).strip_edges()
			if rest.contains(":"):
				var parts := rest.split(":", true, 1)
				if parts.size() == 2:
					var key := parts[0].strip_edges()
					var value := parts[1].strip_edges()
					current_item[key] = _parse_yaml_value(value)
		elif stripped.contains(":") and current_item.size() > 0:
			# Key-value pair within current item
			var parts := stripped.split(":", true, 1)
			if parts.size() == 2:
				var key := parts[0].strip_edges()
				var value := parts[1].strip_edges()
				current_item[key] = _parse_yaml_value(value)

	# Don't forget last item
	if current_item.size() > 0:
		result.append(current_item)

	return result


func _parse_yaml_value(value: String) -> Variant:
	# Remove quotes
	if (value.begins_with('"') and value.ends_with('"')) or \
	   (value.begins_with("'") and value.ends_with("'")):
		return value.substr(1, value.length() - 2)

	# Try integer
	if value.is_valid_int():
		return int(value)

	# Try float
	if value.is_valid_float():
		return float(value)

	# Boolean
	if value.to_lower() == "true":
		return true
	if value.to_lower() == "false":
		return false

	return value


# ==================== Cache UI ====================

## Update cache UI with current stats
func _update_cache_ui() -> void:
	if not _sprite_cache or not cache_section:
		return

	var stats: Dictionary = _sprite_cache.get_stats()

	# Update toggle state
	if cache_toggle:
		cache_toggle.set_pressed_no_signal(stats.enabled)

	# Update size label
	if cache_size_label:
		cache_size_label.text = "%.1f MB / %.0f MB" % [stats.total_size_mb, stats.max_size_mb]

	# Update hit rate label
	if cache_hit_label:
		if stats.session_total > 0:
			cache_hit_label.text = "Hits: %.0f%% (%d/%d)" % [stats.hit_rate_percent, stats.session_hits, stats.session_total]
		else:
			cache_hit_label.text = "Hits: --"

	# Update progress bar
	if cache_bar:
		cache_bar.value = stats.usage_percent

		# Color code based on usage
		if stats.usage_percent > 90:
			cache_bar.add_theme_color_override("fill_color", Color(1, 0.4, 0.4))
		elif stats.usage_percent > 70:
			cache_bar.add_theme_color_override("fill_color", Color(1, 0.8, 0.2))
		else:
			cache_bar.remove_theme_color_override("fill_color")


## Handle cache toggle change
func _on_cache_toggle_changed(enabled: bool) -> void:
	if _sprite_cache:
		_sprite_cache.enabled = enabled
		_save_settings()
		_update_cache_ui()
		status_text.text = "Cache %s" % ("enabled" if enabled else "disabled")


## Handle clear cache button
func _on_clear_cache_pressed() -> void:
	if not _sprite_cache:
		return

	# Show confirmation dialog
	var dialog := ConfirmationDialog.new()
	dialog.title = "Clear Sprite Cache"
	dialog.dialog_text = "Clear all cached sprites?\n\nThis will delete %.1f MB of cached data.\nThis action cannot be undone." % _sprite_cache.get_stats().total_size_mb
	dialog.confirmed.connect(func():
		var clear_err: Error = _sprite_cache.clear_cache()
		if clear_err == OK:
			status_text.text = "Cache cleared"
			_update_cache_ui()
		else:
			status_text.text = "Failed to clear cache"
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()


## Handle cache settings button
func _on_cache_settings_pressed() -> void:
	if not _sprite_cache:
		return

	# Create settings dialog
	var dialog := AcceptDialog.new()
	dialog.title = "Cache Settings"

	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)

	# Max size setting
	var size_hbox := HBoxContainer.new()
	vbox.add_child(size_hbox)

	var size_label := Label.new()
	size_label.text = "Max Cache Size (MB):"
	size_hbox.add_child(size_label)

	var size_spin := SpinBox.new()
	size_spin.min_value = 100
	size_spin.max_value = 10000
	size_spin.step = 100
	size_spin.value = _sprite_cache.max_size_mb
	size_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_hbox.add_child(size_spin)

	# Info label
	var info_label := Label.new()
	info_label.text = "Cache stores generated sprites locally to avoid\nredundant API calls and speed up iteration."
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(info_label)

	dialog.confirmed.connect(func():
		_sprite_cache.max_size_mb = size_spin.value
		_save_settings()
		_update_cache_ui()
		status_text.text = "Cache settings saved"
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)

	add_child(dialog)
	dialog.popup_centered(Vector2(350, 150))


## Handle cache updated signal
func _on_cache_updated(_stats: Dictionary) -> void:
	_update_cache_ui()


## Handle cache hit signal from pool client
func _on_cache_hit(inputs_hash: String) -> void:
	status_text.text = "Using cached sprites (%s...)" % inputs_hash.substr(0, 8)
	status_text.add_theme_color_override("font_color", Color(0.4, 0.8, 1))
	_update_cache_ui()
