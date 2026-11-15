# Agent debug bridge

Opt-in localhost WebSocket for agents and playtest tooling: attach to a
running campaign and query god-mode in-memory state — no screenshots, no save
files. Query-only: no orders, no turn advance, no writes (#699).

## Enable

Off by default; refused on release player exports.

```bash
godot --path . -- --agent-debug=8765   # everything after -- is a user arg
```

- Binds `127.0.0.1` only. Never `0.0.0.0`; no Unix sockets in v1.
- A bare `--agent-debug` takes port 8765. A malformed or out-of-range port
  leaves the bridge off.
- Android debug builds run the same in-app listener; the host reaches it
  through `adb reverse tcp:8765 tcp:8765`, then connects to
  `ws://127.0.0.1:8765`.

## Protocol

Text JSON frames; one answer per request.

| Request | Answer |
|---------|--------|
| `{"id":1,"op":"ping"}` | `{"id":1,"ok":true,"data":{"pong":true}}` |
| `{"id":2,"op":"session"}` | Short card: turn, year, crown, seed, region, calendar state |
| `{"id":3,"op":"dump"}` | Full god-mode bag (see below) |
| `{"id":4,"op":"observer"}` | `MapPlayObserver.snapshot`: ranked scoreboard |
| `{"id":5,"op":"get","path":"economy"}` | One slice of the dump by dotted path |

Errors answer `{"id":N,"ok":false,"error":"..."}` — a first probe never
dangles. Unknown op, unknown path, or a frame that is not a JSON object all
answer an error. Requests may omit `id`; the answer then carries `-1`.
A full `dump` is one large text frame (~100 KB and up for a whole world); the
bridge gives each peer a 1 MB WebSocket buffer both ways.

## The dump

`dump` returns `SaveCodec.capture(play)` — the same rules bag a save carries
(session, regions, visibility, economy, market, diplomacy, ai, gazette,
civilians, fleets, armies, generals) — plus the live-only overlays saves omit,
under the `live` key: `observer_mode`, `ai_mode`, `ai_live_faction`,
`ai_turns`, `ai_trace`, `turn_suspended`, `announced_decisions`,
`market_report`, `court_reports`, `selection`, `hover`, `region` and cheap
`hud` hints (which lens or sheet is up).

`get` slices the same bag: top-level keys (`"economy"`, `"market"`,
`"diplomacy"`) and dotted paths (`"live.ai_mode"`, `"session.turn"`).

## Architecture

- `scripts/debug/agent_debug_bridge.gd` — thin Node on the map screen; owns
  the socket, the flag parse and frame IO. Inert without the flag.
- `scripts/debug/agent_debug_dump.gd` — pure `RefCounted` projector; reads
  `PlaySession`, never writes rules state and never reaches views (REQ-P3-03).

## Security

Loopback-only, opt-in, debug builds. Anything on the host that can open the
port can read full god-mode state — treat the channel as a debug aid, not a
surface for player data. Close the game (or omit the flag) when unattended.

## Tests

`tests/test_agent_debug_bridge.gd` covers the projector's JSON shapes, the
flag parser and a live in-process loopback round trip. Suite is mapped under
the `debug_bridge` domain in `tests/impact_map.toml`.
