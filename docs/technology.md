# Technology and research

Research turns gold into advances: caps, re-equipping, cheaper attacks.
**Pillars:** P2, P3, P4.

**Wiki:** [tech-tree](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree),
[tech-tree-military](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-military),
[research-state](https://github.com/waigore/empires-of-the-sea/wiki/research-state),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Implemented

- **Catalog:** 113 techs; `TechAudit.validate()` enforces ids, prerequisites,
  the DAG, reachability, caps.
- **Research state:** three slots (four with University), per-slot funding,
  `<techUnlocked>`; saved per slot.
- **Costs:** `1800 + (tier - 1) * 600` — 1800/2400/3000/3600 RP.
- **Funding:** presets pay 0/50/150/400/1000 ducats for 0/100/300/800/2500 RP;
  unpaid slots earn nothing. **One press** (`ResearchBatch`, DR-20261118-26)
  files every study at the preset on its face (`FUND ALL · Medium`, stepped
  `−`/`+`), priced first (`Fund 2 of 3 studies at Medium — 450 ducats & 900 RP a
  turn`); it stands down when no row would move; line and receipt both name the
  studies the purse cannot pay (DR-20261119-01).
- **Treasury floor:** Money Lending −500 ducats, Banking with Money Lending −1000.
- **Bonuses:** Industrial Funding +20% (floored) for military and naval techs;
  spies +15% per shadowed court (`SpyNetworks`).
- **Discovery:** New World techs need a revealed tile with the resource; gold,
  silver, gems, diamonds prospected.
- **Extraction caps:** `min(improvement, tech cap, terrain, path transport,
  town cap)`; horses 1, wool 3.
- **Unlocks (`TechUnlocks`):** every build order, each military tech's
  upgrade path and attack price.
- **Re-equipping (`RegimentUpgrades`):** regiments take the newest type its
  techs unlock; minors follow.
- **Attack price (`ArmyAttackCost`):** 100 ducats a Great Power land battle;
  ×0.75 Industrial Machinery, ×0.85 Modern Military Funding.
- **Transport:** road 2 needs Road Construction; rail needs Early Steam
  Engine (flat), Later Steam Engine (hills, swamps), Dynamite (mountains).
- **Privateering:** a charter holder's interception and raids rise 25%.
- **Rivals:** AI courts fill slots via `ResearchTurn`; a court at its floor
  keeps one study at Low (DR-20261113-24).
- **Goal slot:** orders the queue (goal, prerequisites, catalog); funds
  nothing, rides the save (`ResearchState.goal`, DR-20261111-21).
- **UI:** `RESEARCH` opens the college: goal strip, slots, the one press,
  AVAILABLE/KNOWN tabs, a tech-tree door. Slots show ducats and a
  gauge (`ResearchBar`); every advance prints what it opens
  (`TechCatalog.payoff_text`); touch never hovers. The tree lays the 113
  advances by depth (`TechTreeLayout`) with edges and the selected advance's
  road (`REQ-P5-03`, `REQ-P1-05`).

## Deferred (REQ-P2-02)

No research rule is deferred; gaps: [`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/tech_catalog.gd`, `tech_audit.gd` | catalog, costs, caps, validation |
| `scripts/rules/tech_unlocks.gd`, `tech_plan.gd`, `tech_order.gd` | what a tech opens, state/road, queue order |
| `scripts/rules/tech_tree_layout.gd` | chart columns, edges, ancestor cone |
| `scripts/rules/research_state.gd`, `research_slots.gd`, `research_funding.gd` | slots, funding, saves, presets, floor |
| `scripts/rules/research_batch.gd` | the one press: plan, line, receipt |
| `scripts/rules/research_turn.gd` | Research phase, preview |
| `scripts/rules/tech_discovery.gd` | revealed commodities |
| `scripts/rules/regiment_upgrades.gd`, `army_attack_cost.gd` | re-equipping, attack treasury |
| `scripts/ui/research_panel.gd`, `research_sheet_fit.gd`, `research_fund_press.gd` | shell, tabs, chart door, press, phone fit |
| `scripts/ui/tech_tree_*.gd` | full-screen chart |
| `scripts/ui/research_row.gd`, `research_slot_row.gd`, `research_bar.gd` | rows, slot spend, gauge |
| `scripts/ui/tech_icons.gd` | tech → medallion |

Rules stay node-free (`REQ-P3-03`); the panel emits intents.

## Tests

`test_research_rules`, plus `test_improvement_system`,
`test_army_field_rules`, `test_battle_rules`.
