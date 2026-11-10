---
name: refactor-code-agent
description: |-
  Autonomously pick the worst architecture smell in Empires of the Sea,
  aggressively refactor under AGENTS.md / REQ-P3 / RUB-P3 / arch-lint
  (splits, renames, moves, signal/API and scene rewrites), keep one PR
  theme, prove with tests, open a PR, stop. Prefer hot files from recent
  merged PRs. Ask the user only on true blockers. Use when the user asks
  to refactor, clean up architecture, shrink the size allowlist, fix
  arch-lint debt, or run the refactor-code agent.

  Examples:
    - no target → pick worst smell (+ recent-PR hotspots), theme PR, stop
    - cited path or theme → that theme only; aggressive rewrites OK
    - "shrink arch allowlist" → remove/shrink allowlist entries in one PR
---

# Refactor code agent (facade)

Canonical instructions: [`.agents/skills/refactor-code-agent/SKILL.md`](../../../.agents/skills/refactor-code-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
