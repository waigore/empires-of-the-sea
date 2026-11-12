# Impact map + tier-1 budget

Tier 1 selects suites from [`tests/impact_map.toml`](../../../../tests/impact_map.toml) via `tools/select_impacted_tests.py`. Budgets: unit+coverage **≤5 min**; smoke **≤2 min** ([`docs/testing.md`](../../../../docs/testing.md)).

## Map every new file (required domains only)

For each new in-scope `.gd` (production or test):

| Rule | Detail |
|------|--------|
| Explicit `[[rules]]` | Never rely on a broad catch-all; unmapped paths fail strict selection |
| Narrowest domain | Prefer the smallest existing domain that covers the change |
| New domain OK | Add one when it keeps the selected suite set smaller |
| No extras | Do not list the path on domains that are not needed |
| Avoid `full = true` | Only when unavoidable; treat as a budget fail until remapped |
| New test suites | Add the suite filename only to the domain(s) that should run it |

Update domain `suites = [...]` when adding a test file that belongs on that domain.

## Proof (fail closed)

Before scoring / PR, with code or tests touched:

```bash
python tools/select_impacted_tests.py --check-complete
python tools/select_impacted_tests.py --base origin/main --print-command
gd-tools test --coverage --parallel 4 --timeout 240 $(
  python tools/select_impacted_tests.py --base origin/main \
    | grep -v '^ALL$' | grep -v '^NONE$'
)
gd-tools coverage diff --patch --base origin/main --patch-fail-under 80
```

| Fail | Fix |
|------|-----|
| Unmapped path / `--check-complete` | Add a narrow `[[rules]]` (+ suite list if needed) |
| Selection prints `ALL` / `full` | Remap off `full`; split or tighten domains |
| Selected run **>5 min** wall | Too-wide domain — remap, split domain, or shrink suites; do not open PR |
| Patch coverage under 80% | Add/adjust tests; do not weaken the gate |

Do not ship a feature PR whose impacted set is known-wide.

## Suite structuring

How to keep suites fast (fixtures, `before_all`, lazy attach, one boot per theme, smoke limits): follow **Speed rules** in [`docs/testing.md`](../../../../docs/testing.md). Do not duplicate that guidance here.

Smoke path: [e2e-smoke.md](e2e-smoke.md).
