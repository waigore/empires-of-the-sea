# Court dossier

The player's intelligence reading of a rival court (wiki:
[AI dossier](https://github.com/waigore/empires-of-the-sea/wiki/ai-dossier),
[hidden agendas](https://github.com/waigore/empires-of-the-sea/wiki/hidden-agendas)).
The court panel carries a summary under the chronicle; its button opens the full
sheet over the map.

**Pillars:** P2 rules, P3 pure, P5 discoverability, P1 court.

## Summary (court panel)

- **Reading** — the strongest suspicion with its band and confidence
  (`Possible 25%`), or a plain "too little to band" line.
- **Bands** — 0–2 Unknown, 3–5 Possible (25%), 6–8 Likely (60%), 9–10 Almost
  certain (85%), 11+ Confirmed (100%); `Confirmed` never names the truth.
- **Evidence and behaviour** — the three newest acts, stamped, then counted
  provinces, wars, alliances and calls refused.

## Full sheet

`Full dossier · N observations · timeline` opens a sheet on the HUD:

| Section | Shows |
|---------|-------|
| Intel | Leader and archetype, provinces against yours, the herald's word |
| Suspicion | One row per agenda, tap to unfold **its timeline**: turn, act, points |
| Timeline | Every observation, newest first, stamped |
| Behaviour | War/alliance/peace counts plus the spy's **build notes** |

The best-guess row starts open; Back/Escape closes it (`REQ-P5-07`).

## Evidence rules (DR-20261110-05, DR-20261110-25)

Only the subject's own acts count; the reading comes from the court chronicle
every save carries.

| Act | Agenda | Points |
|-----|--------|-------:|
| Declared war | warmonger | 2 (+1 vs a smaller court) |
| War on a former ally | backstabber | 4 |
| Broke an alliance | backstabber / isolationist | 3 / 1 |
| Declared war on a larger court | envy | 2 (+1 when you) |
| Refused a call to arms | isolationist | 2 |
| Stood aside, refused an offer | isolationist | 1 |
| Protested a lesser war | peacemaker | 1 |
| Intervened | peacemaker | 2 |
| White peace | peacemaker | 2 |
| Alliance, accepted offer, aid | peacemaker | 1 |
| Absorbed a court | warmonger | 1 |
| Study seen by your spy | tech_thief | 2 |

Spy observations belong to the crown that posted them, stamped with their turn.
A court's **builds** (estate, town, road, port, fort, rail)
under a spy's eye are notes, not evidence: they weigh on no agenda. Research is
otherwise hidden, so `tech_thief` has no other path.

The newest 50 observations are kept; older ones drop. Names are masked
against the viewer's contacts.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/intel_evidence.gd` | the chronicle read: weights, act copy, cap, masking |
| `scripts/rules/intel_dossier.gd` | bands, agenda rows, timelines, notes |
| `scripts/ui/court_dossier.gd` | the summary block in the court panel |
| `scripts/ui/court_dossier_screen.gd` | the full sheet and its timelines |
| `scripts/map/map_play_spies.gd` | writes a shadowed court's studies and builds |

The dossier never reads
`AiState`, so the truth cannot leak.

## Tests

`tests/test_intel_rules.gd`, `tests/test_intel_dossier.gd`, plus the dossier cases in
`tests/test_diplomacy_panel.gd`, `tests/test_espionage.gd`.

```bash
gd-tools test --no-cache tests/test_intel_rules.gd tests/test_intel_dossier.gd tests/test_diplomacy_panel.gd tests/test_espionage.gd
```
