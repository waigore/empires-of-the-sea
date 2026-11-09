---
name: fix-tests-agent
description: |-
  Fix open ci-tier2 full-suite failures: reproduce, repair tests or code,
  open one PR, babysit it to squash auto-merge, then close the sticky
  ci-tier2 issue. Hourly schedule is gated on an open issue with that
  label. Use when automation or a user asks to fix tier-2 tests, clear
  ci-tier2, or run the fix-tests agent.

  Examples:
    - hourly dispatch with open ci-tier2 → fix, PR, babysit, close issue
    - no open ci-tier2 → gate skips; do nothing
    - "fix the tier2 failure" → same as dispatch with the sticky issue
---

# Fix tests agent (facade)

Canonical instructions: [`.agents/skills/fix-tests-agent/SKILL.md`](../../../.agents/skills/fix-tests-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
