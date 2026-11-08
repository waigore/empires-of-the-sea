---
name: hunt-defects-agent
description: |-
  Autonomously hunt Empires of the Sea rules defects via playtesting: read
  wiki Game rules, confirm an implementation exists, play (prefer live;
  headless OK) and critically check behavior vs rules, fix every defect found
  in that session, open one PR citing expected vs observed, stop. Hill-climbs
  P2 (RUB-P2-*). Skip missing features (use implement-feature). Ask the user
  only on true blockers. Use when the user asks to hunt defects, playtest
  rules, find rules bugs, P2 hill climb, or run the hunt-defects agent.

  Examples:
    - no target → judge a domain, playtest, fix session defects, PR, stop
    - "playtest boarding" → that implemented domain only; fix cluster; PR
    - "P2 hill climb" → same; prefer high-risk or recently changed rules
---

# Hunt defects agent (facade)

Canonical instructions: [`.agents/skills/hunt-defects-agent/SKILL.md`](../../../.agents/skills/hunt-defects-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
