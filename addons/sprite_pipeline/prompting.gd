@tool
class_name SpritePrompting
extends RefCounted
## Builds the image prompt for one queue item: the same text sprite-pipeline-backend sends.
##
## PARITY: app/services/pipeline_runner.py in sprite-pipeline-backend
## (FastHookProvider._build_prompt_local and the BUILD_BRIEF branch of run()).
## Change both sides together; tests/test_prompting.gd holds prompts copied from the backend.
## Pure functions: no file access, no logging.


## {prompt: String, grid_size: int} for a queue item and the global style.
## The sheet is laid out as a grid_size x grid_size grid on a 1024x1024 canvas.
static func build_prompt(spec: Dictionary, global_style: String) -> Dictionary:
	var row_descriptions: Array = spec["row_descriptions"] if spec.get("row_descriptions") is Array else []
	var prompt_text := _base_prompt(spec, global_style, row_descriptions)

	var active_rows := _whole_number(spec.get("rows", 1))
	if active_rows == 0:
		active_rows = 1
	var frames_per_row := _whole_number(spec.get("frames", 1))
	var grid_size := maxi(frames_per_row, active_rows)
	var cell_size := floori(1024.0 / grid_size) if grid_size > 0 else 1024

	if grid_size <= 1:
		return {
			"prompt": "%s. Single centered sprite, clean edges. Fully transparent background, no ground shadow, no border, no frame." % prompt_text,
			"grid_size": grid_size,
		}

	var row_lines := PackedStringArray()
	for index in row_descriptions.size():
		var description = row_descriptions[index]
		var row_type = description.get("type", "custom") if description is Dictionary else "custom"
		if row_type == "variation":
			var line := "Row %d: variation of row %d" % [index + 1, _whole_number(description.get("variationOf", 0)) + 1]
			var modifier = description.get("modifier", "")
			if modifier:
				line += ", but %s" % str(modifier)
			row_lines.append(line)
		else:
			var row_prompt = description.get("prompt", "") if description is Dictionary else ""
			if row_prompt:
				row_lines.append("Row %d: %s" % [index + 1, str(row_prompt)])
			else:
				row_lines.append("Row %d: same as overall description" % (index + 1))
	var row_block := (". ".join(row_lines) + ".") if not row_lines.is_empty() else ""

	var padding_parts := PackedStringArray()
	if active_rows < grid_size:
		padding_parts.append("Rows %d-%d are empty (leave transparent/blank)" % [active_rows + 1, grid_size])
	if frames_per_row < grid_size:
		padding_parts.append("Columns %d-%d are empty (leave transparent/blank)" % [frames_per_row + 1, grid_size])
	var padding_note := (". ".join(padding_parts) + ".") if not padding_parts.is_empty() else ""

	var prompt := "".join(PackedStringArray([
		"STRICT GRID LAYOUT: Create a 1024x1024 pixel spritesheet with EXACTLY ",
		"%d rows and %d columns forming a %dx%d uniform grid. " % [grid_size, grid_size, grid_size, grid_size],
		"Each cell is EXACTLY %dx%d pixels. " % [cell_size, cell_size],
		"Every sprite MUST fit inside its cell boundaries — do NOT let sprites overlap or merge across cells. ",
		"Rows 1-%d contain sprites with EXACTLY %d frames per row. " % [active_rows, frames_per_row],
		row_block + " ",
		padding_note + " ",
		"Each frame shows a different pose or animation step. ",
		"Style: %s. " % prompt_text,
		"Fully transparent background, no ground shadow, no border, no frame.",
	]))
	return {"prompt": prompt, "grid_size": grid_size}


## Queue items with a description but no prompt get the description as their prompt:
## the plugin's queue format documented `description`, the backend reads `prompt`.
## Returns new dictionaries; the input queue is not changed.
static func normalize_queue(queue: Array) -> Array:
	var normalized := []
	for item in queue:
		if not item is Dictionary:
			normalized.append(item)
			continue
		var copy: Dictionary = item.duplicate(true)
		var description = copy.get("description")
		if not copy.get("prompt") and description is String and not description.is_empty():
			copy["prompt"] = description
		normalized.append(copy)
	return normalized


## The BUILD_PROMPT text: the global style plus the first custom row prompt, the item's
## prompt, or the file name without ".png" and with spaces for underscores
static func _base_prompt(spec: Dictionary, global_style: String, row_descriptions: Array) -> String:
	for description in row_descriptions:
		if description is Dictionary and description.get("type") == "custom" and description.get("prompt"):
			return "%s. %s" % [global_style, str(description["prompt"])]
	var prompt = spec.get("prompt", "")
	if prompt:
		return "%s. %s" % [global_style, str(prompt)]
	var file_name := str(spec.get("file_name", "sprite.png"))
	return "%s. %s" % [global_style, file_name.replace(".png", "").replace("_", " ")]


static func _whole_number(value: Variant) -> int:
	return int(value) if value is int or value is float else 0
