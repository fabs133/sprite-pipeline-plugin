extends "res://tests/test_case.gd"
## The dock's reaction to generation signals, with the scene loaded headless.

const DockScene := preload("res://addons/sprite_pipeline/ui/main_dock.tscn")
const MainDock := preload("res://addons/sprite_pipeline/ui/main_dock.gd")
const PoolClient := preload("res://addons/sprite_pipeline/api/pool_client.gd")


func _dock() -> Node:
	var dock := DockScene.instantiate()
	tree.root.add_child(dock)
	return dock


func test_progress_percent_moves_the_bar() -> void:
	var dock := _dock()
	dock._on_generation_percent(40, "generating")
	check_eq(dock.progress_bar.value, 40.0, "bar value")
	check_eq(dock.status_text.text, "generating (40%)", "status text")
	dock.free()


func test_grid_warnings_show_in_the_results() -> void:
	var dock := _dock()
	dock._is_generating = true
	dock._on_generation_completed({"version": 2, "results": [{"grid_violation": true}, {"grid_violation": false}], "errors": []})
	check_eq(dock.results_label.text, "Results: 2 success, 0 errors (1 grid warnings)", "results text")
	check_eq(dock.results_label.get_theme_color("font_color"), Color(1, 0.8, 0.2), "yellow label")
	dock.free()


func test_count_grid_warnings() -> void:
	check_eq(MainDock.count_grid_warnings({"results": [{"grid_violation": true}, {}, "not a result"]}), 1, "one warning")
	check_eq(MainDock.count_grid_warnings({}), 0, "no results")


func test_import_resolves_relative_manifest_paths() -> void:
	var root := make_temp_dir("dock_import")
	DirAccess.make_dir_recursive_absolute(root.path_join("characters"))
	var file := FileAccess.open(root.path_join("characters/hero.png"), FileAccess.WRITE)
	file.store_string("png")
	file.close()
	var dock := _dock()
	var result: Dictionary = dock._import_assets_from_manifest({"results": [
		{"file_path": "characters/hero.png", "sha256": PoolClient.sha256_hex("png".to_utf8_buffer())},
		{"file_path": "../escape.png"},
	]}, root)
	check_eq(result["skipped"], 1, "intact file under output_root is skipped")
	check_eq(result["failed"], 1, "unsafe path fails")
	dock.free()
	remove_dir(root)
