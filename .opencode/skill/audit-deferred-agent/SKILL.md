---
name: audit-deferred-agent
description: |-
  Autonomously audit Empires of the Sea deferred features against code and
  wiki: collect deferred / out-of-scope / playable-slice notes from docs,
  wiki, Design Records and the Design Changelog; mark what is already live;
  re-rank remaining gaps by impact; update docs/deferred.md and domain
  Deferred sections; open one docs-only PR; stop. Analysis only — do not
  implement features. Ask the user only on true blockers. Use when the user
  asks to audit deferred, rank deferred features, update the deferred
  backlog, or run the audit-deferred agent.

  Examples:
    - no target → full audit, update docs, PR, stop
    - cited domain → that domain's deferred list only; still refresh deferred.md
    - "what's left to implement" → same full audit path
---

# Audit deferred agent (facade)

Canonical instructions: [`.agents/skills/audit-deferred-agent/SKILL.md`](../../../.agents/skills/audit-deferred-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
