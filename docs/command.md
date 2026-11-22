# The crown's commanders

Every general the pool holds — medals, the next cap study, the fights the court
would lead.

**Pillars:** P1 chrome, P2 fidelity, P3 pure projection, P5 one press.

**Wiki:** [military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals)
§ Generals, § Count and tech-gated cap, § Medals, § Assignment. Decisions:
DR-20261115-11, DR-20261122-02, DR-20261122-22.

## Opening it

The army dossier's commander row carries **Commanders** (`G`), on the muster
roll's chrome ([`armies.md`](armies.md)). The dossier keeps one line naming who
leads.

## What it reads

| Line | Reads |
|------|-------|
| Count | `2 of 3 commanders`, or `4 commanders (cap 1)` above cap |
| Counsel | the fights the court would lead, and which commanders answer |
| Road | every cap rung — `Cap 2 · Organised Regiments — studied` |
| Commander | his christened name and his decoration count |
| Effects | `Line +2 · morale +10% · initiative +20` |
| Note | what one medal is worth, and the leader's own medals when none is free |

No province or marker, so no **Visit**.

## The fights the court would lead

One gold line under the count names the fights the land pass would start, each
by the standard's title and the ground its order storms or relieves, and the
commanders that answer:

- `The court would send 2 hosts into battle — the field army at Tucapel to storm
  Cádiz and the Home Army to throw the host out of Lisbon — each led by a
  commander.`

A fight is a march the pass words as a storm or a relief; a frontier
advance, a rotation or walk home and the seat's split spend no commander. A
short pool reads `… its 2 commanders would lead 2, and the last host would fight
on the leader's own 2 medals` (§ Assignment). Three fights are named, the rest
counted; the draw is random, so no host is paired with a man.

The reading is `MapPlayCommandPick`: the plan THE CROWN'S ARMY prints, narrowed
to the fights, against the pool `CommandLedger` counts; nothing is appointed,
marched or awarded.

## Figures and limits

`CommandLedger.effects` reads `ArmyModifiers` — the line is `deployment_limit`'s,
the morale share its aura's, the initiative its medal weight; the cap is
`GeneralRoster.cap_for`, the fallback `ArmyModifiers.fallback_medals` (no second
table, `REQ-P2-03`). The projection reads the stored pool, never `pool()`, so a
reading cannot spawn a commander. No appointment, medal, save key or turn moves.

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

`tests/test_ledgers.gd` (command section) — the pool and medals, the cap rungs,
an above-cap roster, the effects and fallback, the named fights, and the door,
back and key. `tools/smoke/smoke_sheets.gd` opens it on the real map.