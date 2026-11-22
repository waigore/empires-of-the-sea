extends SceneTree
## Throwaway probe for issue #1357: why does `navy.sortie` never fire?
## Reads every turn's fleets worldwide: who is at sea, who carries a warship,
## and which gate held each warship-bearing home fleet.

const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")

var _turns: int = 40
var _gates: Dictionary = {}
var _sea_rows: Dictionary = {}
var _home_war: Dictionary = {}


func _initialize() -> void:
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--turns="):
			_turns = raw.trim_prefix("--turns=").to_int()
	_run.call_deferred()


func _run() -> void:
	var entry: Dictionary = GameConfig.SIZES[1]
	var screen: MapScreen = SCENE.instantiate()
	screen.map_seed = 1500
	screen.map_width = int(entry["width"])
	screen.map_height = int(entry["height"])
	screen.observer_mode = true
	MapPlayTurn.view_live = false
	screen.infinite_mode = false
	root.add_child(screen)
	for _frame in 3:
		await process_frame
	var play: PlaySession = screen.play
	play.ai_mode = AiControl.FULL
	while not play.campaign_over() and play.turn <= _turns:
		MapPlayTurn.end_turn(play)
		await process_frame
		_read_world(play)
	print("--- at-sea summary (turn -> sea / warships / with army / with civilians)")
	var turns: Array = _sea_rows.keys()
	turns.sort()
	var total_sea: int = 0
	var total_war: int = 0
	for turn: Variant in turns:
		var row: Dictionary = _sea_rows[turn]
		total_sea += int(row["sea"])
		total_war += int(row["war"])
		if int(row["sea"]) > 0:
			print("t%s sea=%d warships=%d armies=%d civilians=%d" % [
				String(turn), int(row["sea"]), int(row["war"]),
				int(row["army"]), int(row["civ"]),
			])
	print("totals: fleet-turns at sea=%d, warship-turns at sea=%d" % [total_sea, total_war])
	print("--- home fleets that ever held a warship: %s" % str(_home_war.keys()))
	print("--- warship-bearing home-fleet reads, by gate")
	var gates: Array = _gates.keys()
	gates.sort()
	for gate: Variant in gates:
		print("  gate %-32s %d" % [String(gate), int(_gates[gate])])
	quit(0)


func _read_world(play: PlaySession) -> void:
	if play.world == null or play.diplomacy == null:
		return
	var sea: int = 0
	var war: int = 0
	var armies: int = 0
	var civs: int = 0
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array[FleetState] = MapPlayCourt.region_fleets(play, region)
		for fleet: FleetState in roster:
			if fleet == null or not fleet.is_afloat():
				continue
			if not fleet.is_at_sea():
				continue
			sea += 1
			if AiSquadronReads.has_warship(fleet):
				war += 1
			if fleet.embarked_army >= 0:
				armies += 1
			if not fleet.embarked_civilians.is_empty():
				civs += 1
		_read_home_fleets(play, model, roster)
	_sea_rows[play.turn] = {
		"sea": sea, "war": war, "army": armies, "civ": civs,
	}


func _read_home_fleets(play: PlaySession, model: MapModel, roster: Array[FleetState]) -> void:
	for fleet: FleetState in roster:
		if fleet == null or not NavalMovement.is_home_fleet(model, fleet):
			continue
		if fleet.moved or not fleet.is_afloat():
			continue
		var faction: int = fleet.owner
		if not MapPlayCourt.planning_factions(play).has(faction):
			continue
		if not MapPlayCourt.at_war(play, faction):
			continue
		if not AiSquadronReads.has_warship(fleet):
			_gate("no warship in the home fleet")
			continue
		if not _home_war.has(faction):
			_home_war[faction] = play.turn
		var hostile: Dictionary = Hostility.owners(play.diplomacy, faction)
		if hostile.is_empty():
			_gate("no hostile")
			continue
		if AiNavalPlanner.trade_garrison(model, roster, fleet) \
				and not AiSquadronReads.hostile_beside(model, roster, fleet, hostile):
			_gate("garrison, water clear")
			continue
		if AiNavalPlanner.trade_garrison(model, roster, fleet):
			_gate("garrison but hostile beside")
			continue
		var beside: bool = AiSquadronReads.hostile_beside(model, roster, fleet, hostile)
		if not beside:
			_gate("no hostile beside the seat")
		else:
			_gate("HOSTILE BESIDE — planner free to fight")


func _gate(gate: String) -> void:
	_gates[gate] = int(_gates.get(gate, 0)) + 1
