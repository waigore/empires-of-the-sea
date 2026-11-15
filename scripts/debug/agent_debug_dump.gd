class_name AgentDebugDump
extends RefCounted
## Pure projector for the Agent Debug Bridge (issue #699): god-mode in-memory
## state as plain, JSON-ready data (REQ-P3-03). Node-free: it reads PlaySession
## only, never writes rules state and never reaches views — the bridge Node owns
## the socket, this module owns the answer.
##
## The `dump` op is `SaveCodec.capture` (the god-mode rules bag a save carries)
## plus the live-only overlays saves omit, keyed under `live`.

const OP_PING: String = "ping"
const OP_SESSION: String = "session"
const OP_DUMP: String = "dump"
const OP_OBSERVER: String = "observer"
const OP_GET: String = "get"
## Key the live-only overlays ride under on a full dump.
const LIVE_KEY: String = "live"


## One protocol answer: `{"id": N, "ok": true, "data": ...}` or
## `{"id": N, "ok": false, "error": "..."}`. Requests are `{"id": N, "op": ...}`
## (with `path` for `get`). Query-only by construction: nothing here mutates.
static func frame(request: Variant, play: PlaySession) -> Dictionary:
	if typeof(request) != TYPE_DICTIONARY:
		return _error(-1, "frames must be JSON objects")
	var id: int = int(request["id"]) if request.has("id") else -1
	var op: String = String(request.get("op", ""))
	if op == OP_PING:
		return _ok(id, {"pong": true})
	if op == OP_SESSION:
		return _play_op(id, play, session_info(play))
	if op == OP_DUMP:
		return _play_op(id, play, capture(play))
	if op == OP_OBSERVER:
		return _play_op(id, play, MapPlayObserver.snapshot(play))
	if op == OP_GET:
		return _get_frame(request, play, id)
	return _error(id, "unknown op '%s'" % op)


## The full god-mode bag: the save codec's capture plus the live overlays.
## Overlays are read straight off the session (no copies): the bridge
## serializes each answer the moment it is built.
static func capture(play: PlaySession) -> Dictionary:
	var dump := SaveCodec.capture(play)
	if play != null:
		dump[LIVE_KEY] = _live(play)
	return dump


## Short card for the `session` op: who is playing, where the calendar stands.
static func session_info(play: PlaySession) -> Dictionary:
	return {
		"turn": play.turn,
		"year": TurnTime.year_for_turn(play.turn),
		"player_faction": play.player_faction,
		"human_faction": play.human_faction_id(),
		"observer_mode": play.observer_mode,
		"ai_mode": play.ai_mode,
		"ai_live_faction": play.ai_live_faction,
		"seed": play.map_seed,
		"map_size": [play.map_width, play.map_height],
		"region": play.region_index,
		"infinite_mode": play.infinite_mode,
		"difficulty": play.difficulty,
		"advanced_start": play.advanced_start,
		"campaign_over": play.campaign_over(),
		"turn_suspended": play.turn_suspended,
	}


## Resolves a dotted path against a dump: `"economy"`, `"live.ai_mode"`,
## `"session.turn"`. Returns `{found: bool, value: Variant}` — a missing hop is
## not an error at this layer, the `get` frame reports it.
static func resolve(dump: Dictionary, path: String) -> Dictionary:
	var cursor: Variant = dump
	for part: String in path.split(".", false):
		if typeof(cursor) != TYPE_DICTIONARY or not cursor.has(part):
			return {"found": false, "value": null}
		cursor = cursor[part]
	return {"found": true, "value": cursor}


# --- internals ----------------------------------------------------------------


## The ops that need a live session share one guard: without one, the rules bag
## is empty and only `ping` still answers.
static func _play_op(id: int, play: PlaySession, data: Variant) -> Dictionary:
	if play == null:
		return _error(id, "no live session")
	return _ok(id, data)


## Live-only overlays a save omits (issue #699): session flags, the AI's
## turn records, the court's despatch state and where the crown is looking.
static func _live(play: PlaySession) -> Dictionary:
	return {
		"observer_mode": play.observer_mode,
		"ai_mode": play.ai_mode,
		"ai_live_faction": play.ai_live_faction,
		"ai_turns": play.ai_turns,
		"ai_trace": play.ai_trace,
		"turn_suspended": play.turn_suspended,
		"announced_decisions": play.announced_decisions,
		"market_report": play.market_report,
		"court_reports": play.court_reports,
		"selection": play.selected_province,
		"hover": play.hover_province,
		"region": play.region_index,
		"hud": _hud_hints(play),
	}


## Cheap, read-only HUD hints: what chrome is up. No repaint, no geometry.
static func _hud_hints(play: PlaySession) -> Dictionary:
	return {
		"resource_lens": play.lens != null and play.lens.active,
		"diplomacy_lens": play.diplomacy_lens != null and play.diplomacy_lens.active,
		"crown_lens": play.crown_lens != null and play.crown_lens.active,
		"defence_lens": play.defence_lens != null and play.defence_lens.active,
		"quick_battle_shown": play.hud != null and play.hud.is_quick_battle_shown(),
		"improvements_open": play.improvements != null and play.improvements.is_open(),
	}


## The `get` op: capture the full dump (the god-mode bag is required day one),
## then slice one path out of it. An unknown path answers `ok: false`.
static func _get_frame(request: Dictionary, play: PlaySession, id: int) -> Dictionary:
	if play == null:
		return _error(id, "no live session")
	var path: String = String(request.get("path", ""))
	if path.is_empty():
		return _error(id, "get requires a path")
	var found: Dictionary = resolve(capture(play), path)
	if not bool(found["found"]):
		return _error(id, "no data at '%s'" % path)
	return _ok(id, found["value"])


static func _ok(id: int, data: Variant) -> Dictionary:
	return {"id": id, "ok": true, "data": data}


static func _error(id: int, message: String) -> Dictionary:
	return {"id": id, "ok": false, "error": message}
