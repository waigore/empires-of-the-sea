# Android debug APK

Debug APKs are produced only by GitHub Actions, never by a local Godot export unless the user explicitly asks for a local build.

## Trigger

Workflow: [`.github/workflows/android-debug.yml`](../.github/workflows/android-debug.yml).

It runs on `pull_request` (`opened` / `synchronize` / `reopened`) into the long-lived **`android-debug`** branch (same-repo heads only). A push to that branch alone does not build.

The job exports preset `Android Debug` via [`.github/scripts/export_android_debug.sh`](../.github/scripts/export_android_debug.sh) (CI-only: requires `ANDROID_EXPORT_CI=1`; rewrites Godot editor settings). Package `com.waigore.empiresofthesea.debug`, arm64 only, signed with [`export/android/debug.keystore`](../export/android/debug.keystore).

## Publish

On success the workflow creates or updates a **prerelease** tagged `android-debug/<YYYY-MM-DD>/<sha>` (UTC date), titled `android-debug <YYYY-MM-DD> <12-char-sha>`, with asset `empires-of-the-sea-<12-char-sha>-debug.apk`.

Install over a previous build: `adb install -r <apk>`.

## Agent procedure

1. Prefer current `main` as the APK contents. Open a same-repo PR **into** `android-debug`.
2. If `main` → `android-debug` conflicts, branch from `origin/android-debug` (`chore/android-debug-sync`), merge `origin/main`, resolve conflicts **in favor of `main`**, push, and open (or retarget) the PR from that branch. Never force-push `android-debug`.
3. Wait for the **Android debug** check to succeed. Report the release URL and the `.apk` download URL. Do not stop at the PR URL alone.
4. Leave auto-merge alone unless the user asks; merging updates `android-debug` for the next sync.

## Out of scope

- Local JDK / Android SDK / Godot template install for this path
- Release (non-debug) signing or Play Store uploads
- Editing the workflow or keystore unless the user asked to change the pipeline
