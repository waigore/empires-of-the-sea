# Technology and research

The tech tree stores the catalog, slots and funding; Research turns gold into
advances, and researched techs lift extraction caps, re-equip regiments and
cheapen a land attack.
**Pillars:** P2, P3, P4.

**Wiki:** [tech-tree](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree),
[tech-tree-military](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-military),
[research-state](https://github.com/waigore/empires-of-the-sea/wiki/research-state),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Implemented

- **Catalog:** 113 wiki techs with id, name, era (cost tier), category,
  prerequisites, caps and discovery resources; `TechAudit.validate()` enforces
  unique ids, known prerequisites, a DAG, reachability, cap coverage and
  declared exceptions.
- **Research state:** three slots (four with University), per-slot funding and
  progress, `<techUnlocked>`.
- **Costs:** `1800 + (tier - 1) * 600` — 1800/2400/3000/3600 RP.
- **Funding:** None/Low/Medium/High/Maximum pay 0/50/150/400/1000 ducats for
  0/100/300/800/2500 RP; unpaid slots earn nothing.
- **Treasury floor:** Money Lending allows −500 ducats during research, Banking
  with Money Lending −1000.
- **Industrial Funding of Research:** +20% (floored) RP for military and naval
  techs; spy networks add +15% per shadowed court (`SpyNetworks`).
- **Discovery:** New World techs need a revealed tile holding the resource;
  gold, silver, gems, diamonds must also be prospected.
- **Extraction caps:** techs set the cap used by extraction, estates and Builder
  orders, `min(improvement, tech cap, terrain, path transport, town cap)`;
  exceptions match the wiki (horses 1, wool 3).
- **Unlocks (`TechUnlocks`):** build orders derived from the canonical gates
  (regiments, hulls, civilians, workers, forts, batteries, roads, general cap),
  plus each military tech's upgrade path and attack-price factor; `TechAudit`
  rejects unknown gates.
- **Re-equipping (`RegimentUpgrades`):** after Movement, before Combat, a Great
  Power's regiments take the newest same-category type its techs unlock —
  instance, army and province kept, the tech is the whole price. Minors follow
  the leading power; Tribes stay at 1.
- **Attack price (`ArmyAttackCost`):** 100 ducats per Great Power attacker per
  land battle; ×0.75 Industrial Machinery, ×0.85 Modern Military Funding (63
  both); charged once per exchange off the attacker's ledger, floored at zero,
  shown in the despatch.
- **Transport gates:** road 2 needs Road Construction; rail needs Early Steam
  Engine (flat), Later Steam Engine (hills, swamps), Dynamite (mountains).
- **Privateering Companies:** the charter holder's Patrol/Blockade interception
  and trade raids rise 25%.
- **Rivals:** AI courts fill their own slots via the same `ResearchTurn`.
- **UI:** `RESEARCH` opens the college ledger — slot rows (progress, spy badge,
  funding, cancel) and AVAILABLE/KNOWN tabs with cost/effect tooltips.

## Deferred (REQ-P2-02)

Goal-tech sorting and save/load of slot assignments.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/tech_catalog.gd` | catalog, costs, caps, effect text |
| `scripts/rules/tech_unlocks.gd` | what each tech opens |
| `scripts/rules/tech_audit.gd` | catalog validation |
| `scripts/rules/research_state.gd` | slots, funding, progress |
| `scripts/rules/research_funding.gd` | presets, treasury floor |
| `scripts/rules/research_turn.gd` | Research phase |
| `scripts/rules/tech_discovery.gd` | revealed commodities |
| `scripts/rules/regiment_upgrades.gd` | in-place re-equipping |
| `scripts/rules/army_attack_cost.gd` | per-battle attack treasury |
| `scripts/ui/research_panel.gd` | ledger shell and tabs |
| `scripts/ui/research_row.gd` | slot, available and known rows |

Rules stay node-free (`REQ-P3-03`); the panel emits intents and
`EconomyController` applies them.

## Tests

`test_tech_catalog`, `test_tech_discovery`, `test_research_state`,
`test_research_turn`, `test_research_panel`, `test_research_screen`,
`test_improvement_system`, `test_army_field_rules`, `test_battle_rules`.
