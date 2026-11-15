extends GdToolsTest
## One boot for the crown's turn: civilian voyages, deed protection, warp travel,
## the crown road survey and the capital choice.

## Merged from test_civilian_voyage, test_deed_protection, test_warp_travel,
## test_crown_road_survey, test_capital_choice, test_civilian_field_rules.
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

func before_each() -> void:
	_field_before_each()

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

# --- voyage_read ---

func test_a_free_squadron_has_hulls_and_no_passengers() -> void:
	_setup_civilian_voyage()
	var fleet: FleetState = _fleet()
	assert_true(VoyageRead.is_free(fleet))

	fleet.embarked_army = 3
	assert_false(VoyageRead.is_free(fleet), "an army aboard is no free hull")

	var laden: FleetState = _fleet()
	laden.add_civilian(7)
	assert_false(VoyageRead.is_free(laden), "a colonist aboard is no free hull")
	assert_false(
		VoyageRead.is_free(FleetState.empty_in_port(9, 0, 0)), "a slip has no hull"
	)
	assert_false(VoyageRead.is_free(null))

func test_the_free_squadron_is_the_lowest_id_that_still_moves() -> void:
	_setup_civilian_voyage()
	var first: FleetState = FleetState.in_port(3, 0, 0, ["a"], {"a": "fluyte"})
	var spent: FleetState = FleetState.in_port(2, 0, 0, ["a"], {"a": "fluyte"})
	spent.moved = true
	var foreign: FleetState = FleetState.in_port(1, 1, 0, ["a"], {"a": "fluyte"})

	var found: FleetState = VoyageRead.free_squadron([first, spent, foreign], 0)

	assert_eq(found.id, 3)
	assert_eq(VoyageRead.free_squadron([spent], 0), null, "a spent move is no hull")

func test_the_roomiest_squadron_carries_the_most_hulls() -> void:
	_setup_civilian_voyage()
	var small: FleetState = FleetState.in_port(2, 0, 0, ["a"], {"a": "fluyte"})
	var large: FleetState = FleetState.in_port(
		3, 0, 0, ["a", "b", "c"], {"a": "fluyte", "b": "fluyte", "c": "fluyte"}
	)
	var spent: FleetState = FleetState.in_port(
		4, 0, 0, ["a", "b", "c", "d"], {"a": "fluyte"}
	)
	spent.moved = true

	assert_eq(VoyageRead.roomiest([small, large, spent], 0).id, 3)

func test_the_free_hull_count_skips_spent_and_laden_hulls() -> void:
	_setup_civilian_voyage()
	var free_a: FleetState = FleetState.in_port(1, 0, 0, ["a"], {"a": "fluyte"})
	var free_b: FleetState = FleetState.in_port(2, 0, 0, ["a"], {"a": "fluyte"})
	var spent: FleetState = FleetState.in_port(3, 0, 0, ["a"], {"a": "fluyte"})
	spent.moved = true
	var laden: FleetState = FleetState.in_port(4, 0, 0, ["a"], {"a": "fluyte"})
	laden.add_civilian(7)
	var foreign: FleetState = FleetState.in_port(5, 1, 0, ["a"], {"a": "fluyte"})

	assert_eq(
		VoyageRead.free_count([free_a, free_b, spent, laden, foreign, null], 0), 2
	)

func test_a_loaded_squadron_is_read_with_or_without_its_move() -> void:
	_setup_civilian_voyage()
	var spent: FleetState = FleetState.in_port(2, 0, 0, ["a"], {"a": "fluyte"})
	spent.add_civilian(7)
	spent.moved = true
	var waiting: FleetState = FleetState.in_port(4, 0, 0, ["a"], {"a": "fluyte"})
	waiting.add_civilian(8)

	assert_eq(VoyageRead.carrying([waiting, spent], 0).id, 2)
	assert_eq(VoyageRead.carrying([waiting, spent], 0, true).id, 4)
	assert_eq(VoyageRead.carrying([waiting], 1), null)

func test_the_idle_colonist_has_not_worked_moved_or_embarked() -> void:
	_setup_civilian_voyage()
	var worked: CivilianState = CivilianState.create(2, 0, "explorer", Vector2i(0, 0))
	worked.start_work("prospect", Vector2i(0, 0), 2)
	var spent: CivilianState = CivilianState.create(3, 0, "explorer", Vector2i(0, 0))
	spent.moved = true
	var aboard: CivilianState = CivilianState.create(4, 0, "explorer", Vector2i(0, 0))
	aboard.embarked_fleet = 5
	var idle: CivilianState = CivilianState.create(6, 0, "explorer", Vector2i(1, 0))
	var builder: CivilianState = CivilianState.create(1, 0, "builder", Vector2i(0, 0))

	var found: CivilianState = VoyageRead.idle_colonist(
		[worked, spent, aboard, builder, idle], 0, "explorer"
	)

	assert_eq(found.id, 6)
	assert_eq(VoyageRead.idle_colonist([], 0, "explorer"), null)

func test_owns_land_reads_the_provinces_and_their_region() -> void:
	_setup_civilian_voyage()
	var world := WorldMap.new()
	world.add_region(_model)

	assert_true(VoyageRead.owns_land(_model, 0))
	assert_true(VoyageRead.owns_land(_model, 1))
	assert_false(VoyageRead.owns_land(_model, 9))
	assert_false(VoyageRead.owns_land(null, 0))
	assert_true(VoyageRead.owns_land_in(world, WorldMap.OLD_WORLD, 0))
	assert_false(VoyageRead.owns_land_in(world, WorldMap.NEW_WORLD, 0))
	assert_false(VoyageRead.owns_land_in(null, WorldMap.OLD_WORLD, 0))

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

## A court on `earn` still works its own land, but only the extraction that
## refills the store: town levels, roads and ports wait for the muster it is
## saving for (issue #489). A survey survives: the deposit is hidden until the
## Explorer digs, so its order names no resource — dropping it left every rival
## with an idle Explorer for the whole campaign.
func test_an_earning_court_keeps_only_extraction_works() -> void:
	var model := MapModel.new()
	model.setup(3, 1)
	model.terrain.fill(MapModel.Terrain.PLAINS)
	model.resource[model.index_of(0, 0)] = 3
	model.resource[model.index_of(1, 0)] = MapModel.NO_ID
	var plan: Dictionary = {
		"orders": [
			{"action": "build_improvement", "tile": Vector2i(0, 0)},
			{"action": "build_improvement", "tile": Vector2i(1, 0)},
			{"action": "build_town", "tile": Vector2i(2, 0)},
			{"action": "prospect", "tile": Vector2i(1, 0)},
		],
	}

	MapPlayCivilianAi._keep_extraction(plan, model)

	assert_eq((plan["orders"] as Array).size(), 2, "the resource tile and the survey survive")
	assert_eq((plan["orders"] as Array)[0]["tile"], Vector2i(0, 0))
	assert_eq(String((plan["orders"] as Array)[1]["action"]), "prospect")


## The two purses: a court on `earn` keeps the works open down to its cash floor
## while hires still wait for the muster (issue #489).
func test_the_works_purse_opens_when_the_court_is_earning() -> void:
	var saving: Dictionary = MapPlayCivilianAi.purses_for(1000, 2400, -1)
	assert_eq(int(saving["spendable"]), 0, "nothing is discretionary below the reserve")
	assert_eq(int(saving["works"]), 0)
	assert_false(bool(saving["earn"]))

	var earning: Dictionary = MapPlayCivilianAi.purses_for(1000, 2400, 400)
	assert_eq(int(earning["spendable"]), 0, "hires still stand down")
	assert_eq(int(earning["works"]), 600, "extraction may draw on the purse")
	assert_true(bool(earning["earn"]))


## Hires stand down while the court saves; the works purse is a separate read.
func test_a_hire_reads_the_hire_purse() -> void:
	var config: AiConfig = AiConfig.build(0, 1500)
	var units: Array = []
	var rich: Dictionary = {
		"capital_province": 0, "treasury": 5000, "hire_treasury": 0, "paper": 5,
	}
	var poor: Dictionary = {
		"capital_province": 0, "treasury": 0, "hire_treasury": 5000, "paper": 5,
	}

	assert_true(
		AiCivilianPlanner.training_order(config, units, rich).is_empty(),
		"a court saving for its muster hires nobody"
	)
	assert_false(
		AiCivilianPlanner.training_order(config, units, poor).is_empty(),
		"the hire purse is what pays a new civilian"
	)


func _is_contiguous(path: Array) -> bool:
	for i in range(1, path.size()):
		var step: Vector2i = path[i] - path[i - 1]
		if absi(step.x) + absi(step.y) != 1:
			return false
	return true

# ==== merged from test_civilian_field_rules.gd (one coverage boot; docs/testing.md § Speed rules) ====
## Civilian movement, work, improvement and estate-row rules on the shared
## civilian fixture (test_estate_rows_rules is folded in).
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).

const field_Fixture = preload("res://tests/civilian_fixture.gd")
## A Tribe that a rival crown has colonised, and the crown that colonised it:
## the pair a colonial boycott bars (wiki: diplomacy § GP–Tribe — Boycott, R6).
const FALSE_COLONY_TRIBE: int = 9
const BOYCOTT_ISSUER: int = 2


## Minimal HUD for the deed despatch: the purchase path repaints the treasury
## and toasts, and neither may build real chrome inside a rules test.
class DeedHud extends GameHud:
	var toasts: Array[String] = []

	func set_treasury(_value: int, _animate: bool = true) -> void:
		pass

	func toast(text: String, _icon_name: String = "") -> void:
		toasts.append(text)


var field__model: MapModel = null
var field__works: LandWorks = null
var _units: Array[CivilianState] = []
var _stock: Dictionary = {}
var _view: VisibilityModel = null

func _field_before_each() -> void:
	field__model = field_Fixture.build()
	field__works = LandWorks.new()
	_units = []
	_stock = field_Fixture.stockpile()
	_view = field_Fixture.visibility(field__model)

# --- from test_civilian_movement.gd ---
## Civilian land movement (wiki: civilian-units § Relations).

func test_explorer_walks_one_orthogonal_land_tile() -> void:
	var explorer := field_Fixture.unit("explorer", Vector2i(1, 1))
	var tiles: Array[Vector2i] = CivilianMovement.valid_tiles(field__model, explorer)
	assert_eq(tiles.size(), 4)
	for tile: Vector2i in [
		Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)
	]:
		assert_true(tiles.has(tile), str(tile))


func test_sea_and_diagonals_are_out_of_reach() -> void:
	var explorer := field_Fixture.unit("explorer", field_Fixture.COAST_TILE)
	var tiles: Array[Vector2i] = CivilianMovement.valid_tiles(field__model, explorer)
	assert_false(tiles.has(Vector2i(1, 4)), "sea row")
	assert_eq(CivilianMovement.apply_move(
		field__model, explorer, Vector2i(1, 4)
	)["ok"], false)


func test_builder_keeps_to_its_crowns_land() -> void:
	var builder := field_Fixture.unit("builder", Vector2i(2, 1))
	var tiles: Array[Vector2i] = CivilianMovement.valid_tiles(field__model, builder)
	assert_false(tiles.has(Vector2i(3, 1)))
	assert_true(tiles.has(Vector2i(2, 0)))
	var refused: Dictionary = CivilianMovement.apply_move(
		field__model, builder, Vector2i(3, 1)
	)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("without a war"))
	assert_eq(builder.tile, Vector2i(2, 1))


func test_explorer_may_cross_into_a_rival_province() -> void:
	var explorer := field_Fixture.unit("explorer", Vector2i(2, 1))
	var result: Dictionary = CivilianMovement.apply_move(
		field__model, explorer, Vector2i(3, 1)
	)
	assert_true(bool(result["ok"]))
	assert_eq(explorer.tile, Vector2i(3, 1))


func test_one_move_per_turn() -> void:
	var explorer := field_Fixture.unit("explorer", Vector2i(1, 1))
	assert_true(bool(CivilianMovement.apply_move(
		field__model, explorer, Vector2i(2, 1)
	)["ok"]))
	var second: Dictionary = CivilianMovement.apply_move(
		field__model, explorer, Vector2i(2, 2)
	)
	assert_false(bool(second["ok"]))
	assert_true(String(second["reason"]).contains("already moved"))
	assert_eq(explorer.tile, Vector2i(2, 1))


func test_begin_turn_restores_the_move() -> void:
	var explorer := field_Fixture.unit("explorer", Vector2i(1, 1))
	CivilianMovement.apply_move(field__model, explorer, Vector2i(2, 1))
	var units: Array[CivilianState] = [explorer]
	CivilianMovement.begin_turn(units)
	assert_false(explorer.moved)
	assert_true(bool(CivilianMovement.apply_move(
		field__model, explorer, Vector2i(2, 2)
	)["ok"]))


func test_working_civilians_stay_on_their_tile() -> void:
	var builder := field_Fixture.unit("builder", field_Fixture.IRON_TILE)
	builder.start_work("build_improvement", field_Fixture.IRON_TILE, 1)
	var result: Dictionary = CivilianMovement.apply_move(
		field__model, builder, Vector2i(0, 1)
	)
	assert_false(bool(result["ok"]))
	assert_eq(CivilianMovement.valid_tiles(field__model, builder), [])


func test_non_adjacent_tiles_are_refused() -> void:
	var explorer := field_Fixture.unit("explorer", Vector2i(0, 0))
	var result: Dictionary = CivilianMovement.apply_move(
		field__model, explorer, Vector2i(2, 2)
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("one tile"))
	assert_eq(explorer.tile, Vector2i(0, 0))


func test_out_of_bounds_land_is_refused() -> void:
	assert_false(CivilianMovement.may_enter(field__model, "explorer", 0, Vector2i(-1, 0)))
	assert_false(CivilianMovement.may_enter(field__model, "explorer", 0, Vector2i(9, 9)))
	assert_true(CivilianMovement.may_enter(field__model, "explorer", 0, Vector2i(0, 0)))


## Order visibility gate (wiki: fog-and-exploration § Order Visibility
## Requirements): a march into a province the crown has never charted is
## refused, even though an Explorer may roam any land.
func test_a_march_into_an_uncharted_province_is_refused() -> void:
	var explorer := field_Fixture.unit("explorer", Vector2i(2, 0))
	for tile: Vector2i in field__model.province_tiles(field_Fixture.RIVAL_PROVINCE):
		_view.lower_to(field__model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN)
	assert_false(
		CivilianMovement.valid_tiles(field__model, explorer, _view).has(Vector2i(3, 0)),
		"the uncharted province is not a march option"
	)
	var result: Dictionary = CivilianMovement.apply_move(
		field__model, explorer, Vector2i(3, 0), _view
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("charted"))
	assert_eq(explorer.tile, Vector2i(2, 0))


## One charted tile anywhere in the province is enough: a coast glimpsed from
## the sea opens the whole province to land orders.
func test_a_glimpsed_province_accepts_the_march() -> void:
	var explorer := field_Fixture.unit("explorer", Vector2i(2, 0))
	var tiles: Array[Vector2i] = field__model.province_tiles(field_Fixture.RIVAL_PROVINCE)
	for tile: Vector2i in tiles:
		_view.lower_to(field__model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN)
	_view.raise_to(field__model.index_of(tiles[0].x, tiles[0].y), VisibilityModel.Level.FOGGED)
	assert_true(
		CivilianMovement.valid_tiles(field__model, explorer, _view).has(Vector2i(3, 0))
	)
	assert_true(bool(CivilianMovement.apply_move(
		field__model, explorer, Vector2i(3, 0), _view
	)["ok"]))

# --- from test_civilian_work.gd ---
## Civilian work orders: gates, costs, multi-turn progress and tile effects
## (wiki: civilian-units § Work Types, extraction-and-improvements costs).

func test_exploration_time_follows_the_wiki_formula() -> void:
	# ceil(3 × province tiles / largest province), capped at three turns.
	assert_eq(CivilianWork.explore_turns(field__model, field_Fixture.PLAYER_PROVINCE), 3)
	assert_eq(CivilianWork.explore_turns(field__model, field_Fixture.RIVAL_PROVINCE), 2)


func test_explorer_charts_a_rival_province_over_several_turns() -> void:
	var explorer := _add("explorer", Vector2i(3, 1))
	var check: Dictionary = _validate(explorer, "explore")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), 2)
	assert_true(bool(CivilianWork.assign(
		field__model, explorer, "explore", field__works, _units, _stock, _view
	)["ok"]))
	assert_true(explorer.is_working())

	var first: Array[Dictionary] = CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_false(bool(first[0]["completed"]))
	assert_true(explorer.is_working())

	var second: Array[Dictionary] = CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_true(bool(second[0]["completed"]))
	assert_true(explorer.is_idle())
	var tile: Vector2i = field__model.province_tiles(field_Fixture.RIVAL_PROVINCE)[0]
	assert_eq(_view.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE)
	assert_true(_view.is_province_fully_visible(field_Fixture.RIVAL_PROVINCE))


func test_explorer_cannot_chart_land_already_seen() -> void:
	var explorer := _add("explorer", field_Fixture.IRON_TILE)
	var check: Dictionary = _validate(explorer, "explore")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("already charted"))


func test_prospecting_takes_one_turn_and_records_the_tile() -> void:
	var explorer := _add("explorer", field_Fixture.IRON_TILE)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), 1)
	CivilianWork.assign(field__model, explorer, "prospect", field__works, _units, _stock, _view)
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_true(bool(reports[0]["completed"]))
	assert_true(field__works.is_prospected(0, field__model, field_Fixture.IRON_TILE))
	assert_false(field__works.is_prospected(1, field__model, field_Fixture.IRON_TILE))


func test_only_prospectable_ground_can_be_prospected() -> void:
	# Timber on plains: the resource already shows, so there is nothing to read.
	var explorer := _add("explorer", field_Fixture.TIMBER_TILE)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("already known"))
	# Bare plains: not survey ground at all (wiki: fog-and-exploration
	# § Prospectable terrain).
	field__model.resource[field__model.index_of(field_Fixture.TIMBER_TILE.x, field_Fixture.TIMBER_TILE.y)] = MapModel.NO_ID
	check = _validate(explorer, "prospect")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("swamp, hills, mountain or desert"))


func test_tin_tiles_can_be_prospected() -> void:
	# Wiki: fog-and-exploration § Prospect-Required Resources lists tin with the
	# other prospected minerals; tin spawns on marsh ground.
	var tile := Vector2i(2, 2)
	field__model.resource[field__model.index_of(tile.x, tile.y)] = 8
	field__model.terrain[field__model.index_of(tile.x, tile.y)] = MapModel.Terrain.SWAMP
	var explorer := _add("explorer", tile)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	CivilianWork.assign(field__model, explorer, "prospect", field__works, _units, _stock, _view)
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_true(field__works.is_prospected(0, field__model, tile))


func test_exploring_a_minor_province_needs_a_consulate() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var works := LandWorks.new()
	var explorer := field_Fixture.unit("explorer", Vector2i(2, 1))
	var units: Array[CivilianState] = [explorer]
	var view := field_Fixture.visibility(model)
	var no_court := DiplomacyState.new()
	no_court.initialize(1)
	no_court.ensure_relation(0, 6, 50)
	for action: String in ["explore", "prospect"]:
		var blocked: Dictionary = CivilianWork.validate(
			model, explorer, action, works, units, field_Fixture.stockpile(), view,
			CivilianState.NO_TILE, {}, {}, {"diplomacy": no_court}
		)
		assert_false(bool(blocked["ok"]), action)
		assert_true(String(blocked["reason"]).contains("consulate"), action)
	var court := field_Fixture.merchant_court()
	var allowed: Dictionary = CivilianWork.validate(
		model, explorer, "prospect", works, units, field_Fixture.stockpile(), view,
		CivilianState.NO_TILE, {}, {}, {"diplomacy": court}
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))


func test_a_prospected_tile_cannot_be_prospected_again() -> void:
	var explorer := _add("explorer", field_Fixture.IRON_TILE)
	field__works.set_prospected(0, field__model, field_Fixture.IRON_TILE)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("already been prospected"))


func test_only_charted_land_can_be_prospected() -> void:
	var explorer := _add("explorer", field_Fixture.IRON_TILE)
	var index: int = field__model.index_of(field_Fixture.IRON_TILE.x, field_Fixture.IRON_TILE.y)
	_view.lower_to(index, VisibilityModel.Level.UNKNOWN)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("charted"))
	_view.raise_to(index, VisibilityModel.Level.FOGGED)
	var allowed: Dictionary = _validate(explorer, "prospect")
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))


func test_a_survey_uncovers_the_mineral_and_the_report_names_it() -> void:
	var explorer := _add("explorer", field_Fixture.IRON_TILE)
	# Hidden until the survey lands: no row, no readable resource, no estate.
	assert_eq(
		MineralSurvey.known_resource(field__model, field__works, 0, field_Fixture.IRON_TILE), -1
	)
	assert_true(
		ResourceSurvey.province_rows(
			field__model, field__works, _units, 0, field_Fixture.PLAYER_PROVINCE
		).filter(
			func(row: Dictionary) -> bool: return row["tile"] == field_Fixture.IRON_TILE
		).is_empty(),
		"an unsurveyed mineral is never surveyed"
	)
	assert_true(
		ImprovementLedger.snapshot(
			field__model, field__works, _units, _stock, 0, field_Fixture.BARE_TILE
		)["estates"].filter(
			func(row: Dictionary) -> bool: return row["tile"] == field_Fixture.IRON_TILE
		).is_empty(),
		"no estate row exists for ground the crown has not read"
	)
	CivilianWork.assign(field__model, explorer, "prospect", field__works, _units, _stock, _view)
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		field__model, _units, field__works, _view
	)
	assert_eq(String(reports[0].get("find", "")), "iron", "the despatch names the find")
	assert_eq(
		MineralSurvey.known_resource(field__model, field__works, 0, field_Fixture.IRON_TILE), 1
	)
	assert_false(
		ResourceSurvey.province_rows(
			field__model, field__works, _units, 0, field_Fixture.PLAYER_PROVINCE
		).filter(
			func(row: Dictionary) -> bool: return row["tile"] == field_Fixture.IRON_TILE
		).is_empty(),
		"the survey lens now names the estate"
	)
	# Fog is unchanged by a survey: only the deposit became known.
	assert_eq(
		_view.level_at(field_Fixture.IRON_TILE.x, field_Fixture.IRON_TILE.y),
		VisibilityModel.Level.FULLY_VISIBLE
	)


func test_the_survey_predicate_reads_ground_and_courts_alike() -> void:
	# The one predicate every surface shares (wiki: fog-and-exploration
	# § Prospecting; DR-20261111-26).
	var iron: int = field__model.resource_at(field_Fixture.IRON_TILE.x, field_Fixture.IRON_TILE.y)
	assert_true(MineralSurvey.is_mineral(iron), "iron is a deposit")
	assert_false(MineralSurvey.is_mineral(-1))
	var timber: int = field__model.resource_at(field_Fixture.TIMBER_TILE.x, field_Fixture.TIMBER_TILE.y)
	assert_false(MineralSurvey.is_mineral(timber))
	assert_true(MineralSurvey.terrain_known(timber))
	assert_false(MineralSurvey.terrain_known(iron))
	assert_false(MineralSurvey.terrain_known(-1))
	# Ground: hills can be read, plains cannot, the sea never.
	assert_true(MineralSurvey.prospectable(field__model, field_Fixture.IRON_TILE))
	assert_false(MineralSurvey.prospectable(field__model, field_Fixture.TIMBER_TILE))
	assert_false(MineralSurvey.prospectable(field__model, Vector2i(0, 4)))
	assert_false(MineralSurvey.prospectable(null, field_Fixture.IRON_TILE))
	# Known: hidden before the survey, read after it, and only for that court.
	assert_eq(MineralSurvey.known_resource(field__model, field__works, 0, field_Fixture.IRON_TILE), -1)
	assert_eq(MineralSurvey.known_resource(null, field__works, 0, field_Fixture.IRON_TILE), -1)
	assert_false(MineralSurvey.is_known(field__model, field__works, 0, field_Fixture.IRON_TILE))
	assert_eq(MineralSurvey.find_of(field__model, field_Fixture.IRON_TILE), "iron")
	assert_eq(MineralSurvey.find_of(field__model, field_Fixture.HILLS_TILE), "")
	assert_eq(MineralSurvey.find_of(null, field_Fixture.IRON_TILE), "")
	field__works.set_prospected(0, field__model, field_Fixture.IRON_TILE)
	assert_eq(
		MineralSurvey.known_resource(field__model, field__works, 0, field_Fixture.IRON_TILE), iron
	)
	assert_eq(MineralSurvey.known_resource(field__model, field__works, 1, field_Fixture.IRON_TILE), -1)
	# The set of ground left to read, per province and per court.
	var left: Array[Vector2i] = MineralSurvey.unsurveyed_in_province(
		field__model, field__works, 0, field_Fixture.PLAYER_PROVINCE
	)
	assert_false(left.has(field_Fixture.IRON_TILE), "a read tile leaves the set")
	assert_true(left.has(field_Fixture.HILLS_TILE))
	var counts: Dictionary = MineralSurvey.unsurveyed_by_province(field__model, field__works, 0)
	assert_eq(int(counts.get(field_Fixture.PLAYER_PROVINCE, 0)), left.size())
	assert_true(MineralSurvey.unsurveyed_in_province(null, field__works, 0, 0).is_empty())
	assert_true(MineralSurvey.unsurveyed_by_province(null, field__works, 0).is_empty())
	# Refusals name the one thing that is wrong, in the order a player hits it.
	assert_true(MineralSurvey.refusal(field__model, field__works, 0, Vector2i(0, 4)).contains("land"))
	assert_true(
		MineralSurvey.refusal(field__model, field__works, 0, field_Fixture.IRON_TILE).contains("already been")
	)
	assert_true(
		MineralSurvey.refusal(field__model, field__works, 0, field_Fixture.TIMBER_TILE).contains("already known")
	)
	# Bare plains are not survey ground; the refusal says which ground is.
	assert_true(
		MineralSurvey.refusal(field__model, field__works, 0, Vector2i(2, 3)).contains("swamp, hills")
	)
	assert_true(MineralSurvey.refusal(field__model, field__works, 0, field_Fixture.HILLS_TILE).is_empty())
	assert_true(MineralSurvey.can_prospect(field__model, field__works, 0, field_Fixture.HILLS_TILE))
	# Uncharted ground is never a target.
	var view := VisibilityModel.new()
	view.setup(field__model, 0)
	view.lower_to(
		field__model.index_of(field_Fixture.HILLS_TILE.x, field_Fixture.HILLS_TILE.y),
		VisibilityModel.Level.UNKNOWN
	)
	assert_true(
		MineralSurvey.refusal(field__model, field__works, 0, field_Fixture.HILLS_TILE, view).contains("charted")
	)


func test_an_empty_survey_is_legal_and_finds_nothing() -> void:
	var explorer := _add("explorer", field_Fixture.HILLS_TILE)
	assert_true(MineralSurvey.prospectable(field__model, field_Fixture.HILLS_TILE))
	var check: Dictionary = _validate(explorer, "prospect")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	CivilianWork.assign(field__model, explorer, "prospect", field__works, _units, _stock, _view)
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		field__model, _units, field__works, _view
	)
	assert_true(bool(reports[0]["completed"]))
	assert_eq(String(reports[0].get("find", "x")), "", "the ground held nothing")
	assert_true(field__works.is_prospected(0, field__model, field_Fixture.HILLS_TILE))
	# A read tile is never a survey target again, even with nothing under it.
	var again: Dictionary = _validate(explorer, "prospect")
	assert_false(bool(again["ok"]))
	assert_true(String(again["reason"]).contains("already been prospected"))


func test_an_explorer_surveys_only_the_province_it_stands_in() -> void:
	var far := Vector2i(4, 3)
	field__model.terrain[field__model.index_of(far.x, far.y)] = MapModel.Terrain.HILLS
	var explorer := _add("explorer", field_Fixture.BARE_TILE)
	var check: Dictionary = CivilianWork.validate(
		field__model, explorer, "prospect", field__works, _units, _stock, _view, far
	)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("province it stands in"))
	# The same Explorer may read any tile of its own province without marching.
	var near: Dictionary = CivilianWork.validate(
		field__model, explorer, "prospect", field__works, _units, _stock, _view,
		field_Fixture.IRON_TILE
	)
	assert_true(bool(near["ok"]), String(near.get("reason", "")))


func test_a_rivals_survey_does_not_reveal_the_deposit() -> void:
	var explorer := _add("explorer", field_Fixture.IRON_TILE)
	CivilianWork.assign(field__model, explorer, "prospect", field__works, _units, _stock, _view)
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_true(field__works.is_prospected(0, field__model, field_Fixture.IRON_TILE))
	assert_eq(
		MineralSurvey.known_resource(field__model, field__works, 1, field_Fixture.IRON_TILE), -1,
		"another court reads nothing from our survey"
	)


func test_builder_pays_materials_and_raises_the_improvement_level() -> void:
	var builder := _add("builder", field_Fixture.IRON_TILE)
	field__works.set_prospected(0, field__model, field_Fixture.IRON_TILE)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(check["cost"], {"lumber": 1, "castIron": 1})
	assert_eq(int(check["duration"]), 1)
	CivilianWork.assign(field__model, builder, "build_improvement", field__works, _units, _stock, _view)
	assert_eq(int(_stock["lumber"]), 39)
	assert_eq(int(_stock["castIron"]), 39)
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_eq(field__works.improvement_at(field__model, field_Fixture.IRON_TILE), 1)

	var second: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(second["ok"]))
	assert_true(String(second["reason"]).contains("tech"))


func test_improvements_need_a_resource_tile() -> void:
	var builder := _add("builder", field_Fixture.BARE_TILE)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("with a resource"))


func test_builder_cannot_improve_foreign_land() -> void:
	var builder := _add("builder", field_Fixture.RIVAL_GRAIN_TILE)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("not held by your crown"))


func test_improvements_stop_at_level_four() -> void:
	var builder := _add("builder", field_Fixture.IRON_TILE)
	field__works.set_improvement(field__model, field_Fixture.IRON_TILE, LandWorks.MAX_IMPROVEMENT)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("fully improved"))


func test_builder_upgrades_the_town_with_national_bureaucracy() -> void:
	var builder := _add("builder", field_Fixture.BARE_TILE)
	var blocked: Dictionary = _validate(builder, "upgrade_town")
	assert_false(bool(blocked["ok"]))
	assert_true(String(blocked["reason"]).contains("National Bureaucracy"))
	var tech := {"national_bureaucracy": true}
	var check: Dictionary = _validate(builder, "upgrade_town", tech)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(check["cost"], {"lumber": 4, "castIron": 4})
	assert_eq(int(check["duration"]), 2)
	CivilianWork.assign(
		field__model, builder, "upgrade_town", field__works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech
	)
	assert_eq(int(_stock["lumber"]), 36)
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_eq(field__model.provinces[0].town_development, 2)


## A town can be raised while a Builder is still at it — a capital reassignment
## sets the new seat to town development 4. The finished order lands its priced
## level but never lowers what the town already holds (wiki:
## extraction-and-improvements § Improvement Build Costs; capital-and-connectivity
## § Capital loss and reassignment).
func test_a_finished_town_order_never_lowers_the_town() -> void:
	var builder := _add("builder", field_Fixture.BARE_TILE)
	var tech := {"national_bureaucracy": true}
	var check: Dictionary = _validate(builder, "upgrade_town", tech)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), 2)
	var order: Dictionary = CivilianWork.assign(
		field__model, builder, "upgrade_town", field__works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech
	)
	assert_true(bool(order["ok"]), String(order.get("reason", "")))
	# The court moves here: the seat rule lifts the town to 4 mid-build.
	field__model.provinces[0].town_development = 4
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_eq(field__model.provinces[0].town_development, 4)


func test_town_upgrades_only_on_the_town_tile_and_stop_at_four() -> void:
	var builder := _add("builder", field_Fixture.TIMBER_TILE)
	var tech := {"national_bureaucracy": true}
	var wrong: Dictionary = _validate(builder, "upgrade_town", tech)
	assert_false(bool(wrong["ok"]))
	assert_true(String(wrong["reason"]).contains("town tile"))
	field__model.provinces[0].town_development = 4
	var capped: Dictionary = CivilianWork.validate(
		field__model, field_Fixture.unit("builder", field_Fixture.BARE_TILE), "upgrade_town",
		field__works, _units, _stock, _view, CivilianState.NO_TILE, {}, tech
	)
	assert_false(bool(capped["ok"]))
	assert_true(String(capped["reason"]).contains("fully developed"))


func test_town_order_dispatches_the_nearest_builder() -> void:
	field__model.provinces[0].town_tile = field_Fixture.BARE_TILE
	var builder := _add("builder", field_Fixture.TIMBER_TILE)
	var tech := {"national_bureaucracy": true}
	var result: Dictionary = ImprovementOrders.upgrade_town(
		field__model, _units, field__works, _stock, _view, 0, field_Fixture.BARE_TILE, tech
	)
	assert_true(bool(result["ok"]), String(result.get("message", "")))
	assert_true(builder.is_working())
	assert_eq(builder.work_tile(), field_Fixture.BARE_TILE)
	assert_eq(builder.work_action(), "upgrade_town")


func test_town_order_reports_a_missing_builder() -> void:
	field__model.provinces[0].town_tile = field_Fixture.BARE_TILE
	var result: Dictionary = ImprovementOrders.upgrade_town(
		field__model, _units, field__works, _stock, _view, 0, field_Fixture.BARE_TILE,
		{"national_bureaucracy": true}
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["message"]).contains("No idle Builder"))


func test_scrub_forest_caps_timber_improvements() -> void:
	var builder := _add("builder", field_Fixture.TIMBER_TILE)
	var index: int = field__model.index_of(field_Fixture.TIMBER_TILE.x, field_Fixture.TIMBER_TILE.y)
	field__model.terrain[index] = MapModel.Terrain.SCRUB_FOREST
	field__works.set_improvement(field__model, field_Fixture.TIMBER_TILE, 1)
	var check: Dictionary = CivilianWork.validate(
		field__model, builder, "build_improvement", field__works, _units, _stock, _view,
		CivilianState.NO_TILE, {"timber": 4}, {"circular_saw": true}
	)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Terrain caps"))


func test_one_crew_per_tile() -> void:
	var first := _add("builder", field_Fixture.TIMBER_TILE)
	var second := _add("builder", field_Fixture.TIMBER_TILE)
	assert_true(bool(CivilianWork.assign(
		field__model, first, "build_improvement", field__works, _units, _stock, _view
	)["ok"]))
	var check: Dictionary = CivilianWork.validate(
		field__model, second, "build_improvement", field__works, _units, _stock, _view
	)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("already working this tile"))


func test_work_needs_materials_in_the_stockpile() -> void:
	var builder := _add("builder", field_Fixture.IRON_TILE)
	field__works.set_prospected(0, field__model, field_Fixture.IRON_TILE)
	_stock = {"lumber": 0, "castIron": 0}
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Stores are short of"))
	assert_true(String(check["reason"]).contains("lumber"))


func test_engineer_builds_one_road_per_tile() -> void:
	var engineer := _add("engineer", Vector2i(0, 1))
	var check: Dictionary = _validate(engineer, "build_road")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(check["cost"], {"lumber": 1, "castIron": 1})
	CivilianWork.assign(field__model, engineer, "build_road", field__works, _units, _stock, _view)
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_eq(field__works.transport_at(field__model, Vector2i(0, 1)), LandWorks.TRANSPORT_ROAD)
	var again: Dictionary = _validate(engineer, "build_road")
	assert_false(bool(again["ok"]))
	assert_true(String(again["reason"]).contains("already has a road"))


func test_road_construction_raises_a_road_to_level_two() -> void:
	var tile := Vector2i(0, 1)
	field__works.set_transport(field__model, tile, LandWorks.TRANSPORT_ROAD)
	var engineer := _add("engineer", tile)
	var locked: Dictionary = _validate(engineer, "build_road")
	assert_false(bool(locked["ok"]))
	assert_true(String(locked["reason"]).contains("already has a road"))
	var tech := {"road_construction": true}
	var check: Dictionary = _validate(engineer, "build_road", tech)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), CivilianTransport.ROAD_TURNS)
	assert_true(bool(CivilianWork.assign(
		field__model, engineer, "build_road", field__works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech
	)["ok"]))
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_eq(field__works.transport_at(field__model, tile), LandWorks.TRANSPORT_IMPROVED_ROAD)
	var capped: Dictionary = _validate(engineer, "build_road", tech)
	assert_false(bool(capped["ok"]))
	assert_true(String(capped["reason"]).contains("improved road"))


func test_rail_builder_lays_rail_on_a_road() -> void:
	var tile := Vector2i(0, 1)
	field__works.set_transport(field__model, tile, LandWorks.TRANSPORT_ROAD)
	var rail := _add("rail_builder", tile)
	var locked: Dictionary = _validate(rail, "build_rail")
	assert_false(bool(locked["ok"]))
	assert_true(String(locked["reason"]).contains("Early Steam Engine"))
	var tech := {"early_steam_engine": true}
	var check: Dictionary = _validate(rail, "build_rail", tech)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(check["cost"], {"lumber": 2, "steel": 2})
	assert_eq(int(check["duration"]), CivilianTransport.RAIL_TURNS)
	assert_true(bool(CivilianWork.assign(
		field__model, rail, "build_rail", field__works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech
	)["ok"]))
	assert_eq(int(_stock["steel"]), 6)
	var first: Array[Dictionary] = CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_false(bool(first[0]["completed"]))
	assert_eq(field__works.transport_at(field__model, tile), LandWorks.TRANSPORT_ROAD)
	var second: Array[Dictionary] = CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_true(bool(second[0]["completed"]))
	assert_eq(field__works.transport_at(field__model, tile), LandWorks.TRANSPORT_RAIL)


func test_rail_needs_an_existing_road_and_an_unrailed_tile() -> void:
	var tile := Vector2i(0, 1)
	var rail := _add("rail_builder", tile)
	var tech := {"early_steam_engine": true}
	var no_road: Dictionary = _validate(rail, "build_rail", tech)
	assert_false(bool(no_road["ok"]))
	assert_true(String(no_road["reason"]).contains("existing road"))
	field__works.set_transport(field__model, tile, LandWorks.TRANSPORT_RAIL)
	var railed: Dictionary = _validate(rail, "build_rail", tech)
	assert_false(bool(railed["ok"]))
	assert_true(String(railed["reason"]).contains("already carries a railroad"))


func test_rail_terrain_techs_gate_hills_swamps_and_mountains() -> void:
	var tile := Vector2i(0, 1)
	var index: int = field__model.index_of(tile.x, tile.y)
	field__works.set_transport(field__model, tile, LandWorks.TRANSPORT_ROAD)
	var rail := _add("rail_builder", tile)
	var early := {"early_steam_engine": true}
	var later := {"early_steam_engine": true, "later_steam_engine": true}
	var powder := {"early_steam_engine": true, "later_steam_engine": true, "dynamite": true}
	field__model.terrain[index] = MapModel.Terrain.HILLS
	var hills_locked: Dictionary = _validate(rail, "build_rail", early)
	assert_false(bool(hills_locked["ok"]))
	assert_true(String(hills_locked["reason"]).contains("Later Steam Engine"))
	assert_true(bool(_validate(rail, "build_rail", later)["ok"]))
	field__model.terrain[index] = MapModel.Terrain.SWAMP
	assert_true(bool(_validate(rail, "build_rail", later)["ok"]))
	field__model.terrain[index] = MapModel.Terrain.MOUNTAINS
	var mountains_locked: Dictionary = _validate(rail, "build_rail", later)
	assert_false(bool(mountains_locked["ok"]))
	assert_true(String(mountains_locked["reason"]).contains("Dynamite"))
	assert_true(bool(_validate(rail, "build_rail", powder)["ok"]))
	field__model.terrain[index] = MapModel.Terrain.HARDWOOD_FOREST
	assert_true(bool(_validate(rail, "build_rail", early)["ok"]), "forest is flat ground")


func test_rail_builders_are_exempt_from_tile_exclusivity() -> void:
	var tile := Vector2i(0, 1)
	field__works.set_transport(field__model, tile, LandWorks.TRANSPORT_ROAD)
	var first := _add("rail_builder", tile)
	var second := _add("rail_builder", tile)
	var tech := {"early_steam_engine": true}
	assert_true(bool(CivilianWork.assign(
		field__model, first, "build_rail", field__works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech
	)["ok"]))
	assert_true(bool(_validate(second, "build_rail", tech)["ok"]))


## A Rail Builder's work never claims the tile: only Builder, Engineer and
## Merchant work is exclusive (wiki: civilian-units § Per-player tile
## exclusivity).
func test_a_working_rail_builder_does_not_claim_the_tile() -> void:
	var tile: Vector2i = field_Fixture.TIMBER_TILE
	field__works.set_transport(field__model, tile, LandWorks.TRANSPORT_ROAD)
	var rail := _add("rail_builder", tile)
	var tech := {"early_steam_engine": true}
	assert_true(bool(CivilianWork.assign(
		field__model, rail, "build_rail", field__works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech
	)["ok"]))
	var builder := _add("builder", tile)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))


## A Spy on counter-espionage holds a province, not its town tile, so the
## Builder may still raise the town under it (wiki: civilian-units
## § Per-player tile exclusivity).
func test_a_working_spy_does_not_claim_the_town_tile() -> void:
	var province: ProvinceState = field__model.province_data(field_Fixture.PLAYER_PROVINCE)
	province.town_tile = field_Fixture.BARE_TILE
	province.town_development = 1
	var spy := _add("spy", field_Fixture.BARE_TILE)
	assert_true(bool(CivilianWork.assign(
		field__model, spy, "counter_spy", field__works, _units, _stock, _view
	)["ok"]))
	var builder := _add("builder", field_Fixture.BARE_TILE)
	var check: Dictionary = _validate(
		builder, "upgrade_town", {"national_bureaucracy": true}
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))


## Two Merchants are both bound by the rule, so the second deed on one tile is
## refused (wiki: civilian-units § Per-player tile exclusivity).
func test_a_working_merchant_claims_the_tile_against_another() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var works := LandWorks.new()
	var tile := Vector2i(3, 1)
	var first := field_Fixture.unit("merchant", tile)
	first.id = 1
	first.start_work(LandPurchase.ACTION, tile, 1)
	var second := field_Fixture.unit("merchant", tile)
	second.id = 2
	var units: Array[CivilianState] = [first, second]
	var check: Dictionary = CivilianWork.validate(
		model, second, "purchase_land", works, units, field_Fixture.stockpile(), null,
		tile, {}, {}, {"treasury": 5000, "diplomacy": field_Fixture.merchant_court()}
	)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Another crew"))


func test_engineer_builds_a_port_only_on_the_coast() -> void:
	var engineer := _add("engineer", field_Fixture.IRON_TILE)
	var inland: Dictionary = _validate(engineer, "build_port")
	assert_false(bool(inland["ok"]))
	assert_true(String(inland["reason"]).contains("coastal"))

	engineer.tile = field_Fixture.COAST_TILE
	var coastal: Dictionary = _validate(engineer, "build_port")
	assert_true(bool(coastal["ok"]), String(coastal.get("reason", "")))
	assert_eq(int(coastal["duration"]), CivilianTransport.PORT_TURNS)
	assert_eq(_cost_text(coastal["cost"]), "5 lumber + 5 cast iron")


func test_a_province_holds_one_port() -> void:
	var engineer := _add("engineer", field_Fixture.COAST_TILE)
	CivilianWork.assign(field__model, engineer, "build_port", field__works, _units, _stock, _view)
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_true(field__works.has_port(field__model, field_Fixture.COAST_TILE))
	var second: Dictionary = _validate(engineer, "build_port")
	assert_false(bool(second["ok"]))
	assert_true(String(second["reason"]).contains("already has a port"))


## One port per seaboard, not per province: a province facing two sea zones may
## carry a port on each (wiki: extraction-and-improvements § Port Placement).
func test_a_second_port_may_rise_on_another_seaboard() -> void:
	var model := MapModel.new()
	model.setup(5, 3)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(tile)
	for x in 5:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0 if x < 2 else 1
	var province := ProvinceState.create(
		0, "Split", tiles, Vector2(2.0, 0.5), tiles.size(), 0, true
	)
	province.town_tile = Vector2i(2, 0)
	province.town_development = 1
	model.provinces = [province]
	model.sea_zones = [
		SeaZoneState.create(0, "West", [Vector2i(0, 2), Vector2i(1, 2)], Vector2(0.5, 2.0), 2),
		SeaZoneState.create(1, "East", [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)], Vector2(3.0, 2.0), 3),
	]
	var works := LandWorks.new()
	var stock := field_Fixture.stockpile()
	var west := Vector2i(0, 1)
	var east := Vector2i(3, 1)
	assert_true(CivilianTransport.seaboards_of(model, west).has(0))
	assert_true(CivilianTransport.seaboards_of(model, east).has(1))
	var first := field_Fixture.unit("engineer", west)
	first.id = 1
	var units: Array[CivilianState] = [first]
	assert_true(bool(CivilianWork.assign(
		model, first, "build_port", works, units, stock
	)["ok"]))
	CivilianWork.resolve_turn(model, units, works)
	CivilianWork.resolve_turn(model, units, works)
	assert_true(works.has_port(model, west))
	var second := field_Fixture.unit("engineer", east)
	second.id = 2
	units.append(second)
	var check: Dictionary = CivilianWork.validate(
		model, second, "build_port", works, units, stock
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	var same: Dictionary = CivilianWork.validate(
		model, first, "build_port", works, units, stock
	)
	assert_false(bool(same["ok"]), "the same seaboard still takes one port")


func test_port_builds_take_two_turns() -> void:
	var engineer := _add("engineer", field_Fixture.COAST_TILE)
	CivilianWork.assign(field__model, engineer, "build_port", field__works, _units, _stock, _view)
	var first: Array[Dictionary] = CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_false(bool(first[0]["completed"]))
	assert_false(field__works.has_port(field__model, field_Fixture.COAST_TILE))
	var second: Array[Dictionary] = CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_true(bool(second[0]["completed"]))
	assert_true(field__works.has_port(field__model, field_Fixture.COAST_TILE))


func test_cancelling_work_returns_the_unit_to_idle() -> void:
	var builder := _add("builder", field_Fixture.IRON_TILE)
	CivilianWork.assign(field__model, builder, "build_improvement", field__works, _units, _stock, _view)
	var spent: int = 40 - int(_stock["lumber"])
	builder.cancel_work()
	assert_true(builder.is_idle())
	assert_eq(builder.work, {})
	assert_eq(40 - int(_stock["lumber"]), spent)
	assert_eq(field__works.improvement_at(field__model, field_Fixture.IRON_TILE), 0)


func test_a_type_cannot_take_another_types_work() -> void:
	var builder := _add("builder", field_Fixture.IRON_TILE)
	var check: Dictionary = _validate(builder, "explore")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("cannot explore province"))


func test_a_mine_needs_prospecting_first() -> void:
	var builder := _add("builder", field_Fixture.IRON_TILE)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("prospect"))


func test_builder_can_take_an_estate_away_from_its_tile() -> void:
	var builder := _add("builder", field_Fixture.BARE_TILE)
	var check: Dictionary = CivilianWork.validate(
		field__model, builder, "build_improvement", field__works, _units, _stock, _view,
		field_Fixture.TIMBER_TILE
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	CivilianWork.assign(
		field__model, builder, "build_improvement", field__works, _units, _stock, _view,
		field_Fixture.TIMBER_TILE
	)
	assert_eq(builder.tile, field_Fixture.TIMBER_TILE)
	assert_eq(builder.origin_tile, field_Fixture.BARE_TILE)
	assert_eq(builder.assigned_tile, field_Fixture.TIMBER_TILE)
	CivilianWork.resolve_turn(field__model, _units, field__works, _view)
	assert_eq(field__works.improvement_at(field__model, field_Fixture.TIMBER_TILE), 1)
	assert_eq(builder.origin_tile, CivilianState.NO_TILE)


func test_cancelling_a_relocated_order_returns_the_builder() -> void:
	var builder := _add("builder", field_Fixture.BARE_TILE)
	field__works.set_prospected(0, field__model, field_Fixture.IRON_TILE)
	CivilianWork.assign(
		field__model, builder, "build_improvement", field__works, _units, _stock, _view,
		field_Fixture.IRON_TILE
	)
	assert_eq(builder.tile, field_Fixture.IRON_TILE)
	builder.cancel_work()
	assert_eq(builder.tile, field_Fixture.BARE_TILE)
	assert_eq(builder.origin_tile, CivilianState.NO_TILE)
	assert_eq(field__works.improvement_at(field__model, field_Fixture.IRON_TILE), 0)


func test_busy_civilians_refuse_new_orders() -> void:
	var builder := _add("builder", field_Fixture.IRON_TILE)
	field__works.set_prospected(0, field__model, field_Fixture.IRON_TILE)
	CivilianWork.assign(field__model, builder, "build_improvement", field__works, _units, _stock, _view)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("already working"))


func test_status_stays_idle_or_working_across_the_work_pass() -> void:
	var builder := _add("builder", field_Fixture.IRON_TILE)
	CivilianWork.assign(field__model, builder, "build_improvement", field__works, _units, _stock, _view)
	for _turn in 3:
		CivilianWork.resolve_turn(field__model, _units, field__works, _view)
		assert_true(
			builder.status == CivilianState.Status.IDLE
			or builder.status == CivilianState.Status.WORKING
		)
	assert_true(builder.is_idle())


func test_options_explain_each_work_order() -> void:
	var explorer := _add("explorer", field_Fixture.TIMBER_TILE)
	var options: Array[Dictionary] = CivilianWork.options(
		field__model, explorer, field__works, _units, _stock, _view
	)
	assert_eq(options.size(), 2)
	for option: Dictionary in options:
		if String(option["action"]) == "prospect":
			assert_false(bool(option["ok"]))
			# Timber shows on the chart already, so there is nothing to read.
			assert_true(String(option["reason"]).contains("already known"))
		else:
			assert_eq(String(option["label"]), "Explore province")
			assert_eq(String(option["cost_text"]), "Free")


func test_idle_units_produce_no_reports() -> void:
	_add("builder", field_Fixture.IRON_TILE)
	assert_eq(CivilianWork.resolve_turn(field__model, _units, field__works, _view), [])


# --- merchant land purchase and tile deeds ----------------------------------
## Wiki: civilian-units § Merchant. A Merchant buys a resource tile in a Minor
## Nation or Tribe province, with an embassy, no war and a prospected mineral.


func test_a_spy_walks_into_a_rival_great_powers_land_unchallenged() -> void:
	# Stealth: no war, no declaration, and no order needed to earn its keep
	# (wiki: civilian-units § Spy; DR-20261110-03).
	var spy := field_Fixture.unit("spy", Vector2i(2, 1))
	var moved: Dictionary = CivilianMovement.apply_move(
		field__model, spy, Vector2i(3, 1), _view
	)
	assert_true(bool(moved["ok"]), String(moved.get("reason", "")))
	assert_eq(spy.tile, Vector2i(3, 1))
	assert_false(
		CivilianMovement.may_enter(field__model, "builder", 0, Vector2i(3, 1)),
		"a builder needs crown land"
	)


func test_merchant_may_enter_foreign_land_but_a_builder_may_not() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var merchant := field_Fixture.unit("merchant", Vector2i(1, 1))
	assert_true(bool(CivilianMovement.apply_move(
		model, merchant, Vector2i(2, 1)
	)["ok"]))
	var builder := field_Fixture.unit("builder", Vector2i(1, 1))
	assert_false(CivilianMovement.may_enter(model, "builder", 0, Vector2i(2, 1)))


func test_purchase_land_prices_at_fifteen_times_the_base_price() -> void:
	var model: MapModel = field_Fixture.build_minor()
	assert_eq(LandPurchase.cost(model, Vector2i(3, 1)), 750, "grain")
	assert_eq(LandPurchase.cost(model, Vector2i(2, 1)), 1200, "iron")
	assert_eq(LandPurchase.cost_text(model, Vector2i(3, 1)), "£750")


func test_merchant_purchase_needs_embassy_and_a_clear_sale() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var works := LandWorks.new()
	var merchant := field_Fixture.unit("merchant", Vector2i(1, 1))
	var units: Array[CivilianState] = [merchant]
	var stock := field_Fixture.stockpile()
	var tile := Vector2i(3, 1)
	var no_court := DiplomacyState.new()
	no_court.initialize(1)
	no_court.ensure_relation(0, 6, 1)
	var refused: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, stock, null, tile,
		{}, {}, {"treasury": 5000, "diplomacy": no_court}
	)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("embassy"))
	var court := field_Fixture.merchant_court()
	DiplomacyRules.declare_war(court, 0, 6)
	var war: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, stock, null, tile,
		{}, {}, {"treasury": 5000, "diplomacy": court}
	)
	assert_false(bool(war["ok"]))
	assert_true(String(war["reason"]).contains("war"))
	var poor := field_Fixture.merchant_court()
	var cheap: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, stock, null, tile,
		{}, {}, {"treasury": 749, "diplomacy": poor}
	)
	assert_false(bool(cheap["ok"]))
	assert_true(String(cheap["reason"]).contains("treasury"))


func test_minerals_must_be_prospected_before_purchase() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var works := LandWorks.new()
	var merchant := field_Fixture.unit("merchant", Vector2i(1, 1))
	var units: Array[CivilianState] = [merchant]
	var iron := Vector2i(2, 1)
	var context: Dictionary = {"treasury": 5000, "diplomacy": field_Fixture.merchant_court()}
	var blocked: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, field_Fixture.stockpile(), null,
		iron, {}, {}, context
	)
	assert_false(bool(blocked["ok"]))
	assert_true(String(blocked["reason"]).contains("prospect"))
	works.set_prospected(0, model, iron)
	var allowed: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, field_Fixture.stockpile(), null,
		iron, {}, {}, context
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))


## A boycott bars the deed: the boycotted crown may not buy land from a Tribe
## the issuing crown colonised (wiki: diplomacy § GP–Tribe — Boycott, R6).
func test_a_boycott_bars_the_deed_to_a_colonys_land() -> void:
	var model: MapModel = field_Fixture.build_minor()
	model.provinces[1].owner = FALSE_COLONY_TRIBE
	var court := DiplomacyState.new()
	court.initialize(1)
	court.ensure_relation(0, FALSE_COLONY_TRIBE, 1)
	court.set_overture(0, FALSE_COLONY_TRIBE, DiplomacyCatalog.STAGE_EMBASSY)
	court.set_colony(FALSE_COLONY_TRIBE, BOYCOTT_ISSUER)
	court.ensure_relation(BOYCOTT_ISSUER, 0, 1)
	assert_true(bool(DiplomacyTrade.boycott(court, BOYCOTT_ISSUER, 0)["ok"]))
	var works := LandWorks.new()
	var merchant := field_Fixture.unit("merchant", Vector2i(1, 1))
	var units: Array[CivilianState] = [merchant]
	var tile := Vector2i(3, 1)
	var context: Dictionary = {"treasury": 5000, "diplomacy": court}
	var refused: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, field_Fixture.stockpile(), null,
		tile, {}, {}, context
	)
	assert_false(bool(refused["ok"]), "a boycott bars trade with that colony")
	assert_true(String(refused["reason"]).contains("boycott"))
	# Lifting the boycott opens the deed again: the gate is the pair, not the tile.
	court.end_turn()
	assert_true(bool(DiplomacyTrade.revoke_boycott(court, BOYCOTT_ISSUER, 0)["ok"]))
	var allowed: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, field_Fixture.stockpile(), null,
		tile, {}, {}, context
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))


func test_purchase_completes_one_turn_later_and_debits_the_purse() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var works := LandWorks.new()
	var merchant := field_Fixture.unit("merchant", Vector2i(1, 1))
	var units: Array[CivilianState] = [merchant]
	var tile := Vector2i(3, 1)
	var context: Dictionary = {"treasury": 5000, "diplomacy": field_Fixture.merchant_court()}
	var check: Dictionary = CivilianWork.assign(
		model, merchant, "purchase_land", works, units, field_Fixture.stockpile(), null,
		tile, {}, {}, context
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(context["treasury"]), 5000, "assign does not debit")
	var economy := PlayerEconomy.starting()
	economy.treasury = 5000
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		model, units, works, null, economy
	)
	assert_true(bool(reports[0]["completed"]))
	assert_eq(economy.treasury, 4250, "price is debited at completion")
	assert_true(model.is_purchased_tile(tile))
	assert_eq(model.owner_at(tile.x, tile.y), 0, "tile changes hands")
	assert_eq(model.province_owner(1), 6, "the province stays Genoese")
	assert_false(model.purchase_tile(tile, 7), "one deed per tile")


# --- a deed develops the seller's town (DR-20261112-01, fixture path) --------
## Main's `_deed_world` suite owns the rule table; this path checks the same
## growth against `field_Fixture.build_minor` and the manufacture projection.


func _sign_deed(model: MapModel, tile: Vector2i, treasury: int = 5000) -> Dictionary:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	var report: Dictionary = {}
	assert_true(LandPurchase.complete(model, tile, 0, economy, report), "the deed is signed")
	return report


func test_a_deed_raises_the_minors_town() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var province: ProvinceState = model.province_data(1)
	assert_eq(province.town_level(), 1, "a Minor's town starts at level 1")
	var report: Dictionary = _sign_deed(model, Vector2i(3, 1))
	assert_eq(province.town_development, 2, "one deed lifts the town")
	assert_true(
		MinorTownGrowth.deed_line(
			model, province, "Genoa", int(report.get("town_level", 0))
		).ends_with("The town rises to level 2."),
		"the report names it"
	)


func test_each_deed_raises_the_town_until_it_tops_out() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var province: ProvinceState = model.province_data(1)
	for tile: Vector2i in [Vector2i(3, 0), Vector2i(2, 2), Vector2i(3, 2)]:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	_sign_deed(model, Vector2i(3, 1))
	_sign_deed(model, Vector2i(2, 1))
	assert_eq(province.town_level(), 3, "two deeds")
	_sign_deed(model, Vector2i(3, 0))
	assert_eq(province.town_level(), 4, "three deeds")
	_sign_deed(model, Vector2i(2, 2))
	assert_eq(province.town_level(), 4, "a fourth deed changes nothing")
	assert_eq(MinorTownGrowth.apply(model, province), 0, "no further rise")


func test_a_lost_deed_never_lowers_the_town() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var province: ProvinceState = model.province_data(1)
	province.town_development = 3
	var report: Dictionary = _sign_deed(model, Vector2i(3, 1))
	assert_eq(province.town_level(), 3, "a town above its deed level keeps it")
	assert_false(
		MinorTownGrowth.deed_line(
			model, province, "Genoa", int(report.get("town_level", 0))
		).contains("town"),
		"nothing to announce"
	)


func test_a_great_power_province_never_grows_this_way() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var province: ProvinceState = model.province_data(0)
	model.resource[model.index_of(0, 1)] = 0
	_sign_deed(model, Vector2i(0, 1))
	assert_eq(province.town_development, 0, "a crown's own town is its Builder's work")
	assert_eq(MinorTownGrowth.apply(model, province), 0)


func test_a_deed_turns_the_minors_harvest_into_manufactures() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var province: ProvinceState = model.province_data(1)
	for tile: Vector2i in province.tiles:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	assert_true(
		MinorMarket.province_manufactures(model, province).is_empty(),
		"a level-1 town pays no bonus"
	)
	_sign_deed(model, Vector2i(3, 1))
	assert_eq(
		MinorMarket.province_manufactures(model, province), {"lumber": 1, "paper": 1},
		"four timber estates feed the level-2 town"
	)


func test_a_purchased_tile_becomes_an_owned_estate() -> void:
	var model: MapModel = field_Fixture.build()
	var works := LandWorks.new()
	var tile := field_Fixture.RIVAL_GRAIN_TILE
	assert_true(model.purchase_tile(tile, 0))
	assert_eq(model.owner_at(tile.x, tile.y), 0)
	assert_false(model.purchase_tile(tile, 1), "no second buyer")
	works.set_improvement(model, tile, 1)
	works.set_prospected(0, model, field_Fixture.IRON_TILE)
	for step: Vector2i in [Vector2i(1, 0), Vector2i(2, 0), tile]:
		works.set_transport(model, step, LandWorks.TRANSPORT_ROAD)
	var totals: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, field_Fixture.BARE_TILE
	)
	assert_eq(totals, {"grain": 1}, "the deed yields for its buyer")
	var seller: Dictionary = Extraction.yields(
		model, 1, -1, {}, works, field_Fixture.BARE_TILE
	)
	assert_eq(seller, {}, "the old owner no longer extracts it")
	var snap: Dictionary = ImprovementLedger.snapshot(
		model, works, [], {}, 0, field_Fixture.BARE_TILE
	)
	assert_eq(
		int(snap["counts"]["estates"]), 3, "the enclave joins the realm's two estates"
	)
	assert_eq(String(_row_at(snap, tile)["province_name"]), "Coro")


func _add(type_id: String, tile: Vector2i) -> CivilianState:
	var unit := field_Fixture.unit(type_id, tile)
	unit.id = _units.size() + 1
	_units.append(unit)
	return unit


func _validate(
	unit: CivilianState, action: String, tech_unlocked: Dictionary = {}
) -> Dictionary:
	return CivilianWork.validate(
		field__model, unit, action, field__works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech_unlocked
	)


func _cost_text(cost: Dictionary) -> String:
	return CivilianWork.cost_text(cost)

# --- from test_improvement_system.gd ---
## Improvement catalog, connectivity, extraction and the estates ledger
## (wiki: extraction-and-improvements, capital-and-connectivity).

func test_catalog_names_follow_the_resource_not_the_level() -> void:
	assert_eq(ImprovementCatalog.base_name(0), "Lumber camp")
	assert_eq(ImprovementCatalog.base_name(1), "Mine")
	assert_eq(ImprovementCatalog.base_name(4), "Farm")
	assert_eq(ImprovementCatalog.base_name(5), "Pasture")
	assert_eq(ImprovementCatalog.base_name(6), "Ranch")
	assert_eq(ImprovementCatalog.display_name(4, 0), "Farm")
	assert_eq(ImprovementCatalog.display_name(4, 3), "Farm (L3)")
	assert_eq(ImprovementCatalog.display_name(-1, 2), "Improvement (L2)")


func test_catalog_maps_resources_to_commodities_and_yield() -> void:
	assert_eq(ImprovementCatalog.commodity(0), "timber")
	assert_eq(ImprovementCatalog.commodity(1), "iron")
	assert_eq(ImprovementCatalog.commodity(4), "grain")
	assert_eq(ImprovementCatalog.yield_for(0, 3), {"timber": 3})
	assert_eq(ImprovementCatalog.yield_for(0, 0), {})
	assert_eq(ImprovementCatalog.production(9), ImprovementCatalog.MAX_LEVEL)
	assert_true(ImprovementCatalog.needs_prospecting(1))
	assert_false(ImprovementCatalog.needs_prospecting(0))


func test_capital_tile_and_its_neighbours_are_connected() -> void:
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		field__model, field__works, 0, field_Fixture.BARE_TILE
	)
	assert_true(connected.has(field__model.index_of(0, 0)))
	assert_true(connected.has(field__model.index_of(0, 1)))
	assert_true(connected.has(field__model.index_of(1, 0)))
	assert_false(connected.has(field__model.index_of(2, 2)))


func test_roads_extend_connectivity_beyond_the_capital() -> void:
	field__works.set_transport(field__model, Vector2i(1, 0), LandWorks.TRANSPORT_ROAD)
	field__works.set_transport(field__model, Vector2i(2, 0), LandWorks.TRANSPORT_ROAD)
	field__works.set_transport(field__model, Vector2i(2, 1), LandWorks.TRANSPORT_ROAD)
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		field__model, field__works, 0, field_Fixture.BARE_TILE
	)
	assert_true(connected.has(field__model.index_of(2, 1)))
	assert_true(connected.has(field__model.index_of(2, 2)))
	assert_false(connected.has(field__model.index_of(3, 1)))


func test_a_built_port_seeds_its_province() -> void:
	field__works.add_port(field__model, field_Fixture.COAST_TILE)
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		field__model, field__works, 0, field_Fixture.BARE_TILE
	)
	assert_true(connected.has(field__model.index_of(1, 3)))
	assert_true(connected.has(field__model.index_of(1, 2)))
	assert_eq(ImprovementSystem.town_tile(field__model, field__works, 0, field_Fixture.BARE_TILE), field_Fixture.BARE_TILE)
	assert_eq(ImprovementSystem.town_tile(field__model, field__works, 1, field_Fixture.BARE_TILE), Vector2i(-1, -1))


func test_disconnected_improvements_do_not_yield() -> void:
	field__works.set_improvement(field__model, field_Fixture.TIMBER_TILE, 1)
	var totals: Dictionary = Extraction.yields(
		field__model, 0, -1, {}, field__works, field_Fixture.BARE_TILE
	)
	assert_eq(totals, {})
	assert_eq(int(_stock["lumber"]), 40)


func test_connected_improvements_yield_their_commodity() -> void:
	field__works.set_transport(field__model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	field__works.set_improvement(field__model, field_Fixture.TIMBER_TILE, 1)
	var totals: Dictionary = Extraction.yields(
		field__model, 0, -1, {}, field__works, field_Fixture.BARE_TILE
	)
	assert_eq(totals, {"timber": 1})
	assert_eq(int(_stock["lumber"]), 40)
	assert_eq(ImprovementSystem.output_text({"timber": 2, "grain": 1}), "1 grain · 2 timber")


func test_tech_and_transport_caps_limit_the_yield() -> void:
	assert_eq(ImprovementCatalog.effective_yield(0, 1, {}, 1, 4), 1)
	assert_eq(ImprovementCatalog.effective_yield(0, 4, {"timber": 4}, 1, 4), 1)
	assert_eq(ImprovementCatalog.effective_yield(0, 4, {"timber": 4}, 4, 4), 4)
	assert_eq(ImprovementCatalog.effective_yield(0, 0, {}, 4, 4), 0)


func test_minerals_must_be_prospected_to_yield() -> void:
	field__works.set_transport(field__model, Vector2i(1, 0), LandWorks.TRANSPORT_ROAD)
	field__works.set_improvement(field__model, field_Fixture.IRON_TILE, 1)
	var blocked: Dictionary = Extraction.yields(
		field__model, 0, -1, {}, field__works, field_Fixture.BARE_TILE
	)
	assert_eq(blocked, {})
	field__works.set_prospected(0, field__model, field_Fixture.IRON_TILE)
	var totals: Dictionary = Extraction.yields(
		field__model, 0, -1, {}, field__works, field_Fixture.BARE_TILE
	)
	assert_eq(totals, {"iron": 1})


func test_foreign_estates_never_pay_the_player() -> void:
	field__works.set_improvement(field__model, field_Fixture.RIVAL_GRAIN_TILE, 3)
	var totals: Dictionary = Extraction.yields(
		field__model, 0, -1, {}, field__works, field_Fixture.BARE_TILE
	)
	assert_eq(totals, {})


## A colony's estates beside its port town are Town-rule connected, so the town's
## own development level caps their yield (wiki: extraction-and-improvements
## § Extraction formula and town development cap).
func test_a_port_town_caps_the_estates_beside_it() -> void:
	var offshoot: Array = _overseas_estate(2, true)
	var model: MapModel = offshoot[0]
	var works: LandWorks = offshoot[1]
	var totals: Dictionary = Extraction.yields(
		model, 0, -1, {"grain": 4}, works, Vector2i(-1, -1)
	)
	assert_eq(totals, {"grain": 2})


## A rail from the landfall lifts the cap: the estate then reaches the crown by
## road, so town development does not limit it.
func test_a_colony_road_lifts_the_town_cap() -> void:
	var offshoot: Array = _overseas_estate(2, true)
	var model: MapModel = offshoot[0]
	var works: LandWorks = offshoot[1]
	works.set_transport(model, Vector2i(0, 1), LandWorks.TRANSPORT_RAIL)
	var totals: Dictionary = Extraction.yields(
		model, 0, -1, {"grain": 4}, works, Vector2i(-1, -1)
	)
	assert_eq(totals, {"grain": 4})


## An inland town caps nothing: only a port town beside the crown's sea path
## limits its neighbours.
func test_an_inland_town_does_not_cap_the_yield() -> void:
	var offshoot: Array = _overseas_estate(2, false)
	var model: MapModel = offshoot[0]
	var works: LandWorks = offshoot[1]
	var resolved: Dictionary = LandConnectivity.resolve(model, works, 0, Vector2i(-1, -1))
	assert_eq(
		LandConnectivity.town_cap_for(model, resolved, 0, model.index_of(0, 1)),
		LandWorks.MAX_IMPROVEMENT
	)


## One colony province: a town at (0,0) and a level-4 grain estate beside it.
## `port` builds the town's harbour; `development` is the town's level.
func _overseas_estate(development: int, port: bool) -> Array:
	var model := MapModel.new()
	model.setup(2, 2)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 2:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(tile)
			if tile != Vector2i(0, 0):
				model.resource[model.index_of(x, y)] = 4
	var province := ProvinceState.create(0, "Colonia", tiles, Vector2(0.5, 0.5), 4, 0, false)
	province.town_tile = Vector2i(0, 0)
	province.town_development = development
	model.provinces = [province]
	var works := LandWorks.new()
	if port:
		works.add_port(model, Vector2i(0, 0))
	works.set_improvement(model, Vector2i(0, 1), 4)
	return [model, works]


func test_ledger_snapshot_exposes_status_and_actions() -> void:
	field__works.set_transport(field__model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	field__works.set_transport(field__model, field_Fixture.TIMBER_TILE, LandWorks.TRANSPORT_RAIL)
	field__works.set_improvement(field__model, field_Fixture.TIMBER_TILE, 2)
	field__works.set_improvement(field__model, field_Fixture.IRON_TILE, 1)
	field__works.set_prospected(0, field__model, field_Fixture.IRON_TILE)
	var builder := field_Fixture.unit("builder", field_Fixture.BARE_TILE)
	builder.id = 1
	_units.append(builder)
	var snap: Dictionary = ImprovementLedger.snapshot(
		field__model, field__works, _units, _stock, 0, field_Fixture.BARE_TILE, {"timber": 4}
	)
	var counts: Dictionary = snap["counts"]
	assert_eq(int(counts["estates"]), 2)
	assert_eq(int(counts["improved"]), 2)
	assert_eq(int(counts["producing"]), 2)
	assert_eq(int(counts["idle_builders"]), 1)
	assert_eq(snap["totals"], {"timber": 1, "iron": 1})
	var timber: Dictionary = _row_at(snap, field_Fixture.TIMBER_TILE)
	assert_eq(String(timber["name"]), "Lumber camp (L2)")
	assert_eq(String(timber["status"]), "producing")
	assert_true(bool(timber["can_build"]))
	assert_eq(int(timber["output"]), 1)
	assert_true(String(timber["status_text"]).contains("transport cap 1"))
	var iron: Dictionary = _row_at(snap, field_Fixture.IRON_TILE)
	assert_eq(String(iron["status"]), "producing")
	assert_false(bool(iron["can_build"]))
	assert_true(String(iron["build_reason"]).contains("tech"))


func test_upgrades_above_the_tech_cap_are_refused() -> void:
	field__works.set_transport(field__model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	field__works.set_improvement(field__model, field_Fixture.TIMBER_TILE, 1)
	var builder := field_Fixture.unit("builder", field_Fixture.BARE_TILE)
	builder.id = 1
	_units.append(builder)
	var snap: Dictionary = ImprovementLedger.snapshot(
		field__model, field__works, _units, _stock, 0, field_Fixture.BARE_TILE
	)
	var row: Dictionary = _row_at(snap, field_Fixture.TIMBER_TILE)
	assert_true(bool(row["tech_limited"]))
	assert_eq(int(row["tech_cap"]), 1)
	assert_false(bool(row["can_build"]))
	assert_true(String(row["build_reason"]).contains("tech"))
	assert_eq(int(row["output"]), 1)


func test_researched_techs_let_build_orders_pass_the_cap() -> void:
	field__works.set_transport(field__model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	field__works.set_improvement(field__model, field_Fixture.TIMBER_TILE, 1)
	var builder := field_Fixture.unit("builder", field_Fixture.BARE_TILE)
	builder.id = 1
	_units.append(builder)
	var refused: Dictionary = ImprovementOrders.build(
		field__model, _units, field__works, _stock, null, 0, field_Fixture.TIMBER_TILE
	)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["message"]).contains("tech"))
	var caps: Dictionary = TechCatalog.extraction_caps({"saw_mill": true})
	assert_eq(int(caps["timber"]), 2)
	var allowed: Dictionary = ImprovementOrders.build(
		field__model, _units, field__works, _stock, null, 0, field_Fixture.TIMBER_TILE, caps
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("message", "")))
	assert_true(builder.is_working())


func test_ledger_surfaces_an_active_build_and_cancel() -> void:
	var builder := field_Fixture.unit("builder", field_Fixture.TIMBER_TILE)
	builder.id = 1
	_units.append(builder)
	assert_true(bool(CivilianWork.assign(
		field__model, builder, "build_improvement", field__works, _units, _stock, null,
		field_Fixture.TIMBER_TILE
	)["ok"]))
	var snap: Dictionary = ImprovementLedger.snapshot(
		field__model, field__works, _units, _stock, 0, field_Fixture.BARE_TILE
	)
	var row: Dictionary = _row_at(snap, field_Fixture.TIMBER_TILE)
	assert_eq(String(row["status"]), "building")
	assert_true(bool(row["working"]))
	assert_false(bool(row["can_build"]))
	assert_true(String(row["status_text"]).contains("1 turn"))
	var cancelled: Dictionary = ImprovementOrders.cancel(field__model, _units, 0, field_Fixture.TIMBER_TILE)
	assert_true(bool(cancelled["ok"]))
	assert_true(builder.is_idle())


func test_build_orders_pick_the_nearest_builder() -> void:
	var far := field_Fixture.unit("builder", Vector2i(2, 2))
	far.id = 9
	var near := field_Fixture.unit("builder", Vector2i(1, 1))
	near.id = 3
	_units = [far, near]
	assert_eq(ImprovementOrders.nearest_builder(_units, 0, field_Fixture.TIMBER_TILE), near)
	var result: Dictionary = ImprovementOrders.build(
		field__model, _units, field__works, _stock, null, 0, field_Fixture.TIMBER_TILE
	)
	assert_true(bool(result["ok"]), String(result.get("message", "")))
	assert_eq(near.tile, field_Fixture.TIMBER_TILE)
	assert_true(near.is_working())
	assert_eq(int(_stock["lumber"]), 39)


func test_build_orders_report_when_no_builder_is_free() -> void:
	var result: Dictionary = ImprovementOrders.build(
		field__model, _units, field__works, _stock, null, 0, field_Fixture.TIMBER_TILE
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["message"]).contains("No idle Builder"))


func test_short_inputs_explain_missing_materials() -> void:
	var short: Dictionary = ImprovementSystem.short_inputs(
		{"lumber": 4, "castIron": 4}, {"lumber": 1, "castIron": 9}
	)
	assert_eq(short, {"lumber": 4})


# --- crews caught by a province changing hands ---


func test_a_stranded_builder_withdraws_to_its_crowns_land() -> void:
	var builder := field_Fixture.unit("builder", Vector2i(2, 1), 1)
	var roster: Array[CivilianState] = [builder]

	var reports: Array[Dictionary] = CivilianStranding.withdraw(field__model, roster)

	assert_eq(roster.size(), 1, "the crew survives")
	assert_eq(builder.tile, Vector2i(3, 1), "withdraws onto its own province")
	assert_false(bool(reports[0]["lost"]))
	assert_eq(Vector2i(reports[0]["from"]), Vector2i(2, 1))


func test_a_surrounded_crew_is_lost_with_the_province() -> void:
	var engineer := field_Fixture.unit("engineer", Vector2i(0, 0), 1)
	var roster: Array[CivilianState] = [engineer]

	var reports: Array[Dictionary] = CivilianStranding.withdraw(field__model, roster)

	assert_eq(roster.size(), 0, "nowhere legal to stand")
	assert_true(bool(reports[0]["lost"]))


func test_explorers_are_never_evicted_from_foreign_land() -> void:
	var explorer := field_Fixture.unit("explorer", Vector2i(2, 1), 1)
	var roster: Array[CivilianState] = [explorer]

	var reports: Array[Dictionary] = CivilianStranding.withdraw(field__model, roster)

	assert_eq(roster.size(), 1)
	assert_eq(explorer.tile, Vector2i(2, 1))
	assert_true(reports.is_empty())


func test_a_withdrawn_crew_drops_the_work_it_can_no_longer_do() -> void:
	var builder := field_Fixture.unit("builder", Vector2i(2, 1), 1)
	builder.start_work("build_improvement", Vector2i(2, 1), 2)
	var roster: Array[CivilianState] = [builder]

	CivilianStranding.withdraw(field__model, roster)

	assert_eq(builder.tile, Vector2i(3, 1))
	assert_false(builder.is_working(), "the lost tile's order ends")


func test_a_crew_on_its_own_land_is_left_alone() -> void:
	var builder := field_Fixture.unit("builder", Vector2i(0, 1), 0)
	var roster: Array[CivilianState] = [builder]

	var reports: Array[Dictionary] = CivilianStranding.withdraw(field__model, roster)

	assert_eq(builder.tile, Vector2i(0, 1))
	assert_true(reports.is_empty())


func test_withdraw_without_a_map_touches_nothing() -> void:
	var builder := field_Fixture.unit("builder", Vector2i(2, 1), 1)
	var roster: Array[CivilianState] = [builder]

	assert_true(CivilianStranding.withdraw(null, roster).is_empty())
	assert_eq(roster.size(), 1)
	assert_eq(builder.tile, Vector2i(2, 1))


func test_an_embarked_crew_is_never_evicted() -> void:
	var builder := field_Fixture.unit("builder", Vector2i(2, 1), 1)
	builder.embark_on(7)
	var roster: Array[CivilianState] = [builder]

	var reports: Array[Dictionary] = CivilianStranding.withdraw(field__model, roster)

	assert_eq(roster.size(), 1, "a passenger is off the map, not stranded")
	assert_true(builder.is_embarked())
	assert_true(reports.is_empty())


func _row_at(snap: Dictionary, tile: Vector2i) -> Dictionary:
	for row: Dictionary in snap["estates"]:
		if Vector2i(row["tile"]) == tile:
			return row
	return {}

# --- from test_civilian_roster.gd ---------------------------------------------
## Whole-empire roster view-model: region/province grouping, filters and status.
## Kept in this suite so the civilian domain pays one Godot boot (docs/testing.md).

func test_roster_snapshot_spans_both_regions_and_ignores_rivals() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_roster_world(), _roster_regions(), 0
	)
	assert_eq(int(snapshot["total"]), 5)
	assert_eq(int(snapshot["by_region"][FactionCatalog.OLD_WORLD]), 3)
	assert_eq(int(snapshot["by_region"][FactionCatalog.NEW_WORLD]), 2)
	assert_eq(int(snapshot["idle"]), 4)
	assert_eq(int(snapshot["working"]), 1)
	assert_eq(int(snapshot["by_type"]["merchant"]), 1)
	assert_eq((snapshot["groups"] as Array).size(), 2, "one posting per region")


func test_roster_region_filter_narrows_to_one_world() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_roster_world(), _roster_regions(), 0
	)
	assert_eq(CivilianRoster.count(snapshot, LedgerRows.REGION_ALL), 5)
	assert_eq(CivilianRoster.count(snapshot, LedgerRows.REGION_OLD), 3)
	assert_eq(CivilianRoster.count(snapshot, LedgerRows.REGION_NEW), 2)
	for group: Dictionary in CivilianRoster.groups(snapshot, LedgerRows.REGION_NEW):
		assert_eq(int(group["region"]), FactionCatalog.NEW_WORLD)


func test_roster_craft_filter_and_chip_counts() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_roster_world(), _roster_regions(), 0
	)
	assert_eq(CivilianRoster.count(snapshot, LedgerRows.REGION_ALL, "merchant"), 1)
	assert_eq(CivilianRoster.count(snapshot, LedgerRows.REGION_OLD, "merchant"), 0)
	var counts: Dictionary = CivilianRoster.type_counts(snapshot, LedgerRows.REGION_OLD)
	assert_eq(int(counts["explorer"]), 1)
	assert_eq(int(counts["builder"]), 1)
	assert_eq(int(counts["merchant"]), 0)


func test_roster_rows_carry_posting_and_work_status() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_roster_world(), _roster_regions(), 0
	)
	var merchant: Dictionary = _row_of_type(snapshot, "merchant")
	assert_eq(String(merchant["province_name"]), "Veracruz")
	assert_eq(int(merchant["region"]), FactionCatalog.NEW_WORLD)
	assert_true(String(merchant["status_text"]).contains("Build improvement"))
	assert_true(String(merchant["status_text"]).contains("2 turns to go"))
	assert_almost_eq(float(merchant["progress"]), 0.0, 0.001)
	var explorer: Dictionary = _row_of_type(snapshot, "explorer")
	assert_eq(String(explorer["status_text"]), "Idle — ready for orders")


func test_roster_status_filter_reads_who_waits_for_orders() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_roster_world(), _roster_regions(), 0
	)
	assert_eq(
		CivilianRoster.count(snapshot, LedgerRows.REGION_ALL, "", CivilianRoster.STATUS_IDLE),
		4,
		"four crews have no order",
	)
	assert_eq(
		CivilianRoster.count(
			snapshot, LedgerRows.REGION_ALL, "", CivilianRoster.STATUS_WORKING
		),
		1,
	)
	for group: Dictionary in CivilianRoster.groups(
		snapshot, LedgerRows.REGION_ALL, "", CivilianRoster.STATUS_WORKING
	):
		for row: Dictionary in group["rows"]:
			assert_true(bool(row["working"]), "only a working crew answers the at-work view")
	assert_eq(
		CivilianRoster.count(
			snapshot, LedgerRows.REGION_OLD, "", CivilianRoster.STATUS_WORKING
		),
		0,
		"the Old World column has no work running",
	)
	assert_eq(
		CivilianRoster.count(
			snapshot, LedgerRows.REGION_OLD, "", CivilianRoster.STATUS_IDLE
		),
		3,
		"the status reads against the world filter, not beside it",
	)
	assert_eq(
		CivilianRoster.count(
			snapshot, LedgerRows.REGION_ALL, "merchant", CivilianRoster.STATUS_IDLE
		),
		0,
		"the merchant is at work, so the idle craft view is empty",
	)


func test_roster_status_and_craft_tallies_agree_with_the_other_filters() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_roster_world(), _roster_regions(), 0
	)
	var counts: Dictionary = CivilianRoster.status_counts(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(counts[CivilianRoster.STATUS_ALL]), 5)
	assert_eq(int(counts[CivilianRoster.STATUS_IDLE]), 4)
	assert_eq(int(counts[CivilianRoster.STATUS_WORKING]), 1)
	assert_eq(
		int(CivilianRoster.status_counts(snapshot, LedgerRows.REGION_NEW)[
			CivilianRoster.STATUS_WORKING
		]),
		1,
	)
	assert_eq(
		int(CivilianRoster.status_counts(snapshot, LedgerRows.REGION_ALL, "spy")[
			CivilianRoster.STATUS_IDLE
		]),
		1,
		"the idle tally counts what the craft filter leaves (the rival's spy is not ours)",
	)
	var types: Dictionary = CivilianRoster.type_counts(
		snapshot, LedgerRows.REGION_ALL, CivilianRoster.STATUS_WORKING
	)
	assert_eq(int(types["merchant"]), 1)
	assert_eq(int(types["spy"]), 0, "a craft tally follows the order filter too")
	assert_eq(CivilianRoster.status_label(CivilianRoster.STATUS_WORKING), "At work")
	assert_eq(CivilianRoster.status_label(CivilianRoster.STATUS_IDLE), "Idle")


func test_roster_empty_inputs_make_an_empty_roster() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(null, null, 0)
	assert_eq(int(snapshot["total"]), 0)
	assert_true((snapshot["groups"] as Array).is_empty())
	for type_id: String in CivilianCatalog.ORDER:
		assert_eq(int(snapshot["by_type"][type_id]), 0)


func _roster_regions() -> MapRegionTable:
	var table := MapRegionTable.new()
	var old_units: Array[CivilianState] = []
	old_units.append(_roster_unit(1, 0, "explorer", Vector2i(0, 0)))
	old_units.append(_roster_unit(2, 0, "builder", Vector2i(0, 2)))
	old_units.append(_roster_unit(3, 0, "spy", Vector2i(1, 1)))
	old_units.append(_roster_unit(4, 1, "spy", Vector2i(2, 0)))
	table.set_region(FactionCatalog.OLD_WORLD, old_units)

	var new_units: Array[CivilianState] = []
	var merchant: CivilianState = _roster_unit(5, 0, "merchant", Vector2i(0, 0))
	merchant.start_work("build_improvement", Vector2i(0, 1), 2, Vector2i(0, 0))
	new_units.append(merchant)
	new_units.append(_roster_unit(6, 0, "rail_builder", Vector2i(0, 2)))
	table.set_region(FactionCatalog.NEW_WORLD, new_units)
	return table


func _roster_world() -> WorldMap:
	var old: MapModel = field_Fixture.build()
	var new: MapModel = field_Fixture.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	var world := WorldMap.new()
	world.add_region(old)
	world.add_region(new)
	return world


func _roster_unit(
	id: int, owner: int, type_id: String, tile: Vector2i
) -> CivilianState:
	return CivilianState.create(id, owner, type_id, tile)


func _row_of_type(snapshot: Dictionary, type_id: String) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if String(row["type_id"]) == type_id:
			return row
	return {}


# --- crown link for the province dossier ------------------------------------

## One row of owned land: Cádiz (capital at 0,0) and Coro (town at 6,0), with a
## grain estate beside the Coro town.
func _crown_link_model() -> Array:
	var model := MapModel.new()
	model.setup(7, 2)
	var home_tiles: Array[Vector2i] = []
	var far_tiles: Array[Vector2i] = []
	for y in 2:
		for x in 7:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if x < 3:
				model.province[model.index_of(x, y)] = 0
				home_tiles.append(tile)
			else:
				model.province[model.index_of(x, y)] = 1
				far_tiles.append(tile)
	var home := ProvinceState.create(0, "Cádiz", home_tiles, Vector2(1, 0), 6, 0, true)
	home.capital_tile = Vector2i(0, 0)
	home.town_tile = Vector2i(0, 0)
	home.town_development = 4
	var far := ProvinceState.create(1, "Coro", far_tiles, Vector2(5, 0), 8, 0, false)
	far.town_tile = Vector2i(6, 0)
	far.town_development = 1
	model.provinces = [home, far]
	model.resource[model.index_of(4, 0)] = 4
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(4, 0), 1)
	return [model, works]


## Wiki: capital-and-connectivity § Connectivity — an unlinked province town
## reports the gap to the crown and the road tiles the crown already holds.
func test_province_link_measures_the_gap_to_the_crown() -> void:
	var built: Array = _crown_link_model()
	var model: MapModel = built[0]
	var works: LandWorks = built[1]
	var capital: Vector2i = Vector2i(0, 0)
	var unlinked: Dictionary = LandConnectivity.province_link(
		model, works, 0, capital, 1
	)
	assert_false(bool(unlinked["linked"]))
	assert_eq(int(unlinked["roads"]), 0)
	assert_eq(int(unlinked["distance"]), 5, "Coro town is five tiles from the crown")
	for x in [1, 2, 3]:
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_ROAD)
	var partial: Dictionary = LandConnectivity.province_link(model, works, 0, capital, 1)
	assert_false(bool(partial["linked"]))
	assert_eq(int(partial["roads"]), 1, "only Coro's own road is in the province")
	assert_eq(int(partial["distance"]), 2, "three roads leave two tiles to build")
	for x in [4, 5]:
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_ROAD)
	var linked: Dictionary = LandConnectivity.province_link(model, works, 0, capital, 1)
	assert_true(bool(linked["linked"]), "the town now reaches the capital")
	assert_eq(int(linked["distance"]), 0)
	assert_eq(int(linked["roads"]), 3)
	assert_eq(Vector2i(linked["town"]), Vector2i(6, 0))


## The capital province is linked by definition, and a foreign or missing
## province returns an empty summary rather than a false link.
func test_province_link_guards_missing_data() -> void:
	var built: Array = _crown_link_model()
	var model: MapModel = built[0]
	var works: LandWorks = built[1]
	var home: Dictionary = LandConnectivity.province_link(
		model, works, 0, Vector2i(0, 0), 0
	)
	assert_true(bool(home["linked"]), "the capital town is the seat")
	assert_eq(int(home["distance"]), 0)
	assert_false(bool(LandConnectivity.province_link(
		null, works, 0, Vector2i(0, 0), 1
	)["linked"]))
	assert_false(bool(LandConnectivity.province_link(
		model, works, 0, Vector2i(0, 0), -1
	)["linked"]))


## Wiki: extraction-and-improvements § Town and extraction — the estates ledger
## tells the player how far an unlinked estate still is from the crown network.
func test_the_estate_row_reports_the_gap_to_the_crown() -> void:
	var built: Array = _crown_link_model()
	var model: MapModel = built[0]
	var works: LandWorks = built[1]
	var row: Dictionary = ImprovementLedger.estate_row(
		model, works, [], {"lumber": 9, "castIron": 9}, 0, Vector2i(4, 0),
		Vector2i(0, 0), {}
	)
	assert_false(bool(row["connected"]))
	assert_eq(int(row["link_distance"]), 3, "the estate is three tiles from the crown")
	assert_true(
		String(row["status_text"]).contains("3 tiles to the crown network"),
		String(row["status_text"])
	)
	for x in [1, 2, 3]:
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_ROAD)
	var nearer: Dictionary = ImprovementLedger.estate_row(
		model, works, [], {"lumber": 9, "castIron": 9}, 0, Vector2i(4, 0),
		Vector2i(0, 0), {}
	)
	assert_eq(int(nearer["link_distance"]), 0,
		"a road beside the estate links it")
	assert_true(bool(nearer["connected"]))


# --- a deed raises the Minor or Tribe town (DR-20261112-01) ------------------
## Minors and Tribes never build, so a Great Power's purchased land is the only
## play path that develops their towns (wiki: civilian-units § Merchant;
## extraction-and-improvements § Town manufacturing bonus).


## A two-province map: a Great Power holds the west, Minor Nation 6 holds four
## timber estates and a province town in the east.
func _deed_world() -> WorldMap:
	var model := MapModel.new()
	model.setup(5, 2)
	for y in 2:
		for x in 5:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0 if x < 2 else 1
	var gp_tiles: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)
	]
	var minor_tiles: Array[Vector2i] = [
		Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
		Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
	]
	var gp := ProvinceState.create(0, "P0", gp_tiles, Vector2.ZERO, 4, 0)
	var minor := ProvinceState.create(1, "P1", minor_tiles, Vector2.ZERO, 6, 6)
	minor.town_tile = Vector2i(2, 0)
	minor.town_development = 1
	model.provinces = [gp, minor]
	# Four timber estates beside the town; the town tile never holds a resource.
	for tile: Vector2i in [Vector2i(3, 0), Vector2i(4, 0), Vector2i(2, 1), Vector2i(3, 1)]:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	var world := WorldMap.new()
	world.add_region(model)
	return world


func test_the_deed_level_table_starts_at_one_and_caps_at_four() -> void:
	assert_eq(MinorTownGrowth.level_for(0), 1, "no deed, no growth")
	assert_eq(MinorTownGrowth.level_for(1), 2)
	assert_eq(MinorTownGrowth.level_for(2), 3)
	assert_eq(MinorTownGrowth.level_for(3), 4)
	assert_eq(MinorTownGrowth.level_for(4), 4, "town development tops out at 4")
	assert_eq(MinorTownGrowth.level_for(-2), 1)


func test_each_deed_lifts_the_minor_town_one_level() -> void:
	var world: WorldMap = _deed_world()
	var model: MapModel = world.region(0)
	var minor: ProvinceState = model.provinces[1]
	var economy := PlayerEconomy.starting()
	economy.treasury = 5000
	var tiles: Array[Vector2i] = [Vector2i(3, 0), Vector2i(4, 0), Vector2i(2, 1)]
	for index in tiles.size():
		assert_true(LandPurchase.complete(model, tiles[index], 0, economy))
		assert_eq(minor.town_development, 2 + index, "one level per deed")
	assert_eq(MinorTownGrowth.deeds_in(model, minor), 3)
	assert_eq(MinorTownGrowth.apply(model, minor), 0, "a fourth deed cannot pass 4")


func test_a_great_power_province_never_grows_from_a_deed() -> void:
	var world: WorldMap = _deed_world()
	var model: MapModel = world.region(0)
	var gp: ProvinceState = model.provinces[0]
	model.resource[model.index_of(0, 0)] = 0
	assert_true(model.purchase_tile(Vector2i(0, 0), 1))
	assert_eq(MinorTownGrowth.apply(model, gp), 0)
	assert_eq(gp.town_development, 0, "a crown's own town is its Builder's work")


func test_a_lost_deed_never_lowers_a_grown_town() -> void:
	var world: WorldMap = _deed_world()
	var model: MapModel = world.region(0)
	var minor: ProvinceState = model.provinces[1]
	minor.town_development = 4
	assert_true(model.purchase_tile(Vector2i(3, 0), 0))
	assert_eq(MinorTownGrowth.apply(model, minor), 0, "development is built, not rented")
	assert_eq(minor.town_development, 4)


func test_the_deed_puts_the_minor_town_manufactures_on_the_market() -> void:
	var world: WorldMap = _deed_world()
	var model: MapModel = world.region(0)
	var economy := PlayerEconomy.starting()
	economy.treasury = 5000
	assert_null(_lumber_offer(MinorMarket.emit_orders(world)), "a level-1 town pays nothing")
	assert_true(LandPurchase.complete(model, Vector2i(3, 0), 0, economy))
	var lumber: MarketOrder = _lumber_offer(MinorMarket.emit_orders(world))
	assert_not_null(lumber, "the deed develops the town to level 2")
	assert_eq(lumber.faction, 6)
	assert_eq(lumber.quantity, 1, "floor(4 timber / 4) x 1")
	assert_eq(lumber.origin_index, model.index_of(2, 0), "the province town is the source")


func _lumber_offer(orders: Array[MarketOrder]) -> MarketOrder:
	for order: MarketOrder in orders:
		if order.commodity == "lumber":
			return order
	return null


func test_the_deed_line_names_the_town_it_developed() -> void:
	var world: WorldMap = _deed_world()
	var model: MapModel = world.region(0)
	var minor: ProvinceState = model.provinces[1]
	assert_false(
		MinorTownGrowth.deed_line(model, minor, "Genoa").contains("town"),
		"a level-1 town has nothing to announce"
	)
	var economy := PlayerEconomy.starting()
	economy.treasury = 5000
	assert_true(LandPurchase.complete(model, Vector2i(3, 0), 0, economy))
	var line: String = MinorTownGrowth.deed_line(model, minor, "Genoa", minor.town_level())
	assert_true(line.begins_with("The deed to Genoa is signed"), line)
	assert_true(line.ends_with("The town rises to level 2."), line)
	minor.town_development = 4
	assert_false(
		MinorTownGrowth.deed_line(model, minor, "Genoa", 0).contains("town"),
		"a deed that did not raise the town says nothing about it"
	)


## The despatch names the level the completion actually set. A fourth deed (a
## town already at 4) must not announce a rise that never happened (REQ-P5-05;
## DR-20261112-01).
func test_a_deed_reports_only_the_level_it_actually_raised() -> void:
	var world: WorldMap = _deed_world()
	var model: MapModel = world.region(0)
	var minor: ProvinceState = model.provinces[1]
	var economy := PlayerEconomy.starting()
	economy.treasury = 50000
	var works := LandWorks.new()
	var tiles: Array[Vector2i] = [
		Vector2i(3, 0), Vector2i(4, 0), Vector2i(2, 1), Vector2i(3, 1)
	]
	var expected: Array[int] = [2, 3, 4, 0]
	for index in tiles.size():
		var merchant: CivilianState = CivilianState.create(
			1, 0, "merchant", tiles[index]
		)
		merchant.start_work(LandPurchase.ACTION, tiles[index], 1)
		var crew: Array[CivilianState] = [merchant]
		var reports: Array[Dictionary] = CivilianWork.resolve_turn(
			model, crew, works, null, economy
		)
		assert_eq(reports.size(), 1)
		var raised: int = int(reports[0].get("town_level", -1))
		assert_eq(raised, expected[index], "deed %d names the level it raised" % (index + 1))
		assert_eq(
			MinorTownGrowth.deed_line(model, minor, "Genoa", maxi(raised, 0)).contains("town"),
			expected[index] > 0,
			"only a real rise is announced"
		)


## The purchase toast carries the level the completion reported, so a deed a
## fully grown town cannot lift never claims a rise (REQ-P5-05; DR-20261112-01).
func test_the_purchase_toast_names_only_a_real_town_rise() -> void:
	var world: WorldMap = _deed_world()
	var model: MapModel = world.region(0)
	var play := PlaySession.new()
	play.world = world
	play.model = model
	play.player_faction = 0
	var hud := DeedHud.new()
	play.hud = hud
	var report: Dictionary = {
		"owner": 0, "region": 0, "tile": Vector2i(3, 0), "province": 1,
	}
	model.purchase_tile(Vector2i(3, 0), 0)
	MapPlayCivilians._settle_purchase(play, report)
	assert_eq(hud.toasts.size(), 1)
	assert_false(hud.toasts[0].contains("town"), hud.toasts[0])
	model.purchase_tile(Vector2i(4, 0), 0)
	report["tile"] = Vector2i(4, 0)
	report["town_level"] = 3
	MapPlayCivilians._settle_purchase(play, report)
	assert_eq(hud.toasts.size(), 2)
	assert_true(hud.toasts[1].ends_with("The town rises to level 3."), hud.toasts[1])
	hud.free()


func test_the_growth_rule_ignores_a_missing_model_or_province() -> void:
	assert_eq(MinorTownGrowth.apply(null, null), 0)
	assert_eq(MinorTownGrowth.deeds_in(null, null), 0)
	assert_eq(
		MinorTownGrowth.deed_line(null, null, "Genoa"),
		"The deed to Genoa is signed; the tile answers to your crown."
	)


# --- another crown's crew on the dossier (DR-20261111-26, per court) ---------

## A rival's crew is observe-only, and its ground is read through OUR survey
## record: a rival's uncover does not reveal the mineral to another court, and
## no order we could press applies to a crew that is not ours (wiki:
## fog-and-exploration § Prospecting — per court; civilian-units § Work Order
## Summary; REQ-P2-03, REQ-P5-06).
func test_a_rivals_crew_dossier_names_no_mineral_we_have_not_surveyed() -> void:
	var tile: Vector2i = field_Fixture.IRON_TILE
	# The rival surveyed its own ground; our crown has not.
	field__works.set_prospected(1, field__model, tile)
	assert_false(field__works.is_prospected(0, field__model, tile), "our crown has not surveyed it")
	var rival := CivilianState.create(2, 1, "builder", tile)
	var panel := CivilianPanel.new()
	add_child(panel)
	panel.refresh(
		field__model, rival, field__works, [rival], field_Fixture.stockpile(), _view, {}, {},
		{"treasury": 5000, "diplomacy": null}, 0
	)
	assert_eq(_panel_row(panel, "Resource"), "Unsurveyed ground")
	assert_false(
		_panel_row(panel, "Works").contains("Prospected"),
		"the rival's survey is not our survey: " + _panel_row(panel, "Works")
	)
	assert_eq(panel._status.text, "Enemy colours · no orders")
	assert_false(_dossier_offers_orders(panel), "a rival crew takes none of our orders")
	assert_false(panel._stock_line.visible, "our stores do not price a rival's crew")
	# Our own Builder on the same tile reads what WE know, so the sheet still
	# names a surveyed deposit and still offers its orders.
	field__works.set_prospected(0, field__model, tile)
	var mine := CivilianState.create(3, 0, "builder", tile)
	panel.refresh(
		field__model, mine, field__works, [mine], field_Fixture.stockpile(), _view, {}, {}, {}, 0
	)
	assert_eq(_panel_row(panel, "Resource"), "Iron")
	assert_true(
		_panel_row(panel, "Works").contains("Prospected"),
		"our own survey shows: " + _panel_row(panel, "Works")
	)
	assert_true(_dossier_offers_orders(panel), "our own crew still takes orders")
	panel.free()


## The value column of one dossier row, or "" when the caption is absent.
func _panel_row(panel: CivilianPanel, caption: String) -> String:
	var children: Array[Node] = panel._detail.get_children()
	var index: int = 0
	while index + 1 < children.size():
		var key: Label = children[index] as Label
		var value: Label = children[index + 1] as Label
		if key != null and key.text == caption:
			return value.text if value != null else ""
		index += 2
	return ""


## True when the dossier's order block carries a pressable order.
func _dossier_offers_orders(panel: CivilianPanel) -> bool:
	for child: Node in panel._orders.get_children():
		if child is Button:
			return true
	return false


## Ground in a Minor or Tribe province is unreadable without a Consulate, so the
## map draws no survey mark there and the Explorer's sheet names the gate rather
## than promising taps the rules refuse (wiki: civilian-units § Work Order
## Summary — explore/prospect require a Consulate; DR-20261111-26; REQ-P2-03).
func test_no_survey_mark_or_promise_without_a_consulate() -> void:
	var model: MapModel = field_Fixture.build_minor()
	var works := LandWorks.new()
	var court: DiplomacyState = field_Fixture.merchant_court()
	court.set_overture(0, 6, "none")
	var explorer := CivilianState.create(1, 1, "explorer", Vector2i(2, 2))
	assert_eq(
		MineralSurvey.unsurveyed_in_province(model, works, 1, 1, null),
		[Vector2i(2, 1)] as Array[Vector2i],
		"the ground itself is still unsurveyed"
	)
	var gate: String = CivilianExplorerGates.consulate_refusal(
		model, 1, 1, {"diplomacy": court}
	)
	assert_eq(gate, "Establish a consulate before exploring or prospecting")
	# The rules refuse the order the mark would have promised.
	var check: Dictionary = CivilianWork.validate(
		model, explorer, "prospect", works, [explorer], field_Fixture.stockpile(), null,
		Vector2i(2, 1), {}, {}, {"treasury": 5000, "diplomacy": court}
	)
	assert_false(bool(check["ok"]))
	assert_eq(String(check["reason"]), gate)
	# The mark set and the dossier line read the same gate.
	var play := PlaySession.new()
	play.model = model
	play.land_works = works
	play.player_faction = 1
	play.diplomacy = court
	play.economy = null
	assert_eq(
		MapPlayCivilians._survey_tiles(play, explorer), [] as Array[Vector2i],
		"no survey mark is drawn where the court may not dig"
	)
	var panel := CivilianPanel.new()
	add_child(panel)
	panel.refresh(
		model, explorer, works, [explorer], field_Fixture.stockpile(), null, {}, {},
		{"treasury": 5000, "diplomacy": court}, 1
	)
	assert_eq(_panel_row(panel, "Survey"), gate)
	panel.free()
	# With a Consulate the ground and its mark come back.
	court.set_overture(1, 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(CivilianExplorerGates.consulate_refusal(model, 1, 1, {"diplomacy": court}), "")
	assert_eq(
		MapPlayCivilians._survey_tiles(play, explorer),
		[Vector2i(2, 1)] as Array[Vector2i],
		"a Consulate opens the province's ground"
	)

# --- from test_estate_rows_rules.gd ---
## EstateRows: the one-estate reading the management ledger groups and totals.

func test_priority_orders_a_building_estate_first_and_an_unknown_last() -> void:
	assert_eq(EstateRows.priority("building"), 0)
	assert_eq(EstateRows.priority("producing"), 1)
	assert_lt(EstateRows.priority("maxed"), 9, "a known status sorts before an unknown")
	assert_eq(EstateRows.priority("paved"), 9, "an unknown status sorts last")


func test_status_reads_work_before_level_and_a_mineral_before_vacancy() -> void:
	var builder := field_Fixture.unit("builder", field_Fixture.TIMBER_TILE)
	builder.start_work("build_improvement", field_Fixture.TIMBER_TILE, 1)
	assert_eq(
		EstateRows.status_for(0, true, builder, false, false), "building",
		"a Builder at work outranks a vacant estate"
	)
	assert_eq(
		EstateRows.status_for(0, true, null, true, false), "unprospected",
		"a known but unsurveyed mineral is never vacant"
	)
	assert_eq(EstateRows.status_for(0, true, null, true, true), "vacant")
	assert_eq(EstateRows.status_for(2, false, null, false, false), "disconnected")
	assert_eq(
		EstateRows.status_for(ImprovementCatalog.MAX_LEVEL, true, null, false, false),
		"maxed"
	)
	assert_eq(EstateRows.status_for(1, true, null, false, false), "producing")


func test_a_linked_estate_row_carries_no_road_gap_claim() -> void:
	field__works.set_improvement(field__model, field_Fixture.TIMBER_TILE, 2)
	var row: Dictionary = EstateRows.project(
		field__model, field__works, [], {}, 0, field_Fixture.TIMBER_TILE,
		field__model.resource_at(field_Fixture.TIMBER_TILE.x, field_Fixture.TIMBER_TILE.y),
		field_Fixture.PLAYER_PROVINCE,
		{"transport": LandWorks.TRANSPORT_ROAD}, {"network": {}}, [], {"timber": 2}
	)
	assert_eq(int(row["level"]), 2)
	assert_eq(String(row["status"]), "producing")
	assert_true(bool(row["connected"]))
	assert_eq(int(row["link_distance"]), 0)
	assert_eq(int(row["builder_id"]), -1, "no idle Builder musters")
	assert_true(String(row["status_text"]).contains("Yields"))
	assert_false(
		String(row["status_text"]).contains("to the crown network"),
		"a linked estate carries no road-gap claim"
	)


func test_an_unlinked_estate_row_names_its_condition_and_refusal() -> void:
	field__works.set_improvement(field__model, field_Fixture.TIMBER_TILE, 2)
	var row: Dictionary = EstateRows.project(
		field__model, field__works, [], {}, 0, field_Fixture.TIMBER_TILE,
		field__model.resource_at(field_Fixture.TIMBER_TILE.x, field_Fixture.TIMBER_TILE.y),
		field_Fixture.PLAYER_PROVINCE, {}, {"network": {}}, [], {}
	)
	assert_false(bool(row["connected"]))
	assert_eq(String(row["status"]), "disconnected")
	assert_false(bool(row["can_build"]))
	assert_true(
		String(row["build_reason"]).contains("tech"),
		"the refusal names the first gate that blocks the estate: %s"
		% String(row["build_reason"])
	)


func test_an_unsurveyed_mineral_reads_unprospected_until_an_explorer_reads_it() -> void:
	var row: Dictionary = EstateRows.project(
		field__model, field__works, [], {}, 0, field_Fixture.IRON_TILE,
		field__model.resource_at(field_Fixture.IRON_TILE.x, field_Fixture.IRON_TILE.y),
		field_Fixture.PLAYER_PROVINCE,
		{"transport": LandWorks.TRANSPORT_ROAD}, {"network": {}}, [], {}
	)
	assert_eq(String(row["status"]), "unprospected")
	assert_true(bool(row["needs_prospecting"]))
	assert_false(bool(row["prospected"]))
	assert_false(bool(row["can_build"]))
	assert_true(String(row["build_reason"]).contains("prospect"))


## Two fort projects may run in one province, and the later completion adds no
## level (wiki: siege-mechanics § Fort Levels). The receipt must not claim a wall
## the turn did not raise: the crown paid twice and bought one wall.
func test_a_second_fort_project_reports_no_level_added() -> void:
	var first := _add("engineer", field_Fixture.BARE_TILE)
	var second := _add("engineer", field_Fixture.BARE_TILE)
	assert_true(bool(CivilianWork.assign(
		field__model, first, "build_fort", field__works, _units, _stock, _view
	)["ok"]))
	assert_true(bool(CivilianWork.assign(
		field__model, second, "build_fort", field__works, _units, _stock, _view
	)["ok"]))
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		field__model, _units, field__works, _view
	)
	assert_eq(reports.size(), 2)
	assert_eq(int(reports[0]["fort_before"]), 0)
	assert_eq(int(reports[0]["fort_level"]), 1)
	assert_eq(int(reports[1]["fort_before"]), 1, "the wall already stood")
	assert_eq(int(reports[1]["fort_level"]), 1, "and the duplicate added no level")
	assert_eq(FortRules.level_at(field__model, field_Fixture.PLAYER_PROVINCE), 1)
	assert_true(
		FortRules.raise_line(
			int(reports[0]["fort_before"]), int(reports[0]["fort_level"])
		).begins_with("wood fort raised"),
		"the first project names the wall it raised"
	)
	assert_true(
		FortRules.raise_line(
			int(reports[1]["fort_before"]), int(reports[1]["fort_level"])
		).begins_with("no level added"),
		"the duplicate says it added nothing"
	)
