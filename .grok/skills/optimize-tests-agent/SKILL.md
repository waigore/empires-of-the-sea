---
name: optimize-tests-agent
description: |-
  Autonomously profile and aggressively speed up Empires of the Sea tests
  so the coverage suite stays ≤5 min and e2e smoke ≤2 min (docs/testing.md),
  without weakening the 80% coverage gate or meaningful asserts. Prefer
  shared fixtures, before_all caches, smaller maps, and CI --parallel.
  Open one themed PR; stop. Ask the user only on true blockers. Use when
  the user asks to optimize tests, speed up CI, cut suite time, fix slow
  coverage runs, or run the optimize-tests agent.

  Examples:
    - no target → profile, cut worst suites, enforce budgets, PR, stop
    - "tests are timing out" → profile under coverage, fix hot paths, PR
    - "e2e smoke too slow" → shrink smoke only; keep asserts; PR
---

# Optimize tests agent (facade)

Canonical instructions: [`.agents/skills/optimize-tests-agent/SKILL.md`](../../../.agents/skills/optimize-tests-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
