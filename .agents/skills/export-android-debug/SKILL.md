---
name: export-android-debug
description: |-
  Publish a debug-signed Android APK via the Android debug GitHub Action and a
  GitHub Release under android-debug/. Never export locally unless the
  user explicitly asks for a local build. Use when the user wants an Android
  debug APK, debug build, or a downloadable APK on GitHub.

  Examples:
  - user: "Create me an android debug build" → PR into android-debug, wait, give APK URL
  - user: "I need a debug APK on GitHub" → same path; report the release download link
  - user: "Export the Android APK locally" → only then consider a local export; otherwise Actions
---

# Export Android debug

Thin skill. The contract is [`docs/android-debug.md`](../../../docs/android-debug.md). Do not invent a parallel local export path.

## Steps

1. **Read** the contract.
2. **Follow** its agent procedure (PR into `android-debug`, conflict sync favoring `main`, wait for the Action, report the release and `.apk` URLs).
3. **Stop** when the prerelease asset is downloadable, or when a blocker needs the user (auth, missing `android-debug` branch, failed export).

## Rules

- Explicit only for local builds: do not run `.github/scripts/export_android_debug.sh` or install JDK/SDK/templates for this skill unless the user asked for a local export.
- Do not force-push `android-debug` or rewrite the debug keystore.
- Do not treat an open PR or a green check alone as done; the deliverable is the GitHub Release APK URL.
