# Playtest playbook

## Implemented vs missing

| Signal | Treat as |
|--------|----------|
| Real rules/UI path + outcomes | Playtest surface |
| Stub / TODO / no call sites | Skip → implement-feature |
| Wiki says X, code has Y wrong | Defect |
| Wiki says X, code has nothing | Not this agent |

## Live vs headless

Prefer **live** (`tools/run.sh`) when outcomes are player-visible or easy to misread from APIs alone. Use **headless** (rules tests, scripted drives, narrow smoke probes) when it still falsifies the wiki claim. Aim of the session is critical comparison — not a particular runner.

Never put long campaign playtests into CI smoke (≤2 min). Prefer `tests/` regressions for each fix.

## Session shape

1. List wiki claims for the domain (inputs → legal options → outcomes).
2. Exercise happy path + edge cases (illegal moves, phase gates, multi-unit, end turn).
3. Log expected vs observed immediately; do not “fix by feel” without a cite.
4. After fixes, re-run the same paths before PR.

## Judgement hints

- Recent PRs that touched `scripts/rules/**` or map play: hunt regressions first.
- Domains with lots of wiki text but thin tests: high latent-bug yield.
- If playtest finds only missing features, stop that domain; do not implement them here.
- **Compare the player's path with the AI adapter** for any newly shipped rule
  (e.g. `EconomyController` vs `MapPlayEconomyAi._extraction`). When an adapter keeps
  its own copy of the rule — per-region extraction, cargo, upkeep — it silently
  bypasses the new limit, so the human pays and the rival does not (`REQ-P2-03`).
- **A documented ordering must be a priority, not a score delta.** When the wiki
  says one work kind "outranks" another, a single weighted score is not enough:
  bonuses on the lower kind invert the ordering (a resource road's need and
  adjacency bonuses beat the town link's base weight, so no rival town ever
  connected). Encode the ordering explicitly and let the score rank only inside
  one kind.
- **Play one turn past the action, not just the action.** Renumbering and merge
  paths (a warp crossing, docking into the home fleet) rotate ids; unit
  back-pointers (`embarked_fleet`) drift and the *end-of-turn* pass then drops the
  unit. A scenario that ends the turn is what surfaces it.
- **The drives share `tests/playtest_launch.gd`** (title → setup → capital chart →
  map). A drive that prints one line and `map screen missing` means the launch flow
  moved: repair the launcher, not the game, and say so in the PR.
- **A documented "X before Y" ordering must consume the blow, not add a second
  hit.** Where the wiki has one target engaged first (a fort battery shot at
  "before the lanes"), code that applies the whole attack to X and then the whole
  attack to Y lets both land; spend what X soaked and let only the remainder on.
- **Splitting one casualty draw into pools must keep the side's single limit.**
  A per-pool deployment limit lets one blow bleed two or three times the deployed
  slice, so reserves the rule protects die anyway; draw the first pool to the
  limit and hand the rest of it to the next pool.
- **Preload test helpers, do not `class_name` them.** `tools/run.sh` only rescans
  `scripts/ scenes/ ui/ autoload/` for the class cache, so a new `class_name` under
  `tests/` is not declared on a manual run.
