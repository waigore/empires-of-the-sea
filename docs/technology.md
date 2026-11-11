# Technology and research

Research turns gold into advances that lift caps, re-equip regiments and
cheapen attacks.
**Pillars:** P2, P3, P4.

**Wiki:** [tech-tree](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree),
[tech-tree-military](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-military),
[research-state](https://github.com/waigore/empires-of-the-sea/wiki/research-state),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Implemented

- **Catalog:** 113 wiki techs (id, name, era, category, prerequisites, caps,
  discovery); `TechAudit.validate()` enforces unique ids, known prerequisites, a
  DAG, reachability and cap coverage.
- **Research state:** three slots (four with University), per-slot funding,
  progress and `<techUnlocked>`.
- **Costs:** `1800 + (tier - 1) * 600` — 1800/2400/3000/3600 RP.
- **Funding:** presets pay 0/50/150/400/1000 ducats for 0/100/300/800/2500 RP;
  unpaid slots earn nothing.
- **Treasury floor:** Money Lending allows −500 ducats, Banking with Money
  Lending −1000.
- **Industrial Funding:** +20% (floored) RP for military and naval techs; spy
  networks add +15% per shadowed court (`SpyNetworks`).
- **Discovery:** New World techs need a revealed tile holding the resource;
  gold, silver, gems, diamonds must be prospected.
- **Extraction caps:** techs set the cap for extraction, estates and Builder
  orders, `min(improvement, tech cap, terrain, path transport, town cap)`; exceptions per
  wiki (horses 1, wool 3).
- **Unlocks (`TechUnlocks`):** build orders from the canonical gates (regiments,
  hulls, civilians, workers, forts, batteries, roads, general cap) plus each
  military tech's upgrade path and attack-price factor.
- **Re-equipping (`RegimentUpgrades`):** a Great Power's regiments take the
  newest same-category type its techs unlock — the tech is the whole price;
  minors follow the leading power.
- **Attack price (`ArmyAttackCost`):** 100 ducats per Great Power attacker per
  land battle; ×0.75 Industrial Machinery, ×0.85 Modern Military Funding;
  charged once per exchange, floored at zero.
- **Transport:** road 2 needs Road Construction; rail needs Early Steam Engine
  (flat), Later Steam Engine (hills, swamps), Dynamite (mountains).
- **Privateering Companies:** the charter holder's Patrol/Blockade
  interception and trade raids rise 25%.
- **Rivals:** AI courts fill slots via `ResearchTurn`.
- **Goal slot:** a goal orders the queue — goal, prerequisites nearest-first,
  catalog order; it funds nothing and rides the save
  (`ResearchState.goal`, DR-20261111-21).
- **Slot persistence:** saves keep each slot's tech and funding; load drops what
  the catalog or roster cannot hold and forfeits unbound progress.
- **UI:** `RESEARCH` opens the college ledger — goal strip, slot rows (progress,
  spy badge, funding, cancel) and AVAILABLE/KNOWN tabs with a series medallion
  (`TechIcons`; `tools/art/tech-medallions.md`) and tooltips.

## Deferred (REQ-P2-02)

No research rule is deferred; gaps: [`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/tech_catalog.gd` | catalog, costs, caps, effects |
| `scripts/rules/tech_unlocks.gd` | what each tech opens |
| `scripts/rules/tech_audit.gd` | catalog validation |
| `scripts/rules/tech_order.gd` | goal-first queue order |
| `scripts/rules/research_state.gd` | slots, funding, progress |
| `scripts/rules/research_slots.gd` | slot persistence |
| `scripts/rules/research_funding.gd` | presets, treasury floor |
| `scripts/rules/research_turn.gd` | Research phase |
| `scripts/rules/tech_discovery.gd` | revealed commodities |
| `scripts/rules/regiment_upgrades.gd` | in-place re-equipping |
| `scripts/rules/army_attack_cost.gd` | attack treasury |
| `scripts/ui/research_panel.gd` | ledger shell, goal strip, tabs |
| `scripts/ui/research_row.gd` | slot/available/known rows |
| `scripts/ui/tech_icons.gd` | tech id → medallion |

Rules stay node-free (`REQ-P3-03`); the panel emits intents the controller
applies.

## Tests

`test_tech_*` and `test_research_*` suites, plus `test_improvement_system`,
`test_army_field_rules`, `test_battle_rules`.
