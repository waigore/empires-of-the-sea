# Diplomacy

War, peace, treaties, aid, intervention, the chronicle (wiki:
[diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy)).

**Pillars:** P1–P4.

## Implemented

- **Relations** (`DiplomacyState`): pair score, war state, turn
  stamps; same-region seed 50. Bands 0–25/26–50/51–75/76–100 as a ladder,
  never scores. GP pairs start at Embassy; survives war and peace.
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
  choose: intervene, stand aside (lose embassy) or protest (−10; −5 vs
  Propaganda).
- **Overture chain:** Consulate £500 → Embassy £1,000 → NAP free → Join Empire
  £5,000 + £2,000/province; one per target per turn.
  Minor/Tribe embassies need Diplomatic Expertise.
- **Join Empire:** absorbs a Minor, colonizes a Tribe; nearly defeated GP
  (≤3 provinces, no capital) needs Empire Building.
- **Aid & land:** Grant Aid £1,000 multiples at embassy (+5); Subsidy
  5–20% in fives, Minor/Tribe only; Merchant land 15× base, one deed/tile.
- **First contact:** Tribe enters court once a seen tile sits in its
  provinces; sea-reach intel does not.
- **Chronicle** (`DiplomacyHistory`): unbounded; panel shows the pair newest
  first, `Year Y (Turn N)`; unmet crowns `Unknown faction`; no scores.
- **Dossier** (`IntelDossier`, `CourtDossier`): evidence, banded suspicion and
  behaviour per court ([`intel-dossier.md`](intel-dossier.md)).
- **Diplomatic lens** (`DIPLOMACY_LENS`, **P**): charted land washed blue
  (yours), green (friendly/allied), grey (neutral) or red (war). Taps select.
- **Rival AI courts:** one order per GP per turn ([`ai.md`](ai.md)).
  Below 50 war desire a rival offers white peace; either answer starts a
  3-turn cooldown (`diplomacy.peace_cooldown_turns`).

## Deferred (REQ-P2-02)

- Subsidy pricing, trade boosts, FTP, boycotts (no counterparty);
  Merchant overseas cargo, colony profit share, near-defeat land war.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/diplomacy_catalog.gd` | costs, bands, ladder, tech gates |
| `scripts/rules/diplomacy_state.gd` | relations, overtures, subsidies, events |
| `scripts/rules/diplomacy_rules.gd` | war, peace, alliance, overture |
| `scripts/rules/call_to_arms.gd` | mutual-defence calls and answers |
| `scripts/rules/intervention.gd` | third-party war choices |
| `scripts/rules/diplomacy_aid.gd` | grant aid and subsidies |
| `scripts/rules/diplomacy_orders.gd` | validation, catalogue |
| `scripts/rules/diplomacy_proposals.gd` | rival proposals, answers |
| `scripts/rules/diplomacy_history.gd` | chronicle, masking, stamps |
| `scripts/rules/diplomacy_survey.gd` | lens bands, run merge |
| `scripts/map/diplomacy_lens.gd` | political wash |
| `scripts/rules/intel_dossier.gd` | dossier evidence, weights, bands |
| `scripts/ui/diplomacy_panel.gd` | court ledger and shell |
| `scripts/ui/court_dossier.gd` | dossier block |
| `scripts/ui/court_prompts.gd` | consent/proposal banners |
| `scripts/ui/diplomacy_history_panel.gd` | chronicle rows |
| `scripts/map/map_play_diplomacy.gd` | intents, first contact, phase |

Rules need no nodes (`REQ-P3-03`); panel → `DiplomacyOrders.apply`, phase →
`end_turn`.

## Tests

Suites: `test_diplomacy_*`, `test_call_to_arms`, `test_intervention`,
`test_intel_dossier`, `test_espionage`.

```bash
gd-tools test --coverage --min 80
```
