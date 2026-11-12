extends GdToolsTest
## The live setup path of an advanced start (wiki: advanced-starts; DR-20261111-01):
## a real map screen opening at a mid-age tier, with the treasury, the muster,
## the chart and the roster the tier promises.
##
## Split from test_advanced_start so the two expensive screen mounts do not hold
## the ten cheap rule cases inside one suite process (the reason test_map_screen
## was split from test_map_screen_crown_orders). The shared two-region fixture is
## reused as-is: the late tier's roster needs the full chart, so shrinking it
## would quietly drop a Rail Builder.

const Fixture = preload("res://tests/map_fixture.gd")
const NEW_WORLD: int = 1

var world: WorldMap = null


func before_all() -> void:
	world = Fixture.world()


func after_all() -> void:
	world = null


func test_a_new_campaign_opens_on_the_preset() -> void:
	var screen: MapScreen = _open(AdvancedStart.TURNS50)
	var play: PlaySession = screen.play
	assert_eq(play.turn, 50, "the age opens at turn 50")
	assert_eq(TurnTime.year_for_turn(play.turn), 1598)
	assert_eq(play.advanced_start, AdvancedStart.TURNS50)
	assert_eq(play.treasury(), 20000, "the tier purse")
	assert_eq(play.economy.economy.workers.count(WorkerPool.Tier.PEASANT), 16)
	assert_eq(play.economy.economy.research.unlocked_ids().size(), 23)
	assert_gte(
		play.economy.economy.quantity("grain"), 16 * PlayerEconomy.START_GRAIN_TURNS,
		"the tier workforce is fed from the first turn"
	)
	assert_true(play.visibility_by_region.has(NEW_WORLD), "the inherited chart exists")
	var home: ArmyState = _home_army(screen, play.player_faction)
	assert_not_null(home)
	assert_eq(home.count(), 11, "five opening regiments plus the tier's six")
	assert_gte(_home_galleons(screen, play.player_faction), 1, "a Galleon waits in port")
	var roster: Array = screen.civilian_layer.regions.value(0, [])
	assert_eq(_civilian_count(roster, play.player_faction, "explorer"), 3)
	assert_eq(_civilian_count(roster, play.player_faction, "spy"), 1)
	screen.free()


func test_a_late_campaign_opens_with_the_documented_progress() -> void:
	var screen: MapScreen = _open(AdvancedStart.TURNS100)
	var play: PlaySession = screen.play
	assert_eq(play.turn, 100, "the age opens at turn 100")
	assert_eq(TurnTime.year_for_turn(play.turn), 1698)
	assert_eq(play.treasury(), 40000)
	assert_eq(
		play.hud._treasury_label.text, TextFormat.thousands(play.treasury()),
		"the top bar reads the tier purse, not the turn-0 ledger it opened on",
	)
	assert_eq(
		play.hud._income_label.text, TextFormat.delta(play.income),
		"the per-turn figure follows the tier ledger too",
	)
	assert_eq(play.economy.economy.workers.count(WorkerPool.Tier.APPRENTICE), 4)
	assert_eq(play.economy.economy.research.unlocked_ids().size(), 45)
	assert_gte(_home_galleons(screen, play.player_faction), 6, "the late tier sails a convoy")
	var home: ArmyState = _home_army(screen, play.player_faction)
	assert_not_null(home)
	assert_eq(home.count(), 17, "five opening regiments plus the tier's twelve")
	var roster: Array = screen.civilian_layer.regions.value(0, [])
	assert_gte(
		_civilian_count(roster, play.player_faction, "rail_builder"), 1,
		"the late tier fields a Rail Builder"
	)
	screen.free()


## Every court inherits the same New World chart (wiki § NW sea-zone visibility
## is per Great Power): a rival reads the Passage lanes its own grid holds, so
## its voyages are not blind to water the player was given.
func test_rivals_inherit_the_passage_lanes() -> void:
	var screen: MapScreen = _open(AdvancedStart.TURNS50)
	var play: PlaySession = screen.play
	var human: int = play.player_faction
	var human_zones: Array[int] = play.court_charts.known_zones(human, NEW_WORLD)
	assert_false(human_zones.is_empty(), "the crown inherits the Passage lanes")
	for faction: int in FactionCatalog.great_power_ids():
		if faction == human:
			continue
		var view: VisibilityModel = play.court_charts.model_for(faction, NEW_WORLD)
		assert_not_null(view, "a rival holds a New World chart")
		assert_eq(view.player_id, faction, "each court reads its own grid")
		var rival_zones: Array[int] = play.court_charts.known_zones(faction, NEW_WORLD)
		assert_eq(rival_zones, human_zones, "every court reads the same lanes")
	screen.free()


## A rival reads its own colony beach (100-turn claim): owned shore, fully
## visible water, through the court's own grid rather than the player's.
func test_a_rival_reads_its_own_colony_coast() -> void:
	var screen: MapScreen = _open(AdvancedStart.TURNS100)
	var play: PlaySession = screen.play
	var model: MapModel = play.world.region(NEW_WORLD)
	for faction: int in FactionCatalog.great_power_ids():
		var view: VisibilityModel = play.court_charts.model_for(faction, NEW_WORLD)
		assert_not_null(view)
		var held: int = 0
		for province: ProvinceState in model.provinces:
			if province.owner != faction:
				continue
			held += 1
			assert_true(
				view.is_province_fully_visible(province.id),
				"a crown reads its own colony"
			)
		assert_gte(held, 1, "the late tier seats every crown in the New World")
	screen.free()


func _open(tier: String) -> MapScreen:
	var screen: MapScreen = Fixture.SCENE.instantiate()
	screen.map_width = Fixture.WORLD_WIDTH
	screen.map_height = Fixture.WORLD_HEIGHT
	screen.preset_world = world
	screen.advanced_start = tier
	add_child(screen)
	return screen


func _home_army(screen: MapScreen, faction: int) -> ArmyState:
	for raw: Variant in screen.army_layer.regions.value(0, []):
		var army: ArmyState = raw as ArmyState
		if army != null and army.owner == faction and army.is_home_army():
			return army
	return null


func _home_galleons(screen: MapScreen, faction: int) -> int:
	var count: int = 0
	for raw: Variant in screen.ship_layer.regions.value(0, []):
		var fleet: FleetState = raw as FleetState
		if fleet == null or fleet.owner != faction:
			continue
		for hull: String in fleet.hulls:
			if fleet.type_of(hull) == "galleon":
				count += 1
	return count


func _civilian_count(roster: Array, faction: int, type_id: String) -> int:
	var count: int = 0
	for raw: Variant in roster:
		var unit: CivilianState = raw as CivilianState
		if unit != null and unit.owner == faction and unit.type_id == type_id:
			count += 1
	return count
