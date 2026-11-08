# Android builds

Export presets, local builds and release signing for the Android target.

## Presets

[`export_presets.cfg`](../export_presets.cfg) is tracked and defines two standard (non-Gradle)
APK presets:

| Preset | Package | Output |
|--------|---------|--------|
| `Android Debug` | `com.waigore.empiresofthesea.debug` | `build/android/empires-of-the-sea-debug.apk` |
| `Android Release` | `com.waigore.empiresofthesea` | `build/android/empires-of-the-sea-release.apk` |

Both target `arm64-v8a` only (`0.1.0`, code 1), run on the `gl_compatibility` renderer in
landscape, and exclude `addons/`, `tests/` and Markdown from the pack. `build/` is gitignored.

## Local build

```bash
mkdir -p build/android
godot --headless --path . --export-debug "Android Debug" build/android/empires-of-the-sea-debug.apk
adb install -r build/android/empires-of-the-sea-debug.apk
adb shell am start -n com.waigore.empiresofthesea.debug/com.godot.game.GodotAppLauncher
```

Requirements: Godot 4.7.x with Android export templates, JDK 17+ (21 is fine), and the Android SDK
with build-tools + platform installed. Godot reads the JDK from `export/android/java_sdk_path` in
editor settings — it does **not** fall back to `JAVA_HOME`, so a headless/CI machine must set that
setting (the Android SDK path does fall back to `ANDROID_HOME`). The export directory must exist
beforehand; Godot will not create it.

## Release signing

Release keystores and passwords are never committed (`*.keystore`, `*.jks`, `keystore/` are
gitignored; the committed [`export/android/debug.keystore`](../export/android/debug.keystore) is
the exception for debug CI). Presets carry no signing material. Supply release credentials at
export time:

```bash
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/upload.jks \
GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=… \
godot --headless --path . --export-release "Android Release" build/android/empires-of-the-sea-release.apk
```

## CI

Tests stay in [CI](../.github/workflows/ci.yml). Debug APKs are published by the
[`android-debug`](android-debug.md) workflow (PR into `android-debug` → GitHub Release). That check
is **not** required on `main`.

## Notes

- Google Play needs an `.aab`: install the Android build template
  (`Project → Install Android Build Template`), set `gradle_build/use_gradle_build=true` and switch
  `gradle_build/export_format` to AAB.
- Version bumps live in `scripts/game_version.gd` (`GameVersion`) and the presets' `version/name`
  and `version/code` — update all three together.
