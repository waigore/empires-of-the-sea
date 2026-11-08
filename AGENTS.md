# Agent guide — Empires of the Sea

Godot 4 game for **desktop** (Windows, macOS, Linux) and **mobile** (Android, iOS). Prefer reuse and existing project patterns over new abstractions.

## Always refer to

| Doc | Use |
|-----|-----|
| [Game rules (wiki)](https://github.com/waigore/empires-of-the-sea/wiki) | Rules source of truth (P2) |
| [`docs/requirements.md`](docs/requirements.md) | Product pillars P1–P4 (`REQ-*`) |
| [`docs/rubric.md`](docs/rubric.md) | Evaluation gate (`RUB-*`) |
| [`docs/pull-requests.md`](docs/pull-requests.md) | PR base rules (`gh`, required checks) |
| [`docs/android-debug.md`](docs/android-debug.md) | Debug APK via PR into `android-debug` |
| [`docs/skills.md`](docs/skills.md) | Project skills + agent facades |
| [`docs/README.md`](docs/README.md) | Docs index |

## Docs policy

Every Markdown file at the repo root and under `docs/` must stay **≤ 500 words** (fenced code excluded). CI job `docs-lint` hard-fails over-limit files (`python tools/lint_docs_words.py`). Prefer tables and short bullets; put long mechanics in the wiki.

## Stack

- Engine: Godot 4.7.x · GDScript (typed where practical)
- Scenes: `.tscn` + scripts; logic in scripts, composition in scenes
- Tests: [`gd-tools`](https://github.com/mansyar/gd-tools) (`GdToolsTest`); CI: `gd-tools test --coverage --min 80`

## Layout

| Path | Use |
|------|-----|
| `scenes/` | Gameplay and screen scenes |
| `scripts/` | Shared / non-scene scripts |
| `scripts/world/` | Pure map data (`MapModel`, `MapGeo`) used by rules |
| `scripts/session/` | Play context for map play helpers (`PlaySession`) |
| `scripts/platform/` | Thin OS/platform adapters only |
| `ui/` | UI scenes, themes, components |
| `assets/` | Art, audio, fonts |
| `autoload/` | Allowlisted cross-cutting only (`arch-lint`) |
| `tests/` | Unit tests (`extends GdToolsTest`) |
| `addons/gd-tools-*` | Vendored gd-tools addons |

## Conventions

- **Reuse first**; typed GDScript; signals over deep node reach-ins. Scripts ≤400 lines / ≤25 methods; size allowlist ≤5 and shrink-only (`arch-lint`).
- **Input**: mouse/keyboard + touch via InputMap actions.
- **UI**: containers + anchors + theme; no fixed pixel layouts; no hover-only critical UX.
- **Exports**: platform diffs in `scripts/platform/`; shared core. P3 gated by `arch-lint` (`RUB-P3-*`).
- **Assets**: intentional import settings; atlases when useful.

## Do / don’t

- Do keep scenes focused; guard early; shallow nesting.
- Do run with `tools/run.sh` (imports first); bare `godot --path .` on a fresh clone fails — `class_name` globals come from the editor-generated `.godot/` cache.
- Do open/merge PRs with `gh`; wait for required checks — see [`docs/pull-requests.md`](docs/pull-requests.md).
- Don’t commit `.godot/`, export caches, or local overrides.
- Don’t add plugins/addons without need; don’t hard-code resolutions or OS names in gameplay.
- Don’t bypass, force-merge, or skip required PR checks.

## When unsure

Match neighboring naming, folders, and signal/export style. Smallest change that keeps desktop and mobile playable.
