# PR body + rubric self-score

Use with `gh pr create`. Keep the title why-focused (architecture payoff).

```markdown
## Summary
- <theme and why this refactor>
- Hotspot / recent-PR context: <files or PRs that motivated the theme>
- Requirements: <REQ-P3-* …>
- Rubric: overall PASS — see decision record
- Allowlist: <unchanged | shrunk/removed entries>

## Decision record
Pillars touched: P_
RUB scores: P1… P2… P3… P4… (or N/A)
Overall: PASS
Blocking IDs: (none)
Notes: <behavior preserved; key splits/moves>

## Test plan
- [ ] `python tools/lint_arch.py`
- [ ] `gd-tools test --coverage --min 80 --parallel 4` (≤5 min)
- [ ] `python tools/lint_docs_words.py` (if docs touched)
- [ ] `godot --headless --path . --script res://tools/e2e_smoke.gd` (if main-scene composition touched; aim ≤2 min)
- [ ] Manual: <desktop + touch path if UI/scene graph moved>
```

Score only applicable `RUB-*`. Any applicable 0 → do not open as done; fix first.
