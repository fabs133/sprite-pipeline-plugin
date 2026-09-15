@tool
class_name SpriteSettingsStore
extends RefCounted
## Writes settings into a ConfigFile without dropping the keys the caller doesn't own,
## such as [dev] enable_automation or lines added by hand.


## Load the file at path, set values ({section: {key: value}}) and save it. A null value
## removes its key. A missing file starts empty; a file that doesn't parse is replaced,
## with a warning.
static func save(path: String, values: Dictionary) -> Error:
	var config := ConfigFile.new()
	var err := config.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("[SpritePipeline] Could not read %s (%s); writing the settings over it" % [path, error_string(err)])
		config = ConfigFile.new()
	for section: String in values:
		var keys: Dictionary = values[section]
		for key: String in keys:
			config.set_value(section, key, keys[key])
	return config.save(path)
