extends RefCounted
## Base class for headless tests: checks record failures instead of stopping the run.

var failures: Array[String] = []
## The runner's SceneTree, for timers and nodes in async tests
var tree: SceneTree


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected %s, got %s" % [message, var_to_str(expected), var_to_str(actual)])
