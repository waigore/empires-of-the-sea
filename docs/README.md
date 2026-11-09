# Docs

Index for product and process docs. Agent entry: [`../AGENTS.md`](../AGENTS.md).

Every Markdown file at the repo root and under `docs/` must stay **≤ 500 words** (fenced code excluded). Lint: `python tools/lint_docs_words.py` (CI job `docs-lint`).

## Product

| Doc | Purpose |
|-----|---------|
| [Game rules (wiki)](https://github.com/waigore/empires-of-the-sea/wiki) | Mechanics source of truth |
| [Design Records (wiki)](https://github.com/waigore/empires-of-the-sea/wiki/design-records) | Clarifications (`DR-YYYYMMDD-NN`); see [changelog](https://github.com/waigore/empires-of-the-sea/wiki/design-changelog) |
| [requirements.md](requirements.md) | Pillars P1–P5 (`REQ-*`) |
| [rubric.md](rubric.md) | Evaluation gate (`RUB-*`) |
| [world.md](world.md) | Great Powers, Minors, Tribes and the two-region world |
| [capital-choice.md](capital-choice.md) | Seating the court before turn 1: rules, chart, persistence |
| [diplomacy.md](diplomacy.md) | Relations, war/peace, alliances, overtures, aid |
| [dialogue.md](dialogue.md) | Court voice: dialogue points, envoy moods, proposal banners |
| [ai.md](ai.md) | Rival-court AI: registry, personalities, agendas, diplomacy planner |
| [ai-observer.md](ai-observer.md) | Full-AI observer: live dashboard, metrics, headless export |
| [fleets.md](fleets.md) | Fleet movement, docking, ship reveal and naval combat |
| [naval-missions.md](naval-missions.md) | Patrol, blockade, interception, retreat and cargo raids |
| [armies.md](armies.md) | Land regiments, Home Army, marches and field battles |
| [forts.md](forts.md) | Fort levels, engineer builds, walls and emplaced batteries |
| [civilians.md](civilians.md) | Civilian units: training, movement, work orders |
| [improvements.md](improvements.md) | Estates: improvement yields, connectivity, management ledger |
| [economy.md](economy.md) | Stockpile, production recipes, town bonus, riches |
| [technology.md](technology.md) | Tech tree, research slots, funding, extraction caps |
| [ui-demo.md](ui-demo.md) | Map screen demo notes |
| [hud-top-bar.md](hud-top-bar.md) | Cartouche bar: purpose rule, removed controls, geometry |
| [audio.md](audio.md) | Music beds, cues, mix controls, rebuild |

## Process

| Doc | Purpose |
|-----|---------|
| [pull-requests.md](pull-requests.md) | PR rules: `gh`, required checks, merge |
| [testing.md](testing.md) | Test + e2e budgets (≤5 min / ≤2 min) |
| [android-build.md](android-build.md) | Android export presets, local build, release signing |
| [android-debug.md](android-debug.md) | Debug APK via PR into `android-debug` |
| [skills.md](skills.md) | Project skills; Cursor/OpenCode/Grok facades; Hermes via `.agents` |
