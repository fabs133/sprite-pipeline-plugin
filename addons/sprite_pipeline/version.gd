@tool
class_name SpritePipelineVersion
extends RefCounted
## Single source of truth for the plugin and protocol versions.
##
## plugin.cfg and asset.cfg carry the same plugin version; scripts/validate.ps1
## fails if they disagree. Other scripts preload this file instead of using the
## class name, because addons/sprite_pipeline/.gdignore keeps it out of the
## global class list.

const PLUGIN := "1.1.0"
const PROTOCOL := "2.0.0"
