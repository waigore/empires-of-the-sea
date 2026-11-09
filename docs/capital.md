# Capital loss and a crown's fall

A captured capital is detected against a snapshot taken before Combat: each
crown's seat (its owned province carrying the capital flag) is remembered, then
compared after the battles. `CapitalLoss` resolves every lost seat once, in
ascending faction id (wiki:
[capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity)
§ Capital loss and reassignment; DR-20261109-02).

**Pillars:** P2 (rules fidelity), P5 (visible consequences), P3 (pure rules).

## Reassignment

- The court moves to the first owned province in its original region: seaboard
  provinces (ascending id) first, then inland.
- The new seat's tile is the province tile nearest the province centre, ties by
  row then column — a stand-in for the absent `townTileKey`.
- A Great Power's new capital province gains town development 4; a Minor or
  Tribe keeps the province's own level.
- No ports, roads or terrain are added; the captured province's palace flag is
  cleared so the conqueror does not inherit a second capital.
- The player's session and economy capital reads follow the new seat.

## A crown falls

- A crown with no owned province left in its original region falls.
- Every remaining province changes colours to the conqueror of the lost seat;
  the fallen crown's armies, fleets and civilians disband and its diplomacy is
  cleared.
- Join Empire absorption happens outside this pass, so it reports once.

## Persistence

The capital flag and tile are saved with each province, so a relocated seat
reloads on its chosen tile.

## Tests

`test_capital_loss` (reassignment, fall, seats, purge), `test_save_codec`
(relocated seat survives a load), `test_capital_choice`.

```bash
gd-tools test tests/test_capital_loss.gd
```

