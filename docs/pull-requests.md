# Pull requests

Base rules for opening and landing PRs (humans and agents).

**Tooling:** use [`gh`](https://cli.github.com/) for all GitHub PR operations.  
**Gate docs:** map player/rules changes to [`requirements.md`](requirements.md) (`REQ-*`) and [`rubric.md`](rubric.md) (`RUB-*`).

## Principles

1. **Small and focused** — one concern; stack PRs over mixed refactors + features.
2. **Use `gh`** — create, inspect, merge via CLI.
3. **Respect checks** — required status checks are the merge gate; never bypass or force-merge.
4. **Prefer auto-merge** — enable squash auto-merge when ready; let GitHub land when green.

## Required checks (main)

**Protect main** requires these (strict: branch up to date with `main`):

| Check | Workflow | Meaning |
|-------|----------|---------|
| `tests` | [CI](../.github/workflows/ci.yml) | **Tier 1:** impacted suites + **80% patch** on PRs; no-op if no code paths; `main` push skips |
| `build` | [CI](../.github/workflows/ci.yml) | Headless import/compile; else no-op |
| `e2e-smoke` | [CI](../.github/workflows/ci.yml) | Needs `build`; mini-flow (`tools/e2e_smoke.gd`); else no-op |
| `docs-lint` | [CI](../.github/workflows/ci.yml) | Docs ≤ 500 words — always |
| `arch-lint` | [CI](../.github/workflows/ci.yml) | P3 bars (`tools/lint_arch.py`) — always |
| `skills-isolation` | [CI](../.github/workflows/ci.yml) | PR-only: fail if code **and** skills both change |
| `ai-bench-report` | [CI](../.github/workflows/ci.yml) | PR AI paths: hills report ≥ baseline |

Code paths (`tests`/`build`/`e2e-smoke`/`skills-isolation`): `scenes/`, `scripts/`, `ui/`, `autoload/`, `tests/`, `addons/`, `project.godot`, `icon.svg` (+ `tools/e2e_smoke.gd` for build/smoke). Skills: `.agents/skills/`, `.cursor/skills/`, `.opencode/skill/`, `.grok/skills/`. Docs-only and skills-only OK. `workflow_dispatch` runs tests/build/smoke. `docs-lint` / `arch-lint` always.

**Tier 2** ([ci-tier2](../.github/workflows/tier2.yml)): every **8h** on `main` — 4 suite shards + merged overall 80%. Not a PR check. Sticky `ci-tier2` → fix-tests agent.

Budgets ([testing.md](testing.md)): PR `tests` **≤5 min**; smoke **≤2 min**. Merge: **squash only**; delete branches; auto-merge on.

### Respecting checks

- Confirm with `gh pr checks` / `gh pr view --json statusCheckRollup,mergeStateStatus`.
- Do not merge while required checks fail, pend, or skip incompletely.
- Do not use `--admin`, overrides, or rule disablement for a red PR.
- Fix forward on the PR branch; don’t close/reopen to clear failures.
- Keep the branch current with `main` under strict status policy.

## Workflow with `gh`

**Before:** up-to-date `main`; branch `feat/…` / `fix/…` / `docs/…`; run tests + docs/arch lints when relevant; clean `git status`.

**Create:**

```bash
git push -u origin HEAD
gh pr create --title "…" --body "$(cat <<'EOF'
## Summary
- …

## Test plan
- [ ] …

EOF
)"
```

Prefer draft until reviewable. Title/body say **why**; cite `REQ-*` / `RUB-*` when relevant.

**While open:** `gh pr checks` · `gh pr view` · `gh pr comment`. Push fixes; avoid force-push unless rewriting a private draft.

**Merge:** prefer squash auto-merge ([Automerge](../.github/workflows/automerge.yml)):

```bash
gh pr merge --squash --auto --delete-branch
```

Never merge to `main` outside a PR that satisfied the ruleset checks.

## Quick checklist

- [ ] Maps to a pillar (`P1`–`P5`) or is docs/tooling-only
- [ ] Opened/updated with `gh`
- [ ] Checks green (`skills-isolation`, `ai-bench-report` if AI)
- [ ] Branch current with `main`; squash / `--auto` — no bypass
