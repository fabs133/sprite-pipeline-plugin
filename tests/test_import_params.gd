extends "res://tests/test_case.gd"

const ImportParams := preload("res://addons/sprite_pipeline/import_params.gd")
const EditorIntegration := preload("res://addons/sprite_pipeline/editor_integration.gd")

## hero.png.import as Godot 4.7.2 wrote it for a new 128x32 PNG
const GODOT_IMPORT_FILE := """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://dhfwf3btyt16b"
path="res://.godot/imported/hero.png-8027e51eb4de7876c648b7bf49af1e52.ctex"
metadata={
"vram_texture": false
}

[deps]

source_file="res://assets/sprites/characters/hero.png"
dest_files=["res://.godot/imported/hero.png-8027e51eb4de7876c648b7bf49af1e52.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


func _params(text: String) -> Dictionary:
	var config := ConfigFile.new()
	config.parse(text)
	var params := {}
	for key in config.get_section_keys("params"):
		params[key] = config.get_value("params", key)
	return params


func test_godot_defaults_differ_only_in_3d_detection() -> void:
	check_eq(ImportParams.diff(_params(GODOT_IMPORT_FILE)), {"detect_3d/compress_to": 0}, "diff of a fresh import")


func test_no_diff_on_pinned_params() -> void:
	var params := _params(GODOT_IMPORT_FILE)
	params["detect_3d/compress_to"] = 0
	check_eq(ImportParams.diff(params), {}, "already pinned")


func test_diff_on_lossy_compression_and_mipmaps() -> void:
	var params := _params(GODOT_IMPORT_FILE)
	params["compress/mode"] = 1
	params["mipmaps/generate"] = true
	params["detect_3d/compress_to"] = 0
	check_eq(ImportParams.diff(params), {"compress/mode": 0, "mipmaps/generate": false}, "lossy with mipmaps")


func test_missing_keys_differ() -> void:
	check_eq(ImportParams.diff({}), ImportParams.DESIRED, "empty params")
	check_eq(ImportParams.diff({"compress/mode": 0, "mipmaps/generate": false}), {"detect_3d/compress_to": 0}, "one key missing")
	check_eq(ImportParams.diff({"compress/mode": 0.0, "mipmaps/generate": false, "detect_3d/compress_to": 0}), {"compress/mode": 0}, "a float is not the int")


func test_apply_leaves_unrelated_keys_untouched() -> void:
	var config := ConfigFile.new()
	config.parse(GODOT_IMPORT_FILE)
	check(ImportParams.apply(config), "a fresh import changes")
	check_eq(config.get_value("params", "detect_3d/compress_to"), 0, "pinned")
	check_eq(config.get_value("params", "compress/lossy_quality"), 0.7, "unrelated param kept")
	check_eq(config.get_value("params", "process/fix_alpha_border"), true, "unrelated param kept")
	check_eq(config.get_value("remap", "uid"), "uid://dhfwf3btyt16b", "remap section kept")
	check_eq(config.get_value("deps", "source_file"), "res://assets/sprites/characters/hero.png", "deps section kept")
	check(not ImportParams.apply(config), "a second apply changes nothing")

	var empty := ConfigFile.new()
	check(ImportParams.apply(empty), "a file without params gets them")
	check_eq(empty.get_section_keys("params").size(), ImportParams.DESIRED.size(), "only the pinned keys")


func test_manifest_png_paths() -> void:
	var manifest := {"results": [
		{"file_path": "characters/hero.png", "frame_paths": ["characters/hero/frame_0_0.png", "characters/hero/frame_0_1.png"], "raw_path": "characters/hero_raw.png"},
		{"file_path": "misc/still.PNG", "frame_paths": []},
		{"file_path": "../escape.png"},
		{"file_path": "misc/notes"},
		{"file_path": "characters/hero.png"},
		"not a result",
	]}
	check_eq(ImportParams.manifest_png_paths(manifest, "res://assets/sprites"), PackedStringArray([
		"res://assets/sprites/characters/hero.png",
		"res://assets/sprites/characters/hero/frame_0_0.png",
		"res://assets/sprites/characters/hero/frame_0_1.png",
		"res://assets/sprites/misc/still.PNG",
	]), "sheets and frames, no raw sheet, unsafe path, other file or duplicate")
	check_eq(ImportParams.manifest_png_paths({}, "res://assets/sprites"), PackedStringArray(), "no results")


func test_pin_import_params_rewrites_only_what_differs() -> void:
	var root := make_temp_dir("pin_import")
	var fresh := root.path_join("hero.png")
	var pinned := root.path_join("pinned.png")
	var not_imported := root.path_join("new.png")
	_write(fresh + ".import", GODOT_IMPORT_FILE)
	_write(pinned + ".import", GODOT_IMPORT_FILE.replace("detect_3d/compress_to=1", "detect_3d/compress_to=0"))
	var pinned_before := FileAccess.get_file_as_string(pinned + ".import")

	var changed := EditorIntegration.pin_import_params(PackedStringArray([fresh, pinned, not_imported]))
	check_eq(changed, PackedStringArray([fresh]), "only the fresh import changed")
	var config := ConfigFile.new()
	check_eq(config.load(fresh + ".import"), OK, "rewritten file parses")
	check_eq(config.get_value("params", "detect_3d/compress_to"), 0, "pinned on disk")
	check_eq(config.get_value("remap", "path"), "res://.godot/imported/hero.png-8027e51eb4de7876c648b7bf49af1e52.ctex", "remap kept on disk")
	check_eq(FileAccess.get_file_as_string(pinned + ".import"), pinned_before, "an already pinned file is not rewritten")
	check(not FileAccess.file_exists(not_imported + ".import"), "no .import created for a file Godot has not imported")
	remove_dir(root)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
