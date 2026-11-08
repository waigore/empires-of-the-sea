# PR body — hunt defects

Use with `gh pr create`. Title: why-focused (rules fidelity), not a file list.

```markdown
## Summary
- Playtest domain: <wiki page / rule area>
- Defects fixed: <N>
- Requirements: REQ-P2-01, REQ-P2-03, REQ-P2-04 (as applicable)
- Rubric: overall PASS — see decision record

## Defects

### <short name>
- **Wiki:** <page + rule / section>
- **Expected:** <behavior per wiki>
- **Observed:** <what playtest showed>
- **Fix:** <what changed>

(repeat per defect)

## Decision record
Pillars touched: P2 (…others if touched)
RUB scores: P1… P2… P3… P4… (or N/A)
Overall: PASS
Blocking IDs: (none)
Notes: <live vs headless; new-feature regression vs latent if known>

## Test plan
- [ ] `gd-tools test --coverage --min 80 --parallel 4` (≤5 min)
- [ ] `python tools/lint_docs_words.py` (if docs touched)
- [ ] `godot --headless --path . --script res://tools/e2e_smoke.gd` (only if smoke/main-scene path touched; ≤2 min)
- [ ] Re-play: <path that previously failed — live or headless>
```

Score applicable `RUB-*` only. Any applicable 0 → fix before opening as done.
