# Technology and research

The tech tree stores the catalog, research slots and funding; the Research phase
turns gold into advances, and researched techs lift extraction caps.
**Pillars:** P2 (rules), P3 (rules/view), P4.

**Wiki:** [tech-tree](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree),
[tech-tree-gathering](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-gathering),
[research-state](https://github.com/waigore/empires-of-the-sea/wiki/research-state),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Implemented

- **Catalog:** all 113 wiki techs with id, display name, era (cost tier),
  category, cross-category prerequisites, extraction caps, discovery resources
  and effect notes. `TechAudit.validate()` enforces unique
  ids, known prerequisites, a DAG, reachability from the roots, cap coverage
  and declared exceptions.
- **Research state:** three slots (four with University), funding per slot,
  progress per tech, `<techUnlocked>`; "currently researching" is the key set
  of the progress table.
- **Costs:** `1800 + (tier - 1) * 600`; tier 1–4 cost 1800/2400/3000/3600 RP
  — 6/8/10/12 turns at Medium.
- **Funding:** None/Low/Medium/High/Maximum pay 0/50/150/400/1000 ducats for
  0/100/300/800/2500 RP. Cancelling a slot forfeits its progress.
- **Research phase** runs after Production in `EconomyTurn`. An unfunded slot
  earns nothing that turn; the wiki has no partial funding, so none is invented.
- **Treasury floor:** Money Lending allows −500 ducats during research, Banking
  with Money Lending −1000.
- **Industrial Funding of Research:** +20% (floored) RP for military and naval
  techs.
- **Discovery:** New World discovery techs need a revealed tile holding the
  resource; gold, silver, gems and diamonds must also be prospected.
- **Extraction caps:** techs set the cap used by extraction, the estates ledger
  and Builder orders:
  `min(improvement, tech cap, terrain cap, path transport, town cap)`.
  Exceptions match the wiki (horses 1, wool 3).
- **Unlocks:** `TechUnlocks` derives every build order a tech opens from the
  canonical gate tables (regiments, hulls, civilians, worker tiers, forts,
  batteries, roads/railroads, general cap); the college tooltip prints them and
  `TechAudit` rejects a gate naming an unknown tech.
- **Transport gates:** roads level 2 need Road Construction; railroads need
  Early Steam Engine (flat), Later Steam Engine (hills, swamps), Dynamite
  (mountains).
- **Privateering Companies:** the charter holder's Patrol/Blockade
  interception and trade raids rise 25%; the fleet dossier names it.
- **UI:** `RESEARCH` opens the college ledger — slot rows with progress, a
  funding button and cancel; AVAILABLE and KNOWN tabs with cost and effect
  tooltips.

## Deferred (REQ-P2-02)

- Spy +15% RP boost, goal-tech sorting, save/load of slot assignments.
- In-place upgrade paths and the land-battle attack treasury modifiers: named
  in tooltips, not simulated.
- Terrain hard caps and path transport caps.

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
