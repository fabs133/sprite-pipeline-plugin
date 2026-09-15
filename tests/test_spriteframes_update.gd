extends "res://tests/test_case.gd"
## Regenerating a sheet whose SpriteFrames the editor already holds (open in the
## SpriteFrames panel, used by an open scene). The held instance has to get the new
## frames: the editor saves that instance, and would write the old frames back.
##
## Outside the editor a PNG can't be imported, so each test puts its sheet texture into
## the resource cache under the PNG's path, where ResourceLoader finds it as it finds an
## imported sheet. The cache entry lasts as long as the texture is referenced.

const EditorIntegration := preload("res://addons/sprite_pipeline/editor_integration.gd")
const Builder := preload("res://addons/sprite_pipeline/spriteframes_builder.gd")
const Writer := preload("res://addons/sprite_pipeline/spriteframes_writer.gd")


func test_a_held_tres_the_plugin_wrote_gets_the_new_frames() -> void:
	var root := make_temp_dir("spriteframes_update")
	var sheet := _cache_sheet(root, 128, 64)
	var tres := root.path_join("hero.tres")
	check_eq(EditorIntegration.write_spriteframes(_manifest(4, 1), root, 8.0, true), {tres: Writer.WRITE}, "first run writes hero.tres")
	var held := load(tres) as SpriteFrames
	check(held != null and ResourceLoader.has_cached(tres), "hero.tres is held in the resource cache")
	if held == null:
		remove_dir(root)
		return
	check_eq(held.get_animation_speed(&"default"), 8.0, "the held instance starts at 8 fps")

	check_eq(EditorIntegration.write_spriteframes(_manifest(4, 2), root, 12.0, false), {tres: Writer.UPDATE}, "second run updates hero.tres")
	check(load(tres) == held, "the cache still holds the same instance")
	_check_two_rows(held, sheet, 12.0, false, "held instance")
	_check_two_rows(_from_disk(tres), sheet, 12.0, false, "hero.tres on disk")
	check(not FileAccess.file_exists(root.path_join("hero.generated.tres")), "no .generated.tres")
	remove_dir(root)


func test_a_held_tres_the_user_made_is_left_alone() -> void:
	var root := make_temp_dir("spriteframes_user")
	var sheet := _cache_sheet(root, 128, 32)
	var tres := root.path_join("hero.tres")
	var user_made := SpriteFrames.new()
	user_made.set_animation_speed(&"default", 3.0)
	check_eq(ResourceSaver.save(user_made, tres), OK, "saved a SpriteFrames without the metadata")
	var file_before := FileAccess.get_file_as_string(tres)
	var held := load(tres) as SpriteFrames
	check(held != null and ResourceLoader.has_cached(tres), "hero.tres is held in the resource cache")
	if held == null:
		remove_dir(root)
		return

	var generated := root.path_join("hero.generated.tres")
	check_eq(EditorIntegration.write_spriteframes(_manifest(4, 1), root, 12.0, true), {generated: Writer.GENERATED}, "the new resource goes to hero.generated.tres")
	check_eq(held.get_animation_names(), PackedStringArray(["default"]), "held animations unchanged")
	check_eq(held.get_frame_count(&"default"), 0, "held frames unchanged")
	check_eq(held.get_animation_speed(&"default"), 3.0, "held fps unchanged")
	check(not held.has_meta(Builder.GENERATED_META), "held instance got no metadata")
	check_eq(FileAccess.get_file_as_string(tres), file_before, "hero.tres on disk unchanged")
	_check_default_row(_from_disk(generated), sheet, 12.0, "hero.generated.tres")
	remove_dir(root)


func test_metadata_deleted_in_the_editor_counts_before_the_resource_is_saved() -> void:
	var root := make_temp_dir("spriteframes_meta_removed")
	var sheet := _cache_sheet(root, 128, 32)
	var tres := root.path_join("hero.tres")
	check_eq(EditorIntegration.write_spriteframes(_manifest(4, 1), root, 8.0, true), {tres: Writer.WRITE}, "first run writes hero.tres")
	var held := load(tres) as SpriteFrames
	if held == null:
		failures.append("hero.tres did not load")
		remove_dir(root)
		return
	# What deleting sprite_pipeline_generated in the inspector does, before a save
	held.remove_meta(Builder.GENERATED_META)
	var file_before := FileAccess.get_file_as_string(tres)

	var generated := root.path_join("hero.generated.tres")
	check_eq(EditorIntegration.write_spriteframes(_manifest(4, 1), root, 12.0, true), {generated: Writer.GENERATED}, "the held instance's metadata decides, not the file's")
	check_eq(held.get_animation_speed(&"default"), 8.0, "held instance unchanged")
	check_eq(FileAccess.get_file_as_string(tres), file_before, "hero.tres on disk unchanged")
	_check_default_row(_from_disk(generated), sheet, 12.0, "hero.generated.tres")
	remove_dir(root)


func test_with_overwrite_a_held_tres_the_user_made_is_rebuilt_in_place() -> void:
	var root := make_temp_dir("spriteframes_overwrite_held")
	var sheet := _cache_sheet(root, 128, 64)
	var tres := root.path_join("hero.tres")
	check_eq(ResourceSaver.save(SpriteFrames.new(), tres), OK, "saved a SpriteFrames without the metadata")
	var held := load(tres) as SpriteFrames
	if held == null:
		failures.append("hero.tres did not load")
		remove_dir(root)
		return

	check_eq(EditorIntegration.write_spriteframes(_manifest(4, 2), root, 12.0, false, true), {tres: Writer.UPDATE}, "overwrite replaces hero.tres")
	check(load(tres) == held, "the cache still holds the same instance")
	_check_two_rows(held, sheet, 12.0, false, "held instance")
	_check_two_rows(_from_disk(tres), sheet, 12.0, false, "hero.tres on disk")
	remove_dir(root)


## A sheet texture of width x height, cached under root/hero.png as if Godot imported it
func _cache_sheet(root: String, width: int, height: int) -> Texture2D:
	var texture := ImageTexture.create_from_image(Image.create_empty(width, height, false, Image.FORMAT_RGBA8))
	texture.take_over_path(root.path_join("hero.png"))
	return texture


## A manifest with one result, hero.png, of frames x rows 32x32 cells
func _manifest(frames: int, rows: int) -> Dictionary:
	return {"results": [{"file_path": "hero.png", "frames": float(frames), "rows": float(rows), "frame_w": 32.0, "frame_h": 32.0}]}


## The SpriteFrames in the file at path, read without the resource cache
func _from_disk(path: String) -> SpriteFrames:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SpriteFrames


## The resource for a 4x2 result: row_0 and row_1 of 4 frames cut from sheet
func _check_two_rows(sprite_frames: SpriteFrames, sheet: Texture2D, fps: float, loop: bool, label: String) -> void:
	if sprite_frames == null:
		failures.append("%s: no SpriteFrames" % label)
		return
	check_eq(sprite_frames.get_animation_names(), PackedStringArray(["row_0", "row_1"]), "%s animations" % label)
	for animation in ["row_0", "row_1"]:
		check_eq(sprite_frames.get_frame_count(animation), 4, "%s %s frame count" % [label, animation])
		check_eq(sprite_frames.get_animation_speed(animation), fps, "%s %s fps" % [label, animation])
		check_eq(sprite_frames.get_animation_loop(animation), loop, "%s %s loop" % [label, animation])
	var last := sprite_frames.get_frame_texture(&"row_1", 3) as AtlasTexture
	check(last != null and last.atlas == sheet and last.region == Rect2(96, 32, 32, 32), "%s last frame cut from the sheet" % label)
	check_eq(sprite_frames.get_meta(Builder.GENERATED_META, false), true, "%s carries the plugin's metadata" % label)


## The resource for a 4x1 result: default with 4 frames cut from sheet
func _check_default_row(sprite_frames: SpriteFrames, sheet: Texture2D, fps: float, label: String) -> void:
	if sprite_frames == null:
		failures.append("%s: no SpriteFrames" % label)
		return
	check_eq(sprite_frames.get_animation_names(), PackedStringArray(["default"]), "%s animations" % label)
	check_eq(sprite_frames.get_frame_count(&"default"), 4, "%s frame count" % label)
	check_eq(sprite_frames.get_animation_speed(&"default"), fps, "%s fps" % label)
	var first := sprite_frames.get_frame_texture(&"default", 0) as AtlasTexture
	check(first != null and first.atlas == sheet, "%s frames cut from the sheet" % label)
