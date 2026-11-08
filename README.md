# Empires of the Sea

Naval strategy game built with **Godot 4.7**, targeting desktop (Windows, macOS, Linux) and mobile (Android, iOS).

## Requirements

- [Godot 4.7.x](https://godotengine.org/download) (standard build)
- Python 3.10+ and [`gd-tools-cli`](https://pypi.org/project/gd-tools-cli/) for tests/coverage
- Export templates for your target platforms
- Android: JDK 17+, Android SDK; iOS: macOS + Xcode

## Getting started

1. Open the project in Godot (`project.godot`).
2. Run the main scene (F5).
3. Export via **Project → Export** using the presets for desktop and mobile.

## Playable map demo

F5 opens the map screen demo (`scenes/map_screen.tscn`): a procedurally generated
Old World region rendered as an antique atlas.

| Action | Desktop | Touch |
|--------|---------|-------|
| Pan | drag, WASD / arrows, two-finger trackpad | one-finger drag |
| Zoom | wheel, pinch, `+` / `−` buttons, E / Q | pinch, `+` / `−` buttons |
| Jump | click the minimap | tap / drag the minimap |
| Select | click a province or a fleet | tap |
| Focus capital | `F` | — |
| End turn | `Space` / `Enter` or the gold seal | tap the gold seal |

Design notes live in [`docs/ui-demo.md`](docs/ui-demo.md).

## Development

```bash
pip install gd-tools-cli
gd-tools doctor
gd-tools test --coverage --min 80
```

- Tests live under `tests/` and extend `GdToolsTest`.
- CI enforces an **80% line coverage** gate on every PR.
- Game code, tests, assets, and CI config require at least one collaborator approval.
- Docs-only PRs (e.g. `docs/`, Markdown) do not require approval and auto-merge (squash) via GitHub Actions when checks pass.

## Project layout

```
res://
├── scenes/       # Packed scenes (.tscn)
├── scripts/      # GDScript (.gd)
├── assets/       # Art, audio, fonts
├── ui/           # UI scenes and themes
├── autoload/     # Singletons
├── tests/        # gd-tools unit tests
└── addons/       # gd-tools test/coverage/editor plugins
```

## Platforms

| Platform | Notes |
|----------|--------|
| Windows / Linux / macOS | Primary desktop targets |
| Android | Touch-first controls; test on device |
| iOS | Requires Apple developer setup for device builds |

Design for both mouse/keyboard and touch. Prefer resolution-independent UI (anchors, containers, theme scales).
