@tool
class_name SpriteCacheUtils
extends RefCounted
## Utility functions for sprite caching system.
##
## Provides deterministic hash computation for cache keys.

## Compute SHA256 hash of generation inputs for cache key.
## Ensures deterministic ordering for consistent hashes.
static func compute_inputs_hash(queue_data: Array, global_style: String) -> String:
	# Sort queue by category then file_name for deterministic order
	var sorted := queue_data.duplicate(true)
	sorted.sort_custom(func(a, b):
		var cat_a: String = a.get("category", "")
		var cat_b: String = b.get("category", "")
		if cat_a != cat_b:
			return cat_a < cat_b
		var name_a: String = a.get("file_name", "")
		var name_b: String = b.get("file_name", "")
		return name_a < name_b
	)

	# Build canonical form
	var canonical := {
		"global_style": global_style.strip_edges(),
		"queue": sorted
	}

	# Generate SHA256 hash
	var json_str := JSON.stringify(canonical, "", false)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(json_str.to_utf8_buffer())
	return ctx.finish().hex_encode()


## Compute SHA256 of a file's contents
static func compute_file_hash(file_path: String) -> String:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return ""

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)

	while not file.eof_reached():
		var chunk := file.get_buffer(8192)
		if chunk.size() > 0:
			ctx.update(chunk)

	file.close()
	return ctx.finish().hex_encode()
