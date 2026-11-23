extends SceneTree
## Headless free-playtest drive for the rival overseas invasion (wiki:
## ships-and-naval § Missions and Movement, § Naval transport; ai-architecture
## § Naval policy): an all-AI campaign plays real turns and the drive reads every
## expedition the way the court's trace does — the boarding, the Passage, the
## beachhead and the landing — beside the landing gate's own verdict, so a stalled
## expedition names the gate that refused it (a site whose shore changed hands
## before it opened). The observer's turn trace shows the legs; this shows why a
## leg never comes.
##
##   godot --headless --path . --script res://playtests/playtest_overseas_invasion.gd
##
## Not a CI gate: 40 turns of the standard chart take about 45 s.

const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")
const SEED: int = 1500
const TURNS: int = 40

## Landings the campaign's own turn trace recorded, one line each.
var _ashore: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = SCENE.instantiate()
	screen.map_seed = SEED
	screen.map_width = int(GameConfig.SIZES[1]["width"])
	screen.map_height = int(GameConfig.SIZES[1]["height"])
	screen.observer_mode = true
	screen.infinite_mode = true
	# A headless batch skips the pure-view refresh (docs/ai-observer.md § Performance).
	MapPlayTurn.view_live = false
	root.add_child(screen)
	for _frame in 3:
		await process_frame
	var play: PlaySession = screen.play
	if play == null:
		print("the map screen built no session — update playtests/playtest_overseas_invasion.gd")
		quit(1)
		return
	play.ai_mode = AiControl.FULL
	var panel := screen.get_node_or_null("AiObserver") as AiObserverPanel
	if panel != null:
		panel.running = false
	print("seed %d · all-AI campaign · reading rival expeditions" % SEED)
	while not play.campaign_over() and play.turn <= TURNS:
		var before: int = play.turn
		MapPlayTurn.end_turn(play)
		await process_frame
		_read(play)
		if play.turn == before:
			print("turn %d stalled (a decision is suspended)" % before)
			break
	print("")
	if _ashore.is_empty():
		print("no army came ashore in %d turns" % TURNS)
	else:
		print("armies that came ashore: %d in %d turns" % [_ashore.size(), TURNS])
	screen.free()
	quit(0)


## Every squadron carrying troops this turn and the step the planner would give
## it next — with the landing gate's own words when that step is a landing. The
## campaign's turn trace follows, so a leg the fleets no longer show (a landing)
## still reads.
func _read(play: PlaySession) -> void:
	for region: int in play.ship_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var fleets: Array = MapPlayCourtRoster.region_fleets(play, region)
		var armies: Array[ArmyState] = MapPlayCourtRoster.visible_armies(play, region)
		for raw: Variant in fleets:
			var fleet: FleetState = raw
			if fleet == null or fleet.embarked_army < 0:
				continue
			var army: ArmyState = null
			for candidate: ArmyState in armies:
				if candidate != null and candidate.embarked_fleet == fleet.id:
					army = candidate
			if army == null:
				continue
			var order: Dictionary = _order(play, region, model, fleets, armies, fleet)
			print("t%d %s · %s · %d regiment%s aboard · %s%s" % [
				play.turn, FactionCatalog.name_of(fleet.owner), _station(model, fleet),
				army.count(), "" if army.count() == 1 else "s",
				_step_text(order), _gate_text(play, model, army, fleet, order),
			])
	_landings(play)


## The turn's own expedition rows (AiTurnLog): the boarding, the Passage and the
## landing as the court's trace writes them.
func _landings(play: PlaySession) -> void:
	if play.ai_turns.is_empty():
		return
	var record: Dictionary = play.ai_turns.back()
	for raw: Variant in record.get("events", []):
		var event: String = String((raw as Dictionary).get("text", ""))
		if not event.contains("army lands at"):
			continue
		_ashore.append(event)
		print("  %s" % event)


## The step the court would take next, from the planner the game itself calls.
func _order(
	play: PlaySession, region: int, model: MapModel, fleets: Array, armies: Array,
	fleet: FleetState
) -> Dictionary:
	var kind: String = AiControl.court_kind(play, fleet.owner)
	if kind == AiControl.KIND_RANDOM:
		return {}
	var config: Variant = AiBind.config(kind, fleet.owner, play.map_seed)
	var earning: bool = str(AiBindEconomy.income_plan(
		kind, config, play.ledger_for(fleet.owner),
		MapPlayCourt.at_war(play, fleet.owner),
		MapPlayCourtHoldings.regiments(play, fleet.owner),
		MapPlayCourtHoldings.navy_chest(play, fleet.owner),
		MapPlayCourtHoldings.warships(play, fleet.owner)
	).get("goal", "")) == "earn"
	return AiBindCampaign.invasion_plan(
		kind, config, play.diplomacy, play.world, region, model, fleets, armies,
		play.turn, play.court_charts, earning
	)


## The landing gate's verdict, in the rules' own words — empty when the step is
## not a landing (the other steps are not gated here).
func _gate_text(
	play: PlaySession, model: MapModel, army: ArmyState, fleet: FleetState, order: Dictionary
) -> String:
	if order.is_empty() or String(order.get("kind", "")) != AiInvasionPlanner.KIND_LAND:
		return ""
	var check: Dictionary = NavalTransport.can_disembark(
		model, army, fleet, int(order.get("province", -1)), play.turn,
		MapPlayBeachhead.hostile(play)
	)
	if bool(check.get("ok", false)):
		return " · gate open"
	return " · gate: %s" % String(check.get("reason", ""))


func _station(model: MapModel, fleet: FleetState) -> String:
	if not fleet.is_at_sea():
		return "in port at %s" % model.province_name(fleet.province)
	var sea: String = "Old World" if model.region_id == WorldMap.OLD_WORLD else "New World"
	return "%s, %s" % [model.sea_zone_name(fleet.sea_zone), sea]


func _step_text(order: Dictionary) -> String:
	var kind: String = String(order.get("kind", ""))
	if kind.is_empty():
		return "no step"
	if order.has("province") and int(order["province"]) >= 0:
		return "%s %d" % [kind, int(order["province"])]
	if order.has("zone"):
		return "%s zone %d" % [kind, int(order["zone"])]
	return kind
