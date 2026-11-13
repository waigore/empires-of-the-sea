---
name: file-github-issue
description: |-
  File a GitHub issue from a user bug/defect report or feature request:
  classify type, interview for missing details (platform only if stated or
  clearly relevant; else all platforms; map seed when layout/generation
  repro would benefit), search open duplicates and confirm with the user if
  any match, analyze (incl. wiki Game rules alignment), ensure labels todo +
  bug|enhancement, submit via gh without a final draft confirm. Confirm with
  the user before noting a wiki follow-up when rules conflict or are silent.
  Use when the user reports a bug, defect, issue, broken behavior, or asks
  for a feature / enhancement, or when they ask to file/log a GitHub issue.

  Examples:
    - "fleet move ignores range on Android" → bug interview → analysis → issue
    - "add a diplomacy ledger" → feature reason + impact → issue
    - "file this as an issue" → classify, then same path
---

# File GitHub issue

One user report → one GitHub issue (or stop after duplicate confirm). Deliverable: issue URL. Do not fix, open a PR, assign, or edit the wiki in this skill.

Repo: `waigore/empires-of-the-sea` (or current `gh` remote). Use `gh`.

## Sources

| Source | Role |
|--------|------|
| [Wiki Game rules](https://github.com/waigore/empires-of-the-sea/wiki) | Rules SoT — alignment check |
| [`docs/requirements.md`](../../../docs/requirements.md) | Pillars / REQ-* for feature impact |
| [`references/bug-template.md`](references/bug-template.md) | Bug issue body |
| [`references/feature-template.md`](references/feature-template.md) | Feature issue body |

**Not this skill:** implementing a filed `todo` → [`resolve-issue-agent`](../resolve-issue-agent/SKILL.md); verifying `resolved` → [`review-issue-agent`](../review-issue-agent/SKILL.md); hunting defects → hunt-defects; new features from gaps → implement-feature; clarifying wiki design → elucidate-design.

## Labels

| Type | Labels |
|------|--------|
| Bug / defect | `todo`, `bug` |
| Feature request | `todo`, `enhancement` |

Ensure each label exists before filing (`gh label list`). Create missing ones:

```bash
gh label create todo --color 0E8A16 --description "Queued for work" || true
gh label create bug --color d73a4a --description "Something isn't working" || true
gh label create enhancement --color a2eeef --description "New feature or request" || true
```

Do not invent other labels. Leave assignee and milestone unset.

## Workflow

```text
- [ ] 1. Classify (bug vs feature)
- [ ] 2. Interview (fill gaps only)
- [ ] 3. Duplicate search → confirm if matches
- [ ] 4. Analyze (+ wiki alignment)
- [ ] 5. Wiki gate (confirm only if update needed)
- [ ] 6. Ensure labels → submit issue → stop
```

### 1. Classify

- **Bug / defect:** wrong or broken behavior vs expected / wiki.
- **Feature:** new or expanded capability.

If unclear, ask once: bug or feature? Then continue.

### 2. Interview

Ask **only** for missing fields. Do not re-ask what the user already gave.

**Bug (required before submit):**

1. Description / summary
2. Expected result (wiki cite if known)
3. Actual result
4. Steps to reproduce (numbered)

**Platform (bugs — optional):** Record OS/build (`desktop Windows|macOS|Linux` / `Android` / `iOS`), how run, and version/commit **only** when the user stated them or the report is clearly platform-specific. Do **not** ask for platform otherwise. If omitted, assume all platforms; omit `## Platform` from the issue body (do not invent “unknown” or write “all platforms”).

**Map seed (bugs — optional):** Ask for the campaign map seed **only** when repro likely depends on world layout, generation, or seed-driven rolls (map gen, province/coast layout, capitals, fog/geography, “same seed” claims, etc.). Do **not** ask for pure UI/chrome, audio, or seed-independent rules bugs. Point the user to pause menu → Map seed → COPY. If they omit it after the ask, still file and note seed unknown in Analysis notes. Omit `## Map seed` from the body when not provided or not relevant.

**Feature (all required before submit):**

1. Summary of the capability
2. Reason (why it matters)
3. Enough detail for impact analysis (scope, platforms touched if stated)

### 3. Duplicate search

Search **open** issues before filing:

```bash
gh issue list --state open --limit 50 --search "<key symptoms or capability words>"
```

Also skim recent open issues by label (`bug` or `enhancement`) if search is thin.

If a plausible duplicate exists: **stop and confirm with the user** — link candidate(s), ask whether to skip, comment on the existing issue, or file a new one anyway. Do not file until they choose.

If none: continue (no “no duplicates” confirmation needed).

### 4. Analyze

**Bug:** likely locus, wiki alignment (`matches` / `conflicts` / `rules silent`), severity, repro confidence. Fill Analysis on the bug template.

**Feature:** pillars/REQ-* touched, wiki status, scope guess, desktop+mobile, dependencies/risks, alternatives. Fill Impact analysis on the feature template.

Skim code only enough to ground “likely locus” / impact — no deep refactor research.

### 5. Wiki gate

If the report **conflicts** with written Game rules, or needs rules the wiki does **not** cover:

- Ask: whether to note a wiki update on the issue.
- Only if the user says yes: add `## Wiki follow-up` (pages + why).
- If no: omit that section; still file the issue.
- If rules already match: no wiki section, no ask.

Do **not** edit the wiki here.

### 6. Submit

Build title + body from the matching template. Submit **without** a final draft confirm once interview + analysis (+ wiki gate if any) are done.

```bash
gh issue create --title "<title>" --label todo --label <bug|enhancement> --body "$(cat <<'EOF'
<body>
EOF
)"
```

Reply with the issue URL. Stop.

## Rules

- Platform only when stated or clearly relevant; otherwise omit and assume all platforms.
- Map seed only when it would help reproduce (layout / generation / seed-driven rolls); otherwise omit.
- No final “approve this draft?” step after analysis (duplicate + wiki confirms only).
- One issue per report; do not batch unrelated items.
- Prefer `gh`; do not leave issues unlabelled.
