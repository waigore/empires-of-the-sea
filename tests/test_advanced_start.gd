extends GdToolsTest
## Advanced starts (wiki: advanced-starts; DR-20261111-01): tier tables, the
## fixed tech lists, the balanced muster, inherited colonies, chart and estates.
## The live setup path (a real map screen opening mid-age) lives in
## test_advanced_start_live so these cheap cases never wait behind those mounts.

const Fixture = preload("res://tests/map_fixture.gd")
const NEW_WORLD: int = 1

var world: WorldMap = null
var saved: Array = []


func before_all() -> void:
	saved = Fixture.snapshot(Fixture.world())


func before_each() -> void:
	Fixture.restore(Fixture.world(), saved)
	world = Fixture.world()


func after_each() -> void:
	Fixture.restore(world, saved)


# --- tier tables -------------------------------------------------------------


func test_presets_match_the_published_tiers() -> void:
	assert_eq(AdvancedStart.turn(AdvancedStart.TURNS50), 50)
	assert_eq(AdvancedStart.turn(AdvancedStart.TURNS100), 100)
	assert_eq(int(AdvancedStart.entry(AdvancedStart.TURNS50)["treasury"]), 20000)
	assert_eq(int(AdvancedStart.entry(AdvancedStart.TURNS100)["treasury"]), 40000)
	assert_eq(int(AdvancedStart.entry(AdvancedStart.TURNS100)["apprentices"]), 4)
	assert_eq(AdvancedStart.regiments(AdvancedStart.TURNS50), 6)
	assert_eq(AdvancedStart.regiments(AdvancedStart.TURNS100), 12)
	assert_eq(AdvancedStart.cargo_ships(AdvancedStart.TURNS100), 6)
	assert_almost_eq(AdvancedStart.nw_reveal(AdvancedStart.TURNS50), 0.625, 0.0001)


func test_turn_zero_is_the_ordinary_campaign() -> void:
	assert_false(AdvancedStart.active(AdvancedStart.NONE))
	assert_eq(AdvancedStart.tech_ids(AdvancedStart.NONE).size(), 0)
	assert_eq(AdvancedStart.regiment_types(AdvancedStart.NONE).size(), 0)
	assert_eq(AdvancedStart.normalize("nonsense"), AdvancedStart.NONE)


# --- technology --------------------------------------------------------------


func test_tech_lists_are_the_fixed_rows_and_closed_under_prereqs() -> void:
	var fifty: Array[String] = AdvancedStart.tech_ids(AdvancedStart.TURNS50)
	var hundred: Array[String] = AdvancedStart.tech_ids(AdvancedStart.TURNS100)
	assert_eq(fifty.size(), 23, "50-turn list has 23 techs")
	assert_eq(hundred.size(), 45, "100-turn list has 45 techs")
	for tech: String in hundred:
		assert_true(TechCatalog.known(tech), "%s is a catalog tech" % tech)
		for prereq: String in TechCatalog.prerequisites(tech):
			assert_has(hundred, prereq, "%s needs an in-list prereq" % tech)
	assert_false(fifty.has("early_steam_engine"), "the 50-turn age stops before steam")


# --- muster ------------------------------------------------------------------


func test_the_muster_balances_branches_with_buildable_types() -> void:
	for tier: String in [AdvancedStart.TURNS50, AdvancedStart.TURNS100]:
		var types: Array[String] = AdvancedStart.regiment_types(tier)
		assert_eq(types.size(), AdvancedStart.regiments(tier), "full roster musters")
		var branches: Dictionary = {"infantry": 0, "cavalry": 0, "artillery": 0}
		var tech: Dictionary = AdvancedStart.tech_table(tier)
		for type_id: String in types:
			assert_true(
				RegimentEconomy.buildable(type_id, tech),
				"%s is unlocked by the tier's techs" % type_id
			)
			branches[_branch(type_id)] = int(branches[_branch(type_id)]) + 1
		for branch: String in branches.keys():
			assert_gte(int(branches[branch]), 1, "%s gets regiments" % branch)


func _branch(type_id: String) -> String:
	match RegimentCatalog.category(type_id):
		RegimentCatalog.Category.LIGHT_CAVALRY:
			return "cavalry"
		RegimentCatalog.Category.SPEAR_CAVALRY:
			return "cavalry"
		RegimentCatalog.Category.HEAVY_CAVALRY:
			return "cavalry"
		RegimentCatalog.Category.LIGHT_ARTILLERY:
			return "artillery"
		RegimentCatalog.Category.HEAVY_ARTILLERY:
			return "artillery"
		_:
			return "infantry"


# --- colonies and chart ------------------------------------------------------


func test_colonies_leave_every_tribe_a_home() -> void:
	var model: MapModel = world.region(NEW_WORLD)
	var before: Dictionary = _tribe_counts(model)
	var claimed: Dictionary = AdvancedWorld.claim(
		world, AdvancedStart.nw_owned(AdvancedStart.TURNS100), FactionCatalog.great_power_ids()
	)
	assert_false(claimed.is_empty(), "the Passage shore yields colonies")
	for faction: Variant in claimed.keys():
		var provinces: Array = claimed[faction]
		assert_lte(provinces.size(), 6, "a crown takes at most six")
		for province_id: int in provinces:
			assert_eq(
				model.province_owner(province_id), int(faction),
				"the colony changes hands"
			)
	var after: Dictionary = _tribe_counts(model)
	for owner: Variant in before.keys():
		assert_gte(int(after.get(owner, 0)), 1, "tribe %s keeps a province" % owner)


func test_claimed_colonies_are_contiguous() -> void:
	var model: MapModel = world.region(NEW_WORLD)
	var claimed: Dictionary = AdvancedWorld.claim(
		world, AdvancedStart.nw_owned(AdvancedStart.TURNS100), FactionCatalog.great_power_ids()
	)
	for faction: Variant in claimed.keys():
		var provinces: Array = claimed[faction]
		if provinces.size() < 2:
			continue
		var reached: Dictionary = {int(provinces[0]): true}
		var queue: Array[int] = [int(provinces[0])]
		var head: int = 0
		while head < queue.size():
			var province_id: int = queue[head]
			head += 1
			for raw: Variant in MapGeo.province_neighbors(model, province_id):
				if reached.has(int(raw)) or not provinces.has(int(raw)):
					continue
				reached[int(raw)] = true
				queue.append(int(raw))
		assert_eq(reached.size(), provinces.size(), "colonies touch each other")


func _tribe_counts(model: MapModel) -> Dictionary:
	var counts: Dictionary = {}
	for province: ProvinceState in model.provinces:
		if FactionCatalog.type_of(province.owner) == FactionCatalog.Type.TRIBE:
			counts[province.owner] = int(counts.get(province.owner, 0)) + 1
	return counts


func test_the_chart_opens_the_documented_share() -> void:
	var model: MapModel = world.region(NEW_WORLD)
	var visibility := VisibilityModel.new()
	visibility.setup(model, FactionCatalog.PLAYER_FACTION)
	visibility.apply_initial()
	var revealed: int = AdvancedWorld.reveal(
		world, visibility, FactionCatalog.PLAYER_FACTION,
		AdvancedStart.nw_reveal(AdvancedStart.TURNS50)
	)
	var total: int = model.province_count()
	assert_gte(revealed, ceili(float(total) * 0.625) - 1, "most of the New World charts")
	assert_lte(revealed, total, "never more than the map")
	var charted: Array[int] = AdvancedWorld.charted_provinces(
		world, AdvancedStart.nw_reveal(AdvancedStart.TURNS100)
	)
	assert_eq(charted.size(), total, "the 100-turn chart is the whole New World")


## Wiki § NW sea-zone visibility: the chart holds the water beside a flood-filled
## shore *and* the shortest S–S lanes from the Passage that reach it; water off
## both stays unknown.
func test_the_chart_holds_the_passage_lanes() -> void:
	var model: MapModel = world.region(NEW_WORLD)
	var shared: float = AdvancedStart.nw_reveal(AdvancedStart.TURNS50)
	var visibility := VisibilityModel.new()
	visibility.setup(model, FactionCatalog.PLAYER_FACTION)
	visibility.apply_initial()
	AdvancedWorld.reveal(world, visibility, FactionCatalog.PLAYER_FACTION, shared)
	var provinces: Array[int] = AdvancedWorld.charted_provinces(world, shared)
	var entries: Array[int] = world.warp_zones(NEW_WORLD)
	var lanes: Array[int] = AdvancedSeas.charted(model, entries, provinces)
	assert_false(lanes.is_empty(), "the Passage reaches the charted shore")
	for zone_id: int in lanes:
		var data: SeaZoneState = model.sea_zone_data(zone_id)
		assert_not_null(data, "a lane names a real zone")
		for tile: Vector2i in data.tiles:
			assert_gte(
				visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FOGGED,
				"lane water is charted"
			)
	for zone: SeaZoneState in model.sea_zones:
		if lanes.has(zone.id):
			continue
		for tile: Vector2i in zone.tiles:
			assert_eq(
				visibility.level_at(tile.x, tile.y), VisibilityModel.Level.UNKNOWN,
				"water off the lane and off a revealed shore stays unknown"
			)


## The lane, not only the shore: a province charted across open water brings the
## water that reaches it from the Passage, so a voyage can sail the whole way
## instead of guessing at the last step (wiki § NW sea-zone visibility).
func test_a_lane_carries_the_chart_across_open_water() -> void:
	var model: MapModel = world.region(NEW_WORLD)
	var entries: Array[int] = world.warp_zones(NEW_WORLD)
	if entries.is_empty():
		return
	var from_entry: Dictionary = AdvancedSeas.hops(model, entries)
	var far: int = _far_shore(model, from_entry)
	assert_gte(far, 0, "the fixture has a shore off the Passage mouth")
	var shore: Array[int] = NavalMovement.province_sea_zones(model, far)
	var lanes: Array[int] = AdvancedSeas.charted(model, entries, [far])
	for zone: int in shore:
		assert_has(lanes, zone, "the shore's own water charts")
	assert_gt(lanes.size(), shore.size(), "the lane that reaches it charts too")
	var to_shore: Dictionary = AdvancedSeas.hops(model, shore)
	var nearest: int = 1 << 30
	for zone: int in shore:
		nearest = mini(nearest, int(from_entry.get(zone, nearest)))
	for zone: int in lanes:
		assert_eq(
			int(from_entry.get(zone, -1)) + int(to_shore.get(zone, -1)), nearest,
			"every charted zone lies on a shortest lane to the shore"
		)


## Charted water is `fogged`; a shore the crown owns paints its own water fully
## visible through the standing coastal pass.
func test_the_lane_paints_fogged_water_and_a_held_beach_fully_visible() -> void:
	var model: MapModel = world.region(NEW_WORLD)
	var entries: Array[int] = world.warp_zones(NEW_WORLD)
	var far: int = _far_shore(model, AdvancedSeas.hops(model, entries))
	if far < 0:
		return
	var zone: int = int(NavalMovement.province_sea_zones(model, far)[0])
	var visibility := VisibilityModel.new()
	visibility.setup(model, FactionCatalog.PLAYER_FACTION)
	visibility.apply_initial()
	AdvancedSeas.chart(model, visibility, zone, FactionCatalog.PLAYER_FACTION)
	for tile: Vector2i in model.sea_zone_data(zone).tiles:
		assert_eq(
			visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FOGGED,
			"a charted lane is fogged, not surveyed"
		)
	(model.get_province(far) as ProvinceState).owner = FactionCatalog.PLAYER_FACTION
	AdvancedSeas.chart(model, visibility, zone, FactionCatalog.PLAYER_FACTION)
	for tile: Vector2i in model.sea_zone_data(zone).tiles:
		assert_eq(
			visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE,
			"the crown's own beach is fully visible"
		)


## Wiki § NW sea-zone visibility leaves `unknown` only the water that is neither
## P–S adjacent to a revealed province nor on the connecting path. A shore the
## Passage cannot reach in one lane still charts its own water; water off both
## stays unknown.
func test_the_shore_charts_even_where_no_lane_reaches() -> void:
	var model: MapModel = MapModel.new()
	model.setup(8, 3)
	model.region_id = NEW_WORLD
	for y in 3:
		for x in 8:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	# Two shores on two seas that never touch, plus one sea with no shore at all.
	var near: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var far: Array[Vector2i] = [Vector2i(4, 0), Vector2i(5, 0)]
	for tile: Vector2i in near + far:
		model.province[model.index_of(tile.x, tile.y)] = 0 if near.has(tile) else 1
	var zones: Array = [
		SeaZoneState.create(0, "Entry", [Vector2i(0, 1), Vector2i(1, 1)], Vector2.ZERO, 2),
		SeaZoneState.create(1, "Far", [Vector2i(4, 1), Vector2i(5, 1)], Vector2.ZERO, 2),
		SeaZoneState.create(2, "Offshore", [Vector2i(7, 1)], Vector2.ZERO, 1),
	]
	model.sea_zones.clear()
	for zone: SeaZoneState in zones:
		model.sea_zones.append(zone)
		for tile: Vector2i in zone.tiles:
			model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.OCEAN
			model.sea_zone[model.index_of(tile.x, tile.y)] = zone.id
	model.provinces.append(ProvinceState.create(0, "Near", near, Vector2.ZERO, 2, 6))
	model.provinces.append(ProvinceState.create(1, "Far", far, Vector2.ZERO, 2, 6))
	var charted: Array[int] = AdvancedSeas.charted(model, [0], [0, 1])
	assert_has(charted, 0, "the shore beside the Passage charts")
	assert_has(charted, 1, "the far shore charts its own water")
	assert_false(charted.has(2), "water beside no revealed province stays unknown")
	assert_eq(AdvancedSeas.charted(model, [], [0, 1]), charted, "no entry, the shore still charts")
	assert_eq(
		AdvancedSeas.charted(model, [0], []), [] as Array[int], "no shore, no water"
	)


## A province whose shore zone is not at the Passage mouth, preferring one that
## needs more than one S–S hop; -1 when the map has no such shore.
func _far_shore(model: MapModel, from_entry: Dictionary) -> int:
	var fallback: int = -1
	for province: ProvinceState in model.provinces:
		for zone: int in NavalMovement.province_sea_zones(model, province.id):
			var hops: int = int(from_entry.get(zone, -1))
			if hops > 1:
				return province.id
			if hops == 1 and fallback < 0:
				fallback = province.id
	return fallback


# --- estates -----------------------------------------------------------------


func test_prospecting_marks_the_tier_share() -> void:
	var works: Dictionary = {}
	var minerals: int = _mineral_count(world, FactionCatalog.PLAYER_FACTION)
	if minerals == 0:
		return
	var marked: int = AdvancedEstates.prospect(
		world, works, [FactionCatalog.PLAYER_FACTION],
		AdvancedStart.prospect_share(AdvancedStart.TURNS50)
	)
	assert_gte(marked, ceili(float(minerals) * 0.5) - 1, "half the minerals are known")


func test_development_raises_estates_and_roads() -> void:
	var works: Dictionary = {}
	var raised: int = AdvancedEstates.develop(
		world, works, [FactionCatalog.PLAYER_FACTION],
		AdvancedStart.develop_share(AdvancedStart.TURNS50)
	)
	assert_gte(raised, 1, "forward courts already hold estates")
	var model: MapModel = world.region(0)
	var ledger: LandWorks = works[0]
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			if ledger.improvement_at(model, tile) <= 0:
				continue
			assert_true(
				ledger.transport_at(model, tile) > 0 or province.town_tile.x < 0,
				"an estate is reached by road"
			)


func test_minor_land_is_bought_without_moving_the_province() -> void:
	var works: Dictionary = {}
	var bought: int = AdvancedEstates.purchase_minor_land(
		world, works, FactionCatalog.great_power_ids(),
		AdvancedStart.develop_share(AdvancedStart.TURNS50)
	)
	assert_gte(bought, 1, "the Minor Nations have sold land")
	var model: MapModel = world.region(0)
	var deeds: int = 0
	for province: ProvinceState in model.provinces:
		if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.MINOR_NATION:
			continue
		for tile: Vector2i in province.tiles:
			if not model.is_purchased_tile(tile):
				continue
			deeds += 1
			assert_ne(model.owner_at(tile.x, tile.y), province.owner, "the deed moves, not the province")
			assert_true(
				(works[0] as LandWorks).improvement_at(model, tile) > 0
				or model.resource_at(tile.x, tile.y) < 0,
				"bought land is developed"
			)
	assert_eq(deeds, bought, "every purchase is a deed")


## A deed lifts the seller's town at any share of the tier (wiki: world-market
## § Minor and tribe auto-sell — the town stands at `min(4, 1 + deeds)`,
## DR-20261112-01). The tier's round-robin purchases bypass the Merchant's
## completion, so the town has to rise here or the manufactures a bought-up
## Minor used to pay never reach the book.
func test_a_tier_deed_lifts_the_sellers_town() -> void:
	var works: Dictionary = {}
	var bought: int = AdvancedEstates.purchase_minor_land(
		world, works, FactionCatalog.great_power_ids(),
		AdvancedStart.develop_share(AdvancedStart.TURNS50)
	)
	assert_gte(bought, 1, "the Minor Nations have sold land")
	var lifted: int = 0
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			var deeds: int = MinorTownGrowth.deeds_in(model, province)
			if deeds <= 0:
				continue
			assert_eq(
				province.town_development, MinorTownGrowth.level_for(deeds),
				"province %d stands on %d deeds" % [province.id, deeds]
			)
			if MinorTownGrowth.level_for(deeds) > 1:
				lifted += 1
	assert_gte(lifted, 1, "a bought-up town rose off its level-1 baseline")


func _mineral_count(world: WorldMap, faction: int) -> int:
	var count: int = 0
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if model.province_owner(province.id) != faction:
				continue
			for tile: Vector2i in province.tiles:
				if ImprovementCatalog.needs_prospecting(model.resource_at(tile.x, tile.y)):
					count += 1
	return count
