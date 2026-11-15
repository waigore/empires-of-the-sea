#!/usr/bin/env bash
# Bake short git SHA + last-commit UTC into scripts/platform/build_identity.gd.
#
# Run before any Godot export (desktop or mobile) so the main-menu caption can
# show `version X.Y.Z · <sha> · yyyyMMdd-HHmm` without a .git tree at runtime.
# Pass --restore to rewrite the empty placeholders (CI cleanup).
#
# Usage:
#   tools/bake_build_identity.sh
#   tools/bake_build_identity.sh --restore
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/scripts/platform/build_identity.gd"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "$TARGET" ]] || fail "missing $TARGET"

write_identity() {
  local sha="$1"
  local utc="$2"
  cat >"$TARGET" <<EOF
class_name BuildIdentity
extends RefCounted
## Export-time bake of the short git SHA and last-commit UTC stamp.
## Empty in the repo and in editor/dev runs. \`tools/bake_build_identity.sh\`
## fills these before export; CI restores the empty placeholders afterward.

const GIT_SHA: String = "${sha}"
const COMMIT_UTC: String = "${utc}"


static func is_baked() -> bool:
	return not GIT_SHA.is_empty() and not COMMIT_UTC.is_empty()
EOF
}

if [[ "${1:-}" == "--restore" ]]; then
  write_identity "" ""
  echo "Restored empty BuildIdentity placeholders"
  exit 0
fi

command -v git >/dev/null 2>&1 || fail "git is required to bake build identity"
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not a git work tree"

sha="$(git -C "$ROOT" rev-parse --short=7 HEAD)"
# TZ=UTC + format: stays portable on older git (format-utc: needs 2.29+).
utc="$(TZ=UTC git -C "$ROOT" log -1 --format=%cd --date=format:%Y%m%d-%H%M)"
[[ "$sha" =~ ^[0-9a-f]{4,12}$ ]] || fail "unexpected short SHA '$sha'"
[[ "$utc" =~ ^[0-9]{8}-[0-9]{4}$ ]] || fail "unexpected commit UTC '$utc'"

write_identity "$sha" "$utc"
echo "Baked BuildIdentity git_sha=${sha} commit_utc=${utc}"
