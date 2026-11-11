# Diplomacy

War, peace, treaties, aid, intervention, the chronicle (wiki:
[diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy)).

**Pillars:** P1–P4.

## Implemented

- **Relations** (`DiplomacyState`): pair score, war, turn stamps; same-region
  seed 50; bands 0–25/26–50/51–75/76–100, ladder only; GP pairs keep Embassy
  through war.
- **Decay:** non-war pairs drift 4.0 to 50; war freezes.
- **Spy death:** −8 for a Spy killed abroad.
- **War / peace:** war needs peace, freezes the score, clears overtures
  (GP pairs keep Embassy); battles need war. Minors/Tribes accept peace; GP 26+.
- **Alliances:** offer at 51+; AI accepts at 76; human answers. Breaking
  costs −50 with the ally, −10 with others; not in war.
- **Call to arms:** a GP war calls each ally once. AI allies join at 50+;
  human calls wait; refusal breaks the treaty.
- **Intervention:** a war on a Minor/Tribe lets embassy and deed holders
  answer: intervene, stand aside (losing the embassy) or protest −10 (−5 with
  Propaganda). Else it protests at 26+ relation, or stands aside. **A
  deed is a stake** (`DeedProtection`): one deed lifts the trial to 25% and
  blocks standing aside, two to 50%; a deed-only court loses no embassy.
  Declare War names them.
- **Overture chain:** Consulate £500 → Embassy £1,000 → NAP free → Join Empire
  £5,000 + £2,000/province; one per target per turn; Minor/Tribe embassies need
  Diplomatic Expertise.
- **Join Empire:** absorbs a Minor, colonizes a Tribe; a near-defeated GP
  (≤3 provinces) needs Empire Building.
- **Aid & land:** Grant Aid £1,000 multiples at embassy (+5); Subsidy 5–20% in
  fives, Minor/Tribe only; Merchant land 15× base, one deed/tile.
- **Trade terms** (`DiplomacyTrade`): pacts, boycotts and subsidies publish
  price terms; no deal book.
  **Favoured pact** (GP–GP, embassy, accepts at 65+): imports 95%, exports
  105%; war ends it. **Boycott** (needs a colony, GP at peace): target's terms
  drop 10%, its subsidies to our colonies are cancelled and aid there
  barred; war revokes.
  **Subsidy** prices that court's goods: we pay p% more, earn p%
  less. Rails 70–150% buy, 50–130% sell; court and ledger state the rate.
- **First contact:** a Tribe enters court on a seen tile in its provinces, not by
  sea-reach.
- **Chronicle** (`DiplomacyHistory`): unbounded; newest first, `Year Y
  (Turn N)`; unmet crowns `Unknown faction`.
- **Power line:** each Great Power row reads its score against yours — red
  stronger, green matched.
- **Dossier** (`IntelDossier`, `CourtDossier`): evidence, suspicion and
  behaviour per court ([`intel-dossier.md`](intel-dossier.md)).
- **Diplomatic lens** (`DIPLOMACY_LENS`, **P**): land washed blue (yours),
  green (friendly), grey (neutral), red (war).
- **Rival AI courts:** one order per turn ([`ai.md`](ai.md)): war, peace or the
  court menu. Below 50 desire: white peace; consent asks wait, one-sided acts
  land.

## Deferred (REQ-P2-02)

Rival GP–Tribe contact; colony suzerain favoured-partner (R7.1). See
[`deferred.md`](deferred.md).

## Architecture

Rules: `diplomacy_catalog` (costs, bands, gates), `diplomacy_state`,
`diplomacy_rules`, `diplomacy_aid`, `diplomacy_orders` (validate/apply),
`diplomacy_trade` (pacts, boycotts, price terms), `diplomacy_proposals`,
`diplomacy_history`, `diplomacy_survey`, `call_to_arms`, `intervention`, `deed_protection`. Map glue: `map/diplomacy_lens`, `map/map_play_diplomacy`. UI:
`ui/diplomacy_panel`, `court_trade`, `court_dossier`, `court_prompts`,
`diplomacy_history_panel`. Rules need no nodes (`REQ-P3-03`); panel →
`DiplomacyOrders.apply`, phase → `end_turn`.

## Tests

Suites: `test_diplomacy_*` (incl. `test_diplomacy_trade`), `test_call_to_arms`,
`test_intervention`, `test_deed_protection`, `test_intel_dossier`,
`test_espionage`.

```bash
gd-tools test --coverage --min 80
```
