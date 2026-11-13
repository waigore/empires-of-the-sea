# Playbook — optimize AI

## Default headless run

```bash
OUT=/tmp/eots-ai-vs-ai-$$
godot --headless --path . --script res://tools/ai_vs_ai.gd -- \
  --turns=200 --seed=1500 --size=1 --runs=1 --out="$OUT"
```

Reads: `$OUT/run_00_turns.jsonl`, `$OUT/run_00_summary.json`, console win-rate
table. Docs: [`docs/ai-observer.md`](../../../../docs/ai-observer.md).

Fresh clones need editor `.godot/` / import cache — prefer `tools/run.sh`
patterns when bare `godot --path .` fails on globals.

## What to look for

From snapshots / order mix / wars:

- Passive crowns (peace forever while trailing on provinces)
- Under-used planners (navy, civilians, research, economy, spy, colonisation)
- Self-sabotage (overstretch, empty treasury, ignored victory path)
- One crown dominating only via bug vs others never fighting for 31 provinces
- Order spam that never converts into power / provinces

Cite wiki AI + `docs/ai.md` for intended behavior.

## No-op control (quantitative bar)

Goal: **live AI vs control no-op** — no-op crowns issue no (or inert) planner
orders; live AI should show **substantial** progress (provinces, power, or
victory progress) by conclusion or a documented mid-run checkpoint.

Prefer extending `tools/ai_vs_ai.gd` / observer hooks with a small, performant
flag or sibling script over one-off untracked dumps. If a throwaway probe is
faster for one run, keep it local, capture metrics into the issue/PR, then
**delete** it in cleanup unless it ships inside the competitiveness fix PR.

Match seed/size when comparing full-AI vs control benches.

## Optional live observe

Title → `AI OBSERVER (DEBUG)` when JSONL is ambiguous. Do not require live
play for every run.

## Tool extensions

Allowed: minimal harness flags, richer snapshots, no-op mode — keep runs fast
enough for a 200-turn campaign. Exclude throwaway harnesses from coverage
plans the same way `tools/ai_vs_ai.gd` does (`# gd-tools: no cover`).

## Cleanup

Before stop:

```bash
rm -rf /tmp/eots-ai-vs-ai-*   # or the --out path used
```

Drop untracked scratch scripts/dirs that were not part of a shipped PR. Do
not commit `user://` or local override junk.
