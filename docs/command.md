# The crown's commanders

Every general the crown's pool holds — medals, what they buy, the next cap
study, the hosts the court would lead.

**Pillars:** P1 chrome, P2 rules fidelity, P3 pure projection, P5 one press from
the pool.

**Wiki:** [military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals)
§ Generals, § Count and tech-gated cap, § Medals, § Assignment. Decisions:
DR-20261115-11, DR-20261122-02.

## Opening it

The army dossier's commander row carries **Commanders** (`G`), on the muster
roll's own layer and chrome ([`armies.md`](armies.md) § the muster roll). The
dossier keeps one line naming who leads.

## What it reads

| Line | Reads |
|------|-------|
| Count | `2 of 3 commanders`, or `4 commanders (cap 1)` above cap |
| Counsel | the hosts the court would lead and which commanders answer |
| Road | every cap rung — `Cap 2 · Organised Regiments — studied` |
| Commander | his christened name and his decoration count |
| Effects | `Line +2 · morale +10% · initiative +20` |
| Note | what one medal is worth, and the leader's own medals when none is free |

Generals have no province or marker, so a row has no **Visit**.

## The hosts the court would lead

One gold line under the count names the fights the land pass would start this
turn and the commanders that answer them:

- `The court would send 3 hosts into battle — its 2 commanders would lead 2, and
  the last host would fight on the leader's own 2 medals.`

A fight is a march the land pass words as a storm or a relief; a frontier
advance, a rotation or walk home and the seat's split spend no commander.
Binding draws one commander per attacking army, leaving the rest on the leader's
fallback (§ Assignment). The draw is random, so the line counts hosts, never a
name.

The reading is `MapPlayCommandPick`: the plan THE CROWN'S ARMY prints, narrowed
to the marches that fight, against the pool `CommandLedger` counts. Nothing
is appointed, marched or awarded.

## Figures and limits

`CommandLedger.effects` reads `ArmyModifiers` — the line is `deployment_limit`'s,
the morale share its aura's, the initiative its medal weight; the cap is
`GeneralRoster.cap_for`, the fallback `ArmyModifiers.fallback_medals`. No second
table exists (`REQ-P2-03`).

The projection reads the stored pool, never `pool()`, so a reading cannot spawn
a commander; `MapPlaySetup` seats every power at its cap. No appointment,
medal, save key or turn moves.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/command_ledger.gd` | projection, cap road, medal effects |
| `scripts/map/map_play_command.gd` | the crown's pool, studies and leader |
| `scripts/map/map_play_command_pick.gd` | the hosts the land pass would lead |
| `scripts/ui/command_ledger_panel.gd` | the sheet |
| `scripts/ui/command_ledger_row.gd` | one commander |
| `scripts/ui/army_panel.gd` | the `Commanders` door |

## Tests

`tests/test_ledgers.gd` (command section) — the pool and its medals, the cap
rungs, an above-cap roster, the effects and fallback, the hosts the court would
lead, and the door, back and key. `tools/smoke/smoke_sheets.gd` opens it on the
real map.