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
RUB scores: P1… P2… P3… P4… (or N/A)
Overall: PASS
Blocking IDs: (none)
Notes: <brief>

## Test plan
- [ ] `gd-tools test --coverage --min 80` (if code/tests touched)
- [ ] `python tools/lint_docs_words.py` (if docs touched)
- [ ] `godot --headless --path . --script res://tools/e2e_smoke.gd` (if smoke or main-scene path touched; aim ≤2 min)
- [ ] Manual: <desktop + touch path if UI>
```

Score only applicable `RUB-*`. Any applicable 0 → do not open as done; fix first.
