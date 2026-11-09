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
- **Play one turn past the action, not just the action.** Renumbering and merge
  paths (a warp crossing, docking into the home fleet) rotate ids; unit
  back-pointers (`embarked_fleet`) drift and the *end-of-turn* pass then drops the
  unit. A scenario that ends the turn is what surfaces it.
