# Dialogue and mood

A court speaks once an act is done. Presentation only: the rules layer records
events, `DialogueEvents` reads one back into a line and a face, and no mood or
word ever feeds an outcome (`REQ-P2-03`).

## Modules

| File | Job |
|------|-----|
| `scripts/rules/dialogue_catalog.gd` | Points and lines (`DialoguePoint/<category>/<situation>`) |
| `scripts/rules/dialogue_episodes.gd` | The `event` beats: verdicts, a study, the seat, a colony |
| `scripts/rules/dialogue_mood.gd` | The eight portrait moods and the mood machine |
| `scripts/rules/dialogue_events.gd` | Event/offer → speaker, point, face, text |
| `scripts/rules/dialogue_home.gd` | Which court answers the crown's own turn |
| `scripts/map/map_play_court_voice.gd` | Reads the resolved turn and records its beats |

## Where it shows

- **Court panel** — `THEIR ENVOY · <MOOD>` under the herald line: the pair's
  newest voiced act, else the standing word for the current band. The reader is
  never the speaker.
- **Proposal banner** — a waiting offer carries the proposing court's face and
  line above Accept / Refuse (`CourtPrompts`).

## What is voiced

War and peace, alliances formed and broken, overtures, calls to arms,
interventions, proposals answered, first contact, one standing remark per band,
and a battle the crown fought (the court that read the verdict answers the
field, the siege or the water; the line stays out of the chronicle). Bookkeeping
— subsidy, aid, colony status — is silent.

The crown's own turn speaks too. A finished study is answered by the rival that
watches it closest (lowest relation, ties by id) — one beat a turn, naming the
costliest study. A hostile host in the crown's capital province is answered by
its heaviest owner while the crown still holds the seat. A Tribe taken as a
colony answers for its flag. Only the recording crown reads these three, so a
rival never quotes the crown to itself
([`DR-20261111-08`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261111-08)).

## Determinism

Every pick is a stable hash of `(turn, speaker, viewer, point)`: a reloaded
campaign speaks the same words and wears the same face (`REQ-P2-04`). No RNG,
no per-frame work — one line per panel refresh.

## Mood machine

A waiting offer's face reads two inputs, then the seed breaks the tie:

| Condition | Face |
|-----------|------|
| Fresh, unremarkable offer | `considering` (open mood) |
| Waited ≥ 3 turns | `impatient` / `skeptical` |
| Quality ≥ +0.5 | `pleased` / `gracious` |
| Quality ≤ −0.5 | `irritated` / `dismissive` |
| Otherwise | `calculating` / `considering` |

Quality is the relation surplus over what the offer requires (`ALLIANCE_MIN_SCORE`,
`PEACE_MIN_SCORE`, NAP / Join Empire), normalised by 40 points, clamped to ±1.

## The crown's charge

Before the first turn a broadside addresses the player's leader, names the seat
and prints the age's terms; one press begins, and a load skips it
([`DR-20261110-35`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261110-35)).

## Deferred

Yarn scripts and localization, the agenda comment cadence (`dialogueSeed % 7`),
and era-change beats — the campaign has no era model to announce
([`DR-20261110-04`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261110-04)).
