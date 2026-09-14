@tool
class_name SpritePostprocess
extends RefCounted
## Deterministic post-processing of generated sprite sheets: slice the grid cells,
## downscale each cell, reassemble a compact sheet, and check the gutters.
##
## PARITY: sprite_pipeline/postprocess.py in sprite-pipeline-backend. Same cell layout,
## the same nearest-neighbour sampling as Pillow's Image.resize(NEAREST), the same gutter
## check. When the backend switches to a box filter with an alpha threshold, change this
## file the same way.
##
## Pure functions: images and bytes in, images, bytes and dictionaries out.

const GUTTER_PX := 4
const ALPHA_THRESHOLD := 16
const GUTTER_TOLERANCE := 0.05


## Crop the active cells of an NxN sheet as RGBA images, row-major.
## With grid_size 1 the whole image is the single cell.
static func slice_grid(sheet: Image, grid_size: int, rows: int, frames: int) -> Array[Image]:
	var rgba := _rgba(sheet)
	var grid := _active_grid(rgba.get_size(), grid_size, rows, frames)
	var cell_w: int = grid["cell_w"]
	var cell_h: int = grid["cell_h"]
	var cells: Array[Image] = []
	for row in range(grid["rows"]):
		for column in range(grid["columns"]):
			cells.append(rgba.get_region(Rect2i(column * cell_w, row * cell_h, cell_w, cell_h)))
	return cells


## Nearest-neighbour downscale that keeps RGBA and hard pixel edges; never upscales.
## An axis already at or below its target keeps its size.
static func downscale_nearest(img: Image, w: int, h: int) -> Image:
	var source := _rgba(img)
	var src_w := source.get_width()
	var src_h := source.get_height()
	var out_w := mini(w, src_w)
	var out_h := mini(h, src_h)
	if out_w == src_w and out_h == src_h:
		return source

	var source_columns := _nearest_indices(src_w, out_w)
	var source_rows := _nearest_indices(src_h, out_h)
	var src := source.get_data()
	var out := PackedByteArray()
	out.resize(out_w * out_h * 4)
	for y in out_h:
		var src_row_start := source_rows[y] * src_w
		var out_row_start := y * out_w
		for x in out_w:
			var src_index := (src_row_start + source_columns[x]) * 4
			var out_index := (out_row_start + x) * 4
			out[out_index] = src[src_index]
			out[out_index + 1] = src[src_index + 1]
			out[out_index + 2] = src[src_index + 2]
			out[out_index + 3] = src[src_index + 3]
	return Image.create_from_data(out_w, out_h, false, Image.FORMAT_RGBA8, out)


## Share of non-transparent pixels on the boundaries between active cells:
## {gutter_opaque_ratio: float rounded to 4 places, violated: bool}.
## Samples strips gutter_px wide centred on each internal cell boundary; sprites that
## bleed into a neighbouring cell show up as opaque gutter pixels.
static func check_grid_gutters(sheet: Image, grid_size: int, rows: int, frames: int, gutter_px := GUTTER_PX, alpha_threshold := ALPHA_THRESHOLD, tolerance := GUTTER_TOLERANCE) -> Dictionary:
	var rgba := _rgba(sheet)
	var width := rgba.get_width()
	var height := rgba.get_height()
	var grid := _active_grid(rgba.get_size(), grid_size, rows, frames)
	var cell_w: int = grid["cell_w"]
	var cell_h: int = grid["cell_h"]
	var area_w: int = grid["columns"] * cell_w
	var area_h: int = grid["rows"] * cell_h
	var half := floori(gutter_px / 2.0)

	# Strips centred on the internal boundaries between active cells: [left, top, right, bottom]
	var strips := []
	for column in range(1, grid["columns"]):
		var x := column * cell_w
		strips.append([x - half, 0, x - half + gutter_px, area_h])
	for row in range(1, grid["rows"]):
		var y := row * cell_h
		strips.append([0, y - half, area_w, y - half + gutter_px])

	# Count each pixel once where strips cross
	var counted := PackedByteArray()
	counted.resize(width * height)
	counted.fill(0)
	var data := rgba.get_data()
	var gutter_pixels := 0
	var opaque_pixels := 0
	for strip in strips:
		for y in range(maxi(0, strip[1]), mini(height, strip[3])):
			for x in range(maxi(0, strip[0]), mini(width, strip[2])):
				var index := y * width + x
				if counted[index] == 0:
					counted[index] = 1
					gutter_pixels += 1
					if data[index * 4 + 3] > alpha_threshold:
						opaque_pixels += 1

	if gutter_pixels == 0:
		return {"gutter_opaque_ratio": 0.0, "violated": false}
	var ratio := float(opaque_pixels) / float(gutter_pixels)
	return {"gutter_opaque_ratio": ("%.4f" % ratio).to_float(), "violated": ratio > tolerance}


## Slice the active cells, downscale each and reassemble them into a compact sheet
## (columns * frame_w by rows * frame_h, RGBA). The gutter check runs on the original sheet.
## Returns {sheet_png, frames_png (row-major), check, frame_w, frame_h, columns},
## or {} if sheet_png is not a readable PNG.
static func postprocess_sheet(sheet_png: PackedByteArray, grid_size: int, rows: int, frames: int, target_w: int, target_h: int) -> Dictionary:
	var image := Image.new()
	if sheet_png.is_empty() or image.load_png_from_buffer(sheet_png) != OK:
		return {}
	var rgba := _rgba(image)
	var grid := _active_grid(rgba.get_size(), grid_size, rows, frames)
	var columns: int = grid["columns"]

	var cells: Array[Image] = []
	for cell in slice_grid(rgba, grid_size, rows, frames):
		cells.append(downscale_nearest(cell, target_w, target_h))
	var frame_w := cells[0].get_width()
	var frame_h := cells[0].get_height()

	var sheet_data := PackedByteArray()
	sheet_data.resize(columns * frame_w * grid["rows"] * frame_h * 4)
	sheet_data.fill(0)
	var sheet := Image.create_from_data(columns * frame_w, grid["rows"] * frame_h, false, Image.FORMAT_RGBA8, sheet_data)
	var frames_png: Array[PackedByteArray] = []
	for index in cells.size():
		var cell := cells[index]
		var position := Vector2i((index % columns) * frame_w, floori(float(index) / columns) * frame_h)
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), position)
		frames_png.append(cell.save_png_to_buffer())

	return {
		"sheet_png": sheet.save_png_to_buffer(),
		"frames_png": frames_png,
		"check": check_grid_gutters(rgba, grid_size, rows, frames),
		"frame_w": frame_w,
		"frame_h": frame_h,
		"columns": columns,
	}


## Source index for each output index along one axis. Pillow's nearest resize starts at
## half a step and adds the step for each pixel, truncating to an index.
static func _nearest_indices(src_size: int, out_size: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	indices.resize(out_size)
	var step := float(src_size) / float(out_size)
	var position := step * 0.5
	for i in out_size:
		indices[i] = mini(int(position), src_size - 1)
		position += step
	return indices


## {rows, columns, cell_w, cell_h} of the active cells; cells are at least 1 px
static func _active_grid(size: Vector2i, grid_size: int, rows: int, frames: int) -> Dictionary:
	var grid := maxi(1, grid_size)
	return {
		"rows": maxi(1, mini(rows, grid)),
		"columns": maxi(1, mini(frames, grid)),
		"cell_w": maxi(1, floori(float(size.x) / grid)),
		"cell_h": maxi(1, floori(float(size.y) / grid)),
	}


## An RGBA8 copy, so callers' images are never converted in place
static func _rgba(image: Image) -> Image:
	var copy: Image = image.duplicate()
	if copy.is_compressed():
		copy.decompress()
	if copy.get_format() != Image.FORMAT_RGBA8:
		copy.convert(Image.FORMAT_RGBA8)
	return copy
