extends "res://tests/test_case.gd"

const ReimportManifest := preload("res://addons/sprite_pipeline/remediation/actions/reimport_manifest.gd")
const PoolClient := preload("res://addons/sprite_pipeline/api/pool_client.gd")


func test_verify_resolves_manifest_paths() -> void:
	var root := make_temp_dir("reimport")
	DirAccess.make_dir_recursive_absolute(root.path_join("characters"))
	var file := FileAccess.open(root.path_join("characters/hero.png"), FileAccess.WRITE)
	file.store_string("png")
	file.close()
	var sha := PoolClient.sha256_hex("png".to_utf8_buffer())
	var action := ReimportManifest.new()

	var relative: Dictionary = action.verify({"results": [{"file_path": "characters/hero.png", "sha256": sha}]}, root)
	check(relative["verified"], "relative path to an intact file verifies")

	var legacy: Dictionary = action.verify({"results": [{"file_path": root.path_join("characters/hero.png"), "sha256": sha}]}, root)
	check(legacy["verified"], "absolute path under output_root verifies")

	var broken: Dictionary = action.verify({"results": [{"file_path": "../outside.png"}, {"file_path": "characters/hero.png", "sha256": "00"}]}, root)
	check_eq(broken["missing_count"], 1, "unsafe path counts as missing")
	check_eq(broken["mismatch_count"], 1, "hash mismatch")
	remove_dir(root)
