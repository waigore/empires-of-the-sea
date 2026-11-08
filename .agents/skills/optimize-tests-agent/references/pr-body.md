# PR body (optimize-tests)

Use with `gh pr create`. Title = why (budget / speed), not a file list.

```markdown
## Summary
- <what got faster and how>
- Budgets: unit+coverage ≤5 min; e2e smoke ≤2 min ([docs/testing.md](docs/testing.md))
- Before → after: <wall times>; coverage: <%>

## Test plan
- [ ] `gd-tools test --coverage --min 80 --parallel 4 --timeout 240` (≤5 min)
- [ ] `godot --headless --path . --script res://tools/e2e_smoke.gd` (≤2 min)
- [ ] `python tools/lint_docs_words.py` (if docs touched)
- [ ] `python tools/lint_arch.py` (if scripts/scenes touched)
```
