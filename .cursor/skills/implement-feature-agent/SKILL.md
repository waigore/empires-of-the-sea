---
name: implement-feature-agent
description: |-
  Autonomously implement the next Empires of the Sea feature (or a cited
  wiki rule / feature) against docs/deferred.md, docs/requirements.md, the
  wiki Game rules, and docs/rubric.md; with no target, prefer deferred then
  REQ/wiki gap; largest shippable desktop+mobile change; self-score RUB-*;
  open a PR citing REQ/RUB/rules; stop. Ask the user only on true blockers.
  Use when the user asks to implement a feature, ship the next gap, follow
  requirements/rubric/rules, or run the implement-feature agent.

  Examples:
    - no target → largest clear deferred.md item, else REQ/wiki gap; PR; stop
    - cited wiki page or feature → that feature only, then PR
    - cited REQ-* → scoped to that REQ, then PR
---

# Implement feature agent (facade)

Canonical instructions: [`.agents/skills/implement-feature-agent/SKILL.md`](../../../.agents/skills/implement-feature-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
