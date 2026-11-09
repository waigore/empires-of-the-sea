# Diplomacy

War, peace, alliances, overtures, aid and intervention (wiki:
[diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy)).
Open from the `COURT` seal.

**Pillars:** P2 (rules), P3 (pure rules + panel), P1 (court panel), P4 (no
per-frame work).

## Implemented

- **Relations** (`DiplomacyState`): score per pair (0–100) plus war state and
  turn stamps; same-region seed 50, cross-region wait for contact.
- **Auto-embassy:** GP pairs start at Embassy both ways; survives war and peace.
- **Relation bands:** Hostile 0–25, Neutral 26–50, Friendly 51–75, Allied
  76–100; panel shows the ladder, never the score.
- **Decay:** non-war pairs drift 4.0 toward 50 at phase end; a score event that
  turn skips it. War freezes the score.
- **War / peace:** war needs peace, freezes the score and clears alliances and
  overtures (GP pairs keep Embassy); invasion and battles need war.
  Minors/Tribes accept peace; a GP at 26+.
- **Alliances:** offer at 51+; AI GP accepts at 76. Breaking or refusing costs
  −50 with the ally and −10 with other GPs; alliance and war never coexist.
- **Call to arms:** a GP war calls every formal ally of the defender from the
  preceding turn, once. AI allies join at 50+; human call suspends until
  answered. Refusing breaks the treaty with the unified penalty.
- **Intervention:** a war on a Minor/Tribe offers every embassy court one
  choice: intervene (war on the aggressor), stand aside (lose the embassy) or
  protest (−10, or −5 against Propaganda). AI rolls bands 0/25/50/80%.
- **Overture chain:** Consulate £500 → Embassy £1,000 → NAP free → Join Empire
  £5,000 + £2,000/province; one per target per turn. Minor/Tribe embassies need
  Diplomatic Expertise.
- **Join Empire:** absorbs a Minor, colonizes a Tribe; nearly defeated GP
  (≤3 provinces, no capital) needs Empire Building.
- **Grant Aid:** £1,000 multiples, embassy required, fixed +5 relation.
- **Land purchase:** Merchant buys a Minor/Tribe resource tile with embassy and
  no war; 15× base price, one deed per tile.
- **Set Subsidy:** 5–20% in fives, Minor/Tribe only, embassy required, no
  charge; dies on war, lost embassy or cancel.
- **First contact:** Tribe enters court when a non-unknown tile in its
  provinces is visible; sea-reach intel alone does not count.
- **Rival AI courts:** one legal order per AI GP per turn; see [`ai.md`](ai.md).

## Deferred (REQ-P2-02)

- AI overtures/alliances/peace offers to the human court.
- Market-side subsidy pricing, trade boosts, FTP and boycotts (no counterparty).
- Spy, Merchant overseas cargo, colony profit share, near-defeat land war.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/diplomacy_catalog.gd` | costs, bands, ladder, tech gates |
| `scripts/rules/diplomacy_state.gd` | relations, overtures, subsidies, events |
| `scripts/rules/diplomacy_rules.gd` | war, peace, alliance, overture |
| `scripts/rules/call_to_arms.gd` | mutual-defence calls and answers |
| `scripts/rules/intervention.gd` | third-party war choices |
| `scripts/rules/diplomacy_aid.gd` | grant aid and subsidies |
| `scripts/rules/diplomacy_orders.gd` | validation + order catalogue |
| `scripts/ui/diplomacy_panel.gd` | court ledger and shell |
| `scripts/map/map_play_diplomacy.gd` | intents, first contact, phase |

No node deps in rules (`REQ-P3-03`). Panel → `DiplomacyOrders.apply`; phase →
`DiplomacyState.end_turn`.

## Tests

`test_diplomacy_state`, `test_diplomacy_orders`, `test_diplomacy_panel`,
`test_diplomacy_screen`, `test_call_to_arms`, `test_intervention`.

```bash
gd-tools test --coverage --min 80
```
