# Advanced start

Open a new campaign at turn 50 (1598) or turn 100 (1698) with the courts
already grown (wiki:
[advanced-starts](https://github.com/waigore/empires-of-the-sea/wiki/advanced-starts),
[DR-20261110-06](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261110-06)).

**Pillars:** P2 (setup fidelity), P5 (setup choice), P3 (pure bootstrap), P4.

## Choosing it

`NEW GAME` → **Opening**: turn 0, 50 or 100. The preset is fixed for the
campaign; it is saved with the session (`advanced_start`).

## What the tier gives

| | Turn 50 | Turn 100 |
|---|---|---|
| Treasury | 20,000 | 40,000 |
| Workforce | 16 peasants | 16 peasants + 4 apprentices |
| Techs | 23 fixed | 45 fixed |
| Civilians | 3 Explorer, 3 Builder, 2 Engineer, 1 Spy, 1 Merchant | +1 each, +1 Rail Builder |
| Regiments | 6 balanced | 12 balanced |
| Cargo galleons | 1 at the seat | 6 at the seat |
| Diplomacy | Consulates with Old World Minors and met Tribes | Embassies |
| New World | 62.5% charted | All charted, up to 6 colonies per crown |
| Estates | 25% developed, 50% prospected | 50% developed, 75% prospected |

Every Great Power gets the same tier; the human's fog is the only fog painted
(rival fog exploration is deferred). Grain and luxuries are seeded for 20
turns, the same rule the turn-0 start uses.

## Rules

- **Colonies:** each crown grows up to six contiguous Tribe provinces from the
  Passage shore, claiming in rotation so no crown is boxed out. A Tribe keeps
  at least one province and its capital; when the New World is too small some
  crowns hold fewer.
- **Chart:** revealed provinces are fully visible, their water fogged; water
  beside a crown's own colonies is fully visible.
- **Estates:** a developed mineral tile is prospected first; roads run from the
  estate to its province town over the crown's own land. There is no ocean
  road.
- **Minor deeds:** 25%/50% of Minor Nation resource tiles are bought
  round-robin and recorded as deeds; the province stays with its owner.
- **Rosters:** a civilian roster larger than the capital province spills into
  the crown's other provinces, seat first.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/advanced_start.gd` | presets, tech lists, muster plan |
| `scripts/rules/advanced_world.gd` | colonies and inherited chart |
| `scripts/rules/advanced_estates.gd` | prospecting, estates, deeds |
| `scripts/map/map_play_advanced.gd` | one-pass play adapter |
| `scripts/session/game_config.gd` | the setup choice |

Rules are `RefCounted` and node-free (`REQ-P3-03`); `MapScreen` applies the
preset once at new-game time, after the HUD's ledger exists.

## Tests

`tests/test_advanced_start.gd` — tier tables, tech closure, balanced muster,
colonies (contiguity, Tribe survival, parity), chart, estates, deeds, and the
live screen path for both tiers.

```bash
gd-tools test tests/test_advanced_start.gd
```
