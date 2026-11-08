# Diplomacy

War, peace, alliances, the overture chain and foreign aid (wiki:
[diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy)).
Open from the top-bar `COURT` seal.

**Pillars:** P2 (rules), P3 (pure rules + panel), P1 (court panel), P4 (no
per-frame work).

## Implemented

- **Relations** (`DiplomacyState`): one score per faction pair (0–100) plus war
  state, `sinceTurn` and `lastInteractionTurn`; same-region pairs seed at 50,
  cross-region pairs wait for first contact.
- **Auto-embassy:** GP pairs start at Embassy both ways; it survives war and
  peace.
- **Relation bands:** Hostile 0–25, Neutral 26–50, Friendly 51–75, Allied
  76–100; the panel shows the ladder, never the score.
- **Decay:** each non-war pair drifts 4.0 toward 50 at phase end; a score event
  that turn skips decay. War freezes the score.
- **War / peace:** war needs peace, freezes the score, and clears alliances and
  overtures (GP pairs keep Embassy); invasion and battles need war.
  Minors/Tribes accept peace; a GP at Neutral (26) or better.
- **Alliances:** offer at Friendly or better; an AI GP accepts at Allied (76).
  Breaking or refusing one costs −50 with the former ally and −10 with other
  GPs; alliance and war never coexist.
- **Call to arms:** a GP war declaration calls every formal ally of the defender
  from the preceding turn, once. AI allies join at relation 50+; the human's
  call suspends the turn until answered. Refusing breaks the treaty with the
  unified penalty.
- **Overture chain:** Consulate £500 → Embassy £1,000 → NAP free → Join Empire
  £5,000 + £2,000 per target province; one per target per turn. Minor/Tribe
  embassies need Diplomatic Expertise.
- **Join Empire:** a Minor is absorbed; a Tribe becomes a colony; a GP must be
  nearly defeated (≤3 provinces, no capital) and needs Empire Building.
- **Grant Aid:** £1,000 multiples, embassy required, fixed +5 relation.
- **Set Subsidy:** 5–20% in fives, Minor/Tribe only, embassy required, no
  treasury charge; dies on war, lost embassy or cancel.
- **First contact:** a Tribe enters the court only when a non-unknown tile in
  its provinces is visible; sea-reach intel alone does not count.
- **Rival AI courts:** each AI GP scores war desire and emits at most one legal
  order per turn; see [`ai.md`](ai.md).

## Deferred (REQ-P2-02)

- Intervention and AI overtures/alliances/peace offers to the human court.
- Market-side subsidy pricing, trade-deal relation boosts, FTP and boycotts
  (no faction counterparty yet).
- Spy, Merchant `purchase_land`, colony profit share and near-defeat land war.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/diplomacy_catalog.gd` | costs, bands, ladder, tech gates |
| `scripts/rules/diplomacy_state.gd` | relations, overtures, subsidies, events |
| `scripts/rules/diplomacy_rules.gd` | war, peace, alliance, overture |
| `scripts/rules/call_to_arms.gd` | mutual-defence calls and answers |
| `scripts/rules/diplomacy_aid.gd` | grant aid and subsidies |
| `scripts/rules/diplomacy_orders.gd` | validation + order catalogue |
| `scripts/ui/diplomacy_panel.gd` | court ledger and shell |
| `scripts/map/map_play_diplomacy.gd` | intents, first contact, phase |

No node deps in rules (`REQ-P3-03`). Panel → `DiplomacyOrders.apply`; phase →
`DiplomacyState.end_turn`.

## Tests

`test_diplomacy_state`, `test_diplomacy_orders`, `test_diplomacy_panel`,
`test_diplomacy_screen`, `test_call_to_arms`.

```bash
gd-tools test --coverage --min 80
```
