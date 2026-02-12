@tool
extends RefCounted
## Local sprite cache with LRU eviction and disk persistence.
##
## Caches generated sprites to avoid redundant API calls. Uses inputs_hash
## (SHA256 of queue + style) as cache keys. Supports configurable max size
## with LRU eviction policy.

signal cache_updated(stats: Dictionary)

const INDEX_FILE := "index.json"
const DEFAULT_CACHE_DIR := "user://sprite_cache"
const DEFAULT_MAX_SIZE_MB := 500.0
const INDEX_VERSION := 1

## Cache entry structure stored in index
class CacheEntry:
	var inputs_hash: String
	var manifest_path: String
	var sprite_paths: Array[String]
	var total_size_bytes: int
	var created_at: int
	var last_accessed: int

	func _init(hash: String = "") -> void:
		inputs_hash = hash
		manifest_path = ""
		sprite_paths = []
		total_size_bytes = 0
		created_at = Time.get_unix_time_from_system()
		last_accessed = created_at

	func to_dict() -> Dictionary:
		return {
			"inputs_hash": inputs_hash,
			"manifest_path": manifest_path,
			"sprite_paths": sprite_paths,
			"total_size_bytes": total_size_bytes,
			"created_at": created_at,
			"last_accessed": last_accessed
		}

	static func from_dict(data: Dictionary) -> CacheEntry:
		var entry := CacheEntry.new(data.get("inputs_hash", ""))
		entry.manifest_path = data.get("manifest_path", "")
		entry.sprite_paths = Array(data.get("sprite_paths", []), TYPE_STRING, "", null)
		entry.total_size_bytes = data.get("total_size_bytes", 0)
		entry.created_at = data.get("created_at", 0)
		entry.last_accessed = data.get("last_accessed", 0)
		return entry


## Configuration
var max_size_mb: float = DEFAULT_MAX_SIZE_MB:
	set(value):
		max_size_mb = clampf(value, 100.0, 10000.0)
var cache_dir: String = DEFAULT_CACHE_DIR
var enabled: bool = true

## State
var _index: Dictionary = {}  # inputs_hash -> CacheEntry
var _total_size_bytes: int = 0
var _is_loaded: bool = false

## Session statistics
var _session_hits: int = 0
var _session_misses: int = 0


func _init(dir: String = DEFAULT_CACHE_DIR, max_mb: float = DEFAULT_MAX_SIZE_MB) -> void:
	cache_dir = dir
	max_size_mb = max_mb


## Initialize cache - load index from disk
func initialize() -> Error:
	if not enabled:
		return OK

	# Ensure cache directory exists
	var dir := DirAccess.open("user://")
	if not dir:
		push_error("[SpriteCache] Cannot access user:// directory")
		return ERR_CANT_CREATE

	var cache_path := cache_dir.replace("user://", "")
	if not dir.dir_exists(cache_path):
		var err := dir.make_dir_recursive(cache_path)
		if err != OK:
			push_error("[SpriteCache] Failed to create cache directory: %s" % error_string(err))
			return err

	# Load index
	var index_path := cache_dir.path_join(INDEX_FILE)
	if FileAccess.file_exists(index_path):
		var err := _load_index(index_path)
		if err != OK:
			push_warning("[SpriteCache] Failed to load index, starting fresh")
			_index.clear()
			_total_size_bytes = 0

	_is_loaded = true
	print_debug("[SpriteCache] Initialized: %d entries, %.2f MB" % [_index.size(), _total_size_bytes / 1048576.0])
	return OK


## Check if a generation result is cached
func has_cached(inputs_hash: String) -> bool:
	if not enabled or not _is_loaded:
		return false
	return _index.has(inputs_hash)


## Get cached result by inputs_hash
## Returns null if not found, otherwise returns manifest Dictionary
func get_from_cache(inputs_hash: String) -> Variant:
	if not enabled or not _is_loaded:
		_session_misses += 1
		return null

	if not _index.has(inputs_hash):
		_session_misses += 1
		print_debug("[SpriteCache] MISS: %s" % inputs_hash.substr(0, 16))
		return null

	var entry: CacheEntry = _index[inputs_hash]

	# Verify manifest file exists
	if not FileAccess.file_exists(entry.manifest_path):
		push_warning("[SpriteCache] Manifest missing for %s, removing from cache" % inputs_hash.substr(0, 16))
		_remove_entry(inputs_hash)
		_session_misses += 1
		return null

	# Load and return manifest
	var manifest_text := FileAccess.get_file_as_string(entry.manifest_path)
	var json := JSON.new()
	if json.parse(manifest_text) != OK:
		push_warning("[SpriteCache] Invalid manifest JSON for %s" % inputs_hash.substr(0, 16))
		_remove_entry(inputs_hash)
		_session_misses += 1
		return null

	# Update last accessed time
	entry.last_accessed = Time.get_unix_time_from_system()
	_save_index()

	_session_hits += 1
	print_debug("[SpriteCache] HIT: %s" % inputs_hash.substr(0, 16))
	cache_updated.emit(get_stats())

	return json.get_data()


## Add generation result to cache
func add_to_cache(inputs_hash: String, manifest: Dictionary, sprite_files: Array) -> Error:
	if not enabled or not _is_loaded:
		return ERR_UNCONFIGURED

	# Create entry directory
	var entry_dir := cache_dir.path_join(inputs_hash.substr(0, 16))
	var dir := DirAccess.open(cache_dir)
	if not dir:
		return ERR_CANT_CREATE

	if not dir.dir_exists(inputs_hash.substr(0, 16)):
		var err := dir.make_dir(inputs_hash.substr(0, 16))
		if err != OK:
			push_error("[SpriteCache] Failed to create entry directory: %s" % error_string(err))
			return err

	var entry := CacheEntry.new(inputs_hash)
	var total_size: int = 0

	# Save manifest
	var manifest_path := entry_dir.path_join("manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if not manifest_file:
		push_error("[SpriteCache] Failed to write manifest: %s" % manifest_path)
		return ERR_CANT_CREATE

	var manifest_json := JSON.stringify(manifest, "\t")
	manifest_file.store_string(manifest_json)
	manifest_file.close()
	total_size += manifest_json.length()
	entry.manifest_path = manifest_path

	# Copy sprite files to cache
	for sprite_path in sprite_files:
		if not FileAccess.file_exists(sprite_path):
			continue

		var sprite_name: String = sprite_path.get_file()
		var cached_sprite_path := entry_dir.path_join(sprite_name)

		# Copy file
		var source := FileAccess.open(sprite_path, FileAccess.READ)
		if not source:
			continue

		var dest := FileAccess.open(cached_sprite_path, FileAccess.WRITE)
		if not dest:
			source.close()
			continue

		var content := source.get_buffer(source.get_length())
		dest.store_buffer(content)
		total_size += content.size()

		source.close()
		dest.close()

		entry.sprite_paths.append(cached_sprite_path)

	entry.total_size_bytes = total_size

	# Add to index
	_index[inputs_hash] = entry
	_total_size_bytes += total_size

	# Evict if over limit
	_evict_if_needed()

	# Save index
	_save_index()

	print_debug("[SpriteCache] Added: %s (%.2f KB)" % [inputs_hash.substr(0, 16), total_size / 1024.0])
	cache_updated.emit(get_stats())

	return OK


## Remove entry from cache
func _remove_entry(inputs_hash: String) -> void:
	if not _index.has(inputs_hash):
		return

	var entry: CacheEntry = _index[inputs_hash]

	# Delete files
	if FileAccess.file_exists(entry.manifest_path):
		DirAccess.remove_absolute(entry.manifest_path)

	for sprite_path in entry.sprite_paths:
		if FileAccess.file_exists(sprite_path):
			DirAccess.remove_absolute(sprite_path)

	# Try to remove entry directory
	var entry_dir := cache_dir.path_join(inputs_hash.substr(0, 16))
	DirAccess.remove_absolute(entry_dir)

	_total_size_bytes -= entry.total_size_bytes
	_index.erase(inputs_hash)


## Evict LRU entries until under size limit
func _evict_if_needed() -> void:
	var max_bytes: int = int(max_size_mb * 1048576)

	while _total_size_bytes > max_bytes and _index.size() > 0:
		# Find LRU entry
		var lru_hash: String = ""
		var lru_time: int = Time.get_unix_time_from_system()

		for hash in _index:
			var entry: CacheEntry = _index[hash]
			if entry.last_accessed < lru_time:
				lru_time = entry.last_accessed
				lru_hash = hash

		if lru_hash.is_empty():
			break

		print_debug("[SpriteCache] Evicting LRU: %s" % lru_hash.substr(0, 16))
		_remove_entry(lru_hash)


## Clear entire cache
func clear_cache() -> Error:
	if not _is_loaded:
		return ERR_UNCONFIGURED

	# Remove all entries
	var hashes := _index.keys().duplicate()
	for hash in hashes:
		_remove_entry(hash)

	_index.clear()
	_total_size_bytes = 0
	_session_hits = 0
	_session_misses = 0

	_save_index()
	cache_updated.emit(get_stats())

	print_debug("[SpriteCache] Cache cleared")
	return OK


## Get cache statistics
func get_stats() -> Dictionary:
	var total_requests := _session_hits + _session_misses
	var hit_rate: float = 0.0
	if total_requests > 0:
		hit_rate = float(_session_hits) / float(total_requests) * 100.0

	return {
		"enabled": enabled,
		"entry_count": _index.size(),
		"total_size_bytes": _total_size_bytes,
		"total_size_mb": _total_size_bytes / 1048576.0,
		"max_size_mb": max_size_mb,
		"usage_percent": (_total_size_bytes / 1048576.0) / max_size_mb * 100.0 if max_size_mb > 0 else 0.0,
		"session_hits": _session_hits,
		"session_misses": _session_misses,
		"session_total": total_requests,
		"hit_rate_percent": hit_rate
	}


## Get list of all cached entries (for UI display)
func get_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for hash in _index:
		var entry: CacheEntry = _index[hash]
		entries.append({
			"inputs_hash": entry.inputs_hash,
			"size_bytes": entry.total_size_bytes,
			"created_at": entry.created_at,
			"last_accessed": entry.last_accessed,
			"sprite_count": entry.sprite_paths.size()
		})

	# Sort by last accessed (most recent first)
	entries.sort_custom(func(a, b): return a.last_accessed > b.last_accessed)
	return entries


## Load index from disk
func _load_index(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ERR_FILE_NOT_FOUND

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		return ERR_PARSE_ERROR

	var data: Dictionary = json.get_data()

	# Check version
	var version: int = data.get("version", 0)
	if version != INDEX_VERSION:
		push_warning("[SpriteCache] Index version mismatch, rebuilding")
		return ERR_INVALID_DATA

	# Load entries
	_index.clear()
	_total_size_bytes = 0

	var entries: Array = data.get("entries", [])
	for entry_data in entries:
		var entry := CacheEntry.from_dict(entry_data)

		# Verify entry files still exist
		if FileAccess.file_exists(entry.manifest_path):
			_index[entry.inputs_hash] = entry
			_total_size_bytes += entry.total_size_bytes
		else:
			push_warning("[SpriteCache] Skipping orphaned entry: %s" % entry.inputs_hash.substr(0, 16))

	return OK


## Save index to disk
func _save_index() -> Error:
	var index_path := cache_dir.path_join(INDEX_FILE)

	var entries := []
	for hash in _index:
		var entry: CacheEntry = _index[hash]
		entries.append(entry.to_dict())

	var data := {
		"version": INDEX_VERSION,
		"updated_at": Time.get_unix_time_from_system(),
		"entries": entries
	}

	var file := FileAccess.open(index_path, FileAccess.WRITE)
	if not file:
		push_error("[SpriteCache] Failed to save index")
		return ERR_CANT_CREATE

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	return OK
