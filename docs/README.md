# Docs

Index for product and process docs. Agent entry: [`../AGENTS.md`](../AGENTS.md).

Every Markdown file at the repo root and under `docs/` must stay **≤ 500 words** (fenced code excluded). Lint: `python tools/lint_docs_words.py` (CI job `docs-lint`).

## Product

| Doc | Purpose |
|-----|---------|
| [Game rules (wiki)](https://github.com/waigore/empires-of-the-sea/wiki) | Mechanics source of truth |
| [requirements.md](requirements.md) | Pillars P1–P4 (`REQ-*`) |
| [rubric.md](rubric.md) | Evaluation gate (`RUB-*`) |
| [fleets.md](fleets.md) | Fleet movement, docking and ship reveal |
| [ui-demo.md](ui-demo.md) | Map screen demo notes |

## Process

| Doc | Purpose |
|-----|---------|
| [pull-requests.md](pull-requests.md) | PR rules: `gh`, required checks, merge |
| [android-build.md](android-build.md) | Android export presets, local build, release signing |
| [android-debug.md](android-debug.md) | Debug APK via PR into `android-debug` |
| [skills.md](skills.md) | Project skills + Cursor/OpenCode/Grok facades |
