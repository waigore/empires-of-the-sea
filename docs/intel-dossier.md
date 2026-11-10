# Court dossier

The player's intelligence reading of a rival court (wiki:
[AI dossier](https://github.com/waigore/empires-of-the-sea/wiki/ai-dossier),
[hidden agendas](https://github.com/waigore/empires-of-the-sea/wiki/hidden-agendas)).
Sits under the chronicle in the court panel, on the selected crown.

**Pillars:** P2 rules, P3 pure rules, P5 discoverability, P1 court.

## What it shows

- **Reading** — the strongest agenda suspicion with its band and confidence
  (`Possible 25%`), or a plain "too little to band" line.
- **Bands** — every agenda that has reached `Possible`: 0–2 Unknown (0%),
  3–5 Possible (25%), 6–8 Likely (60%), 9–10 Almost certain (85%), 11+
  Confirmed (100%). `Confirmed` still does not name the truth.
- **Evidence** — the three newest observable acts, calendar-stamped; older
  ones are counted, not listed.
- **Behaviour** — provinces held, wars declared, alliances signed, calls to
  arms refused. Counts, never inferences.

## Evidence rules (DR-20261110-05)

Only the subject's own acts count; the reading is built from the court
chronicle, which every save already carries.

| Act | Agenda | Points |
|-----|--------|-------:|
| Declared war | warmonger | 2 (+1 vs a smaller court) |
| Declared war on a former ally | backstabber | 4 |
| Broke a formal alliance | backstabber / isolationist | 3 / 1 |
| Declared war on a larger court | envy | 2 (+1 when that court is you) |
| Refused a call to arms | isolationist | 2 |
| Stood aside in an intervention | isolationist | 1 |
| Protested a war on a lesser court | peacemaker | 1 |
| Refused a rival's offer | isolationist | 1 |
| Intervened against an aggressor | peacemaker | 2 |
| Concluded a white peace | peacemaker | 2 |
| Signed a formal alliance | peacemaker | 1 |
| Accepted a rival's offer | peacemaker | 1 |
| Sent aid | peacemaker | 1 |
| Absorbed a court (Join Empire) | warmonger | 1 |

`tech_thief` has no evidence path: its spy evidence was retired with that work
order, so its band stays Unknown.

The newest 50 observations are kept; older ones drop. Evidence is computed on
demand, so a save round-trip needs no extra field. Names reach the page masked
against the viewer's contacts — an unmet court is "an unknown court".

## Architecture

| File | Role |
|------|------|
| `scripts/rules/intel_dossier.gd` | evidence, weights, bands, best guess |
| `scripts/ui/court_dossier.gd` | the dossier block in the court panel |

Rules need no nodes (`REQ-P3-03`); the panel only renders what the rules
return (`REQ-P2-03`). The dossier never reads `AiState`: the true agenda
cannot leak by construction.

## Deferred (REQ-P2-02)

Spy and espionage evidence, behavioural notes on builds, and the full dossier
screen with a per-agenda timeline.

## Tests

`tests/test_intel_dossier.gd`, plus the dossier cases in
`tests/test_diplomacy_panel.gd`.

```bash
gd-tools test --no-cache tests/test_intel_dossier.gd tests/test_diplomacy_panel.gd
```
