---
name: implement-feature-agent
description: |-
  Autonomously implement the next Empires of the Sea feature (or a cited
  wiki rule / feature) against docs/requirements.md, the wiki Game rules,
  and docs/rubric.md; prefer the largest shippable change that keeps desktop
  and mobile playable; self-score RUB-*; open a PR citing REQ/RUB/rules; stop.
  Ask the user only on true blockers. Use when the user asks to implement a
  feature, ship the next gap, follow requirements/rubric/rules, or run the
  implement-feature agent.

  Examples:
    - no target → pick largest playable rules/REQ gap, implement, PR, stop
    - "implement boarding" / wiki page cite → that feature only, then PR
    - "ship REQ-P2-04 coverage for X" → scoped to that REQ, then PR
---

# Implement feature agent (facade)

Canonical instructions: [`.agents/skills/implement-feature-agent/SKILL.md`](../../../.agents/skills/implement-feature-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
