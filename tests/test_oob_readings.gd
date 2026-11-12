extends GdToolsTest
## Order-of-battle readings (wiki: fog-and-exploration § Explorer vs Spy,
## § Order Visibility Requirements; military-armies § Docket; DR-20261112-09).
##
## A court reads another court's garrison and hulls only across ground and water
## its own chart holds, so a rival plans against what it has seen — never the
## published truth of a colony it has not reached.

const AiFixture = preload("res://tests/ai_fixture.gd")

const RIVAL: int = 1
const OTHER: int = 2
## Province 0 is OTHER's colony; province 1 is RIVAL's; province 2 is unclaimed
## wilds. Sea zone 0 runs under both coasts, so RIVAL charts it at setup; zone 1
## is open water, unknown.
const FOREIGN_PROVINCE: int = 0
const OWN_PROVINCE: int = 1
const WILDS_PROVINCE: int = 2
const HOME_ZONE: int = 0
const OPEN_ZONE: int = 1


## A New World region (every tile unknown at setup) with two colonies, a strip of
## wilds and two sea zones. Six tiles wide, three tall: land on row 0, water below.
func _world() -> WorldMap:
	var model := MapModel.new()
	model.setup(6, 3)
	model.region_id = FactionCatalog.NEW_WORLD
	model.faction_ids = [RIVAL, OTHER]
	for x in 6:
		model.terrain[model.index_of(x, 0)] = MapModel.Terrain.PLAINS
	for zone in 2:
		var tiles: Array[Vector2i] = []
		for x in 6:
			var tile := Vector2i(x, zone + 1)
			tiles.append(tile)
			model.sea_zone[model.index_of(tile.x, tile.y)] = zone
		model.sea_zones.append(
			SeaZoneState.create(zone, "Z%d" % zone, tiles, Vector2.ZERO, tiles.size())
		)
	_add_province(model, FOREIGN_PROVINCE, [Vector2i(0, 0), Vector2i(1, 0)], OTHER)
	_add_province(model, OWN_PROVINCE, [Vector2i(2, 0), Vector2i(3, 0)], RIVAL)
	_add_province(
		model, WILDS_PROVINCE, [Vector2i(4, 0), Vector2i(5, 0)], MapModel.NO_ID
	)
	var world := WorldMap.new()
	world.add_region(model)
	return world


func _add_province(model: MapModel, id: int, tiles: Array[Vector2i], owner: int) -> void:
	var province := ProvinceState.create(
		id, "P%d" % id, tiles, Vector2(tiles[0].x, 0.0), tiles.size(), owner, false
	)
	for tile: Vector2i in tiles:
		model.province[model.index_of(tile.x, tile.y)] = id
	model.provinces.append(province)


## Charts cut from the world; the human court (0) keeps an empty grid here.
func _charts(world: WorldMap) -> CourtCharts:
	var charts := CourtCharts.new()
	charts.setup(world, FactionCatalog.PLAYER_FACTION, {})
	return charts


func _army(id: int, owner: int, province: int, regiments: int = 3) -> ArmyState:
	var types: Array[String] = []
	for index in regiments:
		types.append("peasant_levies")
	return ArmyState.muster(id, owner, province, false, types, 1)


## A squadron of the rival subject, `hulls` strong, in `zone` or in port.
func _sea(id: int, zone: int, hulls: int) -> FleetState:
	var names: Array[String] = []
	for index in hulls:
		names.append("hull_%d_%d" % [id, index])
	return FleetState.at_sea(id, OTHER, zone, names, {})


func _port(id: int, province: int, hulls: int) -> FleetState:
	var names: Array[String] = []
	for index in hulls:
		names.append("hull_%d_%d" % [id, index])
	return FleetState.in_port(id, OTHER, province, names, {})


func _armies(roster: Array) -> MapRegionTable:
	var table := MapRegionTable.new()
	table.set_region(0, roster)
	return table


func _fleets(roster: Array) -> MapRegionTable:
	var table := MapRegionTable.new()
	table.set_region(0, roster)
	return table


func _readings(
	charts: CourtCharts, armies: MapRegionTable, fleets: MapRegionTable
) -> Dictionary:
	return OobReadings.by_court(charts, armies, fleets, [RIVAL, OTHER])


## Nothing seen: both dockets start at zero for every court.
func test_a_charted_court_starts_out_seeing_nothing() -> void:
	var readings: Dictionary = _readings(_charts(_world()), _armies([]), _fleets([]))
	assert_eq(int(readings[RIVAL]["regiments"].get(OTHER, 0)), 0)
	assert_eq(int(readings[RIVAL]["ships"].get(OTHER, 0)), 0)
	assert_true(readings.has(OTHER), "every court carries its own docket")


## A court commands its own standard wherever it stands — even on ground its own
## chart has not reached — and no other court counts it there.
func test_a_court_always_counts_its_own_standard() -> void:
	var army: ArmyState = _army(1, RIVAL, WILDS_PROVINCE)
	var readings: Dictionary = _readings(_charts(_world()), _armies([army]), _fleets([]))
	assert_eq(int(readings[RIVAL]["regiments"][RIVAL]), 3, "its own men are its own")
	assert_eq(int(readings[RIVAL]["regiments"].get(OTHER, 0)), 0, "no foreign men seen")
	assert_eq(
		int(readings[OTHER]["regiments"].get(RIVAL, 0)), 0,
		"the wilds are unknown to the other court"
	)


## Ownership is sight: an army on a court's own ground is that court's to count
## (wiki: fog-and-exploration § New World arrival).
func test_an_army_on_owned_ground_is_seen() -> void:
	var army: ArmyState = _army(1, RIVAL, FOREIGN_PROVINCE)
	var readings: Dictionary = _readings(_charts(_world()), _armies([army]), _fleets([]))
	assert_eq(int(readings[OTHER]["regiments"][RIVAL]), 3, "its own colony shows the enemy")


## A garrison in a colony the reader has not charted is invisible; exploring the
## province reveals it (wiki: fog-and-exploration § Visibility Levels).
func test_an_uncharted_colony_hides_its_garrison() -> void:
	var charts: CourtCharts = _charts(_world())
	var army: ArmyState = _army(1, OTHER, FOREIGN_PROVINCE)
	var armies: MapRegionTable = _armies([army])
	var fleets: MapRegionTable = _fleets([])
	assert_eq(int(_readings(charts, armies, fleets)[RIVAL]["regiments"].get(OTHER, 0)), 0)
	charts.model_for(RIVAL, 0).reveal_province(FOREIGN_PROVINCE)
	assert_eq(
		int(_readings(charts, armies, fleets)[RIVAL]["regiments"][OTHER]), 3,
		"the explored province shows its garrison"
	)


## A squadron at sea is read in charted water only; open ocean stays blind until
## a ship enters it (wiki: fog-and-exploration § Distant sea zone fog).
func test_an_uncharted_sea_zone_hides_a_squadron() -> void:
	var charts: CourtCharts = _charts(_world())
	var armies: MapRegionTable = _armies([])
	var open: MapRegionTable = _fleets([_sea(1, OPEN_ZONE, 2)])
	assert_eq(int(_readings(charts, armies, open)[RIVAL]["ships"].get(OTHER, 0)), 0)
	charts.model_for(RIVAL, 0).reveal_sea_zone(OPEN_ZONE)
	assert_eq(
		int(_readings(charts, armies, open)[RIVAL]["ships"][OTHER]), 2,
		"the charted zone shows its hulls"
	)
	assert_eq(
		int(_readings(charts, armies, _fleets([_sea(2, HOME_ZONE, 1)]))[RIVAL]["ships"][OTHER]),
		1,
		"the home coast is charted from setup"
	)


## A squadron in port hides with its port; a court's own harbour is always its
## own business.
func test_a_port_hides_its_squadron_until_the_port_is_charted() -> void:
	var charts: CourtCharts = _charts(_world())
	var armies: MapRegionTable = _armies([])
	var fleets: MapRegionTable = _fleets([_port(1, FOREIGN_PROVINCE, 1)])
	assert_eq(int(_readings(charts, armies, fleets)[RIVAL]["ships"].get(OTHER, 0)), 0)
	assert_eq(
		int(_readings(charts, armies, fleets)[OTHER]["ships"][OTHER]), 1,
		"its own port is its own business"
	)
	charts.model_for(RIVAL, 0).reveal_province(FOREIGN_PROVINCE)
	assert_eq(int(_readings(charts, armies, fleets)[RIVAL]["ships"][OTHER]), 1)


## Regiments aboard a squadron are read wherever the squadron is seen.
func test_an_embarked_regiment_rides_with_its_squadron() -> void:
	var charts: CourtCharts = _charts(_world())
	var army: ArmyState = _army(1, OTHER, MapModel.NO_ID)
	army.embarked_fleet = 5
	var armies: MapRegionTable = _armies([army])
	assert_eq(
		int(_readings(charts, armies, _fleets([_sea(5, OPEN_ZONE, 1)]))[RIVAL]["regiments"]
			.get(OTHER, 0)),
		0,
		"the squadron is in open water"
	)
	assert_eq(
		int(_readings(charts, armies, _fleets([_sea(5, HOME_ZONE, 1)]))[RIVAL]["regiments"][OTHER]),
		3,
		"the charted water shows the transport and its men"
	)


## A court with no chart at all (a fixture, or a world never charted) reads the
## published docket, exactly as CourtCharts documents for its own lookups.
func test_a_court_without_a_chart_reads_the_published_docket() -> void:
	var army: ArmyState = _army(1, OTHER, FOREIGN_PROVINCE)
	var readings: Dictionary = _readings(
		null, _armies([army]), _fleets([_sea(1, OPEN_ZONE, 1)])
	)
	assert_eq(int(readings[RIVAL]["regiments"][OTHER]), 3)
	assert_eq(int(readings[RIVAL]["ships"][OTHER]), 1)


## The turn pass hands each rival its own charted docket, so war desire is
## scored against what that court has seen (DR-20261112-09).
func test_the_turn_reads_each_court_its_own_reading() -> void:
	var world: WorldMap = AiFixture.world([2, 2, 1])
	var published: Dictionary = _turn(world, {
		"regiments": {RIVAL: 10, OTHER: 40}, "ships": {},
	})
	var charted: Dictionary = _turn(world, {
		"regiments": {RIVAL: 10, OTHER: 40},
		"ships": {},
		"readings": {
			RIVAL: {"regiments": {RIVAL: 10}, "ships": {}},
			OTHER: {"regiments": {OTHER: 40}, "ships": {}},
		},
	})
	assert_eq(
		_factor(published, RIVAL, OTHER, "relative_power"), -25,
		"the published docket reads the other court as far stronger"
	)
	assert_eq(
		_factor(charted, RIVAL, OTHER, "relative_power"), 5,
		"the reading has seen no garrison across the water, so the court looks even"
	)
	assert_eq(
		_factor(charted, OTHER, RIVAL, "relative_power"), 30,
		"the court holding the 40 regiments still reads itself strong"
	)


## The session adapter builds those readings from the charts and the layers; a
## session without them hands the caller nothing and keeps the published docket.
func test_the_map_phase_reads_the_charts_and_the_layers() -> void:
	assert_true(
		MapPlayCourtFog.oob_readings(PlaySession.new()).is_empty(),
		"no charts, no readings"
	)
	var play := PlaySession.new()
	play.world = _world()
	play.player_faction = FactionCatalog.PLAYER_FACTION
	play.court_charts = _charts(play.world)
	assert_true(
		MapPlayCourtFog.oob_readings(play).is_empty(), "charts but no layers, no readings"
	)
	var armies := ArmyLayer.new()
	add_child(armies)
	var roster: Array[ArmyState] = [_army(1, OTHER, FOREIGN_PROVINCE)]
	armies.regions.set_region(0, roster)
	var ships := ShipLayer.new()
	add_child(ships)
	play.army_layer = armies
	play.ship_layer = ships
	var readings: Dictionary = MapPlayCourtFog.oob_readings(play)
	assert_eq(
		int(readings[RIVAL]["regiments"].get(OTHER, 0)), 0,
		"the colony is uncharted"
	)
	assert_eq(int(readings[OTHER]["regiments"][OTHER]), 3, "its own men are its own")


## The diplomacy phase hands the turn its readings: a rival that has not charted
## its neighbour's colony plans against a smaller court than it really is.
func test_the_diplomacy_phase_scores_the_reading() -> void:
	var play := PlaySession.new()
	play.world = _world()
	play.player_faction = FactionCatalog.PLAYER_FACTION
	play.court_charts = _charts(play.world)
	play.map_seed = 1500
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(RIVAL)
	play.diplomacy.ensure_relation(RIVAL, OTHER, 1)
	var armies := ArmyLayer.new()
	add_child(armies)
	var roster: Array[ArmyState] = [_army(1, OTHER, FOREIGN_PROVINCE)]
	armies.regions.set_region(0, roster)
	var ships := ShipLayer.new()
	add_child(ships)
	play.army_layer = armies
	play.ship_layer = ships
	MapPlayDiplomacyAi.run(play)
	assert_eq(play.ai_trace.size(), 5, "every rival court took its turn")
	assert_eq(
		_factor({"trace": play.ai_trace}, RIVAL, OTHER, "relative_power"), 5,
		"a garrison across uncharted water is not counted against the attack"
	)


# --- helpers -----------------------------------------------------------------


func _turn(world: WorldMap, context: Dictionary) -> Dictionary:
	var state := DiplomacyState.new()
	state.reset(RIVAL)
	state.ensure_relation(RIVAL, OTHER, 1)
	return AiTurn.run(
		state, world, AiState.new(), 1, FactionCatalog.PLAYER_FACTION, 1500, context
	)


## One candidate's war-desire factor for a (court, target) pair.
func _factor(run: Dictionary, faction: int, target: int, key: String) -> int:
	for record: Dictionary in run["trace"]:
		if int(record["faction"]) != faction:
			continue
		for entry: Dictionary in record["candidates"]:
			if int(entry["target"]) == target:
				return int((entry["factors"] as Dictionary).get(key, 0))
	return -999
