# Dialogue and mood

A court speaks once an act is done. Presentation only: the rules record events,
`DialogueEvents` reads one into a line and a face, and no mood or word ever
feeds an outcome (`REQ-P2-03`).

## Modules

| File | Job |
|------|-----|
| `scripts/rules/dialogue_catalog.gd` | Points and lines (`DialoguePoint/<category>/<situation>`) |
| `scripts/rules/dialogue_episodes.gd` | The `event` beats: verdicts, a study, the seat, a colony |
| `scripts/rules/dialogue_agenda*.gd` | The `agenda` beat: cadence, evidence gate, veiled points |
| `scripts/rules/dialogue_mood.gd` | The eight moods, the mood machine |
| `scripts/rules/dialogue_events.gd` | Event/offer → speaker, point, face, text |
| `scripts/rules/dialogue_home.gd` | Which court answers the crown's own turn |
| `scripts/rules/dialogue_yarn.gd` | The standing word authored as Yarn |
| `scripts/rules/dialogue_locale.gd` | A locale key per line |
| `scripts/rules/yarn_*.gd` | Yarn parser, expression grammar, runner |
| `scripts/map/map_play_court_voice.gd` | Reads the resolved turn, records its beats |

## Where it shows

- **Court panel** — `THEIR ENVOY · <MOOD>` under the herald line: the newest
  voiced act, else the standing word. The reader never speaks.
- **Proposal banner** — a waiting offer's face and line (`CourtPrompts`).
- **Crown's charge** — a broadside names the seat and the age's terms; one press
  begins (DR-20261110-35).

## What is voiced

War and peace, alliances, overtures, calls to arms, intervention, proposals
answered, first contact, a standing remark per band, and a battle the crown
fought (the court that read the verdict answers it).
Bookkeeping — subsidy, aid, colony status — is silent. Every seventh turn a
known rival may slip a veiled word on its motive (DR-20261111-19).

The crown's own turn speaks too: the closest watching rival for a finished study,
the heaviest hostile host at the seat, a Tribe taken as a colony — read only by
the recording crown
([`DR-20261111-08`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261111-08)).

## Determinism

Every pick hashes `(turn, speaker, viewer, point)`: a reload speaks the same
words and face (`REQ-P2-04`). No RNG.

## Mood machine

| Condition | Face |
|-----------|------|
| Fresh, unremarkable offer | `considering` |
| Waited ≥ 3 turns | `impatient` / `skeptical` |
| Quality ≥ +0.5 | `pleased` / `gracious` |
| Quality ≤ −0.5 | `irritated` / `dismissive` |
| Otherwise | `calculating` / `considering` |

Quality is the surplus over the offer's requirement, normalised by 40 and
clamped to ±1.

## Yarn and localization

The standing word is authored as Yarn (`DialogueYarn.SOURCE`): one node per
point, titled with its content key, `category:`/`mood:` in its `tags:`;
`DialogueCatalog` merges that table with its own. The subset: lines with `#tags`,
`->` options with a `<<command>>`, `<<set>>`, `<<declare>>` (a default: a game-set
variable keeps its value), `<<if>>`/`<<elseif>>`/`<<else>>`/`<<endif>>`,
`<<jump>>`, `<<stop>>`, `{$variable}` interpolation; a malformed script is
refused with its line number; a jump loop is bounded — a script cannot hang a
refresh.

Each variant answers to `DialoguePoint/<point>/<variant>` through
`TranslationServer`: a translation ships without code, an untranslated key falls
back to the authored English (`REQ-P2-03`).

## Deferred

Translation words; era change stays blocked (no era model). Ranked: [`deferred.md`](deferred.md).
