extends "res://tests/test_case.gd"
## The dock's BYOK model and quality pickers.

const DockScene := preload("res://addons/sprite_pipeline/ui/main_dock.tscn")
const BYOKClient := preload("res://addons/sprite_pipeline/api/byok_client.gd")


func test_model_picker_offers_presets_and_a_custom_model() -> void:
	var dock := DockScene.instantiate()
	tree.root.add_child(dock)
	check_eq(dock.image_model_option.item_count, BYOKClient.IMAGE_MODELS.size() + 1, "presets plus Custom")

	dock._select_image_model(BYOKClient.DEFAULT_IMAGE_MODEL)
	check_eq(dock._selected_image_model(), "gpt-image-2", "default model")

	dock._select_image_model("gpt-image-1-mini")
	check_eq(dock._selected_image_model(), "gpt-image-1-mini", "preset")
	check(not dock.custom_model_edit.visible, "no custom field for a preset")

	dock._select_image_model("my-image-model")
	check_eq(dock._selected_image_model(), "my-image-model", "custom model")
	check(dock.custom_model_edit.visible, "custom field shown")
	dock.free()


func test_quality_picker() -> void:
	var dock := DockScene.instantiate()
	tree.root.add_child(dock)
	check_eq(dock.image_quality_option.item_count, BYOKClient.IMAGE_QUALITIES.size(), "one entry per quality")
	dock._select_image_quality("high")
	check_eq(dock._selected_image_quality(), "high", "high")
	dock._select_image_quality("ultra")
	check_eq(dock._selected_image_quality(), "medium", "unknown quality falls back to medium")
	dock.free()
