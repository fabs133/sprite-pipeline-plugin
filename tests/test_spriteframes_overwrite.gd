extends "res://tests/test_case.gd"
## What regenerating a sheet does with its existing SpriteFrames file.

const Writer := preload("res://addons/sprite_pipeline/spriteframes_writer.gd")


func test_without_a_tres_it_is_written() -> void:
	check_eq(Writer.decide(false, false, false), Writer.WRITE, "no .tres")
	check_eq(Writer.decide(false, false, true), Writer.WRITE, "no .tres, overwrite on")
	check_eq(Writer.decide(true, false, false), Writer.WRITE, "metadata of a missing file doesn't count")


func test_a_tres_the_plugin_wrote_is_updated() -> void:
	check_eq(Writer.decide(true, true, false), Writer.UPDATE, "plugin's .tres, overwrite off")
	check_eq(Writer.decide(true, true, true), Writer.UPDATE, "plugin's .tres, overwrite on")


func test_another_tres_is_kept_unless_overwrite_is_on() -> void:
	check_eq(Writer.decide(false, true, false), Writer.GENERATED, "other .tres, overwrite off")
	check_eq(Writer.decide(false, true, true), Writer.UPDATE, "other .tres, overwrite on")


func test_target_paths() -> void:
	var sheet := "res://assets/sprites/characters/hero.png"
	check_eq(Writer.target_path(sheet, Writer.WRITE), "res://assets/sprites/characters/hero.tres", "write")
	check_eq(Writer.target_path(sheet, Writer.UPDATE), "res://assets/sprites/characters/hero.tres", "update")
	check_eq(Writer.target_path(sheet, Writer.GENERATED), "res://assets/sprites/characters/hero.generated.tres", "generated")
