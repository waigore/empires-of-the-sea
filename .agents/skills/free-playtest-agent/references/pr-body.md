# PR body — free playtest

Use with `gh pr create`. Title: why-focused (area expression), not a file list.

```markdown
## Summary
- Free-playtest area: <wiki / feature area>
- Issues fixed: <N>
- Harness: <path or none>
- Diary: https://github.com/waigore/empires-of-the-sea/wiki/playtest-diary
- Learnings: https://github.com/waigore/empires-of-the-sea/wiki/playtest-learnings
- Requirements: <REQ-* as applicable>
- Rubric: overall PASS — see decision record

## Issues

### <short name>
- **Kind:** rules | crash | stuck | ux | balance | novelty | perf
- **Wiki:** <page + section, if rules>
- **Expected:** <behavior / playable expression>
- **Observed:** <playtest / GameForge report>
- **Fix:** <what changed>

(repeat per issue)

## Decision record
Pillars touched: <P2 / P5 / …>
RUB scores: P1… P2… P3… P4… P5… (or N/A)
Overall: PASS
Blocking IDs: (none)
Notes: <GameForge policy/seed or fallback; harness rationale>

## Test plan
- [ ] `gd-tools test --coverage --min 80 --parallel 4` (≤5 min)
- [ ] `python tools/lint_docs_words.py` (if docs touched)
- [ ] `godot --headless --path . --script res://tools/e2e_smoke.gd` (only if smoke/main-scene path touched; ≤2 min)
- [ ] Re-play: <same path/seed that failed>
```

Score applicable `RUB-*` only. Any applicable 0 → fix before opening as done.
