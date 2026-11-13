---
name: file-github-issue
description: |-
  File a GitHub issue from a user bug/defect report or feature request:
  classify type, interview for missing details (bugs require platform),
  search open duplicates and confirm with the user if any match, analyze
  (incl. wiki Game rules alignment), ensure labels todo + bug|enhancement,
  submit via gh without a final draft confirm. Confirm with the user before
  noting a wiki follow-up when rules conflict or are silent. Use when the
  user reports a bug, defect, issue, broken behavior, or asks for a feature /
  enhancement, or when they ask to file/log a GitHub issue.

  Examples:
    - "fleet move ignores range on Android" → bug interview → analysis → issue
    - "add a diplomacy ledger" → feature reason + impact → issue
    - "file this as an issue" → classify, then same path
---

# File GitHub issue (facade)

Canonical instructions: [`.agents/skills/file-github-issue/SKILL.md`](../../../.agents/skills/file-github-issue/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
