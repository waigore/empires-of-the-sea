extends SceneTree
## Headless e2e auto: Small chart, arm Auto, drain five paced turns, assert the
## seat and god-mode bag stayed sane. Same CI job as smoke (`e2e-smoke`), runs
## after it. In-process PlaySession / AgentDebugDump — no WebSocket.
##   godot --headless --path . --script res://tools/e2e_auto.gd
##
## Budget: share the job's ≤5 min wall with smoke (docs/testing.md). Reuses the
## arm + drain path from playtests/playtest_16_auto_mode.gd (wiki: auto-mode).

const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")
const SEED: int = 1500
const AUTO_TURNS: int = 5
## 3x — index into MapPlayAuto.SPEED_SECONDS (headless drain ignores the delay).
const SPEED_3X: int = 3
## Purse / host bounds that still look like a live early campaign.
const TREASURY_MIN: int = -5_000
const TREASURY_MAX: int = 1_000_000
const REGS_MAX: int = 5_000
const DRAIN_GUARD: int = 120

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	MapPlayTurn.view_live = false
	var screen: MapScreen = SCENE.instantiate()
	screen.map_seed = SEED
	screen.map_width = int(GameConfig.SIZES[0]["width"])
	screen.map_height = int(GameConfig.SIZES[0]["height"])
	root.add_child(screen)
	for _frame in 3:
		await process_frame

	var play: PlaySession = screen.play
	_check(play != null, "map screen seats a PlaySession")
	if play == null:
		_finish()
		return

	play.auto_speed = SPEED_3X
	MapPlayAuto.arm(play)
	_close_turn(play)
	await process_frame

	_check(play.auto_active, "Auto holds the seat after the arming turn")
	_check(not play.turn_suspended, "arming turn left no suspended decision")
	_check(not play.campaign_over(), "campaign open after arming turn")
	_check(play.defeat == null, "crown not defeated after arming turn")

	var start_turn: int = play.turn
	play.auto_log.clear()
	for i in AUTO_TURNS:
		var before: int = play.turn
		_drain(play)
		await process_frame
		_check(play.turn == before + 1, "Auto turn %d advanced the calendar" % (i + 1))
		_check(not play.turn_suspended, "Auto turn %d left no stall" % (i + 1))
		_check(play.auto_active, "Auto still holds the seat on turn %d" % (i + 1))
		_check(not play.auto_log.is_empty(), "Auto log has lines on turn %d" % (i + 1))
		_check_purse(play, i + 1)
		play.auto_log.clear()

	_check(play.turn == start_turn + AUTO_TURNS, "calendar advanced exactly +%d" % AUTO_TURNS)
	_check(not play.campaign_over(), "campaign still open after %d Auto turns" % AUTO_TURNS)
	_check(play.defeat == null, "crown not defeated after Auto run")
	_check_dump(play, start_turn + AUTO_TURNS)

	MapPlayTurn.view_live = true
	if is_instance_valid(screen):
		screen.free()
	_finish()


func _check_purse(play: PlaySession, n: int) -> void:
	var treasury: int = play.treasury()
	var regs: int = 0
	if play.army_layer != null:
		regs = play.army_layer.regiment_count_all(play.player_faction)
	_check(
		treasury >= TREASURY_MIN and treasury <= TREASURY_MAX,
		"treasury in bounds on Auto turn %d (%d)" % [n, treasury]
	)
	_check(regs >= 0 and regs <= REGS_MAX, "regiments in bounds on Auto turn %d (%d)" % [n, regs])


## God-mode bag the debug bridge would serve — same projector, no socket.
func _check_dump(play: PlaySession, expected_turn: int) -> void:
	var dump: Dictionary = AgentDebugDump.capture(play)
	_check(not dump.is_empty(), "AgentDebugDump.capture non-empty")
	var turn_slice: Dictionary = AgentDebugDump.resolve(dump, "session.turn")
	_check(bool(turn_slice.get("found", false)), "dump has session.turn")
	_check(int(turn_slice.get("value", -1)) == expected_turn, "dump session.turn matches calendar")
	var economy: Dictionary = AgentDebugDump.resolve(dump, "economy")
	_check(bool(economy.get("found", false)), "dump has economy")
	_check(typeof(economy.get("value")) == TYPE_DICTIONARY, "dump economy is a Dictionary")
	var diplomacy: Dictionary = AgentDebugDump.resolve(dump, "diplomacy")
	_check(bool(diplomacy.get("found", false)), "dump has diplomacy")
	_check(typeof(diplomacy.get("value")) == TYPE_DICTIONARY, "dump diplomacy is a Dictionary")
	var ai_mode: Dictionary = AgentDebugDump.resolve(dump, "live.ai_mode")
	_check(bool(ai_mode.get("found", false)), "dump has live.ai_mode")
	_check(String(ai_mode.get("value", "")) != "", "live.ai_mode non-empty")
	_check(play.auto_active, "auto_active still true when dump is read")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("e2e_auto: PASS %s" % label)
	else:
		printerr("e2e_auto: FAIL %s" % label)
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("e2e_auto: all asserts passed")
		quit(0)
		return
	printerr(
		"e2e_auto: %d assert(s) failed: %s" % [_failures.size(), ", ".join(_failures)]
	)
	quit(1)


## Player End Turn that seats Auto (wiki: auto-mode § Arming and disarming).
func _close_turn(play: PlaySession) -> void:
	MapPlayTurn.end_turn(play)
	var guard: int = 0
	while play.turn_suspended and guard < 6:
		guard += 1
		match ConsentLadder.pending_kind(play.diplomacy, play.player_faction):
			ConsentLadder.CALL:
				MapPlayTurn.answer_call(play, false)
			ConsentLadder.INTERVENTION:
				MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
			ConsentLadder.OFFER:
				MapPlayTurn.answer_offer(play, false)
			_:
				play.turn_suspended = false


## Drain one paced Auto turn via MapPlayAuto.tick (same as the playtest).
func _drain(play: PlaySession) -> void:
	var guard: int = 0
	MapPlayAuto.tick(play)
	while play.auto_book != null and guard < DRAIN_GUARD:
		MapPlayAuto.tick(play)
		guard += 1
