# Victory playtest playbook

## Play stack (prefer live)

1. Live desktop: `tools/run.sh` (imports first). Note map seed when available.
2. Optional: [`agent-debug-bridge`](../../agent-debug-bridge/SKILL.md) for dumps / AI traces while live.
3. Fallbacks if live fails: headless campaign / scripted play, then Hermes `forge_playtest` if present.
4. Record in the log: method, commit, seed, platform.

Do **not** start mid/late via harness for a normal run. If a new game cannot start, log that as a blocker issue and end the session.

## Session issue log (append while playing)

One bullet or short block per finding:

```text
- lens: ux|rules|ai|balance|crash|novelty
  expected: <wiki slug or RUB-*>
  observed: <what happened>
  severity: blocker|major|minor
  repro: <steps / turn / seed if known>
  locus: <guess or unknown>
```

At end: merge duplicates in the log before filing.

## Batch filing (autonomous)

Reuse labels and body shapes from [`file-github-issue`](../../file-github-issue/SKILL.md) templates. **Deltas for this agent:**

| file-github-issue step | This agent |
|------------------------|------------|
| Interview | Skip — fill from session log |
| Duplicate confirm | Search open issues; **skip** clear dupes (note existing URL); file only if distinct |
| Wiki gate ask | If rules conflict/silent, add `## Wiki follow-up` without asking |
| Draft confirm | Never |
| One report → one issue | One **log finding** → one issue (after merge) |

```bash
gh issue list --state open --limit 50 --search "<key symptoms>"
gh label create todo --color 0E8A16 --description "Queued for work" || true
gh label create bug --color d73a4a --description "Something isn't working" || true
gh label create enhancement --color a2eeef --description "New feature or request" || true
gh issue create --title "<title>" --label todo --label <bug|enhancement> --body "$(cat <<'EOF'
<body from template>
EOF
)"
```

Classify: wrong vs wiki/rubric/AI intent → `bug`; missing capability that hollows the victory path → `enhancement`. Platform/seed sections only when known from the session.

## Diary adaptation

Same format as free-playtest wiki-diary, with:

```markdown
## YYYY-MM-DD — victory run
- **Rules:** [victory](…), [AI](…)
- **Method:** live | headless | forge_playtest … seed=<…>
- **Outcome:** win | loss | stuck — <one short clause>
- **Found:** <count> logged; filed <urls or none new>; skipped dupes <urls>
- **Fixed:** observe-only
- **Harness:** none
```
