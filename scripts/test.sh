#!/bin/bash
# Run the plugin's headless GDScript tests (tests/test_*.gd)
# Usage: ./scripts/test.sh
# Set GODOT to a Godot 4.5+ executable if "godot" is not on PATH.

set -e

cd "$(dirname "$0")/.."
exec "${GODOT:-godot}" --headless --path . --script res://tests/run_tests.gd
