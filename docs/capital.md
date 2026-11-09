# Capital loss and a crown's fall

A captured capital is traceable because each seat is a province whose
`capital_of` names its crown. After the turn's battles, `CapitalLoss` resolves
every lost seat once, in ascending faction id (wiki:
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity)
§ Capital loss and reassignment).

**Pillars:** P2 (rules fidelity), P5 (visible consequences), P3 (pure rules).

## Reassignment

- The court moves to the lowest owned province in the same region that can seat
  it: sea-bound provinces first, then inland.
- The new seat takes the capital-choice tile ranking. No ports, roads or
  terrain are added, so a reassigned court can land away from the sea.
- A Great Power's new capital province gains town development 4; a Minor or
  Tribe keeps the province's own level. The old town keeps its development.
- `MapPlayTurn` keeps the player's session and economy capital in step.

## A crown falls

- A Great Power with no sea-bound province left in its original region falls.
- A Minor Nation or Tribe with no province left there falls.
- Every remaining province changes colours to the conqueror of the seat; the
  fallen crown's armies and fleets disband and its diplomacy is cleared.
- Join Empire absorption retires the absorbed seat instead: absorption is not a
  fall, so the court reports one outcome, not two.

## Persistence

`capital_of` and the capital tile are saved with each province. Legacy saves
infer the seat holder from the province owner and keep the regenerated capital
tile.

## Tests

`test_capital_loss` (rules, fall, stale seats, purge), `test_save_codec`
(relocated seat survives a load), `test_capital_choice`.

```bash
gd-tools test tests/test_capital_loss.gd
```
