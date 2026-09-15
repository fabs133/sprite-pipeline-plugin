extends "res://tests/test_case.gd"
## Outside the editor the editor calls do nothing and never touch the project.

const EditorIntegration := preload("res://addons/sprite_pipeline/editor_integration.gd")
const Builder := preload("res://addons/sprite_pipeline/spriteframes_builder.gd")
const Writer := preload("res://addons/sprite_pipeline/spriteframes_writer.gd")


func test_outside_the_editor_nothing_changes() -> void:
	check(not EditorIntegration.is_editor(), "tests run outside the editor")
	check_eq(EditorIntegration.project_filter(), EditorIntegration.FILTER_DEFAULT, "dev project has the default filter")
	check(not EditorIntegration.project_filter_is_nearest(), "Linear is not nearest")
	check_eq(EditorIntegration.set_project_filter_nearest(), ERR_UNAVAILABLE, "no project.godot write")
	check_eq(EditorIntegration.project_filter(), EditorIntegration.FILTER_DEFAULT, "setting unchanged")
	await EditorIntegration.scan_and_wait(PackedStringArray(["res://missing.png"]))
	EditorIntegration.scan()
	EditorIntegration.reimport(PackedStringArray(["res://missing.png"]))


func test_filter_constants_match_the_project_setting() -> void:
	for property in ProjectSettings.get_property_list():
		if property["name"] == EditorIntegration.FILTER_SETTING:
			check_eq(property["hint_string"], ",".join(PackedStringArray(EditorIntegration.FILTER_NAMES)), "enum hint")
			check_eq(EditorIntegration.FILTER_NAMES[EditorIntegration.FILTER_NEAREST], "Nearest", "Nearest index")
			check_eq(EditorIntegration.FILTER_NAMES[EditorIntegration.FILTER_NEAREST_MIPMAP], "Nearest Mipmap", "Nearest Mipmap index")
			check_eq(ProjectSettings.property_get_revert(EditorIntegration.FILTER_SETTING), EditorIntegration.FILTER_DEFAULT, "default")
			return
	failures.append("%s not found" % EditorIntegration.FILTER_SETTING)


func test_only_project_files_without_import_settings_are_pending() -> void:
	var root := make_temp_dir("not_imported")
	check_eq(EditorIntegration._not_imported(PackedStringArray(["res://missing.png", root.path_join("x.png"), "C:/game/out/x.png"])), PackedStringArray(["res://missing.png"]), "only res:// paths wait for an import")
	remove_dir(root)


func test_spriteframes_target_replaces_only_a_tres_the_plugin_wrote() -> void:
	var root := make_temp_dir("spriteframes_target")
	var sheet := root.path_join("hero.png")
	var tres := root.path_join("hero.tres")
	check_eq(EditorIntegration.spriteframes_target(sheet, false), {"path": tres, "action": Writer.WRITE}, "no .tres yet")

	check_eq(ResourceSaver.save(SpriteFrames.new(), tres), OK, "saved a SpriteFrames without the metadata")
	check(not EditorIntegration.written_by_plugin(tres), "a SpriteFrames without the metadata is not the plugin's")
	check_eq(EditorIntegration.spriteframes_target(sheet, false), {"path": root.path_join("hero.generated.tres"), "action": Writer.GENERATED}, "other .tres kept")
	check_eq(EditorIntegration.spriteframes_target(sheet, true), {"path": tres, "action": Writer.UPDATE}, "other .tres with overwrite")

	var sheet_texture := ImageTexture.create_from_image(Image.create_empty(64, 32, false, Image.FORMAT_RGBA8))
	var built := Builder.build({"frames": 2.0, "rows": 1.0, "frame_w": 32.0, "frame_h": 32.0}, sheet_texture, 8.0, true)
	check_eq(ResourceSaver.save(built, tres), OK, "saved a SpriteFrames the plugin built")
	check(EditorIntegration.written_by_plugin(tres), "the plugin's .tres is recognized")
	check_eq(EditorIntegration.spriteframes_target(sheet, false), {"path": tres, "action": Writer.UPDATE}, "plugin's .tres updated")

	var file := FileAccess.open(tres, FileAccess.WRITE)
	file.store_string("not a resource\n")
	file.close()
	check(not EditorIntegration.written_by_plugin(tres), "a file that doesn't load is not the plugin's")
	remove_dir(root)


func test_write_spriteframes_skips_sheets_that_are_not_imported() -> void:
	var root := make_temp_dir("spriteframes_write")
	DirAccess.make_dir_recursive_absolute(root.path_join("characters"))
	var image := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	image.save_png(root.path_join("characters/hero.png"))
	var manifest := {"results": [
		{"file_path": "characters/hero.png", "frames": 2.0, "rows": 1.0, "frame_w": 32.0, "frame_h": 32.0},
		{"file_path": "characters/still.png", "frames": 1.0, "rows": 1.0, "frame_w": 32.0, "frame_h": 32.0},
	]}
	check_eq(EditorIntegration.write_spriteframes(manifest, root, 8.0, true), {}, "nothing written")
	check(not FileAccess.file_exists(root.path_join("characters/hero.tres")), "no .tres for a PNG Godot has not imported")
	remove_dir(root)
