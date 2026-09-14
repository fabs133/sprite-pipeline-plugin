extends "res://tests/test_case.gd"

const ManifestPaths := preload("res://addons/sprite_pipeline/manifest_paths.gd")
const ROOT := "res://assets/sprites"


func test_relative_path_joins_output_root() -> void:
	check_eq(ManifestPaths.resolve(ROOT, "characters/hero.png"), "res://assets/sprites/characters/hero.png", "relative")
	check_eq(ManifestPaths.resolve(ROOT + "/", "characters/hero/frame_0_1.png"), "res://assets/sprites/characters/hero/frame_0_1.png", "root with trailing slash")


func test_parent_segments_are_rejected() -> void:
	check_eq(ManifestPaths.resolve(ROOT, "../x.png"), "", "../x")
	check_eq(ManifestPaths.resolve(ROOT, "characters/../../x.png"), "", "nested ..")
	check(not ManifestPaths.is_safe_relative("a/../b"), "is_safe_relative rejects ..")


func test_absolute_path_under_root_is_accepted() -> void:
	check_eq(ManifestPaths.resolve(ROOT, "res://assets/sprites/characters/hero.png"), "res://assets/sprites/characters/hero.png", "res:// under root")
	check_eq(ManifestPaths.resolve("C:/game/out", "C:/game/out/misc/a.png"), "C:/game/out/misc/a.png", "OS path under root")


func test_absolute_path_outside_root_is_rejected() -> void:
	check_eq(ManifestPaths.resolve(ROOT, "res://project.godot"), "", "res:// outside root")
	check_eq(ManifestPaths.resolve(ROOT, "res://assets/sprites_other/a.png"), "", "sibling sharing the prefix")
	check_eq(ManifestPaths.resolve(ROOT, "res://assets/sprites/../../plugin.gd"), "", "absolute path that climbs out")
	check_eq(ManifestPaths.resolve(ROOT, "/etc/passwd"), "", "OS path outside root")
	check_eq(ManifestPaths.resolve(ROOT, "user://sprite_cache/x.png"), "", "user:// outside a res:// root")


func test_backslashes_are_rejected() -> void:
	var bs := String.chr(92)
	check_eq(ManifestPaths.resolve(ROOT, "characters" + bs + "hero.png"), "", "relative with backslash")
	check_eq(ManifestPaths.resolve("C:/game/out", "C:" + bs + "game" + bs + "out" + bs + "a.png"), "", "Windows absolute path")
	check(not ManifestPaths.is_safe_relative("a" + bs + "b.png"), "is_safe_relative rejects backslash")


func test_res_root_with_relative_path() -> void:
	check_eq(ManifestPaths.resolve("res://", "characters/hero.png"), "res://characters/hero.png", "res:// root")
	check_eq(ManifestPaths.relative_to("res://", "res://characters/hero.png"), "characters/hero.png", "relative_to res:// root")


func test_relative_to_is_the_inverse_of_resolve() -> void:
	check_eq(ManifestPaths.relative_to(ROOT, "res://assets/sprites/characters/hero/frame_0_0.png"), "characters/hero/frame_0_0.png", "under root")
	check_eq(ManifestPaths.relative_to(ROOT, "res://assets/other/hero.png"), "", "outside root")
	check_eq(ManifestPaths.relative_to(ROOT, ROOT), "", "the root itself")


func test_other_unsafe_paths() -> void:
	for path in ["", "/abs/path.png", "c:x.png", "a:b/c.png"]:
		check_eq(ManifestPaths.resolve(ROOT, path), "", "rejects '%s'" % path)
	check_eq(ManifestPaths.resolve("", "a.png"), "", "empty output_root")
