# Technology and research

Research turns gold into advances: caps, re-equipping, cheaper attacks.
**Pillars:** P2, P3, P4.

**Wiki:** [tech-tree](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree),
[tech-tree-military](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-military),
[research-state](https://github.com/waigore/empires-of-the-sea/wiki/research-state),
[tech-and-extraction-cap](https://github.com/waigore/empires-of-the-sea/wiki/tech-and-extraction-cap).

## Implemented

- **Catalog:** 113 techs; `TechAudit.validate()` checks ids, prerequisites,
  DAG, reachability, caps.
- **Research state:** three slots (four with University), per-slot funding,
  `<techUnlocked>`, saved.
- **Costs:** `1800 + (tier - 1) * 600`, so 1800–3600 RP.
- **Funding:** presets pay 0/50/150/400/1000 ducats for 0/100/300/800/2500 RP;
  unpaid slots earn nothing. **One press** (`ResearchBatch`, DR-20261118-26)
  files every study at the face's preset, priced first; line and receipt name
  the studies the purse cannot pay (DR-20261119-01).
- **Treasury floor:** Money Lending −500; Banking with it −1000.
- **Bonuses:** Industrial Funding +20% (floored) for military and naval techs;
  spies +15% per shadowed court (`SpyNetworks`).
- **Discovery:** New World techs need a revealed tile with its resource; gold,
  silver, gems, diamonds prospected.
- **Extraction caps:** `min(improvement, tech cap, terrain, path transport,
  town cap)`; horses 1, wool 3.
- **Unlocks and upgrades:** `TechUnlocks` opens every build order and each
  military tech's upgrade price; `RegimentUpgrades` re-equips a regiment to the
  newest type its techs open (minors follow).
- **Attack price:** 100 ducats a Great Power land battle (`ArmyAttackCost`);
  ×0.75 Industrial Machinery, ×0.85 Modern Military Funding, and a charter
  holder's interception and raids rise 25%.
- **Transport:** road 2 needs Road Construction; rail needs Early Steam
  (flat), Later Steam (hills, swamps), Dynamite (mountains).
- **Rivals:** AI courts fill slots via `ResearchTurn`; a court at its floor
  keeps one study at Low (DR-20261113-24).
- **Goal slot:** orders the queue, funds nothing, saved (`ResearchState.goal`,
  DR-20261111-21).
- **UI:** `RESEARCH` opens the college: goal strip, slots, the one press,
  AVAILABLE/KNOWN tabs, a tech-tree door. Slots show ducats and a gauge
  (`ResearchBar`); every advance prints what it opens
  (`TechCatalog.payoff_text`); touch never hovers. The tree lays advances by
  depth (`TechTreeLayout`).
- **Phone sheet (DR-20261120-03):** the college budgets its plate; the window
  yields (`ResearchSheetFit`).
- **The court's pick (DR-20261121-01):** idle slot prints in gold the study
  policy would open (`MapPlayResearchPick`,
  `AiResearchPlanner.read_free_slot`); an unfundable door is not named
  (`#484`); nothing assigned or spent.

## Deferred (REQ-P2-02)

No rule is deferred; gaps: [`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/tech_catalog.gd`, `tech_audit.gd` | catalog, costs, caps, validation |
| `scripts/rules/tech_unlocks.gd`, `tech_plan.gd`, `tech_order.gd` | what a tech opens, state/road, queue order |
| `scripts/rules/tech_tree_layout.gd` | chart columns, edges, ancestor cone |
| `scripts/rules/research_state.gd`, `research_slots.gd`, `research_funding.gd` | slots, funding, saves, presets, floor |
| `scripts/rules/research_batch.gd` | the one press: plan, line, receipt |
| `scripts/rules/research_walk.gd` | the priced walk rows and press read |
| `scripts/rules/research_turn.gd` | Research phase, preview |
| `scripts/rules/tech_discovery.gd` | revealed commodities |
| `scripts/rules/regiment_upgrades.gd`, `army_attack_cost.gd` | re-equipping, attack treasury |
| `scripts/ui/research_panel.gd`, `research_head_strip.gd`, `research_sheet_fit.gd`, `research_fund_press.gd` | shell, head, fit, press |
| `scripts/ui/tech_tree_*.gd` | full-screen chart |
| `scripts/ui/research_queue_desk.gd`, `research_slot_price.gd` | slot walk, price |
| `scripts/ui/research_row.gd`, `research_slot_row.gd`, `research_bar.gd` | rows, spend, gauge |
| `scripts/ui/tech_icons.gd` | tech → medallion |

Rules stay node-free (`REQ-P3-03`); the panel emits intents.

## Tests

`test_research_rules`, plus `test_improvement_system`,
`test_army_field_rules`, `test_battle_rules`.
