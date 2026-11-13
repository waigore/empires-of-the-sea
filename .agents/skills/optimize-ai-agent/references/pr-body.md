# PR body — optimize AI (competitiveness fix)

Use with `gh pr create`. Title: why-focused (win-seeking / competitiveness).

```markdown
## Summary
- Observation: <seed / size / turns; full-AI and/or no-op control>
- Competitiveness failure: <qualitative and/or no-op bar>
- Fix theme: <planner area>
- Requirements: REQ-P2-03 (and others if touched)
- Rubric: overall PASS — see decision record
- Issues filed this run (non-fix gaps): <URLs or none>

## No-op control
- Setup: <how control crowns were inert>
- Metric: <provinces / power / victory progress>
- Before → after: <substantial progress restored?>

## Changes
- <planner / wiring change and why it seeks to win>

## Decision record
Pillars touched: <P2 and others if any>
RUB scores: P1… P2… P3… P4… P5… (or N/A)
Overall: PASS
Blocking IDs: (none)
Notes: <headless vs live; harness extensions kept>

## Test plan
- [ ] `gd-tools test --coverage --min 80 --parallel 4` (≤5 min)
- [ ] `python tools/lint_docs_words.py` (if docs touched)
- [ ] Re-run: `tools/ai_vs_ai.gd` and/or no-op probe that previously failed
- [ ] Scratch / temp out-dirs cleaned
```

Score applicable `RUB-*` only. Any applicable 0 → fix before opening as done.
