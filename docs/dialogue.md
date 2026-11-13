# Dialogue and mood

A court speaks once an act is done. Presentation only: `DialogueEvents` reads
recorded events into a line and a face; no word feeds an outcome (`REQ-P2-03`).

## Modules

| File | Job |
|------|-----|
| `scripts/rules/dialogue_catalog.gd` | Points and lines (`DialoguePoint/<category>/<situation>`) |
| `scripts/rules/dialogue_episodes.gd` | The `event` beats |
| `scripts/rules/dialogue_agenda*.gd` | The `agenda` beat: cadence, veiled words |
| `scripts/rules/dialogue_mood.gd` | The eight moods and the machine |
| `scripts/rules/dialogue_events.gd` | Event/offer → speaker, point, face, text |
| `scripts/rules/dialogue_yarn.gd`, `yarn_*.gd` | The standing word as Yarn: parser, grammar, runner |
| `scripts/rules/dialogue_locale.gd` | Locale keys, and every tongue that ships |
| `scripts/rules/consent_copy.gd` | The consent prompts' words and their keys |
| `scripts/ui/tongue_*.gd` | The settings page that picks the tongue, and its record |
| `scripts/map/map_play_court_voice.gd` | Reads the resolved turn, records its beats |

## Where it shows

- **Court panel** — `THEIR ENVOY · <MOOD>`: the newest voiced act, else the
  standing word. The reader never speaks.
- **Proposal banner** — a waiting offer's face and line (`CourtPrompts`).
- **Crown's charge** — a broadside names the seat; one press begins
  ([DR-20261110-35](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261110-35)).

## What is voiced

War and peace, alliances, overtures, calls to arms, intervention, answered
proposals, first contact, a standing remark per band and a battle the crown
fought. Bookkeeping is silent; every seventh turn a known rival may slip a veiled
word on its motive (DR-20261111-19). The crown's own turn speaks too (a study, a
host at the seat, a Tribe taken), read only by itself (DR-20261111-08).

## Determinism

Every pick hashes `(turn, speaker, viewer, point)`: a reload speaks the same
words (`REQ-P2-04`).

## Mood machine

| Condition | Face |
|-----------|------|
| Fresh, unremarkable offer | `considering` |
| Waited ≥ 3 turns | `impatient` / `skeptical` |
| Quality ≥ +0.5 | `pleased` / `gracious` |
| Quality ≤ −0.5 | `irritated` / `dismissive` |
| Otherwise | `calculating` / `considering` |

Quality is the surplus over the requirement, normalised by 40, clamped to ±1.

## Yarn and tongues

The standing word is Yarn (`DialogueYarn.SOURCE`): one node per point titled
with its content key, `category:`/`mood:` in `tags:`, merged by
`DialogueCatalog`. The subset covers tags, options, sets, if-branches, jumps,
stops and variables; a malformed script is refused with its line number and a
jump loop is bounded.

Each variant answers to `DialoguePoint/<point>/<variant>` through
`TranslationServer`; an untranslated key keeps the authored English
(`REQ-P2-03`). `fr.po` and `es.po` ship, each answering every variant; any `.po`
in `assets/locales/` is a tongue, and CI holds every file to the catalogue. The device's tongue decides unless the reader picks one; `TonguePage`
on the title and the pause menu moves the next line and keeps the pick in
`user://tongue.cfg` (`REQ-P5-07`).

Blocking prompts answer to `Prompt/<subject>/<line>` (`ConsentCopy`): caption,
stakes, terms, the envoy's face, each answer. Banner and despatch read one
catalogue, filled after the tongue, so a translation names its own courts and
rates (`REQ-P5-05`).

## Deferred

Era change blocked; more tongues are content ([`deferred.md`](deferred.md)).
