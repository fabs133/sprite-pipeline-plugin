extends "res://tests/test_case.gd"

const Postprocess := preload("res://addons/sprite_pipeline/postprocess.gd")


func _color(row: int, column: int) -> Color:
	return Color8(40 + 50 * column, 60 + 40 * row, 200, 255)


## 1024x1024 transparent sheet on a 4x4 grid with one square per active cell.
## bleed makes each square reach 20 px into its neighbours.
func _sheet(rows: int, frames: int, bleed := false) -> Image:
	var data := PackedByteArray()
	data.resize(1024 * 1024 * 4)
	data.fill(0)
	var sheet := Image.create_from_data(1024, 1024, false, Image.FORMAT_RGBA8, data)
	var inset := -20 if bleed else 64
	for row in rows:
		for column in frames:
			sheet.fill_rect(Rect2i(column * 256 + inset, row * 256 + inset, 256 - 2 * inset, 256 - 2 * inset), _color(row, column))
	return sheet


func test_slice_grid_returns_active_cells_row_major() -> void:
	var cells := Postprocess.slice_grid(_sheet(2, 3), 4, 2, 3)
	check_eq(cells.size(), 6, "cell count")
	for index in cells.size():
		var row := floori(index / 3.0)
		var column := index % 3
		check_eq(cells[index].get_size(), Vector2i(256, 256), "cell %d size" % index)
		check_eq(cells[index].get_pixel(128, 128), _color(row, column), "cell %d is row %d column %d" % [index, row, column])


func test_downscale_sizes_and_no_upscaling() -> void:
	var cell := _sheet(1, 1).get_region(Rect2i(0, 0, 256, 256))
	check_eq(Postprocess.downscale_nearest(cell, 32, 32).get_size(), Vector2i(32, 32), "square target")
	check_eq(Postprocess.downscale_nearest(cell, 24, 20).get_size(), Vector2i(24, 20), "non-square target")
	check_eq(Postprocess.downscale_nearest(cell, 512, 16).get_size(), Vector2i(256, 16), "an axis below its target keeps its size")
	check_eq(Postprocess.downscale_nearest(cell, 512, 512).get_data(), cell.get_data(), "a target larger than the cell leaves it unchanged")


func test_nearest_sampling_uses_pixel_centres_like_pillow() -> void:
	var indices := Postprocess._nearest_indices(256, 32)
	check_eq(indices[0], 4, "first output pixel samples the middle of its 8 px span")
	check_eq(indices[31], 252, "last output pixel")
	check_eq(Postprocess._nearest_indices(10, 10), PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]), "same size is the identity")


func test_postprocess_sheet_layout() -> void:
	var result := Postprocess.postprocess_sheet(_sheet(1, 4).save_png_to_buffer(), 4, 1, 4, 32, 32)
	check_eq([result.get("frame_w"), result.get("frame_h"), result.get("columns")], [32, 32, 4], "frame size and columns")
	var sheet := Image.new()
	sheet.load_png_from_buffer(result["sheet_png"])
	check_eq(sheet.get_size(), Vector2i(128, 32), "sheet is frames * frame_w by rows * frame_h")
	check_eq(result["frames_png"].size(), 4, "one PNG per frame")
	for index in 4:
		var frame := Image.new()
		frame.load_png_from_buffer(result["frames_png"][index])
		check_eq(frame.get_size(), Vector2i(32, 32), "frame %d size" % index)
		check_eq(frame.get_pixel(16, 16), _color(0, index), "frame %d in order" % index)
		check_eq(sheet.get_pixel(index * 32 + 16, 16), _color(0, index), "frame %d placed in the sheet" % index)
	check_eq(sheet.get_pixel(0, 0).a, 0.0, "background stays transparent")


func test_gutter_check_tells_clean_from_bleeding_sheets() -> void:
	var clean := Postprocess.check_grid_gutters(_sheet(2, 4), 4, 2, 4)
	check_eq(clean, {"gutter_opaque_ratio": 0.0, "violated": false}, "clean sheet")
	var bleeding := Postprocess.check_grid_gutters(_sheet(2, 4, true), 4, 2, 4)
	check(bleeding["violated"], "bleeding sheet is flagged")
	check(bleeding["gutter_opaque_ratio"] > Postprocess.GUTTER_TOLERANCE, "ratio above the tolerance: %s" % bleeding["gutter_opaque_ratio"])
	check_eq(Postprocess.check_grid_gutters(_sheet(1, 1), 1, 1, 1), {"gutter_opaque_ratio": 0.0, "violated": false}, "a single cell has no gutters")


func test_postprocess_is_deterministic() -> void:
	var png := _sheet(2, 3, true).save_png_to_buffer()
	var first := Postprocess.postprocess_sheet(png, 4, 2, 3, 48, 40)
	var second := Postprocess.postprocess_sheet(png, 4, 2, 3, 48, 40)
	check_eq(first["sheet_png"], second["sheet_png"], "sheet bytes")
	check_eq(first["frames_png"], second["frames_png"], "frame bytes")
	check_eq(first["check"], second["check"], "gutter check")


func test_unreadable_image_gives_an_empty_result() -> void:
	check(Postprocess.postprocess_sheet(PackedByteArray(), 4, 1, 4, 32, 32).is_empty(), "empty buffer")
