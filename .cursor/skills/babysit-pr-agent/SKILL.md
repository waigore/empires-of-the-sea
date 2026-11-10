---
name: babysit-pr-agent
description: |-
  Operate a soft Actions check queue (at most ~3 PRs with queued/in-progress
  runs), then unblock one same-repo PR that is conflicted, behind, or failing
  checks so auto-merge can squash it. Skips fork PRs. One PR fix per run. Use
  when automation or a user asks to babysit PRs for automerge.

  Examples:
    - dispatch with no PR → reshape queue, discover one eligible PR, unblock it
    - dispatch with #12 → reshape queue, unblock #12 when it is same-repo
---

# Babysit PR agent (facade)

Canonical instructions: [`.agents/skills/babysit-pr-agent/SKILL.md`](../../../.agents/skills/babysit-pr-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
