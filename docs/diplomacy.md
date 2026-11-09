# Diplomacy

War, peace, alliances, overtures, aid and intervention (wiki:
[diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy)).
Open from the `COURT` seal.

**Pillars:** P2 rules, P3 pure rules + panel, P1 court, P4 no per-frame work.

## Implemented

- **Relations** (`DiplomacyState`): score per pair (0–100), war state and
  turn stamps; same-region seed 50, cross-region waits for contact.
- **Auto-embassy:** GP pairs start at Embassy both ways; survives war and peace.
- **Relation bands:** Hostile 0–25, Neutral 26–50, Friendly 51–75, Allied
  76–100; the panel shows the ladder, not the score.
- **Decay:** non-war pairs drift 4.0 toward 50 at phase end unless an event
  touched them; war freezes.
- **War / peace:** war needs peace, freezes the score and clears
  alliances/overtures (GP pairs keep Embassy); battles need war. Minors/Tribes
  accept peace; a GP at 26+.
- **Alliances:** offer at 51+; AI accepts at 76 and proposes at Allied
  relations; the human answers. Breaking costs −50 with the ally and −10
  with other GPs; alliance and war never coexist.
- **Call to arms:** a GP war calls each formal ally of the defender, once. AI
  allies join at 50+; human calls wait for the answer; refusing breaks the
  treaty (−50/−10).
- **Intervention:** a war on a Minor/Tribe offers each embassy court a choice:
  intervene (war on the aggressor), stand aside (lose the embassy) or protest
  (−10, or −5 vs Propaganda). AI rolls 0/25/50/80% bands.
- **Overture chain:** Consulate £500 → Embassy £1,000 → NAP free → Join Empire
  £5,000 + £2,000/province; one per target per turn; AI offers free stages.
  Minor/Tribe embassies need Diplomatic Expertise.
- **Join Empire:** absorbs a Minor, colonizes a Tribe; nearly defeated GP
  (≤3 provinces, no capital) needs Empire Building.
- **Aid & land:** Grant Aid £1,000 multiples at embassy (+5); Set Subsidy 5–20%
  in fives, Minor/Tribe only; Merchant land 15× base, one deed/tile.
- **First contact:** a Tribe enters court once a non-unknown tile in its
  provinces is visible; sea-reach intel does not count.
- **Rival AI courts:** one legal order per GP per turn; war, peace or a
  court-answered proposal ([`ai.md`](ai.md)). Below 50 war desire a rival
  offers white peace: accepting ends the war that turn, refusing changes
  nothing, either answer starts a 3-turn cooldown
  (`diplomacy.peace_cooldown_turns`, DR-20261109-07).

## Deferred (REQ-P2-02)

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
| `scripts/rules/diplomacy_proposals.gd` | rival proposals, answers |
| `scripts/ui/diplomacy_panel.gd` | court ledger and shell |
| `scripts/ui/court_prompts.gd` | consent/proposal banners |
| `scripts/map/map_play_diplomacy.gd` | intents, first contact, phase |

No node deps in rules (`REQ-P3-03`). Panel → `DiplomacyOrders.apply`; phase →
`DiplomacyState.end_turn`.

## Tests

Suites: `test_diplomacy_state/orders/panel/screen/proposals`,
`test_call_to_arms`, `test_intervention`.

```bash
gd-tools test --coverage --min 80
```
