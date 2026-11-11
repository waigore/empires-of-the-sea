# Difficulty

The rival courts' opening stores and their edge in land battle, chosen when the
chart is opened and fixed for the campaign.

**Pillars:** P2 (rules fidelity), P3 (rules without view nodes), P5 (a stated
choice), P1 (setup chrome).

**Wiki:** [ruleset-config](https://github.com/waigore/empires-of-the-sea/wiki/ruleset-config)
§ Layers, [combat](https://github.com/waigore/empires-of-the-sea/wiki/combat)
§ Modifiers, [ai-architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture).
Decision: DR-20261110-12.

## Levels

| Level | Rival stores | Rival land strength |
|-------|--------------|---------------------|
| Introductory | 60% | 85% |
| Normal | 100% (published row) | 100% |
| Hard | 140% | 115% |
| Impossible | 180% | 130% |

`Normal` is the published game: every court opens on the same starting row and
fights on the published maths. The other three levels are this product's
data-shaped choice, recorded in the design record above; they never change an
AI's decision algorithm (wiki: ai-personalities).

## Implemented

- **Catalog:** `scripts/rules/difficulty.gd` — ordered ids, labels, plain-word
  hints, both percentage tables, `normalize` (unknown ids fall back to Normal),
  and `scaled`/`scale_start` for the opening row.
- **Choice:** the new-game screen offers the four levels under **Difficulty**
  and prints the effect in one line ("Rivals open with 140% of their stores and
  fight at 115% strength"). The summary line names the level.
- **Config + save:** `GameConfig.difficulty` and `PlaySession.difficulty` carry
  the choice; `SaveCodec` stores it with the session and `AiState` with the
  rival ledgers, so a load restores the campaign at the same level
  (wiki: campaign-persistence).
- **Rival opening stores:** a rival's ledger is founded from
  `PlayerEconomy.starting()` and scaled once, on first read
  (`AiState.economy_for`). The human crown never passes through the scale, so
  its start stays the published row.
- **Rival land strength:** `MapPlayLandTurn.battle_context` publishes
  `difficulty: {faction: multiplier}`; `ArmyModifiers.modifiers` folds it into
  the side multiplier after medals, feeding and leader, before terrain and the
  fortified-defender terms. Auto-resolve and Quick Battle read the same
  context, so plates and outcomes agree.
- **AI-only battles stay unchanged:** two rivals share one multiplier and the
  human crown is excluded, so an AI-vs-AI ratio — and the full-AI observer's
  published maths — is what it was before.

## Not in this slice

Naval battles, AI income per turn, victory thresholds and tutorial/advisor
toggles stay outside the layer; the ruleset-config page names them as future
layer keys. Difficulty is fixed at creation: there is no in-game switch.

## Tests

`tests/test_difficulty.gd` covers the catalog, the one-time ledger scale, the
human exclusion, the battle context and a full assault that fails at
Introductory where it carries the province at Normal; `test_game_setup.gd`
covers the choice and its plain-word hint; `test_save_codec.gd` covers the
round trip.
