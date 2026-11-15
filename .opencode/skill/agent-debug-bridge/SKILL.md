---
name: agent-debug-bridge
description: |-
  Use the Empires of the Sea opt-in localhost WebSocket debug bridge to inspect
  a running campaign: launch/enable it, connect, `dump` god-mode state,
  `observer` scoreboard, and `get` path slices, on desktop and Android
  (`adb reverse`). Use when an agent or playtest needs live in-session state
  without screenshots or save files, or when asked to debug/query a live
  session, enable the agent debug bridge, or read `ai_turns` / `market_report`
  / court reports from a running game.

  Examples:
    - "inspect the live session" → enable flag, connect ws, dump, read keys
    - "read the AI's turn trace this run" → dump → live.ai_turns / ai_trace
    - "query one slice, not the whole dump" → get with a dotted path
---

# Agent debug bridge (facade)

Canonical instructions: [`.agents/skills/agent-debug-bridge/SKILL.md`](../../../.agents/skills/agent-debug-bridge/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
