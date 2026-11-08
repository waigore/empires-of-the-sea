#!/usr/bin/env bash
# Export the project as a debug-signed Android APK (Godot preset "Android Debug").
#
# CI only. Refuses to run elsewhere because it rewrites
# ~/.config/godot/editor_settings-4.7.tres for this Godot 4.7 export.
#
# Required environment:
#   ANDROID_EXPORT_CI=1
#   JAVA_HOME                    JDK root (bin/java present)
#   ANDROID_SDK_ROOT             SDK root (platform-tools/adb and build-tools present)
#   GODOT_ANDROID_KEYSTORE_DEBUG_PATH
#   GODOT_ANDROID_KEYSTORE_DEBUG_USER
#   GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD
# Optional:
#   ANDROID_VERSION_CODE         integer versionCode (default 1)
#   ANDROID_VERSION_NAME         versionName; longer than 12 characters is truncated
#
# Usage: export_android_debug.sh <output.apk>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT"
PRESET="$PROJECT/export_presets.cfg"
OUTPUT="${1:-}"

fail() {
  echo "error: $*" >&2
  [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::error::$*"
  exit 1
}

[[ "${ANDROID_EXPORT_CI:-}" == "1" ]] || fail "ANDROID_EXPORT_CI=1 is required; this script rewrites Godot editor settings"
[[ -n "$OUTPUT" ]] || fail "usage: export_android_debug.sh <output.apk>"
[[ -f "$PRESET" ]] || fail "missing $PRESET"
command -v godot >/dev/null 2>&1 || fail "godot is not on PATH"
[[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]] || fail "JAVA_HOME must contain bin/java"
[[ -n "${ANDROID_SDK_ROOT:-}" && -x "${ANDROID_SDK_ROOT}/platform-tools/adb" ]] || fail "ANDROID_SDK_ROOT must contain platform-tools/adb"
[[ -d "${ANDROID_SDK_ROOT}/build-tools" ]] || fail "ANDROID_SDK_ROOT is missing build-tools"
[[ -n "${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-}" && -f "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" ]] || fail "debug keystore is missing"
[[ -n "${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-}" && -n "${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-}" ]] || fail "debug keystore user and password are required"

code="${ANDROID_VERSION_CODE:-1}"
name="${ANDROID_VERSION_NAME:-}"
[[ "$code" =~ ^[1-9][0-9]*$ ]] || fail "ANDROID_VERSION_CODE must be a positive integer, got '$code'"
[[ ${#name} -le 12 ]] || name="${name:0:12}"

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
settings="$config_home/godot/editor_settings-4.7.tres"
mkdir -p "$(dirname "$settings")"
cat >"$settings" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$JAVA_HOME"
export/android/android_sdk_path = "$ANDROID_SDK_ROOT"
export/android/debug_keystore = "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH"
export/android/debug_keystore_user = "$GODOT_ANDROID_KEYSTORE_DEBUG_USER"
export/android/debug_keystore_pass = "$GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD"
EOF

backup="$(mktemp)"
cp "$PRESET" "$backup"
cleanup() {
  local status=$?
  cp "$backup" "$PRESET"
  rm -f "$backup"
  exit "$status"
}
trap cleanup EXIT

sed -i "s|^version/code=.*|version/code=${code}|" "$PRESET"
sed -i "s|^version/name=.*|version/name=\"${name}\"|" "$PRESET"
grep -q "^version/code=${code}$" "$PRESET" || fail "export preset is missing version/code"
grep -q "^version/name=\"${name}\"$" "$PRESET" || fail "export preset is missing version/name"

mkdir -p "$(dirname "$OUTPUT")"
echo "Exporting Android debug APK to $OUTPUT (versionName=${name:-} versionCode=${code})"
godot --headless --path "$PROJECT" --import
godot --headless --path "$PROJECT" --export-debug "Android Debug" "$OUTPUT"

[[ -f "$OUTPUT" ]] || fail "export did not write $OUTPUT"
bytes="$(stat -c%s "$OUTPUT")"
[[ "$bytes" -gt 1000000 ]] || fail "export wrote ${bytes} bytes; expected an APK larger than 1 MB"
echo "Wrote $OUTPUT (${bytes} bytes)"
