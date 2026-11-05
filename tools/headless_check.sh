#!/usr/bin/env bash
# Headless project check. Owner: Lane A (task A-02). Used by CI and locally before a PR.
#
#   GODOT=/path/to/godot bash tools/headless_check.sh
#
# Windows (Git Bash, Steam build):
#   GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" bash tools/headless_check.sh
#
# Fails if the import or a 5-frame run prints SCRIPT ERROR / Parse Error, if any project script
# (outside addons/) fails to load, or if any tests/<lane>/test_*.gd fails. Missing res://assets/ dependencies (no submodule access) are
# expected and do not fail the check.
set -u

GODOT_BIN="${GODOT:-godot}"
# A stuck Godot (e.g. a script that never calls quit) must not hang CI forever.
GODOT() { timeout 300 "$GODOT_BIN" "$@"; }
cd "$(dirname "$0")/.."

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

echo "== import"
GODOT --headless --path . --import >"$log" 2>&1
echo "== run 5 frames"
GODOT --headless --path . --quit-after 5 >>"$log" 2>&1

if grep -nE "SCRIPT ERROR|Parse Error" "$log"; then
	echo ""
	echo "FAILED: script errors found (full log below)"
	cat "$log"
	exit 1
fi
echo "no script errors"

echo "== load every script"
GODOT --headless --path . --script res://tools/check_scripts.gd 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"
if [ "$status" -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
	echo "FAILED: some scripts do not load"
	exit 1
fi

echo "== tests"
GODOT --headless --path . --script res://tests/run_tests.gd 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"
if [ "$status" -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
	echo "FAILED: tests"
	exit 1
fi
echo "OK"
