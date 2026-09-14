extends "res://tests/test_case.gd"
## Expected prompts are copied from sprite-pipeline-backend (app/services/pipeline_runner.py).
## To regenerate one, run this from sprite-pipeline-backend with its venv, passing the item's
## fields to brief():
##
## .venv/Scripts/python.exe -c "
## import asyncio
## from app.services.pipeline_runner import FastHookProvider
## from sprite_pipeline.hooks import HookRequest, HookTaskType as T
## from sprite_pipeline.pipeline import _SpriteSpec
## async def brief(style, **item):
##     fields = {'file_name': 'sprite.png', 'category': 'misc', 'frame_w': None, 'frame_h': None, 'frames': 1, 'layout': 'row', **item}
##     spec = _SpriteSpec(**fields)
##     p = FastHookProvider('unused', 'gpt-image-2', 'medium', 'transparent', 'low')
##     base = await p.run(HookRequest(task_type=T.BUILD_PROMPT, spec=spec, global_style=style))
##     done = await p.run(HookRequest(task_type=T.BUILD_BRIEF, spec=spec, global_style=style, prompt_text=base.text_output))
##     return done.text_output
## print(asyncio.run(brief('pixel art game sprite, clean silhouette', file_name='hero.png', category='characters', prompt='knight idle', frames=4)))
## "

const Prompting := preload("res://addons/sprite_pipeline/prompting.gd")
const STYLE := "pixel art game sprite, clean silhouette"


func test_frames_in_one_row_match_the_backend() -> void:
	var brief := Prompting.build_prompt({"file_name": "hero.png", "category": "characters", "prompt": "knight idle", "frames": 4, "frame_w": 32, "frame_h": 32, "layout": "row"}, STYLE)
	check_eq(brief["grid_size"], 4, "grid size")
	check_eq(brief["prompt"], "STRICT GRID LAYOUT: Create a 1024x1024 pixel spritesheet with EXACTLY 4 rows and 4 columns forming a 4x4 uniform grid. Each cell is EXACTLY 256x256 pixels. Every sprite MUST fit inside its cell boundaries — do NOT let sprites overlap or merge across cells. Rows 1-1 contain sprites with EXACTLY 4 frames per row.  Rows 2-4 are empty (leave transparent/blank). Each frame shows a different pose or animation step. Style: pixel art game sprite, clean silhouette. knight idle. Fully transparent background, no ground shadow, no border, no frame.", "prompt")


func test_single_sprite_named_after_the_file_matches_the_backend() -> void:
	var brief := Prompting.build_prompt({"file_name": "coin.png", "category": "items", "frames": 1, "layout": "row"}, STYLE)
	check_eq(brief["grid_size"], 1, "grid size")
	check_eq(brief["prompt"], "pixel art game sprite, clean silhouette. coin. Single centered sprite, clean edges. Fully transparent background, no ground shadow, no border, no frame.", "prompt")


func test_row_descriptions_match_the_backend() -> void:
	var brief := Prompting.build_prompt({"file_name": "walker.png", "category": "characters", "frames": 3, "rows": 2, "layout": "grid", "row_descriptions": [
		{"type": "custom", "prompt": "walking left"},
		{"type": "variation", "variationOf": 0, "modifier": "facing right"},
	]}, STYLE)
	check_eq(brief["grid_size"], 3, "grid size")
	check_eq(brief["prompt"], "STRICT GRID LAYOUT: Create a 1024x1024 pixel spritesheet with EXACTLY 3 rows and 3 columns forming a 3x3 uniform grid. Each cell is EXACTLY 341x341 pixels. Every sprite MUST fit inside its cell boundaries — do NOT let sprites overlap or merge across cells. Rows 1-2 contain sprites with EXACTLY 3 frames per row. Row 1: walking left. Row 2: variation of row 1, but facing right. Rows 3-3 are empty (leave transparent/blank). Each frame shows a different pose or animation step. Style: pixel art game sprite, clean silhouette. walking left. Fully transparent background, no ground shadow, no border, no frame.", "prompt")


func test_more_rows_than_frames_and_empty_row_prompts_match_the_backend() -> void:
	var brief := Prompting.build_prompt({"file_name": "big_slime.png", "category": "monsters", "prompt": "", "frames": 2, "rows": 4, "layout": "grid", "row_descriptions": [
		{"type": "custom", "prompt": ""},
		{"type": "variation", "variationOf": 1},
	]}, STYLE)
	check_eq(brief["grid_size"], 4, "grid size")
	check_eq(brief["prompt"], "STRICT GRID LAYOUT: Create a 1024x1024 pixel spritesheet with EXACTLY 4 rows and 4 columns forming a 4x4 uniform grid. Each cell is EXACTLY 256x256 pixels. Every sprite MUST fit inside its cell boundaries — do NOT let sprites overlap or merge across cells. Rows 1-4 contain sprites with EXACTLY 2 frames per row. Row 1: same as overall description. Row 2: variation of row 2. Columns 3-4 are empty (leave transparent/blank). Each frame shows a different pose or animation step. Style: pixel art game sprite, clean silhouette. big slime. Fully transparent background, no ground shadow, no border, no frame.", "prompt")


func test_numbers_parsed_from_json_give_the_same_prompt() -> void:
	var from_yaml := Prompting.build_prompt({"file_name": "hero.png", "prompt": "knight idle", "frames": 4}, STYLE)
	var from_json := Prompting.build_prompt({"file_name": "hero.png", "prompt": "knight idle", "frames": 4.0, "rows": 1.0}, STYLE)
	check_eq(from_json, from_yaml, "float fields")


func test_description_becomes_the_prompt() -> void:
	var queue := [
		{"file_name": "a.png", "description": "red slime"},
		{"file_name": "b.png", "prompt": "blue slime", "description": "not used"},
		{"file_name": "c.png"},
	]
	var normalized := Prompting.normalize_queue(queue)
	check_eq(normalized[0].get("prompt"), "red slime", "description copied to prompt")
	check_eq(normalized[1].get("prompt"), "blue slime", "an existing prompt wins")
	check(not normalized[2].has("prompt"), "nothing added without a description")
	check(not queue[0].has("prompt"), "input queue unchanged")
