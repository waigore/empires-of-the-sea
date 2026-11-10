# Diplomacy

War, peace, treaties, aid, intervention, the chronicle (wiki:
[diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy)).

**Pillars:** P1–P4.

## Implemented

- **Relations** (`DiplomacyState`): pair score, war state, turn stamps;
  same-region seed 50. Bands 0–25/26–50/51–75/76–100, ladder only. GP pairs
  start at Embassy and keep it through war and peace.
- **Decay:** non-war pairs drift 4.0 to 50 unless touched; war freezes.
- **Spy death:** spy killed abroad costs −8 vs host.
- **War / peace:** war requires peace, freezes the score, clears overtures
  (GP pairs keep Embassy); battles need war. Minors/Tribes accept peace; GP at
  26+.
- **Alliances:** offer at 51+; AI accepts at 76; human answers. Breaking
  costs −50 with the ally, −10 with others; never with war.
- **Call to arms:** a GP war calls each formal ally of the defender once. AI
  allies join at 50+; human calls wait; refusal breaks the treaty.
- **Intervention:** war on a Minor/Tribe lets embassy and deed holders
  intervene, stand aside (lose the embassy) or protest: −10, or −5 against a
  declarer holding Propaganda. A rival that does not join protests at 26+
  relation with the victim, else stands aside.
- **Overture chain:** Consulate £500 → Embassy £1,000 → NAP free → Join Empire
  £5,000 + £2,000/province; one per target per turn. Minor/Tribe embassies need
  Diplomatic Expertise.
- **Join Empire:** absorbs a Minor, colonizes a Tribe; a nearly defeated GP
  (≤3 provinces, no capital) needs Empire Building.
- **Aid & land:** Grant Aid £1,000 multiples at embassy (+5); Subsidy 5–20% in
  fives, Minor/Tribe only; Merchant land 15× base, one deed/tile.
- **Trade terms** (`DiplomacyTrade`): one global book cannot match sellers to
  buyers, so pacts, boycotts and subsidies publish price terms.
  **Favoured pact** (GP–GP, embassy, accepts at 65+): imports 95%, exports
  105%; war ends it. **Boycott** (needs a colony, GP at peace): target's terms
  drop 10%, its subsidies to our colonies are cancelled and further aid there
  is barred; war revokes.
  **Subsidy** prices the goods that court produces: we pay p% more, earn p%
  less. Rails 70–150% buy, 50–130% sell; the court and ledger state the rate.
- **First contact:** a Tribe enters court once a seen tile sits in its
  provinces; sea-reach intel does not.
- **Chronicle** (`DiplomacyHistory`): unbounded; newest first, `Year Y
  (Turn N)`; unmet crowns `Unknown faction`; no scores.
- **Dossier** (`IntelDossier`, `CourtDossier`): evidence, suspicion and
  behaviour per court ([`intel-dossier.md`](intel-dossier.md)).
- **Diplomatic lens** (`DIPLOMACY_LENS`, **P**): land washed blue (yours),
  green (friendly), grey (neutral), red (war).
- **Rival AI courts:** one order per turn ([`ai.md`](ai.md)): war, peace or any
  court-menu order. Below 50 desire a rival offers white peace; consent asks
  wait, one-sided acts land at once.

## Deferred (REQ-P2-02)

- Merchant overseas cargo, colony profit share, near-defeat land war.

## Architecture

Rules: `diplomacy_catalog` (costs, bands, gates), `diplomacy_state`,
`diplomacy_rules`, `diplomacy_aid`, `diplomacy_orders` (validate/apply),
`diplomacy_trade` (pacts, boycotts, price terms), `diplomacy_proposals`,
`diplomacy_history`, `diplomacy_survey`, `call_to_arms`, `intervention`,
`intel_dossier`. Map glue: `map/diplomacy_lens`, `map/map_play_diplomacy`. UI:
`ui/diplomacy_panel`, `court_trade`, `court_dossier`, `court_prompts`,
`diplomacy_history_panel`. Rules need no nodes (`REQ-P3-03`); panel →
`DiplomacyOrders.apply`, phase → `end_turn`.

## Tests

Suites: `test_diplomacy_*` (incl. `test_diplomacy_trade`), `test_call_to_arms`,
`test_intervention`, `test_intel_dossier`, `test_espionage`.

```bash
gd-tools test --coverage --min 80
```
