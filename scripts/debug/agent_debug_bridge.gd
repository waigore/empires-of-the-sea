class_name AgentDebugBridge
extends Node
## Opt-in localhost WebSocket debug bridge (issue #699): attaches to the live
## PlaySession and answers query-only god-mode queries over TCP loopback so
## agents can inspect a running session without screenshots or save files.
##
## Off by default. Enabled with a cmdline user arg —
## `godot --path . -- --agent-debug=8765` — or, on Android where the launcher
## alias drops the launch intent's `command_line` extra (a Godot 4.7 template
## limitation its own instrumented tests assert), with a one-line enable file
## in `user://`. Binds `127.0.0.1` only; on Android the host reaches it through
## `adb forward tcp:PORT tcp:PORT` (docs/agent-debug.md). Responses come from
## `AgentDebugDump`; this node owns only the socket (REQ-P3-02/03).

const FLAG: String = "--agent-debug"
const DEFAULT_PORT: int = 8765
## Query-only channel for tooling: a small peer cap keeps one bridge from
## fanning out wide.
const MAX_PEERS: int = 4
## The Android enable file: `user://agent_debug.enable`, one line with the
## port (or empty for the default). Consumed on the boot that reads it.
const ENABLE_FILE: String = "agent_debug.enable"
## A full-world `dump` answer is a single text frame (~100 KB+), above the
## 64 KB peer defaults, so each accepted peer gets a megabyte both ways
## (issue #699).
const PEER_BUFFER_BYTES: int = 1048576

var play: PlaySession = null
## Port the bridge listens on, 0 while disabled. A negative parse result
## (malformed flag) never turns the listener on.
var port: int = 0

var _server: TCPServer = null
var _peers: Array[WebSocketPeer] = []


func _ready() -> void:
	var launch: Dictionary = resolve_launch(
		OS.get_cmdline_user_args(), OS.get_cmdline_args()
	)
	var requested: int = int(launch["port"])
	if bool(launch["warn_unparsed"]):
		print("AgentDebugBridge: flag seen but not parsed; args=%s" %
			[OS.get_cmdline_args()])
	if requested <= 0:
		# Android's launcher alias drops the launch intent's `command_line`
		# extra, so the channel also accepts the enable file (Android path).
		requested = read_enable_file()
	if requested > 0 and not _release_export():
		start(requested)
	elif requested != 0:
		print("AgentDebugBridge: disabled (%s)" %
			("release export" if _release_export() else "bad port"))


## The Android opt-in: a one-line `user://agent_debug.enable` with the port
## (or empty for the default). Consumed on the boot that reads it, so a stale
## file never silently re-enables a later session. Desktop agents use the
## cmdline flag; the file is the documented Android path (docs/agent-debug.md).
static func read_enable_file() -> int:
	if not FileAccess.file_exists("user://" + ENABLE_FILE):
		return 0
	var handle := FileAccess.open("user://" + ENABLE_FILE, FileAccess.READ)
	if handle == null:
		return 0
	var line := handle.get_line().strip_edges()
	handle.close()
	var requested: int = (
		DEFAULT_PORT if line.is_empty()
		else parse_port(PackedStringArray(["--agent-debug=%s" % line]))
	)
	if requested > 0:
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(ENABLE_FILE)
	return requested


## User args first, then full cmdline (Android intent extras land there).
## `warn_unparsed` is true when the flag was named but neither list parsed.
static func resolve_launch(
	user_args: PackedStringArray, cmdline_args: PackedStringArray
) -> Dictionary:
	var requested: int = parse_port(user_args)
	if requested != 0:
		return {"port": requested, "warn_unparsed": false}
	# Android export templates carry the `command_line` intent extra as
	# engine args, not user args (docs/agent-debug.md).
	requested = parse_port(cmdline_args)
	var warn: bool = requested == 0 and (
		flag_mentioned(user_args) or flag_mentioned(cmdline_args)
	)
	return {"port": requested, "warn_unparsed": warn}


## True when an arg list names the flag, so a launch that tried to enable
## the bridge but misformed the value still explains itself in the log.
static func flag_mentioned(args: PackedStringArray) -> bool:
	for raw: String in args:
		if raw.contains(FLAG):
			return true
	return false


## Reads the flag out of parsed user args: `--agent-debug` (default port),
## `--agent-debug=PORT`. Absent → 0; malformed or out of range → -1.
static func parse_port(args: PackedStringArray) -> int:
	for raw: String in args:
		if not raw.begins_with(FLAG):
			continue
		var value: String = raw.trim_prefix(FLAG)
		if value.begins_with("="):
			value = value.substr(1)
		elif not value.is_empty():
			continue
		if value.is_empty():
			return DEFAULT_PORT
		if not value.is_valid_int():
			return -1
		var parsed: int = int(value)
		return parsed if parsed >= 1 and parsed <= 65535 else -1
	return 0


func start(p_port: int) -> void:
	stop()
	if p_port < 1 or p_port > 65535:
		return
	_server = TCPServer.new()
	if _server.listen(p_port, "127.0.0.1") != OK:
		push_error("AgentDebugBridge: cannot listen on 127.0.0.1:%d" % p_port)
		_server = null
		return
	port = p_port
	print("AgentDebugBridge: listening on 127.0.0.1:%d" % p_port)
	if play == null:
		var screen := get_parent() as MapScreen
		if screen != null:
			play = screen.play


## Binds the first free loopback port from `base` upward (tests / playtests);
## answers the bound port, or 0 when none in the short window listened.
func start_first_free(base: int) -> int:
	for offset in 8:
		start(base + offset)
		if is_listening():
			return port
	return 0


func stop() -> void:
	for peer: WebSocketPeer in _peers:
		peer.close()
	_peers.clear()
	if _server != null:
		_server.stop()
		_server = null
	port = 0


func is_listening() -> bool:
	return _server != null


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if _server == null:
		return
	_accept()
	_poll_peers()


func _accept() -> void:
	while _server.is_connection_available():
		var stream: StreamPeerTCP = _server.take_connection()
		if _peers.size() >= MAX_PEERS:
			stream.disconnect_from_host()
			continue
		var peer := WebSocketPeer.new()
		if peer.accept_stream(stream) == OK:
			peer.inbound_buffer_size = PEER_BUFFER_BYTES
			peer.outbound_buffer_size = PEER_BUFFER_BYTES
			_peers.append(peer)
		else:
			stream.disconnect_from_host()


func _poll_peers() -> void:
	var closed: Array[int] = []
	for index in _peers.size():
		var peer := _peers[index]
		peer.poll()
		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while peer.get_available_packet_count() > 0:
					var sent: Error = peer.send_text(
						_answer(peer.get_packet().get_string_from_utf8())
					)
					if sent != OK:
						push_warning("AgentDebugBridge: send failed (%d)" % sent)
			WebSocketPeer.STATE_CLOSED:
				closed.append(index)
	# Remove from the back so the queued indices stay valid.
	for offset in closed.size():
		_peers.remove_at(closed[closed.size() - 1 - offset])


## One text frame in, one text frame out. An unparseable frame still answers,
## so an agent's first probe never dangles.
func _answer(text: String) -> String:
	return JSON.stringify(AgentDebugDump.frame(JSON.parse_string(text), play))


## Release player exports never carry the channel (issue #699 acceptance).
func _release_export() -> bool:
	return OS.has_feature("template_release")
