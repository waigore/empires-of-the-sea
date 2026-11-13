extends SceneTree
## Headless free-playtest drive for the New World exploration loop
## (wiki: fog-and-exploration, civilian-units): boards an Explorer at the
## capital, takes the Passage, lands on uncharted coast, charters a province and
## prospects a mineral tile. Prints one line per step, so a run reads as a
## playtest diary. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_new_world.gd
##
## The fleet is staged in the Passage zone before crossing (a scenario seat, the
## same one rules tests use) so the loop is reachable in one run; everything
## after the crossing is ordered through the game's own play helpers.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
const MAX_TURNS: int = 12
const MARCH_LIMIT: int = 8

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = await _open_game()
	if screen == null:
		_finish()
		return
	_screen = screen
	var play: PlaySession = screen.play
	_say("seed %s — %d Old World provinces, capital %s" % [
		SEED_TEXT,
		play.model.province_count(),
		play.model.province_name(play.capital_province),
	])
	var passage: int = _passage_zone(play)
	var fleet: FleetState = _board_explorer(play)
	if fleet == null or passage < 0:
		_finish()
		return
	var unit: CivilianState = _aboard_explorer(play, fleet)
	if unit == null:
		_say("no Explorer boarded — the loop cannot start")
		_finish()
		return
	_stage_passage(play, fleet, passage)
	if not _cross(play, fleet):
		_finish()
		return
	var province: int = _land(play, fleet, unit)
	if province < 0:
		_finish()
		return
	_explore(play, unit, province)
	_prospect(play, unit, province)
	_hold_check(play, province)
	_finish()


# --- the loop ---------------------------------------------------------------


func _open_game() -> MapScreen:
	return await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX)


func _passage_zone(play: PlaySession) -> int:
	for zone: SeaZoneState in play.model.sea_zones:
		var link: Dictionary = play.world.warp_partner(FactionCatalog.OLD_WORLD, int(zone.id))
		if not link.is_empty():
			return int(zone.id)
	return -1


## Boards the starting Explorer onto the home squadron at the capital.
func _board_explorer(play: PlaySession) -> FleetState:
	var fleet: FleetState = play.ship_layer.home_fleet(play.capital_province)
	if fleet == null:
		_say("no home squadron at the capital")
		return null
	for unit: CivilianState in play.civilian_layer.units:
		if unit.owner != play.player_faction or unit.type_id != "explorer":
			continue
		MapPlayCivilianVoyage.embark(play, fleet, unit.id)
		if fleet.has_civilian(unit.id):
			_say("the Explorer boards the home squadron at %s" % play.model.province_name(
				play.capital_province
			))
			return fleet
	_say("no starting Explorer at the capital")
	return null


func _aboard_explorer(play: PlaySession, fleet: FleetState) -> CivilianState:
	for unit: CivilianState in play.civilian_layer.units:
		if fleet.has_civilian(unit.id):
			return unit
	return null


## Puts the squadron in the Passage zone. The order goes through the rules
## first; a zone out of one turn's reach is seated by the harness instead.
func _stage_passage(play: PlaySession, fleet: FleetState, passage: int) -> void:
	var result: Dictionary = play.ship_layer.order(
		fleet, FleetState.Location.AT_SEA, passage
	)
	if bool(result.get("ok", false)):
		_say("the squadron sails into the Passage")
		return
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = passage
	fleet.province = MapModel.NO_ID
	_say("harness seats the squadron in the Passage (order refused: %s)" % String(
		result.get("reason", "")
	))


func _cross(play: PlaySession, fleet: FleetState) -> bool:
	var tile: Vector2i = play.model.sea_zone_data(fleet.sea_zone).tiles[0]
	play.ship_layer.select(play.ship_layer.ship_for(fleet))
	MapPlayFleets.try_order(play, tile)
	if play.region_index == FactionCatalog.OLD_WORLD:
		_say("the crossing did not happen")
		return false
	_say("the fleet crosses into the %s" % FactionCatalog.region_label(play.region_index))
	var visible: int = 0
	for index in play.visibility.levels.size():
		if play.visibility.level_at_index(index) == VisibilityModel.Level.FULLY_VISIBLE:
			visible += 1
	_say("arrival charts %d of %d tiles" % [visible, play.visibility.levels.size()])
	return true


func _land(play: PlaySession, fleet: FleetState, unit: CivilianState) -> int:
	var coasts: Array[int] = CivilianVoyage.landing_provinces(play.model, unit, fleet)
	if coasts.is_empty():
		_say("no coast is within the squadron's reach")
		return -1
	var province: int = coasts[0]
	var tile: Vector2i = CivilianVoyage.landing_tile_in(play.model, unit, fleet, province)
	var before: int = _charted(play)
	MapPlayCivilianVoyage.land(play, fleet, province)
	if unit.tile != tile:
		_say("the Explorer could not go ashore at %s" % play.model.province_name(province))
		return -1
	_say("the Explorer lands at %s (%d, %d); chart grows by %d tiles" % [
		play.model.province_name(province), tile.x, tile.y, _charted(play) - before,
	])
	return province


## Orders explore, shows the Consulate gate, opens the consulate, then runs the
## multi-turn work to completion.
func _explore(play: PlaySession, unit: CivilianState, province: int) -> void:
	play.civilian_layer.select(unit)
	MapPlayCivilians.on_action(play, "explore")
	if not unit.is_working():
		_say("explore refused: %s" % _refusal(play, unit, "explore"))
		var owner: int = play.model.province_owner(province)
		var stage: String = DiplomacyCatalog.next_stage(
			play.diplomacy.overture(play.player_faction, owner)
		)
		MapCourtOrders.apply(play, DiplomacyOrders.KIND_OVERTURE, owner, stage)
		play.civilian_layer.select(unit)
		MapPlayCivilians.on_action(play, "explore")
		if not unit.is_working():
			_say("explore still refused: %s" % _refusal(play, unit, "explore"))
			return
		_say("the %s with %s opens the survey" % [
			DiplomacyCatalog.stage_label(stage), FactionCatalog.name_of(owner),
		])
	_say("the Explorer begins charting %s (%d turns)" % [
		play.model.province_name(province), unit.remaining_turns(),
	])
	for _turn in MAX_TURNS:
		if not unit.is_working():
			break
		_end_turn(play)
		if unit.is_working():
			_say("turn %d — %d turns of survey left" % [play.turn, unit.remaining_turns()])
	_say("survey done: %s is %s" % [
		play.model.province_name(province),
		"fully charted" if play.visibility.is_province_fully_visible(province) else "still fogged",
	])


## Marches the Explorer onto the nearest mineral tile and prospects it.
func _prospect(play: PlaySession, unit: CivilianState, province: int) -> void:
	var target: Vector2i = _mineral_tile(play, province)
	if target.x < 0:
		_say("no prospectable mineral in %s" % play.model.province_name(province))
		return
	for _step in MARCH_LIMIT:
		if unit.tile == target:
			break
		var next: Vector2i = _step_toward(play, unit.tile, target)
		if next.x < 0:
			_say("no land route to the mineral tile (%d, %d)" % [target.x, target.y])
			return
		CivilianMovement.apply_move(play.model, unit, next)
		_end_turn(play)
	if unit.tile != target:
		_say("the Explorer did not reach the mineral tile")
		return
	play.civilian_layer.select(unit)
	MapPlayCivilians.on_action(play, "prospect")
	if not unit.is_working():
		_say("prospect refused: %s" % _refusal(play, unit, "prospect"))
		return
	_say("the Explorer prospects the mineral at (%d, %d)" % [target.x, target.y])
	_end_turn(play)
	_say("prospected: %s" % str(
		play.land_works.is_prospected(play.player_faction, play.model, target)
	))


# --- helpers ----------------------------------------------------------------


## The Explorer's presence holds the charted province even while the player
## reads the other map: the end-of-turn pass is per region (wiki:
## fog-and-exploration § Fog Decay).
func _hold_check(play: PlaySession, province: int) -> void:
	var visibility: VisibilityModel = play.visibility_by_region[FactionCatalog.NEW_WORLD]
	_screen._cycle_region()
	if _screen.region_index != FactionCatalog.OLD_WORLD:
		_say("could not switch back to the Old World")
		return
	_end_turn(play)
	_say("with the Old World on screen, %s stays fully charted: %s" % [
		play.world.region(FactionCatalog.NEW_WORLD).province_name(province),
		str(visibility.is_province_fully_visible(province)),
	])


func _end_turn(play: PlaySession) -> void:
	MapPlayTurn.end_turn(play)
	while DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, play.player_faction, "")


func _refusal(play: PlaySession, unit: CivilianState, action: String) -> String:
	var check: Dictionary = CivilianWork.validate(
		play.model, unit, action, play.land_works, play.civilian_layer.units,
		play.stockpile(), play.visibility, CivilianState.NO_TILE, play.tech_caps(),
		play.tech_unlocked(), {"treasury": play.treasury(), "diplomacy": play.diplomacy}
	)
	return String(check.get("reason", "no reason given"))


func _charted(play: PlaySession) -> int:
	var count: int = 0
	for index in play.visibility.levels.size():
		if play.visibility.level_at_index(index) != VisibilityModel.Level.UNKNOWN:
			count += 1
	return count


func _mineral_tile(play: PlaySession, province: int) -> Vector2i:
	for tile: Vector2i in play.model.province_tiles(province):
		var resource: int = play.model.resource_at(tile.x, tile.y)
		if ImprovementCatalog.needs_prospecting(resource):
			return tile
	return Vector2i(-1, -1)


## One orthogonal land step that shortens the walk to `target`.
func _step_toward(play: PlaySession, from: Vector2i, target: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_gap: int = absi(from.x - target.x) + absi(from.y - target.y)
	for offset: Vector2i in CivilianMovement.NEIGHBORS:
		var tile: Vector2i = from + offset
		if not play.model.is_land(tile.x, tile.y):
			continue
		var gap: int = absi(tile.x - target.x) + absi(tile.y - target.y)
		if gap < best_gap:
			best = tile
			best_gap = gap
	return best


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_new_world: %d steps ---" % _steps.size())
	quit()
