extends "res://tests/test_case.gd"

const Builder := preload("res://addons/sprite_pipeline/spriteframes_builder.gd")
const Postprocess := preload("res://addons/sprite_pipeline/postprocess.gd")
const Version := preload("res://addons/sprite_pipeline/version.gd")


func test_built_resource_carries_the_plugin_metadata() -> void:
	var sprite_frames := Builder.build(_result(4, 1), _sheet(128, 32), 8.0, true)
	check(sprite_frames != null, "built")
	if sprite_frames == null:
		return
	check_eq(sprite_frames.get_meta(Builder.GENERATED_META, false), true, "generated flag")
	check_eq(sprite_frames.get_meta(Builder.VERSION_META, ""), Version.PLUGIN, "plugin version")
	var root := make_temp_dir("spriteframes_meta")
	var path := root.path_join("hero.tres")
	check_eq(ResourceSaver.save(sprite_frames, path), OK, "saved")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded is SpriteFrames and loaded.get_meta(Builder.GENERATED_META, false) == true, "the flag is saved with the resource")
	remove_dir(root)


func _color(row: int, column: int) -> Color:
	return Color8(40 + 50 * column, 60 + 40 * row, 200, 255)


func _sheet(width: int, height: int) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_empty(width, height, false, Image.FORMAT_RGBA8))


## A manifest result with numbers as floats, the way JSON delivers them
func _result(frames: int, rows: int, frame_w := 32, frame_h := 32) -> Dictionary:
	return {"file_path": "characters/hero.png", "frames": float(frames), "rows": float(rows), "frame_w": float(frame_w), "frame_h": float(frame_h)}


func test_region_math_for_a_4x1_sheet() -> void:
	var result := _result(4, 1)
	check_eq(Builder.region(result, 0, 0), Rect2i(0, 0, 32, 32), "first frame")
	check_eq(Builder.region(result, 0, 1), Rect2i(32, 0, 32, 32), "second frame")
	check_eq(Builder.region(result, 0, 3), Rect2i(96, 0, 32, 32), "last frame")


func test_region_math_for_a_4x2_sheet_with_non_square_frames() -> void:
	var result := _result(4, 2, 24, 16)
	check_eq(Builder.region(result, 0, 3), Rect2i(72, 0, 24, 16), "first row, last column")
	check_eq(Builder.region(result, 1, 0), Rect2i(0, 16, 24, 16), "second row, first column")
	check_eq(Builder.region(result, 1, 3), Rect2i(72, 16, 24, 16), "second row, last column")


func test_regions_match_the_postprocessed_sheet() -> void:
	# A 3x3 grid with 2 rows of 3 frames, one colour per cell, through postprocess.gd
	var source := Image.create_empty(1024, 1024, false, Image.FORMAT_RGBA8)
	for row in 2:
		for column in 3:
			source.fill_rect(Rect2i(column * 341 + 60, row * 341 + 60, 221, 221), _color(row, column))
	var processed := Postprocess.postprocess_sheet(source.save_png_to_buffer(), 3, 2, 3, 32, 32)
	var sheet := Image.new()
	sheet.load_png_from_buffer(processed["sheet_png"])
	var result := {"frames": 3.0, "rows": 2.0, "frame_w": float(processed["frame_w"]), "frame_h": float(processed["frame_h"])}

	var sprite_frames := Builder.build(result, ImageTexture.create_from_image(sheet), 8.0, true)
	check(sprite_frames != null, "built")
	if sprite_frames == null:
		return
	for row in 2:
		for column in 3:
			var frame := sprite_frames.get_frame_texture("row_%d" % row, column) as AtlasTexture
			check_eq(frame.get_image().get_pixel(16, 16), _color(row, column), "row %d column %d shows its own cell" % [row, column])


func test_build_makes_one_animation_per_row() -> void:
	var sheet := _sheet(128, 64)
	var sprite_frames := Builder.build(_result(4, 2), sheet, 8.0, true)
	check(sprite_frames != null, "built")
	if sprite_frames == null:
		return
	check_eq(sprite_frames.get_animation_names(), PackedStringArray(["row_0", "row_1"]), "animations")
	for animation in ["row_0", "row_1"]:
		check_eq(sprite_frames.get_frame_count(animation), 4, "%s frame count" % animation)
		check_eq(sprite_frames.get_animation_speed(animation), 8.0, "%s fps" % animation)
		check_eq(sprite_frames.get_animation_loop(animation), true, "%s loops" % animation)
	var last := sprite_frames.get_frame_texture("row_1", 3) as AtlasTexture
	check_eq(last.region, Rect2(96, 32, 32, 32), "region of the last frame")
	check(last.atlas == sheet, "frames cut from the sheet")
	check(last.filter_clip, "filter_clip on")


func test_single_row_is_default_with_fps_and_loop() -> void:
	var sprite_frames := Builder.build(_result(4, 1), _sheet(128, 32), 12.0, false)
	check(sprite_frames != null, "built")
	if sprite_frames == null:
		return
	check_eq(sprite_frames.get_animation_names(), PackedStringArray(["default"]), "one animation named default")
	check_eq(sprite_frames.get_frame_count("default"), 4, "frame count")
	check_eq(sprite_frames.get_animation_speed("default"), 12.0, "fps")
	check_eq(sprite_frames.get_animation_loop("default"), false, "no loop")


func test_animation_names() -> void:
	check_eq(Builder.animation_names(_result(4, 1)), PackedStringArray(["default"]), "single row")
	check_eq(Builder.animation_names(_result(4, 3)), PackedStringArray(["row_0", "row_1", "row_2"]), "rows")
	var named := _result(4, 3)
	named["animation_names"] = ["walk", "", "walk"]
	check_eq(Builder.animation_names(named), PackedStringArray(["walk", "row_1", "row_2"]), "given names, fallbacks for empty and duplicate")
	var one := _result(2, 1)
	one["animation_names"] = [" idle "]
	check_eq(Builder.animation_names(one), PackedStringArray(["idle"]), "single named row")


func test_stills_and_mismatched_results_give_null() -> void:
	check(Builder.build(_result(1, 1), _sheet(32, 32), 8.0, true) == null, "1x1 still")
	check(not Builder.is_animated(_result(1, 1)), "a still is not animated")
	check(Builder.is_animated(_result(1, 2)), "one frame in two rows is animated")
	check(Builder.build(_result(4, 1), _sheet(64, 32), 8.0, true) == null, "sheet narrower than the frames")
	check(Builder.build(_result(4, 2), _sheet(128, 32), 8.0, true) == null, "sheet shorter than the rows")
	check(Builder.build(_result(4, 1), null, 8.0, true) == null, "no sheet")
	check(Builder.build({"frames": 4.0, "rows": 1.0}, _sheet(128, 32), 8.0, true) == null, "no frame size")
	check(Builder.build(_result(0, 2), _sheet(128, 64), 8.0, true) == null, "zero frames")
