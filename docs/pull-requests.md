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
| `tests` | [CI](../.github/workflows/ci.yml) | Coverage gate when code/tests change; else no-op success |
| `build` | [CI](../.github/workflows/ci.yml) | Headless import/compile; else no-op |
| `e2e-smoke` | [CI](../.github/workflows/ci.yml) | Needs `build`; main-scene mini-flow (`tools/e2e_smoke.gd`); else no-op |
| `docs-lint` | [CI](../.github/workflows/ci.yml) | Docs ≤ 500 words (`tools/lint_docs_words.py`) — always runs |
| `approval-gate` | [Approval gate](../.github/workflows/approval-gate.yml) | Path-based review hook (**no-op** for now) |

`tests` / `build` / `e2e-smoke` run on game-code paths (`scenes/`, `scripts/`, `ui/`, `autoload/`, `tests/`, `addons/`, `project.godot`, `icon.svg`; not `assets/`/CI); `build`/`e2e-smoke` also on `tools/e2e_smoke.gd`. Else no-op green. `workflow_dispatch` runs them. `docs-lint` always.

Smoke (`tools/e2e_smoke.gd`): main mini-flow; **aim ≤2 min**. Extend on player-path features; deep rules in `tests/`. Job timeout 3 min (setup headroom).

Add `docs-lint`, `build`, `e2e-smoke` to Protect main (admin).

Merge method: **squash only**. Branches deleted on merge. Auto-merge enabled.

### Respecting checks

- Confirm with `gh pr checks` / `gh pr view --json statusCheckRollup,mergeStateStatus`.
- Do not merge while required checks fail, pend, or skip incompletely.
- Do not use `--admin`, overrides, or rule disablement for a red PR.
- Fix forward on the PR branch; don’t close/reopen to clear failures.
- Keep the branch current with `main` under strict status policy.

### Approval gate (no-op)

`ENFORCE_APPROVAL=false` → always pass; human review optional. When `true`, non-draft PRs touching game code/tests/assets need one approving review from any write collaborator other than the author (`scenes/`, `scripts/`, `ui/`, `assets/`, `autoload/`, `tests/`, `addons/`, `project.godot`, `icon.svg`). Docs/CI-only paths stay exempt.

```bash
gh pr review <number> --approve
```

## Workflow with `gh`

**Before:** up-to-date `main`; branch `feat/…` / `fix/…` / `docs/…`; run `gd-tools test --coverage --min 80` and `python tools/lint_docs_words.py` when relevant; clean `git status`.

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

- [ ] Maps to a pillar (`P1`–`P4`) or is docs/tooling-only
- [ ] Opened/updated with `gh`
- [ ] `tests` green
- [ ] `build` green
- [ ] `e2e-smoke` green
- [ ] `docs-lint` green
- [ ] `approval-gate` green
- [ ] Branch up to date with `main`
- [ ] Squash merge (or `--auto`) — no check bypass
