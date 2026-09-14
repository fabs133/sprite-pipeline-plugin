extends SceneTree
## Headless test runner: runs every test_* method of every res://tests/test_*.gd.
##
## godot --headless --path . --script res://tests/run_tests.gd
## Prints PASS/FAIL per test and exits with 1 if any test failed or raised a script error.

const TESTS_DIR := "res://tests"


class ScriptErrorCounter extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors := ScriptErrorCounter.new()
	OS.add_logger(errors)
	var passed := 0
	var failed := 0

	var files := Array(DirAccess.get_files_at(TESTS_DIR))
	files.sort()
	for file_name: String in files:
		if not (file_name.begins_with("test_") and file_name.ends_with(".gd")):
			continue
		var script: GDScript = load(TESTS_DIR.path_join(file_name))
		if script == null or not script.can_instantiate():
			print("FAIL %s: script does not load" % file_name)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			var test = script.new()
			test.tree = self
			var errors_before := errors.count
			await test.call(test_name)
			if errors.count > errors_before:
				test.failures.append("raised a script error")
			var label := "%s.%s" % [file_name.get_basename(), test_name]
			if test.failures.is_empty():
				print("PASS %s" % label)
				passed += 1
			else:
				print("FAIL %s: %s" % [label, "; ".join(test.failures)])
				failed += 1

	OS.remove_logger(errors)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
