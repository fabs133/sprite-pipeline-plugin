@tool
extends EditorPlugin
## Sprite Pipeline Editor Plugin
##
## AI-powered sprite generation for Godot 4.
## Supports two modes:
##   - BYOK (Bring Your Own Key): Direct OpenAI API calls
##   - Pool: Shared credits via backend server

const PLUGIN_VERSION := "0.1.0"
const PROTOCOL_VERSION := "1"

# Automation server for test system integration - owned by plugin for reliable lifecycle
const AutomationServerScript := preload("res://addons/sprite_pipeline/api/automation_server.gd")

var dock: Control
var _settings_path := "user://sprite_pipeline_settings.cfg"
var _automation_server = null


func _enter_tree() -> void:
	print_debug("[SpritePipeline] Plugin _enter_tree() starting...")

	# Load the main dock scene
	var dock_scene := preload("res://addons/sprite_pipeline/ui/main_dock.tscn")
	print_debug("[SpritePipeline] dock_scene loaded: %s" % dock_scene)
	dock = dock_scene.instantiate()
	print_debug("[SpritePipeline] dock instantiated: %s" % dock)

	# Add dock to the editor
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	print_debug("[SpritePipeline] dock added to editor")

	# Initialize settings
	_load_settings()

	# Start automation server from plugin (reliable lifecycle)
	_try_enable_automation_server()

	# Connect automation server to dock's handler immediately
	# The dock will queue commands if not yet initialized
	if _automation_server and dock:
		print_debug("[SpritePipeline] Setting up dock automation connection...")
		dock._automation_server = _automation_server
		dock._automation_enabled = true
		# Connect signal - dock._on_automation_command will handle queuing if needed
		_automation_server.command_received.connect(dock._on_automation_command)
		print_debug("[SpritePipeline] Signal connected to dock._on_automation_command")

	print_debug("[SpritePipeline] Plugin loaded v%s (protocol %s)" % [PLUGIN_VERSION, PROTOCOL_VERSION])


func _exit_tree() -> void:
	_stop_automation_server()

	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()

	print_debug("[SpritePipeline] Plugin unloaded")


func _process(_delta: float) -> void:
	# Poll automation server for incoming commands
	if _automation_server:
		_automation_server.poll()


func _load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(_settings_path)
	if err != OK:
		# First run - create default settings
		_save_default_settings()
		return

	# Settings loaded, dock will read them as needed


func _save_default_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("general", "mode", "byok")  # byok or pool
	config.set_value("general", "output_root", "res://assets/sprites")
	config.set_value("general", "global_style", "pixel art game sprite, clean silhouette, transparent background")
	config.set_value("byok", "api_key", "")  # User must set this
	config.set_value("pool", "server_url", "https://sprites.pi-agents.dev")
	config.set_value("pool", "access_token", "")
	config.set_value("pool", "refresh_token", "")
	config.set_value("pool", "token_expires_at", 0)
	config.save(_settings_path)


## Get the settings config file path
func get_settings_path() -> String:
	return _settings_path


## Get plugin version
func get_plugin_version() -> String:
	return PLUGIN_VERSION


## Get protocol version
func get_protocol_version() -> String:
	return PROTOCOL_VERSION


## Try to enable automation server (dev/test mode only)
func _try_enable_automation_server() -> void:
	print_debug("[SpritePipeline] Checking automation enable conditions...")
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
	if config.load(_settings_path) == OK:
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

	print_debug("[SpritePipeline] Starting automation server on port %d..." % port)
	_automation_server = AutomationServerScript.new()
	var err = _automation_server.enable(port)

	if err == OK:
		print_debug("[SpritePipeline] Automation server enabled on port %d" % port)
		# Defer connection until dock is fully ready
		call_deferred("_connect_automation_to_dock")
	else:
		push_error("[SpritePipeline] Failed to start automation server: %s" % error_string(err))
		_automation_server = null


## Connect automation server to dock (called deferred after timer)
func _connect_automation_to_dock_deferred() -> void:
	print_debug("[SpritePipeline] _connect_automation_to_dock_deferred called")
	if not _automation_server:
		print_debug("[SpritePipeline] No automation server")
		return
	if not dock:
		print_debug("[SpritePipeline] No dock")
		return

	# Force dock initialization - call directly
	print_debug("[SpritePipeline] Calling dock.force_initialize()...")
	dock.force_initialize()
	print_debug("[SpritePipeline] dock.force_initialize() returned")

	# Connect the signal directly from the plugin
	var handler := Callable(dock, "_on_automation_command")
	if not _automation_server.command_received.is_connected(handler):
		_automation_server.command_received.connect(handler)
		print_debug("[SpritePipeline] Signal connected from plugin to dock._on_automation_command")
	else:
		print_debug("[SpritePipeline] Signal already connected")

	# Also set the dock's reference so it can respond
	dock._automation_server = _automation_server
	dock._automation_enabled = true
	print_debug("[SpritePipeline] Dock automation enabled")


## Connect automation server to dock (called deferred)
func _connect_automation_to_dock() -> void:
	if not _automation_server:
		return
	if dock and dock.has_method("set_automation_server"):
		dock.set_automation_server(_automation_server)
		print_debug("[SpritePipeline] Automation server passed to dock")
	else:
		push_warning("[SpritePipeline] Dock not ready for automation connection")


## Stop the automation server
func _stop_automation_server() -> void:
	if _automation_server:
		_automation_server.disable()
		_automation_server = null
		print_debug("[SpritePipeline] Automation server stopped")
