# Wiki update (GitHub wiki)

Mechanics SoT lives in the GitHub wiki, not the game repo.

## Preferred: wiki git via `gh` / git

```bash
OWNER=waigore
REPO=empires-of-the-sea
WIKI_DIR=$(mktemp -d)/wiki
gh repo clone "$OWNER/$REPO.wiki" "$WIKI_DIR" -- --depth 20
# edit markdown in $WIKI_DIR (Home.md, design-*.md, rules/AI pages, dr-*.md)
cd "$WIKI_DIR"
git add -A
git commit -m "$(cat <<'EOF'
Clarify <theme>: DR-YYYYMMDD-NN.

EOF
)"
git push origin HEAD
```

If `gh repo clone OWNER/REPO.wiki` fails, clone the wiki remote directly:

```bash
git clone --depth 20 "https://github.com/$OWNER/$REPO.wiki.git" "$WIKI_DIR"
```

Auth: same credentials as `gh` / `HTTPS` git for the repo. Do not force-push the wiki.

## Fallbacks (in order)

1. **Re-clone + retry push** after `git pull --rebase` if rejected non-fast-forward.
2. **GitHub web UI** (browser / Computer Use): edit or create the same pages if git push is impossible.
3. If wiki write is impossible and the code PR would ship a lie vs wiki: stop as a **blocker** (or open the PR only with an explicit release-blocking wiki follow-up — prefer blocker when the whole point of the run is the clarification).

## Conventions

- Filenames kebab-case; record pages `dr-YYYYMMDD-NN.md`.
- Link with `[Title](page-slug)`.
- Prefer editing **Design intent** on AI pages for product decisions; keep architecture sections for structure/determinism.
- Game rules remain SoT for player mechanics; AI pages must not silently redefine them — cite the clarified rules page from AI text when needed.
- After push, cite full wiki URLs in the code PR body.
