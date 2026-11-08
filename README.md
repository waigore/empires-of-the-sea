# Empires of the Sea

Naval strategy game built with **Godot 4.7**, targeting desktop (Windows, macOS, Linux) and mobile (Android, iOS).

## Requirements

- [Godot 4.7.x](https://godotengine.org/download) (standard build)
- Python 3.10+ and [`gd-tools-cli`](https://pypi.org/project/gd-tools-cli/) for tests/coverage
- Export templates for target platforms
- Android: JDK 17+, Android SDK; iOS: macOS + Xcode

## Getting started

1. Open the project in Godot (`project.godot`) — the editor imports it on open.
2. Run the main scene (F5).
3. Export via **Project → Export** using desktop/mobile presets.

From a terminal, use `tools/run.sh` instead of a bare `godot --path .`:

```bash
tools/run.sh                    # play
tools/run.sh --headless --quit-after 300
```

Godot resolves `class_name` globals from `.godot/global_script_class_cache.cfg`,
which only an import pass writes. A fresh clone therefore cannot start (every
script fails with `Identifier "Palette" not declared in the current scope`) until
the project has been imported once; the wrapper does that import, then runs.

## Playable map demo

F5 opens `scenes/map_screen.tscn`: a procedural Old World region as an antique atlas. Design notes: [`docs/ui-demo.md`](docs/ui-demo.md).

| Action | Desktop | Touch |
|--------|---------|-------|
| Pan | drag, WASD / arrows, trackpad | one-finger drag |
| Zoom | wheel, pinch, `+` / `−`, E / Q | pinch, `+` / `−` |
| Jump | click minimap | tap / drag minimap |
| Select | click province or fleet | tap |
| Sail / dock | select a fleet, click a highlighted zone or friendly port | tap the same highlights |
| Focus capital | `F` | — |
| End turn | `Space` / `Enter` or gold seal | gold seal |

## Development

```bash
pip install gd-tools-cli
gd-tools doctor
gd-tools test --coverage --min 80
python tools/lint_docs_words.py
```

- Tests under `tests/` extend `GdToolsTest`.
- CI: **80% coverage** (`tests`) and **docs ≤ 500 words** (`docs-lint`).
- Code/tests/assets need collaborator approval when the approval gate is enforced; docs-only PRs auto-merge (squash) when checks pass.

- Android export presets, device builds and release signing: [`docs/android-build.md`](docs/android-build.md).

## Project layout

```
res://
├── scenes/       # Packed scenes (.tscn)
├── scripts/      # GDScript (.gd)
├── assets/       # Art, audio, fonts
├── ui/           # UI scenes and themes
├── autoload/     # Singletons
├── tests/        # gd-tools unit tests
└── addons/       # gd-tools plugins
```

## Platforms

| Platform | Notes |
|----------|--------|
| Windows / Linux / macOS | Primary desktop targets |
| Android | Touch-first; test on device |
| iOS | Apple developer setup for device builds |

Design for mouse/keyboard and touch. Prefer resolution-independent UI (anchors, containers, theme scales).
