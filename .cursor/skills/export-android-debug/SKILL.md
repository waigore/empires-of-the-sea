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

# Export Android debug (facade)

Canonical instructions: [`.agents/skills/export-android-debug/SKILL.md`](../../../.agents/skills/export-android-debug/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
