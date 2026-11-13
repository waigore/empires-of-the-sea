extends GdToolsTest
## One boot for the crown's turn: civilian voyages, deed protection, warp travel,
## the crown road survey and the capital choice.

## Merged from test_civilian_voyage, test_deed_protection, test_warp_travel,
## test_crown_road_survey, test_capital_choice.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const NavalFixture = preload("res://tests/naval_fixture.gd")
const _Fixture = preload("res://tests/civilian_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")

const MINOR: int = 6
const BUYER: int = 1
const crown_road_survey_WIDTH: int = 9
const crown_road_survey_HEIGHT: int = 4
const CAPITAL: Vector2i = Vector2i(0, 1)
const TOWN_CUT: Vector2i = Vector2i(4, 1)
const TOWN_PORT: Vector2i = Vector2i(7, 2)
const PLAYER: int = FactionCatalog.PLAYER_FACTION
const RIVAL: int = 3
const capital_choice_WIDTH: int = 12
const capital_choice_HEIGHT: int = 9

var _model: MapModel = null
var world_map: WorldMap = null
var _crown_road_survey_model: MapModel = null
var _works: LandWorks = null

var _suite_setup: String = ""

func before_all() -> void:
	_hook_warp_travel_before_all()

func _hook_warp_travel_before_all() -> void:
	world_map = Fixture.world()

func _setup_civilian_voyage() -> void:
	_suite_setup = "civilian_voyage"
	_model = NavalFixture.build()

func _setup_crown_road_survey() -> void:
	_suite_setup = "crown_road_survey"
	_crown_road_survey_model = _build()
	_works = LandWorks.new()

# --- test_civilian_voyage ---

func _fleet() -> FleetState:
	return FleetState.in_port(
		1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"}
	)

func _unit(type_id: String = "builder", tile: Vector2i = Vector2i(0, 0)) -> CivilianState:
	return CivilianState.create(7, 0, type_id, tile)

func test_one_hull_carries_one_civilian() -> void:
	_setup_civilian_voyage()
	assert_eq(CivilianVoyage.capacity(_fleet()), 2)
	assert_eq(CivilianVoyage.capacity(null), 0)

func test_a_civilian_boards_a_squadron_in_its_port() -> void:
	_setup_civilian_voyage()
	var fleet: FleetState = _fleet()
	var unit: CivilianState = _unit()
	var result: Dictionary = CivilianVoyage.embark(_model, unit, fleet)

	assert_true(bool(result["ok"]))
	assert_true(unit.is_embarked())
	assert_eq(unit.embarked_fleet, fleet.id)
	assert_eq(unit.tile, CivilianState.NO_TILE)
	assert_true(unit.moved)
	assert_true(fleet.has_civilian(unit.id))
	assert_eq(fleet.civilian_count(), 1)

func test_boarding_refusals_name_the_missing_condition() -> void:
	_setup_civilian_voyage()
	var fleet: FleetState = _fleet()

	assert_true(String(CivilianVoyage.embark(_model, null, fleet)["reason"]).contains("no civilian"))
	assert_true(String(CivilianVoyage.embark(_model, _unit(), null)["reason"]).contains("No squadron"))

	var foreign: CivilianState = CivilianState.create(8, 1, "builder", Vector2i(0, 0))
	assert_true(String(CivilianVoyage.embark(_model, foreign, fleet)["reason"]).contains("Own colours"))

	var busy: CivilianState = _unit()
	busy.start_work("build_improvement", Vector2i(0, 0), 1)
	assert_true(String(CivilianVoyage.embark(_model, busy, fleet)["reason"]).contains("busy working"))

	var marched: CivilianState = _unit()
	marched.moved = true
	assert_true(String(CivilianVoyage.embark(_model, marched, fleet)["reason"]).contains("already moved"))

	var at_sea: FleetState = FleetState.at_sea(2, 0, 0, ["c"], {"c": "fluyte"})
	assert_true(String(CivilianVoyage.embark(_model, _unit(), at_sea)["reason"]).contains("in port"))

	var sailed: FleetState = _fleet()
	sailed.moved = true
	assert_true(String(CivilianVoyage.embark(_model, _unit(), sailed)["reason"]).contains("already sailed"))

	var elsewhere: CivilianState = _unit("builder", Vector2i(5, 0))
	assert_true(String(CivilianVoyage.embark(_model, elsewhere, fleet)["reason"]).contains("not in this port"))

func test_a_squadron_carrying_an_army_takes_no_colonists() -> void:
	_setup_civilian_voyage()
	var fleet: FleetState = _fleet()
	fleet.embarked_army = 3
	var result: Dictionary = CivilianVoyage.embark(_model, _unit(), fleet)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("carries troops"))

func test_the_passenger_list_cannot_exceed_the_hulls() -> void:
	_setup_civilian_voyage()
	var fleet: FleetState = FleetState.in_port(2, 0, 0, ["a"], {"a": "fluyte"})
	var first: CivilianState = CivilianState.create(7, 0, "builder", Vector2i(0, 0))
	var second: CivilianState = CivilianState.create(8, 0, "explorer", Vector2i(1, 0))

	assert_true(bool(CivilianVoyage.embark(_model, first, fleet)["ok"]))
	var refused: Dictionary = CivilianVoyage.embark(_model, second, fleet)

	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("1 hull"))
	assert_eq(fleet.civilian_count(), 1)

func test_the_port_province_is_the_landing_ground() -> void:
	_setup_civilian_voyage()
	var fleet: FleetState = _fleet()
	var unit: CivilianState = _unit()
	CivilianVoyage.embark(_model, unit, fleet)

	var tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(_model, unit, fleet)

	assert_true(tiles.has(Vector2i(0, 0)))
	assert_true(tiles.has(Vector2i(1, 0)))
	assert_true(tiles.has(Vector2i(0, 1)))
	assert_false(tiles.has(Vector2i(5, 0)), "another province is not this port")
	assert_eq(CivilianVoyage.landing_provinces(_model, unit, fleet), [0])
	assert_eq(
		CivilianVoyage.landing_tile_in(_model, unit, fleet, 0),
		Vector2i(0, 0)
	)

func test_a_squadron_at_sea_lands_on_the_bordering_coast() -> void:
	_setup_civilian_voyage()
	var fleet: FleetState = FleetState.at_sea(2, 0, 0, ["c"], {"c": "fluyte"})
	var explorer: CivilianState = _unit("explorer", Vector2i(0, 0))
	explorer.embarked_fleet = fleet.id
	fleet.add_civilian(explorer.id)

	var tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(_model, explorer, fleet)

	assert_true(tiles.has(Vector2i(1, 0)), "coast beside the zone")
	assert_true(tiles.has(Vector2i(0, 1)))
	assert_false(tiles.has(Vector2i(0, 0)), "inland tiles stay out of reach")
	assert_false(tiles.has(Vector2i(5, 1)), "the far zone is not this coast")

func test_a_builder_needs_crown_land_where_an_explorer_may_land_anywhere() -> void:
	_setup_civilian_voyage()
	var fleet: FleetState = FleetState.at_sea(2, 1, 1, ["c"], {"c": "fluyte"})
	var builder: CivilianState = _unit("builder", Vector2i(0, 0))
	builder.embarked_fleet = fleet.id
	fleet.add_civilian(builder.id)
	var explorer: CivilianState = _unit("explorer", Vector2i(0, 0))
	explorer.embarked_fleet = fleet.id
	fleet.add_civilian(explorer.id)

	var builder_tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(
		_model, builder, fleet
	)
	assert_false(builder_tiles.has(Vector2i(5, 1)), "a rival coast refuses a builder")
	var explorer_tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(
		_model, explorer, fleet
	)
	assert_true(explorer_tiles.has(Vector2i(5, 1)), "an explorer surveys any coast")

func test_going_ashore_spends_the_move_and_frees_the_hull() -> void:
	_setup_civilian_voyage()
	var fleet: FleetState = _fleet()
	var unit: CivilianState = _unit()
	CivilianVoyage.embark(_model, unit, fleet)

	var result: Dictionary = CivilianVoyage.disembark(
		_model, unit, fleet, Vector2i(0, 1)
	)

	assert_true(bool(result["ok"]))
	assert_false(unit.is_embarked())
	assert_eq(unit.tile, Vector2i(0, 1))
	assert_true(unit.moved)
	assert_false(fleet.has_civilian(unit.id))
	assert_eq(CivilianVoyage.disembark(
		_model, unit, fleet, Vector2i(0, 1)
	)["ok"], false)

func test_a_landing_reveals_the_tile_and_its_orthogonal_neighbours() -> void:
	_setup_civilian_voyage()
	var view := VisibilityModel.new()
	view.setup(_model, 0)
	view.levels.fill(VisibilityModel.Level.UNKNOWN)

	var changed: Array = view.reveal_landing(Vector2i(1, 0))

	assert_eq(view.level_at(1, 0), VisibilityModel.Level.FULLY_VISIBLE)
	for tile: Vector2i in [
		Vector2i(2, 0), Vector2i(0, 0), Vector2i(1, 1)
	]:
		assert_eq(
			view.level_at(tile.x, tile.y),
			VisibilityModel.Level.FULLY_VISIBLE,
			str(tile)
		)
	assert_eq(
		view.level_at(0, 1), VisibilityModel.Level.UNKNOWN, "diagonals stay dark"
	)
	assert_eq(changed.size(), 4)
	assert_eq(view.reveal_landing(Vector2i(-1, -1)), [] as Array)

func test_passengers_survive_a_save_round_trip() -> void:
	_setup_civilian_voyage()
	var fleet: FleetState = _fleet()
	var unit: CivilianState = _unit()
	CivilianVoyage.embark(_model, unit, fleet)

	var restored_fleet: FleetState = FleetState.from_dict(fleet.to_dict())
	var restored_unit: CivilianState = CivilianState.from_dict(unit.to_dict())

	assert_eq(restored_fleet.embarked_civilians, [7])
	assert_true(restored_fleet.has_civilian(7))
	assert_true(restored_unit.is_embarked())
	assert_eq(restored_unit.embarked_fleet, fleet.id)

func test_the_roster_entry_follows_the_squadron_across_regions() -> void:
	_setup_civilian_voyage()
	var layer := CivilianLayer.new()
	layer.model = _model
	var unit: CivilianState = _unit()
	layer.units = [unit]
	layer.regions.set_region(0, layer.units)
	layer.regions.set_region(1, [] as Array[CivilianState])

	CivilianVoyageMap.move_to_region(layer, unit.id, 1)

	assert_eq(layer.units.size(), 0)
	var destination: Array = layer.regions.value(1, [])
	assert_true(destination.has(unit))
	assert_eq(CivilianVoyageMap.region_of(layer, unit), 1)
	assert_eq(CivilianVoyageMap.by_id(layer, unit.id), unit)
	assert_eq(CivilianVoyageMap.by_id(layer, 99), null)
	layer.free()

func test_a_sunken_squadron_drowns_its_passengers() -> void:
	_setup_civilian_voyage()
	var layer := CivilianLayer.new()
	layer.model = _model
	var safe: CivilianState = _unit()
	safe.embarked_fleet = 5
	var lost: CivilianState = CivilianState.create(8, 0, "explorer", CivilianState.NO_TILE)
	lost.embarked_fleet = 6
	layer.units = [safe, lost]
	layer.regions.set_region(0, layer.units)

	var dropped: Array[CivilianState] = CivilianVoyageMap.drop_lost(layer, {7: 5})

	assert_eq(dropped.size(), 1)
	assert_eq(dropped[0], lost)
	assert_eq(layer.units.size(), 1)
	assert_true(layer.units.has(safe))
	layer.free()

## A crossing renumbers the squadron and a docking merge folds it into the home
## fleet; either way the passenger's seat follows the roster that lists it.
func test_a_passenger_follows_a_renumbered_or_merged_seat() -> void:
	_setup_civilian_voyage()
	var layer := CivilianLayer.new()
	layer.model = _model
	var moved: CivilianState = _unit()
	moved.embarked_fleet = 2
	var merged: CivilianState = CivilianState.create(8, 0, "explorer", CivilianState.NO_TILE)
	merged.embarked_fleet = 3
	layer.units = [moved, merged]
	layer.regions.set_region(0, layer.units)

	var dropped: Array[CivilianState] = CivilianVoyageMap.drop_lost(
		layer, {moved.id: 9, merged.id: 4}
	)

	assert_eq(dropped, [] as Array[CivilianState])
	assert_eq(moved.embarked_fleet, 9, "the crossed squadron's new id is adopted")
	assert_eq(merged.embarked_fleet, 4, "the home fleet's id is adopted")
	assert_eq(layer.units.size(), 2)
	layer.free()

# --- test_deed_protection ---

func test_a_deed_inside_the_victims_provinces_counts_for_its_buyer() -> void:
	var world: WorldMap = _minor_world()
	assert_eq(DeedProtection.deed_count(world, BUYER, MINOR), 1)
	assert_eq(DeedProtection.deed_count(world, 2, MINOR), 0, "another crown holds nothing")
	assert_true(DeedProtection.holds_deed(world, BUYER, MINOR))
	assert_eq(DeedProtection.holders(world, MINOR), [BUYER] as Array[int])

func test_the_stake_is_what_the_deed_would_cost_to_buy_again() -> void:
	var world: WorldMap = _minor_world()
	var model: MapModel = world.region(0)
	var tile: Vector2i = _first_deed(model, BUYER, MINOR)
	assert_eq(
		DeedProtection.stake_value(world, BUYER, MINOR),
		LandPurchase.cost(model, tile),
		"15 x the resource's base price, the merchant's own price"
	)

func test_a_province_the_victim_lost_takes_the_stake_with_it() -> void:
	var world: WorldMap = _minor_world()
	world.region(0).provinces[1].owner = 7
	assert_eq(DeedProtection.deed_count(world, BUYER, MINOR), 0)
	assert_false(DeedProtection.holds_deed(world, BUYER, MINOR))

func test_one_deed_is_worth_protecting_and_two_are_serious() -> void:
	var world: WorldMap = _minor_world()
	assert_true(DeedProtection.worth_protecting(world, BUYER, MINOR))
	assert_false(DeedProtection.serious_stake(world, BUYER, MINOR))
	var model: MapModel = world.region(0)
	assert_true(model.purchase_tile(Vector2i(2, 1), BUYER), "a second deed is signed")
	assert_eq(DeedProtection.deed_count(world, BUYER, MINOR), 2)
	assert_true(DeedProtection.serious_stake(world, BUYER, MINOR))
	assert_eq(DeedProtection.holding_text(world, BUYER, MINOR), "2 deeds")

func test_a_crown_with_no_deed_has_no_stake() -> void:
	var world: WorldMap = _minor_world()
	assert_false(DeedProtection.worth_protecting(world, 3, MINOR))
	assert_eq(DeedProtection.stake_value(world, 3, MINOR), 0)
	assert_eq(DeedProtection.holding_text(world, 3, MINOR), "")

## A declaration of war does not tear a deed up: the province owner changes
## relations, never the tile's buyer (wiki: diplomacy § Intervention § Do Nothing
## — "purchased land remains recorded until normal province conquest rules
## apply").
func test_a_war_with_the_seller_leaves_the_deed_standing() -> void:
	var world: WorldMap = _minor_world()
	var model: MapModel = world.region(0)
	var tile: Vector2i = _first_deed(model, BUYER, MINOR)
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(BUYER, MINOR, 1)
	assert_true(
		bool(DiplomacyRules.declare_war(state, BUYER, MINOR, true, world).get("ok", false))
	)
	assert_true(model.is_purchased_tile(tile), "the deed survives the declaration")
	assert_eq(model.owner_at(tile.x, tile.y), BUYER)
	assert_eq(DeedProtection.deed_count(world, BUYER, MINOR), 1)

## A crown deciding to attack a protected Minor is told who would answer before
## it commits (REQ-P5-03, REQ-P5-05; DR-20261110-20).
func test_the_court_names_who_would_answer_a_war_on_the_minor() -> void:
	var world: WorldMap = _minor_world()
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(0, MINOR, 1)
	state.ensure_relation(3, MINOR, 1)
	state.set_overture(3, MINOR, DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(
		InterventionCopy.warden_hint(state, world, 0, MINOR),
		"England and Portugal may intervene."
	)
	state.set_overture(3, MINOR, DiplomacyCatalog.STAGE_NONE)
	assert_eq(InterventionCopy.warden_hint(state, world, 0, MINOR), "England may intervene.")

func test_three_wardens_read_as_a_list() -> void:
	var world: WorldMap = _minor_world()
	var model: MapModel = world.region(0)
	assert_true(model.ownership.purchase(model.index_of(2, 1), 2), "a second holder")
	assert_true(model.ownership.purchase(model.index_of(2, 2), 4), "a third holder")
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(0, MINOR, 1)
	assert_eq(
		InterventionCopy.warden_hint(state, world, 0, MINOR),
		"England, France and United Provinces may intervene."
	)

func test_an_unprotected_minor_names_no_warden() -> void:
	var world: WorldMap = _minor_world()
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(0, MINOR, 1)
	world.region(0).ownership.clear()
	assert_eq(InterventionCopy.warden_hint(state, world, 0, MINOR), "")

## Small map where Minor Nation 6 owns province 1 and `BUYER` holds one deed in
## it (the fixture's grain tile).
func _minor_world() -> WorldMap:
	var model: MapModel = _Fixture.build_minor()
	assert_true(model.purchase_tile(Vector2i(3, 1), BUYER), "a deed is signed")
	var world := WorldMap.new()
	world.add_region(model)
	return world

func _first_deed(model: MapModel, buyer: int, target: int) -> Vector2i:
	for province: ProvinceState in model.provinces:
		if province.owner != target:
			continue
		for tile: Vector2i in province.tiles:
			if model.ownership.purchaser(model.index_of(tile.x, tile.y)) == buyer:
				return tile
	return Vector2i(-1, -1)

# --- test_warp_travel ---

func test_a_warp_zone_links_to_one_zone_on_the_other_map() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(1, 0, zone)

	var check: Dictionary = WarpTravel.can_cross(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_true(bool(check["ok"]))
	assert_eq(int(check["to_region"]), FactionCatalog.NEW_WORLD)
	assert_eq(
		int(check["to_zone"]),
		int(world_map.warp_partner(FactionCatalog.OLD_WORLD, zone)["to_zone"])
	)
	assert_true(world_map.is_warp_zone(int(check["to_region"]), int(check["to_zone"])))

func test_crossing_moves_the_fleet_into_the_paired_zone() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(2, 0, zone, ["ship_2"], {"ship_2": "sloop"})

	var result: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_true(bool(result["ok"]))
	assert_eq(int(result["from_zone"]), zone)
	assert_eq(int(result["from_region"]), FactionCatalog.OLD_WORLD)
	assert_eq(int(result["to_region"]), FactionCatalog.NEW_WORLD)
	assert_eq(fleet.sea_zone, int(result["to_zone"]))
	assert_eq(fleet.location, FleetState.Location.AT_SEA)
	assert_eq(fleet.province, MapModel.NO_ID)
	assert_true(fleet.moved)
	# Hulls cross intact, instance ids and types unchanged.
	assert_eq(fleet.ship_count(), 1)
	assert_eq(fleet.type_of("ship_2"), "sloop")

func test_a_crossing_can_be_made_back_the_other_way() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(3, 0, zone)
	var there: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)
	assert_true(bool(there["ok"]))
	fleet.moved = false

	var back: Dictionary = WarpTravel.apply_crossing(
		world_map, int(there["to_region"]), fleet
	)

	assert_true(bool(back["ok"]))
	assert_eq(int(back["to_region"]), FactionCatalog.OLD_WORLD)
	assert_true(world_map.is_warp_zone(FactionCatalog.OLD_WORLD, fleet.sea_zone))

## A crossing is the squadron's sail, so the station and the landing site are
## given up; province ids are region-local, so a marker carried across would
## name an unrelated coast on the other map (wiki: ships-and-naval § Missions
## and Movement — a mission persists until the squadron sails; § Naval transport
## — the beachhead marker is lost if the squadron sails).
func test_a_crossing_gives_up_the_station_and_the_landing_site() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var blockading := FleetState.at_sea(7, 0, zone)
	blockading.mission = FleetState.Mission.BLOCKADE
	blockading.blockade_province = 4
	blockading.beachhead_province = 4
	blockading.beachhead_turn = 3
	var landing := FleetState.at_sea(8, 0, zone)
	landing.mission = FleetState.Mission.BEACHHEAD
	landing.beachhead_province = 5
	landing.beachhead_turn = 3

	assert_true(bool(WarpTravel.apply_crossing(world_map, FactionCatalog.OLD_WORLD, blockading)["ok"]))
	assert_true(bool(WarpTravel.apply_crossing(world_map, FactionCatalog.OLD_WORLD, landing)["ok"]))

	assert_eq(blockading.mission, FleetState.Mission.NONE)
	assert_eq(blockading.blockade_province, MapModel.NO_ID, "the blockade coast does not cross")
	assert_false(blockading.has_beachhead(), "the landing site does not cross")
	assert_eq(blockading.beachhead_turn, -1)
	assert_eq(landing.mission, FleetState.Mission.NONE, "the beachhead mission is given up")
	assert_false(landing.has_beachhead())

func test_a_moved_fleet_cannot_cross() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(4, 0, zone)
	fleet.moved = true

	var result: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("already moved"))
	assert_eq(fleet.sea_zone, zone)

func test_a_fleet_in_port_cannot_cross() -> void:
	var province: int = int(world_map.region(FactionCatalog.OLD_WORLD).provinces[0].id)
	var fleet := FleetState.in_port(5, 0, province)

	var result: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("at sea"))
	assert_eq(fleet.location, FleetState.Location.IN_PORT)

func test_open_water_has_no_passage() -> void:
	var model: MapModel = world_map.region(FactionCatalog.OLD_WORLD)
	var zone: int = -1
	for data: SeaZoneState in model.sea_zones:
		if not world_map.is_warp_zone(FactionCatalog.OLD_WORLD, int(data.id)):
			zone = int(data.id)
			break
	assert_gt(zone, -1, "the Old World has ordinary water")
	var fleet := FleetState.at_sea(6, 0, zone)

	var check: Dictionary = WarpTravel.can_cross(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("passage"))
	assert_false(fleet.moved)

# --- test_crown_road_survey ---

## Three crowns' worth of ground, all held by the player: a capital province in
## the west, a province whose town stands four tiles from the capital, and a
## province whose town is a landfall port (Town rule, so town development caps
## the yield of its neighbours).
func _build() -> MapModel:
	var model := MapModel.new()
	model.setup(crown_road_survey_WIDTH, crown_road_survey_HEIGHT)
	var groups: Dictionary = {0: [], 1: [], 2: []}
	for y in crown_road_survey_HEIGHT - 1:
		for x in crown_road_survey_WIDTH:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			var province_id: int = 0 if x < 3 else (1 if x < 6 else 2)
			model.province[model.index_of(x, y)] = province_id
			(groups[province_id] as Array).append(Vector2i(x, y))
	for x in crown_road_survey_WIDTH:
		model.terrain[model.index_of(x, crown_road_survey_HEIGHT - 1)] = MapModel.Terrain.OCEAN
		model.sea_zone[model.index_of(x, crown_road_survey_HEIGHT - 1)] = 0
	var names: Array[String] = ["Sevilla", "Córdoba", "Granada"]
	var provinces: Array[ProvinceState] = []
	for province_id in 3:
		var tiles: Array[Vector2i] = []
		for raw: Variant in groups[province_id]:
			tiles.append(raw as Vector2i)
		var province := ProvinceState.create(
			province_id, names[province_id], tiles, Vector2(1.0, 1.0),
			tiles.size(), PLAYER, province_id == 0
		)
		provinces.append(province)
	provinces[0].capital_tile = CAPITAL
	provinces[0].town_tile = CAPITAL
	provinces[1].town_tile = TOWN_CUT
	provinces[2].town_tile = TOWN_PORT
	provinces[2].town_development = 2
	model.provinces = provinces
	return model

func _snapshot() -> Dictionary:
	return CrownRoadSurvey.snapshot(_crown_road_survey_model, _works, PLAYER, CAPITAL)

func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}

func _route(survey: Dictionary, province_id: int) -> Array:
	for raw: Variant in survey.get("routes", []):
		var route: Dictionary = raw
		if int(route["province"]) == province_id:
			return route.get("tiles", [])
	return []

func test_capital_network_reads_as_road() -> void:
	_setup_crown_road_survey()
	var survey: Dictionary = _snapshot()
	var states: Dictionary = _states(survey)
	assert_eq(String(states.get(_crown_road_survey_model.index_of(0, 1), "")), CrownRoadSurvey.STATE_ROAD)
	# A tile beside the capital network extracts at its cap, so it reads road too.
	assert_eq(String(states.get(_crown_road_survey_model.index_of(1, 1), "")), CrownRoadSurvey.STATE_ROAD)
	assert_gt(int(survey["tiles"][CrownRoadSurvey.STATE_ROAD]), 0)

func test_cut_province_reports_the_road_still_to_lay() -> void:
	_setup_crown_road_survey()
	var survey: Dictionary = _snapshot()
	var entry: Dictionary = _entry(survey, 1)
	assert_eq(String(entry["state"]), CrownRoadSurvey.STATE_CUT)
	assert_false(bool(entry["linked"]))
	# The town stands four tiles from the capital: three road tiles short.
	assert_eq(int(entry["gap"]), 3)
	# The port province is cut too, seven tiles out: the summary counts both.
	assert_eq(int(survey["counts"]["gap"]), 10)
	assert_eq(int(survey["counts"]["cut"]), 2)
	var route: Array = _route(survey, 1)
	assert_eq(route.size(), 3, "the route is one tile per road still to lay")
	assert_eq(route[0], Vector2i(1, 1))
	assert_eq(route[2], Vector2i(3, 1))
	# The town itself is never laid: it extracts once it stands beside the road.
	assert_false(route.has(TOWN_CUT))

func test_laying_the_shown_route_links_the_province() -> void:
	_setup_crown_road_survey()
	var survey: Dictionary = _snapshot()
	var route: Array = _route(survey, 1)
	assert_false(route.is_empty())
	for raw: Variant in route:
		var tile: Vector2i = raw
		_works.set_transport(_crown_road_survey_model, tile, LandWorks.TRANSPORT_ROAD)
	var linked: Dictionary = _snapshot()
	var entry: Dictionary = _entry(linked, 1)
	assert_true(bool(entry["linked"]))
	assert_eq(String(entry["state"]), CrownRoadSurvey.STATE_ROAD)
	assert_eq(int(entry["gap"]), 0)
	assert_true(_route(linked, 1).is_empty(), "a linked province needs no route")
	# The port province is still cut, but the new road shortens its gap to four.
	assert_eq(int(linked["counts"]["cut"]), 1)
	assert_eq(int(linked["counts"]["gap"]), 4)

func test_a_port_town_links_and_caps_its_neighbours() -> void:
	_setup_crown_road_survey()
	_works.add_port(_crown_road_survey_model, TOWN_PORT)
	var survey: Dictionary = _snapshot()
	var entry: Dictionary = _entry(survey, 2)
	assert_true(bool(entry["linked"]))
	# The port seeds the province's own network, but it is not a road to the
	# crown: its neighbours read town, so town development caps their yield.
	assert_eq(
		String(_states(survey).get(_crown_road_survey_model.index_of(6, 2), "")),
		CrownRoadSurvey.STATE_TOWN
	)
	assert_true(bool(entry["town_caps"]), "a port town caps the estates beside it")
	var neighbour: Dictionary = {
		"state": CrownRoadSurvey.STATE_TOWN, "town_level": 2, "town_caps": true
	}
	assert_eq(
		CrownRoadSurvey.summary_text(neighbour),
		"Crown road: town only — town level 2 caps its yield"
	)


## A town that merely stands beside a landfall port is inland for the town-cap
## rule, so nothing caps the estates around it and the reading must not say it
## does (wiki: extraction-and-improvements § Extraction formula and town
## development cap).
func test_a_town_beside_a_port_is_not_capped() -> void:
	var model := MapModel.new()
	model.setup(4, 2)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(Vector2i(x, y))
	var province := ProvinceState.create(
		0, "Colonia", tiles, Vector2(1.5, 0.5), tiles.size(), PLAYER, false
	)
	province.town_tile = Vector2i(1, 1)
	province.town_development = 1
	model.provinces = [province]
	model.resource[model.index_of(2, 1)] = 4
	var works := LandWorks.new()
	works.add_port(model, Vector2i(0, 1))
	works.set_improvement(model, Vector2i(2, 1), 4)
	var resolved: Dictionary = LandConnectivity.resolve(model, works, PLAYER, Vector2i(-1, -1))
	var survey: Dictionary = CrownRoadSurvey.snapshot(model, works, PLAYER, Vector2i(-1, -1))
	var entry: Dictionary = _entry(survey, 0)
	assert_eq(String(entry["state"]), CrownRoadSurvey.STATE_TOWN)
	assert_false(bool(entry["town_caps"]), "the town carries no port")
	assert_eq(
		CrownRoadSurvey.summary_text(entry),
		"Crown road: town only — town development does not cap it"
	)
	assert_eq(
		LandConnectivity.town_cap_for(model, resolved, 0, model.index_of(2, 1)),
		LandWorks.MAX_IMPROVEMENT,
		"the yield is not capped either"
	)
	assert_eq(
		Extraction.yields(model, PLAYER, -1, {"grain": 4}, works, Vector2i(-1, -1)),
		{"grain": 4},
		"the estate beside the town pays its whole level"
	)


## A reading counts one tile in the singular: the hover line is the only thing a
## player sees of the gap.
func test_the_reading_counts_one_tile_in_the_singular() -> void:
	assert_eq(
		CrownRoadSurvey.summary_text({"state": CrownRoadSurvey.STATE_CUT, "gap": 1}),
		"Crown road: one road tile from the crown"
	)
	assert_eq(
		CrownRoadSurvey.summary_text(
			{"state": CrownRoadSurvey.STATE_ROAD, "cut_tiles": 1}
		),
		"Crown road: linked by road · 1 tile cut off"
	)
	assert_eq(
		CrownRoadSurvey.summary_text({"state": CrownRoadSurvey.STATE_TOWN, "town_level": 0}),
		"Crown road: town only",
		"a town with no development states no cap"
	)

func test_foreign_land_is_never_painted() -> void:
	_setup_crown_road_survey()
	var survey: Dictionary = _snapshot()
	var painted: int = _painted_tiles(survey)
	_crown_road_survey_model.provinces[1].owner = RIVAL
	var foreign: Dictionary = _snapshot()
	assert_eq(_entry(foreign, 1), {}, "a rival province has no crown reading")
	assert_eq(_painted_tiles(foreign), painted - 9)
	assert_eq(int(foreign["counts"]["cut"]), 1, "only the port province is left cut")

func test_uncharted_ground_is_dropped() -> void:
	_setup_crown_road_survey()
	var visibility := VisibilityModel.new()
	visibility.setup(_crown_road_survey_model, PLAYER)
	for y in crown_road_survey_HEIGHT - 1:
		for x in crown_road_survey_WIDTH:
			visibility.lower_to(
				_crown_road_survey_model.index_of(x, y), VisibilityModel.Level.UNKNOWN
			)
	visibility.raise_to(_crown_road_survey_model.index_of(0, 1), VisibilityModel.Level.FULLY_VISIBLE)
	var survey: Dictionary = CrownRoadSurvey.snapshot(
		_crown_road_survey_model, _works, PLAYER, CAPITAL, visibility
	)
	assert_eq(_entry(survey, 1), {}, "a province the crown has not charted is skipped")
	assert_eq(_painted_tiles(survey), 1, "only the charted capital tile is painted")

func test_runs_cover_every_painted_tile_once() -> void:
	_setup_crown_road_survey()
	var survey: Dictionary = _snapshot()
	var from_runs: int = 0
	for state: String in CrownRoadSurvey.STATES:
		for raw: Variant in survey["runs"][state]:
			var run: Rect2 = raw
			from_runs += int(run.size.x) * int(run.size.y)
	assert_eq(from_runs, _painted_tiles(survey))

func test_summary_names_the_gap() -> void:
	_setup_crown_road_survey()
	var survey: Dictionary = _snapshot()
	assert_eq(
		CrownRoadSurvey.summary_text(_entry(survey, 1)),
		"Crown road: 3 road tiles from the crown"
	)
	assert_eq(
		CrownRoadSurvey.summary_text({"state": CrownRoadSurvey.STATE_ROAD}),
		"Crown road: linked by road"
	)
	assert_eq(
		CrownRoadSurvey.summary_text(
			{"state": CrownRoadSurvey.STATE_CUT, "gap": -1}
		),
		"Crown road: no owned-land route to the crown"
	)

## A harbour held by a hostile squadron is no landfall: the province's estates
## stop reaching the crown, while an estate on a road still does (wiki:
## capital-and-connectivity § Blockade; ships-and-naval § Missions and Movement).
func test_a_sealed_harbour_cuts_the_provinces_harvest() -> void:
	_setup_crown_road_survey()
	var model: MapModel = _crown_road_survey_model
	_works.add_port(model, TOWN_PORT)
	model.provinces[2].town_development = 0
	var estate := Vector2i(6, 2)
	_works.set_improvement(model, estate, 4)
	model.resource[model.index_of(estate.x, estate.y)] = 4
	var open: Dictionary = Extraction.yields(
		model, PLAYER, -1, {"grain": 4}, _works, Vector2i(-1, -1)
	)
	assert_eq(open, {"grain": 4}, "the harbour reaches the crown by sea")
	var seals: Blockades = _blockade_of(model, 2)
	var shut: Dictionary = Extraction.yields(
		model, PLAYER, -1, {"grain": 4}, _works, Vector2i(-1, -1), {}, true, {}, seals
	)
	assert_eq(shut, {}, "a blockaded harbour carries nothing home")
	# A road to the crown still pays: the blockade severs the sea path, not the
	# land. The road carries one grade where the harbour carried four.
	for x in 7:
		_works.set_transport(model, Vector2i(x, 2), LandWorks.TRANSPORT_ROAD)
	var road: Dictionary = Extraction.yields(
		model, PLAYER, -1, {"grain": 4}, _works, Vector2i(0, 1), {}, true, {}, seals
	)
	assert_eq(road, {"grain": 1}, "the road survives the blockade")


## A blockade of the court's own capital harbour cuts every sea path at once, so
## only ground the roads reach is left (wiki: capital-and-connectivity § Blockade).
func test_a_blockade_of_the_capital_cuts_every_sea_path() -> void:
	_setup_crown_road_survey()
	var model: MapModel = _crown_road_survey_model
	_works.add_port(model, TOWN_PORT)
	model.provinces[2].town_development = 0
	var estate := Vector2i(6, 2)
	_works.set_improvement(model, estate, 4)
	model.resource[model.index_of(estate.x, estate.y)] = 4
	var seals := Blockades.new()
	seals.sealed = {model.region_id: {0: true}}
	seals.sea_cut = true
	assert_eq(
		Extraction.yields(
			model, PLAYER, -1, {"grain": 4}, _works, Vector2i(-1, -1), {}, true, {}, seals
		),
		{},
		"the capital's fall closes every harbour"
	)


## The province dossier names the rule that cut it: a sealed harbour is not a
## missing road (wiki: capital-and-connectivity § Blockade; REQ-P2-03).
func test_a_blockaded_crown_link_says_which_rule_cut_it() -> void:
	_setup_crown_road_survey()
	var model: MapModel = _crown_road_survey_model
	_works.add_port(model, TOWN_PORT)
	var seals: Blockades = _blockade_of(model, 2)
	var link: Dictionary = LandConnectivity.province_link(
		model, _works, PLAYER, CAPITAL, 2, seals
	)
	assert_false(bool(link["linked"]), "the sea path is cut")
	assert_true(bool(link["blockaded"]))
	var copy: String = DossierCopy.crown_roads(model.provinces[2], link)
	assert_true(copy.contains("harbour blockaded"), copy)
	var open: Dictionary = LandConnectivity.province_link(
		model, _works, PLAYER, CAPITAL, 2
	)
	assert_false(bool(open["blockaded"]), "no blockade, no excuse")


## A station seals a coast only while it is at sea, at war, and over a province
## the asking court still holds (wiki: capital-and-connectivity § Blockade).
func test_a_blockade_seals_a_coast_only_while_at_war_and_at_sea() -> void:
	var model: MapModel = NavalFixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var at_war := func(a: int, b: int) -> bool: return a != b
	var raider: FleetState = FleetState.at_sea(9, RIVAL, 0, ["h1"], {"h1": "carrack"})
	raider.mission = FleetState.Mission.BLOCKADE
	raider.blockade_province = 0
	var seals: Blockades = Blockades.read(world, {0: [raider]}, PLAYER, 0, 1, at_war)
	assert_true(seals.seals(0, 0), "Cádiz is held")
	assert_false(seals.sea_cut, "the capital is another province")
	assert_eq(
		Blockades.note(seals, world),
		"Blockaded: Cádiz — nothing there reaches the crown by sea this turn"
	)
	# In port there is no station to keep.
	var docked: FleetState = FleetState.in_port(9, RIVAL, 0, ["h1"], {"h1": "carrack"})
	docked.mission = FleetState.Mission.BLOCKADE
	docked.blockade_province = 0
	assert_false(Blockades.read(world, {0: [docked]}, PLAYER, 0, 1, at_war).any())
	# Peace lapses it.
	var at_peace := func(_a: int, _b: int) -> bool: return false
	assert_false(Blockades.read(world, {0: [raider]}, PLAYER, 0, 1, at_peace).any())
	# A coast this court does not hold is no loss of its own.
	assert_false(Blockades.read(world, {0: [raider]}, 1, 0, 1, at_war).any())
	assert_eq(Blockades.note(Blockades.new(), world), "", "no blockade, no line")


## The map reads a court's seals from its own stations and wars, so the hub
## gains no method and the rules stay node-free (wiki:
## capital-and-connectivity § Blockade; REQ-P3-02).
func test_the_map_reads_the_courts_sealed_coasts() -> void:
	var model: MapModel = NavalFixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var session := PlaySession.new()
	session.world = world
	session.model = model
	session.diplomacy = DiplomacyState.new()
	session.ship_layer = ShipLayer.new()
	session.player_faction = PLAYER
	session.capital_province = 1
	assert_false(MapPlayBlockades.crown(session).any(), "no station, no seal")
	var raider: FleetState = FleetState.at_sea(9, RIVAL, 0, ["h1"], {"h1": "carrack"})
	raider.mission = FleetState.Mission.BLOCKADE
	raider.blockade_province = 0
	session.ship_layer.regions.set_region(0, [raider])
	session.diplomacy.ensure_relation(RIVAL, PLAYER)
	assert_false(MapPlayBlockades.crown(session).any(), "peace seals nothing")
	session.diplomacy.relation(RIVAL, PLAYER).at_war = true
	var seals: Blockades = MapPlayBlockades.crown(session)
	assert_true(seals.seals(0, 0), "Cádiz is held")
	assert_false(seals.sea_cut, "the capital is province 1")
	session.ship_layer.free()


## The reading's own edges: no world, no court, no station, and a source that
## answers with the wrong thing all seal nothing rather than guessing
## (REQ-P2-03).
func test_the_blockade_reading_keeps_its_edges_quiet() -> void:
	var world := WorldMap.new()
	assert_false(Blockades.read(world, {}, PLAYER, 0, 0).any(), "no regions, no seals")
	assert_false(Blockades.read(null, {0: []}, PLAYER, 0, 0).any())
	assert_false(Blockades.read(world, {}, MapModel.NO_ID, 0, 0).any())
	assert_false(Blockades.of(Callable()).any(), "unwired")
	assert_false(Blockades.of(func() -> int: return 3).any(), "not a reading")
	var cut := Blockades.new()
	cut.sea_cut = true
	assert_eq(
		Blockades.note(cut, world),
		"The capital's harbour is blockaded — only what the roads reach yields this turn"
	)
	assert_eq(Blockades.note(cut, null), "", "no world, no place to name")
	# A court with no map, no rosters or no court at all has no reading either.
	var bare := PlaySession.new()
	assert_false(MapPlayBlockades.crown(null).any())
	assert_false(MapPlayBlockades.crown(bare).any(), "no world yet")
	bare.world = world
	assert_false(MapPlayBlockades.crown(bare).any(), "no fleets yet")
	# A rival's own ports are read from its seat, not the human court's.
	var model: MapModel = NavalFixture.build()
	world.add_region(model)
	bare.ship_layer = ShipLayer.new()
	bare.diplomacy = DiplomacyState.new()
	assert_false(MapPlayBlockades.of(bare, RIVAL).any(), "no wars to read")
	bare.ship_layer.free()


func _blockade_of(model: MapModel, province_id: int) -> Blockades:
	var seals := Blockades.new()
	seals.sealed = {model.region_id: {province_id: true}}
	return seals


## Tile index -> state, rebuilt from the merged runs the view draws.
func _states(survey: Dictionary) -> Dictionary:
	var states: Dictionary = {}
	for state: String in CrownRoadSurvey.STATES:
		for raw: Variant in survey["runs"][state]:
			var run: Rect2 = raw
			for x in int(run.size.x):
				var tile := Vector2i(int(run.position.x) + x, int(run.position.y))
				states[_crown_road_survey_model.index_of(tile.x, tile.y)] = state
	return states

func _painted_tiles(survey: Dictionary) -> int:
	var total: int = 0
	for state: String in CrownRoadSurvey.STATES:
		total += int(survey["tiles"][state])
	return total

# --- test_capital_choice ---

func _blank() -> MapModel:
	var model := MapModel.new()
	model.setup(capital_choice_WIDTH, capital_choice_HEIGHT)
	return model

## Claims tiles for a province, starting from ocean, and registers the province.
func _add_province(
	model: MapModel, id: int, owner: int, tiles: Array, terrain: int = MapModel.Terrain.PLAINS
) -> void:
	var sum := Vector2.ZERO
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = terrain
		model.province[model.index_of(tile.x, tile.y)] = id
		sum += Vector2(tile)
	var typed_tiles: Array[Vector2i] = []
	for tile: Vector2i in tiles:
		typed_tiles.append(tile)
	model.provinces.append(
		ProvinceState.create(
			id, "P%d" % id, typed_tiles, sum / float(tiles.size()), tiles.size(), owner
		)
	)

func _block(x0: int, x1: int, y0: int, y1: int) -> Array:
	var tiles: Array = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			tiles.append(Vector2i(x, y))
	return tiles

## Paints every sea tile with a zone id chosen by position.
func _paint_sea(model: MapModel, zones: Callable) -> void:
	for y in model.height:
		for x in model.width:
			if model.is_sea(x, y):
				model.sea_zone[model.index_of(x, y)] = zones.call(x, y)

## 5x3 island at (3,3)-(7,5) with one sea zone on each side.
func _island_with_four_seaboards() -> MapModel:
	var model := _blank()
	_add_province(model, 0, 0, _block(3, 7, 3, 5))
	_paint_sea(model, func(x: int, y: int) -> int:
		if y <= 2:
			return 0
		if y >= 6:
			return 2
		if x <= 2:
			return 1
		return 3
	)
	return model

## Two separate islands, every sea tile in one zone.
func _two_islands() -> MapModel:
	var model := _blank()
	_add_province(model, 0, 0, _block(2, 4, 2, 4))
	_add_province(model, 1, 1, _block(7, 8, 6, 7))
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	return model

func test_sea_bound_lookup_and_sorted_seaboards() -> void:
	var model := _island_with_four_seaboards()
	assert_true(CapitalChoice.is_sea_bound(model, 0))
	assert_eq(CapitalChoice.sea_bound_sea_zones(model, 0), [0, 1, 2, 3])

func test_great_power_skips_lower_id_inland_province() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 0, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_add_province(model, 2, 1, [Vector2i(6, 6), Vector2i(7, 6)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	assert_false(CapitalChoice.is_sea_bound(model, 0))
	assert_true(CapitalChoice.is_sea_bound(model, 1))

	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(result["ok"])
	assert_eq(int(result["province_id"]), 1)

func test_great_power_without_sea_bound_province_fails_setup() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)

	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_false(result["ok"])
	assert_eq(String(result["error"]), CapitalChoice.ERROR_NO_SEA_BOUND_PROVINCE)
	assert_false(model.provinces[0].capital)

func test_faction_without_provinces_fails_setup() -> void:
	var model := _island_with_four_seaboards()
	var result: Dictionary = CapitalChoice.place_capital(model, 7)
	assert_false(result["ok"])
	assert_eq(String(result["error"]), CapitalChoice.ERROR_NO_OWNED_PROVINCE)

func test_minor_prefers_sea_bound_then_falls_back_to_inland() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 0, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_add_province(model, 2, 1, [Vector2i(7, 7)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)

	var pick: Dictionary = CapitalChoice.pick_province(model, 0, CapitalChoice.KIND_MINOR)
	assert_eq(int(pick["province_id"]), 1)

	var inland := _blank()
	_add_province(inland, 0, 0, [Vector2i(2, 2)])
	_add_province(inland, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(inland, func(_x: int, _y: int) -> int: return 0)
	var fallback: Dictionary = CapitalChoice.pick_province(
		inland, 0, CapitalChoice.KIND_MINOR
	)
	assert_eq(int(fallback["province_id"]), 0)

func test_great_power_takes_first_plains_class_a_tile() -> void:
	var model := _two_islands()
	model.terrain[model.index_of(2, 2)] = MapModel.Terrain.HARDWOOD_FOREST
	assert_eq(CapitalChoice.tile_class(model, 0, Vector2i(2, 2)), CapitalChoice.CLASS_A)
	assert_eq(CapitalChoice.tile_class(model, 0, Vector2i(3, 3)), CapitalChoice.CLASS_B)
	assert_eq(CapitalChoice.choose_tile(model, 0), Vector2i(3, 2))

func test_class_rank_beats_plains() -> void:
	var model := _two_islands()
	for tile: Vector2i in model.province_tiles(0):
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.HARDWOOD_FOREST
	model.terrain[model.index_of(3, 3)] = MapModel.Terrain.PLAINS
	assert_eq(CapitalChoice.choose_tile(model, 0), Vector2i(2, 2))

func test_great_power_falls_back_to_coastal_class_c() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 1, [Vector2i(1, 2), Vector2i(2, 1)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	assert_eq(CapitalChoice.tile_class(model, 0, Vector2i(2, 2)), CapitalChoice.CLASS_C)
	assert_eq(CapitalChoice.choose_tile(model, 0), Vector2i(2, 2))

func test_minor_takes_class_a_before_class_b() -> void:
	var model := _two_islands()
	for tile: Vector2i in model.province_tiles(0):
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.HARDWOOD_FOREST
	model.terrain[model.index_of(3, 3)] = MapModel.Terrain.PLAINS
	assert_eq(
		CapitalChoice.choose_tile(model, 0, CapitalChoice.KIND_MINOR), Vector2i(2, 2)
	)

func test_capital_tile_becomes_plains_and_loses_its_resource() -> void:
	var model := _two_islands()
	var seat := Vector2i(2, 2)
	for tile: Vector2i in model.province_tiles(0):
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.HARDWOOD_FOREST
	model.resource[model.index_of(seat.x, seat.y)] = 3
	model.provinces[0].resource = 3
	model.provinces[0].resource_tile = seat

	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(result["ok"])
	assert_true(bool(result["converted"]))
	assert_eq(model.terrain_at(seat.x, seat.y), MapModel.Terrain.PLAINS)
	assert_eq(model.resource_at(seat.x, seat.y), MapModel.NO_ID)
	assert_eq(model.provinces[0].resource, MapModel.NO_ID)
	assert_false(model.provinces[0].has_resource_tile())

func test_one_port_per_seaboard_with_roads_to_the_capital() -> void:
	var model := _island_with_four_seaboards()
	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(result["ok"])
	var seat := Vector2i(3, 3)
	assert_eq(Vector2i(result["tile"]), seat)

	var ports: Dictionary = result["ports"]
	assert_eq(ports.size(), 4)
	assert_eq(ports[0], seat)
	assert_eq(ports[1], seat)
	assert_eq(ports[2], Vector2i(3, 5))
	assert_eq(ports[3], Vector2i(7, 3))

	var roads: Array = result["road_paths"]
	assert_eq(roads.size(), 2)
	var port_tiles: Array = ports.values()
	for path: Array in roads:
		assert_true(port_tiles.has(path[0]))
		assert_eq(path[path.size() - 1], seat)
		assert_true(_is_contiguous(path))
	assert_eq(model.provinces[0].town_development, 4)

func test_inland_minor_gets_no_ports_or_roads() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)

	var result: Dictionary = CapitalChoice.place_capital(
		model, 0, CapitalChoice.KIND_MINOR
	)
	assert_true(result["ok"])
	assert_eq(int(result["province_id"]), 0)
	assert_true((result["ports"] as Dictionary).is_empty())
	assert_true((result["road_paths"] as Array).is_empty())
	assert_eq(model.provinces[0].town_development, 0)

func test_capital_choice_is_deterministic() -> void:
	var first := _island_with_four_seaboards()
	var second := _island_with_four_seaboards()
	var a: Dictionary = CapitalChoice.place_capital(first, 0)
	var b: Dictionary = CapitalChoice.place_capital(second, 0)
	assert_eq(a["tile"], b["tile"])
	assert_eq(a["ports"], b["ports"])
	assert_eq(a["road_paths"], b["road_paths"])

func test_place_all_reports_one_result_per_faction() -> void:
	var model := _two_islands()
	var results: Array[Dictionary] = CapitalChoice.place_all(model, [0, 1])
	assert_eq(results.size(), 2)
	assert_eq(int(results[0]["province_id"]), 0)
	assert_eq(int(results[1]["province_id"]), 1)
	assert_true(model.provinces[1].capital)

## Two owned provinces on one island, each with its own seaboard.
func _two_owned_coasts() -> MapModel:
	var model := _blank()
	_add_province(model, 0, 0, _block(2, 4, 2, 5))
	_add_province(model, 1, 0, _block(5, 7, 2, 5))
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	return model

## The interactive phase only accepts a crown province that reaches the sea.
func test_can_seat_accepts_only_owned_sea_bound_provinces() -> void:
	var model := _two_islands()
	assert_true(CapitalChoice.can_seat(model, 0, 0), "own sea-bound province")
	assert_false(CapitalChoice.can_seat(model, 0, 1), "another crown's province")
	assert_false(CapitalChoice.can_seat(model, 0, 99), "no such province")

	var inland := _blank()
	_add_province(inland, 0, 0, [Vector2i(2, 2)])
	_add_province(inland, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(inland, func(_x: int, _y: int) -> int: return 0)
	assert_false(
		CapitalChoice.can_seat(inland, 0, 0), "an inland province cannot hold the court"
	)

## The chart glows exactly the provinces the court may sit in: the crown's
## sea-bound holdings, in province order — never a rival's shore or an inland
## holding that would only earn a refusal.
func test_seatable_provinces_lists_only_the_crowns_seaboards() -> void:
	var model := _two_islands()
	_add_province(model, 2, 0, _block(2, 4, 6, 7))
	assert_true(CapitalChoice.is_sea_bound(model, 2), "the third holding reaches the sea")
	var expected: Array[int] = [0, 2]
	assert_eq(CapitalChoice.seatable_provinces(model, 0), expected)
	var auto_seat: int = int(CapitalChoice.pick_province(model, 0)["province_id"])
	assert_true(expected.has(auto_seat), "the auto-choice is one of the glowing provinces")

	var inland := _blank()
	_add_province(inland, 0, 0, [Vector2i(2, 2)])
	_add_province(inland, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(inland, func(_x: int, _y: int) -> int: return 0)
	var none: Array[int] = []
	assert_eq(CapitalChoice.seatable_provinces(inland, 0), none, "inland only: nothing glows")
	assert_eq(CapitalChoice.seatable_provinces(inland, 9), none, "no provinces: nothing glows")

## Seating by hand moves the capital works: the old province keeps its town but
## loses the harbour, the new one gains the court, its roads and town level 4.
func test_seat_capital_moves_the_court_and_its_harbour() -> void:
	var model := _two_owned_coasts()
	var first: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(first["ok"])
	assert_eq(int(first["province_id"]), 0)
	var seat := Vector2i(6, 3)

	var moved: Dictionary = CapitalChoice.seat_capital(model, 0, 1, seat)
	assert_true(moved["ok"])
	assert_eq(int(moved["province_id"]), 1)
	assert_eq(Vector2i(moved["tile"]), seat)
	assert_false(model.provinces[0].capital, "the old seat stands down")
	assert_eq(model.provinces[0].capital_tile, CapitalChoice.NO_TILE)
	assert_true((model.provinces[0].ports as Dictionary).is_empty(), "no stale harbour")
	assert_true((model.provinces[0].road_paths as Array).is_empty(), "no stale roads")
	assert_eq(model.provinces[0].town_development, 1, "the old capital keeps its town")
	assert_true(model.provinces[1].capital)
	assert_eq(model.provinces[1].capital_tile, seat)
	assert_eq(model.provinces[1].town_tile, seat, "the seat is the province town")
	assert_eq(model.provinces[1].town_development, 4)
	assert_true((model.provinces[1].ports as Dictionary).has(0), "the new seat has a port")
	assert_eq(CapitalChoice.seat_province(model, 0), 1)

## Select-then-convert applies to a hand-picked tile too.
func test_seat_capital_converts_the_chosen_tile_to_plains() -> void:
	var model := _two_owned_coasts()
	CapitalChoice.place_capital(model, 0)
	var seat := Vector2i(6, 4)
	var index: int = model.index_of(seat.x, seat.y)
	model.terrain[index] = MapModel.Terrain.HILLS
	model.resource[index] = 3
	model.provinces[1].resource_tile = seat

	var moved: Dictionary = CapitalChoice.seat_capital(model, 0, 1, seat)
	assert_true(moved["ok"])
	assert_true(bool(moved["converted"]))
	assert_eq(model.terrain_at(seat.x, seat.y), MapModel.Terrain.PLAINS)
	assert_eq(model.resource_at(seat.x, seat.y), MapModel.NO_ID)
	assert_false(model.provinces[1].has_resource_tile(), "the resource is cleared")

## A foreign province, an inland one and a tile outside the province are all
## refused, and the court stays where it was.
func test_seat_capital_refuses_foreign_inland_and_outside_tiles() -> void:
	var model := _two_islands()
	CapitalChoice.place_capital(model, 0)
	var before: Vector2i = model.provinces[0].capital_tile

	var foreign: Dictionary = CapitalChoice.seat_capital(model, 0, 1, Vector2i(7, 6))
	assert_false(foreign["ok"])
	assert_eq(String(foreign["error"]), CapitalChoice.ERROR_NOT_OWNED)

	var outside: Dictionary = CapitalChoice.seat_capital(model, 0, 0, Vector2i(7, 6))
	assert_false(outside["ok"])
	assert_eq(String(outside["error"]), CapitalChoice.ERROR_TILE_OUTSIDE)

	var sea: Dictionary = CapitalChoice.seat_capital(model, 0, 0, Vector2i(0, 0))
	assert_false(sea["ok"])
	assert_eq(String(sea["error"]), CapitalChoice.ERROR_TILE_OUTSIDE)

	var inland := _blank()
	_add_province(inland, 0, 0, [Vector2i(2, 2)])
	_add_province(inland, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(inland, func(_x: int, _y: int) -> int: return 0)
	var dry: Dictionary = CapitalChoice.seat_capital(inland, 0, 0, Vector2i(2, 2))
	assert_false(dry["ok"])
	assert_eq(String(dry["error"]), CapitalChoice.ERROR_NOT_SEA_BOUND)

	assert_true(model.provinces[0].capital, "a refused move changes nothing")
	assert_eq(model.provinces[0].capital_tile, before)

func _is_contiguous(path: Array) -> bool:
	for i in range(1, path.size()):
		var step: Vector2i = path[i] - path[i - 1]
		if absi(step.x) + absi(step.y) != 1:
			return false
	return true
