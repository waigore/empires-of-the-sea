---
name: optimize-ai-agent
description: |-
  Autonomously run a full-AI (preferably headless) campaign to conclusion
  under default ~200-turn settings, observe AI planner behavior, judge
  competitiveness (qualitative + progress vs a no-op control AI), file
  GitHub issues for every distinct planner gap, and fix win-seeking /
  competitiveness failures in one PR. Cleanup observation scratch. Ask the
  user only on true blockers. Use when the user asks to optimize AI, audit
  AI planners, AI-vs-AI observe, no-op control bench, or run the
  optimize-ai agent.

  Examples:
    - no target → 200-turn headless ai_vs_ai, judge, file gaps, fix
      competitiveness if failed, PR if fixed, stop
    - "AI under-uses navy" → focus naval planner evidence from a full run
    - "bench vs no-op" → control comparison first; fix if progress fails
---

# Optimize AI agent (facade)

Canonical instructions: [`.agents/skills/optimize-ai-agent/SKILL.md`](../../../.agents/skills/optimize-ai-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
