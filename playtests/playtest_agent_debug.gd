extends SceneTree
## Headless playtest drive for the agent debug bridge (issue #699): the game is
## launched with the real `-- --agent-debug=PORT` user arg, the map mounts, and
## the drive walks the protocol over a live loopback WebSocket — `ping`,
## `session`, `get`, and one full `dump` round trip. It also proves the default
## is off: without the flag the bridge is inert. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_agent_debug.gd -- --agent-debug=8901
##
## Query-only: the drive sends no orders and resolves no turns.

const Launch = preload("res://playtests/playtest_launch.gd")
const DEFAULT_PORT: int = 8901

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var port: int = _flag_port()
	if port <= 0:
		_fail("run with: godot --headless --path . --script res://playtests/playtest_agent_debug.gd -- --agent-debug=8901")
		return
	var screen: MapScreen = await Launch.open_map(self, "1500")
	if screen == null:
		_finish()
		return
	_screen = screen
	var bridge: AgentDebugBridge = screen.get_node_or_null("AgentDebugBridge") as AgentDebugBridge
	if bridge == null:
		_fail("the map screen hosts no AgentDebugBridge")
		return
	if not bridge.is_listening():
		_fail("the bridge did not start with -- --agent-debug=%d" % port)
		return
	if bridge.port != port:
		_fail("the bridge listens on %d, not %d" % [bridge.port, port])
		return
	_say("bridge listening on 127.0.0.1:%d (session turn %d)" % [port, screen.play.turn])
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = AgentDebugBridge.PEER_BUFFER_BYTES
	ws.outbound_buffer_size = AgentDebugBridge.PEER_BUFFER_BYTES
	ws.connect_to_url("ws://127.0.0.1:%d" % port)
	if not await _open(ws, bridge):
		_fail("the local peer never completed the handshake")
		return
	_pong(await _round_trip(ws, '{"id":1,"op":"ping"}'))
	var session: Variant = await _round_trip(ws, '{"id":2,"op":"session"}')
	_card(session)
	var slice: Variant = await _round_trip(ws, '{"id":3,"op":"get","path":"live.ai_mode"}')
	_slice(slice)
	var miss: Variant = await _round_trip(ws, '{"id":4,"op":"get","path":"mystery"}')
	_miss(miss)
	var dump: Variant = await _round_trip(ws, '{"id":5,"op":"dump"}')
	_bag(dump)
	_scoreboard(await _round_trip(ws, '{"id":6,"op":"observer"}'))
	var garbage: Variant = await _round_trip(ws, "not json at all")
	_garbage(garbage)
	ws.close()
	bridge.stop()
	if not bridge.is_listening():
		_say("bridge stopped cleanly")
	_screen.get_parent().call_deferred("free")
	_say("PLAYTEST PASS — agent debug bridge")
	_finish()


func _open(ws: WebSocketPeer, bridge: AgentDebugBridge) -> bool:
	for _attempt in 300:
		ws.poll()
		bridge._process(0.0)
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			return false
		await process_frame
	return false


func _round_trip(ws: WebSocketPeer, request: String) -> Variant:
	ws.send_text(request)
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		ws.poll()
		if ws.get_available_packet_count() > 0:
			return JSON.parse_string(ws.get_packet().get_string_from_utf8())
		OS.delay_msec(10)
		await process_frame
	return null


func _pong(answer: Variant) -> void:
	var frame: Dictionary = _frame(answer)
	_expect(frame.get("ok") == true, "ping answers ok")
	_expect(int(frame.get("id", -2)) == 1, "ping keeps the id")
	_expect((frame.get("data", {}) as Dictionary).get("pong") == true, "ping pongs")


func _card(answer: Variant) -> void:
	var data: Dictionary = _frame(answer).get("data", {}) as Dictionary
	_expect(int(data.get("turn", 0)) >= 1, "the session card names the turn")
	_expect(data.has("year") and data.has("player_faction"), "the card names year and crown")
	_say("session: turn %d, %s, %d" % [
		int(data.get("turn", 0)), TurnTime.year_for_turn(int(data.get("turn", 1))),
		int(data.get("player_faction", -1)),
	])


func _slice(answer: Variant) -> void:
	var frame: Dictionary = _frame(answer)
	_expect(frame.get("ok") == true, "a live overlay path slices")
	_say("get live.ai_mode -> %s" % [str(frame.get("data", ""))])


func _miss(answer: Variant) -> void:
	var frame: Dictionary = _frame(answer)
	_expect(frame.get("ok") == false, "an unknown path answers an error")
	_say("get mystery -> %s" % [str(frame.get("error", ""))])


func _bag(answer: Variant) -> void:
	var frame: Dictionary = _frame(answer)
	var data: Dictionary = frame.get("data", {}) as Dictionary
	if not (frame.get("ok") == true and data.has("live") and data.has("regions")):
		_say("dump frame was: %s" % [str(frame).left(300)])
	_expect(
		frame.get("ok") == true and data.has("live") and data.has("regions"),
		"the dump carries the save bag plus the live overlays"
	)
	var live: Dictionary = data.get("live", {}) as Dictionary
	_say("dump: %d top keys, live overlays %d keys, ai_turns %d" % [
		data.size(), live.size(), (live.get("ai_turns", []) as Array).size(),
	])


func _scoreboard(answer: Variant) -> void:
	var data: Dictionary = _frame(answer).get("data", {}) as Dictionary
	var rows: Array = data.get("rows", [])
	_expect(rows.size() > 0, "the observer scoreboard ranks the crowns")


func _garbage(answer: Variant) -> void:
	var frame: Dictionary = _frame(answer)
	_expect(frame.get("ok") == false, "a non-JSON frame answers an error, not silence")
	_say("garbage -> %s" % [str(frame.get("error", ""))])


func _frame(answer: Variant) -> Dictionary:
	return answer if typeof(answer) == TYPE_DICTIONARY else {}


func _flag_port() -> int:
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--agent-debug="):
			var value: String = raw.substr("--agent-debug=".length())
			return int(value) if value.is_valid_int() else 0
	return 0


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail("FAILED: %s" % what)


func _say(line: String) -> void:
	print("e2e_agent_debug: ", line)
	_steps.append(line)


func _fail(line: String) -> void:
	push_error("e2e_agent_debug: %s" % line)
	print("e2e_agent_debug: FAIL — ", line)
	for step: String in _steps:
		print("  · ", step)
	quit(1)


func _finish() -> void:
	quit(0)
