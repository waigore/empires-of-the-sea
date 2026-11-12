# PR body + rubric self-score

Use with `gh pr create`. Keep the title why-focused.

```markdown
## Summary
- <what shipped and why>
- Wiki / feature: <page or rule name>
- Requirements: <REQ-* …>
- Rubric: overall PASS — see decision record

## Decision record
Pillars touched: P_
RUB scores: P1… P2… P3… P4… P5… (or N/A)
Overall: PASS
Blocking IDs: (none)
Notes: <brief>

## Test plan
- [ ] `python tools/select_impacted_tests.py --check-complete` (if code/tests touched)
- [ ] Impacted `gd-tools test --coverage` via `--print-command` (≤5 min; not ALL/wide)
- [ ] `gd-tools coverage diff --patch --base origin/main --patch-fail-under 80`
- [ ] `python tools/lint_docs_words.py` (if docs touched)
- [ ] `godot --headless --path . --script res://tools/e2e_smoke.gd` (if smoke/main-scene; ≤2 min)
- [ ] Manual: <desktop + touch path if UI>
```

Impact map rules: [impact-map.md](impact-map.md). Score only applicable `RUB-*`. Any applicable 0 → do not open as done; fix first.
