# PR body — elucidate design

Use with `gh pr create` when code shipped. Title: why-focused (P5 / clarity), not a file list.

```markdown
## Summary
- Theme: <related ambiguity cluster>
- Design records: DR-YYYYMMDD-NN …
- Wiki: <pages clarified + record/changelog URLs>
- Requirements: REQ-P5-* (and REQ-P2-* / others as applicable)
- Rubric: overall PASS — see decision record

## Design decisions

### DR-YYYYMMDD-NN — <short title>
- **Ambiguity:** <one line>
- **Change:** <one line>
- **Reasoning (P5-first):** <one line>
- **Impact:** wiki + code
- **Record:** https://github.com/waigore/empires-of-the-sea/wiki/dr-YYYYMMDD-NN

(repeat per DR)

## Decision record
Pillars touched: P5, P2 (…others if touched)
RUB scores: P1… P2… P3… P4… P5… (or N/A)
Overall: PASS
Blocking IDs: (none)
Notes: <P5-wins call if pillars conflicted>

## Test plan
- [ ] `gd-tools test --coverage --min 80 --parallel 4` (≤5 min)
- [ ] `python tools/lint_docs_words.py` (if docs touched)
- [ ] `godot --headless --path . --script res://tools/e2e_smoke.gd` (only if smoke/main-scene path touched; ≤2 min)
- [ ] Manual: <desktop + touch path if UI agency changed>
```

Score applicable `RUB-*` only. Any applicable 0 → fix before opening as done.

Wiki-only runs (no code): do not open an empty PR; report record + changelog URLs instead.
