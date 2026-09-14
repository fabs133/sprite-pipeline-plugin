# Run the plugin's headless GDScript tests (tests/test_*.gd)
# Usage: .\scripts\test.ps1
# Set $env:GODOT to a Godot 4.5+ executable if "godot" is not on PATH
# (on Windows use the *_console.exe build so the output shows in the terminal).

$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$repoRoot = Split-Path -Parent $PSScriptRoot

& $godot --headless --path $repoRoot --script res://tests/run_tests.gd
exit $LASTEXITCODE
