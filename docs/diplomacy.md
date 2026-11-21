# Diplomacy

Wars, treaties, aid, intervention, chronicle — wiki
[diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy).

**Pillars:** P1–P4.

## Implemented

- **Relations** (`DiplomacyState`): score, war; seed 50;
  bands 0–25/26–50/51–75/76–100; GP pairs keep Embassy in war.
- **Decay:** pairs at peace drift to 50; war holds.
- **Spy death:** −8 a Spy killed abroad.
- **War / peace:** war needs peace, freezes the score, clears overtures
  (GP pairs keep Embassy); battles need war, not a Tribe whose land a crown
  bought. Minors/Tribes accept peace; GP 26+.
- **Alliances:** offer at 51+; AI accepts at 76; human answers. Breaking costs −50 with
  ally, −10 with others; never in war.
- **Warmth gates:** refusals name the gate's distance up the herald meter
  (`gate_line`).
- **Call to arms:** a GP war calls each ally once. AI allies join 50+;
  human calls wait; refusal breaks treaty.
- **Intervention:** embassy and deed holders answer a Minor/Tribe war:
  intervene, stand aside (lose embassy) or protest −10 (−5 with Propaganda);
  else protest at 26+. **A deed is a stake** (`DeedProtection`): one lifts trial
  to 25% and blocks stand-aside, two to 50%; a deed-only court keeps its embassy.
- **Overture chain:** Consulate £500 → Embassy £1,000 → NAP free → Join Empire
  £5,000 + £2,000/province; one per target/turn; Minor/Tribe embassies need
  Diplomatic Expertise.
- **Join Empire:** absorbs a Minor, colonizes a Tribe; a GP answers if nearly
  defeated or our power is twice its own; Empire Building gates it.
- **Aid & land:** Grant Aid stepped in £1,000s at embassy (+5 each); Subsidy 5–20% in
  fives, Minor/Tribe only; Merchant land 15× base, one deed/tile.
- **Trade terms** (`DiplomacyTrade`): pacts and boycotts publish.
  **Favoured pact** (GP–GP, embassy, accepts 65+): imports 95%, exports
  105%; war ends it. **Boycott** (needs a colony, GP at peace): no trade with
  our colony Tribes (no fill); its terms drop 10%, subsidies to our colonies
  cancelled, deeds and aid barred; war revokes. **Subsidy:** that court's deals
  pay p% more, earn p% less. Rails 70–150% buy, 50–130% sell.
- **First contact:** a Tribe enters court on a seen tile in its land;
  rivals open at turn close.
- **Colonies:** the `COLONIES ›` door ([`colonies`](colonies.md)).
- **Chronicle:** `Year Y (Turn N)`.
- **Power line:** GP score against yours: red stronger, green matched.
- **Arms:** each court's shield on row, page and dossier.
- **Dossier:** evidence, suspicion, behaviour —
  [`intel-dossier.md`](intel-dossier.md).
- **Diplomatic lens** (**P**): blue yours, green friendly, grey neutral, red war.
- **Rival AI courts:** one order a turn ([`ai.md`](ai.md));
  below 50 desire, white peace.
- **Own envoy** (`MapPlayDiplomacyPick`): the sheet names the order the crown's
  planner would spend on the court in view, where it went instead, or the gate
  that holds it.

## Deferred (REQ-P2-02)

None; rival priced overtures live (`DiplomacyProposals` + asking ledger).
Ranked gaps: [`deferred.md`](deferred.md).

## Architecture

Rules: `diplomacy_catalog`, `diplomacy_state`, `diplomacy_rules`,
`diplomacy_overtures`, `diplomacy_aid`, `diplomacy_orders`,
`diplomacy_trade`, `diplomacy_proposals`, `diplomacy_history`, `diplomacy_survey`,
`call_to_arms`, `intervention`, `deed_protection`, `tribe_contact`. Map:
`map/diplomacy_lens`, `map/map_play_diplomacy`, `map/map_play_diplomacy_pick`,
`map/map_play_tribe_contact`.
UI: `ui/diplomacy_panel`, `court_trade`, `court_dossier`, `court_prompts`,
`faction_crest`. No nodes
(`REQ-P3-03`); panel → `DiplomacyOrders.apply`, phase → `end_turn`.

## Tests

Suites: `test_diplomacy_*`, `test_campaign_rules`, `test_intel_dossier`,
`test_espionage`, `test_heraldry`.

```bash
gd-tools test --coverage --min 80
```
