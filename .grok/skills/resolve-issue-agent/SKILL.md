---
name: resolve-issue-agent
description: |-
  Autonomously take an open GitHub issue labelled todo, implement every task
  on it (code and any wiki follow-ups), open fix PR(s), put screenshots/logs
  under the wiki Evidence hierarchy, wait until fix PR(s) are merged, then
  comment with proof + PR links, add resolved, and remove todo. One issue per
  run. Ask the user only on true blockers. Safe for continuous/hourly dispatch
  with no user message. Use when the user or automation asks to resolve a
  todo issue, work an open todo, or run the resolve-issue agent.

  Examples:
    - no target → pick an open todo by judgement; resolve or advance it; stop
    - "#42" or "resolve #42" → that issue only
    - continuous dispatch → same as no target; exit cleanly if queue empty
---

# Resolve issue agent (facade)

Canonical instructions: [`.agents/skills/resolve-issue-agent/SKILL.md`](../../../.agents/skills/resolve-issue-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
