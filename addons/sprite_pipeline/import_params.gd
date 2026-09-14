@tool
class_name SpriteImportParams
extends RefCounted
## Import settings for generated pixel-art PNGs: the [params] of a texture's .import file
## that the plugin pins, and the PNGs of a manifest to pin them on.
##
## Pure functions: no editor calls, no file access.

const ManifestPaths := preload("res://addons/sprite_pipeline/manifest_paths.gd")

const SECTION := "params"
## Keys and enum values as Godot 4.7.2's texture importer writes them for a PNG
const DESIRED := {
	"compress/mode": 0,  # Lossless
	"mipmaps/generate": false,
	"detect_3d/compress_to": 0,  # Disabled: never switch to VRAM compression when used in 3D
}


## The DESIRED entries whose value differs in current; a missing key differs too
static func diff(current: Dictionary) -> Dictionary:
	var changes := {}
	for key in DESIRED:
		var value = current.get(key)
		if typeof(value) != typeof(DESIRED[key]) or value != DESIRED[key]:
			changes[key] = DESIRED[key]
	return changes


## Set the differing DESIRED keys in the [params] section, leaving every other key as it
## is. Returns true if anything changed.
static func apply(config: ConfigFile) -> bool:
	var current := {}
	if config.has_section(SECTION):
		for key in config.get_section_keys(SECTION):
			current[key] = config.get_value(SECTION, key)
	var changes := diff(current)
	for key in changes:
		config.set_value(SECTION, key, changes[key])
	return not changes.is_empty()


## Every PNG a manifest lists: each result's sheet (file_path) and frames (frame_paths),
## resolved under output_root. Unsafe paths and other file types are left out.
static func manifest_png_paths(manifest: Dictionary, output_root: String) -> PackedStringArray:
	var paths := PackedStringArray()
	var results: Array = manifest["results"] if manifest.get("results") is Array else []
	for result in results:
		if not result is Dictionary:
			continue
		var relative_paths := [result.get("file_path")]
		if result.get("frame_paths") is Array:
			relative_paths.append_array(result["frame_paths"])
		for relative in relative_paths:
			if not relative is String:
				continue
			var path := ManifestPaths.resolve(output_root, relative)
			if path.get_extension().to_lower() == "png" and not path in paths:
				paths.append(path)
	return paths
