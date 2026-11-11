# Difficulty

The rival courts' opening stores and their edge in the field and at sea, and
the bar the crown must clear, chosen when the chart is opened and fixed for the
campaign.

**Pillars:** P2 (rules fidelity), P3 (rules without view nodes), P5 (a stated
choice), P1 (setup chrome).

**Wiki:** [ruleset-config](https://github.com/waigore/empires-of-the-sea/wiki/ruleset-config)
§ Layers, [combat](https://github.com/waigore/empires-of-the-sea/wiki/combat)
§ Modifiers, [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval)
§ Naval Combat Resolution, [victory](https://github.com/waigore/empires-of-the-sea/wiki/victory)
§ Military victory,
[ai-architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture).
Decisions: DR-20261110-12, DR-20261111-24, DR-20261111-28.

## Levels

| Level | Rival stores | Rival strength (field and sea) | Crown's victory bar |
|-------|--------------|---------------------|---------------------|
| Introductory | 60% | 85% | 26 |
| Normal | 100% (published row) | 100% | 31 (published) |
| Hard | 140% | 115% | 36 |
| Impossible | 180% | 130% | 40 |

`Normal` is the published game: every court opens on the same row, fights on the
published maths and wins on 31. The other three are this product's data-shaped
choices (design records above); they never change an AI's decision algorithm
(wiki: ai-personalities). Every rival wins on 31 at every level; only the
crown's own bar moves.

## Implemented

- **Catalog:** `scripts/rules/difficulty.gd` — ordered ids, labels, hints, both
  percentage tables, `level_percent`, `normalize`, `scaled`/`scale_start`.
- **Choice:** the new-game screen offers the four levels and prints the effect in
  one line; the summary names the level.
- **Config + save:** `GameConfig` / `PlaySession` carry the choice; `SaveCodec`
  and `AiState` store it, so a load restores the level
  (wiki: campaign-persistence).
- **Rival opening stores:** a rival's ledger is founded from
  `PlayerEconomy.starting()` and scaled once on first read
  (`AiState.economy_for`); the human crown never passes through the scale.
- **Rival land strength:** `MapPlayLandTurn.battle_context` publishes
  `difficulty: {faction: multiplier}`; `ArmyModifiers.modifiers` folds it in
  after medals, feeding and leader, before terrain and forts. Auto-resolve and
  Quick Battle read the same context.
- **Rival sea strength:** `MapPlayNavalTurn.strength_multipliers` hands the table
  to `NavalCombat` after the squadron's rations; the dossier reads the same
  factors, so the odds printed are the odds struck.
- **AI-only battles unchanged:** two rivals share one multiplier and the crown is
  excluded, so an AI-vs-AI ratio and the observer's maths are as before.
- **Crown's victory bar:** `VictoryRules.crown_threshold` scales the published 31
  by the level's percentage; every rival keeps 31 and the observer stays
  published. Setup and the crown's charge print the bar (DR-20261111-28).

## Not in this slice

AI income per turn and tutorial/advisor toggles stay outside the layer
([`deferred.md`](deferred.md)). Difficulty is fixed at creation.

## Tests

`tests/test_difficulty.gd` covers the catalog, the ledger scale, the human
exclusion, the battle context, a naval engagement that turns on the level, and
the victory bar at every level (rival and observer rows included).
`test_game_setup.gd` covers the choice and the bar it states;
`test_campaign_intro.gd` the charge; `test_save_codec.gd` the round trip.
