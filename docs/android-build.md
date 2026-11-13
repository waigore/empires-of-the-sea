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

## Device quirks

### Never ask for the safe area on Android

`DisplayServer.get_display_safe_area()` **aborts the process on Android 17** (SDK 37). Godot 4.7's
`GodotIO.getDisplaySafeArea` wraps the decor view in AndroidX `WindowInsetsCompat`, which calls
`ViewCompat.getRootWindowInsets`, which wraps again — a Java recursion that exhausts the thread's
4 MB stack. The tombstone reads `JNI DETECTED ERROR … java.lang.StackOverflowError` on
`GetArrayLength`, with `getDisplaySafeArea → step → onDrawFrame`.

Any screen that mounts the HUD hits it, because `GameHud._relayout()` asks for insets; the title,
setup and crown's-charge pages do not, so the crash looked like "the map screen never opens".

`PlatformDisplay.safe_insets()` therefore reads `DisplayServer.get_display_cutouts()` on Android
(plain `WindowInsets.getDisplayCutout()`, no compat layer) and turns the rectangles into edge insets
— `PlatformDisplay.insets_for()` and `test_mobile_layout.gd` pin that rule. In fullscreen play the
cutouts are the only thing over the canvas, so nothing is lost. iOS keeps the safe-area call.
Revisit only when the engine bumps its bundled AndroidX.

