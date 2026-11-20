extends SceneTree
## Headless free-playtest drive for Auto mode (wiki: auto-mode; issue #725): a
## live campaign hands its seat to the AI, the paced driver plays the turns, and
## the drive prints every line the Auto log wrote beside the crown's own numbers,
## so a seat that stops acting — or a purse that stops paying — names itself.
##
##   godot --headless --path . --script res://playtests/playtest_16_auto_mode.gd
##
## Not a CI gate: twelve turns of the standard chart take about 15 s.

const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")
const SEED: int = 1500
const TURNS: int = 12


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = SCENE.instantiate()
	screen.map_seed = SEED
	screen.map_width = int(GameConfig.SIZES[1]["width"])
	screen.map_height = int(GameConfig.SIZES[1]["height"])
	screen.infinite_mode = true
	# A headless batch skips the pure-view refresh (docs/ai-observer.md § Performance).
	MapPlayTurn.view_live = false
	root.add_child(screen)
	for _frame in 3:
		await process_frame
	var play: PlaySession = screen.play
	if play == null:
		print("the map screen built no session — update playtests/playtest_16_auto_mode.gd")
		quit(1)
		return
	print("seed %d · crown %d · Auto mode at 3x" % [SEED, play.player_faction])
	MapPlayAuto.arm(play)
	# The player closes one turn themselves, answering whatever the court leaves
	# waiting: that is the boundary the seat changes at (wiki: auto-mode
	# § Arming and disarming).
	_close_turn(play)
	await process_frame
	print("seat held: %s · turn %d" % [play.auto_active, play.turn])
	var regs: int = play.army_layer.regiment_count_all(play.player_faction)
	while not play.campaign_over() and play.turn <= TURNS:
		var turn: int = play.turn
		var treasury: int = play.treasury()
		_drain(play)
		await process_frame
		var fought: int = play.hud.plates.land_queue.size() + play.hud.plates.sea_queue.size()
		print("turn %2d · %4d ducats · %3d regiments · %d land plates" % [
			turn, play.treasury(), play.army_layer.regiment_count_all(play.player_faction),
			fought,
		])
		for line: String in play.auto_log:
			print("    " + line)
		play.auto_log.clear()
		if play.turn == turn:
			print("turn %d stalled — a decision held the calendar" % turn)
			break
		if play.treasury() == treasury and play.army_layer.regiment_count_all(
			play.player_faction
		) == regs and turn > TURNS - 3:
			print("the crown's court stood still for three turns — check the seat")
	print("")
	print("ended: turn %d · %d ducats · %d regiments · campaign over: %s" % [
		play.turn, play.treasury(),
		play.army_layer.regiment_count_all(play.player_faction), play.campaign_over(),
	])
	quit(0)


## Plays one turn the way the court does before Auto takes the seat: press the
## turn, answer whatever consent decision it raises, and let it resolve.
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


## Spends the driver's ticks until the turn in flight closes.
func _drain(play: PlaySession) -> void:
	var guard: int = 0
	MapPlayAuto.tick(play)
	while play.auto_book != null and guard < 60:
		MapPlayAuto.tick(play)
		guard += 1
