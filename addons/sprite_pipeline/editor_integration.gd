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


## Scan the FileSystem and wait until the scan and the imports it starts are done, or
## until timeout_msec passed. Returns either way.
static func scan_and_wait(timeout_msec := SCAN_TIMEOUT_MSEC) -> void:
	var filesystem := _filesystem()
	if filesystem == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + timeout_msec
	# scan() does nothing while a scan runs, and that scan may predate the new files
	if _is_busy(filesystem):
		await _wait_until_idle(filesystem, tree, deadline)
	filesystem.scan()
	await _wait_until_idle(filesystem, tree, deadline)
	if _is_busy(filesystem):
		push_warning("[SpritePipeline] FileSystem scan still running after %d s; continuing" % (timeout_msec / 1000))


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


static func _filesystem() -> EditorFileSystem:
	return EditorInterface.get_resource_filesystem() if is_editor() else null


static func _is_busy(filesystem: EditorFileSystem) -> bool:
	return filesystem.is_scanning() or filesystem.is_importing()


## Imports of new files run at the end of a scan, while is_scanning() is still true
static func _wait_until_idle(filesystem: EditorFileSystem, tree: SceneTree, deadline: int) -> void:
	await tree.process_frame
	while _is_busy(filesystem) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
