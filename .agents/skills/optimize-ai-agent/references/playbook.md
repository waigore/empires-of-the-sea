# Playbook — optimize AI

## Default headless run

```bash
OUT=/tmp/eots-ai-vs-ai-$$
godot --headless --path . --script res://tools/ai_vs_ai.gd -- \
  --turns=200 --seed=1500 --size=1 --runs=1 --ai=full --out="$OUT"
```

Reads: `$OUT/run_00_turns.jsonl`, `$OUT/run_00_summary.json`, console win-rate
table. Docs: [`docs/ai-observer.md`](../../../../docs/ai-observer.md).

Fresh clones need editor `.godot/` / import cache — prefer `tools/run.sh`
patterns when bare `godot --path .` fails on globals.

## Planner modes (`AiControl`)

| Flag | Use |
|------|-----|
| `--ai=full` | All crowns plan (default observation) |
| `--ai=noop` | All crowns inert (sanity / baseline) |
| `--ai=bench` | Live crown plans; others no-op (`--live=ID` optional) |

```bash
# Quantitative win-seeking bar: one live AI vs no-op rivals
godot --headless --path . --script res://tools/ai_vs_ai.gd -- \
  --turns=200 --seed=1500 --ai=bench --out="$OUT"
```

Snapshots expose `ai_mode`, `ai_live`, and per-crown `plans`. Prefer these
flags over inventing a throwaway probe.

## What to look for

From snapshots / order mix / wars:

- Passive crowns (peace forever while trailing on provinces)
- Under-used planners (navy, civilians, research, economy, spy, colonisation)
- Self-sabotage (overstretch, empty treasury, ignored victory path)
- One crown dominating only via bug vs others never fighting for 31 provinces
- Order spam that never converts into power / provinces
- Under `bench`: live crown fails to pull ahead of inert controls

Cite wiki AI + `docs/ai.md` for intended behavior.

## No-op control (quantitative bar)

Required when judging competitiveness or closing a competitiveness fix: run
`--ai=bench` (same seed/size as a `full` run when comparing). Live AI must show
**substantial** progress (provinces, power, or victory progress) vs idle
rivals by conclusion or a documented checkpoint. `--ai=noop` is optional
sanity that nobody moves.

## Optional live observe

Title → `AI OBSERVER (DEBUG)` when JSONL is ambiguous. Do not require live
play for every run. Live dashboard stays `full` unless the session’s
`play.ai_mode` is set the same way as the headless tool.

## Tool extensions

Prefer existing `--ai=` / `--live=` / snapshot fields. Further harness work
only if those are insufficient — keep runs fast for a 200-turn campaign;
exclude throwaways from coverage (`# gd-tools: no cover`).

## Cleanup

Before stop:

```bash
rm -rf /tmp/eots-ai-vs-ai-*   # or the --out path used
```

Drop untracked scratch scripts/dirs that were not part of a shipped PR. Do
not commit `user://` or local override junk.
