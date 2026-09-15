@tool
class_name SpriteFramesWriter
extends RefCounted
## What regenerating a sheet does with its SpriteFrames file.
##
## <sheet>.tres is replaced when the plugin wrote it (it carries
## SpriteFramesBuilder.GENERATED_META) or when overwrite_spriteframes is on. Any other
## existing <sheet>.tres is kept and the new resource goes to <sheet>.generated.tres.
##
## Pure functions: the caller looks at the files.

## No <sheet>.tres yet: write it
const WRITE := "write"
## Replace <sheet>.tres
const UPDATE := "update"
## Keep <sheet>.tres and write <sheet>.generated.tres
const GENERATED := "generated"
## File name ending used instead of .tres for GENERATED
const GENERATED_SUFFIX := ".generated.tres"


## WRITE, UPDATE or GENERATED, for a <sheet>.tres that exists or not and carries the
## plugin's metadata or not, under the overwrite_spriteframes setting
static func decide(existing_has_meta: bool, exists: bool, overwrite_setting: bool) -> String:
	if not exists:
		return WRITE
	if existing_has_meta or overwrite_setting:
		return UPDATE
	return GENERATED


## The file an action writes for a sheet
static func target_path(sheet_path: String, action: String) -> String:
	return sheet_path.get_basename() + (GENERATED_SUFFIX if action == GENERATED else ".tres")
