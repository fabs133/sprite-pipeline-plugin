@tool
class_name SpriteFramesBuilder
extends RefCounted
## A SpriteFrames resource for a manifest v2 result: one animation per row of the sheet,
## one AtlasTexture per frame.
##
## Layout as postprocess.gd and the backend write it: the sheet is frames * frame_w wide
## and rows * frame_h high, with the cells row-major from the top left. A raw 1024x1024
## sheet has the same cells in its top-left corner.
##
## Pure functions: the sheet texture comes in, nothing is loaded or saved.

const Version := preload("res://addons/sprite_pipeline/version.gd")
## Metadata set on every SpriteFrames the plugin builds; regenerating replaces a .tres
## that has it (SpriteFramesWriter)
const GENERATED_META := &"sprite_pipeline_generated"
## Metadata with the version of the plugin that built the resource
const VERSION_META := &"sprite_pipeline_version"


## True for a result with more than one frame; a single still needs no SpriteFrames
static func is_animated(result: Dictionary) -> bool:
	return _count(result.get("frames"), 1) > 1 or _count(result.get("rows"), 1) > 1


## SpriteFrames for result, cut from sheet. null for a single still, a result without a
## frame size, or a sheet smaller than the frames the result describes.
static func build(result: Dictionary, sheet: Texture2D, fps: float, loop: bool) -> SpriteFrames:
	var frames := _count(result.get("frames"), 1)
	var rows := _count(result.get("rows"), 1)
	if not is_animated(result) or frames < 1 or rows < 1 or sheet == null:
		return null
	var last := region(result, rows - 1, frames - 1)
	if last.size.x < 1 or last.size.y < 1 or last.end.x > sheet.get_width() or last.end.y > sheet.get_height():
		return null

	var sprite_frames := SpriteFrames.new()
	sprite_frames.set_meta(GENERATED_META, true)
	sprite_frames.set_meta(VERSION_META, Version.PLUGIN)
	# A new SpriteFrames starts with an empty "default" animation
	sprite_frames.remove_animation(&"default")
	var names := animation_names(result)
	for row in rows:
		var animation := StringName(names[row])
		sprite_frames.add_animation(animation)
		sprite_frames.set_animation_speed(animation, fps)
		sprite_frames.set_animation_loop(animation, loop)
		for column in frames:
			var frame := AtlasTexture.new()
			frame.atlas = sheet
			frame.region = Rect2(region(result, row, column))
			# Keeps the neighbouring cells' pixels out of the frame's edges when filtered
			frame.filter_clip = true
			sprite_frames.add_frame(animation, frame)
	return sprite_frames


## The sheet region of the frame in row and column
static func region(result: Dictionary, row: int, column: int) -> Rect2i:
	var frame_w := _count(result.get("frame_w"), 0)
	var frame_h := _count(result.get("frame_h"), 0)
	return Rect2i(column * frame_w, row * frame_h, frame_w, frame_h)


## One unique name per row: result.animation_names[row] when given, otherwise "default"
## for a single row and "row_<n>" for several.
static func animation_names(result: Dictionary) -> PackedStringArray:
	var rows := _count(result.get("rows"), 1)
	var given: Array = result["animation_names"] if result.get("animation_names") is Array else []
	var names := PackedStringArray()
	for row in maxi(rows, 0):
		var animation_name := ""
		if row < given.size() and given[row] is String:
			animation_name = given[row].strip_edges()
		if animation_name.is_empty() or animation_name in names:
			animation_name = "default" if rows == 1 else "row_%d" % row
		while animation_name in names:
			animation_name = "%s_%d" % [animation_name, row]
		names.append(animation_name)
	return names


## A whole number from a manifest value (JSON numbers arrive as floats), else fallback
static func _count(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	return fallback
