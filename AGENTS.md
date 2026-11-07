# Agent guide — Empires of the Sea

Godot 4 game for **desktop** (Windows, macOS, Linux) and **mobile** (Android, iOS). Prefer reuse and existing project patterns over new abstractions.

## Stack

- Engine: Godot 4.7.x
- Language: GDScript (typed where practical)
- Scenes: `.tscn` + scripts; keep logic in scripts, composition in scenes
- Tests: [`gd-tools`](https://github.com/mansyar/gd-tools) (`GdToolsTest`); CI requires `gd-tools test --coverage --min 80`

## Layout

| Path | Use |
|------|-----|
| `scenes/` | Gameplay and screen scenes |
| `scripts/` | Shared / non-scene scripts |
| `ui/` | UI scenes, themes, components |
| `assets/` | Art, audio, fonts |
| `autoload/` | Singletons only when cross-cutting |
| `tests/` | Unit tests (`extends GdToolsTest`) |
| `addons/gd-tools-*` | Vendored gd-tools test/coverage/editor addons |

## Conventions

- **Reuse first**: extend existing scenes, scripts, and UI before adding new modules.
- **Typed GDScript**: use type hints on exports, params, and returns.
- **Signals over tight coupling**: emit/connect; avoid reaching deep into other node trees.
- **Input**: support mouse/keyboard and touch; use InputMap actions, not hard-coded keys.
- **UI**: containers + anchors; theme for shared styles; no fixed pixel layouts that break on phones.
- **Mobile**: assume limited screen size and touch targets; avoid hover-only UX.
- **Exports**: keep platform differences behind feature checks or small adapters; shared core logic.
- **Assets**: import settings intentional (filter, compression); prefer atlases for 2D sprites when useful.

## Do / don’t

- Do keep scenes focused; extract reusable sub-scenes.
- Do guard early; keep nesting shallow.
- Don’t commit `.godot/`, export caches, or local override files.
- Don’t add editor plugins or third-party addons without a clear need.
- Don’t hard-code resolutions, aspect ratios, or platform OS names in gameplay code.

## When unsure

Match neighboring files’ naming, folder placement, and signal/export style. Prefer the smallest change that preserves desktop and mobile playability.
