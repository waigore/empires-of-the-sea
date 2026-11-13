# Evidence wiki hierarchy

Screenshots and logs for issue resolution live in the **GitHub wiki**, not the game repo.

## Hierarchy

| Page | Wiki slug / file | Role |
|------|------------------|------|
| Home | [`Evidence`](https://github.com/waigore/empires-of-the-sea/wiki/Evidence) · `Evidence.md` | Index of all issue evidence |
| Per issue | `evidence/issue-N` · `evidence/issue-N.md` | Proof for GitHub issue `#N` |

Always link new pages from the home index. Create `Evidence.md` if missing.

## Clone / push

Full clone preferred (not shallow-only if replacing images). Same pattern as other wiki skills:

```bash
OWNER=waigore
REPO=empires-of-the-sea
WIKI_DIR=$(mktemp -d)/wiki
gh repo clone "$OWNER/$REPO.wiki" "$WIKI_DIR" -- --depth 20
# mkdir -p evidence; edit Evidence.md and evidence/issue-N.md; add images under evidence/
cd "$WIKI_DIR"
git add -A
git commit -m "$(cat <<'EOF'
Evidence for issue #N.

EOF
)"
git push origin HEAD
```

Do not force-push the wiki. On non-fast-forward: `git pull --rebase` and retry.

## Home page skeleton (`Evidence.md`)

```markdown
# Evidence

Proof of issue resolution (screenshots, logs). Each issue has a child page.

| Issue | Status | Page |
|-------|--------|------|
| #N | in progress \| ready for review | [evidence/issue-N](evidence/issue-N) |
```

Keep the table updated when adding or finishing a page.

## Per-issue page (`evidence/issue-N.md`)

```markdown
# Evidence — issue #N

- Issue: https://github.com/waigore/empires-of-the-sea/issues/N
- PRs: <merged PR URLs>
- Platform(s) exercised: <…>

## Expected
<from issue>

## Proof
### Screenshots
![desc](images/…)

### Logs
\`\`\`text
…
\`\`\`

## Notes
<how this shows acceptance / wiki tasks done>
```

Store binaries under `evidence/` (e.g. `evidence/images/issue-N-….png`) and commit them with the page. Prefer relative image links.

## Rules

- Do not put long logs or screenshots only in GitHub issue comments — wiki is the home; the issue comment **links** here.
- One issue → one `evidence/issue-N` page (update in place across runs).
- Mark the home-table status `ready for review` only when proof matches the issue acceptance (and any wiki follow-ups listed on the issue).
