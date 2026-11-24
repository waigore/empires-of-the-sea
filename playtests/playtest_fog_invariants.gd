extends SceneTree
## Headless playtest drive: plays a real campaign turn by turn and checks the
## wiki's fog standing invariants after every close for the crown **and** every
## rival court (wiki: fog-and-exploration § Fog Decay, § Distant sea zone fog,
## § Coastal sea zone visibility, § Explorer vs Spy). A violation is a rules
## defect, not a display nit.
##
## The rival economy pass applies the rivals' crews' moves, so a Spy or Explorer
## that leaves a province there must fog it in the same end-of-turn — no grace
## (wiki: fog-and-exploration § Fog Decay; civilian-units § Spy (1)). This drive
## is the proof: any province left fully visible with no crew in it fails.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_fog_invariants.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
const MAX_TURNS: int = 18

var _steps: PackedStringArray = PackedStringArray()
var _violations: Array[String] = []
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX)
	if _screen == null:
		_finish()
		return
	var play: PlaySession = _screen.play
	_say("seed %s · turn %d · player %s" % [
		SEED_TEXT, play.turn, FactionCatalog.name_of(play.player_faction),
	])
	_check(play, "opening")
	for _index in MAX_TURNS:
		if play.campaign_over():
			_say("campaign closed at turn %d" % play.turn)
			break
		_end_turn(play)
		_check(play, "turn %d" % play.turn)
	_finish()


# --- the invariants ---------------------------------------------------------


func _check(play: PlaySession, label: String) -> void:
	if play.court_charts == null:
		return
	for faction: int in FactionCatalog.great_power_ids():
		for region in play.world.region_count():
			var chart: VisibilityModel = play.court_charts.model_for(faction, region)
			var model: MapModel = play.world.region(region)
			if chart == null or model == null:
				continue
			var tag: String = "%s %s r%d" % [label, FactionCatalog.name_of(faction), region]
			_check_own_tiles(chart, model, faction, tag)
			_check_foreign_land(play, chart, model, faction, region, tag)
			_check_water(play, chart, model, faction, region, tag)


## Own provinces (and deeds) are always fully visible and never decay
## (wiki: fog-and-exploration § Own vs Other Provinces).
func _check_own_tiles(
	chart: VisibilityModel, model: MapModel, faction: int, tag: String
) -> void:
	for y in model.height:
		for x in model.width:
			if model.owner_at(x, y) != faction:
				continue
			if chart.level_at(x, y) < VisibilityModel.Level.FULLY_VISIBLE:
				_violation("own tile", tag, "%d,%d reads %d" % [
					x, y, chart.level_at(x, y),
				])


## After the pass, only own ground and a province held by an Explorer or a Spy
## keeps its tiles fully visible (wiki: fog-and-exploration § Fog Decay;
## § Explorer vs Spy — presence holds charted ground, and the last crew leaving
## fogs it in the same pass).
func _check_foreign_land(
	play: PlaySession,
	chart: VisibilityModel,
	model: MapModel,
	faction: int,
	region: int,
	tag: String
) -> void:
	var held: Array = CivilianMovement.held_provinces(
		model, _civilians(play, region), faction
	)
	for province: ProvinceState in model.provinces:
		var held_province: bool = held.has(province.id)
		var leaked: int = 0
		var sample: Vector2i = Vector2i.ZERO
		for tile: Vector2i in province.tiles:
			if model.owner_at(tile.x, tile.y) == faction:
				continue
			if chart.level_at(tile.x, tile.y) != VisibilityModel.Level.FULLY_VISIBLE:
				continue
			leaked += 1
			sample = tile
		if leaked > 0 and not held_province:
			_violation("foreign land", tag, "province %d (%d tile(s), e.g. %d,%d)" % [
				province.id, leaked, sample.x, sample.y,
			])


## A fully visible water tile after the pass belongs to a zone with an owned
## coast or a friendly squadron at sea (wiki: fog-and-exploration § Distant sea
## zone fog; § Coastal sea zone visibility).
func _check_water(
	play: PlaySession,
	chart: VisibilityModel,
	model: MapModel,
	faction: int,
	region: int,
	tag: String
) -> void:
	var at_sea: Array = []
	for fleet: FleetState in _fleets(play, region):
		if fleet.owner == faction and fleet.is_at_sea():
			at_sea.append(fleet.sea_zone)
	for zone: SeaZoneState in model.sea_zones:
		if zone.id == MapModel.NO_ID:
			continue
		if chart.owns_coast(zone.id) or at_sea.has(zone.id):
			continue
		for tile: Vector2i in zone.tiles:
			if chart.level_at(tile.x, tile.y) == VisibilityModel.Level.FULLY_VISIBLE:
				_violation("distant water", tag, "%d,%d (zone %d)" % [
					tile.x, tile.y, zone.id,
				])


# --- drivers ----------------------------------------------------------------


func _fleets(play: PlaySession, region: int) -> Array[FleetState]:
	var fleets: Array[FleetState] = []
	if play.ship_layer == null:
		return fleets
	if play.model != null and play.model.region_id == region:
		return play.ship_layer.fleets
	fleets.assign(play.ship_layer.regions.value(region, []))
	return fleets


func _civilians(play: PlaySession, region: int) -> Array[CivilianState]:
	var units: Array[CivilianState] = []
	if play.civilian_layer == null:
		return units
	if play.model != null and play.model.region_id == region:
		return play.civilian_layer.units
	units.assign(play.civilian_layer.regions.value(region, []))
	return units


func _end_turn(play: PlaySession) -> void:
	var start_turn: int = play.turn
	for _attempt in 12:
		MapPlayTurn.end_turn(play)
		if play.turn != start_turn:
			return
		var human: int = play.player_faction
		if CallToArms.has_pending(play.diplomacy, human):
			MapCourtOrders.apply(play, CallToArms.KIND_REFUSE, human, "")
		elif Intervention.has_pending(play.diplomacy, human):
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, human):
			MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, human, "")
		else:
			return
		if play.turn != start_turn:
			return
	_say("the turn would not close")


func _violation(category: String, label: String, detail: String) -> void:
	_violations.append("%s · %s · %s" % [category, label, detail])


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	_say("")
	_say("--- %d violation(s) ---" % _violations.size())
	for line: String in _violations:
		_say("  " + line)
	quit()
