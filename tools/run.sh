#!/usr/bin/env bash
# Launch the game, importing the project first when it has never been imported.
#
# Godot resolves `class_name` globals from .godot/global_script_class_cache.cfg,
# and only an import pass (editor open, `--import`, or gd-tools) writes that file.
# A fresh clone therefore fails to start with a wall of
#   SCRIPT ERROR: Parse Error: Identifier "Palette" not declared in the current scope.
# until the project is imported once. This wrapper does that import, then runs.
#
# Usage:
#   tools/run.sh                       # play the game
#   tools/run.sh --headless --quit-after 300
#   GODOT=/path/to/godot tools/run.sh  # non-default engine binary
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
CACHE=".godot/global_script_class_cache.cfg"

cd "$ROOT"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "error: '$GODOT' not found on PATH (set GODOT=/path/to/godot)" >&2
	exit 127
fi

if [[ ! -f "$CACHE" ]]; then
	echo "First run: importing project (writes .godot/)…"
	"$GODOT" --headless --path . --import --quit
	if [[ ! -f "$CACHE" ]]; then
		echo "error: import did not produce $CACHE — the project cannot start" >&2
		exit 1
	fi
fi

exec "$GODOT" --path . "$@"
