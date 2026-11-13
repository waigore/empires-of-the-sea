---
name: review-issue-agent
description: |-
  Autonomously take an open GitHub issue labelled resolved, verify wiki
  Evidence plus merged implementation against the issue expected outcome,
  then either close with a brief note or send it back to todo with a concise
  comment (≤150 plain-English words either way). Skip and wait if fix PRs
  are not merged. One issue per run. Ask the user only on true blockers.
  Safe for hourly dispatch with no user message. Use when the user or
  automation asks to review a resolved issue, verify issue evidence, or run
  the review-issue agent.

  Examples:
    - no target → pick an open resolved by judgement; review; stop
    - "#42" or "review #42" → that issue only
    - hourly dispatch → same as no target; exit cleanly if queue empty
---

# Review issue agent (facade)

Canonical instructions: [`.agents/skills/review-issue-agent/SKILL.md`](../../../.agents/skills/review-issue-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
