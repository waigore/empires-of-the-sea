# Docs

Index for product and process docs. Entry: [`../AGENTS.md`](../AGENTS.md).

Root and `docs/` Markdown must stay **≤ 500 words** (fenced code excluded). Lint: `python tools/lint_docs_words.py` (CI `docs-lint`).

## Product

| Doc | Purpose |
|-----|---------|
| [Game rules (wiki)](https://github.com/waigore/empires-of-the-sea/wiki) | Mechanics truth |
| [Design Records (wiki)](https://github.com/waigore/empires-of-the-sea/wiki/design-records) | Clarifications (`DR-*`) + [changelog](https://github.com/waigore/empires-of-the-sea/wiki/design-changelog) |
| [requirements.md](requirements.md) | Pillars P1–P5 (`REQ-*`) |
| [rubric.md](rubric.md) | Evaluation gate (`RUB-*`) |
| [deferred.md](deferred.md) | Deferred gaps by impact |
| [world.md](world.md) | Great Powers, Minors, Tribes, two regions |
| [advanced-start.md](advanced-start.md) | Turn-50/100 opening: tiers, colonies, estates |
| [difficulty.md](difficulty.md) | Rival stores, rival land strength |
| [victory.md](victory.md) | Military victory, defeat, calendar end and the age's race |
| [capital-choice.md](capital-choice.md) | Seat the court before turn 1: rules, chart, save |
| [diplomacy.md](diplomacy.md) | Relations, war/peace, alliances, overtures, aid |
| [colonies.md](colonies.md) | Colonies: suzerain, seat, subsidy, boycott bar |
| [dialogue.md](dialogue.md) | Court voice: dialogue points, envoy moods, banners |
| [intel-dossier.md](intel-dossier.md) | Court dossier: agenda suspicion, evidence, bands |
| [ai.md](ai.md) | Rival-court AI: registry, personalities, agendas, planner |
| [ai-observer.md](ai-observer.md) | Full-AI observer: dashboard, metrics, headless export |
| [ai-objectives.md](ai-objectives.md) | AI objective ledger: one utility, rank, allocate |
| [fleets.md](fleets.md) | Fleet movement, docking, ship reveal and naval combat |
| [naval-missions.md](naval-missions.md) | Patrol, blockade, interception, retreat and cargo raids |
| [naval-despatch.md](naval-despatch.md) | The sea's despatch plate: a battle told on the water |
| [armies.md](armies.md) | Land regiments, Home Army, marches and field battles |
| [command.md](command.md) | The crown's commanders: the pool, its medals, the cap road |
| [field-hospital.md](field-hospital.md) | A train's tents: pitching, rest tempo, rations, travel |
| [forts.md](forts.md) | Fort levels, builds, walls and emplaced batteries |
| [battle-sim.md](battle-sim.md) | Visual Battle Simulator: a playtesting view of Quick Battle |
| [civilians.md](civilians.md) | Civilian units: training, movement, work orders |
| [espionage.md](espionage.md) | Spies: presence, counter-espionage, research and reports |
| [improvements.md](improvements.md) | Estates: improvement yields, connectivity, management ledger |
| [provinces.md](provinces.md) | The crown's provinces: one ledger for every holding |
| [towns.md](towns.md) | The crown's towns: levels, the next step, Raise |
| [walls.md](walls.md) | The crown's walls: levels and Raise |
| [hospitals.md](hospitals.md) | The crown's hospitals: levels, rations, Raise |
| [economy.md](economy.md) | Stockpile, recipes, town bonus, riches |
| [technology.md](technology.md) | Tech tree, slots, funding, extraction caps |
| [ui-panels.md](ui-panels.md) | Close seal: one door, top-right |
| [ui-demo.md](ui-demo.md) | Map-screen demo notes |
| [hud-top-bar.md](hud-top-bar.md) | Cartouche bar: purpose, geometry |
| [audio.md](audio.md) | Music, cues, mix |

## Process

| Doc | Purpose |
|-----|---------|
| [pull-requests.md](pull-requests.md) | PR rules: `gh`, required checks, merge |
| [testing.md](testing.md) | Test + e2e budgets (≤5 min / ≤5 min) |
| [android-build.md](android-build.md) | Android export presets, local build, signing |
| [android-debug.md](android-debug.md) | Debug APK via PR into `android-debug` |
| [agent-debug.md](agent-debug.md) | Localhost agent debug bridge: enable flag, ops, adb forward |
| [playtest-capture.md](playtest-capture.md) | Desktop capture mode: screenshots, video, comments, report |
| [skills.md](skills.md) | Project skills; Cursor/OpenCode/Grok facades; Hermes via `.agents` |
