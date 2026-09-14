extends "res://tests/test_case.gd"

const Version := preload("res://addons/sprite_pipeline/version.gd")


func test_versions_have_three_numeric_parts() -> void:
	for version: String in [Version.PLUGIN, Version.PROTOCOL]:
		var parts := version.split(".")
		check_eq(parts.size(), 3, "%s part count" % version)
		for part in parts:
			check(part.is_valid_int(), "%s part '%s' is a number" % [version, part])


func test_plugin_cfg_matches_version() -> void:
	var cfg := ConfigFile.new()
	check_eq(cfg.load("res://addons/sprite_pipeline/plugin.cfg"), OK, "plugin.cfg loads")
	check_eq(cfg.get_value("plugin", "version", ""), Version.PLUGIN, "plugin.cfg version")
