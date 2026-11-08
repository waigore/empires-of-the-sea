# Android builds

Export presets, local builds and release signing for the Android target.

## Presets

[`export_presets.cfg`](../export_presets.cfg) is tracked and defines two standard (non-Gradle)
APK presets:

| Preset | Output |
|--------|--------|
| `Android Debug` | `build/android/empires-of-the-sea-debug.apk` |
| `Android Release` | `build/android/empires-of-the-sea-release.apk` |

Both target `arm64-v8a` + `armeabi-v7a`, package `com.waigore.empiresofthesea` (`0.1.0`, code 1),
run on the `gl_compatibility` renderer in landscape, and exclude `addons/`, `tests/` and Markdown
from the pack. `build/` is gitignored.

## Local build

```bash
mkdir -p build/android
godot --headless --path . --export-debug "Android Debug" build/android/empires-of-the-sea-debug.apk
adb install -r build/android/empires-of-the-sea-debug.apk
adb shell am start -n com.waigore.empiresofthesea/com.godot.game.GodotAppLauncher
```

Requirements: Godot 4.7.x with Android export templates, JDK 17+ (21 is fine), and the Android SDK
with build-tools + platform installed. Godot reads the JDK from `export/android/java_sdk_path` in
editor settings — it does **not** fall back to `JAVA_HOME`, so a headless/CI machine must set that
setting (the Android SDK path does fall back to `ANDROID_HOME`). The export directory must exist
beforehand; Godot will not create it.

## Release signing

Keystores and passwords are never committed (`*.keystore`, `*.jks`, `keystore/` are gitignored) and
the presets carry no signing material. Supply it at export time:

```bash
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/upload.jks \
GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=… \
godot --headless --path . --export-release "Android Release" build/android/empires-of-the-sea-release.apk
```

## CI

CI runs tests only (`gd-tools test --coverage --min 80`); it does not build the Android APK. Run the
local build above, or add a separate build workflow if automated artifacts are needed later.

## Notes

- Google Play needs an `.aab`: install the Android build template
  (`Project → Install Android Build Template`), set `gradle_build/use_gradle_build=true` and switch
  `gradle_build/export_format` to AAB.
- Version bumps live in `scripts/game_version.gd` (`GameVersion`) and the presets' `version/name`
  and `version/code` — update all three together.
