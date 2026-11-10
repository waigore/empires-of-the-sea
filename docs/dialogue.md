# Dialogue and mood

A rival court speaks once an act is done. Presentation only: the rules layer
records events, `DialogueEvents` reads one back into a line and a face, and no
mood or word ever feeds an outcome (`REQ-P2-03`).

## Modules

| File | Job |
|------|-----|
| `scripts/rules/dialogue_catalog.gd` | Authored points and period lines (`DialoguePoint/<category>/<situation>`) |
| `scripts/rules/dialogue_mood.gd` | The eight portrait moods and the mood machine |
| `scripts/rules/dialogue_events.gd` | Event/offer → speaker, point, face, text |

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
cold). Bookkeeping acts (subsidy, aid, colony status) stay silent; the standing
word covers them.

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

The campaign opens on a printed broadside before the first turn: the crown
addresses the player's own leader, names the seat the chart confirmed, and
prints the age's terms — the win condition, the calendar chosen at setup and how
many rival crowns sail. One press begins the age; back and Escape are the same
one dismissal, so the gate never quits the app. The page prints what
`CampaignIntro` composed, and the pick is a stable salt of seed and crown, so a
replay speaks alike. A load installs the map screen directly and never repeats
the charge ([`DR-20261110-35`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261110-35)).

| File | Job |
|------|-----|
| `scripts/rules/campaign_intro.gd` | The charge: `intro/opening` copy, the age's terms, the salt |
| `scripts/ui/intro_screen.gd`, `scenes/intro.tscn` | The broadside page and its one action |

## Deferred

Yarn scripts and localization, the optional agenda comment cadence
(`dialogueSeed % 7`) and reactive beats on battles/era change
([`DR-20261110-04`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261110-04)).
