# E2E smoke (implement-feature)

`tools/e2e_smoke.gd` — headless main-scene mini-flow; CI job `e2e-smoke`.

## Rule

When a feature adds a player-visible path the smoke can hit, **add or adjust** asserts in the same PR. Unit tests still own deep rules (`tests/`).

## Keep it fast

- **Hard budget ≤ 2 minutes** wall time (CI `e2e-smoke` timeout). See [`docs/testing.md`](../../../../docs/testing.md).
  `godot --headless --path . --script res://tools/e2e_smoke.gd`
- Prefer a few `await process_frame` steps; no sleeps, no full campaigns, no asset thrash.
- Extend the existing mini-flow; don’t spawn a second suite.
- If coverage needs long setup, put it in unit/integration tests instead (unit suite **≤5 min**).

## Local proof

Run the smoke once after changing it (or the main-scene path). Cite it in the PR test plan.
