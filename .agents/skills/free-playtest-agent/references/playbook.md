# Free-playtest playbook

## Area choice (hard-to-reach first)

| Prefer | Avoid |
|--------|--------|
| Late-phase / rare branch / multi-step gates | Only the title-screen happy path |
| Domains with thin harnesses in learnings | Wholly unimplemented wiki pages |
| Recent churn + player-visible expression risk | Unrelated drive-by refactors |
| Areas learnings mark as flaky or untested | Re-testing a just-covered green path with no new angle |

Announce area + why, then continue.

## Reachability

1. Check learnings for an existing harness; reuse/extend before inventing.
2. If mid/late game is required and play-forward is slow/noisy → add a **small reusable** scenario (config, debug start, fixture, scripted setup under `tests/` or existing session helpers).
3. Harness should make the **next** free-playtest of this area cheap; avoid one-off throwaways when a tiny durable hook works.
4. Never dump long campaigns into CI smoke (≤2 min). Prefer unit/integration regressions for fixes; harness may be opt-in/debug.

## GameForge (Hermes)

Load the GameForge **playtesting** skill, then:

| Goal | Hint |
|------|------|
| Smoke + design notes | `explorer`, shorter duration |
| Crash / stuck hunt | `monkey` |
| Goal-directed | `agent` + explicit goal string |
| Confirm fix | **same seed** as the failing run |

Read `report.md`; inspect `moments.jpg` when present. Map signals: runtime error, stuck, input no-effect, slow frames, nothing-happens, low novelty, too hard/easy → fix if they hurt **this area’s** expression.

If `forge_playtest` cannot drive this project usefully, fall back to `tools/run.sh` / headless drives; note the fallback in the diary.

## Issue triage

| Finding | Action |
|---------|--------|
| Wiki X, code Y wrong | Fix (rules defect) |
| Crash / stuck / dead input in area | Fix |
| UX that hides or blocks the area | Fix when in theme |
| Balance/novelty/perf from report | Fix when it clearly harms expression; tune narrowly |
| Feature missing entirely | Skip → implement-feature |
| Wiki ambiguous | Note → elucidate-design; do not invent rules |

## Session discipline

- One area theme per run; cluster related fixes.
- Log expected vs observed with wiki cites for rules issues.
- Re-run the same path/seed after fixes before PR.
