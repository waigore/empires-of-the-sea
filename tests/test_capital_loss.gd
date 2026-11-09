extends GdToolsTest
## Capital loss, reassignment and terminal fall (wiki: capital-and-connectivity
## § Capital loss and reassignment; DR-20261109-02).
##
## The rules fixture is a hand-built 6x4 chart: Seat/Harbour/Uplands belong to
## one crown and Rival Seat to another, so a captured seat has a deterministic
## seaboard successor, an inland-only crown has a fallback, and a crown with a
## single province has nothing left to fall back on.

const Fixture = preload("res://tests/map_fixture.gd")

const SEAT: int = 0
const HARBOUR: int = 1
const UPLANDS: int = 2
const RIVAL: int = 3


func test_snapshot_records_the_capital_of_each_crown() -> void:
	var model: MapModel = _chart()
	var seats: Dictionary = CapitalLoss.snapshot(model)
	assert_eq(int(seats[0]), SEAT)
	assert_eq(int(seats[1]), RIVAL)


func test_a_captured_seat_moves_to_the_lowest_seaboard_province() -> void:
	var model: MapModel = _chart()
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 1

	var result: Dictionary = CapitalLoss.resolve(model, before)

	assert_eq(result["reassigned"].size(), 1)
	var row: Dictionary = result["reassigned"][0]
	assert_eq(int(row["faction"]), 0)
	assert_eq(int(row["province"]), HARBOUR, "seaboard first, ascending id")
	assert_eq(int(row["lost"]), SEAT)
	assert_true(model.province_data(HARBOUR).capital)
	assert_false(model.province_data(SEAT).capital, "the captured seat stops being a capital")
	assert_false(model.province_data(UPLANDS).capital)


func test_a_crown_with_only_inland_provinces_falls_back_to_them() -> void:
	var model: MapModel = _chart()
	model.province_data(HARBOUR).owner = 1
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 1

	var result: Dictionary = CapitalLoss.resolve(model, before)

	assert_eq(int(result["reassigned"][0]["province"]), UPLANDS)
	assert_true(model.province_data(UPLANDS).capital)


func test_a_great_power_seat_reaches_town_development_four() -> void:
	var model: MapModel = _chart()
	model.province_data(HARBOUR).town_development = 1
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 1

	CapitalLoss.resolve(model, before)

	assert_eq(model.province_data(HARBOUR).town_development, 4)


func test_a_minor_nation_keeps_its_new_seats_town_development() -> void:
	var model: MapModel = _chart()
	_hand_over(model, 0, [SEAT, HARBOUR, UPLANDS])
	_hand_over(model, 6, [SEAT, HARBOUR, UPLANDS])
	model.province_data(SEAT).capital = true
	model.province_data(HARBOUR).town_development = 2
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 1

	CapitalLoss.resolve(model, before)

	assert_eq(model.province_data(HARBOUR).town_development, 2)
	assert_true(model.province_data(HARBOUR).capital)
	assert_eq(CapitalLoss.seat_of(model, 6), HARBOUR)


func test_the_new_seat_gets_a_tile_near_the_province_centre() -> void:
	var model: MapModel = _chart()
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 1

	CapitalLoss.resolve(model, before)

	var seat: ProvinceState = model.province_data(HARBOUR)
	assert_in(seat.capital_tile, seat.tiles)
	assert_eq(seat.capital_tile, CapitalLoss.town_tile(seat), "deterministic on a re-read")


func test_an_intact_capital_is_left_alone() -> void:
	var model: MapModel = _chart()
	var before: Dictionary = CapitalLoss.snapshot(model)

	var result: Dictionary = CapitalLoss.resolve(model, before)

	assert_eq(result["reassigned"].size(), 0)
	assert_eq(result["fallen"].size(), 0)
	assert_eq(CapitalLoss.seat_of(model, 0), SEAT)
	assert_eq(CapitalLoss.seat_of(model, 1), RIVAL)


func test_a_crown_with_no_province_left_falls_to_the_conqueror() -> void:
	var model: MapModel = _chart()
	_hand_over(model, 0, [SEAT, HARBOUR, UPLANDS])
	_hand_over(model, 6, [SEAT])
	_hand_over(model, 1, [HARBOUR, UPLANDS])
	model.province_data(SEAT).capital = true
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 0

	var result: Dictionary = CapitalLoss.resolve(model, before)

	assert_eq(result["fallen"].size(), 1)
	var row: Dictionary = result["fallen"][0]
	assert_eq(int(row["faction"]), 6)
	assert_eq(int(row["conqueror"]), 0)
	assert_eq(int(row["lost"]), SEAT)
	assert_false(model.province_data(SEAT).capital)


func test_a_crown_that_already_fell_is_not_reported_again() -> void:
	var model: MapModel = _chart()
	_hand_over(model, 0, [SEAT, HARBOUR, UPLANDS])
	_hand_over(model, 6, [SEAT])
	_hand_over(model, 1, [HARBOUR, UPLANDS])
	model.province_data(SEAT).capital = true
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 0
	var first: Dictionary = CapitalLoss.resolve(model, before)
	assert_eq(first["fallen"].size(), 1)

	# The next Combat phase snapshots a crown that no longer holds a seat.
	var after: Dictionary = CapitalLoss.snapshot(model)
	var again: Dictionary = CapitalLoss.resolve(model, after)

	assert_eq(again["fallen"].size(), 0, "a fallen crown does not fall twice")
	assert_eq(again["reassigned"].size(), 0, "and is not given a new seat")


func test_a_crown_without_a_snapshot_seat_is_not_given_one() -> void:
	var model: MapModel = _chart()
	_hand_over(model, 6, [HARBOUR, UPLANDS])
	var before: Dictionary = CapitalLoss.snapshot(model)
	assert_eq(int(before[6]), CapitalLoss.NO_ID)

	var result: Dictionary = CapitalLoss.resolve(model, before)

	assert_eq(result["reassigned"].size(), 0, "no seat was lost, so none is reassigned")
	assert_eq(result["fallen"].size(), 0)
	assert_eq(CapitalLoss.seat_of(model, 6), CapitalLoss.NO_ID)


func test_a_fall_hands_every_province_in_every_region_to_the_conqueror() -> void:
	var old_world: MapModel = _chart()
	var new_world: MapModel = _chart()
	new_world.region_id = FactionCatalog.NEW_WORLD
	new_world.region_key = FactionCatalog.region_key(FactionCatalog.NEW_WORLD)
	var world := WorldMap.new()
	world.add_region(old_world)
	world.add_region(new_world)
	_hand_over(old_world, 6, [SEAT])
	_hand_over(old_world, 1, [HARBOUR, UPLANDS])
	_hand_over(new_world, 6, [RIVAL])
	_hand_over(new_world, 0, [SEAT, HARBOUR, UPLANDS])
	var before: Array = CapitalLoss.snapshot_world(world)
	old_world.province_data(SEAT).owner = 0

	var result: Dictionary = CapitalLoss.resolve_world(world, before)

	assert_eq(result["fallen"].size(), 1)
	assert_eq(result["reassigned"].size(), 0, "no seat is invented in the overseas region")
	assert_eq(int(result["fallen"][0]["conqueror"]), 0)
	assert_eq(new_world.province_data(RIVAL).owner, 0, "the overseas holding follows")
	assert_eq(world.owned_provinces(WorldMap.NEW_WORLD, 6), 0)


func test_the_pick_is_stable_across_calls() -> void:
	var model: MapModel = _chart()
	var owned: Array[int] = [HARBOUR, UPLANDS]

	var first: int = CapitalLoss.pick_capital_province(model, owned)
	var second: int = CapitalLoss.pick_capital_province(model, owned)

	assert_eq(first, HARBOUR)
	assert_eq(second, first)


# --- screen wiring -----------------------------------------------------------

func test_a_captured_capital_reseats_its_owner_on_the_map() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	var model: MapModel = screen.model
	var saved: Array[Dictionary] = _save_seats(model)
	var target: int = _enemy_capital_next_door(screen)
	assert_gt(target, -1)
	var enemy: int = model.province_owner(target)
	assert_eq(_capital_count(model, enemy), 1, "the crown has exactly one seat to lose")
	# Rival land AI can split and march into a declared seat on the same
	# end-turn pass; strip that crown's armies so the capture stays unopposed.
	screen.army_layer.transfer_owner(enemy, MapModel.NO_ID)
	_declare_war(screen, enemy)
	_detach_one(screen)
	var tile: Vector2i = model.province_data(target).tiles[0]
	assert_true(MapPlayArmies.try_order(screen.play, tile))

	MapPlayTurn.end_turn(screen.play)

	assert_eq(model.province_owner(target), MapScreen.PLAYER_FACTION)
	assert_false(model.province_data(target).capital, "the captured seat stops being a capital")
	assert_eq(_capital_count(model, enemy), 1, "the crown keeps exactly one seat")
	_restore_seats(model, saved)
	screen.free()


func test_the_player_capital_framing_follows_a_reassignment() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	var model: MapModel = screen.model
	var home: int = screen.capital_province
	var home_tile: Vector2i = model.capital_tile_of(home)
	var successor: int = _successor(model, home)
	assert_gt(successor, -1)
	model.province_data(successor).capital = true
	model.province_data(successor).capital_tile = CapitalLoss.town_tile(
		model.province_data(successor)
	)
	model.province_data(home).capital = false

	MapPlayArmies.sync_player_capital(screen.play)

	assert_eq(screen.capital_province, successor)
	assert_eq(screen.capital_tile, model.capital_tile_of(successor))
	model.province_data(home).capital = true
	model.province_data(home).capital_tile = home_tile
	model.province_data(successor).capital = false
	model.province_data(successor).capital_tile = CapitalLoss.NO_TILE
	screen.free()


func test_a_fallen_crown_leaves_the_roster_and_the_court() -> void:
	var screen: MapScreen = Fixture.attach_screen(self)
	var minor: int = FactionCatalog.minor_ids()[0]
	screen.play.diplomacy.ensure_relation(minor, 0, screen.play.diplomacy.turn)
	assert_not_null(screen.play.diplomacy.relation(minor, 0))
	var armies_before: int = _army_count(screen, minor)
	assert_gt(armies_before, 0)
	var toasts_before: int = screen.hud._toast_box.get_child_count()

	var changed: bool = MapPlayArmies.apply_capital_loss(
		screen.play, {"fallen": [{"faction": minor, "conqueror": 0}], "reassigned": []}
	)

	assert_true(changed)
	assert_eq(_army_count(screen, minor), 0)
	assert_null(screen.play.diplomacy.relation(minor, 0))
	assert_eq(screen.hud._toast_box.get_child_count(), toasts_before + 1)
	screen.free()


# --- fixtures ----------------------------------------------------------------

## Lands and waters of the test chart, in tile coordinates.
func _chart() -> MapModel:
	var model := MapModel.new()
	model.setup(6, 4)
	model.region_id = FactionCatalog.OLD_WORLD
	model.region_key = FactionCatalog.region_key(FactionCatalog.OLD_WORLD)
	model.faction_ids = [0, 1, 2, 6]
	var land: Dictionary = {
		SEAT: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],
		HARBOUR: [Vector2i(3, 0), Vector2i(3, 1), Vector2i(2, 0), Vector2i(2, 2), Vector2i(3, 2)],
		UPLANDS: [Vector2i(1, 1), Vector2i(2, 1)],
	}
	# The rival seat sits apart on the eastern seaboard.
	var rival_tiles: Array[Vector2i] = [Vector2i(5, 0), Vector2i(5, 1)]
	for province_id: int in land.keys():
		_fill(model, land[province_id], province_id)
	_fill(model, rival_tiles, RIVAL)
	model.provinces = [
		_province(SEAT, "Seat", land[SEAT], 0, true),
		_province(HARBOUR, "Harbour", land[HARBOUR], 0, false),
		_province(UPLANDS, "Uplands", land[UPLANDS], 0, false),
		_province(RIVAL, "Rival Seat", rival_tiles, 1, true),
	]
	var water: Array[Vector2i] = []
	for y in model.height:
		for x in model.width:
			if model.province_at(x, y) == MapModel.NO_ID:
				water.append(Vector2i(x, y))
	for tile: Vector2i in water:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 0
	model.sea_zones = [SeaZoneState.create(0, "Open Water", water, Vector2(4.0, 3.0), water.size())]
	return model


func _fill(model: MapModel, tiles: Array, province_id: int) -> void:
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = province_id


func _province(
	id: int, title: String, tiles: Array, owner: int, capital: bool
) -> ProvinceState:
	var typed: Array[Vector2i] = []
	typed.assign(tiles)
	var sum := Vector2.ZERO
	for tile: Vector2i in typed:
		sum += Vector2(tile)
	var center: Vector2 = sum / maxf(float(typed.size()), 1.0)
	var data := ProvinceState.create(id, title, typed, center, typed.size(), owner, capital)
	if capital:
		data.capital_tile = CapitalLoss.town_tile(data)
	return data


## Hands provinces to a faction without touching anything else on the chart.
func _hand_over(model: MapModel, faction: int, provinces: Array) -> void:
	for province_id: int in provinces:
		model.province_data(province_id).owner = faction


func _successor(model: MapModel, capital: int) -> int:
	var owned: Array[int] = []
	for province: ProvinceState in model.provinces:
		if province.owner == MapScreen.PLAYER_FACTION and province.id != capital:
			owned.append(province.id)
	return CapitalLoss.pick_capital_province(model, owned)


func _army_count(screen: MapScreen, faction: int) -> int:
	var total: int = 0
	for raw: Variant in screen.army_layer.regions.values():
		var roster: Array = raw
		for army: ArmyState in roster:
			if army != null and army.owner == faction:
				total += 1
	return total


## Marks a province next to the player's capital as a rival crown's only seat,
## so one march captures a capital without disturbing the rest of the map.
func _enemy_capital_next_door(screen: MapScreen) -> int:
	var model: MapModel = screen.model
	for province_id: int in MapGeo.province_neighbors(model, screen.capital_province):
		var data: ProvinceState = model.province_data(province_id)
		if data == null or data.owner == MapScreen.PLAYER_FACTION or data.owner == MapModel.NO_ID:
			continue
		if data.capital:
			continue
		var enemy: int = data.owner
		for province: ProvinceState in model.provinces:
			if province.owner == enemy and province.capital:
				province.capital = false
		data.capital = true
		data.capital_tile = CapitalLoss.town_tile(data)
		return province_id
	return -1


func _capital_count(model: MapModel, faction: int) -> int:
	var total: int = 0
	for province: ProvinceState in model.provinces:
		if province.owner == faction and province.capital:
			total += 1
	return total


func _save_seats(model: MapModel) -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	for province: ProvinceState in model.provinces:
		saved.append({
			"id": province.id,
			"owner": province.owner,
			"capital": province.capital,
			"tile": province.capital_tile,
			"town": province.town_development,
		})
	return saved


func _restore_seats(model: MapModel, saved: Array[Dictionary]) -> void:
	for row: Dictionary in saved:
		var province: ProvinceState = model.province_data(int(row["id"]))
		if province == null:
			continue
		province.owner = int(row["owner"])
		province.capital = bool(row["capital"])
		province.capital_tile = row["tile"]
		province.town_development = int(row["town"])


func _declare_war(screen: MapScreen, faction: int) -> void:
	screen.play.diplomacy.ensure_relation(
		screen.play.player_faction, faction, screen.play.diplomacy.turn
	)
	DiplomacyRules.declare_war(screen.play.diplomacy, screen.play.player_faction, faction)


func _detach_one(screen: MapScreen) -> ArmyState:
	for army: ArmyState in screen.army_layer.armies:
		if army.owner == screen.play.player_faction and army.is_home_army():
			screen.army_layer.select(army)
			MapPlayArmies.on_action(screen.play, "detach:%s" % army.regiments[0])
			return screen.army_layer.selected_army
	return null
