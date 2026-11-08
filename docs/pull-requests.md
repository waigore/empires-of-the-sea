# Pull requests

Base rules for opening and landing PRs. Applies to humans and agents.

**Tooling:** use [`gh`](https://cli.github.com/) for all GitHub PR operations (create, view, checks, comment, merge). Do not use the web UI as the primary path when `gh` can do the job.

**Gate docs:** map changes to [`requirements.md`](requirements.md) (`REQ-*`) and score with [`rubric.md`](rubric.md) (`RUB-*`) when the change is player- or rules-facing.

---

## Principles

1. **Small and focused** — one concern per PR; prefer stacked PRs over mixed refactors + features.
2. **Use `gh`** — create, inspect, and merge through the CLI so status and checks stay explicit.
3. **Respect checks** — required status checks are the merge gate. Never bypass, force-merge, or ask to skip them.
4. **Prefer auto-merge** — once the PR is ready and checks can pass, enable squash auto-merge and let GitHub land it when green.

---

## Required checks (main)

The **Protect main** ruleset requires these status checks (strict: branch must be up to date with `main`):

| Check | Workflow | Meaning |
|-------|----------|---------|
| `tests` | [CI](../.github/workflows/ci.yml) | `gd-tools test --coverage --min 80` |

Human review is optional (not a merge gate). Merge method on `main` is **squash only**. Branches are deleted on merge. Auto-merge is enabled on the repo.

### Respecting checks

- Before merge (or enabling auto-merge), confirm with `gh pr checks` / `gh pr view --json statusCheckRollup,mergeStateStatus`.
- **Do not merge** while required checks are failing, pending, or skipped in a way that leaves the gate incomplete.
- **Do not** use `--admin`, merge overrides, or temporary rule disablement to land a red PR.
- If checks fail: fix forward on the PR branch, push, and re-check. Do not close/reopen to “clear” failures.
- Keep the branch current with `main` when strict status policy blocks merge (`gh pr merge` / auto-merge will wait until the branch is updated).

---

## Workflow with `gh`

### Before opening

1. Start from an up-to-date `main`.
2. Use a descriptive branch name (`feat/…`, `fix/…`, `docs/…`).
3. Run tests locally when the change touches game logic or tests:  
   `gd-tools test --coverage --min 80`
4. Confirm `git status` / diff — no `.godot/`, secrets, or local override junk.

### Create

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

- Prefer **draft** (`gh pr create --draft` or `gh pr ready` later) until the change is reviewable and CI-green locally when applicable.
- Title and body should say **why**; cite `REQ-*` / `RUB-*` when relevant.
- Include a short test plan (commands or manual steps).

### While open

```bash
gh pr checks          # required: tests
gh pr view            # status, URL
gh pr comment --body "…"
```

- Push fixes to the same branch; avoid force-push unless rewriting a private draft and collaborators agree.
- Do not land unrelated commits on the PR branch.

### Merge

Prefer enabling squash auto-merge (the [Automerge](../.github/workflows/automerge.yml) workflow also tries this when events fire):

```bash
gh pr merge --squash --auto --delete-branch
```

- Only merge manually with the same squash policy when auto-merge cannot be used and **`tests`** is green.
- Never merge to `main` outside a PR that has satisfied the ruleset checks.

---

## Quick checklist

- [ ] Change maps to at least one pillar (`P1`–`P4`) or is explicitly docs/tooling-only
- [ ] PR opened/updated with `gh`
- [ ] `tests` green (`gd-tools test --coverage --min 80`)
- [ ] Branch up to date with `main`
- [ ] Squash merge (or `--auto`) — no check bypass
