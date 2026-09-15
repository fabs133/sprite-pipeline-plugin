extends "res://tests/test_case.gd"
## Saving settings keeps the keys the dock doesn't own.

const SettingsStore := preload("res://addons/sprite_pipeline/settings_store.gd")
const DockScene := preload("res://addons/sprite_pipeline/ui/main_dock.tscn")
const SETTINGS_PATH := "user://sprite_pipeline_settings.cfg"


func _write(path: String, values: Dictionary) -> void:
	var config := ConfigFile.new()
	for section: String in values:
		for key: String in values[section]:
			config.set_value(section, key, values[section][key])
	config.save(path)


func _load(path: String) -> ConfigFile:
	var config := ConfigFile.new()
	config.load(path)
	return config


func test_save_keeps_keys_it_was_not_given() -> void:
	var root := make_temp_dir("settings_store")
	var path := root.path_join("settings.cfg")
	_write(path, {"dev": {"enable_automation": true}, "general": {"mode": "pool"}})
	check_eq(SettingsStore.save(path, {"general": {"mode": "byok"}, "editor": {"pin_import_params": false}}), OK, "saved")
	var config := _load(path)
	check_eq(config.get_value("dev", "enable_automation", false), true, "[dev] enable_automation survives")
	check_eq(config.get_value("general", "mode", ""), "byok", "existing key updated")
	check_eq(config.get_value("editor", "pin_import_params", true), false, "new key added")
	remove_dir(root)


func test_null_removes_a_key() -> void:
	var root := make_temp_dir("settings_store")
	var path := root.path_join("settings.cfg")
	_write(path, {"pool": {"server_url": "https://example.com", "access_token": "acc"}})
	SettingsStore.save(path, {"pool": {"access_token": null, "refresh_token": null}})
	var config := _load(path)
	check(not config.has_section_key("pool", "access_token"), "access_token removed")
	check(not config.has_section_key("pool", "refresh_token"), "a missing key stays missing")
	check_eq(config.get_value("pool", "server_url", ""), "https://example.com", "other keys kept")
	remove_dir(root)


func test_a_missing_or_unreadable_file_starts_empty() -> void:
	var root := make_temp_dir("settings_store")
	var missing := root.path_join("missing.cfg")
	check_eq(SettingsStore.save(missing, {"general": {"mode": "byok"}}), OK, "missing file saved")
	check_eq(_load(missing).get_value("general", "mode", ""), "byok", "missing file written")

	var broken := root.path_join("broken.cfg")
	var file := FileAccess.open(broken, FileAccess.WRITE)
	file.store_string("[general\nmode = = =\n")
	file.close()
	check_eq(SettingsStore.save(broken, {"general": {"mode": "byok"}}), OK, "unreadable file saved")
	check_eq(_load(broken).get_value("general", "mode", ""), "byok", "unreadable file replaced")
	remove_dir(root)


func test_dock_save_keeps_dev_settings_and_drops_tokens_without_a_login() -> void:
	var dock := DockScene.instantiate()
	tree.root.add_child(dock)
	# Added after the dock loaded the file, so it neither starts the automation server
	# nor restores the tokens
	var config := _load(SETTINGS_PATH)
	config.set_value("dev", "enable_automation", true)
	config.set_value("pool", "access_token", "stale")
	config.set_value("pool", "refresh_token", "stale-refresh")
	config.save(SETTINGS_PATH)

	dock._pool_client = null
	dock._save_settings()
	config = _load(SETTINGS_PATH)
	check_eq(config.get_value("dev", "enable_automation", false), true, "[dev] enable_automation survives a dock save")
	check(config.has_section_key("general", "mode"), "the dock's own keys are written")
	check(not config.has_section_key("pool", "access_token"), "access_token removed without a login")
	check(not config.has_section_key("pool", "refresh_token"), "refresh_token removed without a login")
	dock.free()

	# Leave the settings file as the other tests expect it
	config.set_value("dev", "enable_automation", null)
	config.save(SETTINGS_PATH)
