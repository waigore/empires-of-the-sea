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

# Agent debug bridge

Query-only localhost WebSocket into a running Empires of the Sea session.
Contract pages: [`docs/agent-debug.md`](../../../docs/agent-debug.md) and the
wiki [`Agent-debug-bridge`](https://github.com/waigore/empires-of-the-sea/wiki/Agent-debug-bridge)
page. Never write rules state through it — the channel is read-only by design.

## 1. Enable

The bridge is off by default and refuses to start on release player exports.

```bash
godot --path . -- --agent-debug=8765     # bare --agent-debug = 8765
```

- Desktop: connect straight to `ws://127.0.0.1:8765`.
- Android debug build: `adb forward tcp:8765 tcp:8765` first, then the same
  `ws://127.0.0.1:8765` from the host. (`forward`, not `reverse`: the listener
  lives on the device, so the host→device tunnel is what agents need.)
- A malformed / out-of-range port leaves the bridge off; the game plays
  normally either way.

## 2. Talk the protocol

Text JSON frames; exactly one answer per request. Requests may omit `id`.

| Request | Answer |
|---------|--------|
| `{"id":1,"op":"ping"}` | `ok` + `{"pong":true}` — health check |
| `{"id":2,"op":"session"}` | Card: turn, year, factions, seed, region, difficulty, campaign state |
| `{"id":3,"op":"dump"}` | Full god-mode bag (big; prefer `get` when you need one slice) |
| `{"id":4,"op":"observer"}` | Ranked Great Power scoreboard |
| `{"id":5,"op":"get","path":"economy"}` | One slice; dotted paths (`"live.ai_mode"`, `"session.turn"`) |

Every error answers `{"id":N,"ok":false,"error":"..."}` — unknown op, unknown
path, non-JSON frame. A probe never dangles; retry on the next frame.

## 3. Read the dump

`dump` = `SaveCodec.capture(play)` (the save's rules bag: `session`,
`regions`, `visibility`, `economy`, `market`, `diplomacy`, `ai`, `victory`,
`defeat`, `gazette`, `civilians`, `fleets`, `armies`, `generals`) **plus**
live-only overlays under `live`: `observer_mode`, `ai_mode`,
`ai_live_faction`, `ai_turns`, `ai_trace`, `turn_suspended`,
`announced_decisions`, `market_report`, `court_reports`, `selection`,
`hover`, `region`, `hud` hints.

- A few bag values are Godot `Vector2i`s that stringify as `"(x, y)"` strings;
  parse them as coordinate pairs.
- `ai_turns` is one merged record per resolved turn; `ai_trace` is the raw
  per-court action list (wiki: turn-trace-interpretation).

## 4. Prove it

Quick loopback probe (Python on the host):

```python
from websocket import create_connection
ws = create_connection("ws://127.0.0.1:8765")
ws.send('{"id":1,"op":"ping"}'); print(ws.recv())   # {"id":1,"ok":true,...}
```

If the handshake fails: is the flag after `--`? Is the port the one the game
printed? On Android, did `adb reverse` run after the (re)install?

## Out of scope

Orders, turn advance, any write. `0.0.0.0` bind, Unix sockets, release builds,
multiplayer.
