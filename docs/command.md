# The crown's commanders

Every general the crown's pool holds, in one ledger — his medals, what they buy
in the field, and the study that raises the cap next.

**Pillars:** P1 (period sheet chrome), P2 (the reading is the rules'), P3 (pure
projection), P5 (the pool is one press from where a crown asks who leads).

**Wiki:** [military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals)
§ Generals, § Count and tech-gated cap, § Medals. Decision: DR-20261115-11.

## Opening it

The army dossier's commander row carries **Commanders** (`G`). The ledger is the
muster roll's sibling: its own modal layer, the same sheet chrome, the same
pause-door park ([`armies.md`](armies.md) § the muster roll). The dossier keeps
one line naming who leads; the ledger explains what a medal buys, so a phone
sheet is not asked to wrap a paragraph over the orders.

## What it reads

| Line | Reads |
|------|-------|
| Count | `2 of 3 commanders`, or `4 commanders (cap 1)` above cap |
| Road | every cap rung — `Cap 2 · Organised Regiments — studied` |
| Commander | his christened name and his decoration count |
| Effects | `Line +2 · morale +10% · initiative +20` |
| Note | what one medal is worth, and the leader's own medals when none is free |

Generals are abstract (no province, no marker), so a row has no **Visit**: the
pool has no place on the chart to visit.

## The figures are the combat module's

`CommandLedger.effects` reads `ArmyModifiers`: the line a medal adds is
`deployment_limit`'s own, the morale share is its aura's, the initiative is its
medal weight. The cap is `GeneralRoster.cap_for`; the fallback is
`ArmyModifiers.fallback_medals` per side, because a leader's land bonus is
published per side. No second table exists (`REQ-P2-03`).

## What it never does

No appointment, muster, medal, save key or turn moves. A reading must not spawn
or christen a commander the turn has not, so the projection reads the stored
pool and never `pool()`.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/command_ledger.gd` | projection, cap road, medal effects |
| `scripts/map/map_play_command.gd` | the crown's pool, studies and leader |
| `scripts/ui/command_ledger_panel.gd` | the sheet |
| `scripts/ui/command_ledger_row.gd` | one commander |
| `scripts/ui/army_panel.gd` | the `Commanders` door |

## Tests

`tests/test_ledgers.gd` (the command section) — the pool and its medals, the
cap rungs and the next study, an above-cap roster, the effects and the
fallback, and the door, back and key.
