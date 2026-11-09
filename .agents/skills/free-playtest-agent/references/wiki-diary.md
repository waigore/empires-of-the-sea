# Wiki playtest diary

Mechanics SoT stays on Game rules pages. This agent owns two wiki pages only:

| Page | Slug | Role |
|------|------|------|
| Playtest Diary | `playtest-diary` | Compact session log (prepend) |
| Playtest Learnings | `playtest-learnings` | Durable summary **≤ 300 words** — read every run |

## Edit via wiki git

```bash
OWNER=waigore
REPO=empires-of-the-sea
WIKI_DIR=$(mktemp -d)/wiki
gh repo clone "$OWNER/$REPO.wiki" "$WIKI_DIR" -- --depth 20
# edit playtest-diary.md and playtest-learnings.md
cd "$WIKI_DIR"
git add playtest-diary.md playtest-learnings.md Home.md
git commit -m "$(cat <<'EOF'
Playtest diary: <area>.

EOF
)"
git push origin HEAD
```

Do not force-push. If push rejects, `git pull --rebase` and retry. Fallback: GitHub web UI.

## Diary entry (prepend; keep tiny)

```markdown
## YYYY-MM-DD — <area>
- **Rules:** [Page](slug), [Page](slug)
- **Method:** forge_playtest policy=<…> duration=<…> seed=<…> | live | headless | harness `<path>`
- **Found:** <1–3 short bullets or "none">
- **Fixed:** PR <url or #N> | diary-only
- **Harness:** `<path>` | none | reused `<path>`
```

No long transcripts. Link Game rules pages; do not paste rules text.

## Learnings page (≤ 300 words)

Rewrite in place each run so the page stays a **summary**, not a log:

- Durable lessons (what breaks, what to watch)
- Harness inventory (area → path)
- Coverage gaps / next hard-to-reach targets
- Drop stale noise; diary holds history

Count words (fenced code excluded). If over 300, cut before push.

## Home

Keep a short “Playtesting” link block on `Home.md` pointing at both pages (create once if missing).
