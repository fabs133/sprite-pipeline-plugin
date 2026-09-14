extends "res://tests/test_case.gd"
## Outside the editor the editor calls do nothing and never touch the project.

const EditorIntegration := preload("res://addons/sprite_pipeline/editor_integration.gd")


func test_outside_the_editor_nothing_changes() -> void:
	check(not EditorIntegration.is_editor(), "tests run outside the editor")
	check_eq(EditorIntegration.project_filter(), EditorIntegration.FILTER_DEFAULT, "dev project has the default filter")
	check(not EditorIntegration.project_filter_is_nearest(), "Linear is not nearest")
	check_eq(EditorIntegration.set_project_filter_nearest(), ERR_UNAVAILABLE, "no project.godot write")
	check_eq(EditorIntegration.project_filter(), EditorIntegration.FILTER_DEFAULT, "setting unchanged")
	await EditorIntegration.scan_and_wait()
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
