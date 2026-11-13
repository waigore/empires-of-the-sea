# Dialogue and mood

A court speaks once an act is done. Presentation only: `DialogueEvents` reads
the recorded events into a line and a face; no word feeds an outcome
(`REQ-P2-03`).

## Modules

| File | Job |
|------|-----|
| `scripts/rules/dialogue_catalog.gd` | Points and lines (`DialoguePoint/<category>/<situation>`) |
| `scripts/rules/dialogue_episodes.gd` | The `event` beats: verdicts, a study, the seat |
| `scripts/rules/dialogue_agenda*.gd` | The `agenda` beat: cadence, veiled points |
| `scripts/rules/dialogue_mood.gd` | The eight moods and the machine |
| `scripts/rules/dialogue_events.gd` | Event/offer → speaker, point, face, text |
| `scripts/rules/dialogue_yarn.gd` | The standing word, as Yarn |
| `scripts/rules/dialogue_locale.gd` | Locale keys, and every tongue that ships |
| `scripts/ui/tongue_*.gd` | The settings page that picks the tongue, and its record |
| `scripts/rules/yarn_*.gd` | Yarn parser, expression grammar, runner |
| `scripts/map/map_play_court_voice.gd` | Reads the resolved turn, records its beats |

## Where it shows

- **Court panel** — `THEIR ENVOY · <MOOD>` under the herald: the newest voiced
  act, else the standing word. The reader never speaks.
- **Proposal banner** — a waiting offer's face and line (`CourtPrompts`).
- **Crown's charge** — a broadside names the seat and the age's terms; one press
  begins ([DR-20261110-35](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261110-35)).

## What is voiced

War and peace, alliances, overtures, calls to arms, intervention, proposals
answered, first contact, a standing remark per band, and a battle the crown
fought. Bookkeeping (subsidy, aid, colony status) is silent. Every seventh
turn a known rival may slip a veiled word on its motive (DR-20261111-19).

The crown's own turn speaks too (a study, a host at the seat, a Tribe taken),
read only by the recording crown
([`DR-20261111-08`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261111-08)).

## Determinism

Every pick hashes `(turn, speaker, viewer, point)`: a reload speaks the same
words (`REQ-P2-04`). No RNG.

## Mood machine

| Condition | Face |
|-----------|------|
| Fresh, unremarkable offer | `considering` |
| Waited ≥ 3 turns | `impatient` / `skeptical` |
| Quality ≥ +0.5 | `pleased` / `gracious` |
| Quality ≤ −0.5 | `irritated` / `dismissive` |
| Otherwise | `calculating` / `considering` |

Quality is the surplus over the requirement, normalised by 40, clamped to ±1.

## Yarn and localization

The standing word is Yarn (`DialogueYarn.SOURCE`): one node per point titled
with its content key, `category:`/`mood:` in `tags:`, merged by
`DialogueCatalog`. The subset: `#tags`, `->` options with a `<<command>>`,
`<<set>>`, `<<declare>>`, `<<if>>` / `<<elseif>>` / `<<else>>` / `<<endif>>`,
`<<jump>>`, `<<stop>>` and `{$variable}`; a malformed script is refused with its
line number, a jump loop bounded.

Each variant answers to `DialoguePoint/<point>/<variant>` through
`TranslationServer`; an untranslated key keeps the authored English
(`REQ-P2-03`). `fr.po` and `es.po` ship, each answering every variant; any `.po`
in `assets/locales/` is a tongue the build learns, and CI holds every file to the
catalogue. The device's tongue decides unless the reader picks one: the settings
door on the title screen and in the pause menu opens `TonguePage`, and the pick
moves the next line and is kept in `user://tongue.cfg` (`REQ-P5-07`).

## Deferred

Era change blocked; more tongues are content. Ranked:
[`deferred.md`](deferred.md).
