@tool
class_name ManifestPaths
extends RefCounted
## Resolves manifest paths against the output directory.
##
## Manifest v2 (Pool and BYOK) stores paths relative to output_root; manifests
## written by BYOK before 1.1.0 stored absolute paths. Pure functions: no file
## access, no logging.


## Resolve a manifest file_path (relative in v2, absolute in legacy BYOK manifests)
## to an absolute path under output_root.
## Returns "" if the path is unsafe or escapes output_root.
static func resolve(output_root: String, file_path: String) -> String:
	if output_root.is_empty() or file_path.is_empty() or String.chr(92) in file_path:
		return ""
	if file_path.is_absolute_path():
		var relative := relative_to(output_root, file_path)
		return "" if relative.is_empty() else output_root.simplify_path().path_join(relative)
	if not is_safe_relative(file_path):
		return ""
	return output_root.simplify_path().path_join(file_path)


## True if a server-supplied relative path cannot escape the directory it is joined to:
## not empty, no leading "/", no backslash, no ":" and no ".." segment.
static func is_safe_relative(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or String.chr(92) in path or ":" in path:
		return false
	return not ".." in path.split("/")


## Inverse of resolve: abs_path relative to output_root, or "" if it is not inside it.
static func relative_to(output_root: String, abs_path: String) -> String:
	if output_root.is_empty() or abs_path.is_empty():
		return ""
	if String.chr(92) in output_root or String.chr(92) in abs_path:
		return ""
	var root := output_root.simplify_path()
	var prefix := root if root.ends_with("/") else root + "/"
	var path := abs_path.simplify_path()
	if not path.begins_with(prefix):
		return ""
	var relative := path.substr(prefix.length())
	return relative if is_safe_relative(relative) else ""
