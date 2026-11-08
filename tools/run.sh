#!/usr/bin/env bash
# Launch the game, importing the project first when it needs it.
#
# Godot resolves `class_name` globals from .godot/global_script_class_cache.cfg,
# and only an import pass (editor open, `--import`, or gd-tools) writes that file.
# Without a current cache, startup fails with a wall of
#   SCRIPT ERROR: Parse Error: Identifier "Palette" not declared in the current scope.
# That happens on a fresh clone, and also whenever a pull or branch switch adds,
# renames or moves a `class_name` script while a previous cache is still on disk.
# This wrapper re-imports in both cases, then runs.
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

# The cache is current only when it exists, no script has changed since it was
# written, and every script it points at is still there.
cache_is_current() {
	[[ -f "$CACHE" ]] || return 1
	if find scripts scenes ui autoload -name '*.gd' -newer "$CACHE" -print -quit 2>/dev/null |
		grep -q .; then
		return 1
	fi
	while IFS= read -r path; do
		[[ -f "${path#res://}" ]] || return 1
	done < <(grep -o 'res://[^"]*\.gd' "$CACHE" | sort -u)
	return 0
}

if ! cache_is_current; then
	if [[ -f "$CACHE" ]]; then
		echo "Import cache is stale: re-importing…"
	else
		echo "First run: importing project (writes .godot/)…"
	fi
	"$GODOT" --headless --path . --import --quit
	if [[ ! -f "$CACHE" ]]; then
		echo "error: import did not produce $CACHE — the project cannot start" >&2
		exit 1
	fi
fi

exec "$GODOT" --path . "$@"
