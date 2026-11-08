---
name: optimize-tests-agent
description: |-
  Autonomously profile and aggressively speed up Empires of the Sea tests
  so the coverage suite stays ≤5 min and e2e smoke ≤2 min (docs/testing.md),
  without weakening the 80% coverage gate or meaningful asserts. Prefer
  shared fixtures, before_all caches, smaller maps, and CI --parallel.
  Open one themed PR; stop. Ask the user only on true blockers. Use when
  the user asks to optimize tests, speed up CI, cut suite time, fix slow
  coverage runs, or run the optimize-tests agent.

  Examples:
    - no target → profile, cut worst suites, enforce budgets, PR, stop
    - "tests are timing out" → profile under coverage, fix hot paths, PR
    - "e2e smoke too slow" → shrink smoke only; keep asserts; PR
---

# Optimize tests agent

One **PR-sized test-speed theme** per run. Deliverable: an open PR. Do not merge, babysit checks, or force-push.

Budgets are hard ([`docs/testing.md`](../../../docs/testing.md)):

| Suite | Budget |
|-------|--------|
| `gd-tools test --coverage --min 80 --parallel 4` | **≤ 5 min** |
| `godot --headless --path . --script res://tools/e2e_smoke.gd` | **≤ 2 min** |

Do **not** drop coverage below 80%, delete meaningful cases, or raise CI timeouts to “fix” slowness.

## Sources of truth

| Source | Role |
|--------|------|
| [`docs/testing.md`](../../../docs/testing.md) | Budgets + speed rules |
| [`docs/pull-requests.md`](../../../docs/pull-requests.md) | Required checks |
| [`gd-tools.toml`](../../../gd-tools.toml) | Per-test timeout |
| [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml) | Job timeouts / parallel |
| [`tests/map_fixture.gd`](../../../tests/map_fixture.gd) | Shared small world for MapScreen |
| [`references/playbook.md`](references/playbook.md) | gd-tools pitfalls + tactics |

## Workflow

```text
- [ ] 1. Orient + profile
- [ ] 2. Select theme
- [ ] 3. Optimize (aggressive)
- [ ] 4. Prove budgets
- [ ] 5. Document if budgets/rules moved
- [ ] 6. Open PR and stop
```

### 1. Orient + profile

Sync to current `main`. Measure before changing:

```bash
gd-tools test --coverage --min 80 --durations 20 --timeout 240
gd-tools test --coverage --min 80 --parallel 4 --durations 15 --timeout 240
/usr/bin/time -p godot --headless --path . --script res://tools/e2e_smoke.gd
```

Note wall time vs summed duration. Coverage multiplies world-gen cost — always profile **with** `--coverage`. Skim recent CI `tests` / `e2e-smoke` step timings via `gh` when useful.

### 2. Select theme

Pick **one** coherent theme that maximizes wall-time win. Priority when tied:

1. MapScreen / world generation repeated per test under coverage
2. Broken or missing shared caches (`before_all`, fixtures)
3. Oversized generator sizes in tests vs playable defaults
4. Missing CI `--parallel` or timeouts that hide regressions
5. E2E smoke: large maps, sleeps, redundant boot frames

If the user cites a suite or symptom, that wins. Otherwise announce theme + top slow tests briefly, then continue.

### 3. Optimize (aggressive)

Branch `chore/…` or `test/…` from up-to-date `main`.

**In bounds:** extend `map_fixture` / pure fixtures; `before_all` + non-underscore shared vars; `MapScreen.preset_world`; shrink test/smoke map sizes; `free()` screens in `after_each`; CI `--parallel` + budget timeouts; trim smoke frames; update `docs/testing.md` / CI comments.

**Out of bounds:** deleting coverage-critical tests; lowering `--min 80`; raising job timeouts instead of fixing slowness; gameplay feature work; unrelated refactors.

Apply the playbook ([`references/playbook.md`](references/playbook.md)). Prefer reuse of `tests/map_fixture.gd`, `civilian_fixture.gd`, `naval_fixture.gd`.

### 4. Prove budgets

```bash
python tools/lint_docs_words.py
python tools/lint_arch.py
gd-tools test --coverage --min 80 --parallel 4 --timeout 240 --durations 15
/usr/bin/time -p godot --headless --path . --script res://tools/e2e_smoke.gd
```

Coverage must stay ≥ 80%. Wall times must clear the budgets with headroom for CI setup. Fix failures before opening the PR.

### 5. Document

If budgets, commands, or speed rules changed, keep [`docs/testing.md`](../../../docs/testing.md) current (and README / AGENTS / pull-requests pointers if commands changed). Docs ≤ 500 words.

### 6. Open PR and stop

Commit with a why-focused message (time saved / budget enforced). Push and create the PR with `gh` (template: [`references/pr-body.md`](references/pr-body.md)). Include before/after timings in the body.

**Stop** after the PR URL exists. Do not auto-merge or babysit unless asked.

## Autonomy / blockers

Do not ask for mid-run approval of fixture shape or which slow suite to hit first.

**Ask only on true blockers**, then stop: cannot run Godot/gd-tools; credentials/`gh` broken; coverage cannot stay ≥ 80% without the slow path and no alternative fixture exists; change would need secrets, force-push, or check bypass.

## Report

Lead with the PR URL. State theme, before/after timings, coverage %, whether budgets hold.
