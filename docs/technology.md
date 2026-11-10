# Technology and research

The tech tree stores the catalog, research slots and funding; the Research phase
turns gold into advances, and researched techs lift extraction caps.
**Pillars:** P2, P3, P4.

**Wiki:** [tech-tree](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree),
[tech-tree-gathering](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-gathering),
[research-state](https://github.com/waigore/empires-of-the-sea/wiki/research-state),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Implemented

- **Catalog:** all 113 wiki techs with id, name, era (cost tier), category,
  prerequisites, extraction caps, discovery resources, notes.
  `TechAudit.validate()` enforces unique ids, known prerequisites, a DAG,
  reachability, cap coverage, declared exceptions.
- **Research state:** three slots (four with University), funding per slot,
  progress per tech, `<techUnlocked>`; "researching" is the progress table's
  key set.
- **Costs:** `1800 + (tier - 1) * 600`; tiers 1–4 cost 1800/2400/3000/3600 RP
  — 6/8/10/12 Medium turns.
- **Funding:** None/Low/Medium/High/Maximum pay 0/50/150/400/1000 ducats for
  0/100/300/800/2500 RP. Cancelling a slot forfeits its progress.
- **Research phase** runs after Production in `EconomyTurn`; a slot that cannot
  pay its full gold earns nothing and is reported unfunded (no partial funding).
- **Treasury floor:** Money Lending allows −500 ducats during research, Banking
  with Money Lending −1000.
- **Industrial Funding of Research:** +20% (floored) RP for military and naval
  techs.
- **Spy network:** each shadowed rival Great Power adds +15% RP, once per
  court, to Low+ slots on techs that court knows; percentages add to Industrial
  Funding before one floor (`SpyNetworks`, `dr-20261110-03`).
- **Discovery:** New World techs need a revealed tile holding the resource;
  gold, silver, gems, diamonds must also be prospected.
- **Extraction caps:** techs set the cap used by extraction, estates and Builder
  orders: `min(improvement, tech cap, terrain cap, path transport, town cap)`;
  exceptions match the wiki (horses 1, wool 3).
- **Unlocks:** `TechUnlocks` derives build orders from the canonical gates
  (regiments, hulls, civilians, workers, forts, batteries, roads, general cap);
  tooltips print them and `TechAudit` rejects unknown gates.
- **Transport gates:** road 2 needs Road Construction; rail needs Early Steam
  Engine (flat), Later Steam Engine (hills, swamps), Dynamite (mountains).
- **Privateering Companies:** charter holder's Patrol/Blockade interception and
  trade raids rise 25%; the dossier names it.
- **Rivals:** AI courts fill their own slots via the same `ResearchTurn`
  (docs/ai.md; `dr-20261109-20`).
- **UI:** `RESEARCH` opens the college ledger — slot rows with progress, spy
  badge, funding button, cancel; AVAILABLE and KNOWN tabs with cost/effect
  tooltips.

## Deferred (REQ-P2-02)

- Goal-tech sorting and save/load of slot assignments; counter-spy.
- In-place upgrades and land-battle attack treasury modifiers: named in
  tooltips, not simulated.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/tech_catalog.gd` | catalog data, costs, caps, effect text |
| `scripts/rules/tech_unlocks.gd` | what each tech opens, derived from the gates |
| `scripts/rules/tech_audit.gd` | start-up style validation of the catalog |
| `scripts/rules/research_state.gd` | slots, funding, progress, knowledge |
| `scripts/rules/research_funding.gd` | funding presets and treasury floor |
| `scripts/rules/research_turn.gd` | Research phase resolution |
| `scripts/rules/tech_discovery.gd` | revealed commodities per player |
| `scripts/ui/research_panel.gd` | college ledger shell and tabs |
| `scripts/ui/research_row.gd` | slot, available and known rows |

Rules stay node-free (`REQ-P3-03`); the panel emits intents and
`EconomyController` applies them.

## Tests

`test_tech_catalog`, `test_tech_discovery`, `test_research_state`,
`test_research_turn`, `test_research_panel`, `test_research_screen`,
`test_improvement_system`.
