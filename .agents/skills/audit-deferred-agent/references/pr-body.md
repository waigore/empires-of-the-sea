# PR body — audit deferred

Use with `gh pr create`. Docs-only; no game code.

```markdown
## Summary
- Audited deferred claims vs code/wiki/Design Records
- Moved live items out of backlog; re-ranked remaining gaps
- Requirements: REQ-P2-02
- Top remaining gap: <rank-1 name or “unchanged”>

## Already live (this pass)
- <item → locus> (or “none newly cleared”)

## Remaining gaps (impact order)
1. <gap> — <why>
2. …

## Out of scope / blocked
- <item> — <DR or reason> (or “none”)

## Test plan
- [ ] `python tools/lint_docs_words.py`
- [ ] Spot-check domain Deferred sections vs `docs/deferred.md`
- [ ] No `scenes/` / `scripts/` / `tests/` game changes in this PR
```
