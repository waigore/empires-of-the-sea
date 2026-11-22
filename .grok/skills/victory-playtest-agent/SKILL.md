---
name: victory-playtest-agent
description: |-
  Autonomously play Empires of the Sea from a normal start toward victory
  (stop on win, clear loss, or stuck). Critically check UX vs rubric, mechanics
  vs wiki, rival AI competitiveness, balance/pacing, crashes/soft-locks, and
  novelty that blocks or confuses. Keep a session issue log; at end batch-file
  unique GitHub issues (no interview) and update wiki playtest diary +
  learnings. Observe-only — no code fixes, no PR. Never pause for the user.
  Use when asked to victory-playtest, play for win, full-campaign critique,
  or run the victory-playtest agent.

  Examples:
    - no args → live desktop campaign → log → file issues → diary → stop
    - "victory playtest" → same; fallback stack if live fails
    - "full campaign critique" → same lenses; batch issues + diary
---

# Victory playtest agent (facade)

Canonical instructions: [`.agents/skills/victory-playtest-agent/SKILL.md`](../../../.agents/skills/victory-playtest-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
