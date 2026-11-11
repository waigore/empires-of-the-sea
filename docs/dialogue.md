# Dialogue and mood

A court speaks once an act is done. Presentation only: the rules layer
records events, `DialogueEvents` reads one back into a line and a face, and no
mood or word ever feeds an outcome (`REQ-P2-03`).

## Modules

| File | Job |
|------|-----|
| `scripts/rules/dialogue_catalog.gd` | Authored points and period lines (`DialoguePoint/<category>/<situation>`) |
| `scripts/rules/dialogue_episodes.gd` | The `event` beats: verdicts, a finished study, a host at the seat, a colony |
| `scripts/rules/dialogue_mood.gd` | The eight portrait moods and the mood machine |
| `scripts/rules/dialogue_events.gd` | Event/offer → speaker, point, face, text |
| `scripts/rules/dialogue_home.gd` | Which court answers the crown's own turn |
| `scripts/map/map_play_court_voice.gd` | Reads the resolved turn and records its beats |

## Where it shows

- **Court panel** — `THEIR ENVOY · <MOOD>` under the herald line: the pair's
  newest voiced act, else the court's standing word for the current relation
  band. The reader is never the speaker.
- **Proposal banner** — a waiting offer carries the proposing court's face and
  line above Accept / Refuse (`CourtPrompts`).

## What is voiced

War declared (either side), peace, alliance formed/broken, overtures
granted/accepted/refused/withdrawn, call to arms answered or refused,
intervention joined/stood aside/protested, proposals accepted or refused, first
contact — plus one standing remark per band (war, alliance, friendly, neutral,
cold). A battle the crown fought is voiced too: the court that read the verdict
answers the field, the siege or the water, and the line never enters the
diplomatic chronicle. Bookkeeping acts (subsidy, aid, colony status) stay
silent; the standing word covers them.

The crown's own turn also speaks. A study the Research phase finished is
answered by the rival that watches the crown most closely (the lowest relation,
ties by ascending id) — one beat a turn, naming the costliest study. A hostile
host standing in the crown's capital province at the turn's close is answered by
its heaviest owner, so long as the crown still holds the seat. A Tribe the crown
took as a colony answers for its lost flag. Only the crown reads these three: a
court never quotes the crown back to itself
([`DR-20261111-08`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261111-08)).

## Determinism

Every pick is a stable integer hash of `(turn, speaker, viewer, point)`, so a
reloaded campaign speaks the same words and wears the same face (`REQ-P2-04`).
No RNG, no per-frame work: one line per panel refresh.

## Mood machine

A waiting offer's face reads two inputs, then the seed breaks the tie:

| Condition | Face |
|-----------|------|
| Fresh, unremarkable offer | `considering` (open mood) |
| Waited ≥ 3 turns | `impatient` / `skeptical` |
| Quality ≥ +0.5 | `pleased` / `gracious` |
| Quality ≤ −0.5 | `irritated` / `dismissive` |
| Otherwise | `calculating` / `considering` |

Quality is the relation surplus over what the offer's own rules require
(`ALLIANCE_MIN_SCORE`, `PEACE_MIN_SCORE`, NAP / Join Empire), normalised by 40
points and clamped to ±1. Proposals store the turn they arrived on, which is
their stall counter.

## The crown's charge

Before the first turn a broadside addresses the player's leader, names the seat
the chart confirmed, and prints the age's terms (win condition, calendar, rival
count). One press begins; back and Escape are the same dismissal, so the gate
never quits. Copy comes from `CampaignIntro` with a stable seed/crown salt; a
load skips the charge
([`DR-20261110-35`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261110-35)).

| File | Job |
|------|-----|
| `scripts/rules/campaign_intro.gd` | `intro/opening` copy, terms, salt |
| `scripts/ui/intro_screen.gd`, `scenes/intro.tscn` | Broadside and its one action |

## Deferred

Yarn scripts and localization, the optional agenda comment cadence
(`dialogueSeed % 7`), and era-change beats — the campaign has no era model to
announce ([`DR-20261110-04`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261110-04)).
