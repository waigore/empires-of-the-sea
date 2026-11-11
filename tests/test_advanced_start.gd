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
