extends GdToolsTest
## Agent Debug Bridge (issue #699): the pure projector's JSON shapes, the flag
## parser and the thin server's lifecycle — one live loopback round-trip in
## process. The projector is the rules surface (REQ-P3-03); the bridge owns
## only the socket.

const Fixture = preload("res://tests/map_fixture.gd")
const DUMP_KEYS: Array[String] = [
	"version", "game_version", "saved_at", "session", "regions", "visibility",
	"economy", "market", "diplomacy", "ai", "victory", "defeat", "gazette",
	"civilians", "fleets", "armies", "generals",
]
const LIVE_KEYS: Array[String] = [
	"observer_mode", "ai_mode", "ai_live_faction", "ai_turns", "ai_trace",
	"turn_suspended", "announced_decisions", "market_report", "court_reports",
	"selection", "hover", "region", "hud",
]

## Non-underscore: gd-tools clones a fresh suite instance per test and does not
## copy underscore fields out of before_all (docs/testing.md speed rules).
var mounted: MapScreen = null


func before_all() -> void:
	mounted = Fixture.attach_screen(self)


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null


# --- the projector's dump shapes ---------------------------------------------


func test_dump_carries_the_save_bag_plus_live_overlays() -> void:
	var play: PlaySession = mounted.play
	var dump: Dictionary = AgentDebugDump.capture(play)
	for key: String in DUMP_KEYS:
		assert_true(dump.has(key), "the dump carries the save bag's %s" % key)
	var live: Dictionary = dump["live"]
	for key: String in LIVE_KEYS:
		assert_true(live.has(key), "the live overlay reports %s" % key)
	assert_eq(bool(live["observer_mode"]), play.observer_mode, "the overlay reads the session")
	assert_eq(int(live["selection"]), play.selected_province, "the overlay reports the selection")
	assert_eq(int(live["region"]), play.region_index, "the overlay reports the region")
	assert_true(live["hud"] is Dictionary, "hud hints ride with the overlay")
	assert_ne(JSON.stringify(dump), "", "the full dump is JSON-safe")


func test_a_session_without_a_world_still_dumps_its_overlays() -> void:
	var dump: Dictionary = AgentDebugDump.capture(PlaySession.new())
	assert_true(dump.has("live"), "the overlays ride alone without a world")
	assert_false(dump.has("regions"), "an empty save bag carries no regions")
	assert_ne(JSON.stringify(dump), "", "the overlay-only dump is JSON-safe")


# --- the protocol frame --------------------------------------------------------


func test_ping_answers_and_keeps_the_id() -> void:
	var answer: Dictionary = AgentDebugDump.frame({"id": 1, "op": "ping"}, mounted.play)
	assert_true(bool(answer["ok"]), "ping answers ok")
	assert_eq(int(answer["id"]), 1, "the answer carries the request id")
	assert_true(bool(answer["data"]["pong"]), "ping pongs")


func test_session_reports_the_live_card() -> void:
	var play: PlaySession = mounted.play
	var answer: Dictionary = AgentDebugDump.frame({"id": 2, "op": "session"}, play)
	assert_true(bool(answer["ok"]), "session answers ok")
	var data: Dictionary = answer["data"]
	assert_eq(int(data["turn"]), play.turn, "the card names the turn")
	assert_eq(int(data["player_faction"]), play.player_faction, "the card names the crown")
	assert_eq(int(data["seed"]), play.map_seed, "the card names the seed")
	assert_ne(JSON.stringify(data), "", "the card is JSON-safe")


func test_dump_observer_and_get_answer_ok() -> void:
	var play: PlaySession = mounted.play
	var dump: Dictionary = AgentDebugDump.frame({"id": 3, "op": "dump"}, play)
	assert_true(bool(dump["ok"]), "dump answers ok")
	assert_true((dump["data"] as Dictionary).has("live"), "dump carries the overlays")
	var observer: Dictionary = AgentDebugDump.frame({"id": 4, "op": "observer"}, play)
	assert_true(bool(observer["ok"]), "observer answers ok")
	assert_true((observer["data"] as Dictionary).has("rows"), "observer is the scoreboard")
	var slice: Dictionary = AgentDebugDump.frame({"id": 5, "op": "get", "path": "session"}, play)
	assert_true(bool(slice["ok"]), "get answers ok")
	assert_eq(
		int(slice["data"]["turn"]), play.turn,
		"a top-level path slices the god-mode bag"
	)
	var nested: Dictionary = AgentDebugDump.frame(
		{"id": 6, "op": "get", "path": "live.ai_mode"}, play
	)
	assert_true(bool(nested["ok"]), "a nested path resolves")


func test_get_reports_unknown_and_missing_paths() -> void:
	var play: PlaySession = mounted.play
	var unknown: Dictionary = AgentDebugDump.frame({"id": 7, "op": "get", "path": "mystery"}, play)
	assert_false(bool(unknown["ok"]), "an unknown top-level key answers error")
	assert_true(String(unknown["error"]).contains("mystery"), "the error names the path")
	var missing: Dictionary = AgentDebugDump.frame({"id": 8, "op": "get"}, play)
	assert_false(bool(missing["ok"]), "a get without a path is an error")
	var deep: Dictionary = AgentDebugDump.frame(
		{"id": 9, "op": "get", "path": "live.nope.x"}, play
	)
	assert_false(bool(deep["ok"]), "a missing hop answers error")


func test_bad_frames_answer_errors_not_dangles() -> void:
	var play: PlaySession = mounted.play
	var unparseable: Dictionary = AgentDebugDump.frame(17, play)
	assert_false(bool(unparseable["ok"]), "a non-object frame answers an error")
	assert_eq(int(unparseable["id"]), -1, "no id can be kept")
	var unknown_op: Dictionary = AgentDebugDump.frame({"id": 10, "op": "mystery"}, play)
	assert_false(bool(unknown_op["ok"]), "an unknown op answers an error")
	var no_id: Dictionary = AgentDebugDump.frame({"op": "ping"}, play)
	assert_eq(int(no_id["id"]), -1, "a missing id falls back to -1")


func test_frames_without_a_session_error_but_ping_lives() -> void:
	var dump: Dictionary = AgentDebugDump.frame({"id": 11, "op": "dump"}, null)
	assert_false(bool(dump["ok"]), "no session, no dump")
	assert_eq(String(dump["error"]), "no live session", "the error is plain")
	var pong: Dictionary = AgentDebugDump.frame({"id": 12, "op": "ping"}, null)
	assert_true(bool(pong["ok"]), "ping still answers without a session")


# --- the flag parser -----------------------------------------------------------


func test_parse_port_reads_the_flag() -> void:
	assert_eq(AgentDebugBridge.parse_port(PackedStringArray()), 0, "no flag, no port")
	assert_eq(
		AgentDebugBridge.parse_port(PackedStringArray(["--agent-debug=8765"])),
		8765, "an explicit port wins"
	)
	assert_eq(
		AgentDebugBridge.parse_port(PackedStringArray(["--agent-debug"])),
		AgentDebugBridge.DEFAULT_PORT, "a bare flag takes the default port"
	)
	assert_eq(
		AgentDebugBridge.parse_port(PackedStringArray(["--quiet", "--agent-debug=1234"])),
		1234, "the flag is read among other user args"
	)


func test_parse_port_refuses_bad_ports() -> void:
	for bad: String in ["0", "-1", "99999", "abc", "8765x"]:
		assert_eq(
			AgentDebugBridge.parse_port(PackedStringArray(["--agent-debug=%s" % bad])),
			-1, "port %s is refused" % bad
		)
	assert_eq(
		AgentDebugBridge.parse_port(PackedStringArray(["--agent-debug-port=1"])),
		0, "a different flag sharing the prefix is ignored"
	)


func test_flag_mentioned_spots_a_misformed_enable() -> void:
	assert_false(
		AgentDebugBridge.flag_mentioned(PackedStringArray()),
		"an empty list never mentions the flag"
	)
	assert_false(
		AgentDebugBridge.flag_mentioned(PackedStringArray(["--quiet"])),
		"unrelated args do not mention the flag"
	)
	assert_true(
		AgentDebugBridge.flag_mentioned(PackedStringArray(["--agent-debug"])),
		"a bare flag is mentioned"
	)
	assert_true(
		AgentDebugBridge.flag_mentioned(PackedStringArray(["--agent-debug=8765"])),
		"an explicit port is mentioned"
	)
	assert_true(
		AgentDebugBridge.flag_mentioned(PackedStringArray(["--agent-debugfoo"])),
		"a misformed token still mentions the flag for the diagnostic"
	)


func test_resolve_launch_prefers_user_args_then_cmdline() -> void:
	var from_user: Dictionary = AgentDebugBridge.resolve_launch(
		PackedStringArray(["--agent-debug=1234"]),
		PackedStringArray(["--agent-debug=9999"]),
	)
	assert_eq(int(from_user["port"]), 1234, "user args win over the full cmdline")
	assert_false(bool(from_user["warn_unparsed"]), "a parsed port needs no warn")
	var from_cmdline: Dictionary = AgentDebugBridge.resolve_launch(
		PackedStringArray(),
		PackedStringArray(["--agent-debug=4321"]),
	)
	assert_eq(int(from_cmdline["port"]), 4321, "Android-style cmdline is the fallback")
	assert_false(bool(from_cmdline["warn_unparsed"]), "a cmdline parse needs no warn")
	var absent: Dictionary = AgentDebugBridge.resolve_launch(
		PackedStringArray(["--quiet"]),
		PackedStringArray(["--path", "."]),
	)
	assert_eq(int(absent["port"]), 0, "no flag means the bridge stays off")
	assert_false(bool(absent["warn_unparsed"]), "absence is not a misform")
	var misformed: Dictionary = AgentDebugBridge.resolve_launch(
		PackedStringArray(),
		PackedStringArray(["--agent-debugfoo"]),
	)
	assert_eq(int(misformed["port"]), 0, "a misformed token does not parse")
	assert_true(bool(misformed["warn_unparsed"]), "a misformed enable still warns")
	var bad_port: Dictionary = AgentDebugBridge.resolve_launch(
		PackedStringArray(["--agent-debug=0"]),
		PackedStringArray(),
	)
	assert_eq(int(bad_port["port"]), -1, "an out-of-range user port is refused")
	assert_false(bool(bad_port["warn_unparsed"]), "a refused parse is not unparsed")


# --- the thin server -----------------------------------------------------------


func test_the_screen_hosts_an_inert_bridge() -> void:
	var bridge: AgentDebugBridge = mounted.get_node_or_null("AgentDebugBridge") as AgentDebugBridge
	assert_not_null(bridge, "the map screen hosts the bridge")
	if bridge == null:
		return
	assert_false(bridge.is_listening(), "the bridge is off without the flag")
	assert_eq(bridge.play, mounted.play, "the bridge holds the live session")


func test_start_stop_and_a_live_loopback_round_trip() -> void:
	var bridge := AgentDebugBridge.new()
	bridge.name = "AgentDebugBridgeProbe"
	bridge.play = mounted.play
	add_child(bridge)
	bridge.start(0)
	assert_false(bridge.is_listening(), "an out-of-range port never listens")
	var bound: int = bridge.start_first_free(9377)
	assert_true(bound > 0, "the bridge binds a loopback port")
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % bound)
	var opened: bool = _await_open(bridge, ws)
	assert_true(opened, "a local peer completes the handshake")
	if opened:
		ws.send_text('{"id":7,"op":"ping"}')
		var reply: String = _await_reply(bridge, ws)
		assert_ne(reply, "", "the bridge answers the frame")
		var answer: Variant = JSON.parse_string(reply)
		if typeof(answer) == TYPE_DICTIONARY:
			assert_eq(int(answer["id"]), 7, "the reply keeps the request id")
			assert_true(bool(answer["ok"]), "ping rides the live socket")
	bridge.stop()
	assert_false(bridge.is_listening(), "stop closes the listener")
	bridge.free()


func _await_open(bridge: AgentDebugBridge, ws: WebSocketPeer) -> bool:
	for _attempt in 200:
		ws.poll()
		bridge._process(0.0)
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			return false
		OS.delay_msec(2)
	return false


func _await_reply(bridge: AgentDebugBridge, ws: WebSocketPeer) -> String:
	for _attempt in 200:
		bridge._process(0.0)
		ws.poll()
		if ws.get_available_packet_count() > 0:
			return ws.get_packet().get_string_from_utf8()
		OS.delay_msec(2)
	return ""
