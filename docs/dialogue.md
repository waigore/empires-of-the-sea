# Dialogue and mood

Presentation only: the rules record events, `DialogueEvents` reads one into a line
and a face, and no word or mood feeds an outcome (`REQ-P2-03`).

## Modules

| File | Job |
|------|-----|
| `scripts/rules/dialogue_catalog.gd` | Points and lines (`DialoguePoint/<category>/<situation>`) |
| `scripts/rules/dialogue_episodes.gd` | The `event` beats: verdicts, a study, the seat, a colony |
| `scripts/rules/dialogue_agenda*.gd` | The `agenda` beat: cadence, evidence gate, veiled points |
| `scripts/rules/dialogue_mood.gd` | The eight portrait moods and the mood machine |
| `scripts/rules/dialogue_events.gd` | Event/offer → speaker, point, face, text |
| `scripts/rules/dialogue_home.gd` | Which court answers the crown's own turn |
| `scripts/rules/dialogue_yarn.gd` | The standing word authored as Yarn |
| `scripts/rules/dialogue_locale.gd` | A locale key per line |
| `scripts/rules/yarn_*.gd` | Yarn parser, expression grammar, runner |
| `scripts/map/map_play_court_voice.gd` | Reads the resolved turn and records its beats |

## Where it shows

- **Court panel** — `THEIR ENVOY · <MOOD>` under the herald line: the pair's
  newest voiced act, else the standing word.
- **Proposal banner** — a waiting offer's face and line (`CourtPrompts`).

## What is voiced

War and peace, alliances, overtures, calls to arms, intervention, proposals
answered, first contact, one standing remark per band, and a battle the crown
fought. Bookkeeping — subsidy, aid, colony status — is silent. Every seventh turn
a known rival may slip a veiled word about its motive (DR-20261111-19).

The crown's own turn speaks too: the rival watching a finished study closest, the
heaviest owner of a host at the seat, a Tribe taken as a colony. Only the
recording crown reads them
([`DR-20261111-08`](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261111-08)).

## Determinism

Every pick hashes `(turn, speaker, viewer, point)`: a reload speaks the same
words and face (`REQ-P2-04`). No RNG; one line per refresh.

## Mood machine

| Condition | Face |
|-----------|------|
| Fresh, unremarkable offer | `considering` (open mood) |
| Waited ≥ 3 turns | `impatient` / `skeptical` |
| Quality ≥ +0.5 | `pleased` / `gracious` |
| Quality ≤ −0.5 | `irritated` / `dismissive` |
| Otherwise | `calculating` / `considering` |

Quality is the surplus over the requirement, normalised by 40, clamped to ±1.

## Yarn and localization

The standing word is authored as Yarn (`DialogueYarn.SOURCE`): one node per
point, titled with its content key, `category:`/`mood:` on its `tags:` line;
`DialogueCatalog` merges that table with its own. The subset: tagged lines, `->`
options with a `<<command>>`, `<<set>>`, the `<<if>>` family, `<<jump>>`,
`<<stop>>`, `{$variable}` interpolation; a malformed script is refused with its
line number.

Each variant answers to `DialoguePoint/<point>/<variant>` through
`TranslationServer`. `assets/locales/fr.po` answers all 124 variants — the key is
the `msgid`, the English a `#.` comment — and `DialogueLocale.SHIPPED` registers
it once, so the reader's OS tongue decides and an unanswered key falls back to
English (`REQ-P2-03`, DR-20261113-06). The suite fails on a variant left in
English, a lost `{speaker}`/`{other}`, or a dropped key.

## Deferred

An in-game tongue picker (the tongue follows the OS) and further tongues; era
change stays blocked (no era model). Ranked: [`deferred.md`](deferred.md).
