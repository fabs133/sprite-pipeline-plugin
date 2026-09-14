@tool
class_name SpriteEditorIntegration
extends RefCounted
## The plugin's calls into the Godot editor: project settings, FileSystem scans and
## reimports. Everything that needs EditorInterface lives here, and each of those
## functions does nothing outside the editor, so the dock and headless tests can call
## them unconditionally.

const FILTER_SETTING := "rendering/textures/canvas_textures/default_texture_filter"
## The setting's enum is "Nearest,Linear,Linear Mipmap,Nearest Mipmap" (Godot 4.7.2);
## the default is Linear (1). Not CanvasItem.TEXTURE_FILTER_NEAREST, which is 1.
const FILTER_NAMES := ["Nearest", "Linear", "Linear Mipmap", "Nearest Mipmap"]
const FILTER_NEAREST := 0
const FILTER_NEAREST_MIPMAP := 3
const FILTER_DEFAULT := 1
const SCAN_TIMEOUT_MSEC := 10000

const ImportParams := preload("res://addons/sprite_pipeline/import_params.gd")
const SpriteFramesBuilder := preload("res://addons/sprite_pipeline/spriteframes_builder.gd")
const ManifestPaths := preload("res://addons/sprite_pipeline/manifest_paths.gd")
## File name ending used instead of .tres when <sheet>.tres exists and must not be replaced
const GENERATED_SUFFIX := ".generated.tres"


static func is_editor() -> bool:
	return Engine.is_editor_hint()


## The project's default 2D texture filter (index into FILTER_NAMES)
static func project_filter() -> int:
	return int(ProjectSettings.get_setting(FILTER_SETTING, FILTER_DEFAULT))


## True if upscaled 2D textures stay sharp: Nearest, or Nearest Mipmap
static func project_filter_is_nearest() -> bool:
	return project_filter() in [FILTER_NEAREST, FILTER_NEAREST_MIPMAP]


## Set the project's default 2D texture filter to Nearest and save project.godot.
## Returns ERR_UNAVAILABLE outside the editor, so a test run never rewrites a project.
static func set_project_filter_nearest() -> Error:
	if not is_editor():
		return ERR_UNAVAILABLE
	ProjectSettings.set_setting(FILTER_SETTING, FILTER_NEAREST)
	return ProjectSettings.save()


## Start a FileSystem scan without waiting for it
static func scan() -> void:
	var filesystem := _filesystem()
	if filesystem:
		filesystem.scan()


## Scan the FileSystem and wait until the scan is done and each file of imported_paths
## under res:// (files Godot imports, such as PNGs) has been imported, or until
## timeout_msec passed. Returns either way.
static func scan_and_wait(imported_paths := PackedStringArray(), timeout_msec := SCAN_TIMEOUT_MSEC) -> void:
	var filesystem := _filesystem()
	if filesystem == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + timeout_msec
	# scan() does nothing while a scan runs, and that scan may predate the new files
	if _is_busy(filesystem):
		await _wait_until_idle(filesystem, tree, deadline)
	filesystem.scan()
	# The editor imports new files a few frames after the scan ends, so an idle
	# FileSystem alone doesn't mean the files are imported: wait for their .import files
	await tree.process_frame
	var pending := _not_imported(imported_paths)
	while (_is_busy(filesystem) or not pending.is_empty()) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
		pending = _not_imported(pending)
	if _is_busy(filesystem) or not pending.is_empty():
		push_warning("[SpritePipeline] Scan or import of %d generated files not finished after %d s; continuing" % [pending.size(), timeout_msec / 1000])


## Reimport files whose .import settings changed
static func reimport(paths: PackedStringArray) -> void:
	var filesystem := _filesystem()
	if filesystem and not paths.is_empty():
		filesystem.reimport_files(paths)


## Pin SpriteImportParams.DESIRED in the .import file of each PNG, then reimport the files
## whose settings changed (in the editor). A PNG without a .import file, which Godot has
## not imported yet, is skipped with a warning. Returns the paths whose settings changed.
static func pin_import_params(png_paths: PackedStringArray) -> PackedStringArray:
	var changed := PackedStringArray()
	for path in png_paths:
		var import_path := path + ".import"
		var config := ConfigFile.new()
		if not FileAccess.file_exists(import_path) or config.load(import_path) != OK:
			push_warning("[SpritePipeline] %s is not imported yet; its import settings were not pinned" % path)
			continue
		if not ImportParams.apply(config):
			continue
		var err := config.save(import_path)
		if err != OK:
			push_warning("[SpritePipeline] Could not save %s: %s" % [import_path, error_string(err)])
			continue
		changed.append(path)
	reimport(changed)
	return changed


## Save a SpriteFrames resource next to each animated sheet in the manifest. The sheets
## must be imported already, so that loading them returns a texture. An existing
## <sheet>.tres is replaced only with overwrite; otherwise <sheet>.generated.tres is
## written. Returns the paths written.
static func write_spriteframes(manifest: Dictionary, output_root: String, fps: float, loop: bool, overwrite := false) -> PackedStringArray:
	var written := PackedStringArray()
	var results: Array = manifest["results"] if manifest.get("results") is Array else []
	for result in results:
		if not result is Dictionary or not SpriteFramesBuilder.is_animated(result):
			continue
		var sheet_path := ManifestPaths.resolve(output_root, str(result.get("file_path", "")))
		if sheet_path.get_extension().to_lower() != "png":
			continue
		if not ResourceLoader.exists(sheet_path, "Texture2D"):
			push_warning("[SpritePipeline] %s is not imported; no SpriteFrames written for it" % sheet_path)
			continue
		var sheet := ResourceLoader.load(sheet_path, "Texture2D") as Texture2D
		var sprite_frames := SpriteFramesBuilder.build(result, sheet, fps, loop)
		if sprite_frames == null:
			push_warning("[SpritePipeline] %s does not match the frames in its manifest entry; no SpriteFrames written for it" % sheet_path)
			continue
		var target := spriteframes_path(sheet_path, overwrite)
		var err := ResourceSaver.save(sprite_frames, target)
		if err != OK:
			push_warning("[SpritePipeline] Could not save %s: %s" % [target, error_string(err)])
			continue
		written.append(target)
	return written


## Where the SpriteFrames for a sheet go: <sheet>.tres, or <sheet>.generated.tres when
## <sheet>.tres exists and overwrite is off
static func spriteframes_path(sheet_path: String, overwrite: bool) -> String:
	var path := sheet_path.get_basename() + ".tres"
	if overwrite or not FileAccess.file_exists(path):
		return path
	return sheet_path.get_basename() + GENERATED_SUFFIX


## Select a file in the FileSystem dock
static func navigate_to(path: String) -> void:
	if is_editor():
		EditorInterface.get_file_system_dock().navigate_to_path(path)


static func _filesystem() -> EditorFileSystem:
	return EditorInterface.get_resource_filesystem() if is_editor() else null


static func _is_busy(filesystem: EditorFileSystem) -> bool:
	return filesystem.is_scanning() or filesystem.is_importing()


## The paths under res:// that have no .import file yet
static func _not_imported(paths: PackedStringArray) -> PackedStringArray:
	var pending := PackedStringArray()
	for path in paths:
		if path.begins_with("res://") and not FileAccess.file_exists(path + ".import"):
			pending.append(path)
	return pending


## Imports of new files run at the end of a scan, while is_scanning() is still true
static func _wait_until_idle(filesystem: EditorFileSystem, tree: SceneTree, deadline: int) -> void:
	await tree.process_frame
	while _is_busy(filesystem) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
