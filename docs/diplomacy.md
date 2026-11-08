# Diplomacy

War, peace, alliances, the overture chain and foreign aid (wiki:
[diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy)).
Open from the top-bar `COURT` seal.

**Pillars:** P2 (rules fidelity), P3 (pure rules + panel), P1 (heraldic court
panel), P4 (turn-based, no per-frame work).

## Implemented

- **Relations** (`DiplomacyState`): one score per faction pair in `[0, 100]`,
  state `AT_PEACE`/`AT_WAR`, `sinceTurn`, `lastInteractionTurn`. Same-region
  pairs seed at 50: Old World GP/GP, GP/Minor and Minor/Minor; New World
  Tribe/Tribe. Cross-region pairs wait for first contact.
- **Auto-embassy:** every GP pair starts at Embassy in both directions and it
  survives war and peace.
- **Relation bands:** Hostile 0–25, Neutral 26–50, Friendly 51–75, Allied
  76–100. The panel shows the herald ladder, never the score.
- **Decay:** each non-war pair drifts 4.0 toward 50 at phase end; any score
  event that turn skips decay for that pair. War freezes the score.
- **War / peace:** war is valid only at peace and freezes the score, clears
  formal alliances and overtures (GP pairs fall back to Embassy). Armies need
  war to enter foreign land or fight. Minors/Tribes always accept peace; a GP
  accepts at Neutral (26) or better.
- **Alliances:** offer to a GP at Friendly or better; an AI GP accepts at
  Allied (76). Breaking an alliance (or refusing one) applies −50 with the
  former ally and −10 with every other GP. Alliance and war never coexist.
- **Overture chain:** Trade Consulate £500 → Embassy £1,000 → NAP free → Join
  Empire £5,000 + £2,000 per target province. One overture per target per turn;
  Minor/Tribe embassies need Diplomatic Expertise.
- **Join Empire:** a Minor is absorbed (provinces transfer, faction removed);
  a Tribe becomes a colony without losing provinces; a GP must be nearly
  defeated (≤3 provinces and no capital) and needs Empire Building.
- **Grant Aid:** £1,000 multiples, needs an embassy, and gives a fixed +5
  relation.
- **Set Subsidy:** 5–20% in steps of 5, Minor/Tribe only, embassy required, no
  charge. A subsidy dies on war, loss of embassy, or manual cancel.
- **First contact:** a Tribe enters the court only with a non-unknown tile in
  one of its provinces; sea-reach intel alone does not count.

## Deferred (REQ-P2-02)

- Intervention, call-to-arms prompts, AI war declarations and the Full-AI
  planner; AI acceptance thresholds are interim (no AI order flow yet).
- Market-side subsidy pricing, trade-deal relation boosts, FTP and boycotts
  (the market has no faction counterparty yet).
- Spy, Merchant `purchase_land`, colony profit share and near-defeat land war.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/diplomacy_catalog.gd` | costs, bands, ladder, tech gates |
| `scripts/rules/diplomacy_relation.gd` | one pair record |
| `scripts/rules/diplomacy_state.gd` | relations, overtures, subsidies, events |
| `scripts/rules/diplomacy_rules.gd` | war, peace, alliance, overture |
| `scripts/rules/diplomacy_aid.gd` | grant aid and subsidies |
| `scripts/rules/diplomacy_orders.gd` | validation + order catalogue |
| `scripts/ui/diplomacy_panel.gd` | the court ledger |
| `scripts/ui/diplomacy_hud.gd` | court shell assembly |
| `scripts/map/map_play_diplomacy.gd` | intents, first contact, phase |

No node deps in rules (`REQ-P3-03`). Panel → `DiplomacyOrders.apply`; phase →
`DiplomacyState.end_turn`.

## Tests

`test_diplomacy_state`, `test_diplomacy_orders`, `test_diplomacy_panel`,
`test_diplomacy_screen`.

```bash
gd-tools test --coverage --min 80
```
