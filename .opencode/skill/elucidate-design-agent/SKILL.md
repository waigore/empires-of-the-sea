---
name: elucidate-design-agent
description: |-
  Autonomously analyze Empires of the Sea wiki (Game rules + AI) for unclear,
  contradictory, or underspecified statements; elucidate a P5-first design
  (other pillars accounted for); update wiki + Design Record + Design Changelog;
  implement when code is affected; open one PR; stop. Ask the user only on true
  blockers. Use when the user asks to elucidate design, clarify wiki gaps,
  resolve rules/AI ambiguity, P5 design climb, or run the elucidate-design agent.

  Examples:
    - no target → judge related wiki gaps, record, wiki, implement, PR, stop
    - cited theme → that theme only; batch related gaps; PR
    - cross-page ambiguity → clarify, record, PR
---

# Elucidate design agent (facade)

Canonical instructions: [`.agents/skills/elucidate-design-agent/SKILL.md`](../../../.agents/skills/elucidate-design-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
