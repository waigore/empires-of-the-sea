# gdlint: disable=max-public-methods
extends GdToolsTest
## Pure battle contracts: army modifiers, army state, battle reports, naval
## combat and generals.
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).
## Consolidated rulebook: quick battle, siege depth, battle sim, forts and
## sieges, the capital fort grant, the hospital, army field rules, parity and
## the battle overlay (one Godot boot per domain). Merged from
## test_fort_capital so coverage does not pay a second boot for pure fort
## grant cases (docs/testing.md § Speed rules).

const Fixture = preload("res://tests/army_fixture.gd")
const FACTIONS: Array[String] = ["España", "England", "France", "Portugal"]
const SIM_SCENE: PackedScene = preload("res://scenes/battle_sim.tscn")

# --- from test_army_modifiers.gd ---
## Combat modifiers: feeding, medals, deployment, terrain and leaders
## (wiki: combat § Modifiers and configurable values, military-generals § Medals).


func test_feeding_bands_follow_the_published_table() -> void:
	assert_almost_eq(ArmyModifiers.feeding_multiplier(1.0), 1.0, 0.001)
	assert_almost_eq(ArmyModifiers.feeding_multiplier(0.75), 0.75, 0.001)
	assert_almost_eq(ArmyModifiers.feeding_multiplier(0.5), 0.75, 0.001)
	assert_almost_eq(ArmyModifiers.feeding_multiplier(0.49), 0.5, 0.001)


func test_medal_aura_is_five_percent_per_medal_capped_at_twenty() -> void:
	assert_almost_eq(ArmyModifiers.medal_aura(0), 1.0, 0.001)
	assert_almost_eq(ArmyModifiers.medal_aura(2), 1.1, 0.001)
	assert_almost_eq(ArmyModifiers.medal_aura(4), 1.2, 0.001)
	assert_almost_eq(ArmyModifiers.medal_aura(9), 1.2, 0.001)


func test_deployment_limit_grows_with_medals_and_nationalism() -> void:
	assert_eq(ArmyModifiers.deployment_limit(0, false), 10)
	assert_eq(ArmyModifiers.deployment_limit(2, false), 12)
	assert_eq(ArmyModifiers.deployment_limit(0, true), 12)
	assert_eq(ArmyModifiers.deployment_limit(4, true), 16)


func test_terrain_uses_the_dominant_type_and_favours_the_defender() -> void:
	var model := Fixture.build()
	for tile: Vector2i in model.province_data(2).tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.HILLS
	assert_eq(ArmyModifiers.terrain_for(model, 2), MapModel.Terrain.HILLS)
	assert_almost_eq(ArmyModifiers.terrain_multiplier(MapModel.Terrain.HILLS), 1.15, 0.001)
	assert_almost_eq(ArmyModifiers.terrain_multiplier(MapModel.Terrain.PLAINS), 1.0, 0.001)


## A province that names no tiles grounds the battle on plains, and its ranking
## is empty — the sheet then has no runner-up to print (issue #1084).
func test_a_province_with_no_tiles_falls_back_to_plains() -> void:
	var model := Fixture.build()
	assert_eq(ArmyModifiers.terrain_ranking(model, MapModel.NO_ID), [] as Array[int])
	assert_eq(ArmyModifiers.terrain_for(model, MapModel.NO_ID), MapModel.Terrain.PLAINS)


## The ranking lists every terrain the province holds, most common first, so the
## sheet can name the runner-up without a second walk of the tiles (issue #1084).
func test_terrain_ranking_reads_most_common_first() -> void:
	var model := Fixture.build()
	var tiles: Array = model.province_tiles(0)
	for index in tiles.size():
		var tile: Vector2i = tiles[index]
		var terrain: int = MapModel.Terrain.PLAINS
		if index == 0:
			terrain = MapModel.Terrain.SWAMP
		elif index == 1:
			terrain = MapModel.Terrain.HILLS
		model.terrain[model.index_of(tile.x, tile.y)] = terrain
	var ranked: Array[int] = ArmyModifiers.terrain_ranking(model, 0)
	assert_eq(ranked.size(), 3)
	assert_eq(ranked[0], MapModel.Terrain.PLAINS, "the commonest ground leads")
	# Hills and swamp tie at one tile each: the lower terrain id runs second.
	assert_eq(ranked[1], MapModel.Terrain.HILLS)
	assert_eq(ranked[2], MapModel.Terrain.SWAMP)


## The forest split prints both sides of the terrain: 0.9 for the attacker and
## 1.5 / 1.1 for the defender (wiki: resource-terrain-region-rules
## § Acceptance Criteria).
func test_forest_terrain_multiples_both_sides_of_a_battle() -> void:
	var model := Fixture.build()
	_set_province_terrain(model, 2, MapModel.Terrain.HARDWOOD_FOREST)
	var hardwood: Dictionary = _terrain_pair(model)
	assert_almost_eq(float(hardwood["attacker"]), 0.9, 0.001, "a wood slows the advance")
	assert_almost_eq(float(hardwood["defender"]), 1.5, 0.001, "and shelters the line")

	_set_province_terrain(model, 2, MapModel.Terrain.SCRUB_FOREST)
	var scrub: Dictionary = _terrain_pair(model)
	assert_almost_eq(float(scrub["attacker"]), 0.9, 0.001)
	assert_almost_eq(float(scrub["defender"]), 1.1, 0.001)

	_set_province_terrain(model, 2, MapModel.Terrain.PLAINS)
	var plains: Dictionary = _terrain_pair(model)
	assert_almost_eq(float(plains["attacker"]), 1.0, 0.001, "open ground costs the attacker nothing")
	assert_almost_eq(float(plains["defender"]), 1.0, 0.001)


## The modifier is not cosmetic: the same 5 Guards that carry a 9-Pikemen
## garrison in the open are held at a standstill once the wood slows them.
func test_a_wood_holds_where_the_open_field_falls() -> void:
	var open: Dictionary = _fight_in(MapModel.Terrain.PLAINS)
	var wood: Dictionary = _fight_in(MapModel.Terrain.HARDWOOD_FOREST)

	assert_eq(int(open["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_true(bool(open["captured"]))
	assert_eq(int(wood["outcome"]), ArmyCombat.Outcome.STALEMATE)
	assert_false(bool(wood["captured"]), "the province holds")


func _set_province_terrain(model: MapModel, province: int, terrain: int) -> void:
	for tile: Vector2i in model.province_data(province).tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = terrain


func _terrain_pair(model: MapModel) -> Dictionary:
	return {
		"defender": float(
			ArmyModifiers.modifiers({}, 0, true, model, 2, 1)["multiplier"]
		),
		"attacker": float(
			ArmyModifiers.modifiers({}, 0, false, model, 2, 1)["multiplier"]
		),
	}


func _fight_in(terrain: int) -> Dictionary:
	var model := Fixture.build()
	_set_province_terrain(model, 2, terrain)
	var defender := Fixture.army(1, 1, 2, _regiment_types("pikemen", 9), true)
	var attacker := Fixture.army(2, 0, 2, _regiment_types("guards", 5))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})
	return reports[0] if not reports.is_empty() else {}


func _regiment_types(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types


func test_leader_keys_match_exact_and_variant_ids() -> void:
	assert_almost_eq(ArmyModifiers.leader_multiplier("napoleon"), 1.25, 0.001)
	assert_almost_eq(ArmyModifiers.leader_multiplier("france_napoleon_leader"), 1.25, 0.001)
	assert_almost_eq(ArmyModifiers.leader_multiplier("gustavus"), 1.15, 0.001)
	assert_almost_eq(ArmyModifiers.leader_multiplier("gustavus", true), 1.0, 0.001)
	assert_almost_eq(ArmyModifiers.leader_multiplier("frederick", true), 1.15, 0.001)
	assert_almost_eq(ArmyModifiers.leader_multiplier("frederick"), 1.0, 0.001)
	assert_almost_eq(ArmyModifiers.leader_multiplier(""), 1.0, 0.001)
	assert_eq(ArmyModifiers.fallback_medals("napoleon"), 4)
	assert_eq(ArmyModifiers.fallback_medals("gustavus"), 2)
	assert_eq(ArmyModifiers.fallback_medals("gustavus", true), 0)
	assert_eq(ArmyModifiers.fallback_medals("frederick", true), 2)
	assert_eq(ArmyModifiers.fallback_medals(""), 0)


func test_deployed_keeps_the_strongest_regiments() -> void:
	var types: Array[String] = ["guards"]
	for _index in 11:
		types.append("peasant_levies")
	var side: Array[ArmyState] = [Fixture.army(1, 0, 2, types)]
	var deployed: Array[Dictionary] = ArmyModifiers.deployed(side, 10)

	assert_eq(deployed.size(), 10)
	var guards: int = 0
	for entry: Dictionary in deployed:
		var army: ArmyState = entry["army"]
		if army.type_of(String(entry["id"])) == "guards":
			guards += 1
	assert_eq(guards, 1, "the strongest regiment stays deployed")


func test_strength_scales_the_deployed_slice() -> void:
	var side: Array[ArmyState] = [Fixture.army(1, 0, 2, ["pikemen", "pikemen"])]
	assert_almost_eq(ArmyModifiers.strength(side, 10, 1.2), 12.0, 0.001)


## The line is the strongest `limit` regiments; the rest are reserves that take
## no casualties (wiki: combat § The line and the reserve; DR-20261111-15).
func test_casualties_are_drawn_from_the_line_and_spare_the_reserve() -> void:
	var types: Array[String] = ["guards"]
	for _index in 13:
		types.append("peasant_levies")
	var army := Fixture.army(1, 0, 2, types)
	var side: Array[ArmyState] = [army]
	var deployed_ids: Array[String] = []
	for entry: Dictionary in ArmyModifiers.deployed(side, 10):
		deployed_ids.append(String(entry["id"]))
	var reserve_ids: Array[String] = []
	for regiment_id: String in army.regiments:
		if not deployed_ids.has(regiment_id):
			reserve_ids.append(regiment_id)
	assert_eq(reserve_ids.size(), 4, "four regiments stand in reserve")

	var lost: Array[String] = ArmyForce.apply_losses([army], side, 4, 10)

	assert_eq(lost.size(), 4)
	for regiment_id: String in reserve_ids:
		assert_true(army.regiments.has(regiment_id), "a reserve is never a casualty")


## A reserve takes no battle wear either: an auto-resolved exchange spends its
## wounds over the line it dealt when it opened, never over the reserves that
## would fill the slice once casualties have thinned it (wiki: combat § The line
## and the reserve — "a reserve adds no strength, takes no casualties, and takes
## no battle wear"). The prober read 99/110 on two of the four reserves before
## the fix, because the wear pass re-read the strongest `limit` survivors.
func test_an_auto_resolved_exchange_never_wears_a_reserve() -> void:
	var model := Fixture.build()
	_set_province_terrain(model, 2, MapModel.Terrain.PLAINS)
	var defender: ArmyState = Fixture.army(1, 1, 2, ["pikemen"], true)
	var marching: ArmyState = Fixture.army(2, 0, 2, _regiment_types("pikemen", 14))
	marching.moved = true
	var side: Array[ArmyState] = [marching]
	var line_ids: Array[String] = []
	for entry: Dictionary in ArmyModifiers.deployed(side, 10):
		line_ids.append(String(entry["id"]))
	assert_eq(line_ids.size(), 10, "ten stand in the line")
	var reserve: Array[String] = []
	for regiment_id: String in marching.regiments:
		if not line_ids.has(regiment_id):
			reserve.append(regiment_id)
	assert_eq(reserve.size(), 4, "four stand in reserve")

	var armies: Array[ArmyState] = [defender, marching]
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})

	assert_eq(reports.size(), 1)
	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_false((reports[0]["attacker_lost"] as Array).is_empty(), "the line bleeds")
	assert_true(RegimentCondition.mauled(side) > 0, "the line carries the wear")
	for regiment_id: String in reserve:
		var data: Dictionary = marching.condition_of(regiment_id)
		assert_eq(
			int(data["hp"]), int(data["max"]),
			"a reserve takes no battle wear: %s" % regiment_id
		)


## A reserve adds no strength to a blow either (wiki: combat § The line and the
## reserve — "a reserve adds no strength"; quick-battle § Battlefield layout —
## "the reserve is dealt nowhere ... take no casualties and add no strength").
## Playtest: a line of six musketeers broke two men a volley; the same six with
## eight pikemen waiting behind them broke two, two, then three — the blow was
## weighed over the strongest ten of the side, so the men the battle never dealt
## lent it their weight once the line had thinned.
func test_a_reserve_adds_no_weight_to_a_blow() -> void:
	var line: Array[String] = []
	for entry: Dictionary in ArmyForce.side_entries(_lane_side(_muskets(6), 2)):
		line.append(String(entry["id"]))
	var bare: Array[ArmyState] = _lane_side(_muskets(6), 2)
	var stuffed_types: Array[String] = _muskets(6)
	stuffed_types.append_array(_pikes(8))
	var stuffed: Array[ArmyState] = _lane_side(stuffed_types, 2)
	assert_eq(line.size(), 6)
	assert_true(
		ArmyModifiers.strength(stuffed, 10, 1.0) > ArmyForce.line_strength(stuffed, line, 1.0),
		"the limit slice weighs more than the dealt line: that is the weight the old read paid"
	)

	var with_line: Array[int] = _volley_losses(bare, line)
	var with_reserve: Array[int] = _volley_losses(stuffed, line)

	assert_eq(with_line, [2, 2, 2], "six muskets break two a volley")
	assert_eq(
		with_reserve, with_line,
		"eight pikemen behind the line change no volley's weight"
	)


## The mean enemy weight is read over the men its line was dealt too, so a fresh
## reserve never props up a mauled line: a wounded muzzle line is as soft as its
## own survivors, not as tough as the men behind it (wiki: quick-battle § Cohesion
## and effective strength — "reserves behind the deployment limit never count").
func test_a_mauled_line_reads_its_own_mean_weight() -> void:
	var side_types: Array[String] = _muskets(3)
	side_types.append_array(_pikes(6))
	var side: Array[ArmyState] = _lane_side(side_types, 1)
	var line: Array[String] = []
	for entry: Dictionary in ArmyForce.side_entries(side):
		if line.size() < 3:
			line.append(String(entry["id"]))
	var thin: Array[ArmyState] = _lane_side(_muskets(3), 1)
	for regiment_id: String in line:
		RegimentCondition.wound(side[0], regiment_id, 80.0)
		RegimentCondition.wound(thin[0], regiment_id, 80.0)

	assert_almost_eq(
		ArmyModifiers.average_rank(side, 10, line),
		ArmyModifiers.average_rank(thin, 10), 0.001
	)
	assert_true(
		ArmyModifiers.average_rank(side, 10) > ArmyModifiers.average_rank(side, 10, line),
		"the limit slice would let six fresh pikes prop up the mauled line"
	)
	assert_true(
		ArmyModifiers.average_rank(side, 10, line) < RegimentCatalog.strength("pikemen"),
		"the line reads as its own wounded men, not as the pikes behind it"
	)


## A besieger's shot is weighed over its dealt line as well: a musket held in
## reserve carries nothing to the wall (wiki: siege-mechanics § Quick Battle
## lanes; combat § The line and the reserve).
func test_a_besiegers_reserve_carries_no_shot_to_the_wall() -> void:
	var side: Array[ArmyState] = _lane_side(_muskets(12), 2)
	var line: Array[String] = []
	for entry: Dictionary in ArmyForce.side_entries(side):
		if line.size() < 6:
			line.append(String(entry["id"]))

	var dealt: float = SiegeLanes.striking_weight(side, 10, 1.0, line)
	var whole: float = SiegeLanes.striking_weight(side, 10, 1.0)

	assert_almost_eq(whole, 10.0 * RegimentCatalog.strength("musketeers"), 0.001)
	assert_almost_eq(dealt, 6.0 * RegimentCatalog.strength("musketeers"), 0.001)
	assert_true(dealt < whole, "the six muskets in reserve strike nothing")


## Three volleys of one attacking side against a fresh line of ten pikes, read
## off a hand-built state shaped as [QuickBattle] builds it: the losses it breaks
## per volley.
func _volley_losses(side: Array[ArmyState], line: Array[String]) -> Array[int]:
	var defender: Array[ArmyState] = _lane_side(_pikes(10), 1)
	var armies: Array[ArmyState] = []
	armies.append_array(side)
	armies.append_array(defender)
	var state: Dictionary = _lane_state(side, defender, 0)
	state["attacker"]["line"] = line
	var broken: Array[int] = []
	for _index in 3:
		var entry: Dictionary = QuickBattleActions.resolve(
			armies, state, "attacker", "defender", "volley", [] as Array[Dictionary]
		)
		broken.append(int(entry["defender_lost"]))
	return broken


## The report carries the line and the reserve so the plate and the despatch can
## name them (wiki: combat § The line and the reserve; DR-20261111-15). The line
## is read before any exchange, while every regiment is still standing.
func test_the_report_names_the_line_and_the_reserve() -> void:
	var defending: Array[ArmyState] = [Fixture.army(1, 1, 2, _regiment_types("pikemen", 9), true)]
	var attacking: Array[ArmyState] = [Fixture.army(2, 0, 2, _regiment_types("guards", 14))]

	var line: Dictionary = ArmyModifiers.line_fields(attacking, 10, defending, 10)

	assert_eq(int(line["attacker_deployed"]), 10)
	assert_eq(int(line["attacker_reserve"]), 4)
	assert_eq(int(line["attacker_limit"]), 10)
	assert_eq(int(line["defender_deployed"]), 9)
	assert_eq(int(line["defender_reserve"]), 0)


## The chain carries its winner: after the first attacker takes the field, the
## next attacker fights the captor, and the province ends with the side the last
## engagement leaves holding it (wiki: combat § Multi-Attacker Chain — "the
## previous battle's winner (without healing or regenerating regiments) and the
## next attacker"; § Province Flip — the province flips "to the attacker faction
## that was last in the chain"). Playtest: two Great Powers fell on one province,
## the first wiped the garrison and the second never fought — it stood in a
## province another court had just taken.
func test_the_chain_carries_a_winner_against_the_next_attacker() -> void:
	var model := Fixture.build()
	var defender: ArmyState = Fixture.army(1, 1, 2, ["peasant_levies"])
	var first: ArmyState = Fixture.army(2, 0, 2, _regiment_types("regulars", 4))
	var second: ArmyState = Fixture.army(3, 2, 2, _regiment_types("regulars", 4))
	first.moved = true
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})

	assert_eq(reports.size(), 2, "the second attacker meets the first's winner")
	if reports.size() < 2:
		return
	assert_true(bool(reports[0]["captured"]), "the first attacker takes the field")
	assert_eq(
		int(reports[1]["defender"]), int(reports[0]["attacker"]),
		"the winner holds the field against the next attacker"
	)
	if bool(reports[1]["captured"]):
		assert_eq(
			model.province_owner(2), int(reports[1]["attacker"]),
			"the last winner holds the province"
		)
	else:
		assert_eq(
			model.province_owner(2), int(reports[1]["defender"]),
			"the holder the chain leaves keeps the province"
		)


func test_modifiers_compose_terrain_feeding_and_leader() -> void:
	var model := Fixture.build()
	for tile: Vector2i in model.province_data(2).tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.HILLS
	var context: Dictionary = {
		"feeding": {1: 0.5},
		"leaders": {1: "napoleon"},
	}
	var defender: Dictionary = ArmyModifiers.modifiers(context, 0, true, model, 2, 1)
	assert_almost_eq(float(defender["multiplier"]), 0.75 * 1.25 * 1.15, 0.001)
	var attacker: Dictionary = ArmyModifiers.modifiers(context, 0, false, model, 2, 1)
	assert_almost_eq(float(attacker["multiplier"]), 0.75 * 1.25, 0.001)

	var nationalism: Dictionary = {"tech": {1: {"nationalism": true}}}
	var limit: int = int(ArmyModifiers.modifiers(nationalism, 2, false, model, 2, 1)["limit"])
	assert_eq(limit, 14)

# --- from test_army_state.gd ---
## Army containers: composition, split, combine and the Home Army invariant
## (wiki: military-armies).


func test_muster_mints_stable_regiment_instances() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen", "squires", "pikemen"], true)
	assert_eq(army.count(), 3)
	assert_true(army.is_home_army())
	assert_eq(army.type_of("unit_101"), "pikemen")
	assert_eq(army.type_of("unit_102"), "squires")
	assert_eq(army.count_of_type("pikemen"), 2)
	assert_almost_eq(army.strength(), 14.0, 0.001)
	assert_almost_eq(army.cavalry_share(), 1.0 / 3.0, 0.001)
	assert_eq(army.composition_text(), "2 Pikemen · Squires")


func test_unknown_regiment_types_fall_back_to_the_default() -> void:
	var army := ArmyState.create(1, 0, 0, false, ["unit_1"], {"unit_1": "dragoons"})
	assert_eq(army.type_of("unit_1"), RegimentCatalog.DEFAULT_TYPE)
	assert_eq(army.type_of("missing"), RegimentCatalog.DEFAULT_TYPE)


func test_split_moves_only_the_chosen_instances() -> void:
	var army := Fixture.army(1, 0, 0, ["peasant_levies", "pikemen", "guards"], true)
	army.moved = true
	var armies: Array[ArmyState] = [army]
	var ids: Array[String] = ["unit_102"]

	var result: Dictionary = ArmyRoster.split(armies, army, ids, 2)

	assert_true(bool(result["ok"]))
	assert_eq(armies.size(), 2)
	assert_eq(army.count(), 2)
	assert_false(army.regiments.has("unit_102"))
	var field: ArmyState = result["army"] as ArmyState
	assert_eq(field.count(), 1)
	assert_eq(field.type_of("unit_102"), "pikemen")
	assert_eq(field.province, army.province)
	assert_eq(field.owner, army.owner)
	assert_false(field.is_home_army())
	assert_true(field.moved)


func test_split_rejects_unknown_or_empty_selections() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"], true)
	var armies: Array[ArmyState] = [army]
	var none: Array[String] = []
	assert_false(bool(ArmyRoster.split(armies, army, none, 2)["ok"]))
	var foreign: Array[String] = ["unit_999"]
	assert_false(bool(ArmyRoster.split(armies, army, foreign, 2)["ok"]))
	assert_eq(army.count(), 1)


func test_emptying_a_field_army_removes_it_but_the_home_army_persists() -> void:
	var home := Fixture.army(1, 0, 0, ["pikemen"], true)
	var field := Fixture.army(2, 0, 1, ["pikemen"])
	var armies: Array[ArmyState] = [home, field]
	var home_ids: Array[String] = ["unit_101"]
	var field_ids: Array[String] = ["unit_201"]

	ArmyRoster.split(armies, field, field_ids, 3)
	ArmyRoster.split(armies, home, home_ids, 4)

	assert_false(armies.has(field))
	assert_true(armies.has(home))
	assert_true(home.is_empty())


func test_combine_uses_the_home_army_as_the_target() -> void:
	var field := Fixture.army(1, 0, 0, ["pikemen"])
	var home := Fixture.army(2, 0, 0, ["squires"], true)
	var armies: Array[ArmyState] = [field, home]
	var selected: Array[ArmyState] = [field, home]

	var result: Dictionary = ArmyRoster.combine(armies, selected)

	assert_true(bool(result["ok"]))
	assert_eq(armies.size(), 1)
	assert_true(armies[0].is_home_army())
	assert_eq(armies[0].count(), 2)
	assert_eq(armies[0].count_of_type("pikemen"), 1)
	assert_eq(armies[0].count_of_type("squires"), 1)


func test_combine_keeps_the_first_army_when_no_home_army_is_present() -> void:
	var first := Fixture.army(1, 0, 0, ["pikemen"])
	var second := Fixture.army(2, 0, 0, ["squires"])
	var armies: Array[ArmyState] = [first, second]
	var selected: Array[ArmyState] = [first, second]

	var result: Dictionary = ArmyRoster.combine(armies, selected)

	assert_true(bool(result["ok"]))
	assert_eq(result["army"], first)
	assert_eq(first.count(), 2)
	assert_false(armies.has(second))


## The panel stacks a province's standards by army id, so the standard the crown
## sees first absorbs the rest whatever it tapped (wiki: military-armies
## § Split and combine — "the first selected army in panel display order").
func test_combine_keeps_the_panel_first_army_whatever_the_tap() -> void:
	var earlier := Fixture.army(3, 0, 0, ["pikemen"])
	var later := Fixture.army(9, 0, 0, ["squires"])
	var armies: Array[ArmyState] = [later, earlier]
	var selected: Array[ArmyState] = [later, earlier]

	var result: Dictionary = ArmyRoster.combine(armies, selected)

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(result["army"], earlier, "the standard the panel prints first")
	assert_eq(earlier.count(), 2)
	assert_false(armies.has(later))


func test_combine_rejects_armies_in_different_provinces() -> void:
	var here := Fixture.army(1, 0, 0, ["pikemen"])
	var there := Fixture.army(2, 0, 1, ["pikemen"])
	var armies: Array[ArmyState] = [here, there]
	var selected: Array[ArmyState] = [here, there]

	var result: Dictionary = ArmyRoster.combine(armies, selected)

	assert_false(bool(result["ok"]))
	assert_eq(armies.size(), 2)
	assert_eq(here.count(), 1)
	assert_eq(there.count(), 1)


func test_combine_requires_two_armies() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	var armies: Array[ArmyState] = [army]
	var selected: Array[ArmyState] = [army]
	assert_false(bool(ArmyRoster.combine(armies, selected)["ok"]))


## Split/combine is a land order: the wiki scopes it to armies that share a
## province (military-armies § Split and combine), and an embarked army has no
## province — a squadron carries it as one (ships-and-naval § Naval transport).
func test_split_refuses_an_army_aboard_a_squadron() -> void:
	var model := Fixture.build()
	var army := Fixture.army(1, 0, 0, ["pikemen", "squires"])
	var fleet := FleetState.in_port(1, 0, 0, ["ship_1", "ship_2"])
	assert_true(bool(NavalTransport.embark(model, army, fleet)["ok"]))
	var armies: Array[ArmyState] = [army]
	var ids: Array[String] = ["unit_101"]

	var result: Dictionary = ArmyRoster.split(armies, army, ids, 2)

	assert_false(bool(result["ok"]), "troops aboard cannot detach mid-voyage")
	assert_eq(armies.size(), 1)
	assert_eq(army.count(), 2)
	assert_eq(army.embarked_fleet, fleet.id)


func test_combine_refuses_armies_aboard_a_squadron() -> void:
	var model := Fixture.build()
	var first := Fixture.army(1, 0, 0, ["pikemen"])
	var second := Fixture.army(2, 0, 0, ["squires"])
	var fleet_a := FleetState.in_port(1, 0, 0, ["ship_1"])
	var fleet_b := FleetState.in_port(2, 0, 0, ["ship_2"])
	assert_true(bool(NavalTransport.embark(model, first, fleet_a)["ok"]))
	assert_true(bool(NavalTransport.embark(model, second, fleet_b)["ok"]))
	var armies: Array[ArmyState] = [first, second]
	var selected: Array[ArmyState] = [first, second]

	var result: Dictionary = ArmyRoster.combine(armies, selected)

	assert_false(bool(result["ok"]), "two squadrons cannot pool their troops")
	assert_eq(armies.size(), 2)
	assert_eq(first.count(), 1)
	assert_eq(second.count(), 1)
	assert_eq(fleet_a.embarked_army, first.id)
	assert_eq(fleet_b.embarked_army, second.id)


func test_prune_drops_empty_field_armies_only() -> void:
	var none: Array[String] = []
	var home := Fixture.army(1, 0, 0, none, true)
	var field := Fixture.army(2, 0, 1, none)
	var armies: Array[ArmyState] = [home, field]
	ArmyRoster.prune(armies)
	assert_eq(armies.size(), 1)
	assert_true(armies.has(home))


## Field armies are the court's deployed columns in stable id order: the Home
## Army, an emptied column and a foreign army stay out (REQ-P3-01, REQ-P3-04).
func test_field_armies_reads_the_deployed_columns_in_id_order() -> void:
	var none: Array[String] = []
	var home := Fixture.army(1, 0, 0, none, true)
	var late := Fixture.army(7, 0, 2, ["pikemen"])
	var early := Fixture.army(3, 0, 1, ["squires"])
	var empty := Fixture.army(5, 0, 3, none)
	var foreign := Fixture.army(2, 1, 1, ["pikemen"])
	var field: Array[ArmyState] = ArmyRoster.field_armies(
		[home, late, early, empty, foreign], 0
	)
	assert_eq(field.size(), 2)
	assert_eq(field[0], early)
	assert_eq(field[1], late)


## A detached or combined-away regiment leaves nothing behind on its old army:
## the condition and the record are one store, released together.
func test_a_removed_regiment_leaves_no_condition_behind() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen", "pikemen", "guards"], true)

	assert_true(army.remove_regiment("unit_102"))
	assert_false(army.remove_regiment("unit_102"), "a second removal is refused")

	assert_false(army.regiment_health.has("unit_102"), "no health for a departed regiment")
	assert_false(army.regiment_medals.has("unit_102"), "no chevrons for a departed regiment")
	assert_false(army.regiment_names.has("unit_102"), "no title for a departed regiment")
	assert_false(army.regiment_engagements.has("unit_102"))
	assert_true(army.regiment_health.has("unit_101"), "the survivors keep theirs")


func test_a_joined_empire_regiments_are_handed_over_in_place() -> void:
	var home := Fixture.army(1, 6, 1, ["pikemen"], true)
	var field := Fixture.army(2, 6, 2, ["squires"])
	var armies: Array[ArmyState] = [home, field]

	ArmyRoster.hand_over(armies, 6, 4)

	assert_eq(armies.size(), 2, "an absorption retires nobody")
	assert_eq(home.owner, 4)
	assert_eq(field.owner, 4)
	assert_false(home.home, "the winner keeps exactly one Home Army")
	assert_false(field.home)


func test_a_terminal_fall_retires_the_crowns_armies() -> void:
	var die := Fixture.army(1, 6, 1, ["pikemen"], true)
	var keep := Fixture.army(2, 4, 2, ["squires"], true)
	var armies: Array[ArmyState] = [die, keep]

	ArmyRoster.hand_over(armies, 6, MapModel.NO_ID)

	assert_eq(armies, [keep] as Array[ArmyState], "only the fallen crown's armies leave")
	assert_eq(keep.owner, 4, "the survivor's colours are untouched")

# --- from test_battle_report.gd ---
## Despatch wording for resolved battles (moved out of the screen controller).


func test_a_side_one_victory_reads_as_a_held_zone() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["a", "b"],
	}
	assert_eq(BattleReport.describe(battle, "Windward Passage", FACTIONS),
		"España holds the Windward Passage — England loses 2 ships")


func test_a_side_two_victory_reads_as_a_repulse() -> void:
	var battle: Dictionary = {
		"attacker": 1,
		"defender": 2,
		"outcome": NavalCombat.Outcome.SIDE2_VICTORY,
		"attacker_lost": ["a"],
		"defender_lost": [],
	}
	assert_eq(BattleReport.describe(battle, "Gulf of Darién", FACTIONS),
		"France repels England in the Gulf of Darién — England loses 1 ship")


## A winning side still spends hulls on the beaten side's damage pool, and the
## despatch names both sides' dead — a crown never loses a named hull in silence
## (DR-20261111-07, REQ-P5-05).
func test_the_despatch_names_both_sides_losses() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": ["a"],
		"attacker_lost_names": ["Trinidad"],
		"defender_lost": ["b", "c"],
		"defender_lost_names": ["Revenge", "Vanguard"],
		"attacker_strength": 18.25,
		"defender_strength": 11.0,
	}
	assert_eq(
		BattleReport.describe(battle, "Windward Passage", FACTIONS),
		"España holds the Windward Passage — England loses 2 ships"
		+ " (Revenge, Vanguard); España loses 1 ship (Trinidad)"
		+ " — 18.2 strength to 11.0"
	)


## A beaten side that slips away keeps every hull, but the holder still pays for
## the win: the retreat despatch names the hulls it spent.
func test_a_retreat_despatch_names_the_holders_own_losses() -> void:
	var battle: Dictionary = {
		"attacker": 1,
		"defender": 0,
		"outcome": NavalCombat.Outcome.SIDE2_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["a"],
		"defender_lost_names": ["Trinidad"],
		"retreat": {"success": true, "beaten": 1},
	}
	assert_eq(
		BattleReport.describe(battle, "Mar Tirreno", FACTIONS),
		"England withdraws from the Mar Tirreno — España holds the zone"
		+ "; España loses 1 ship (Trinidad)"
	)


## The resolver records the names of every hull it sinks, read before the hull
## leaves the roster (the name lives on the fleet and dies with it).
func test_a_resolved_battle_records_the_names_it_sank() -> void:
	var strong := FleetState.at_sea(1, 0, 0, ["a", "b"], {"a": "frigate", "b": "frigate"})
	var weak := FleetState.at_sea(2, 1, 0, ["c"], {"c": "fluyte"})
	var doomed_name: String = ShipNames.of(weak, "c")

	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])

	assert_gt(battles.size(), 0)
	var battle: Dictionary = battles[0]
	var lost: Array = battle.get("attacker_lost", []) if int(battle["attacker"]) == 1 \
		else battle.get("defender_lost", [])
	assert_eq(lost, ["c"], "the weak squadron's hull is the one sunk")
	assert_eq(
		battle.get("attacker_lost_names", []) if int(battle["attacker"]) == 1 \
			else battle.get("defender_lost_names", []),
		[doomed_name],
		"the report names the hull it sank"
	)


func test_a_stalemate_reads_as_a_withdrawal() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 3,
		"outcome": NavalCombat.Outcome.STALEMATE,
		"attacker_lost": [],
		"defender_lost": [],
	}
	assert_eq(BattleReport.describe(battle, "Azores", FACTIONS),
		"España and Portugal trade broadsides in the Azores and withdraw")


## The despatch carries the arithmetic behind the verdict, so the court sees why
## one side held the zone (wiki: ships-and-naval § Naval Strength Aggregation).
func test_the_despatch_names_the_strength_behind_the_verdict() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["a", "b"],
		"attacker_strength": 18.25,
		"defender_strength": 11.0,
	}
	assert_eq(
		BattleReport.describe(battle, "Windward Passage", FACTIONS),
		"España holds the Windward Passage — England loses 2 ships"
		+ " — 18.2 strength to 11.0"
	)


## A resolved clash always carries the strengths the resolver fought with.
func test_a_resolved_battle_prints_its_strengths() -> void:
	var strong := FleetState.at_sea(1, 0, 0, ["a", "b"], {"a": "frigate", "b": "frigate"})
	var weak := FleetState.at_sea(2, 1, 0, ["c"], {"c": "carrack"})

	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])

	assert_gt(battles.size(), 0)
	assert_true(
		BattleReport.describe(battles[0], "Azores", FACTIONS).contains("strength to"),
		"the despatch names the odds"
	)


func test_unknown_flags_do_not_crash_the_despatch() -> void:
	var battle: Dictionary = {
		"attacker": 9,
		"defender": -1,
		"outcome": NavalCombat.Outcome.STALEMATE,
	}
	var text: String = BattleReport.describe(battle, "Nowhere", FACTIONS)
	assert_true(text.contains("An unknown flag"))


func test_a_land_victory_reads_as_a_capture() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"attacker_lost": ["a"],
		"defender_lost": ["b", "c"],
	}
	assert_eq(
		BattleReport.describe_land(battle, "Flanders", FACTIONS),
		"España takes Flanders — England loses 2 regiments; España loses 1 regiment"
	)


## A won field names the winner's own dead as well as the beaten side's, and a
## side that left nobody stays unspoken rather than printing a zero
## (wiki: combat § Land battle resolution; DR-20261119-07).
func test_a_land_victory_without_losses_names_only_the_beaten_side() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["b", "c"],
	}
	assert_eq(
		BattleReport.describe_land(battle, "Flanders", FACTIONS),
		"España takes Flanders — England loses 2 regiments"
	)
	var bloodless: Dictionary = battle.duplicate()
	bloodless["defender_lost"] = []
	assert_eq(
		BattleReport.describe_land(bloodless, "Flanders", FACTIONS),
		"España takes Flanders",
		"a bloodless beaten side prints no zero"
	)


func test_a_land_advantage_reads_as_a_held_field() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.ATTACKER_ADVANTAGE,
		"attacker_lost": ["a"],
		"defender_lost": ["b", "c"],
	}
	assert_eq(
		BattleReport.describe_land(battle, "Flanders", FACTIONS),
		"España holds the field at Flanders — England loses 2 regiments; España loses 1 regiment"
	)


func test_a_land_repulse_reads_as_a_hold() -> void:
	var battle: Dictionary = {
		"attacker": 1,
		"defender": 2,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"attacker_lost": ["a"],
		"defender_lost": ["b"],
	}
	assert_eq(
		BattleReport.describe_land(battle, "Burgundy", FACTIONS),
		"France holds Burgundy — England loses 1 regiment; France loses 1 regiment"
	)
	var unscathed: Dictionary = battle.duplicate()
	unscathed["defender_lost"] = []
	assert_eq(
		BattleReport.describe_land(unscathed, "Burgundy", FACTIONS),
		"France holds Burgundy — England loses 1 regiment"
	)


func test_mutual_annihilation_reports_the_reformed_garrison() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.MUTUAL_ANNIHILATION,
		"garrison": 1,
		"recovered_type": "guards",
	}
	assert_eq(
		BattleReport.describe_land(battle, "Artois", FACTIONS),
		"España and England destroy each other at Artois — a Guards garrison reforms"
	)


func test_mutual_annihilation_without_a_garrison_reads_empty() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.MUTUAL_ANNIHILATION,
		"garrison": 0,
	}
	assert_eq(
		BattleReport.describe_land(battle, "Artois", FACTIONS),
		"España and England destroy each other at Artois — the province stands empty"
	)


func test_an_unopposed_capture_and_a_stalemate_read_plainly() -> void:
	var capture: Dictionary = {
		"attacker": 0,
		"defender": 3,
		"outcome": ArmyCombat.Outcome.CAPTURE,
	}
	assert_eq(
		BattleReport.describe_land(capture, "Algarve", FACTIONS),
		"España occupies Algarve unopposed"
	)
	var standoff: Dictionary = {
		"attacker": 0,
		"defender": 2,
		"outcome": ArmyCombat.Outcome.STALEMATE,
	}
	assert_eq(
		BattleReport.describe_land(standoff, "Picardy", FACTIONS),
		"España and France stand off at Picardy"
	)

## combat § Garrison recovery: the reformed garrison is a new standard and new
## men, so it takes the crown's own id cursors when the pass carries them. A
## roster scan alone reuses an id the other chart still wears, and the next
## split or muster then hands the same number out twice
## (wiki: military-armies § Split and combine).
func test_a_recovered_garrison_mints_from_the_crowns_id_cursors() -> void:
	var roster: Array[ArmyState] = [
		ArmyState.muster(1, 0, 0, true, ["pikemen", "pikemen"], 1),
		ArmyState.muster(2, 0, 2, false, ["pikemen", "pikemen"], 3),
	]
	var cursors: Dictionary = {"army": 7, "regiment": 9}
	var recovery: Dictionary = ArmyGarrison.recover(roster, 2, 0, 4, {"ids": cursors})

	assert_eq(int(recovery["count"]), 1)
	assert_eq(roster.size(), 3)
	assert_eq(roster[2].id, 7, "the new standard takes the crown's next army id")
	assert_eq(roster[2].regiments, ["unit_9"], "and the crown's next regiment id")
	assert_eq(int(cursors["army"]), 8, "the cursor moves past what it minted")
	assert_eq(int(cursors["regiment"]), 10)


func test_a_recovered_garrison_without_cursors_mints_above_the_roster() -> void:
	var roster: Array[ArmyState] = [
		ArmyState.muster(1, 0, 0, true, ["pikemen", "pikemen"], 1),
		ArmyState.muster(2, 0, 2, false, ["pikemen", "pikemen"], 3),
	]
	ArmyGarrison.recover(roster, 2, 0, 4, {})

	assert_eq(roster[2].id, 3, "a hand-built roster still mints above its own armies")
	assert_eq(roster[2].regiments, ["unit_5"], "and above its own men")


func test_a_stale_cursor_never_reuses_a_live_id() -> void:
	var roster: Array[ArmyState] = [
		ArmyState.muster(1, 0, 0, true, ["pikemen", "pikemen"], 1),
		ArmyState.muster(2, 0, 2, false, ["pikemen", "pikemen"], 3),
	]
	var cursors: Dictionary = {"army": 1, "regiment": 1}
	ArmyGarrison.recover(roster, 2, 0, 4, {"ids": cursors})

	assert_eq(roster[2].id, 3, "the roster's live ids win over a stale cursor")
	assert_eq(roster[2].regiments, ["unit_5"])
	assert_eq(int(cursors["army"]), 4)
	assert_eq(int(cursors["regiment"]), 6)


# --- from test_naval_combat.gd ---
## Sea-zone combat (wiki: ships-and-naval § Naval Combat).


func _fleet(id: int, owner: int, zone: int, types: Array) -> FleetState:
	var fleet := FleetState.at_sea(id, owner, zone)
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for index in types.size():
		var hull_id: String = "ship_%d_%d" % [id, index]
		hull_ids.append(hull_id)
		hull_types[hull_id] = types[index]
	fleet.set_hulls(hull_ids, hull_types)
	return fleet


func _squadron(id: int, owner: int, zone: int, type_id: String, count: int) -> FleetState:
	var types: Array = []
	for _index in count:
		types.append(type_id)
	return _fleet(id, owner, zone, types)


func test_side_strength_and_durability_aggregate_every_hull() -> void:
	var fleet: FleetState = _fleet(1, 0, 3, ["carrack", "sloop"])
	assert_almost_eq(NavalCombat.side_strength([fleet]), 6.0, 0.0001)
	assert_almost_eq(NavalCombat.side_durability([fleet]), 4.4, 0.0001)
	assert_eq(NavalCombat.side_hull_count([fleet]), 2)


func test_contested_zones_need_two_factions_at_sea() -> void:
	var spanish: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var dutch: FleetState = _squadron(2, 1, 2, "fluyte", 1)
	var ally: FleetState = _squadron(3, 0, 2, "sloop", 1)
	assert_eq(NavalCombat.contested_zones([spanish, dutch, ally]), [2])


func test_single_faction_or_port_fleets_do_not_fight() -> void:
	var spanish: FleetState = _squadron(1, 0, 2, "carrack", 1)
	var consort: FleetState = _squadron(2, 0, 2, "carrack", 1)
	var docked: FleetState = FleetState.in_port(3, 1, 0)
	assert_eq(NavalCombat.contested_zones([spanish, consort, docked]), [])


func test_peaceful_fleets_do_not_contest_a_zone() -> void:
	var spanish: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var dutch: FleetState = _squadron(2, 1, 2, "fluyte", 1)
	var peace := func(_a: int, _b: int) -> bool: return false
	var war := func(_a: int, _b: int) -> bool: return true
	assert_eq(NavalCombat.contested_zones([spanish, dutch], peace), [])
	assert_true(NavalCombat.resolve_turn([spanish, dutch], peace).is_empty())
	assert_eq(NavalCombat.contested_zones([spanish, dutch], war), [2])


func test_a_third_party_at_peace_stays_out_of_a_war() -> void:
	var spanish: FleetState = _squadron(1, 0, 2, "carrack", 3)
	var dutch: FleetState = _squadron(2, 1, 2, "fluyte", 1)
	var swede: FleetState = _squadron(3, 5, 2, "carrack", 1)
	var only_dutch_at_war := func(a: int, b: int) -> bool:
		return (a == 0 and b == 1) or (a == 1 and b == 0)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[spanish, dutch, swede], only_dutch_at_war
	)
	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["defender"]), 1)
	assert_eq(swede.ship_count(), 1, "a neutral fleet is untouched")


## A neutral owner with a lower id must not steal the initiative from the two
## belligerents (wiki: ships-and-naval § Naval Combat attacker/defender).
func test_a_neutral_lower_owner_does_not_take_the_initiative() -> void:
	var neutral: FleetState = _squadron(1, 0, 2, "carrack", 1)
	var first: FleetState = _squadron(2, 2, 2, "carrack", 1)
	var second: FleetState = _squadron(3, 3, 2, "carrack", 1)
	var only_23 := func(a: int, b: int) -> bool:
		return (a == 2 and b == 3) or (a == 3 and b == 2)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[neutral, first, second], only_23
	)
	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["attacker"]), 2)
	assert_eq(neutral.ship_count(), 1, "the neutral fleet is untouched")


func test_the_moved_fleet_attacks() -> void:
	var defender: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var attacker: FleetState = _squadron(2, 1, 2, "sloop", 2)
	attacker.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([defender, attacker])
	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["attacker"]), 1)
	assert_eq(int(battles[0]["defender"]), 0)


func test_without_a_mover_the_lowest_owner_takes_the_initiative() -> void:
	var first: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var second: FleetState = _squadron(2, 2, 2, "fluyte", 1)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([second, first])
	assert_eq(int(battles[0]["attacker"]), 0)


func test_matched_squadrons_stalemate_without_losses() -> void:
	var first: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var second: FleetState = _squadron(2, 1, 2, "carrack", 2)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([first, second])
	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.STALEMATE)
	assert_eq(first.ship_count(), 2)
	assert_eq(second.ship_count(), 2)
	assert_eq(NavalCombat.outcome_label(int(battles[0]["outcome"])), "stalemate")


## A hungry squadron fights at the army morale bands (wiki:
## workers-and-population § Consumption — fullyFedShips / totalShips).
func test_a_starving_squadron_fights_at_the_hungry_morale_band() -> void:
	var first: FleetState = _squadron(1, 0, 2, "carrack", 2)
	var second: FleetState = _squadron(2, 1, 2, "carrack", 2)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[first, second], Callable(), {"navy_feeding": {0: 0.4, 1: 1.0}}
	)
	assert_almost_eq(float(battles[0]["attacker_strength"]), 2.75, 0.0001)
	assert_almost_eq(float(battles[0]["defender_strength"]), 5.5, 0.0001)
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.SIDE2_VICTORY)


## Wiki: share > 0.53 wins for the attacker and share < 0.47 wins for the
## defender — 0.53 exactly is still a stalemate (§ Naval Combat Resolution).
func test_a_share_of_exactly_fifty_three_percent_is_a_stalemate() -> void:
	var attacker: FleetState = _fleet(
		1, 0, 9, _types("carrack", 4) + _types("fluyte", 24)
	)
	var defender: FleetState = _fleet(
		2, 1, 9, _types("carrack", 5) + _types("fluyte", 19)
	)
	attacker.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([attacker, defender])
	assert_eq(battles.size(), 1)
	assert_almost_eq(float(battles[0]["attacker_strength"]), 53.0, 0.0001)
	assert_almost_eq(float(battles[0]["defender_strength"]), 47.0, 0.0001)
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.STALEMATE)
	assert_eq(attacker.ship_count(), 28)
	assert_eq(defender.ship_count(), 24)


func _types(type_id: String, count: int) -> Array:
	var out: Array = []
	for _index in count:
		out.append(type_id)
	return out


func test_stronger_side_breaks_the_weaker_squadron() -> void:
	var strong: FleetState = _squadron(1, 0, 2, "carrack", 3)
	var weak: FleetState = _squadron(2, 1, 2, "carrack", 1)
	strong.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.SIDE1_VICTORY)
	assert_eq(weak.ship_count(), 0)
	assert_false(weak.is_afloat())
	assert_eq(int((battles[0]["defender_lost"] as Array).size()), 1)


func test_the_victor_pays_for_its_win() -> void:
	var strong: FleetState = _squadron(1, 0, 2, "carrack", 3)
	var frigate: FleetState = _fleet(2, 1, 2, ["frigate"])
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, frigate])
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.SIDE1_VICTORY)
	assert_eq(frigate.ship_count(), 0)
	# 5.8 strength * 0.5 damage covers one 2.2-durability carrack, not two.
	assert_eq(int((battles[0]["attacker_lost"] as Array).size()), 1)
	assert_eq(strong.ship_count(), 2)


func test_attacking_into_a_stronger_fleet_loses_the_attackers() -> void:
	var attacker: FleetState = _squadron(1, 1, 4, "fluyte", 1)
	attacker.moved = true
	var defender: FleetState = _squadron(2, 0, 4, "frigate", 2)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([attacker, defender])
	assert_eq(int(battles[0]["outcome"]), NavalCombat.Outcome.SIDE2_VICTORY)
	assert_eq(attacker.ship_count(), 0)
	assert_eq(defender.ship_count(), 2)
	assert_eq(NavalCombat.outcome_label(int(battles[0]["outcome"])), "defender victory")


func test_multi_faction_zone_resolves_one_engagement_per_defender() -> void:
	var host: FleetState = _squadron(1, 0, 5, "carrack", 4)
	var first: FleetState = _squadron(2, 1, 5, "fluyte", 1)
	var second: FleetState = _squadron(3, 2, 5, "fluyte", 1)
	host.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([host, second, first])
	assert_eq(battles.size(), 2)
	assert_eq(int(battles[0]["defender"]), 1)
	assert_eq(int(battles[1]["defender"]), 2)
	assert_eq(first.ship_count(), 0)
	assert_eq(second.ship_count(), 0)
	assert_gt(host.ship_count(), 0)


func test_resolution_is_deterministic() -> void:
	var first: FleetState = _squadron(1, 0, 7, "carrack", 3)
	var second: FleetState = _squadron(2, 1, 7, "sloop", 2)
	var once: Array[Dictionary] = NavalCombat.resolve_turn([first, second])
	var first_again: FleetState = _squadron(1, 0, 7, "carrack", 3)
	var second_again: FleetState = _squadron(2, 1, 7, "sloop", 2)
	var twice: Array[Dictionary] = NavalCombat.resolve_turn([first_again, second_again])
	assert_eq(once, twice)
	assert_eq(first.hulls, first_again.hulls)
	assert_eq(second.hulls, second_again.hulls)


func test_battle_report_fields_describe_the_sides() -> void:
	var strong: FleetState = _squadron(1, 0, 8, "carrack", 3)
	var weak: FleetState = _squadron(2, 1, 8, "carrack", 1)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])
	var battle: Dictionary = battles[0]
	assert_eq(int(battle["zone"]), 8)
	assert_eq(int(battle["attacker_before"]), 3)
	assert_eq(int(battle["defender_before"]), 1)
	assert_almost_eq(float(battle["attacker_strength"]), 8.25, 0.0001)
	assert_almost_eq(float(battle["defender_strength"]), 2.75, 0.0001)

# --- from test_generals.gd ---
## General pool, tech-gated cap, pre-Combat binding and medals
## (wiki: military-generals § Generals).


func test_cap_follows_the_tech_floors_without_stacking() -> void:
	assert_eq(GeneralRoster.cap_for({}), 1)
	assert_eq(GeneralRoster.cap_for({"organised_regiments": true}), 2)
	assert_eq(
		GeneralRoster.cap_for({"organised_regiments": true, "national_bureaucracy": true}),
		3
	)
	assert_eq(
		GeneralRoster.cap_for(
			{"national_bureaucracy": true, "improved_infantry_tactics": true}
		),
		3
	)
	assert_eq(GeneralRoster.cap_for({"nationalism": true}), 4)


func test_sync_spawns_to_cap_and_never_trims() -> void:
	var roster := GeneralRoster.new()
	assert_eq(roster.sync(0, {}), 1)
	assert_eq(roster.sync(0, {"organised_regiments": true}), 2)
	assert_eq(roster.medals(0, "general_2"), 0)
	assert_eq(roster.sync(0, {}), 2, "above-cap rosters are tolerated")
	assert_eq(roster.ids(0).size(), 2)


## The opening frame holds the cap, not the first turn tick: every Great Power
## is seated before any reading touches the pool (wiki: military-generals
## § Count and tech-gated cap — "The faction always has exactly that many
## generals"). A reading that spawned the pool itself would hide the gap.
func test_the_opening_seats_one_commander_per_great_power() -> void:
	var roster := GeneralRoster.new()
	var powers: Array[int] = FactionCatalog.great_power_ids()
	assert_eq(roster.seat_great_powers(), powers.size(), "one commander each")
	for faction: int in powers:
		assert_eq(
			(roster.pools.get(faction, []) as Array).size(), 1,
			"the pool holds the opening cap before anything reads it"
		)
	assert_eq(roster.seat_great_powers(), 0, "seating again spawns nothing")
	assert_eq(
		(roster.pools.get(FactionCatalog.minor_ids()[0], []) as Array).size(), 0,
		"a Minor Nation musters no general"
	)


func test_medals_gain_one_per_win_and_cap_at_four() -> void:
	var roster := GeneralRoster.new()
	roster.pool(0)
	for expected: int in [1, 2, 3, 4, 4]:
		assert_eq(roster.award(0, "general_1"), expected)
	assert_eq(roster.summary(0), "1 general · 4 medals")


func test_save_dict_round_trip_keeps_pools_and_medals() -> void:
	var roster := GeneralRoster.new()
	roster.sync(0, {"nationalism": true})
	roster.sync(1, {"organised_regiments": true})
	roster.award(0, "general_1")
	roster.award(0, "general_1")
	roster.award(0, "general_3")

	# The save store keeps typed variants, but string keys must also restore.
	var restored: GeneralRoster = GeneralRoster.from_dict(roster.to_dict())
	var from_text: GeneralRoster = GeneralRoster.from_dict({
		"pools": {"0": [{"id": "general_1", "medals": 2}]}
	})

	assert_eq(restored.count(0), 4, "the persisted cap is the pool size")
	assert_eq(restored.medals(0, "general_1"), 2, "earned medals survive")
	assert_eq(restored.medals(0, "general_3"), 1)
	assert_eq(restored.medals(0, "general_2"), 0)
	assert_eq(restored.count(1), 2)
	assert_eq(from_text.count(0), 1, "string keys rebuild the pool")
	assert_eq(from_text.medals(0, "general_1"), 2)


func test_from_dict_tolerates_junk_and_caps_medals() -> void:
	var roster: GeneralRoster = GeneralRoster.from_dict({"pools": {
		"2": [{"id": "general_1", "medals": 99}, {"id": ""}, 7],
		3: "nope",
	}})
	assert_eq(roster.count(2), 1, "only usable general rows load")
	assert_eq(roster.medals(2, "general_1"), GeneralRoster.MAX_MEDALS)


func test_binding_gives_one_general_per_attacking_army() -> void:
	var model := Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"])
	var first := Fixture.army(2, 0, 2, ["pikemen"])
	first.moved = true
	var second := Fixture.army(3, 0, 2, ["pikemen"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]
	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, GeneralRoster.new(), 3
	)["army_general"]

	assert_eq(bindings.size(), 2)
	assert_true(bindings.has(first.id) != bindings.has(second.id))
	assert_true(bindings.has(defender.id), "the defender also gets a commander")


func test_defender_binding_stops_when_the_pool_is_spent() -> void:
	var model := Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var first := Fixture.army(1, 1, 2, ["peasant_levies"])
	var second := Fixture.army(2, 1, 2, ["peasant_levies"])
	var attacker := Fixture.army(3, 0, 2, ["guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [first, second, attacker]
	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, GeneralRoster.new(), 5
	)["army_general"]

	assert_eq(bindings.size(), 2)
	assert_true(bindings.has(attacker.id))
	assert_true(bindings.has(first.id) != bindings.has(second.id))


func test_one_general_covers_both_an_attack_and_a_defence() -> void:
	# The attack cap is offensive-only: defender binding draws from generals not
	# bound to another *defending* army, so a cap-1 crown can still command its
	# home battle in the same Combat phase (wiki: military-generals § Assignment).
	var model := Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var defender_of_two := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacker := Fixture.army(2, 0, 2, ["pikemen"])
	attacker.moved = true
	var invader := Fixture.army(3, 2, 0, ["pikemen"])
	invader.moved = true
	var home_defender := Fixture.army(4, 0, 0, ["peasant_levies"])
	var armies: Array[ArmyState] = [defender_of_two, attacker, invader, home_defender]
	var roster := GeneralRoster.new()
	assert_eq(roster.count(0), 1, "the crown has a single general")

	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, roster, 0
	)["army_general"]

	assert_eq(
		String(bindings.get(attacker.id, "")),
		"general_1",
		"the offensive commitment takes the general"
	)
	assert_eq(
		String(bindings.get(home_defender.id, "")),
		"general_1",
		"the defence still draws the general from its own pool"
	)


func test_unbound_sides_use_the_leader_fallback_medals() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]
	assert_eq(ArmyCommand.medals(side, {"leaders": {0: "napoleon"}}), 4)
	assert_eq(ArmyCommand.medals(side, {"leaders": {0: "frederick"}}, true), 2)
	assert_eq(ArmyCommand.medals(side, {"leaders": {0: "frederick"}}), 0,
		"Frederick publishes defence only")
	assert_eq(ArmyCommand.medals(side, {"leaders": {0: "gustavus"}}, false), 2)
	assert_eq(ArmyCommand.medals(side, {"leaders": {0: "gustavus"}}, true), 0,
		"Gustavus publishes attack only")
	assert_eq(ArmyCommand.medals(side, {}), 0)


## A battle-sim scenario names the sides' medals directly and carries no roster,
## so the phase's opening read is the only answer there (battle-sim).
func test_a_context_without_a_roster_reads_the_phase_snapshot() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]

	assert_eq(ArmyCommand.medals(side, {"army_medals": {army.id: 2}}), 2)
	assert_eq(ArmyCommand.medals(side, {"army_general": {army.id: "general_1"}}), 0)


## A general earns a medal at once and fights the phase's later engagements with
## it (wiki: combat § Acceptance — the increment persists "for subsequent
## engagements and turns"), so the live roster beats the phase snapshot.
func test_a_general_fights_later_engagements_with_the_medal_he_earned() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]
	var roster := GeneralRoster.new()
	roster.pool(0)
	for _index in 3:
		roster.award(0, "general_1")
	var context: Dictionary = {
		"roster": roster,
		"army_general": {army.id: "general_1"},
		"army_medals": {army.id: 1},
	}
	assert_eq(
		ArmyCommand.medals(side, context), 3,
		"the general's own medals answer, not the phase's opening snapshot"
	)


## The second engagement of a chain: the defender's general won the first, so he
## commands the second with that medal — one more regiment in the line.
func test_a_chain_defender_uses_the_medal_won_in_the_earlier_exchange() -> void:
	var model := Fixture.build()
	model.faction_ids = [0, 1, 2]
	var world := WorldMap.new()
	world.add_region(model)
	var guards: Array[String] = []
	for _index in 12:
		guards.append("guards")
	var defender := Fixture.army(1, 1, 2, guards, true)
	var first := Fixture.army(2, 0, 2, ["peasant_levies"])
	first.moved = true
	var second := Fixture.army(3, 2, 2, ["peasant_levies"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]
	var roster := GeneralRoster.new()
	var binding: Dictionary = GeneralBinding.bind_phase(world, {0: armies}, roster, 0)
	var context: Dictionary = {
		"roster": roster,
		"army_general": binding.get("army_general", {}),
		"army_medals": binding.get("army_medals", {}),
		"leaders": {},
		"feeding": {},
		"tech": {},
	}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(reports.size(), 2, "both attackers fought the same defender")
	assert_eq(int(reports[0]["defender_medals"]), 0)
	assert_eq(int(reports[1]["defender_medals"]), 1)
	assert_eq(int(reports[1]["defender_limit"]), 11)
	assert_eq(roster.medals(1, "general_1"), 2, "each win is one medal")
	# The despatch prints the count the award produced, not the pool's figure
	# when the line is written: the first win was his first medal, and reading
	# the roster after the whole phase would print the second on both lines
	# (wiki: military-generals § Medals — "his new count").
	assert_eq(
		int(reports[0]["medal_count"]), 1,
		"the first win names the count it produced"
	)
	assert_eq(int(reports[1]["medal_count"]), 2, "the second names its own")


func test_a_winning_general_earns_a_medal() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = {"roster": roster, "army_general": {attacker.id: "general_1"}}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(String(reports[0]["medal_gain"]), "general_1")
	assert_eq(int(reports[0]["medal_owner"]), 0)
	assert_eq(roster.medals(0, "general_1"), 1)


func test_a_four_medal_general_gains_nothing_more() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	for _index in 4:
		roster.award(0, "general_1")
	var context: Dictionary = {
		"roster": roster,
		"army_general": {attacker.id: "general_1"},
		"army_medals": {attacker.id: 4},
	}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(roster.medals(0, "general_1"), 4)
	assert_eq(String(reports[0]["medal_gain"]), "")
	assert_eq(int(reports[0]["medal_count"]), 0, "a capped commander's line names no count")


func test_a_losing_general_keeps_his_medals() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["guards", "guards", "guards"])
	var attacker := Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = {"roster": roster, "army_general": {attacker.id: "general_1"}}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_eq(roster.medals(0, "general_1"), 0)
	assert_eq(String(reports[0]["medal_gain"]), "")


## The side's commander is the army with the most regiments BEFORE battle
## resolution (wiki: military-armies § Battle grouping). Two defending armies of
## one crown merge into one side; when the bigger army is mauled below its
## veteran sibling during the exchange, the medal still belongs to the general
## who commanded the side when it opened — not to the army that merely
## outnumbers the survivors afterwards.
func test_the_medal_goes_to_the_pregame_primary_defender() -> void:
	var model := Fixture.build()
	var big: ArmyState = Fixture.army(1, 1, 2, _levies(5))
	var small: ArmyState = Fixture.army(2, 1, 2, _guards(4))
	var attacker: ArmyState = Fixture.army(3, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [big, small, attacker]
	var roster := GeneralRoster.new()
	roster.sync(1, {"organised_regiments": true})
	var context: Dictionary = {
		"roster": roster,
		"army_general": {big.id: "general_1", small.id: "general_2"},
		"leaders": {},
		"feeding": {},
		"tech": {},
	}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_true(
		big.count() < small.count(),
		"the pre-battle primary is mauled below its sibling by the fighting"
	)
	assert_eq(
		String(reports[0]["medal_gain"]), "general_1",
		"the commander at the open takes the medal, not the survivor"
	)
	assert_eq(int(reports[0]["medal_owner"]), 1)
	assert_eq(roster.medals(1, "general_1"), 1)
	assert_eq(roster.medals(1, "general_2"), 0, "the sibling commander was never credited")


## The same read for the attacking side: two attacking armies of one crown in
## the province merge into one side, and the decoration follows the primary at
## the open even after the casualties reorder the survivors.
func test_the_medal_goes_to_the_pregame_primary_attacker() -> void:
	var model := Fixture.build()
	var big: ArmyState = Fixture.army(1, 0, 2, _levies(5))
	big.moved = true
	var small: ArmyState = Fixture.army(2, 0, 2, _guards(4))
	small.moved = true
	var defender: ArmyState = Fixture.army(3, 1, 2, ["peasant_levies"])
	var armies: Array[ArmyState] = [big, small, defender]
	var roster := GeneralRoster.new()
	roster.sync(0, {"organised_regiments": true})
	var context: Dictionary = {
		"roster": roster,
		"army_general": {big.id: "general_1", small.id: "general_2"},
		"leaders": {},
		"feeding": {},
		"tech": {},
	}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_true(big.count() < small.count(), "the pre-battle primary falls behind its sibling")
	assert_eq(String(reports[0]["medal_gain"]), "general_1")
	assert_eq(roster.medals(0, "general_1"), 1)
	assert_eq(roster.medals(0, "general_2"), 0)


## Quick Battle fights the same merged side and must credit the same commander
## (wiki: quick-battle § Outcome and integration — same pipeline as auto-resolve).
func test_quick_battle_credits_the_pregame_primary_defender() -> void:
	var model := Fixture.build()
	var big: ArmyState = Fixture.army(1, 1, 2, _levies(5))
	var small: ArmyState = Fixture.army(2, 1, 2, _guards(4))
	var attacker: ArmyState = Fixture.army(3, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [big, small, attacker]
	var roster := GeneralRoster.new()
	roster.sync(1, {"organised_regiments": true})
	var context: Dictionary = {
		"roster": roster,
		"army_general": {big.id: "general_1", small.id: "general_2"},
		"leaders": {},
		"feeding": {},
		"tech": {},
		"quick_battle": true,
		"player_faction": 1,
		"battle_plan": "balanced",
	}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_true(reports[0].has("quick"), "the human's battle runs on the plate")
	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_true(big.count() < small.count())
	assert_eq(String(reports[0]["medal_gain"]), "general_1")
	assert_eq(roster.medals(1, "general_1"), 1)
	assert_eq(roster.medals(1, "general_2"), 0)


## One record shape for both resolvers: the plate and the gazette read the same
## fields whichever route fought the battle (REQ-P2-03, REQ-P3-01).
func test_auto_resolve_and_quick_battle_open_the_same_record() -> void:
	var model := Fixture.build()
	var base: Dictionary = BattleSettlement.report_skeleton(
		model, 2, 0, 1, ArmyCombat.Outcome.STALEMATE,
		[] as Array[String], [] as Array[String], {}, {}
	)
	var auto_defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var auto_attacker := Fixture.army(2, 0, 2, _guards(5))
	auto_attacker.moved = true
	var auto_armies: Array[ArmyState] = [auto_defender, auto_attacker]
	var auto: Array[Dictionary] = ArmyCombat.resolve_turn(model, auto_armies)
	assert_false(auto.is_empty())
	for key: String in base.keys():
		assert_true(auto[0].has(key), "auto-resolve carries %s" % key)

	var quick_model := Fixture.build()
	var quick_defender := Fixture.army(3, 1, 2, ["peasant_levies"], true)
	var quick_attacker := Fixture.army(4, 0, 2, _guards(5))
	quick_attacker.moved = true
	var quick_armies: Array[ArmyState] = [quick_defender, quick_attacker]
	var quick_context: Dictionary = {
		"quick_battle": true,
		"player_faction": 0,
		"battle_plan": "balanced",
		"leaders": {},
		"feeding": {},
		"tech": {},
	}
	var quick: Array[Dictionary] = ArmyCombat.resolve_turn(
		quick_model, quick_armies, quick_context
	)
	assert_true(quick[0].has("quick"), "the human's battle runs on the plate")
	for key: String in base.keys():
		assert_true(quick[0].has(key), "quick battle carries %s" % key)
	assert_eq(String(base["medal_gain"]), "", "an open record names no decoration")


## Every crown's roster is reconciled with its own research at the Combat phase
## (wiki: military-generals § Count and tech-gated cap). The ledger only syncs
## the human's pool, so a rival used to fly one commander for the whole age.
func test_the_combat_phase_reconciles_every_crown_with_its_own_tech() -> void:
	var model := Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var defender := Fixture.army(1, 0, 0, ["peasant_levies"], true)
	var first := Fixture.army(2, 1, 0, ["pikemen"])
	first.moved = true
	var second := Fixture.army(3, 1, 0, ["pikemen"])
	second.moved = true
	var roster := GeneralRoster.new()
	var context: Dictionary = {
		"tech": {0: {"nationalism": true}, 1: {"organised_regiments": true}, 2: {}},
		"hostile": func(_a: int, _b: int) -> bool: return true,
	}

	ArmyBattles.resolve_region_turn(
		world, {0: [defender, first, second] as Array[ArmyState]}, roster, context
	)

	assert_eq(roster.ids(1), ["general_1", "general_2"], "the rival's cap 2 lands")
	assert_eq(roster.count(0), 4, "the human's nationalism cap lands")
	assert_eq(roster.count(2), 1, "a court with no cap tech keeps one commander")


## A reconciled pool is what lets a court field two attacking armies under two
## commanders in one Combat phase (wiki: military-generals § Assignment).
func test_a_reconciled_court_commands_both_of_its_attacking_armies() -> void:
	var model := Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var defender := Fixture.army(1, 0, 0, ["peasant_levies"], true)
	var first := Fixture.army(2, 1, 0, ["pikemen"])
	first.moved = true
	var second := Fixture.army(3, 1, 0, ["pikemen"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]
	var roster := GeneralRoster.new()
	roster.reconcile({1: {"organised_regiments": true}})

	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, roster, 7
	)["army_general"]

	assert_true(bindings.has(first.id))
	assert_true(bindings.has(second.id))
	assert_true(
		String(bindings[first.id]) != String(bindings[second.id]),
		"two commanders, never one bound twice"
	)


## The reconciliation reads only Great Powers and only their own row: a Minor
## Nation holds no pool and a junk tech row must not grow one.
func test_reconcile_reads_only_great_powers_and_their_own_tech() -> void:
	var roster := GeneralRoster.new()

	roster.reconcile({1: {"nationalism": true}, 6: {"nationalism": true}, 2: "nope"})

	assert_eq(roster.count(1), 4)
	assert_false(roster.pools.has(6), "minors never hold commanders")
	assert_false(roster.pools.has(2), "a junk tech row is ignored")


## A moved army in another province of the same region is not in this battle.
## The old binding walked every moved army in the region, so the first province
## battle could spend a cap-1 crown's only commander on an army that was not
## even standing there (wiki: military-generals § Assignment).
func test_binding_ignores_moved_armies_outside_the_battle_province() -> void:
	var model: MapModel = Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	# Province 2 holds a marching army but no defender, so it is no battle.
	var marcher: ArmyState = Fixture.army(2, 0, 2, ["pikemen"])
	marcher.moved = true
	var defender: ArmyState = Fixture.army(3, 1, 4, ["peasant_levies"])
	var attacker: ArmyState = Fixture.army(4, 0, 4, ["guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [marcher, defender, attacker]
	var roster := GeneralRoster.new()

	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, roster, 1
	)["army_general"]

	assert_false(bindings.has(marcher.id), "a march outside the battle spends nothing")
	assert_eq(
		String(bindings.get(attacker.id, "")),
		"general_1",
		"the army that fights takes the crown's only commander"
	)


## A march into land its crown is at peace with triggers no engagement, so it
## must not bind a commander or spend the phase's offensive cap
## (wiki: military-generals § Assignment — "will participate in land combat").
func test_binding_skips_a_march_that_is_not_at_war() -> void:
	var model: MapModel = Fixture.build()
	# Province 2 is owned by a Minor Nation the crown is at peace with; province
	# 4 by a rival Great Power at war.
	model.province_data(2).owner = 6
	var world := WorldMap.new()
	world.add_region(model)
	var minor_defender: ArmyState = Fixture.army(1, 6, 2, ["peasant_levies"])
	var peaceful_march: ArmyState = Fixture.army(2, 0, 2, ["pikemen"])
	peaceful_march.moved = true
	var rival_defender: ArmyState = Fixture.army(3, 1, 4, ["peasant_levies"])
	var attacker: ArmyState = Fixture.army(4, 0, 4, ["guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [minor_defender, peaceful_march, rival_defender, attacker]
	var hostile := func(a: int, b: int) -> bool: return a == 0 and b == 1
	var roster := GeneralRoster.new()

	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, roster, 7, hostile
	)["army_general"]

	assert_false(bindings.has(peaceful_march.id), "peace binds no commander")
	assert_eq(
		String(bindings.get(attacker.id, "")),
		"general_1",
		"the war the crown is fighting keeps its commander"
	)


## End to end: the Combat phase passes its war query into binding, so a peaceful
## march cannot starve the real battle of the crown's general. The medal
## snapshot proves who was bound: the general carries two medals, and the report
## reads them only when that general commanded the attacking side.
func test_the_combat_phase_binds_only_the_army_that_fights() -> void:
	var model: MapModel = Fixture.build()
	model.province_data(2).owner = 6
	var world := WorldMap.new()
	world.add_region(model)
	var minor_defender: ArmyState = Fixture.army(1, 6, 2, ["peasant_levies"])
	var peaceful_march: ArmyState = Fixture.army(2, 0, 2, ["pikemen"])
	peaceful_march.moved = true
	var rival_defender: ArmyState = Fixture.army(3, 1, 4, ["peasant_levies"])
	var attacker: ArmyState = Fixture.army(4, 0, 4, ["guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [minor_defender, peaceful_march, rival_defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	roster.award(0, "general_1")
	roster.award(0, "general_1")
	var context: Dictionary = {
		"hostile": func(a: int, b: int) -> bool: return a == 0 and b == 1,
		"seed": 1,
	}

	var reports: Array[Dictionary] = ArmyBattles.resolve_region_turn(
		world, {0: armies}, roster, context
	)

	assert_eq(reports.size(), 1, "only the war produces a battle")
	assert_eq(int(reports[0]["province"]), 4)
	assert_eq(
		int(reports[0]["attacker_medals"]),
		2,
		"the general with two medals commands the army that fights"
	)


# --- Quick Battle extracted modules (REQ-P3-01 / REQ-P3-04) ---
## Action catalog, fort battery, and plate copy live in their own modules so
## the soft-capped orchestrators stay under ≤400/≤25. Covered here (battle
## domain) so the impact map does not select ALL via impact_map.toml or the
## unmapped test_quick_battle_*.gd catch-all.


func test_quick_battle_action_scripts_come_from_the_plan_catalog() -> void:
	assert_eq(QuickBattleActions.actions_for("aggressive"), ["maneuver", "assault"])
	assert_eq(QuickBattleActions.actions_for("defensive"), ["fall_back", "volley"])
	assert_eq(QuickBattleActions.actions_for("unknown"), ["volley", "entrench", "volley"])


## The battle's law lives on [QuickBattleTerms] and its rounds on
## [QuickBattleRounds]: one answer for the plate, the simulator and the rounds,
## with no pass-through copy on the orchestrator (REQ-P3-01).
func test_quick_battle_terms_are_the_ones_the_battle_fights_under() -> void:
	assert_eq(QuickBattleTerms.MAX_ROUNDS, 3)
	assert_eq(QuickBattleTerms.CP_PER_ROUND, 3)
	assert_eq(QuickBattleRounds.MAX_ROUNDS, QuickBattleTerms.MAX_ROUNDS)
	assert_eq(QuickBattleRounds.CP_PER_ROUND, QuickBattleTerms.CP_PER_ROUND)


func test_quick_battle_battery_silences_guns_and_downgrades() -> void:
	var model := Fixture.build()
	model.province_data(2).fort_level = 1
	var guns: Array[Dictionary] = QuickBattleBattery.make(1, {}, 1)
	assert_eq(guns.size(), 1)
	assert_eq(QuickBattleBattery.alive(guns), 1)
	assert_eq(QuickBattleBattery.hit(guns, 4), 1)
	assert_eq(QuickBattleBattery.alive(guns), 0)
	assert_true(QuickBattleBattery.downgrade_fort(model, 2, 1, guns))
	assert_eq(model.province_data(2).fort_level, 0)


## A standing gun soaks the blow it takes: a hit short of its HP spends the fire
## without silencing it, so the garrison behind it is sheltered
## (wiki: siege-mechanics § Quick Battle lanes).
func test_a_standing_gun_soaks_the_blow_before_it_is_silenced() -> void:
	var guns: Array[Dictionary] = QuickBattleBattery.make(1, {}, 1)
	var first: Dictionary = QuickBattleBattery.absorb(guns, 1)
	assert_eq(int(first["absorbed"]), 1, "the gun takes the whole hit")
	assert_eq(int(first["destroyed"]), 0)
	assert_eq(QuickBattleBattery.alive(guns), 1)
	var second: Dictionary = QuickBattleBattery.absorb(guns, 4)
	assert_eq(int(second["absorbed"]), 1, "a dead gun soaks nothing more")
	assert_eq(int(second["destroyed"]), 1)
	assert_almost_eq(QuickBattleBattery.total_hp(guns), 0.0, 0.001)


func test_quick_battle_copy_names_the_victor() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"player_faction": 0,
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
	}
	var names: Array = ["España", "England"]
	assert_eq(
		QuickBattleCopy.outcome_text(
			ArmyCombat.Outcome.ATTACKER_VICTORY, battle, "Flanders", names
		),
		"España takes Flanders"
	)
	assert_true(QuickBattleCopy.player_won(ArmyCombat.Outcome.ATTACKER_VICTORY, battle))
	assert_eq(QuickBattleCopy.roman(2), "II")
	assert_eq(
		QuickBattleCopy.action_line(
			{
				"side": 0,
				"action": "assault",
				"label": "Assault",
				"attacker_lost": 1,
				"defender_lost": 2,
				"guns_destroyed": 1,
			},
			battle,
			names
		),
		"España — Assault · 2 lost · 1 of its own · 1 gun silenced"
	)


# --- raid despatches (DR-20261110-13) ---------------------------------------


func test_a_raid_on_the_crown_names_the_raider_the_cargo_and_the_hulls() -> void:
	var raid: Dictionary = {
		"kind": "incoming",
		"raider": 1,
		"victim": 0,
		"losses": {"grain": 3, "timber": 2},
	}
	assert_eq(
		BattleReport.describe_raid(raid, "Mar Caribe", FACTIONS, 0),
		"England seizes 5 cargo (3 grain, 2 timber) off the Mar Caribe — no hull lost"
	)


## A commerce raid that takes a hull names her, on both sides of the ledger
## (wiki: ships-and-naval § Trade and Transport Interception; DR-20261111-17).
func test_a_raid_despatch_names_the_merchant_it_sank() -> void:
	var sunk: Array = [
		{"id": "ship_7", "type_id": "fluyte", "name": "Vrouw Maria"}
	]
	var incoming: Dictionary = {
		"kind": "incoming", "raider": 1, "victim": 0,
		"losses": {"grain": 3}, "hulls_lost": sunk,
	}
	assert_eq(
		BattleReport.describe_raid(incoming, "Mar Caribe", FACTIONS, 0),
		"England seizes 3 grain off the Mar Caribe and sinks the Fluyte Vrouw Maria"
	)
	var prize: Dictionary = {
		"kind": "prize", "raider": 0, "victim": 2,
		"losses": {"grain": 3}, "hulls_lost": sunk,
	}
	assert_eq(
		BattleReport.describe_raid(prize, "Golfo de México", FACTIONS, 0),
		"Your station takes 3 grain off the Golfo de México as prize and sends the Fluyte Vrouw Maria down"
	)


func test_a_sunk_hull_without_a_name_still_prints() -> void:
	assert_eq(BattleReport.sunk_of([]), "")
	assert_eq(BattleReport.sunk_of([{"type_id": "carrack"}]), "Carrack")
	assert_eq(BattleReport.sunk_of(["not a hull"]), "")


func test_a_prize_despatch_reads_as_the_crowns_own_haul() -> void:
	var raid: Dictionary = {
		"kind": "prize",
		"raider": 0,
		"victim": 2,
		"losses": {"grain": 4},
	}
	assert_eq(
		BattleReport.describe_raid(raid, "Golfo de México", FACTIONS, 0),
		"Your station takes 4 grain off the Golfo de México as prize — no hull lost"
	)


func test_a_raid_with_no_zone_name_still_reads() -> void:
	var raid: Dictionary = {"raider": 1, "victim": 0, "losses": {}}
	var text: String = BattleReport.describe_raid(raid, "", FACTIONS, 0)
	assert_true(text.contains("open water"))
	assert_true(text.contains("no cargo"))

# --- from regiment condition (wiki: combat § Strength, military-units § Stats) ---


func test_a_regiments_health_pool_scales_with_its_defence() -> void:
	assert_eq(RegimentCatalog.max_health("peasant_levies"), 90)
	assert_eq(RegimentCatalog.max_health("pikemen"), 110)
	assert_eq(RegimentCatalog.max_health("guards"), 120)
	assert_eq(RegimentCatalog.max_health("culverin"), 80)


func test_chevrons_multiply_a_regiments_firepower() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var regiment: String = army.regiments[0]

	assert_almost_eq(army.strength(), 5.0, 0.001)
	army.regiment_medals[regiment] = 2
	assert_almost_eq(army.strength(), 6.0, 0.001, "a chevron is +10%")
	army.regiment_medals[regiment] = 9
	assert_almost_eq(army.strength(), 7.0, 0.001, "four chevrons is the cap")


func test_a_wound_lowers_firepower_and_never_destroys() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var regiment: String = army.regiments[0]

	var dealt: int = RegimentCondition.wound(army, regiment, 55.0)
	assert_eq(dealt, 55)
	assert_almost_eq(army.strength(), 2.5, 0.001, "half a regiment fights at half strength")

	RegimentCondition.wound(army, regiment, 999.0)
	assert_eq(int(army.condition_of(regiment)["hp"]), 1)
	assert_eq(army.count(), 1, "a wound alone never removes a regiment")


func test_wear_mauls_survivors_and_rest_recovers_a_quarter() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]

	assert_eq(RegimentCondition.wear(side, 0.5), 2, "both regiments are mauled")
	for regiment: String in army.regiments:
		assert_eq(int(army.condition_of(regiment)["hp"]), 55)

	RegimentCondition.rest(army)
	for regiment: String in army.regiments:
		assert_eq(int(army.condition_of(regiment)["hp"]), 83, "a quarter of 110 is 28")
	assert_eq(RegimentCondition.mauled(side), 2)

	army.regiment_health[army.regiments[0]] = 100
	RegimentCondition.rest(army)
	assert_eq(
		int(army.condition_of(army.regiments[0])["hp"]), 110, "rest never overfills"
	)


func test_split_and_combine_carry_condition() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen", "guards"], true)
	var pikes: String = army.regiments[0]
	army.regiment_health[pikes] = 40
	army.regiment_medals[pikes] = 3
	var armies: Array[ArmyState] = [army]

	var split: Dictionary = ArmyRoster.split(armies, army, [pikes], 9)
	assert_true(bool(split["ok"]))
	var field: ArmyState = split["army"] as ArmyState
	assert_eq(int(field.condition_of(pikes)["hp"]), 40, "the wounded stay wounded")
	assert_eq(int(field.condition_of(pikes)["medals"]), 3, "the chevrons travel")

	var selected: Array[ArmyState] = [army, field]
	var merged: Dictionary = ArmyRoster.combine(armies, selected)
	assert_true(bool(merged["ok"]))
	var home: ArmyState = merged["army"] as ArmyState
	assert_eq(int(home.condition_of(pikes)["hp"]), 40)
	assert_eq(int(home.condition_of(pikes)["medals"]), 3)


func test_a_save_round_trip_keeps_regiment_condition() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen", "guards"])
	var pikes: String = army.regiments[0]
	army.regiment_health[pikes] = 61
	army.regiment_medals[pikes] = 2

	var restored := ArmyState.from_dict(army.to_dict())

	assert_eq(int(restored.condition_of(pikes)["hp"]), 61)
	assert_eq(int(restored.condition_of(pikes)["medals"]), 2)
	assert_almost_eq(restored.strength(), army.strength(), 0.001)


func test_the_ratio_bands_live_in_one_table() -> void:
	assert_almost_eq(float(ArmyBands.for_ratio(2.0)["attacker"]), 0.15, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(1.2)["attacker"]), 0.3, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(0.8)["attacker"]), 0.5, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(0.5)["attacker"]), 1.0, 0.001)


## The table's morale row: an attacker whose morale is lower than the defender's
## fights the blunted band between 1.5 and 4.0 to one, and every other row keeps
## its published fractions (wiki: combat § Auto-resolve ratio bands).
func test_a_hungrier_attacker_fights_the_blunted_band() -> void:
	var blunted: Dictionary = ArmyBands.for_ratio(2.0, 0.5, 1.0)
	assert_almost_eq(float(blunted["attacker"]), 0.6, 0.001)
	assert_almost_eq(float(blunted["defender"]), 0.4, 0.001)
	assert_true(bool(blunted.get("blunted", false)), "the band is blunted")
	assert_almost_eq(float(ArmyBands.for_ratio(2.0, 1.0, 1.0)["attacker"]), 0.15, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(2.0, 1.0, 0.75)["attacker"]), 0.15, 0.001)
	# The morale row claims only 1.5 <= ratio < 4.0.
	assert_almost_eq(float(ArmyBands.for_ratio(4.0, 0.5, 1.0)["attacker"]), 0.15, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(1.2, 0.5, 1.0)["attacker"]), 0.3, 0.001)


## A hungrier attacker at blunted odds guts the garrison and still does not take
## the province: the row writes a stalemate, not an attacker victory.
func test_a_hungry_attacker_guts_the_garrison_without_taking_the_province() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["pikemen"], true)
	var attacker := Fixture.army(2, 0, 2, ["pikemen", "pikemen", "pikemen", "pikemen"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	# 4 pikemen at half rations against 1 at full: strength ratio 2.0.
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(
		model, armies, {"seed": 7, "feeding": {0: 0.4, 1: 1.0}}
	)

	assert_eq(reports.size(), 1)
	var battle: Dictionary = reports[0]
	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.STALEMATE)
	assert_true(bool(battle.get("blunted", false)), "the despatch can say why")
	assert_eq(model.province_owner(2), 1, "the hungry attacker does not take the province")
	assert_eq(defender.count(), 0, "the garrison was gutted")
	assert_true(attacker.count() > 0, "the attacker keeps the field")
	var line: String = BattleReport.describe_land(battle, "Harbour", FACTIONS)
	assert_true(line.contains("hungrier"), "the toast names the blunted win: %s" % line)


## The same odds at full rations still take the province: the morale row is the
## only difference (and ratio == 4.0 itself is outside its band).
func test_full_rations_at_the_same_odds_take_the_province() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["pikemen"], true)
	var attacker := Fixture.army(2, 0, 2, ["pikemen", "pikemen", "pikemen", "pikemen"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(
		model, armies, {"seed": 7, "feeding": {0: 1.0, 1: 1.0}}
	)

	assert_eq(reports.size(), 1)
	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_false(bool(reports[0].get("blunted", false)))
	assert_eq(model.province_owner(2), 0, "a fed attacker takes the province")


## A won auto-resolve battle tells the plate what it cost: surviving chevrons,
## mauled survivors, and the same numbers the dossier will read.
func test_a_won_battle_awards_chevrons_and_mauls_its_survivors() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {"seed": 11})
	var battle: Dictionary = reports[0]

	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_true(int(battle["attacker_chevrons"]) > 0, "winning survivors rise a chevron")
	assert_true(int(battle["attacker_mauled"]) > 0, "survivors carry the field's wear")
	var entries: Array = battle["attacker_health"] as Array
	assert_eq(entries.size(), attacker.count())
	for entry: Dictionary in entries:
		assert_eq(int(entry["medals"]), 1)
		assert_true(float(entry["fraction"]) < 1.0, "nobody leaves unmarked")
		assert_true(int(entry["max"]) > 0)


## The land toast carries the condition tail too, so a battle's cost is read
## without opening the plate (REQ-P5-05).
func test_a_land_despatch_appends_the_condition_tail() -> void:
	var battle: Dictionary = {
		"attacker": 0, "defender": 1,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"attacker_lost": ["unit_1"],
		"attacker_chevrons": 0, "defender_chevrons": 2,
		"attacker_mauled": 3, "defender_mauled": 1,
	}
	var line: String = BattleReport.describe_land(battle, "Flanders", FACTIONS)
	assert_true(line.contains("2 chevrons won"), line)
	assert_true(line.contains("4 regiments mauled"), line)
	assert_eq(BattleReport.regiment_note({}), "")


# --- attack treasury (wiki: tech-tree-military § Economy modifiers) ---------


func test_the_attack_price_follows_the_published_techs() -> void:
	assert_eq(ArmyAttackCost.cost({}), 100, "base price per battle")
	assert_eq(ArmyAttackCost.cost({"industrial_machinery": true}), 75)
	assert_eq(ArmyAttackCost.cost({"modern_military_funding": true}), 85)
	assert_eq(
		ArmyAttackCost.cost({
			"industrial_machinery": true, "modern_military_funding": true,
		}),
		63,
		"the two factors multiply"
	)
	assert_almost_eq(ArmyAttackCost.multiplier({}), 1.0, 0.001)
	assert_almost_eq(ArmyAttackCost.multiplier({"modern_military_funding": true}), 0.85, 0.001)


func test_a_charge_draws_on_the_callers_ledger() -> void:
	var charged: Array = []
	var pay := func(owner: int, cost: int) -> int:
		charged.append([owner, cost])
		return cost
	var fee: Dictionary = ArmyAttackCost.charge({"pay_attack": pay, "tech": {2: {}}}, 2)
	assert_eq(charged, [[2, 100]])
	assert_eq(int(fee["due"]), 100)
	assert_eq(int(fee["paid"]), 100)
	var free: Dictionary = ArmyAttackCost.charge({}, 2)
	assert_eq(int(free["due"]), 100)
	assert_eq(int(free["paid"]), 0, "no ledger means nothing is taken")
	var thin: Dictionary = ArmyAttackCost.charge(
		{"pay_attack": func(_o: int, _c: int) -> int: return 40}, 2
	)
	assert_eq(int(thin["paid"]), 40, "a thin purse never overpays")
	var report: Dictionary = ArmyAttackCost.stamp(thin, {})
	assert_eq(int(report["attack_cost"]), 100)
	assert_eq(int(report["attack_paid"]), 40)


func test_the_crowns_ledger_pays_and_floors_at_zero() -> void:
	var ledger := PlayerEconomy.starting()
	var before: int = ledger.treasury
	assert_eq(ArmyAttackCost.pay(ledger, 100), 100)
	assert_eq(ledger.treasury, before - 100)
	ledger.treasury = 40
	assert_eq(ArmyAttackCost.pay(ledger, 100), 40, "a crown never fights on credit")
	assert_eq(ledger.treasury, 0)
	assert_eq(ArmyAttackCost.pay(null, 100), 0, "no ledger, no charge")


func test_the_battle_context_charges_through_the_crowns_own_ledger() -> void:
	var play := PlaySession.new()
	var controller := EconomyController.new()
	controller.economy = PlayerEconomy.starting()
	play.economy = controller
	play.player_faction = FactionCatalog.PLAYER_FACTION
	var before: int = controller.economy.treasury

	var pay: Callable = MapPlayLandTurn.battle_context(play)["pay_attack"]

	assert_eq(int(pay.call(play.player_faction, 75)), 75)
	assert_eq(controller.economy.treasury, before - 75)
	assert_eq(
		int(pay.call(FactionCatalog.great_power_ids()[1], 75)), 0,
		"a court with no ledger pays nothing"
	)
	controller.free()


func test_a_land_battle_charges_its_attacker_once() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var charged: Array = []
	var pay := func(owner: int, cost: int) -> int:
		charged.append([owner, cost])
		return cost

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(
		model, armies, {"pay_attack": pay, "tech": {0: {"industrial_machinery": true}}}
	)

	assert_eq(reports.size(), 1)
	assert_eq(int(reports[0]["attack_cost"]), 75)
	assert_eq(int(reports[0]["attack_paid"]), 75)
	assert_eq(charged, [[0, 75]], "the defender pays nothing")


func test_each_attacker_in_a_chain_pays_its_own_price() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["guards", "guards", "guards"], true)
	var first := Fixture.army(2, 0, 2, ["pikemen", "pikemen", "pikemen", "pikemen"])
	first.moved = true
	var second := Fixture.army(3, 2, 2, ["pikemen", "pikemen"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]
	var charged: Array = []
	var pay := func(owner: int, cost: int) -> int:
		charged.append([owner, cost])
		return cost

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {"pay_attack": pay})

	assert_eq(reports.size(), 2, "both attackers get an exchange")
	assert_eq(charged.size(), 2, "one charge per battle context")
	assert_eq(int(reports[0]["attack_paid"]), 100)
	assert_eq(int(reports[1]["attack_paid"]), 100)


func test_an_unopposed_capture_costs_no_battle_treasury() -> void:
	var model := Fixture.build()
	var attacker := Fixture.army(1, 0, 3, ["guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [attacker]
	var charged: Array = []
	var pay := func(owner: int, cost: int) -> int:
		charged.append([owner, cost])
		return cost

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {"pay_attack": pay})

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.CAPTURE)
	assert_eq(charged, [], "walking into an empty province is not a battle")
	assert_eq(model.province_owner(3), 0)
## An auto-resolved siege names the battery it silenced and the fort it dropped,
## and earns the silenced-battery medallion (DR-20261110-22, REQ-P5-05).
func test_an_auto_resolved_siege_despatch_names_the_silenced_battery() -> void:
	var battle: Dictionary = {
		"attacker": 0, "defender": 1,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"attacker_lost": ["unit_1"], "defender_lost": [],
		"siege": {
			"guns_start": 2, "guns_left": 0, "guns_lost": 2,
			"fort_before": 2, "fort_after": 1, "fort_downgraded": true,
		},
	}
	var line: String = BattleReport.describe_land(battle, "Burgundy", FACTIONS)
	assert_true(line.contains("2 of 2 emplaced guns silenced"), line)
	assert_true(line.contains("the Stone fort falls to Wood"), line)
	assert_eq(BattleReport.icon_of(battle), "silenced_gun")


func test_a_partial_battery_loss_reads_without_a_fort_fall() -> void:
	var battle: Dictionary = {
		"siege": {
			"guns_start": 3, "guns_left": 2, "guns_lost": 1,
			"fort_before": 3, "fort_after": 3, "fort_downgraded": false,
		},
	}
	assert_eq(
		BattleReport.siege_note(battle),
		" — 1 of 3 emplaced guns silenced"
	)
	assert_eq(BattleReport.siege_note({}), "")
	assert_eq(BattleReport.icon_of({}), "")


## A Quick Battle's battery is the same battery: the plate carries the wall for a
## moment, but the despatch that stays in the ledger must still say when the
## court's own fort lost a level (wiki: siege-mechanics § Emplaced Artillery;
## REQ-P5-05).
func test_a_quick_battles_siege_despatch_names_the_silenced_battery() -> void:
	var battle: Dictionary = {
		"attacker": 0, "defender": 1, "fort_level": 3,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"attacker_lost": ["unit_1"], "defender_lost": [],
		"quick": {
			"guns_start": 3, "guns_left": 1, "guns_lost": 2,
			"fort_downgraded": true, "fort_after": 2,
		},
	}
	var line: String = BattleReport.describe_land(battle, "Burgundy", FACTIONS)
	assert_true(line.contains("2 of 3 emplaced guns silenced"), line)
	assert_true(line.contains("the Modern fort falls to Stone"), line)
	assert_eq(BattleReport.icon_of(battle), "silenced_gun")

	# A quick battle whose battery was never touched adds no tail.
	var quiet: Dictionary = {
		"attacker": 0, "defender": 1, "fort_level": 1,
		"outcome": ArmyCombat.Outcome.STALEMATE,
		"attacker_lost": [], "defender_lost": [],
		"quick": {"guns_start": 1, "guns_left": 1, "guns_lost": 0},
	}
	assert_eq(BattleReport.siege_note(quiet), "")
	assert_eq(BattleReport.icon_of(quiet), "")


# --- from test_quick_battle_rules.gd ---
## Quick Battle contracts (wiki: quick-battle): three rounds, a player plan,
## deterministic casualties, the same ownership pipeline as auto-resolve, and
## virtual emplaced guns for sieges.


func test_quick_battle_is_deterministic_for_a_fixed_seed() -> void:
	var first: Dictionary = _fight("balanced", _guards(6), _pikes(4))
	var second: Dictionary = _fight("balanced", _guards(6), _pikes(4))

	assert_eq(int(first["outcome"]), int(second["outcome"]))
	assert_eq(
		(first["attacker_lost"] as Array).size(),
		(second["attacker_lost"] as Array).size()
	)
	assert_eq(
		(first["defender_lost"] as Array).size(),
		(second["defender_lost"] as Array).size()
	)
	assert_eq(_round_count(first), _round_count(second))


func test_quick_battle_runs_at_most_three_rounds() -> void:
	var battle: Dictionary = _fight("balanced", _guards(6), _pikes(6))
	var rounds: int = _round_count(battle)
	assert_true(rounds >= 1)
	assert_true(rounds <= QuickBattleTerms.MAX_ROUNDS)


func test_the_players_plan_drives_the_action_script() -> void:
	var aggressive: Dictionary = _fight("aggressive", _guards(6), _pikes(4))
	var defensive: Dictionary = _fight("defensive", _guards(6), _pikes(4))
	assert_eq(String(aggressive["quick"]["plan"]), "aggressive")
	assert_eq(String(defensive["quick"]["plan"]), "defensive")


## The crown holds one plan and it binds the side it commands, even on the wall;
## a rival side keeps the rule-derived script instead (wiki: quick-battle § The
## crown's plan; DR-20261110-33).
func test_the_crowns_plan_holds_on_the_defending_side() -> void:
	var model := Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := Fixture.army(1, 1, 2, _pikes(6), true)
	var attacker := Fixture.army(2, 2, 2, _guards(8))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = _context("aggressive")
	context["player_faction"] = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	var quick: Dictionary = reports[0]["quick"]

	assert_eq(String(quick["defender_plan"]), "aggressive", "the crown's plan holds")
	assert_eq(String(quick["plan"]), "balanced", "the rival keeps its own script")


func test_quick_battle_removes_casualties_from_the_armies() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, _pikes(6), true)
	var attacker := Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var before: int = ArmyForce.side_regiments(armies)

	ArmyCombat.resolve_turn(model, armies, _context("balanced"))

	assert_true(ArmyForce.side_regiments(armies) < before)


func test_a_siege_fields_virtual_guns_and_downgrades_the_fort() -> void:
	var model := Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, _guards(20))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, _context("balanced"))
	var battle: Dictionary = reports[0]

	assert_eq(String(battle["battle_mode"]), "siege")
	assert_eq(int(battle["quick"]["guns_start"]), 1)
	assert_true(bool(battle["quick"]["fort_downgraded"]))
	assert_eq(int(battle["quick"]["guns_lost"]), 1, "the battery is silenced")
	assert_eq(String(battle["quick"]["gun_type"]), "royal_artillery")
	assert_eq(int(battle["quick"]["fort_after"]), 0)
	assert_eq(model.province_data(2).fort_level, 0)


## The wall lanes are recorded for the despatch: infantry man the parapet, the
## battery and horse shelter behind it (wiki: siege-mechanics).
func test_a_siege_records_the_wall_lanes() -> void:
	var battle: Dictionary = _fight(
		"balanced", _guards(8), ["pikemen", "musketeers", "culverin"], 2
	)
	var lanes: Dictionary = battle["quick"]["lanes"]

	assert_eq(int(lanes["wall"]), 2, "two infantry regiments hold the wall")
	assert_eq(int(lanes["behind"]), 1, "the gun waits behind the parapet")


## Melee-only regiments cannot attack a wall or anything inside it; they need
## firearms or guns (wiki: siege-mechanics § Damage Reduction).
func test_melee_only_besiegers_are_turned_away() -> void:
	var model := Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, _pikes(8))
	attacker.moved = true
	var context: Dictionary = _context("balanced")
	## A garrison that holds the wall gives the pikes nothing to hit.
	context["defender_battle_plan"] = "defensive"
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	var battle: Dictionary = reports[0]

	assert_eq((battle["defender_lost"] as Array).size(), 0, "the garrison is untouched")
	assert_eq(int(battle["quick"]["guns_lost"]), 0, "pikes cannot silence the battery")
	var turned: bool = false
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if int(action["turned"]) > 0:
				turned = true
	assert_true(turned, "the despatch says the wall turned the blow aside")


## Only firearms, bows and guns strike a wall: eight pikes marching beside two
## musketeers break no more of a levied wall than the two muskets alone, and a
## line of pikes on its own opens no gate (wiki: siege-mechanics § Damage
## Reduction — "melee-only units cannot attack walls"; § Quick Battle lanes —
## "only regiments with RNG >= 2 can strike it").
func test_a_besiegers_pikes_do_not_break_the_wall() -> void:
	## Two firearms and eight pikes against the same line of ten firearms: both
	## sides field ten, and only the two muskets may weigh on the wall.
	var piked: Array[String] = _muskets(2)
	for _index in 8:
		piked.append("halberdiers")
	var mixed: Dictionary = _fight("aggressive", piked, _levies(12), 1)
	var ten: Dictionary = _fight("aggressive", _muskets(10), _levies(12), 1)

	assert_true(_wall_losses(mixed) > 0, "the two muskets still reach the wall")
	assert_true(
		_wall_losses(mixed) < _wall_losses(ten),
		"the eight pikes add nothing to the wall the two muskets break"
	)
	assert_true(
		_breaches(mixed) < _breaches(ten),
		"nor do they beat a gate down beside them"
	)


## The blow a besieger can land on a wall is the deployed regiments' rank that
## carry a firearm, a bow or a gun — a pike's rank is left out of the weight.
func test_only_firearms_weigh_against_a_wall() -> void:
	var pikes: Array[ArmyState] = _lane_side(["pikemen", "pikemen"], 2)
	var mixed: Array[ArmyState] = _lane_side(["musketeers", "pikemen"], 2)
	var muskets: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 2)

	assert_almost_eq(SiegeLanes.striking_weight(pikes, 10, 1.0), 0.0, 0.001, "pikes reach nothing")
	assert_almost_eq(
		SiegeLanes.striking_weight(mixed, 10, 1.0),
		float(RegimentCatalog.strength("musketeers")),
		0.01,
		"one musket weighs, the pike beside it does not"
	)
	assert_almost_eq(
		SiegeLanes.striking_weight(muskets, 10, 1.0),
		ArmyModifiers.strength(muskets, 10, 1.0),
		0.01,
		"a line of firearms weighs its whole rank"
	)


## What the crown reads before a siege is the exchange's own maths, not a second
## table beside it (wiki: siege-mechanics § Wall Protection; DR-20261120-06): the
## soak the wall takes off an attack and the share of a blow it spares the
## garrison, level by level, in one set of words.
func test_the_wall_read_names_the_figures_the_exchange_reads() -> void:
	var levels: Array[int] = [1, 2, 3]
	var hp: Array[int] = [10, 20, 30]
	var spared: Array[int] = [25, 45, 60]
	for index in levels.size():
		var level: int = levels[index]
		assert_eq(
			WallRead.line(level),
			"%d wall hp · %d%% off a blow" % [hp[index], spared[index]],
			"the wall's own two figures"
		)
		assert_almost_eq(
			WallRead.damage_share(level),
			1.0 - FortRules.loss_scale(level),
			0.0001,
			"the spared share is the casualty band's own scale"
		)
		assert_almost_eq(
			FortRules.wall_soak(500.0, level),
			500.0 - float(hp[index]),
			0.01,
			"and the soak is what the attack loses"
		)
	assert_eq(WallRead.line(0), "", "open ground says nothing")


## A march into another court's walled province reads the wall it will have to
## break; open ground keeps the plain line, so no siege is named where none
## stands (wiki: siege-mechanics § Wall Protection; REQ-P5-05).
func test_a_march_reads_the_wall_that_stands_there() -> void:
	assert_eq(WallRead.march_line("Badajoz", 0), "", "no wall, no siege line")
	assert_eq(
		WallRead.march_line("Badajoz", 1),
		"The army marches on Badajoz — a wood fort stands: "
		+ "10 wall hp, 1 emplaced gun, 25% off a blow."
	)
	assert_true(
		WallRead.march_line("Badajoz", 2).contains("2 emplaced guns"),
		WallRead.march_line("Badajoz", 2)
	)
	assert_true(
		WallRead.march_line("Badajoz", 3).contains("30 wall hp"),
		WallRead.march_line("Badajoz", 3)
	)


## A garrison that leaves the wall to sortie can hit back with every regiment,
## which is how a pike garrison hurts a siege at all.
func test_a_sortie_lets_a_pike_garrison_fight() -> void:
	var model := Fixture.build()
	model.province_data(2).fort_level = 2
	var defender := Fixture.army(1, 1, 2, _pikes(6), true)
	var attacker := Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var context: Dictionary = _context("aggressive")
	context["player_faction"] = 1
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_true(int(reports[0]["quick"]["sorties"]) > 0, "the defender chose to sortie")
	assert_true(
		(reports[0]["attacker_lost"] as Array).size() > 0,
		"outside the wall the pikes can reach the besiegers"
	)


## Regiment detail: the report counts the losses by regiment type, so the
## despatch can name them.
func test_the_report_tallies_losses_by_regiment_type() -> void:
	var battle: Dictionary = _fight("balanced", _guards(10), ["peasant_levies", "pikemen"], 1)
	var detail: Dictionary = battle["defender_detail"]
	var counted: int = 0
	for type_id: Variant in detail.keys():
		counted += int(detail[type_id])
		assert_true(RegimentCatalog.has_type(String(type_id)))

	assert_eq(counted, (battle["defender_lost"] as Array).size())
	assert_false(RegimentCatalog.detail_text(detail).is_empty())


func test_rival_battles_keep_the_aggregate_path() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, _pikes(3), true)
	var attacker := Fixture.army(2, 0, 2, _guards(5))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = _context("balanced")
	context["player_faction"] = 2

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_false(reports[0].has("quick"), "a rival battle stays auto-resolve")


func test_a_weak_attacker_is_repulsed() -> void:
	var battle: Dictionary = _fight("balanced", _pikes(2), _guards(8))
	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)


## Side strength is tactical, not a head count: four guards outweigh four
## pikes, and four pikes outweigh four levies (wiki: quick-battle § Cohesion
## and effective strength).
func test_effective_strength_aggregates_fpn_and_fpm() -> void:
	var guards: Array[ArmyState] = _lane_side(_guards(4), 2)
	var pikes: Array[ArmyState] = _lane_side(_pikes(4), 1)
	var levies: Array[ArmyState] = _lane_side(_levies(4), 1)

	var guard_weight: float = QuickBattleTerms.effective_strength(guards, 10, 3, 1.0)
	var pike_weight: float = QuickBattleTerms.effective_strength(pikes, 10, 3, 1.0)
	var levy_weight: float = QuickBattleTerms.effective_strength(levies, 10, 3, 1.0)

	assert_almost_eq(guard_weight, 4.0 * 22.0, 0.01, "Σ (FPN + FPM) for the slice")
	assert_true(guard_weight > pike_weight)
	assert_true(pike_weight > levy_weight)
	assert_almost_eq(
		QuickBattleTerms.effective_strength(guards, 10, 0, 1.0), 0.0, 0.001,
		"a broken line has no strength"
	)
	assert_almost_eq(
		QuickBattleTerms.effective_strength(guards, 10, 3, 2.0), guard_weight * 2.0,
		0.01, "the side multiplier scales the whole slice"
	)


## Reserves behind the deployment limit never count, exactly as in
## auto-resolve (wiki: combat § Strength).
func test_only_the_deployed_slice_counts_toward_strength() -> void:
	var twelve: Array[ArmyState] = _lane_side(_guards(12), 2)

	assert_almost_eq(
		QuickBattleTerms.effective_strength(twelve, 10, 3, 1.0), 10.0 * 22.0, 0.01
	)


## A chevroned regiment weighs more than a fresh one, and health scales it the
## same way (wiki: combat § Strength).
func test_chevrons_and_health_raise_a_regiments_weight() -> void:
	var fresh: Array[ArmyState] = _lane_side(_guards(2), 2)
	var veteran: Array[ArmyState] = _lane_side(_guards(2), 2)
	var army: ArmyState = veteran[0]
	for regiment_id: String in army.regiments:
		army.regiment_medals[regiment_id] = RegimentCatalog.MAX_MEDALS
	var fresh_weight: float = QuickBattleTerms.effective_strength(fresh, 10, 3, 1.0)
	var veteran_weight: float = QuickBattleTerms.effective_strength(veteran, 10, 3, 1.0)

	assert_almost_eq(veteran_weight, fresh_weight * 1.4, 0.01)
	var first: String = army.regiments[0]
	army.regiment_health[first] = RegimentCatalog.max_health("guards") / 2
	assert_true(
		QuickBattleTerms.effective_strength(veteran, 10, 3, 1.0) < veteran_weight,
		"a mauled regiment shoulders less"
	)


## An action's blow is spent as weight, so the same volley from a guard line
## breaks more men than from a levy line (wiki: quick-battle § Cohesion and
## effective strength).
func test_a_stronger_line_breaks_more_of_the_enemy() -> void:
	var strong: Array[ArmyState] = _lane_side(_guards(4), 2)
	var levies: Array[ArmyState] = _lane_side(_levies(4), 1)
	var hard: Dictionary = QuickBattleActions.resolve(
		_lane_joined(strong, levies), _lane_state(strong, levies, 0),
		"attacker", "defender", "volley", [] as Array[Dictionary]
	)
	var levy_attackers: Array[ArmyState] = _lane_side(_levies(4), 2)
	var guard_defenders: Array[ArmyState] = _lane_side(_guards(4), 1)
	var soft: Dictionary = QuickBattleActions.resolve(
		_lane_joined(levy_attackers, guard_defenders),
		_lane_state(levy_attackers, guard_defenders, 0),
		"attacker", "defender", "volley", [] as Array[Dictionary]
	)

	assert_eq(int(hard["defender_lost"]), 4, "the guard volley breaks the levy line")
	assert_true(int(soft["defender_lost"]) < 4, "the levy volley cannot break four guards")


## The virtual battery weighs its emplaced gun type, scaled by its remaining
## HP, instead of a flat per-gun count (wiki: quick-battle § Emplaced fort
## artillery).
func test_the_battery_weighs_its_gun_type_and_remaining_health() -> void:
	var guns: Array[Dictionary] = QuickBattleBattery.make(1, {}, 1)
	var royal: float = float(RegimentCatalog.strength("royal_artillery"))

	assert_almost_eq(QuickBattleBattery.strength(guns), royal, 0.01)
	QuickBattleBattery.hit(guns, 1)
	assert_almost_eq(QuickBattleBattery.strength(guns), royal * 0.5, 0.01)
	QuickBattleBattery.hit(guns, 1)
	assert_almost_eq(QuickBattleBattery.strength(guns), 0.0, 0.01, "a silenced gun weighs nothing")


func test_a_quick_battle_win_awards_the_general() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = _context("balanced")
	context["roster"] = roster
	context["army_general"] = {attacker.id: "general_1"}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(String(reports[0]["medal_gain"]), "general_1")
	assert_eq(int(reports[0]["medal_owner"]), 0)


func test_a_siege_battery_fires_while_guns_stand() -> void:
	var battle: Dictionary = _fight("balanced", _guards(6), _guards(8), 3)
	assert_eq(int(battle["quick"]["guns_start"]), 3)
	assert_true(int(battle["quick"]["guns_left"]) < 3)
	var fired: bool = false
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if String(action["action"]) == "battery":
				fired = true
	assert_true(fired, "the emplaced battery answers the assault")


## A reserve behind the line never pays for a charge: the same ten men in the
## line pay the same price for their assault whether ten more wait behind them
## or not (wiki: combat § The line and the reserve — "a reserve adds no strength,
## takes no casualties"; quick-battle § Battlefield layout — "the reserve is
## dealt nowhere").
func test_a_reserve_never_pays_for_the_charge() -> void:
	var alone: Dictionary = _fight("aggressive", _guards(10), _pikes(6), 0)
	var backed: Dictionary = _fight("aggressive", _guards(10) + _pikes(10), _pikes(6), 0)

	assert_eq(
		_assault_cost(backed), _assault_cost(alone),
		"the reserve adds no weight to the charge the line pays for"
	)
	assert_eq(
		int(backed["quick"]["attacker_start"]) - int(backed["quick"]["attacker_left"]),
		int(alone["quick"]["attacker_start"]) - int(alone["quick"]["attacker_left"]),
		"nor any loss of its own"
	)


## The fort's emplaced battery lays its fire on the men the besieging line was
## dealt: a reserve behind the line draws no shot and adds no target (wiki:
## combat § The line and the reserve — "a reserve adds no strength").
func test_the_battery_weighs_the_besieging_line_not_the_reserve() -> void:
	assert_eq(
		_battery_volley(_guards(10) + _pikes(30)), _battery_volley(_guards(10)),
		"a reserve behind the line makes the fort's fire no heavier"
	)


## A gun held in reserve never drops shot behind a parapet it never approached:
## the share that crosses the wall is the line's own guns over the line's own
## men (wiki: siege-mechanics § Quick Battle lanes — "artillery / besieging
## regiments"; combat § The line and the reserve — "a reserve adds no strength").
func test_a_reserve_gun_drops_no_shot_behind_the_wall() -> void:
	var on_line: Array[ArmyState] = _lane_side(["musketeers", "musketeers", "culverin"], 2)
	var held: Array[ArmyState] = _lane_side(
		["musketeers", "musketeers", "musketeers", "culverin"], 2
	)
	var line: Array[String] = _line_without_guns(held)

	assert_true(
		_behind_losses(on_line, ArmyForce.line_ids(on_line, 10)) > 0,
		"a gun in the line reaches behind the parapet"
	)
	assert_eq(
		_behind_losses(held, line), 0,
		"a gun in the reserve drops no shot behind the wall"
	)


## The own price of an assault or a sortie, as the attacker's actions name it.
func _assault_cost(battle: Dictionary) -> int:
	var total: int = 0
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if String(action["action"]) == "assault":
				total += int(action["attacker_lost"])
	return total


## One emplaced battery's volley against a besieging side, read off the blow.
func _battery_volley(types: Array[String]) -> int:
	var side: Array[ArmyState] = _lane_side(types, 2)
	var state: Dictionary = _lane_state(side, [] as Array[ArmyState], 3)
	state["attacker"]["wings"] = QuickBattleWings.deploy(side, 10)
	state["attacker"]["line"] = ArmyForce.line_ids(side, 10)
	var guns: Array[Dictionary] = QuickBattleBattery.make(3, {}, 1)
	return int(QuickBattleBattery.fire(_lane_joined(side, [] as Array[ArmyState]), state, guns)["lost"])


## The men of a besieging side left in the line once its guns are held back.
func _line_without_guns(side: Array[ArmyState]) -> Array[String]:
	var line: Array[String] = []
	for entry: Dictionary in ArmyForce.side_entries(side):
		if not RegimentCatalog.is_artillery(String(entry["type"])):
			line.append(String(entry["id"]))
	return line


## Behind-lane casualties one siege blow draws from a levied garrison.
func _behind_losses(attacker: Array[ArmyState], line: Array[String]) -> int:
	var defender: Array[ArmyState] = _lane_side(
		["peasant_levies", "peasant_levies", "peasant_levies", "squires", "squires"], 1
	)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)
	var split: Dictionary = SiegeLanes.strike(
		armies, attacker, defender, 12, 10, 2, false, {}, {}, line
	)
	return (split["behind"] as Array).size()


## The despatch copy reads `defender_lost` on an attacker's action as losses it
## inflicted and `attacker_lost` as its own cost, so the report must add up that
## way round: every loss a side suffered is either inflicted by the enemy or paid
## by its own action.
func test_round_despatches_add_up_to_each_sides_losses() -> void:
	var battle: Dictionary = _fight("aggressive", _guards(6), _pikes(8), 2)
	var quick: Dictionary = battle["quick"]
	var atk_inflicted: int = 0
	var atk_own: int = 0
	var def_inflicted: int = 0
	var def_own: int = 0
	for round: Dictionary in quick["rounds"]:
		for action: Dictionary in round["actions"]:
			var entry: Dictionary = action as Dictionary
			if int(entry["side"]) == int(battle["attacker"]):
				atk_inflicted += int(entry["defender_lost"])
				atk_own += int(entry["attacker_lost"])
			else:
				def_inflicted += int(entry["attacker_lost"])
				def_own += int(entry["defender_lost"])
	assert_eq(
		def_inflicted + atk_own,
		int(quick["attacker_start"]) - int(quick["attacker_left"]),
		"every attacker loss is a despatch number"
	)
	assert_eq(
		atk_inflicted + def_own,
		int(quick["defender_start"]) - int(quick["defender_left"]),
		"every defender loss is a despatch number"
	)


func _fight(
	plan: String, attacker_types: Array[String], defender_types: Array[String],
	fort: int = 0, defender_plan: String = ""
) -> Dictionary:
	var model := Fixture.build()
	model.province_data(2).fort_level = fort
	var defender := Fixture.army(1, 1, 2, defender_types, true)
	var attacker := Fixture.army(2, 0, 2, attacker_types)
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = _context(plan)
	if not defender_plan.is_empty():
		context["defender_battle_plan"] = defender_plan
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	return reports[0]


func test_a_quick_battle_pays_the_attack_price_too() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, _pikes(4), true)
	var attacker := Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var charged: Array = []
	var pay := func(owner: int, cost: int) -> int:
		charged.append([owner, cost])
		return mini(cost, 40)
	var context: Dictionary = _context("balanced")
	context["pay_attack"] = pay

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(charged, [[0, 100]], "the plate charges the same price as auto-resolve")
	assert_eq(int(reports[0]["attack_cost"]), 100)
	assert_eq(int(reports[0]["attack_paid"]), 40, "a thin purse pays what it has")
	assert_true(reports[0].has("quick"))


func _context(plan: String) -> Dictionary:
	return {
		"quick_battle": true,
		"player_faction": 0,
		"battle_plan": plan,
		"seed": 11,
	}


func _round_count(battle: Dictionary) -> int:
	return (battle["quick"]["rounds"] as Array).size()


func _guards(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	return types


func _pikes(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("pikemen")
	return types


func _levies(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("peasant_levies")
	return types


func _muskets(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("musketeers")
	return types


## Gates a siege beat down, as the plate reads them.
func _breaches(battle: Dictionary) -> int:
	return int((battle["quick"]["gates"] as Dictionary).get("broken", 0))


## Wall regiments a besieger broke over the whole battle, read off the round log
## the plate prints.
func _wall_losses(battle: Dictionary) -> int:
	var total: int = 0
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if int(action["side"]) == int(battle["attacker"]):
				total += int(action["wall_lost"])
	return total

# --- Siege lanes (wiki: siege-mechanics § Quick Battle lanes) ---


func test_the_garrison_splits_into_wall_and_behind() -> void:
	var side: Array[ArmyState] = _lane_side(["pikemen", "musketeers", "squires", "culverin"], 1)

	assert_eq(SiegeLanes.wall_ids(side).size(), 2, "infantry man the wall")
	assert_eq(SiegeLanes.behind_ids(side).size(), 2, "horse and guns wait behind")
	assert_true(SiegeLanes.is_wall_type("guards"))
	assert_false(SiegeLanes.is_wall_type("squires"))
	assert_false(SiegeLanes.is_wall_type("culverin"))
	assert_eq(SiegeLanes.describe(side), "2 on the wall · 2 behind")


## A standing gun spends the besieger's blow before the lanes: the garrison is
## sheltered while the battery answers (wiki: siege-mechanics § Quick Battle
## lanes — "spends its blow on the battery before the lanes").
func test_a_standing_gun_spends_the_blow_before_the_lanes() -> void:
	var defender: Array[ArmyState] = _lane_side(
		["peasant_levies", "peasant_levies", "peasant_levies"], 1
	)
	var attacker: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 2)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)
	var guns: Array[Dictionary] = QuickBattleBattery.make(1, {}, 1)
	var state: Dictionary = _lane_state(attacker, defender, 1)

	var first: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)
	assert_eq(int(first["defender_lost"]), 0, "the gun drinks the volley")
	assert_eq(int(first["battery_hit"]), 1)
	assert_eq(int(first["guns_destroyed"]), 0, "one hit does not silence a gun")

	var second: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)
	assert_eq(int(second["guns_destroyed"]), 1, "the second volley silences it")
	assert_eq(int(second["defender_lost"]), 0, "the garrison is still under cover")

	var third: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)
	assert_eq(int(third["guns_destroyed"]), 0)
	assert_true(int(third["wall_lost"]) > 0, "with the battery quiet the wall takes the fire")


## One blow bleeds no more than the deployed slice: the two lanes share one
## deployment limit, so the reserves behind it still do not die in the same
## volley (wiki: combat § Auto-resolve casualty selection).
func test_a_siege_blow_bleeds_no_more_than_the_deployed_slice() -> void:
	var limit: int = ArmyModifiers.deployment_limit(0, false)
	var guns_only: Array[String] = []
	for _index in 18:
		guns_only.append("culverin")
	var thick: Array[String] = ["peasant_levies", "peasant_levies"]
	for _index in 20:
		thick.append("squires")
	var attacker: Array[ArmyState] = _lane_side(guns_only, 2)
	var defended: Array[ArmyState] = _lane_side(thick, 1)
	var armies: Array[ArmyState] = _lane_joined(attacker, defended)

	var split: Dictionary = SiegeLanes.strike(armies, attacker, defended, 60, limit, 3, false)

	assert_eq((split["wall"] as Array).size(), 0, "a gun-only besieger hits nothing on the wall")
	assert_eq(
		(split["behind"] as Array).size(), limit,
		"the behind lane takes the deployed slice and no more"
	)


func test_melee_only_besiegers_cannot_touch_a_wall() -> void:
	var attacker: Array[ArmyState] = _lane_side(["pikemen", "knights"], 2)
	var defender: Array[ArmyState] = _lane_side(["peasant_levies"], 1)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)
	var wanted: int = 3

	var split: Dictionary = SiegeLanes.strike(armies, attacker, defender, wanted, 10, 2, false)

	assert_eq(int(split["turned"]), wanted, "the wall turns the pikes aside")
	assert_eq((split["wall"] as Array).size(), 0)
	assert_eq(defender[0].count(), 1, "nobody on the wall is hurt")


func test_firearms_hit_the_wall_and_the_fort_blunts_the_blow() -> void:
	var open_field: int = _struck_lane_losses(2 - 2, 4)
	var stone: int = _struck_lane_losses(2, 4)

	assert_eq(open_field, 4, "an open field takes the whole blow")
	assert_eq(stone, ceili(4.0 * FortRules.loss_scale(2)), "the wall spares a share")
	assert_true(stone < open_field)


func test_only_artillery_reaches_behind_the_wall() -> void:
	var muskets: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 2)
	var guns: Array[ArmyState] = _lane_side(["musketeers", "musketeers", "culverin"], 2)
	var defender: Array[ArmyState] = _lane_side(["pikemen", "pikemen", "pikemen", "culverin"], 1)
	var armies: Array[ArmyState] = _lane_joined(guns, defender)

	assert_false(SiegeLanes.can_reach_behind(muskets), "small arms stay outside")
	var shot: Dictionary = SiegeLanes.strike(armies, guns, defender, 4, 10, 2, false)

	assert_true((shot["behind"] as Array).size() > 0, "guns drop shot over the parapet")
	assert_true((shot["wall"] as Array).size() > 0)

	var walls_only: Array[ArmyState] = _lane_side(["pikemen", "pikemen", "pikemen", "culverin"], 1)
	var field_only: Array[ArmyState] = _lane_joined(muskets, walls_only)
	var small: Dictionary = SiegeLanes.strike(field_only, muskets, walls_only, 4, 10, 2, false)
	assert_eq((small["behind"] as Array).size(), 0, "only artillery can hit behind")


func test_a_sortie_sheds_the_walls_protection() -> void:
	var sheltered: int = _struck_lane_losses(2, 6, false)
	var sortied: int = _struck_lane_losses(2, 6, true)

	assert_eq(sheltered, ceili(6.0 * FortRules.loss_scale(2)))
	assert_eq(sortied, 6, "outside the wall the garrison takes the whole blow")
	assert_true(sortied > sheltered)


func test_return_fire_follows_the_garrisons_range() -> void:
	var pikes: Array[ArmyState] = _lane_side(["pikemen", "pikemen"], 1)
	var muskets: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 1)
	var mixed: Array[ArmyState] = _lane_side(["pikemen", "pikemen", "musketeers", "musketeers"], 1)

	assert_almost_eq(SiegeLanes.return_fire_share(pikes), 0.0, 0.001, "pikes cannot shoot")
	assert_almost_eq(SiegeLanes.return_fire_share(muskets), 1.0, 0.001)
	assert_almost_eq(SiegeLanes.return_fire_share(mixed), 0.5, 0.001)


## A reserve behind the wall neither shoots from it nor thins the fire of the men
## who stand on it: the wall's ranged share is read over the line the battle
## dealt, not over every regiment the garrison has (wiki: combat § The line and
## the reserve — "a reserve adds no strength"; siege-mechanics § Quick Battle
## lanes — "ranged share of its own count"). Bowmen rank below pikemen, so the
## ten pikes are the line and the four bows wait behind it.
func test_a_reserve_never_returns_fire_from_the_wall() -> void:
	var pike_wall: Array[ArmyState] = _lane_side(
		["bowmen", "bowmen", "bowmen", "bowmen",
		"pikemen", "pikemen", "pikemen", "pikemen", "pikemen",
		"pikemen", "pikemen", "pikemen", "pikemen", "pikemen"], 1
	)
	var pike_line: Array[String] = ArmyForce.line_ids(pike_wall, 10)
	assert_eq(pike_line.size(), 10, "ten pikes stand in the line")
	assert_almost_eq(
		SiegeLanes.return_fire_share(pike_wall, pike_line), 0.0, 0.001,
		"a pike wall gives no return fire, whatever waits behind it"
	)
	## The other way round: a musket wall keeps its whole fire though four levies
	## wait behind it.
	var musket_wall: Array[ArmyState] = _lane_side(
		["peasant_levies", "peasant_levies", "peasant_levies", "peasant_levies",
		"musketeers", "musketeers", "musketeers", "musketeers", "musketeers",
		"musketeers", "musketeers", "musketeers", "musketeers", "musketeers"], 1
	)
	var musket_line: Array[String] = ArmyForce.line_ids(musket_wall, 10)
	assert_almost_eq(
		SiegeLanes.return_fire_share(musket_wall, musket_line), 1.0, 0.001,
		"the levies behind the wall thin no fire"
	)


## The wall's volley breaks no besieger when the only bows in the garrison wait
## in reserve: a regiment that never took the field adds no strength to the
## parapet (wiki: combat § The line and the reserve; siege-mechanics
## § Quick Battle lanes).
func test_a_reserve_never_shoots_at_a_besieger() -> void:
	var bare: int = _wall_volley_losses(
		["pikemen", "pikemen", "pikemen", "pikemen", "pikemen",
		"pikemen", "pikemen", "pikemen", "pikemen", "pikemen"]
	)
	var stuffed: int = _wall_volley_losses(
		["bowmen", "bowmen", "bowmen", "bowmen",
		"pikemen", "pikemen", "pikemen", "pikemen", "pikemen",
		"pikemen", "pikemen", "pikemen", "pikemen", "pikemen"]
	)

	assert_eq(bare, 0, "a pike wall breaks nobody")
	assert_eq(stuffed, bare, "the four bows behind the wall fire nothing")


## A pike wall still sallies when the only bows in the garrison wait in reserve:
## the automatic sally reads the wall's own line, and a bow held back opens no
## wall either (wiki: siege-mechanics § Quick Battle lanes — "a garrison with no
## firearm behind a wall sallies on its own"; combat § The line and the reserve).
func test_a_pike_wall_with_a_reserve_still_sallies() -> void:
	var side: Array[ArmyState] = _rival(
		["bowmen", "bowmen", "bowmen", "bowmen",
		"pikemen", "pikemen", "pikemen", "pikemen", "pikemen",
		"pikemen", "pikemen", "pikemen", "pikemen", "pikemen"]
	)
	var line: Array[String] = ArmyForce.line_ids(side, 10)

	assert_eq(
		QuickBattleTerms.plan_for(side, 1, {}, true, true, line), "aggressive",
		"a wall with no firearm on it sallies"
	)
	assert_false(SiegeLanes.can_reach_wall(side, line), "a bow in reserve opens no wall")


## The besieger's losses from one wall volley, with the garrison's line and lanes
## dealt the way [QuickBattle] deals them.
func _wall_volley_losses(types: Array[String]) -> int:
	var defender: Array[ArmyState] = _lane_side(types, 1)
	var attacker: Array[ArmyState] = _lane_side(
		["musketeers", "musketeers", "musketeers", "musketeers", "musketeers", "musketeers"], 2
	)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)
	var state: Dictionary = {
		"attacker": {
			"side": attacker, "owner": 2, "limit": 10, "mods": {},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "balanced", "exposed": false,
			"line": ArmyForce.line_ids(attacker, 10),
		},
		"defender": {
			"side": defender, "owner": 1, "limit": 10, "mods": {"fort": 1},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "defensive", "exposed": false,
			"line": ArmyForce.line_ids(defender, 10),
			"lanes": SiegeLanes.line_ids(defender, 10),
		},
		"terrain": "open",
		"gates": SiegeGates.gates_for(1),
	}
	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "defender", "attacker", "volley", []
	)
	return int(entry["attacker_lost"])


func test_an_empty_garrison_absorbs_nothing() -> void:
	var attacker: Array[ArmyState] = _lane_side(["musketeers"], 2)
	var defender: Array[ArmyState] = []
	var split: Dictionary = SiegeLanes.strike(
		attacker, attacker, defender, 3, 10, 2, false
	)

	assert_eq((split["wall"] as Array).size(), 0)
	assert_eq((split["behind"] as Array).size(), 0)
	assert_eq(int(split["turned"]), 0)
	assert_almost_eq(SiegeLanes.return_fire_share(defender), 0.0, 0.001)
	assert_false(SiegeLanes.can_reach_wall(defender))
	assert_eq(SiegeLanes.describe(defender), "0 on the wall · 0 behind")


## A hole in an army list (a pruned army) is skipped, never crashed on.
func test_a_null_army_is_skipped() -> void:
	var side: Array[ArmyState] = _lane_side(["pikemen"], 1)
	side.append(null)

	assert_eq(SiegeLanes.wall_ids(side).size(), 1)
	assert_false(SiegeLanes.behind_ids(side).size() > 0)
	assert_true(SiegeLanes.can_reach_wall(_lane_side(["musketeers"], 2)))
	assert_false(SiegeLanes.can_reach_behind(side))


func _struck_lane_losses(fort: int, wanted: int, exposed: bool = false) -> int:
	var attacker: Array[ArmyState] = _lane_side(["musketeers", "musketeers", "musketeers"], 2)
	var defender: Array[ArmyState] = _lane_side(
		["peasant_levies", "peasant_levies", "peasant_levies", "peasant_levies",
		"peasant_levies", "peasant_levies"], 1
	)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)
	var split: Dictionary = SiegeLanes.strike(
		armies, attacker, defender, wanted, 10, fort, exposed
	)
	return (split["wall"] as Array).size() + (split["behind"] as Array).size()


func _lane_side(types: Array[String], owner: int) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(Fixture.army(10 + owner, owner, 2, types, true))
	return side


func _lane_joined(first: Array[ArmyState], second: Array[ArmyState]) -> Array[ArmyState]:
	var all: Array[ArmyState] = []
	all.append_array(first)
	all.append_array(second)
	return all


## Battle state for one scripted action, shaped the way [QuickBattle] builds it.
func _lane_state(attacker: Array[ArmyState], defender: Array[ArmyState], fort: int) -> Dictionary:
	return {
		"attacker": {
			"side": attacker, "owner": 2, "limit": 10, "mods": {},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "balanced", "exposed": false,
		},
		"defender": {
			"side": defender, "owner": 1, "limit": 10, "mods": {"fort": fort},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "defensive", "exposed": false,
		},
	}

# --- regiment health and chevrons (wiki: combat § Strength; DR-20261110-14) ---


## Every blow that breaks a regiment must show the health it took from the men
## still standing: the plate's bars and damage numbers read from these hits.
func test_every_action_shows_the_health_it_took() -> void:
	var battle: Dictionary = _fight("balanced", _guards(6), _guards(20))
	var counted: int = 0
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			var losses: int = int(action["attacker_lost"]) + int(action["defender_lost"])
			var hits: Array = action["hits"] as Array
			if losses <= 0:
				continue
			counted += 1
			assert_true(not hits.is_empty(), "a blow that broke a regiment mauled the rest")
			assert_eq(int(action["mauled"]), hits.size())
			for hit: Dictionary in hits:
				assert_true(int(hit["damage"]) > 0)
				assert_true(int(hit["hp"]) < int(hit["max"]))
	assert_true(counted > 0, "the fight landed blows")


func test_round_logs_carry_a_condition_snapshot() -> void:
	var battle: Dictionary = _fight("balanced", _guards(6), _guards(6))
	var rounds: Array = battle["quick"]["rounds"] as Array
	assert_true(not rounds.is_empty())
	for round: Dictionary in rounds:
		assert_true(round.has("attacker_health"))
		assert_true(round.has("defender_health"))
		assert_true(float(round["attacker_strength"]) <= 1.0)
		assert_true(float(round["defender_strength"]) <= 1.0)
	var last: Dictionary = rounds[rounds.size() - 1] as Dictionary
	var mauled: int = 0
	var entries: Array = (last["attacker_health"] as Array) + (last["defender_health"] as Array)
	for entry: Dictionary in entries:
		if float(entry["fraction"]) < 1.0:
			mauled += 1
	assert_true(mauled > 0, "survivors carry wounds out of the battle")


func test_the_battle_report_carries_aftermath_condition_and_chevrons() -> void:
	var battle: Dictionary = _fight("balanced", _guards(8), _pikes(2))
	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_true((battle["attacker_health"] as Array).size() > 0)
	assert_true(int(battle["attacker_chevrons"]) > 0)
	assert_eq(int(battle["defender_chevrons"]), 0, "the broken side wins nothing")
	assert_true(int(battle["defender_mauled"]) >= 0)


## The same aftermath hook writes the field's name onto the winner's colours
## (wiki: naming § Regiment records; DR-20261112-02). The plate reads the count.
func test_a_won_quick_battle_honours_the_winning_colours() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, _pikes(2), true)
	var attacker := Fixture.army(2, 0, 2, _guards(8))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, _context("balanced"))

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(int(reports[0]["attacker_honours"]), attacker.count())
	assert_eq(int(reports[0]["defender_honours"]), 0, "a broken side takes no colour")
	for regiment_id: String in attacker.regiments:
		assert_eq(RegimentRecord.colours(attacker, regiment_id), [2])


func test_a_defended_province_honours_its_holder() -> void:
	var battle: Dictionary = _fight("defensive", _pikes(2), _guards(8))
	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_eq(int(battle["attacker_honours"]), 0, "the beaten side takes nothing")
	assert_true(int(battle["defender_honours"]) > 0, "the field's name goes to the holder")


func test_veterans_are_deployed_ahead_of_fresh_regiments() -> void:
	var army := Fixture.army(1, 0, 2, ["guards", "guards"])
	var veteran: String = army.regiments[0]
	army.regiment_medals[veteran] = 4
	var side: Array[ArmyState] = [army]

	var deployed: Array[Dictionary] = ArmyModifiers.deployed(side, 1)

	assert_eq(String(deployed[0]["id"]), veteran, "the chevroned regiment leads")
	assert_eq(int(deployed[0]["medals"]), 4)

# --- The published plan scripts (wiki: quick-battle § The crown's plan,
# § The plan scripts; DR-20261110-34) ---


## The three stances and their ordered action lists are the rules: the page
## publishes them, so a replay must be able to read them here.
func test_the_published_plan_scripts_match_the_wiki() -> void:
	assert_eq(QuickBattleActions.actions_for("aggressive"), ["maneuver", "assault"])
	assert_eq(QuickBattleActions.actions_for("balanced"), ["volley", "entrench", "volley"])
	assert_eq(QuickBattleActions.actions_for("defensive"), ["fall_back", "volley"])

	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, true), ["entrench", "sortie"],
		"a siege garrison with an aggressive plan entrenches then sallies"
	)
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, false),
		["entrench", "volley", "volley"],
		"a sortie with no wall is ordinary volley fire"
	)
	assert_eq(QuickBattleActions.actions_for("balanced", true, true), ["volley", "entrench"])
	assert_eq(QuickBattleActions.actions_for("balanced", true, false), ["volley", "entrench"])
	assert_eq(QuickBattleActions.actions_for("defensive", true, true), ["fall_back", "volley"])
	assert_eq(QuickBattleActions.actions_for("defensive", true, false), ["fall_back", "volley"])


## 3 CP a side each round, and no action is ever taken without its price.
func test_a_side_spends_at_most_three_cp_a_round() -> void:
	for plan: String in ["aggressive", "balanced", "defensive"]:
		var battle: Dictionary = _fight(plan, _guards(6), _pikes(6))
		var rounds: Array = battle["quick"]["rounds"] as Array
		assert_true(not rounds.is_empty())
		for round: Dictionary in rounds:
			for side: int in [int(battle["attacker"]), int(battle["defender"])]:
				var spent: int = _cp_spent(round, side)
				assert_true(spent <= QuickBattleTerms.CP_PER_ROUND, "%s spends %d CP" % [plan, spent])


## The side the human does not command is chosen in the published order
## (wiki: quick-battle § The opposing script): a scenario plan, the crown's own,
## the firearmless sally, a cavalry share ≥ 0.3, then the side's default.
func test_the_opposing_script_follows_the_published_order() -> void:
	var pikes: Array[ArmyState] = _rival(["pikemen", "pikemen"])
	var muskets: Array[ArmyState] = _rival(["pikemen", "musketeers"])
	assert_eq(QuickBattleTerms.plan_for(pikes, 1, {}, true, true), "aggressive",
		"a wall with no firearm sallies")
	assert_eq(QuickBattleTerms.plan_for(muskets, 1, {}, true, true), "defensive",
		"a wall that can shoot holds")
	assert_eq(QuickBattleTerms.plan_for(_rival(["squires", "pikemen", "pikemen"]), 1, {}, false),
		"aggressive", "cavalry share ≥ 0.3")
	assert_eq(QuickBattleTerms.plan_for(_rival(["squires", "pikemen", "pikemen", "pikemen"]), 1, {}, true, false),
		"defensive", "cavalry share below 0.3")
	assert_eq(QuickBattleTerms.plan_for(_rival(["squires", "pikemen"]), 0, {}, false), "aggressive")
	assert_eq(QuickBattleTerms.plan_for(_rival(["pikemen", "pikemen"]), 0, {}, false), "balanced")
	## An explicit scenario plan outranks the ranking, and the crown's plan
	## outranks the automatic sally.
	assert_eq(
		QuickBattleTerms.plan_for(pikes, 1, {"defender_battle_plan": "balanced"}, true, true),
		"balanced"
	)
	assert_eq(
		QuickBattleTerms.plan_for(pikes, 1, {"player_faction": 1, "battle_plan": "defensive"}, true, true),
		"defensive", "the crown's plan holds its own wall"
	)


## A sally is a real sortie, not a label: the firearmless garrison leaves the
## wall (wiki: siege-mechanics § Gates and Sortie).
func test_a_firearmless_garrison_sallies_when_no_one_commands_it() -> void:
	## The garrison must still stand when its turn comes: a line that has lost
	## its last regiment spends no point, so a sally is read on a wall that
	## holds men (wiki: quick-battle § Outcome and integration).
	var battle: Dictionary = _fight("balanced", _guards(4), _pikes(10), 1)
	assert_eq(String(battle["quick"]["defender_plan"]), "aggressive")
	assert_true(int(battle["quick"]["sorties"]) > 0, "the garrison left the wall")


## Any value the page does not publish is `balanced`, wherever it came from
## (wiki: quick-battle § The crown's plan).
func test_an_unknown_plan_is_balanced() -> void:
	assert_eq(QuickBattleActions.normalize_plan("hammer"), "balanced")
	assert_eq(QuickBattleActions.normalize_plan(""), "balanced")
	assert_eq(QuickBattleActions.normalize_plan("defensive"), "defensive")
	assert_eq(
		QuickBattleTerms.plan_for(
			_rival(["pikemen"]), 0, {"player_faction": 0, "battle_plan": "hammer"}, false
		),
		"balanced", "a crown's unknown stance fights balanced"
	)


## Every blow a round records — a scripted order and the fort's own volley —
## wears the one action shape the plate and the despatch read, so neither needs
## a special case for the battery (REQ-P3-01).
func test_every_blow_writes_the_one_action_shape() -> void:
	var battle: Dictionary = _fight("balanced", _guards(6), _guards(8), 3)
	var skeleton: Dictionary = QuickBattleActions.action_entry(1, "battery", "Emplaced battery")
	var saw_battery: bool = false
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			for key: String in skeleton.keys():
				assert_true(action.has(key), "a blow carries %s" % key)
			if String(action["action"]) == "battery":
				saw_battery = true
				assert_eq(String(action["label"]), "Emplaced battery")
	assert_true(saw_battery, "the emplaced battery answers the siege")


## A battery that hits nobody writes no action at all: the plate must not print
## a silent volley (wiki: quick-battle § Wings and collapse).
func test_a_silent_battery_writes_no_action() -> void:
	var side: Array[ArmyState] = _rival(["guards", "guards", "guards", "guards"])
	var state: Dictionary = {
		"attacker": {"side": side, "limit": 10, "wings": {}, "broken": [],
			"lost": [] as Array[String]},
		"defender": {},
	}
	var silent: Array[Dictionary] = []
	assert_true(
		QuickBattleBattery.volley_entry(side, state, silent, 1).is_empty(),
		"no gun, no volley"
	)


## The report slice is written from the facts read when the battle opened, so
## the plate, the despatch and the rail read one shape (REQ-P2-03, REQ-P3-01).
func test_the_report_slice_reads_the_opening_it_is_handed() -> void:
	var state: Dictionary = {
		"attacker": {"plan": "balanced", "side": [] as Array[ArmyState], "cohesion": 2,
			"broken": []},
		"defender": {"plan": "defensive", "side": [] as Array[ArmyState], "cohesion": 3,
			"broken": []},
	}
	var opening: Dictionary = {
		"attacker_start": 6,
		"defender_start": 4,
		"level": 2,
		"downgraded": true,
		"after": 1,
		"wall": 2,
		"behind": 1,
		"terrain": "hill",
		"gates": {"broken": 1},
	}
	var slice: Dictionary = QuickBattleReport.build(
		state, [] as Array[Dictionary], [] as Array[Dictionary], {}, 1, opening,
		{"attacker": {"limit": 10}, "defender": {"limit": 5}}, {}
	)

	assert_eq(int(slice["attacker_start"]), 6)
	assert_eq(int(slice["defender_start"]), 4)
	assert_eq(String(slice["terrain"]), "hill")
	assert_eq(String(slice["terrain_label"]), SiegeGround.terrain_label("hill"))
	assert_eq(int(slice["lanes"]["wall"]), 2)
	assert_eq(int(slice["lanes"]["behind"]), 1)
	assert_eq(int(slice["breaches"]), 1)
	assert_eq(int(slice["limits"]["defender"]), 5)
	assert_eq(int(slice["attacker_cohesion"]), 2)
	assert_eq(int(slice["sorties"]), 0)
	assert_true(bool(slice["fort_downgraded"]))
	assert_eq(int(slice["fort_after"]), 1)
	assert_true(slice.has("wings_broken"), "the wings record rides the slice")


func _rival(types: Array[String]) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(Fixture.army(7, 1, 2, types, true))
	return side


func _cp_spent(round: Dictionary, side: int) -> int:
	var spent: int = 0
	for entry: Dictionary in round["actions"] as Array:
		if int(entry["side"]) != side:
			continue
		spent += int(QuickBattleActions.ACTION_CP.get(String(entry["action"]), 0))
	return spent


# --- from test_siege_depth.gd ---
## Siege depth (wiki: siege-mechanics § Quick Battle lanes / § Gates and Sortie;
## quick-battle § Terrain / § Core actions): lane terrain, three gates and the
## breach they open, and the dedicated Sortie order.


func test_lane_terrain_follows_the_ground() -> void:
	var model := Fixture.build()
	assert_eq(SiegeGround.lane_terrain(model, 2, 0), "open", "plains without a fort")
	assert_eq(SiegeGround.lane_terrain(model, 2, 1), "town", "a fort rings its town")
	_set_ground(model, 2, MapModel.Terrain.HILLS)
	assert_eq(SiegeGround.lane_terrain(model, 2, 0), "hill")
	assert_eq(SiegeGround.lane_terrain(model, 2, 2), "hill", "broken ground keeps its character")
	_set_ground(model, 2, MapModel.Terrain.HARDWOOD_FOREST)
	assert_eq(SiegeGround.lane_terrain(model, 2, 0), "woods")
	_set_ground(model, 2, MapModel.Terrain.SWAMP)
	assert_eq(SiegeGround.lane_terrain(model, 2, 0), "marsh")
	assert_eq(SiegeGround.lane_terrain(model, 2, 0, "town"), "town", "a playtest may override")


## The ground is published as `marsh` (wiki: quick-battle § Terrain;
## DR-20261110-27): a swamp province fights on marsh ground and the documented
## override is the same id the record carries — not the map's terrain enum name.
func test_the_marsh_ground_speaks_the_published_id() -> void:
	var model := Fixture.build()
	_set_ground(model, 2, MapModel.Terrain.SWAMP)

	assert_true(SiegeGround.TERRAIN.has("marsh"), "the published id is the table key")
	assert_eq(SiegeGround.lane_terrain(model, 2, 0, "marsh"), "marsh",
		"the documented playtest override is honoured")
	assert_eq(SiegeGround.lane_terrain(model, 2, 0, "swamp"), "marsh",
		"the map enum name is not a lane id; it falls back to the province ground")
	assert_almost_eq(SiegeGround.terrain_scale("volley", "marsh"), 0.9, 0.001)
	assert_almost_eq(SiegeGround.terrain_scale("assault", "marsh"), 0.7, 0.001)
	assert_almost_eq(SiegeGround.entrench_scale("marsh"), 0.8, 0.001)
	assert_eq(SiegeGround.terrain_label("marsh"), "Marsh")

	var battle: Dictionary = _siege_fight(
		"balanced", _repeat("guards", 8), _repeat("musketeers", 6), 0, "marsh"
	)
	assert_eq(String(battle["quick"]["terrain"]), "marsh", "the record speaks the rule")
	assert_eq(String(battle["quick"]["terrain_label"]), "Marsh")
	assert_true(
		_assault_losses("marsh", 20) < _assault_losses("open", 20),
		"a charge into the marsh is blunted, not open ground"
	)


func test_terrain_scales_the_action_tables() -> void:
	assert_almost_eq(SiegeGround.terrain_scale("volley", "open"), 1.0, 0.001)
	assert_almost_eq(SiegeGround.terrain_scale("assault", "town"), 0.55, 0.001)
	assert_almost_eq(SiegeGround.terrain_scale("assault", "woods"), 0.6, 0.001)
	assert_almost_eq(SiegeGround.terrain_scale("volley", "woods"), 0.75, 0.001)
	assert_almost_eq(SiegeGround.entrench_scale("town"), 1.4, 0.001)
	assert_almost_eq(SiegeGround.entrench_scale("marsh"), 0.8, 0.001)
	assert_almost_eq(SiegeGround.terrain_scale("entrench", "town"), 1.0, 0.001, "no damage")
	assert_eq(SiegeGround.terrain_label("hill"), "Hillside")
	assert_eq(SiegeGround.terrain_label("unknown"), "Open field")


func test_three_gates_open_one_at_a_time() -> void:
	var gates: Dictionary = SiegeGates.gates_for(2)
	assert_eq(int(gates["max"]), 3)
	assert_eq(int(gates["threshold"]), 7, "20 wall HP shared by three gates")
	assert_false(SiegeGates.breached(gates))
	assert_eq(SiegeGates.batter(gates, 6), 0, "six casualties do not open a gate")
	assert_eq(SiegeGates.batter(gates, 1), 1, "the seventh does")
	assert_true(SiegeGates.breached(gates))
	assert_almost_eq(SiegeGates.breach_share(gates), 1.0 / 3.0, 0.001)
	assert_eq(SiegeGates.batter(gates, 20), 2, "the rest fall in one blow")
	assert_eq(int(gates["broken"]), 3, "three gates and no more")
	assert_eq(SiegeGates.batter(gates, 20), 0)
	assert_true(SiegeGates.gates_for(0).is_empty(), "no fort, no gates")
	assert_eq(SiegeGates.breach_threshold(0), 0)
	assert_eq(SiegeGates.batter({}, 4), 0, "a field battle has no gate state")


func test_a_breach_sheds_the_wall_and_opens_the_behind_lane() -> void:
	var sheltered: Dictionary = _breach_strike(0)
	assert_true((sheltered["wall"] as Array).size() > 0, "the wall takes the shot")
	assert_eq(int(sheltered["gates_broken"]), 0, "one blow is not a breach")

	var opened: Dictionary = _breach_strike(1)
	assert_true(
		(opened["wall"] as Array).size() > (sheltered["wall"] as Array).size(),
		"a gate down, the wall no longer spares the garrison"
	)
	assert_true(
		(opened["behind"] as Array).size() > (sheltered["behind"] as Array).size(),
		"the attackers pour through the gate into the behind lane"
	)


## A fresh defender each time: the same blow against a whole wall and against a
## wall already breached through one gate.
func _breach_strike(broken: int) -> Dictionary:
	var attacker: Array[ArmyState] = _side(["musketeers", "musketeers", "musketeers", "culverin"], 2)
	var types: Array[String] = _repeat("peasant_levies", 8)
	types.append_array(_repeat("squires", 2))
	types.append_array(_repeat("culverin", 2))
	var defender: Array[ArmyState] = _side(types, 1)
	var armies: Array[ArmyState] = _joined(attacker, defender)
	var gates: Dictionary = SiegeGates.gates_for(2)
	gates["broken"] = broken
	return SiegeLanes.strike(armies, attacker, defender, 12, 20, 2, false, gates)


## A line with no fight left in it delivers no blow, so it has nothing to spend
## on the fort's battery — a spent besieger cannot grind a gun down (wiki:
## siege-mechanics § Quick Battle lanes — "the guns take the blow", and only
## what a blow delivers can reach them; DR-20261110-22 buys gun loss with the
## besieging train's weight, never with an empty blow).
func test_a_spent_line_cannot_grind_down_the_battery() -> void:
	var attacker: Array[ArmyState] = _side(_repeat("musketeers", 4), 2)
	var defender: Array[ArmyState] = _side(_repeat("pikemen", 4), 1)
	var state: Dictionary = _state(attacker, defender, "open")
	state["defender"]["mods"] = {"fort": 2}
	state["attacker"]["cohesion"] = 0
	var armies: Array[ArmyState] = state["armies"]
	var guns: Array[Dictionary] = QuickBattleBattery.make(2, {}, 1)

	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)

	assert_eq(int(entry["battery_hit"]), 0, "no blow, nothing for the guns to soak")
	assert_eq(int(entry["guns_destroyed"]), 0, "a spent line cannot silence a gun")
	assert_almost_eq(
		QuickBattleBattery.total_hp(guns), 4.0, 0.001, "the battery is untouched"
	)
	## The other side of the line: a line with fight left in it still pays the
	## guns first, so the fix does not stop a real besieger from silencing them.
	var fresh: Array[Dictionary] = QuickBattleBattery.make(2, {}, 1)
	state["attacker"]["cohesion"] = 3
	var spent: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", fresh
	)
	assert_true(int(spent["battery_hit"]) > 0, "a real blow is spent on the battery")


func test_a_quick_battle_reports_its_ground_and_gates() -> void:
	var battle: Dictionary = _siege_fight(
		"balanced", _repeat("guards", 20), _repeat("musketeers", 10), 1, "hill"
	)
	var quick: Dictionary = battle["quick"]
	assert_eq(String(quick["terrain"]), "hill")
	assert_eq(String(quick["terrain_label"]), "Hillside")
	assert_eq(int((quick["gates"] as Dictionary)["max"]), 3)
	assert_true(int((quick["gates"] as Dictionary)["damage"]) > 0, "the wall was beaten")
	assert_eq(int((quick["limits"] as Dictionary)["attacker"]), 10)
	assert_eq(String(battle["battle_mode"]), "siege")


func test_a_garrison_without_firearms_sallies_on_its_own() -> void:
	var battle: Dictionary = _siege_fight(
		"balanced", _repeat("guards", 8), _repeat("pikemen", 6), 2, "town"
	)
	assert_true(int(battle["quick"]["sorties"]) > 0, "a pike garrison must sally to fight")
	assert_eq(String(battle["quick"]["defender_plan"]), "aggressive")


func test_the_sortie_is_a_dedicated_order() -> void:
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, true),
		["entrench", "sortie"], "a sally, not an assault on its own wall"
	)
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, false),
		["entrench", "volley", "volley"], "no wall, no gate to sally from"
	)
	assert_eq(QuickBattleActions.actions_for("aggressive"), ["maneuver", "assault"])
	assert_eq(int(QuickBattleActions.ACTION_CP["sortie"]), 2)
	assert_eq(String(QuickBattleActions.ACTION_LABEL["sortie"]), "Sortie")


## A sally is only a sally for a garrison behind its wall: with no wall to leave,
## or named by an attacker, it resolves as ordinary volley fire (wiki:
## quick-battle § Core actions).
func test_a_sortie_without_a_wall_resolves_as_volley() -> void:
	var defender: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 1)
	var attacker: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 2)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)

	var field: Dictionary = _lane_state(attacker, defender, 0)
	var defender_sally: Dictionary = QuickBattleActions.resolve(
		armies, field, "defender", "attacker", "sortie", []
	)
	assert_eq(String(defender_sally["action"]), "volley", "no wall, no sortie")

	var walled: Dictionary = _lane_state(attacker, defender, 1)
	walled["gates"] = SiegeGates.gates_for(1)
	walled["defender"]["lanes"] = SiegeLanes.line_ids(defender, 10)
	var attacker_sally: Dictionary = QuickBattleActions.resolve(
		armies, walled, "attacker", "defender", "sortie", []
	)
	assert_eq(String(attacker_sally["action"]), "volley", "an attacker cannot sally")


func test_an_assault_into_town_is_weaker() -> void:
	var open_losses: int = _assault_losses("open")
	var town_losses: int = _assault_losses("town")
	assert_true(town_losses < open_losses, "streets and rooftops blunt a charge")


func test_entrenching_is_surer_in_cover() -> void:
	var open_guard: float = _entrench_guard("open")
	var town_guard: float = _entrench_guard("town")
	assert_almost_eq(open_guard, 0.45, 0.001)
	assert_almost_eq(town_guard, 0.63, 0.001)
	assert_true(town_guard > open_guard)


func test_a_sortie_in_the_open_costs_the_garrison_dear() -> void:
	## Enough pike that a quality assault leaves men to pay the sally's own cost
	## (main's FPN/FPM blow no longer treats a thin garrison as a head count).
	var battle: Dictionary = _siege_fight(
		"aggressive", _repeat("guards", 8), _repeat("pikemen", 16), 1, "town"
	)
	var sortie: Dictionary = {}
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if bool(action["sortie"]):
				sortie = action
	assert_true(not sortie.is_empty(), "the plate records the sally")
	assert_true(int(sortie["defender_lost"]) > 0, "the sally costs its own men")
	assert_eq(String(sortie["label"]), "Sortie")


# --- fixtures ----------------------------------------------------------------


func _siege_fight(
	plan: String, attacker: Array[String], defender: Array[String], fort: int,
	terrain: String
) -> Dictionary:
	var model := Fixture.build()
	model.province_data(2).fort_level = fort
	_set_ground(model, 2, _ground(terrain))
	var defender_army := Fixture.army(1, 1, 2, defender, true)
	var attacker_army := Fixture.army(2, 0, 2, attacker)
	attacker_army.moved = true
	var armies: Array[ArmyState] = [defender_army, attacker_army]
	var context: Dictionary = {
		"quick_battle": true, "player_faction": 0,
		"battle_plan": plan, "seed": 11, "terrain_override": terrain,
	}
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	return reports[0]


func _assault_losses(terrain: String, count: int = 6) -> int:
	## Peer-quality lines so the blow stays in the terrain band instead of
	## wiping both open and town (quality weight from main's Quick Battle).
	var attacker: Array[ArmyState] = _side(_repeat("pikemen", count), 2)
	var defender: Array[ArmyState] = _side(_repeat("pikemen", count), 1)
	var armies: Array[ArmyState] = _joined(attacker, defender)
	var state: Dictionary = _state(attacker, defender, terrain)
	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "assault", [] as Array[Dictionary]
	)
	return int(entry["defender_lost"])


func _entrench_guard(terrain: String) -> float:
	var attacker: Array[ArmyState] = _side(_repeat("guards", 4), 2)
	var defender: Array[ArmyState] = _side(_repeat("pikemen", 4), 1)
	var state: Dictionary = _state(attacker, defender, terrain)
	var armies: Array[ArmyState] = state["armies"]
	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "defender", "attacker", "entrench", [] as Array[Dictionary]
	)
	return float(entry["guard"])


func _state(
	attacker: Array[ArmyState], defender: Array[ArmyState], terrain: String
) -> Dictionary:
	var state: Dictionary = {
		"attacker": {
			"side": attacker, "owner": 2, "limit": 10, "mods": {},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "balanced", "exposed": false,
		},
		"defender": {
			"side": defender, "owner": 1, "limit": 10, "mods": {"fort": 0},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "defensive", "exposed": false,
		},
		"terrain": terrain,
		"gates": {},
	}
	## One list so the resolver can find both sides' regiments by instance id.
	state["armies"] = _joined(attacker, defender)
	return state


func _side(types: Array[String], owner: int) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(Fixture.army(10 + owner, owner, 2, types, true))
	return side


func _joined(first: Array[ArmyState], second: Array[ArmyState]) -> Array[ArmyState]:
	var all: Array[ArmyState] = []
	all.append_array(first)
	all.append_array(second)
	return all


func _set_ground(model: MapModel, province: int, terrain: int) -> void:
	var data: ProvinceState = model.province_data(province)
	for tile: Vector2i in data.tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = terrain


func _ground(terrain: String) -> int:
	match terrain:
		"hill":
			return MapModel.Terrain.HILLS
		"woods":
			return MapModel.Terrain.HARDWOOD_FOREST
		"marsh":
			return MapModel.Terrain.SWAMP
	return MapModel.Terrain.PLAINS


func _repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types


# --- from test_battle_sim.gd ---
## The Battle Simulator's rules glue (`BattleScenario`) and its scene. The
## sandbox must run the live Quick Battle resolver, not a parallel model
## (REQ-P2-03); the screen must paint the record it gets back.


func test_the_scenario_builds_the_requested_battle() -> void:
	var spec: Dictionary = {
		"attacker": ["musketeers", "musketeers", "musketeers", "culverin"],
		"defender": ["pikemen", "pikemen", "musketeers", "culverin"],
		"fort": 2, "terrain": "woods", "seed": 3,
	}
	var result: Dictionary = BattleScenario.fight(spec)
	var report: Dictionary = result["report"]
	var quick: Dictionary = report["quick"]

	assert_eq(int(report["fort_level"]), 2)
	assert_eq(String(report["battle_mode"]), "siege")
	assert_eq(String(quick["terrain"]), "woods")
	assert_eq(String(quick["terrain_label"]), "Woods")
	assert_eq(int(quick["guns_start"]), 2, "a stone fort fields two emplaced guns")
	assert_eq(int(quick["lanes"]["wall"]), 3)
	assert_eq(int(quick["lanes"]["behind"]), 1)
	assert_eq(int((quick["gates"] as Dictionary)["max"]), 3)
	assert_eq(int(quick["attacker_start"]), 4)
	assert_eq(int(quick["defender_start"]), 4)


func test_the_scenario_runs_the_live_resolver() -> void:
	var spec: Dictionary = {
		"attacker": ["guards", "guards", "guards", "guards", "culverin"],
		"defender": ["pikemen", "pikemen", "musketeers"], "fort": 1, "terrain": "town",
		"attacker_plan": "aggressive", "defender_plan": "balanced", "seed": 11,
	}
	var first: Dictionary = BattleScenario.fight(spec)
	var scene: Dictionary = BattleScenario.build(spec)
	var direct: Dictionary = QuickBattle.resolve_exchange(
		scene["model"], scene["armies"], scene["province"], scene["defender"],
		scene["attacker"], false, scene["context"]
	)
	var sandbox: Dictionary = first["report"]

	assert_eq(int(sandbox["outcome"]), int(direct["outcome"]))
	assert_eq(
		(sandbox["defender_lost"] as Array).size(),
		(direct["defender_lost"] as Array).size()
	)
	assert_eq(
		(sandbox["attacker_lost"] as Array).size(),
		(direct["attacker_lost"] as Array).size()
	)
	assert_eq(String(sandbox["quick"]["defender_plan"]), "balanced")


func test_the_scenario_normalises_unknown_types() -> void:
	var scene: Dictionary = BattleScenario.build({
		"attacker": ["not_a_regiment"], "defender": ["pikemen"], "terrain": "open",
	})
	var armies: Array[ArmyState] = scene["armies"]
	assert_eq(armies[1].count(), 1)
	assert_eq(armies[1].type_of(armies[1].regiments[0]), RegimentCatalog.DEFAULT_TYPE)


func test_a_field_scenario_has_no_wall() -> void:
	var result: Dictionary = BattleScenario.fight({
		"attacker": ["musketeers", "musketeers"], "defender": ["pikemen", "pikemen"],
		"fort": 0, "terrain": "hill",
	})
	var quick: Dictionary = result["report"]["quick"]
	assert_eq(String(result["report"]["battle_mode"]), "field")
	assert_true((quick["gates"] as Dictionary).is_empty(), "no fort, no gates")
	assert_eq(String(quick["terrain"]), "hill")


## The published marsh id is the ground the sandbox paints (wiki: quick-battle
## § Terrain): a swamp province fights on marsh, and BattleScenario must map
## that id onto MapModel.Terrain.SWAMP — not leave the match arm dead.
func test_the_marsh_scenario_paints_swamp_ground() -> void:
	var scene: Dictionary = BattleScenario.build({
		"attacker": ["musketeers"], "defender": ["pikemen"], "terrain": "marsh",
	})
	var model: MapModel = scene["model"]
	assert_eq(model.terrain[model.index_of(2, 1)], MapModel.Terrain.SWAMP)
	assert_eq(String(scene["context"]["terrain_override"]), "marsh")


func test_every_ground_paints() -> void:
	var field := QuickBattleField.new()
	field.custom_minimum_size = Vector2(480, 320)
	field.size = Vector2(480, 320)
	add_child(field)
	for terrain: String in ["open", "hill", "woods", "town", "marsh"]:
		field.terrain = terrain
		field.fort_level = 3 if terrain == "town" else 0
		field.gates_broken = 2
		field.attacker_count = 4
		field.defender_count = 4
		field.attacker_health = []
		field.defender_health = []
		field.queue_redraw()
		await get_tree().process_frame
	assert_eq(field.terrain, "marsh")
	field.free()


## A painted plate is only as good as the asset behind it: a moved or renamed
## texture must fail here, not on a playtester's screen.
func test_the_painted_plate_assets_exist() -> void:
	for terrain: String in BattlePlate.PLATES.keys():
		var entry: Dictionary = BattlePlate.PLATES[terrain]
		assert_true(
			ResourceLoader.exists(String(entry["path"])),
			"missing plate for %s" % terrain
		)
	for fort in [1, 2, 3]:
		assert_true(
			ResourceLoader.exists(BattlePlate.WALLS[fort]), "missing wall %d" % fort
		)
	for path: String in [
		BattlePlate.SOLDIER, BattlePlate.CANNON, BattlePlate.HORSE, BattlePlate.RUBBLE,
	]:
		assert_true(ResourceLoader.exists(path), "missing %s" % path)


## The wall must read as a fortification: taller than a man, with the garrison
## standing on the parapet above the field line.
func test_the_wall_towers_over_the_garrison() -> void:
	for fort in [1, 2, 3]:
		var wall: float = BattlePlate.wall_height(600.0, fort)
		assert_true(wall > BattlePlate.soldier_height(600.0) * 1.5, "wall too low")
		assert_true(BattlePlate.parapet_y(600.0, fort) < 600.0 * BattlePlate.GROUND)
	assert_true(
		BattlePlate.wall_height(600.0, 3) > BattlePlate.wall_height(600.0, 1),
		"a later fort stands taller"
	)


func test_the_simulator_scene_fights_and_steps() -> void:
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame

	screen._fight()
	assert_false(screen._result.is_empty(), "Fight resolves the current setup")
	assert_true(screen._log.text.contains("ROUND"), "the despatch is printed")
	assert_true(screen._log.text.contains("OUTCOME"))
	assert_true(screen._field.fort_level >= 0)

	screen._step()
	assert_true(screen._status.text.contains("Round") or screen._status.text.contains("No rounds"))
	screen._reset()
	assert_true(screen._result.is_empty())
	assert_eq(screen._field.attacker_count, 0)

	screen.free()


## The Sandbox paints the wings its record carries: each round the plate shows
## what that round left standing, and the aftermath shows the wings the battle
## left — not the deal it opened with (wiki: quick-battle § Wings and collapse).
func test_the_simulator_plate_walks_the_wings_it_records() -> void:
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame
	_sim_slots(screen._setup, "attacker", [["guards", 6], ["culverin", 0], ["knights", 2]])
	_sim_slots(screen._setup, "defender", [["pikemen", 6], ["musketeers", 0], ["knights", 2]])
	screen._setup._fort.selected = 0
	screen._setup._attacker_plan.selected = 1
	screen._fight()
	var quick: Dictionary = screen._result["report"]["quick"]
	var broke: bool = false
	for index in (quick["rounds"] as Array).size():
		screen._show_round(index)
		var round: Dictionary = quick["rounds"][index]
		assert_eq(
			str(screen._field.attacker_wings), str(round["wings"]["attacker"]),
			"round %d paints the wings it left" % (index + 1)
		)
		assert_eq(str(screen._field.defender_wings), str(round["wings"]["defender"]))
		assert_eq(
			str(screen._field.defender_broken), str(round["wings_broken"]["defender"]),
			"a wing that broke this round is struck through"
		)
		if not (round["wings_broken"]["defender"] as Array).is_empty():
			broke = true
	assert_true(broke, "the sandbox fight breaks a wing, or the plate is untested")
	screen._show_aftermath()
	assert_eq(
		str(screen._field.attacker_wings), str(quick["wings"]["attacker"]),
		"the aftermath shows the wings the battle left"
	)
	assert_eq(str(screen._field.defender_broken), str(quick["wings_broken"]["defender"]))
	assert_true(
		screen._log.text.contains("Wings — "), "the despatch says the collapse in words"
	)
	screen.free()


## The sandbox fights the army the rail shows: an emptied side is refused by
## name, never replaced by a default army the playtester never set (REQ-P2-03).
func test_the_sandbox_fights_the_army_the_rail_shows() -> void:
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame
	_sim_slots(screen._setup, "attacker", [["musketeers", 0], ["culverin", 0], ["knights", 0]])
	assert_true(
		(screen._setup.spec()["attacker"] as Array).is_empty(),
		"an emptied rail fields no men"
	)
	screen._fight()
	assert_true(screen._result.is_empty(), "a refused Fight resolves no battle")
	assert_true(
		screen._status.text.begins_with("The Attack fields no men"),
		"the refusal names the empty side: %s" % screen._status.text
	)
	assert_true(screen._log.text.is_empty(), "a refused Fight writes no despatch")
	screen._step()
	assert_true(screen._result.is_empty(), "Next round cannot resolve a refused setup")
	_sim_slots(screen._setup, "attacker", [["musketeers", 4], ["culverin", 0], ["knights", 0]])
	_sim_slots(screen._setup, "defender", [["pikemen", 0], ["musketeers", 0], ["culverin", 0]])
	screen._fight()
	assert_true(
		screen._status.text.begins_with("The Garrison fields no men"),
		"the garrison's emptiness is named too"
	)
	screen.free()


## The step walk ends where the battle ends: Next round reaches every round the
## record holds, then the aftermath, and only then starts the plate over. A
## round the battle never fought has no door.
func test_the_sandbox_walks_into_its_aftermath() -> void:
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame
	_sim_slots(screen._setup, "attacker", [["musketeers", 6], ["culverin", 1], ["knights", 0]])
	_sim_slots(screen._setup, "defender", [["pikemen", 4], ["musketeers", 2], ["culverin", 0]])
	screen._setup._fort.selected = 2
	screen._fight()
	var rounds: Array = screen._rounds()
	assert_true(rounds.size() > 0, "Fight resolves a round")
	for index in rounds.size():
		screen._step()
		assert_eq(screen._field.round_index, index, "step %d shows round %d" % [index, index + 1])
	screen._step()
	assert_eq(
		screen._field.round_index, rounds.size() - 1,
		"the step after the last round is the aftermath"
	)
	assert_false(screen._status.text.begins_with("Round "), "the aftermath is not a round")
	screen._step()
	assert_eq(screen._field.round_index, 0, "stepping past the aftermath starts the plate over")
	for index in QuickBattleTerms.MAX_ROUNDS:
		var door: Button = screen._round_buttons.get_child(index) as Button
		assert_eq(
			door.disabled, index >= rounds.size(),
			"round %d's door follows the rounds fought" % (index + 1)
		)
	screen.free()


## The sandbox prints the sheet the game's plate prints: the line and the men
## who waited behind it, and the honours and citations the colours won — a
## sandbox that reads fewer lines than the game hides its subject (REQ-P5-05).
func test_the_sandbox_prints_the_games_aftermath() -> void:
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame
	_sim_slots(screen._setup, "attacker", [["musketeers", 20], ["culverin", 20], ["knights", 20]])
	_sim_slots(screen._setup, "defender", [["pikemen", 4], ["musketeers", 3], ["culverin", 1]])
	screen._setup._attacker_plan.selected = 1
	screen._setup._terrain.selected = 1
	screen._fight()
	var report: Dictionary = screen._result["report"]
	var deployed: int = int(report.get("attacker_deployed", 0))
	var reserve: int = int(report.get("attacker_reserve", 0))
	assert_true(reserve > 0, "the rail seats an army larger than the line")
	assert_true(
		screen._log.text.contains("Line — The Attack: %d of %d in the line" % [deployed, deployed + reserve]),
		"the despatch names the men who waited behind the line"
	)
	assert_true(screen._log.text.contains("Ground — "), "broken ground is named")
	if int(report.get("attacker_honours", 0)) > 0:
		assert_true(screen._log.text.contains("Honours — "), "the colours' honours are printed")
	if int(report.get("attacker_citations", 0)) > 0:
		assert_true(screen._log.text.contains("Citations — "), "the colours' citations are printed")
	for round: Dictionary in screen._rounds():
		for action: Dictionary in round.get("actions", []) as Array:
			assert_true(
				screen._log.text.contains(
					QuickBattleCopy.action_line(action, report, BattleSimScreen.NAMES)
				),
				"every resolved action reaches the despatch"
			)
	screen.free()


## The rail offers only levers the resolver reads (wiki: combat § Strength;
## siege-mechanics § Emplaced Artillery): a side's chevrons reach the exchange as
## its commander's rank — the deployment limit counts them — and the picked gun
## line is the battery `QuickBattleBattery` spawns. A rail that offered a number
## the fight never read would teach a playtester a rule the game does not have.
func test_the_sandbox_rail_carries_medals_and_the_battery_line() -> void:
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame
	_sim_slots(screen._setup, "attacker", [["musketeers", 6], ["culverin", 1], ["knights", 0]])
	_sim_slots(screen._setup, "defender", [["pikemen", 4], ["musketeers", 2], ["culverin", 0]])
	screen._setup._fort.selected = 2
	screen._setup._guns.selected = 2
	screen._setup._attacker_medals.value = 3
	screen._setup._defender_medals.value = 2
	var spec: Dictionary = screen._setup.spec()

	assert_eq(int(spec["attacker_medals"]), 3)
	assert_eq(int(spec["defender_medals"]), 2)
	assert_true(
		bool((spec["tech"] as Dictionary).get("emplaced_siege_guns", false)),
		"the siege line carries its own study"
	)
	assert_true(
		bool((spec["tech"] as Dictionary).get("heavy_emplaced_artillery", false)),
		"a siege battery is built on the heavy line the table names"
	)
	screen._fight()
	var quick: Dictionary = screen._result["report"]["quick"]
	assert_eq(
		String(quick["gun_type"]), "siege_guns",
		"the rail's line is the battery the resolver spawns"
	)
	assert_eq(
		int(quick["limits"]["attacker"]), ArmyModifiers.BASE_DEPLOYMENT + 3,
		"the attacker's chevrons move its deployment limit"
	)
	assert_eq(
		int(quick["limits"]["defender"]), ArmyModifiers.BASE_DEPLOYMENT + 2,
		"the defender's chevrons move its own"
	)
	assert_true(
		screen._readout.text.contains("defender medals 2"),
		"the readout reads the levers back: %s" % screen._readout.text
	)
	screen.free()


## A quick battle with one attacker is deterministic for a fixed plan: the seed
## only breaks an initiative tie between rival attackers (wiki: combat
## § Initiative), so this sandbox carries no seed on its rail and two seeds fight
## the same record. A dial that never moved a fight taught a playtester otherwise.
func test_the_sandbox_has_no_seed_that_cannot_move_a_fight() -> void:
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame
	assert_false(
		screen._setup.spec().has("seed"), "the rail offers no seed a lone attacker cannot feel"
	)
	screen.free()
	var spec: Dictionary = {
		"attacker": ["musketeers", "musketeers", "musketeers", "culverin"],
		"defender": ["pikemen", "pikemen", "musketeers", "culverin"],
		"fort": 2, "terrain": "woods",
	}
	var first: Dictionary = BattleScenario.fight(spec)
	spec["seed"] = 4242
	var second: Dictionary = BattleScenario.fight(spec)
	assert_eq(
		str(first["report"]["attacker_lost"]), str(second["report"]["attacker_lost"]),
		"a second seed breaks the same men"
	)
	assert_eq(
		int(first["report"]["quick"]["guns_left"]),
		int(second["report"]["quick"]["guns_left"]),
		"and leaves the same battery"
	)


## Fills the sandbox's setup rail: one [type, count] per slot.
func _sim_slots(setup: BattleSimSetup, side: String, rows: Array) -> void:
	var slots: Array = setup._attacker_slots if side == "attacker" else setup._defender_slots
	for index in mini(rows.size(), slots.size()):
		var row: Array = rows[index]
		(slots[index]["picker"] as OptionButton).selected = maxi(
			setup._types.find(String(row[0])), 0
		)
		(slots[index]["count"] as SpinBox).value = int(row[1])


## A line that has lost every wing keeps its chips on the plate — struck
## through, which is the collapse they exist to show — while a line with no
## wings at all (a garrison behind a wall) draws none (wiki: quick-battle
## § Wings and collapse).
func test_a_line_that_lost_every_wing_still_shows_its_chips() -> void:
	assert_true(
		QuickBattleField.wings_shown({"left": 0, "center": 0, "right": 0}, ["left", "center", "right"]),
		"a broken line is still read on the plate"
	)
	assert_true(QuickBattleField.wings_shown({"left": 0, "center": 3, "right": 0}, []))
	assert_false(
		QuickBattleField.wings_shown({"left": 0, "center": 0, "right": 0}, []),
		"a garrison holds no wings, so it draws no chips"
	)


## The chips are the plate's smallest furniture: on a short plate (a handset's)
## they grow so three still read, and a tall plate keeps the published size
## (REQ-P1-07).
func test_the_wing_chips_grow_on_a_short_plate() -> void:
	assert_eq(QuickBattleField.chip_scale(400.0), 1.0, "a tall plate is unchanged")
	assert_eq(QuickBattleField.chip_scale(300.0), 1.0)
	assert_true(QuickBattleField.chip_scale(160.0) > 1.0, "a handset plate grows its chips")
	assert_eq(
		QuickBattleField.chip_scale(40.0), QuickBattleField.CHIP_SCALE_MAX,
		"the growth is capped so the chips never swamp the line"
	)


## The plate is a soft overlay the court must be able to leave: on a landscape
## handset the painted field gives way so the Skip and Continue doors stay on
## the screen (REQ-P1-07, REQ-P5-06).
func test_the_battle_plate_fits_a_landscape_handset() -> void:
	var report: Dictionary = BattleScenario.fight({
		"attacker": ["musketeers", "musketeers", "culverin", "knights"],
		"defender": ["pikemen", "pikemen", "musketeers", "culverin"],
		"fort": 2, "terrain": "open", "attacker_plan": "balanced",
		"defender_plan": "defensive", "seed": 11,
	})["report"]
	for size: Vector2i in [Vector2i(800, 360), Vector2i(914, 411)]:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var overlay := QuickBattleOverlay.new()
		viewport.add_child(overlay)
		await get_tree().process_frame
		await get_tree().process_frame
		overlay.show_battle(report, "Cadiz", ["Spain", "England"])
		await get_tree().process_frame
		var panel: Control = overlay._panel
		assert_true(
			panel.get_global_rect().end.y <= float(size.y),
			"the plate runs off a %s screen" % str(size)
		)
		var cont: Control = overlay._continue
		assert_true(
			cont.get_global_rect().end.y <= float(size.y),
			"the Continue door is off a %s screen" % str(size)
		)
		assert_true(
			overlay.field.custom_minimum_size.y >= BattlePlateFrame.BODY_MIN,
			"the field keeps a readable floor"
		)
		overlay.free()
		viewport.free()


## The instrument is a phone-and-tablet tool too: below three columns it stacks
## the rail, the plate and the despatches into one scrolling column, so nothing
## is clipped off a handset (REQ-P1-05, REQ-P5-07).
func test_the_simulator_stacks_on_a_handset() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 640)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	viewport.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(screen._stacked, "a handset stacks the instrument")
	assert_true(screen._row is ScrollContainer, "the stacked column scrolls")
	var width: float = 360.0
	for panel: Control in [screen._setup, screen._field, screen._log_panel]:
		assert_true(
			panel.get_global_rect().end.x <= width,
			"a panel runs off the handset: %s" % str(panel.get_global_rect())
		)
	assert_true(
		screen._setup.get_global_rect().end.y <= screen._field.get_global_rect().position.y,
		"the rail stands above the plate"
	)
	assert_true(
		screen._field.get_global_rect().end.y <= screen._log_panel.get_global_rect().position.y,
		"the despatches stand below the plate"
	)
	screen._fight()
	assert_false(screen._result.is_empty(), "the stacked instrument still fights")
	screen.free()
	viewport.free()


## A desktop keeps the three columns it always had.
func test_the_simulator_keeps_three_columns_on_a_desktop() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	viewport.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(screen._stacked, "a desktop keeps its columns")
	assert_true(screen._row is HBoxContainer)
	assert_eq(screen._setup.custom_minimum_size.x, 320.0)
	assert_eq(screen._log_panel.custom_minimum_size.x, 380.0)
	screen.free()
	viewport.free()

# --- naming, order of battle and settlement ---

## One boot for naming, order-of-battle readings and battle settlement (wiki: naming;
## fog-and-exploration § Order Visibility; combat § Outcomes). Merged from
## test_name_roster, test_general_names, test_oob_readings and test_battle_settlement so
## coverage pays one instrumentation pass.

const POOL: Array[String] = ["Revenge", "Sovereign", "Vanguard"]


func test_a_pick_comes_from_the_pool_and_never_repeats() -> void:
	var taken: Array[String] = []
	for step in POOL.size():
		var name: String = NameRoster.pick(POOL, "%d" % step, taken, "Unnamed")
		assert_true(POOL.has(name), "step %d picked '%s' from its pool" % [step, name])
		assert_false(taken.has(name), "'%s' is worn twice" % name)
		taken.append(name)


func test_the_same_key_always_christens_the_same_name() -> void:
	var first: String = NameRoster.pick(POOL, "0:0:ship_1", [], "Unnamed")
	var second: String = NameRoster.pick(POOL, "0:0:ship_1", [], "Unnamed")

	assert_eq(first, second, "a reload draws the same title")
	assert_false(NameRoster.pick(POOL, "0:0:ship_2", [], "Unnamed").is_empty())


func test_a_spent_pool_numbers_its_repeats() -> void:
	var taken: Array[String] = POOL.duplicate()
	var numbered: String = NameRoster.pick(POOL, "0:0:ship_1", taken, "Unnamed")

	assert_true(numbered.ends_with(" II"), "the fourth hull is numbered, got '%s'" % numbered)
	assert_false(taken.has(numbered), "the numbered pick is still free")


func test_a_pool_past_its_last_ordinal_repeats_its_last_title() -> void:
	var taken: Array[String] = POOL.duplicate()
	for _cycle in NameRoster.ORDINALS.size():
		var name: String = NameRoster.pick(POOL, "0:0:ship_1", taken, "Unnamed")
		if not taken.has(name):
			taken.append(name)
	var last: String = NameRoster.pick(POOL, "0:0:ship_1", taken, "Unnamed")

	assert_true(taken.has(last), "an exhausted numbering falls back to a taken title")
	assert_true(last.ends_with(" VIII"), "the last ordinal is the ceiling, got '%s'" % last)


func test_an_empty_pool_falls_back_to_the_callers_word() -> void:
	var empty: Array[String] = []

	assert_eq(NameRoster.pick(empty, "0:0:ship_1", [], "Unnamed"), "Unnamed")
	assert_eq(NameRoster.pick(empty, "0:general_1", [], "Commander"), "Commander")


func test_a_crown_with_no_pool_reads_the_generic_one() -> void:
	var pools: Dictionary = {0: ["Revenge"]}
	var generic: Array[String] = ["Providence"]

	assert_eq(NameRoster.pool_of(pools, generic, 0), ["Revenge"])
	assert_eq(NameRoster.pool_of(pools, generic, 9), generic, "an unknown crown is generic")


func test_taken_names_reads_the_store_and_skips_the_new_instance() -> void:
	var store: Dictionary = {"ship_1": "Revenge", "ship_2": "", "ship_3": "Vanguard"}

	assert_eq(
		NameRoster.taken_names(["ship_1", "ship_2", "ship_3"], store, "ship_1"),
		["Vanguard"],
		"the hull being christened and the unnamed one are left out"
	)
	assert_eq(NameRoster.taken_names([], {}, ""), [], "an empty roster names nothing")


func test_a_saved_title_map_reads_json_keys_as_strings() -> void:
	assert_eq(
		NameRoster.map_from({"1": "Revenge"}),
		{"1": "Revenge"},
		"a string-keyed map survives"
	)
	assert_eq(
		NameRoster.map_from({1: "Vanguard"}),
		{"1": "Vanguard"},
		"a numeric key is read back as the string a save writes"
	)
	assert_eq(NameRoster.map_from([1, 2]), {}, "a malformed map reads empty")
	assert_eq(NameRoster.map_from(null), {}, "a missing map reads empty")


## A JSON round-trip turns every count into a float; the reader casts it back, so
## a restored regiment's condition and record compare equal to what was saved.
func test_a_saved_number_map_reads_json_values_as_ints() -> void:
	var json: String = JSON.stringify({"unit_1": 3, "unit_2": 0})
	var raw: Variant = JSON.parse_string(json)

	assert_eq(
		NameRoster.numbers_from(raw),
		{"unit_1": 3, "unit_2": 0},
		"counts survive a JSON round-trip as ints"
	)
	assert_eq(NameRoster.numbers_from({1: "2"}), {"1": 2}, "a numeric key and a text value")
	assert_eq(NameRoster.numbers_from("nonsense"), {}, "malformed reads empty")
	assert_eq(NameRoster.numbers_from(null), {}, "a missing map reads empty")


func test_the_digest_is_the_fn_1a_save_contract() -> void:
	assert_eq(NameRoster.stable_hash("0:0:ship_1"), 3815455475)
	assert_eq(NameRoster.stable_hash("0:general_1"), 2632187469)
	assert_eq(NameRoster.stable_hash("0:1:unit_101"), 1682817625)
	assert_false(
		NameRoster.stable_hash("0:0:ship_1") == NameRoster.stable_hash("0:0:ship_2"),
		"a different instance draws a different start"
	)


func test_every_roster_numbers_repeats_the_same_way() -> void:
	var hulls: Array[String] = ShipNames.pool_for(0).duplicate()
	var regiments: Array[String] = RegimentNames.pool_for(0).duplicate()
	var generals: Array[String] = GeneralNames.pool_for(0).duplicate()

	assert_true(ShipNames.mint(0, 0, "ship_1", hulls).ends_with(" II"))
	assert_true(RegimentNames.mint(0, 0, "unit_1", regiments).ends_with(" II"))
	assert_true(GeneralNames.mint(0, "general_1", generals).ends_with(" II"))
# --- test_general_names ---

## Every commander bears a name (wiki: naming § General names;
## DR-20261112-03): a crown christens its generals from its own period pool, no
## two of them share a name, a saved roster keeps its names, an old save is
## christened on load by the same arithmetic, and the dossier names each general
## with the medals he carries.

const SPAIN: int = 0
const UNKNOWN: int = 9
const CivilianFixture = preload("res://tests/civilian_fixture.gd")


func test_a_new_roster_names_its_generals_from_the_crown_pool() -> void:
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {})

	for general_id: String in roster.ids(SPAIN):
		var christened: String = roster.name_of(SPAIN, general_id)
		assert_false(christened.is_empty(), "a general is never anonymous")
		assert_true(
			GeneralNames.pool_for(SPAIN).has(christened),
			"Spain christens from its own pool, got '%s'" % christened
		)


func test_a_crown_with_no_pool_still_names_its_generals() -> void:
	var roster := GeneralRoster.new()
	roster.sync(UNKNOWN, {})

	assert_true(GeneralNames.GENERIC.has(roster.name_of(UNKNOWN, "general_1")))


func test_no_crown_wears_the_same_name_twice() -> void:
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {"nationalism": true})
	assert_eq(roster.count(SPAIN), 4, "the cap raises the pool to four")

	var borne: Array[String] = []
	for general_id: String in roster.ids(SPAIN):
		var christened: String = roster.name_of(SPAIN, general_id)
		assert_false(borne.has(christened), "'%s' is worn twice" % christened)
		borne.append(christened)


func test_the_same_crown_and_id_always_christen_the_same_name() -> void:
	var first := GeneralRoster.new()
	first.sync(SPAIN, {"nationalism": true})
	var second := GeneralRoster.new()
	second.sync(SPAIN, {"nationalism": true})

	assert_eq(first.names(SPAIN), second.names(SPAIN), "seeded, not drawn")


func test_a_full_pool_numbers_its_repeats() -> void:
	var taken: Array[String] = GeneralNames.pool_for(SPAIN).duplicate()
	var numbered: String = GeneralNames.mint(SPAIN, "general_1", taken)

	assert_true(numbered.ends_with(" II"), "an eleventh commander is numbered, got '%s'" % numbered)
	assert_false(taken.has(numbered), "the numbered pick is still free")


func test_a_saved_roster_keeps_its_names() -> void:
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {"organised_regiments": true})
	roster.award(SPAIN, "general_2")

	var restored: GeneralRoster = GeneralRoster.from_dict(roster.to_dict())

	assert_eq(restored.names(SPAIN), roster.names(SPAIN), "names travel with the save")
	assert_eq(restored.medals(SPAIN, "general_2"), 1, "medals still travel")


func test_an_old_save_is_christened_on_load() -> void:
	# A save written before names existed: ids and medals only.
	var restored: GeneralRoster = GeneralRoster.from_dict({
		"pools": {str(SPAIN): [{"id": "general_1", "medals": 2}]}
	})
	var fresh := GeneralRoster.new()
	fresh.sync(SPAIN, {})

	assert_false(restored.name_of(SPAIN, "general_1").is_empty(), "nothing is anonymous")
	assert_eq(
		restored.name_of(SPAIN, "general_1"),
		fresh.name_of(SPAIN, "general_1"),
		"the same arithmetic christens a legacy save"
	)
	assert_eq(restored.medals(SPAIN, "general_1"), 2, "the record survives the naming")


func test_the_despatch_names_the_commander() -> void:
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {})

	assert_eq(
		roster.label(SPAIN, "general_1"),
		roster.name_of(SPAIN, "general_1"),
		"a medal is credited to a man, not a rank"
	)
	assert_eq(roster.label(SPAIN, "general_9"), "", "an unknown commander names nothing")


func test_the_dossier_block_names_every_general_and_his_medals() -> void:
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {"organised_regiments": true})
	roster.award(SPAIN, "general_1")

	var block: String = roster.line(SPAIN)

	for general_id: String in roster.ids(SPAIN):
		assert_true(
			block.contains(roster.name_of(SPAIN, general_id)),
			"the block names every commander"
		)
	assert_true(block.contains("%s (1 medal)" % roster.name_of(SPAIN, "general_1")))
	assert_true(block.contains("%s (0 medals)" % roster.name_of(SPAIN, "general_2")))
	assert_true(block.contains("+1 line"), "the block says what a medal buys")
	assert_true(block.contains("+5% morale"))
	assert_true(block.contains("+10 initiative"))


func test_a_minor_nation_dossier_carries_no_commanders() -> void:
	var layer := ArmyLayer.new()
	var army := ArmyState.muster(1, 6, 2, false, ["pikemen"], 1)

	assert_eq(layer.command_text(army), "", "a Minor Nation holds no generals")
	layer.free()


func test_the_dossier_shows_the_commanders_under_their_medallion() -> void:
	var model: MapModel = CivilianFixture.build()
	var army := ArmyState.muster(1, SPAIN, 0, false, ["pikemen"], 1)
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {})
	var panel := ArmyPanel.new()
	add_child(panel)

	var opening := ArmyDossierOpening.of(army, true)
	opening.command = roster.line(SPAIN)
	panel.refresh(model, opening)

	assert_true(panel._command_row.visible, "the block shows for the crown's army")
	assert_true(
		String(panel._command.text).contains(roster.name_of(SPAIN, "general_1")),
		"the block names the commander"
	)
	assert_true(
		panel._command.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
		"the block wraps at a phone sheet instead of clipping"
	)
	assert_true(
		not String(panel._command.text).contains("\n"),
		"the row keeps one line; the medal's worth is the ledger's note (DR-20261115-11)"
	)
	assert_not_null(panel._command_icon.texture, "the commander has his own medallion")
	panel.free()
# --- test_oob_readings ---

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


## The docket carries the order of battle as well as the head count: three
## peasant levies (FPN + FPM 3 each) weigh nine, the term the published power
## score reads (wiki: diplomacy § Great Power power score).
func test_the_docket_carries_the_seen_order_of_battle() -> void:
	var army: ArmyState = _army(1, RIVAL, FOREIGN_PROVINCE)
	var readings: Dictionary = _readings(_charts(_world()), _armies([army]), _fleets([]))
	assert_eq(int(readings[OTHER]["regiments"][RIVAL]), 3, "the head count")
	assert_almost_eq(float(readings[OTHER]["strength"][RIVAL]), 9.0, 0.001, "the weight")
	assert_eq(
		float(readings[RIVAL]["strength"][RIVAL]), 9.0, "its own men are its own weight"
	)
	assert_false(
		readings[OTHER]["strength"].has(OTHER), "no unseen army weighs anything"
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
# --- test_battle_settlement ---

## The one settlement pipeline auto-resolve and Quick Battle share: the report
## fields, the province, the medal and the aftermath (wiki: combat § Outcomes;
## quick-battle § Outcome and integration; REQ-P2-03, REQ-P3-01, REQ-P3-04).



func _mods(medals: int = 0, fort: int = 0) -> Dictionary:
	return {"medals": medals, "fort": fort}


func _report(
	model: MapModel, outcome: int, attacker_medals: int = 0, defender_medals: int = 0
) -> Dictionary:
	return BattleSettlement.report_skeleton(
		model, 2, 0, 1, outcome,
		[] as Array[String], [] as Array[String],
		_mods(attacker_medals), _mods(defender_medals)
	)


func test_the_skeleton_carries_the_fields_every_battle_prints() -> void:
	var model := Fixture.build()
	var province: ProvinceState = model.get_province(2)
	province.fort_level = 2
	province.hospital_level = 1
	var atk_lost: Array[String] = ["a1"]
	var def_lost: Array[String] = []
	var report: Dictionary = BattleSettlement.report_skeleton(
		model, 2, 0, 1, ArmyCombat.Outcome.STALEMATE, atk_lost, def_lost,
		_mods(2), _mods(1, 2)
	)
	assert_eq(int(report["province"]), 2)
	assert_eq(int(report["attacker"]), 0)
	assert_eq(int(report["defender"]), 1)
	assert_eq(int(report["outcome"]), ArmyCombat.Outcome.STALEMATE)
	assert_eq(report["attacker_lost"], atk_lost)
	assert_eq(report["defender_lost"], def_lost)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["garrison"]), 0)
	assert_eq(String(report["recovered_type"]), "")
	assert_eq(int(report["attacker_medals"]), 2)
	assert_eq(int(report["defender_medals"]), 1)
	assert_eq(String(report["battle_mode"]), "siege")
	assert_eq(int(report["fort_level"]), 2)
	assert_eq(int(report["hospital_level"]), 1)
	assert_eq(String(report["medal_gain"]), "")
	assert_eq(int(report["medal_owner"]), -1)


func test_a_victory_flips_the_province_and_decorates_the_attacker() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.ATTACKER_VICTORY)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 0, "the victor holds the province")
	assert_true(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 1)
	assert_eq(int(report["defender_chevrons"]), 0)
	assert_eq(int(report["attacker_mauled"]), 0)


func test_a_defeat_keeps_the_province_and_decorates_the_defender() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["guards"])
	var attacking := Fixture.army(2, 0, 2, ["peasant_levies"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.DEFENDER_VICTORY)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 1)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 0)
	assert_eq(int(report["defender_chevrons"]), 1)


## An advantage holds the field but never hands over the province
## (wiki: quick-battle § Outcome and integration).
func test_an_advantage_advances_the_attacker_without_the_province() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.ATTACKER_ADVANTAGE)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 1)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 1)
	assert_eq(int(report["defender_chevrons"]), 0)


func test_a_mutual_annihilation_raises_a_garrison_when_a_second_attacker_waits() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.MUTUAL_ANNIHILATION)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, true, defending.count()
	)

	assert_eq(int(report["garrison"]), 1)
	assert_eq(
		String(report["recovered_type"]),
		RegimentCatalog.garrison_type_for(ArmyGarrison.GREAT_POWER_ERA)
	)
	assert_eq(armies.size(), 3, "the reformed garrison joins the field")


func test_a_mutual_annihilation_with_no_second_attacker_leaves_no_garrison() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.MUTUAL_ANNIHILATION)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, defending.count()
	)

	assert_eq(int(report["garrison"]), 0)
	assert_eq(String(report["recovered_type"]), "")
	assert_eq(armies.size(), 2)


func test_a_stalemate_settles_no_holder_and_no_chevrons() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.STALEMATE)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 1)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 0)
	assert_eq(int(report["defender_chevrons"]), 0)
	assert_eq(int(report["garrison"]), 0)


## A medal is the commander's, not the side's: the settlement asks
## [ArmyCommand] exactly as auto-resolve did before the split.
func test_a_winning_commander_takes_the_medal() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = {
		"roster": roster,
		"army_general": {attacking.id: "general_1"},
	}
	var report: Dictionary = _report(model, ArmyCombat.Outcome.ATTACKER_VICTORY)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		context, false, 1
	)

	assert_eq(String(report["medal_gain"]), "general_1")
	assert_eq(int(report["medal_owner"]), 0)
	assert_eq(roster.medals(0, "general_1"), 1)

# ==== merged from test_land_battle_rules.gd (one coverage boot; docs/testing.md § Speed rules) ====
## One boot for the field: forts and sieges, the hospital, army field rules and
## regiment names, military parity, difficulty and the quick battle resolver.

## Merged from test_fort_rules, test_siege_depth, test_hospital_rules,
## test_army_field_rules, test_army_regiment_names, test_military_parity,
## test_difficulty, test_quick_battle_rules, test_army_markers.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const ArmyFixture = preload("res://tests/army_fixture.gd")
const land_CivilianFixture = preload("res://tests/civilian_fixture.gd")
const siege_depth_Fixture = preload("res://tests/army_fixture.gd")
const hospital_rules_Fixture = preload("res://tests/army_fixture.gd")
const hospital_rules_CivilianFixture = preload("res://tests/civilian_fixture.gd")
const army_field_rules_Fixture = preload("res://tests/army_fixture.gd")
const army_regiment_names_Fixture = preload("res://tests/army_fixture.gd")
const difficulty_Fixture = preload("res://tests/army_fixture.gd")
const quick_battle_rules_Fixture = preload("res://tests/army_fixture.gd")

var _model: MapModel = null
var _army_field_rules_model: MapModel = null

var _suite_setup: String = ""

func _setup_fort_rules() -> void:
	_suite_setup = "fort_rules"
	_model = ArmyFixture.build()

func _setup_army_field_rules() -> void:
	_suite_setup = "army_field_rules"
	_army_field_rules_model = army_field_rules_Fixture.build()

# --- test_fort_rules ---

func test_fort_tables_follow_the_wiki() -> void:
	_setup_fort_rules()
	assert_eq(FortRules.MAX_LEVEL, 3)
	assert_eq(FortRules.guns(1), 1)
	assert_eq(FortRules.guns(2), 2)
	assert_eq(FortRules.guns(3), 3)
	assert_almost_eq(FortRules.wall_hp(1), 10.0, 0.001)
	assert_almost_eq(FortRules.wall_hp(3), 30.0, 0.001)
	assert_almost_eq(FortRules.damage_reduction(3), 0.6, 0.001)
	assert_eq(FortRules.cost(1), {"lumber": 3, "bronze": 3})
	assert_eq(FortRules.cost(3), {"steel": 5, "lumber": 5})
	assert_eq(FortRules.tech_gate(1), "")
	assert_eq(FortRules.tech_gate(2), "mine_engineering")
	assert_eq(FortRules.tech_gate(3), "modern_forts")

func test_fort_levels_are_multi_turn_and_capped() -> void:
	_setup_fort_rules()
	assert_eq(FortRules.turns(1), 1)
	assert_eq(FortRules.turns(3), 3)
	assert_eq(FortRules.next_level(0), 1)
	assert_eq(FortRules.next_level(2), 3)
	assert_eq(FortRules.next_level(3), 3)

## A finished project names the wall it actually left standing: the raise when
## the level went up, and no claim at all when a second project finished after
## the wall already stood (wiki: siege-mechanics § Fort Levels).
func test_a_fort_receipt_names_only_the_level_it_raised() -> void:
	_setup_fort_rules()
	assert_eq(
		FortRules.raise_line(1, 2),
		"stone fort raised · 20 wall hp · 2 emplaced guns"
	)
	assert_eq(
		FortRules.raise_line(2, 2),
		"no level added — the province already stands at a stone fort"
	)
	assert_eq(FortRules.raise_line(0, 0), "no fort stands here")

func test_emplaced_battery_follows_the_researched_line() -> void:
	_setup_fort_rules()
	assert_eq(FortRules.emplaced_type({}), "royal_artillery")
	assert_eq(
		FortRules.emplaced_type({"heavy_emplaced_artillery": true}),
		"heavy_artillery"
	)
	assert_eq(
		FortRules.emplaced_type({"heavy_emplaced_artillery": true, "emplaced_siege_guns": true}),
		"siege_guns"
	)
	assert_almost_eq(
		FortRules.emplaced_strength(2, {}),
		2.0 * float(RegimentCatalog.strength("royal_artillery")),
		0.001
	)
	assert_almost_eq(FortRules.emplaced_strength(0, {}), 0.0, 0.001)

func test_walls_soak_strength_and_spare_the_defenders() -> void:
	_setup_fort_rules()
	assert_almost_eq(FortRules.wall_soak(30.0, 0), 30.0, 0.001)
	assert_almost_eq(FortRules.wall_soak(30.0, 2), 10.0, 0.001)
	assert_almost_eq(FortRules.wall_soak(5.0, 3), 0.0, 0.001)
	assert_almost_eq(FortRules.loss_scale(0), 1.0, 0.001)
	assert_almost_eq(FortRules.loss_scale(1), 0.75, 0.001)

func test_open_field_provinces_stay_field_battles() -> void:
	_setup_fort_rules()
	var defender := ArmyFixture.army(1, 1, 2, land__repeat("peasant_levies", 10))
	var attacker := ArmyFixture.army(2, 0, 2, land__repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(String(reports[0]["battle_mode"]), "field")
	assert_eq(int(reports[0]["fort_level"]), 0)
	assert_eq((reports[0]["defender_lost"] as Array).size(), 6)
	assert_false(reports[0].has("siege"), "no walls means no battery block")

## Auto-resolve gun-loss (DR-20261110-22): the besieging train silences whole
## pieces and a silent battery drops the fort, even when the attack is repelled
## (wiki: siege-mechanics § Emplaced Artillery).
func test_auto_resolve_artillery_silences_the_battery_and_drops_the_fort() -> void:
	_setup_fort_rules()
	var defender := ArmyFixture.army(1, 1, 2, land__repeat("peasant_levies", 10))
	var attacker := ArmyFixture.army(2, 0, 2, ["royal_artillery"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)
	var siege: Dictionary = reports[0]["siege"]

	assert_eq(int(siege["guns_start"]), 1)
	assert_eq(int(siege["guns_lost"]), 1, "one train of guns silences a Wood fort's one gun")
	assert_eq(String(siege["gun_type"]), "royal_artillery")
	assert_true(bool(siege["fort_downgraded"]))
	assert_eq(int(siege["fort_after"]), 0)
	assert_eq(_model.get_province(2).fort_level, 0, "the silent battery leaves open field")

func test_a_besieger_without_artillery_leaves_the_battery_standing() -> void:
	_setup_fort_rules()
	var defender := ArmyFixture.army(1, 1, 2, land__repeat("peasant_levies", 10))
	var attacker := ArmyFixture.army(2, 0, 2, land__repeat("guards", 5))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)
	var siege: Dictionary = reports[0]["siege"]

	assert_eq(int(siege["guns_lost"]), 0, "infantry cannot answer the battery")
	assert_false(bool(siege["fort_downgraded"]))
	assert_eq(_model.get_province(2).fort_level, 1)

func test_a_train_short_of_the_battery_silences_only_its_weight() -> void:
	_setup_fort_rules()
	var defender := ArmyFixture.army(1, 1, 2, land__repeat("peasant_levies", 10))
	var attacker := ArmyFixture.army(2, 0, 2, ["royal_artillery"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 3

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)
	var siege: Dictionary = reports[0]["siege"]

	assert_eq(int(siege["guns_start"]), 3)
	assert_eq(int(siege["guns_lost"]), 1, "one gun's weight silences one of three")
	assert_false(bool(siege["fort_downgraded"]))
	assert_eq(_model.get_province(2).fort_level, 3)

func test_a_silenced_battery_downgrades_even_when_the_attack_is_repelled() -> void:
	_setup_fort_rules()
	var defender := ArmyFixture.army(1, 1, 2, land__repeat("guards", 10))
	var attacker := ArmyFixture.army(2, 0, 2, ["royal_artillery"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_true(bool((reports[0]["siege"] as Dictionary)["fort_downgraded"]))
	assert_eq(_model.get_province(2).fort_level, 0, "guns are lost whatever the banner")

func test_a_better_emplaced_line_needs_a_heavier_train() -> void:
	_setup_fort_rules()
	var royal := ArmyFixture.army(2, 0, 2, land__repeat("royal_artillery", 2))
	var heavy: Dictionary = {"heavy_emplaced_artillery": true}

	assert_eq(
		AutoSiege.guns_silenced(2, {}, [royal], 10), 2,
		"two royal trains silence two royal pieces"
	)
	assert_eq(
		AutoSiege.guns_silenced(2, heavy, [royal], 10), 1,
		"heavy pieces need more than one train for each"
	)
	assert_eq(AutoSiege.artillery_weight([royal], 10), 22.0)
	assert_eq(AutoSiege.gun_weight(heavy), 15.0)
	assert_eq(AutoSiege.guns_silenced(0, {}, [royal], 10), 0, "no fort, no battery")
	assert_eq(AutoSiege.artillery_weight([], 10), 0.0)

func test_walls_blunt_the_assault_and_shrink_defender_losses() -> void:
	_setup_fort_rules()
	var defender := ArmyFixture.army(1, 1, 2, land__repeat("peasant_levies", 10))
	var attacker := ArmyFixture.army(2, 0, 2, land__repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(String(reports[0]["battle_mode"]), "siege")
	assert_eq(int(reports[0]["fort_level"]), 1)
	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_eq((reports[0]["defender_lost"] as Array).size(), 2)
	assert_eq(_model.province_owner(2), 1)

func test_a_captured_province_keeps_its_walls() -> void:
	_setup_fort_rules()
	var defender := ArmyFixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := ArmyFixture.army(2, 0, 2, land__repeat("guards", 5))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 2

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(_model.province_owner(2), 0)
	assert_eq(_model.get_province(2).fort_level, 2)

func test_engineer_raises_a_fort_and_lays_materials_down() -> void:
	_setup_fort_rules()
	var model := land_CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := land_CivilianFixture.unit("engineer", land_CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = land_CivilianFixture.stockpile()
	var check: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, stock
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), 1)
	assert_eq(check["cost"], {"lumber": 3, "bronze": 3})

	var result: Dictionary = CivilianWork.assign(
		model, engineer, "build_fort", works, units, stock
	)
	assert_true(bool(result["ok"]))
	assert_eq(int(stock["lumber"]), 37)
	assert_eq(int(stock["bronze"]), 7)
	assert_eq(model.get_province(land_CivilianFixture.PLAYER_PROVINCE).fort_level, 0)

	CivilianWork.resolve_turn(model, units, works)
	assert_eq(model.get_province(land_CivilianFixture.PLAYER_PROVINCE).fort_level, 1)
	assert_true(engineer.is_idle())


## The order names the wall it buys. Three fort levels share one order name,
## three prices and three waits, so "Build fort" cannot be told from "Build
## fort" for a higher wall (wiki: siege-mechanics § Fort Levels), and the turn
## that finishes it says which level was raised.
func test_the_fort_order_names_its_level_and_its_raise() -> void:
	_setup_fort_rules()
	var model := land_CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := land_CivilianFixture.unit("engineer", land_CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = land_CivilianFixture.stockpile()

	var option: Dictionary = _fort_option(
		CivilianWork.options(model, engineer, works, units, stock)
	)
	assert_eq(String(option["label"]), "Build wood fort")
	assert_eq(String(option["cost_text"]), "3 lumber + 3 bronze · 1 turn")

	var result: Dictionary = CivilianWork.assign(
		model, engineer, "build_fort", works, units, stock
	)
	assert_eq(String(result["label"]), "Build wood fort", "the order names the level")
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(model, units, works)
	assert_eq(int(reports[0].get("fort_level", 0)), 1, "the report carries the level raised")
	assert_eq(
		FortRules.raise_text(1), "wood fort raised · 10 wall hp · 1 emplaced gun",
		"the despatch names the wall, not just the order"
	)

	# A stone wall is a different order: its own level, its own two turns.
	model.get_province(land_CivilianFixture.PLAYER_PROVINCE).fort_level = 1
	var upper: Dictionary = _fort_option(
		CivilianWork.options(
			model, engineer, works, units, stock, null, {}, {"mine_engineering": true}
		)
	)
	assert_eq(String(upper["label"]), "Build stone fort")
	assert_eq(String(upper["cost_text"]), "4 lumber + 4 bronze · 2 turns")


func _fort_option(options: Array[Dictionary]) -> Dictionary:
	for option: Dictionary in options:
		if String(option["action"]) == "build_fort":
			return option
	return {}

func test_upgrades_need_their_tech_and_stop_at_the_ceiling() -> void:
	_setup_fort_rules()
	var model := land_CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := land_CivilianFixture.unit("engineer", land_CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = land_CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(land_CivilianFixture.PLAYER_PROVINCE)

	province.fort_level = 1
	var gated: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, stock
	)
	assert_false(bool(gated["ok"]))
	assert_true(String(gated["reason"]).contains("Mine Engineering"))

	var allowed: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, stock, null,
		CivilianState.NO_TILE, {}, {"mine_engineering": true}
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))
	assert_eq(int(allowed["duration"]), 2)

	province.fort_level = 3
	var ceiling: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, stock
	)
	assert_false(bool(ceiling["ok"]))
	assert_true(String(ceiling["reason"]).contains("modern fort"))

func test_only_owned_land_can_be_fortified() -> void:
	_setup_fort_rules()
	var model := land_CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := land_CivilianFixture.unit(
		"engineer", land_CivilianFixture.RIVAL_GRAIN_TILE, 0
	)
	var units: Array[CivilianState] = [engineer]

	var check: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, land_CivilianFixture.stockpile()
	)

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("not held"))

func test_a_second_project_cannot_leap_a_fort_level() -> void:
	_setup_fort_rules()
	# wiki: siege-mechanics § Fort Levels — Stone costs 4 lumber + 4 bronze and
	# needs Mine Engineering; civilian-units § Work Order Summary — one turn per
	# level. Tile exclusivity does not stop a second engineer in the same
	# province, but the completed projects must still leave one Wood fort.
	var model := land_CivilianFixture.build()
	var works := LandWorks.new()
	var first := land_CivilianFixture.unit("engineer", land_CivilianFixture.BARE_TILE)
	var second := land_CivilianFixture.unit("engineer", Vector2i(2, 1))
	second.id = 2
	var units: Array[CivilianState] = [first, second]
	var stock: Dictionary = land_CivilianFixture.stockpile()
	var a: Dictionary = CivilianWork.assign(model, first, "build_fort", works, units, stock)
	var b: Dictionary = CivilianWork.assign(model, second, "build_fort", works, units, stock)
	assert_true(bool(a["ok"]), String(a.get("reason", "")))
	assert_true(bool(b["ok"]), String(b.get("reason", "")))
	assert_eq(int(stock["bronze"]), 4, "both projects pay their level-1 materials")

	CivilianWork.resolve_turn(model, units, works)

	assert_eq(
		model.get_province(land_CivilianFixture.PLAYER_PROVINCE).fort_level, 1,
		"one turn of level-1 materials buys a Wood fort, not a free Stone one"
	)

func test_a_duplicate_upgrade_cannot_leap_the_modern_forts_gate() -> void:
	_setup_fort_rules()
	var model := land_CivilianFixture.build()
	var works := LandWorks.new()
	var first := land_CivilianFixture.unit("engineer", land_CivilianFixture.BARE_TILE)
	var second := land_CivilianFixture.unit("engineer", Vector2i(2, 2))
	second.id = 2
	var units: Array[CivilianState] = [first, second]
	var stock: Dictionary = land_CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(land_CivilianFixture.PLAYER_PROVINCE)
	province.fort_level = 1
	var tech: Dictionary = {"mine_engineering": true}

	var upgrade: Dictionary = CivilianWork.assign(
		model, first, "build_fort", works, units, stock, null,
		CivilianState.NO_TILE, {}, tech
	)
	assert_eq(int(upgrade["duration"]), 2, "a Stone upgrade is a two-turn project")
	CivilianWork.resolve_turn(model, units, works)
	assert_eq(province.fort_level, 1, "the Stone upgrade is still in progress")
	var duplicate: Dictionary = CivilianWork.assign(
		model, second, "build_fort", works, units, stock, null,
		CivilianState.NO_TILE, {}, tech
	)
	assert_true(bool(duplicate["ok"]), String(duplicate.get("reason", "")))
	CivilianWork.resolve_turn(model, units, works)
	CivilianWork.resolve_turn(model, units, works)

	assert_eq(
		province.fort_level, 2,
		"a finished duplicate leaves the Stone fort alone — Modern Forts is unowned"
	)

func test_a_queued_fort_keeps_its_ordered_level_across_a_save() -> void:
	_setup_fort_rules()
	var model := land_CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := land_CivilianFixture.unit("engineer", land_CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = land_CivilianFixture.stockpile()
	CivilianWork.assign(model, engineer, "build_fort", works, units, stock)

	var restored: CivilianState = CivilianState.from_dict(engineer.to_dict())
	assert_eq(restored.work_detail("fort_level"), 1, "the ordered level rides in work")
	var reloaded: Array[CivilianState] = [restored]
	CivilianWork.resolve_turn(model, reloaded, works)

	assert_eq(model.get_province(land_CivilianFixture.PLAYER_PROVINCE).fort_level, 1)

func test_a_fort_rises_on_the_provinces_town_tile() -> void:
	_setup_fort_rules()
	# wiki: siege-mechanics § Fort Levels — engineers build on the town tile;
	# DR-20261110-24 brings the province-scoped fort onto it.
	var model := land_CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := land_CivilianFixture.unit("engineer", land_CivilianFixture.TIMBER_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = land_CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(land_CivilianFixture.PLAYER_PROVINCE)
	province.town_tile = Vector2i(2, 0)

	assert_eq(FortRules.site_tile(model, province.id), Vector2i(2, 0))
	var check: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, stock
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(Vector2i(check["tile"]), Vector2i(2, 0), "the work targets the town")

	CivilianWork.assign(model, engineer, "build_fort", works, units, stock)
	assert_eq(engineer.work_tile(), Vector2i(2, 0))
	CivilianWork.resolve_turn(model, units, works)
	assert_eq(province.fort_level, 1)
	assert_eq(engineer.tile, Vector2i(2, 0), "the crew works the town it walled")

func test_the_fort_site_falls_back_to_the_capital_then_the_ordered_tile() -> void:
	_setup_fort_rules()
	var model := land_CivilianFixture.build()
	var province: ProvinceState = model.get_province(land_CivilianFixture.PLAYER_PROVINCE)
	assert_eq(FortRules.site_tile(model, province.id), land_CivilianFixture.BARE_TILE)

	province.town_tile = Vector2i(2, 0)
	assert_eq(FortRules.site_tile(model, province.id), Vector2i(2, 0), "the town wins")
	province.town_tile = Vector2i(-1, -1)
	province.capital_tile = Vector2i(-1, -1)
	assert_eq(FortRules.site_tile(model, province.id), Vector2i(-1, -1), "legacy map")

func land__repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types

# --- test_siege_depth ---

func test_land_lane_terrain_follows_the_ground() -> void:
	var model := siege_depth_Fixture.build()
	assert_eq(SiegeGround.lane_terrain(model, 2, 0), "open", "plains without a fort")
	assert_eq(SiegeGround.lane_terrain(model, 2, 1), "town", "a fort rings its town")
	land__set_ground(model, 2, MapModel.Terrain.HILLS)
	assert_eq(SiegeGround.lane_terrain(model, 2, 0), "hill")
	assert_eq(SiegeGround.lane_terrain(model, 2, 2), "hill", "broken ground keeps its character")
	land__set_ground(model, 2, MapModel.Terrain.HARDWOOD_FOREST)
	assert_eq(SiegeGround.lane_terrain(model, 2, 0), "woods")
	land__set_ground(model, 2, MapModel.Terrain.SWAMP)
	assert_eq(SiegeGround.lane_terrain(model, 2, 0), "marsh")
	assert_eq(SiegeGround.lane_terrain(model, 2, 0, "town"), "town", "a playtest may override")

## The ground is published as `marsh` (wiki: quick-battle § Terrain;
## DR-20261110-27): a swamp province fights on marsh ground and the documented
## override is the same id the record carries — not the map's terrain enum name.
func test_land_the_marsh_ground_speaks_the_published_id() -> void:
	var model := siege_depth_Fixture.build()
	land__set_ground(model, 2, MapModel.Terrain.SWAMP)

	assert_true(SiegeGround.TERRAIN.has("marsh"), "the published id is the table key")
	assert_eq(SiegeGround.lane_terrain(model, 2, 0, "marsh"), "marsh",
		"the documented playtest override is honoured")
	assert_eq(SiegeGround.lane_terrain(model, 2, 0, "swamp"), "marsh",
		"the map enum name is not a lane id; it falls back to the province ground")
	assert_almost_eq(SiegeGround.terrain_scale("volley", "marsh"), 0.9, 0.001)
	assert_almost_eq(SiegeGround.terrain_scale("assault", "marsh"), 0.7, 0.001)
	assert_almost_eq(SiegeGround.entrench_scale("marsh"), 0.8, 0.001)
	assert_eq(SiegeGround.terrain_label("marsh"), "Marsh")

	var battle: Dictionary = _siege_depth_fight(
		"balanced", _siege_depth_repeat("guards", 8), _siege_depth_repeat("musketeers", 6), 0, "marsh"
	)
	assert_eq(String(battle["quick"]["terrain"]), "marsh", "the record speaks the rule")
	assert_eq(String(battle["quick"]["terrain_label"]), "Marsh")
	assert_true(
		land__assault_losses("marsh", 20) < land__assault_losses("open", 20),
		"a charge into the marsh is blunted, not open ground"
	)

func test_land_terrain_scales_the_action_tables() -> void:
	assert_almost_eq(SiegeGround.terrain_scale("volley", "open"), 1.0, 0.001)
	assert_almost_eq(SiegeGround.terrain_scale("assault", "town"), 0.55, 0.001)
	assert_almost_eq(SiegeGround.terrain_scale("assault", "woods"), 0.6, 0.001)
	assert_almost_eq(SiegeGround.terrain_scale("volley", "woods"), 0.75, 0.001)
	assert_almost_eq(SiegeGround.entrench_scale("town"), 1.4, 0.001)
	assert_almost_eq(SiegeGround.entrench_scale("marsh"), 0.8, 0.001)
	assert_almost_eq(SiegeGround.terrain_scale("entrench", "town"), 1.0, 0.001, "no damage")
	assert_eq(SiegeGround.terrain_label("hill"), "Hillside")
	assert_eq(SiegeGround.terrain_label("unknown"), "Open field")

func test_land_three_gates_open_one_at_a_time() -> void:
	var gates: Dictionary = SiegeGates.gates_for(2)
	assert_eq(int(gates["max"]), 3)
	assert_eq(int(gates["threshold"]), 7, "20 wall HP shared by three gates")
	assert_false(SiegeGates.breached(gates))
	assert_eq(SiegeGates.batter(gates, 6), 0, "six casualties do not open a gate")
	assert_eq(SiegeGates.batter(gates, 1), 1, "the seventh does")
	assert_true(SiegeGates.breached(gates))
	assert_almost_eq(SiegeGates.breach_share(gates), 1.0 / 3.0, 0.001)
	assert_eq(SiegeGates.batter(gates, 20), 2, "the rest fall in one blow")
	assert_eq(int(gates["broken"]), 3, "three gates and no more")
	assert_eq(SiegeGates.batter(gates, 20), 0)
	assert_true(SiegeGates.gates_for(0).is_empty(), "no fort, no gates")
	assert_eq(SiegeGates.breach_threshold(0), 0)
	assert_eq(SiegeGates.batter({}, 4), 0, "a field battle has no gate state")

func test_land_a_breach_sheds_the_wall_and_opens_the_behind_lane() -> void:
	var sheltered: Dictionary = land__breach_strike(0)
	assert_true((sheltered["wall"] as Array).size() > 0, "the wall takes the shot")
	assert_eq(int(sheltered["gates_broken"]), 0, "one blow is not a breach")

	var opened: Dictionary = land__breach_strike(1)
	assert_true(
		(opened["wall"] as Array).size() > (sheltered["wall"] as Array).size(),
		"a gate down, the wall no longer spares the garrison"
	)
	assert_true(
		(opened["behind"] as Array).size() > (sheltered["behind"] as Array).size(),
		"the attackers pour through the gate into the behind lane"
	)

## A fresh defender each time: the same blow against a whole wall and against a
## wall already breached through one gate.
func land__breach_strike(broken: int) -> Dictionary:
	var attacker: Array[ArmyState] = land__side(["musketeers", "musketeers", "musketeers", "culverin"], 2)
	var types: Array[String] = _siege_depth_repeat("peasant_levies", 8)
	types.append_array(_siege_depth_repeat("squires", 2))
	types.append_array(_siege_depth_repeat("culverin", 2))
	var defender: Array[ArmyState] = land__side(types, 1)
	var armies: Array[ArmyState] = land__joined(attacker, defender)
	var gates: Dictionary = SiegeGates.gates_for(2)
	gates["broken"] = broken
	return SiegeLanes.strike(armies, attacker, defender, 12, 20, 2, false, gates)

## A line with no fight left in it delivers no blow, so it has nothing to spend
## on the fort's battery — a spent besieger cannot grind a gun down (wiki:
## siege-mechanics § Quick Battle lanes — "the guns take the blow", and only
## what a blow delivers can reach them; DR-20261110-22 buys gun loss with the
## besieging train's weight, never with an empty blow).
func test_land_a_spent_line_cannot_grind_down_the_battery() -> void:
	var attacker: Array[ArmyState] = land__side(_siege_depth_repeat("musketeers", 4), 2)
	var defender: Array[ArmyState] = land__side(_siege_depth_repeat("pikemen", 4), 1)
	var state: Dictionary = land__state(attacker, defender, "open")
	state["defender"]["mods"] = {"fort": 2}
	state["attacker"]["cohesion"] = 0
	var armies: Array[ArmyState] = state["armies"]
	var guns: Array[Dictionary] = QuickBattleBattery.make(2, {}, 1)

	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)

	assert_eq(int(entry["battery_hit"]), 0, "no blow, nothing for the guns to soak")
	assert_eq(int(entry["guns_destroyed"]), 0, "a spent line cannot silence a gun")
	assert_almost_eq(
		QuickBattleBattery.total_hp(guns), 4.0, 0.001, "the battery is untouched"
	)
	## The other side of the line: a line with fight left in it still pays the
	## guns first, so the fix does not stop a real besieger from silencing them.
	var fresh: Array[Dictionary] = QuickBattleBattery.make(2, {}, 1)
	state["attacker"]["cohesion"] = 3
	var spent: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", fresh
	)
	assert_true(int(spent["battery_hit"]) > 0, "a real blow is spent on the battery")

func test_land_a_quick_battle_reports_its_ground_and_gates() -> void:
	var battle: Dictionary = _siege_depth_fight(
		"balanced", _siege_depth_repeat("guards", 20), _siege_depth_repeat("musketeers", 10), 1, "hill"
	)
	var quick: Dictionary = battle["quick"]
	assert_eq(String(quick["terrain"]), "hill")
	assert_eq(String(quick["terrain_label"]), "Hillside")
	assert_eq(int((quick["gates"] as Dictionary)["max"]), 3)
	assert_true(int((quick["gates"] as Dictionary)["damage"]) > 0, "the wall was beaten")
	assert_eq(int((quick["limits"] as Dictionary)["attacker"]), 10)
	assert_eq(String(battle["battle_mode"]), "siege")

func test_land_a_garrison_without_firearms_sallies_on_its_own() -> void:
	var battle: Dictionary = _siege_depth_fight(
		"balanced", _siege_depth_repeat("guards", 8), _siege_depth_repeat("pikemen", 6), 2, "town"
	)
	assert_true(int(battle["quick"]["sorties"]) > 0, "a pike garrison must sally to fight")
	assert_eq(String(battle["quick"]["defender_plan"]), "aggressive")

func test_land_the_sortie_is_a_dedicated_order() -> void:
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, true),
		["entrench", "sortie"], "a sally, not an assault on its own wall"
	)
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, false),
		["entrench", "volley", "volley"], "no wall, no gate to sally from"
	)
	assert_eq(QuickBattleActions.actions_for("aggressive"), ["maneuver", "assault"])
	assert_eq(int(QuickBattleActions.ACTION_CP["sortie"]), 2)
	assert_eq(String(QuickBattleActions.ACTION_LABEL["sortie"]), "Sortie")

func test_land_an_assault_into_town_is_weaker() -> void:
	var open_losses: int = land__assault_losses("open")
	var town_losses: int = land__assault_losses("town")
	assert_true(town_losses < open_losses, "streets and rooftops blunt a charge")

func test_land_entrenching_is_surer_in_cover() -> void:
	var open_guard: float = land__entrench_guard("open")
	var town_guard: float = land__entrench_guard("town")
	assert_almost_eq(open_guard, 0.45, 0.001)
	assert_almost_eq(town_guard, 0.63, 0.001)
	assert_true(town_guard > open_guard)

func test_land_a_sortie_in_the_open_costs_the_garrison_dear() -> void:
	## Enough pike that a quality assault leaves men to pay the sally's own cost
	## (main's FPN/FPM blow no longer treats a thin garrison as a head count).
	var battle: Dictionary = _siege_depth_fight(
		"aggressive", _siege_depth_repeat("guards", 8), _siege_depth_repeat("pikemen", 16), 1, "town"
	)
	var sortie: Dictionary = {}
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if bool(action["sortie"]):
				sortie = action
	assert_true(not sortie.is_empty(), "the plate records the sally")
	assert_true(int(sortie["defender_lost"]) > 0, "the sally costs its own men")
	assert_eq(String(sortie["label"]), "Sortie")

func _siege_depth_fight(
	plan: String, attacker: Array[String], defender: Array[String], fort: int,
	terrain: String
) -> Dictionary:
	var model := siege_depth_Fixture.build()
	model.province_data(2).fort_level = fort
	land__set_ground(model, 2, land__ground(terrain))
	var defender_army := siege_depth_Fixture.army(1, 1, 2, defender, true)
	var attacker_army := siege_depth_Fixture.army(2, 0, 2, attacker)
	attacker_army.moved = true
	var armies: Array[ArmyState] = [defender_army, attacker_army]
	var context: Dictionary = {
		"quick_battle": true, "player_faction": 0,
		"battle_plan": plan, "seed": 11, "terrain_override": terrain,
	}
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	return reports[0]

func land__assault_losses(terrain: String, count: int = 6) -> int:
	## Peer-quality lines so the blow stays in the terrain band instead of
	## wiping both open and town (quality weight from main's Quick Battle).
	var attacker: Array[ArmyState] = land__side(_siege_depth_repeat("pikemen", count), 2)
	var defender: Array[ArmyState] = land__side(_siege_depth_repeat("pikemen", count), 1)
	var armies: Array[ArmyState] = land__joined(attacker, defender)
	var state: Dictionary = land__state(attacker, defender, terrain)
	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "assault", [] as Array[Dictionary]
	)
	return int(entry["defender_lost"])

func land__entrench_guard(terrain: String) -> float:
	var attacker: Array[ArmyState] = land__side(_siege_depth_repeat("guards", 4), 2)
	var defender: Array[ArmyState] = land__side(_siege_depth_repeat("pikemen", 4), 1)
	var state: Dictionary = land__state(attacker, defender, terrain)
	var armies: Array[ArmyState] = state["armies"]
	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "defender", "attacker", "entrench", [] as Array[Dictionary]
	)
	return float(entry["guard"])

func land__state(
	attacker: Array[ArmyState], defender: Array[ArmyState], terrain: String
) -> Dictionary:
	var state: Dictionary = {
		"attacker": {
			"side": attacker, "owner": 2, "limit": 10, "mods": {},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "balanced", "exposed": false,
		},
		"defender": {
			"side": defender, "owner": 1, "limit": 10, "mods": {"fort": 0},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "defensive", "exposed": false,
		},
		"terrain": terrain,
		"gates": {},
	}
	## One list so the resolver can find both sides' regiments by instance id.
	state["armies"] = land__joined(attacker, defender)
	return state

func land__side(types: Array[String], owner: int) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(siege_depth_Fixture.army(10 + owner, owner, 2, types, true))
	return side

func land__joined(first: Array[ArmyState], second: Array[ArmyState]) -> Array[ArmyState]:
	var all: Array[ArmyState] = []
	all.append_array(first)
	all.append_array(second)
	return all

func land__set_ground(model: MapModel, province: int, terrain: int) -> void:
	var data: ProvinceState = model.province_data(province)
	for tile: Vector2i in data.tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = terrain

func land__ground(terrain: String) -> int:
	match terrain:
		"hill":
			return MapModel.Terrain.HILLS
		"woods":
			return MapModel.Terrain.HARDWOOD_FOREST
		"marsh":
			return MapModel.Terrain.SWAMP
	return MapModel.Terrain.PLAINS

func _siege_depth_repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types

# --- test_hospital_rules ---

func test_hospital_tables_follow_the_design_record() -> void:
	assert_eq(HospitalRules.MAX_LEVEL, 2)
	assert_almost_eq(HospitalRules.rest_share(0), 0.25, 0.001)
	assert_almost_eq(HospitalRules.rest_share(1), 0.40, 0.001)
	assert_almost_eq(HospitalRules.rest_share(2), 0.55, 0.001)
	assert_almost_eq(HospitalRules.triage_scale(0), 1.0, 0.001)
	assert_almost_eq(HospitalRules.triage_scale(1), 0.80, 0.001)
	assert_almost_eq(HospitalRules.triage_scale(2), 0.65, 0.001)
	assert_eq(HospitalRules.cost(1), {"lumber": 3, "fabric": 2})
	assert_eq(HospitalRules.cost(2), {"lumber": 4, "fabric": 3, "steel": 2})
	assert_eq(HospitalRules.tech_gate(1), "organised_regiments")
	assert_eq(HospitalRules.tech_gate(2), "modern_military_funding")
	assert_eq(HospitalRules.turns(1), 1)
	assert_eq(HospitalRules.turns(2), 2)
	assert_eq(HospitalRules.next_level(0), 1)
	assert_eq(HospitalRules.next_level(2), 2)
	assert_true(HospitalRules.describe(1).contains("rest 40%"))
	assert_true(HospitalRules.describe(2).contains("wear 65%"))
	assert_eq(HospitalRules.describe(0), "No hospital")

func test_a_province_stores_its_hospital_level() -> void:
	var model := hospital_rules_Fixture.build()
	assert_eq(HospitalRules.level_at(model, 2), 0)
	HospitalRules.apply_build(model.province_data(2), 1)
	assert_eq(HospitalRules.level_at(model, 2), 1)
	HospitalRules.apply_build(model.province_data(2), 2)
	assert_eq(HospitalRules.level_at(model, 2), 2)
	HospitalRules.apply_build(model.province_data(2), 1)
	assert_eq(HospitalRules.level_at(model, 2), 2, "a later build never lowers the level")

func test_a_hospital_speeds_the_turn_start_rest() -> void:
	var model := hospital_rules_Fixture.build()
	var army := hospital_rules_Fixture.army(1, 0, 2, ["pikemen"])
	var regiment: String = army.regiments[0]
	army.regiment_health[regiment] = 55

	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 83, "a bare field restores a quarter")

	army.regiment_health[regiment] = 55
	model.province_data(2).hospital_level = 1
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 99, "a field hospital restores 40%")

	army.regiment_health[regiment] = 55
	model.province_data(2).hospital_level = 2
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 110, "a general hospital restores 55%")

func test_a_hospital_triages_the_defenders_battle_wear() -> void:
	var bare: Dictionary = _auto_battle(0)
	var field: Dictionary = _auto_battle(1)
	var general: Dictionary = _auto_battle(2)

	var bare_hp: int = _health_total(bare, "defender_health")
	var field_hp: int = _health_total(field, "defender_health")
	var general_hp: int = _health_total(general, "defender_health")

	assert_true(bare_hp > 0, "the defender survives the exchange")
	assert_true(field_hp > bare_hp, "a field hospital leaves fewer wounds")
	assert_true(general_hp > field_hp, "a general hospital leaves fewer still")
	assert_eq(int(field["hospital_level"]), 1)
	assert_eq(int(general["hospital_level"]), 2)

func test_a_hospital_triages_quick_battle_wear_too() -> void:
	var bare: Dictionary = _quick_battle(0)
	var field: Dictionary = _quick_battle(1)
	assert_true(_health_total(bare, "defender_health") > 0)
	assert_true(
		_health_total(field, "defender_health") > _health_total(bare, "defender_health"),
		"the quick plate reads the same triage"
	)

func test_an_engineer_raises_a_hospital_on_the_town_tile() -> void:
	var model := hospital_rules_CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := hospital_rules_CivilianFixture.unit("engineer", hospital_rules_CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = hospital_rules_CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(hospital_rules_CivilianFixture.PLAYER_PROVINCE)

	var check: Dictionary = CivilianWork.validate(
		model, engineer, "build_hospital", works, units, stock, null,
		CivilianState.NO_TILE, {}, {"organised_regiments": true}
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), 1)
	assert_eq(check["cost"], {"lumber": 3, "fabric": 2})

	var result: Dictionary = CivilianWork.assign(
		model, engineer, "build_hospital", works, units, stock, null,
		CivilianState.NO_TILE, {}, {"organised_regiments": true}
	)
	assert_true(bool(result["ok"]))
	assert_eq(int(stock["lumber"]), 37)
	assert_eq(int(stock["fabric"]), 18)
	assert_eq(province.hospital_level, 0)

	CivilianWork.resolve_turn(model, units, works)
	assert_eq(province.hospital_level, 1)
	assert_true(engineer.is_idle())

## A hospital shares the province town tile, so one crew a player owns builds it
## (wiki: civilian-units § Per-player tile exclusivity).
func test_a_second_engineer_cannot_raise_the_same_hospital() -> void:
	var model := hospital_rules_CivilianFixture.build()
	var works := LandWorks.new()
	var province: ProvinceState = model.get_province(hospital_rules_CivilianFixture.PLAYER_PROVINCE)
	province.town_tile = hospital_rules_CivilianFixture.BARE_TILE
	var first := hospital_rules_CivilianFixture.unit("engineer", hospital_rules_CivilianFixture.BARE_TILE)
	first.id = 1
	var second := hospital_rules_CivilianFixture.unit("engineer", Vector2i(2, 2))
	second.id = 2
	var units: Array[CivilianState] = [first, second]
	var stock: Dictionary = hospital_rules_CivilianFixture.stockpile()
	var tech := {"organised_regiments": true}
	assert_true(bool(CivilianWork.assign(
		model, first, "build_hospital", works, units, stock, null,
		CivilianState.NO_TILE, {}, tech
	)["ok"]))
	var blocked: Dictionary = CivilianWork.validate(
		model, second, "build_hospital", works, units, stock, null,
		CivilianState.NO_TILE, {}, tech
	)
	assert_false(bool(blocked["ok"]))
	assert_true(String(blocked["reason"]).contains("Another crew"))

func test_the_general_hospital_needs_its_tech_and_stops_at_the_ceiling() -> void:
	var model := hospital_rules_CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := hospital_rules_CivilianFixture.unit("engineer", hospital_rules_CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = hospital_rules_CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(hospital_rules_CivilianFixture.PLAYER_PROVINCE)

	province.hospital_level = 1
	var gated: Dictionary = CivilianWork.validate(
		model, engineer, "build_hospital", works, units, stock
	)
	assert_false(bool(gated["ok"]))
	assert_true(String(gated["reason"]).contains("Modern Military Funding"))

	var allowed: Dictionary = CivilianWork.validate(
		model, engineer, "build_hospital", works, units, stock, null,
		CivilianState.NO_TILE, {}, {"modern_military_funding": true}
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))
	assert_eq(int(allowed["duration"]), 2)

	province.hospital_level = 2
	var ceiling: Dictionary = CivilianWork.validate(
		model, engineer, "build_hospital", works, units, stock
	)
	assert_false(bool(ceiling["ok"]))
	assert_true(String(ceiling["reason"]).contains("general hospital"))

func test_a_save_round_trip_keeps_the_hospital() -> void:
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = 2
	var world := WorldMap.new()
	world.add_region(model)

	var captured: Array[Dictionary] = SaveWorld.capture(world)
	model.province_data(2).hospital_level = 0
	assert_true(SaveWorld.apply(world, captured))
	assert_eq(model.province_data(2).hospital_level, 2)

func test_the_army_layer_rests_each_region_by_its_own_hospital() -> void:
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = 1
	var army := hospital_rules_Fixture.army(1, 0, 2, ["pikemen"])
	var regiment: String = army.regiments[0]
	army.regiment_health[regiment] = 55
	var world := WorldMap.new()
	world.add_region(model)
	var layer := ArmyLayer.new()
	layer.regions.set_region(model.region_id, [army] as Array[ArmyState])

	layer.begin_turn(world)

	assert_eq(int(army.condition_of(regiment)["hp"]), 99, "the region's hospital applies")
	layer.free()

func _auto_battle(hospital: int) -> Dictionary:
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = hospital
	var defender := hospital_rules_Fixture.army(1, 1, 2, ["guards", "guards", "guards", "guards"], true)
	var attacker := hospital_rules_Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {"seed": 11})
	return reports[0]

func _quick_battle(hospital: int) -> Dictionary:
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = hospital
	var defender := hospital_rules_Fixture.army(
		1, 1, 2,
		["guards", "guards", "guards", "guards", "guards", "guards",
		"guards", "guards", "guards", "guards"],
		true
	)
	var attacker := hospital_rules_Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = {
		"quick_battle": true,
		"player_faction": 0,
		"battle_plan": "balanced",
		"seed": 11,
	}
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	return reports[0]

func _health_total(battle: Dictionary, key: String) -> int:
	var total: int = 0
	for entry: Dictionary in battle.get(key, []) as Array:
		total += int(entry["hp"])
	return total



# --- the wards eat (DR-20261112-04) -------------------------------------------


func test_the_rations_table_follows_the_design_record() -> void:
	assert_eq(HospitalRules.RATION_PER_LEVEL, 2)
	assert_eq(HospitalRules.food_demand(0), 0)
	assert_eq(HospitalRules.food_demand(1), 2)
	assert_eq(HospitalRules.food_demand(2), 4)
	assert_true(HospitalRules.describe(1).contains("staff 2 food"))
	assert_true(HospitalRules.describe(2).contains("staff 4 food"))
	var hungry: String = HospitalRules.describe(1, false)
	assert_true(hungry.contains("unstaffed"))
	assert_true(hungry.contains("rest 25%"), "an empty ward heals at the field's rate")
	assert_true(hungry.contains("wear 80%"), "the walls still shelter the wounded")



func test_an_unfed_ward_heals_at_the_fields_rate() -> void:
	var model := hospital_rules_Fixture.build()
	var province: ProvinceState = model.province_data(2)
	province.hospital_level = 1
	var army := hospital_rules_Fixture.army(1, 0, 2, ["pikemen"])
	var regiment: String = army.regiments[0]

	army.regiment_health[regiment] = 55
	province.hospital_staffed = false
	assert_eq(HospitalRules.effective_level(model, 2), 0)
	assert_eq(HospitalRules.level_at(model, 2), 1, "the building still stands")
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 83, "no staff, no faster rest")

	army.regiment_health[regiment] = 55
	province.hospital_staffed = true
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 99, "the staff returns")



func test_the_crowns_hospitals_are_counted_seat_first() -> void:
	var world := WorldMap.new()
	var model := hospital_rules_Fixture.build()
	world.add_region(model)
	# Faction 0 holds provinces 0 (seat), 1, 5 and 6.
	model.province_data(1).hospital_level = 1
	model.province_data(0).hospital_level = 2
	model.province_data(2).hospital_level = 2

	var rows: Array[Dictionary] = HospitalRules.demand_rows(world, 0)
	assert_eq(rows.size(), 2, "only this crown's wards eat from its larder")
	assert_eq(int(rows[0]["province"]), 0, "the seat is served first")
	assert_true(bool(rows[0]["seat"]))
	assert_eq(int(rows[1]["province"]), 1)
	var demands: Array[int] = HospitalRules.demand_list(world, 0)
	assert_eq(demands.size(), 2)
	assert_eq(demands[0] + demands[1], 6, "the crown's whole hospital ration")



func test_a_staff_is_fed_whole_or_not_at_all() -> void:
	var world := WorldMap.new()
	var model := hospital_rules_Fixture.build()
	world.add_region(model)
	model.province_data(0).hospital_level = 2
	model.province_data(1).hospital_level = 1

	var short: Dictionary = HospitalRules.feed(world, 0, 2)
	assert_eq(int(short["spent"]), 2, "no half-ration is spent on the seat")
	assert_eq((short["hungry"] as Array).size(), 1)
	assert_eq(int(short["hungry"][0]), 0, "the great hospital goes without")
	assert_false(model.province_data(0).hospital_staffed)
	assert_true(model.province_data(1).hospital_staffed, "the field station keeps its staff")

	var full: Dictionary = HospitalRules.feed(world, 0, 6)
	assert_eq(int(full["spent"]), 6)
	assert_eq((full["hungry"] as Array).size(), 0)
	assert_true(model.province_data(0).hospital_staffed, "a fed ward is staffed again")



func test_the_consumption_phase_feeds_the_wards_after_the_workers() -> void:
	var stock: Dictionary = {"grain": 3, "meat": 0}
	var report: Dictionary = EconomyConsumption.resolve(WorkerPool.make(1), stock, 0, 0, [2])
	assert_eq(int(report["hospital_demand"]), 2)
	assert_eq(int(report["hospital_fed"]), 2, "one peasant, then one field hospital")
	assert_false(bool(report["hospital_hungry"]))
	assert_eq(int(stock.get("grain", 0)), 0)
	assert_eq(int(report["food_eaten"]), 3)

	var larder: Dictionary = {"grain": 9, "meat": 0}
	var fed: Dictionary = EconomyConsumption.resolve(WorkerPool.make(0), larder, 0, 0, [4])
	assert_eq(int(fed["hospital_fed"]), 4)
	assert_false(bool(fed["hospital_hungry"]))
	assert_eq(int(larder.get("grain", 0)), 5)

	# A general hospital needs four rations: two left over are no half staff,
	# so the ward goes without and the larder keeps them (DR-20261112-04).
	var short: Dictionary = {"grain": 2, "meat": 0}
	var hungry: Dictionary = EconomyConsumption.resolve(WorkerPool.make(0), short, 0, 0, [4])
	assert_eq(int(hungry["hospital_fed"]), 0, "no half ration for a great ward")
	assert_true(bool(hungry["hospital_hungry"]))
	assert_eq(int(short.get("grain", 0)), 2, "the larder keeps what no staff can use")


## Playtest: a field hospital at the seat and a general hospital elsewhere, with
## four rations left after the living. The seat eats two, the great ward cannot
## be seated on the two that remain, and those two stay in the larder — a ration
## is never stranded on a ward that cannot be staffed (DR-20261112-04).



## Playtest: a field hospital at the seat and a general hospital elsewhere, with
## four rations left after the living. The seat eats two, the great ward cannot
## be seated on the two that remain, and those two stay in the larder — a ration
## is never stranded on a ward that cannot be staffed (DR-20261112-04).
func test_the_consumption_never_strands_a_ration_on_an_unstaffable_ward() -> void:
	var world := WorldMap.new()
	var model := hospital_rules_Fixture.build()
	world.add_region(model)
	model.province_data(0).hospital_level = 1
	model.province_data(1).hospital_level = 2
	var demands: Array[int] = HospitalRules.demand_list(world, 0)
	assert_eq(demands.size(), 2, "seat first, then the chart's order")
	assert_eq(demands[0], 2, "the seat's field hospital")
	assert_eq(demands[1], 4, "the great ward elsewhere")

	var stock: Dictionary = {"grain": 4, "meat": 0}
	var report: Dictionary = EconomyConsumption.resolve(
		WorkerPool.make(0), stock, 0, 0, demands
	)
	assert_eq(int(report["hospital_demand"]), 6)
	assert_eq(int(report["hospital_fed"]), 2, "only the seat's staff can be seated")
	assert_eq(int(stock.get("grain", 0)), 2, "the rest of the larder is not eaten")

	var fed: Dictionary = HospitalRules.feed(world, 0, int(report["hospital_fed"]))
	assert_eq(int(fed["spent"]), 2, "the larder paid exactly what the staffs ate")
	assert_true(model.province_data(0).hospital_staffed)
	assert_false(model.province_data(1).hospital_staffed)
	assert_eq((fed["hungry"] as Array), [1] as Array)


## The food the larder pays and the staffs it seats are one walk: for every
## larder size, the consumption pass eats exactly what [method HospitalRules.feed]
## spends (DR-20261112-04).



## The food the larder pays and the staffs it seats are one walk: for every
## larder size, the consumption pass eats exactly what [method HospitalRules.feed]
## spends (DR-20261112-04).
func test_the_ration_and_the_staffing_agree_at_every_larder_size() -> void:
	var world := WorldMap.new()
	var model := hospital_rules_Fixture.build()
	world.add_region(model)
	model.province_data(0).hospital_level = 1
	model.province_data(1).hospital_level = 2
	var demands: Array[int] = HospitalRules.demand_list(world, 0)
	for available in 9:
		var stock: Dictionary = {"grain": available, "meat": 0}
		var report: Dictionary = EconomyConsumption.resolve(
			WorkerPool.make(0), stock, 0, 0, demands
		)
		var fed: Dictionary = HospitalRules.feed(world, 0, int(report["hospital_fed"]))
		assert_eq(
			int(fed["spent"]), int(report["hospital_fed"]),
			"larder %d: the food paid is the food seated" % available
		)
		assert_eq(int(stock.get("grain", 0)), available - int(fed["spent"]))



func test_a_save_round_trip_keeps_an_unfed_ward() -> void:
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = 2
	model.province_data(2).hospital_staffed = false
	var world := WorldMap.new()
	world.add_region(model)

	var captured: Array[Dictionary] = SaveWorld.capture(world)
	model.province_data(2).hospital_staffed = true
	assert_true(SaveWorld.apply(world, captured))
	assert_false(model.province_data(2).hospital_staffed)

	# A save written before the wards ate carries no flag: its staffs are fed.
	for region: Variant in captured:
		for entry: Variant in (region as Dictionary).get("provinces", []) as Array:
			(entry as Dictionary).erase("hospital_staffed")
	assert_true(SaveWorld.apply(world, captured))
	assert_true(model.province_data(2).hospital_staffed)



func test_the_army_dossier_names_an_unstaffed_ward() -> void:
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = 1
	var army := hospital_rules_Fixture.army(1, 0, 2, ["guards"])
	var panel := ArmyPanel.new()
	add_child(panel)

	panel.refresh(model, ArmyDossierOpening.of(army, true))
	assert_true(String(panel._strength.text).contains("rest 40%"), panel._strength.text)

	# A ward whose staff went unfed heals at the field's rate, and the dossier
	# says why (wiki: combat § Regiment condition; DR-20261112-04).
	model.province_data(2).hospital_staffed = false
	panel.refresh(model, ArmyDossierOpening.of(army, true))
	assert_true(
		String(panel._strength.text).contains("hospital unstaffed"), panel._strength.text
	)
	assert_false(String(panel._strength.text).contains("rest 40%"))
	panel.free()


# --- the field hospital train (DR-20261112-07) --------------------------------

func test_the_train_table_follows_the_design_record() -> void:
	assert_almost_eq(HospitalTrain.REST_SHARE, 0.40, 0.001)
	assert_eq(HospitalTrain.food(), 2)
	assert_eq(HospitalTrain.tech(), "organised_regiments")
	assert_eq(HospitalTrain.cost(), {"lumber": 2, "fabric": 1})
	assert_true(HospitalTrain.describe().contains("rest 40%"))
	assert_true(HospitalTrain.describe().contains("staff 2 food"))


func test_the_better_of_the_tents_and_the_ward_sets_the_tempo() -> void:
	var model := hospital_rules_Fixture.build()
	assert_almost_eq(HospitalTrain.army_rest_share(model, 1, false), 0.25, 0.001)
	assert_almost_eq(HospitalTrain.army_rest_share(model, 1, true), 0.40, 0.001)
	model.province_data(1).hospital_level = 2
	assert_almost_eq(
		HospitalTrain.army_rest_share(model, 1, true), 0.55, 0.001,
		"the ward's nurses still beat the tents"
	)
	var no_model: MapModel = null
	assert_almost_eq(
		HospitalTrain.army_rest_share(no_model, MapModel.NO_ID, true), 0.40, 0.001,
		"a train heals with no map at all"
	)


func test_the_train_speeds_the_rest_wherever_the_army_stands() -> void:
	var model := hospital_rules_Fixture.build()
	var army := hospital_rules_Fixture.army(1, 0, 1, ["pikemen"])
	var regiment: String = army.regiments[0]
	army.regiment_health[regiment] = 55
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 83, "a bare field restores a quarter")

	army.field_hospital = true
	army.regiment_health[regiment] = 55
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 99, "the train restores 40%")

	# Enemy land: the tents travel with the standard, not the province.
	army.province = 2
	army.regiment_health[regiment] = 55
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 99)


func test_the_trains_staff_eat_with_the_men() -> void:
	var plain := hospital_rules_Fixture.army(1, 0, 1, ["pikemen"])
	var train := hospital_rules_Fixture.army(2, 0, 1, ["pikemen"])
	train.field_hospital = true
	var bare: int = ArmyRoster.food_upkeep_of([plain], 0)
	assert_eq(ArmyRoster.food_upkeep_of([train], 0), bare + 2)
	assert_eq(ArmyRoster.food_upkeep_of([train], 1), 0, "another crown pays nothing")


func test_a_train_is_pitched_on_the_crowns_own_land() -> void:
	var model := hospital_rules_Fixture.build()
	var army := hospital_rules_Fixture.army(1, 0, 1, ["pikemen"])
	var tech: Dictionary = {"organised_regiments": true}
	var stock: Dictionary = {"lumber": 2, "fabric": 1}
	assert_true(bool(HospitalTrain.check(model, army, tech, stock)["ok"]))

	assert_false(bool(HospitalTrain.check(null, army, tech, stock)["ok"]))
	assert_false(bool(HospitalTrain.check(model, null, tech, stock)["ok"]))

	var foreign := hospital_rules_Fixture.army(2, 0, 2, ["pikemen"])
	var check: Dictionary = HospitalTrain.check(model, foreign, tech, stock)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("own land"))

	var embarked := hospital_rules_Fixture.army(3, 0, 1, ["pikemen"])
	embarked.embarked_fleet = 7
	assert_false(bool(HospitalTrain.check(model, embarked, tech, stock)["ok"]))

	var carrying := hospital_rules_Fixture.army(4, 0, 1, ["pikemen"])
	carrying.field_hospital = true
	assert_false(bool(HospitalTrain.check(model, carrying, tech, stock)["ok"]))

	var empty := hospital_rules_Fixture.army(5, 0, 1, [])
	assert_false(bool(HospitalTrain.check(model, empty, tech, stock)["ok"]))

	var locked: Dictionary = HospitalTrain.check(model, army, {}, stock)
	assert_false(bool(locked["ok"]))
	assert_true(String(locked["reason"]).contains("Organised Regiments"))

	var short: Dictionary = HospitalTrain.check(model, army, tech, {"lumber": 1})
	assert_false(bool(short["ok"]))

	# Pitching changes only the standard that carries it.
	HospitalTrain.apply(army)
	assert_true(army.field_hospital)


func test_a_train_stays_with_its_standard_through_split_and_combine() -> void:
	var army := ArmyState.muster(1, 0, 1, false, ["pikemen", "pikemen"])
	army.field_hospital = true
	var armies: Array[ArmyState] = [army]
	var split: Dictionary = ArmyRoster.split(armies, army, [army.regiments[0]], 2)
	assert_true(bool(split["ok"]))
	var detached: ArmyState = split["army"]
	assert_true(army.field_hospital, "the parent standard keeps the tents")
	assert_false(detached.field_hospital)

	# A full detach drops the emptied standard, and the train marches with the men.
	var rest: Array[ArmyState] = [army]
	var all_out: Dictionary = ArmyRoster.split(
		rest, army, army.regiments.duplicate(), 3
	)
	assert_true(bool(all_out["ok"]))
	var moved: ArmyState = all_out["army"]
	assert_eq(rest.size(), 1)
	assert_true(moved.field_hospital)

	var other := ArmyState.muster(4, 0, 1, false, ["pikemen"])
	var pair: Array[ArmyState] = [moved, other]
	var combined: Dictionary = ArmyRoster.combine(pair, pair)
	assert_true(bool(combined["ok"]))
	assert_true((combined["army"] as ArmyState).field_hospital, "one train survives")
	assert_eq(pair.size(), 1)


func test_the_train_rides_in_the_save_and_an_old_save_has_none() -> void:
	var army := ArmyState.muster(1, 0, 1, false, ["pikemen"])
	HospitalTrain.apply(army)
	var restored: ArmyState = ArmyState.from_dict(army.to_dict())
	assert_true(restored.field_hospital)
	var legacy: ArmyState = ArmyState.from_dict({"id": 2, "owner": 0, "province": 1})
	assert_false(legacy.field_hospital)


func test_the_dossier_offers_the_train_and_then_names_it() -> void:
	var model := hospital_rules_Fixture.build()
	var army := hospital_rules_Fixture.army(1, 0, 1, ["guards"])
	var panel := ArmyPanel.new()
	add_child(panel)

	var order: Dictionary = {"caption": "Pitch a field hospital (2 lumber · 1 fabric)", "ok": true}
	var opening := ArmyDossierOpening.of(army, true)
	opening.hospital = order
	panel.refresh(model, opening)
	assert_true(panel._hospital.visible)
	assert_false(panel._hospital.disabled)
	var bare_food: int = panel._food(army)

	# A blocked order still shows, with the rules' reason as its caption.
	var blocked := ArmyDossierOpening.of(army, true)
	blocked.hospital = {"caption": "Tents are pitched on your crown's own land.", "ok": false}
	panel.refresh(model, blocked)
	assert_true(panel._hospital.visible)
	assert_true(panel._hospital.disabled)

	HospitalTrain.apply(army)
	panel.refresh(model, ArmyDossierOpening.of(army, true))
	assert_true(String(panel._strength.text).contains("field hospital"), panel._strength.text)
	assert_false(panel._hospital.visible, "a served order is gone, not disabled")
	# The strength line's food is the army's own upkeep line, nurses included.
	assert_eq(panel._food(army), bare_food + HospitalTrain.food())
	assert_true(
		String(panel._strength.text).contains("%d food" % (bare_food + HospitalTrain.food())),
		panel._strength.text
	)
	panel.free()

# --- test_army_field_rules ---

func test_owned_provinces_are_reachable_and_enemy_land_must_border() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var expected: Array[int] = [1, 2, 6]
	assert_eq(ArmyMovement.destinations(_army_field_rules_model, army), expected)

func test_owned_island_across_water_is_not_a_land_destination() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var destinations: Array[int] = ArmyMovement.destinations(_army_field_rules_model, army)
	assert_false(destinations.has(5))
	var check: Dictionary = ArmyMovement.can_move(_army_field_rules_model, army, 5)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("water"))
	assert_false(ArmyMovement.land_reachable(_army_field_rules_model, 0, 0).has(5))
	assert_true(ArmyMovement.land_reachable(_army_field_rules_model, 0, 0).has(1))

func test_destinations_from_the_far_colony_reach_both_neighbours() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 1, ["pikemen"])
	var expected: Array[int] = [0, 3, 4, 6]
	assert_eq(ArmyMovement.destinations(_army_field_rules_model, army), expected)

func test_the_home_army_never_marches() -> void:
	_setup_army_field_rules()
	var home := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"], true)
	var none: Array[int] = []
	assert_eq(ArmyMovement.destinations(_army_field_rules_model, home), none)
	var check: Dictionary = ArmyMovement.can_move(_army_field_rules_model, home, 1)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Home Army"))

func test_a_moved_army_has_no_march_left() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	army.moved = true
	var none: Array[int] = []
	assert_eq(ArmyMovement.destinations(_army_field_rules_model, army), none)
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, army, 1)["ok"]))

func test_empty_armies_cannot_march() -> void:
	_setup_army_field_rules()
	var none: Array[String] = []
	var army := army_field_rules_Fixture.army(1, 0, 0, none)
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, army, 1)["ok"]))

func test_owned_destination_anywhere_is_legal_even_without_adjacency() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	assert_true(bool(ArmyMovement.can_move(_army_field_rules_model, army, 1)["ok"]))

func test_neutral_or_enemy_land_far_away_is_refused() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, army, 3)["ok"]))
	assert_true(bool(ArmyMovement.can_move(_army_field_rules_model, army, 2)["ok"]))

func test_foreign_land_needs_war_but_wilderness_does_not() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var refused: Dictionary = ArmyMovement.can_move(_army_field_rules_model, army, 2, false)
	assert_false(bool(refused["ok"]), "province 2 belongs to faction 1")
	assert_true(String(refused["reason"]).contains("declare war"))
	assert_true(bool(ArmyMovement.can_move(_army_field_rules_model, army, 2, true)["ok"]))
	var colonist := army_field_rules_Fixture.army(2, 0, 1, ["pikemen"])
	assert_true(
		bool(ArmyMovement.can_move(_army_field_rules_model, colonist, 3, false)["ok"]),
		"unowned wilderness beside the colony is not an invasion"
	)
	var march: Dictionary = ArmyMovement.apply_move(_army_field_rules_model, army, 2, false)
	assert_false(bool(march["ok"]))
	assert_eq(army.province, 0)
	assert_false(army.moved)

func test_invalid_and_current_provinces_are_refused() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, army, 0)["ok"]))
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, army, 99)["ok"]))
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, null, 1)["ok"]))

func test_apply_move_reports_an_attack_and_spends_the_turn() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var result: Dictionary = ArmyMovement.apply_move(_army_field_rules_model, army, 2)
	assert_true(bool(result["ok"]))
	assert_true(bool(result["attacked"]))
	assert_eq(army.province, 2)
	assert_true(army.moved)

func test_apply_move_into_own_land_is_not_an_attack() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var result: Dictionary = ArmyMovement.apply_move(_army_field_rules_model, army, 1)
	assert_true(bool(result["ok"]))
	assert_false(bool(result["attacked"]))

func test_begin_turn_restores_one_march() -> void:
	_setup_army_field_rules()
	var first := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var second := army_field_rules_Fixture.army(2, 0, 1, ["pikemen"])
	first.moved = true
	second.moved = true
	var armies: Array[ArmyState] = [first, second]
	ArmyMovement.begin_turn(armies)
	assert_false(first.moved)
	assert_false(second.moved)

func test_side_strength_aggregates_fpn_and_fpm() -> void:
	_setup_army_field_rules()
	var first := army_field_rules_Fixture.army(1, 0, 0, ["pikemen", "pikemen"])
	var second := army_field_rules_Fixture.army(2, 0, 0, ["squires"])
	var side: Array[ArmyState] = [first, second]
	assert_almost_eq(ArmyForce.side_strength(side), 14.0, 0.001)
	assert_eq(ArmyForce.side_regiments(side), 3)
	assert_almost_eq(ArmyCommand.initiative(side), 50.0 / 3.0, 0.001)

## One walk over a side: army by army, roster order, an empty slot skipped, so
## every reader that scans a battle side names the same regiments in one order
## (REQ-P3-01).
func test_a_side_walks_its_regiments_army_by_army() -> void:
	_setup_army_field_rules()
	var first := army_field_rules_Fixture.army(1, 0, 0, ["pikemen", "pikemen"])
	var second := army_field_rules_Fixture.army(2, 0, 0, ["squires"])
	var side: Array[ArmyState] = [first, null, second]
	var entries: Array[Dictionary] = ArmyForce.side_entries(side)
	assert_eq(entries.size(), 3)
	assert_true(entries[0]["army"] == first)
	assert_eq(String(entries[0]["id"]), first.regiments[0])
	assert_eq(String(entries[0]["type"]), "pikemen")
	assert_eq(String(entries[1]["type"]), "pikemen")
	assert_true(entries[2]["army"] == second)
	assert_eq(String(entries[2]["type"]), "squires")
	var types: Array[String] = ArmyForce.side_types(side)
	assert_eq(types.size(), 3)
	assert_eq(types[0], "pikemen")
	assert_eq(types[2], "squires")
	var none: Array[ArmyState] = []
	assert_true(ArmyForce.side_entries(none).is_empty())

func test_contested_provinces_need_a_great_power_mover() -> void:
	_setup_army_field_rules()
	var attacker := army_field_rules_Fixture.army(1, 0, 2, ["pikemen"])
	attacker.moved = true
	var minor := army_field_rules_Fixture.army(2, 6, 2, ["pikemen"])
	minor.moved = true
	var idle := army_field_rules_Fixture.army(3, 0, 3, ["pikemen"])
	var armies: Array[ArmyState] = [attacker, minor, idle]
	var expected: Array[int] = [2]
	assert_eq(ArmyCombat.contested_provinces(_army_field_rules_model, armies), expected)

func test_unopposed_capture_flips_the_province() -> void:
	_setup_army_field_rules()
	var attacker := army_field_rules_Fixture.army(1, 0, 2, ["peasant_levies", "pikemen"])
	attacker.moved = true
	var armies: Array[ArmyState] = [attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(reports.size(), 1)
	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.CAPTURE)
	assert_true(bool(reports[0]["captured"]))
	assert_eq(_army_field_rules_model.province_owner(2), 0)
	assert_eq(attacker.count(), 2)

func test_a_third_faction_blocks_an_unopposed_capture() -> void:
	_setup_army_field_rules()
	var attacker := army_field_rules_Fixture.army(1, 0, 2, ["pikemen"])
	attacker.moved = true
	var third := army_field_rules_Fixture.army(2, 2, 2, ["pikemen"])
	var armies: Array[ArmyState] = [attacker, third]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(reports.size(), 0)
	assert_eq(_army_field_rules_model.province_owner(2), 1)

func test_attacker_victory_eliminates_the_home_army_and_flips() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := army_field_rules_Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_true(bool(reports[0]["captured"]))
	assert_eq(_army_field_rules_model.province_owner(2), 0)
	assert_eq(defender.count(), 0)
	assert_true(armies.has(defender))
	assert_gt(attacker.count(), 0)

func test_defender_victory_wipes_the_attacker_without_a_flip() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["guards", "guards", "guards", "guards", "guards"])
	var attacker := army_field_rules_Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_eq(_army_field_rules_model.province_owner(2), 1)
	assert_false(armies.has(attacker))
	assert_gt(defender.count(), 0)

func test_matched_large_armies_stalemate() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, _army_field_rules_repeat("peasant_levies", 10))
	var attacker := army_field_rules_Fixture.army(2, 0, 2, _army_field_rules_repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.STALEMATE)
	assert_eq(_army_field_rules_model.province_owner(2), 1)
	assert_gt(defender.count(), 0)
	assert_gt(attacker.count(), 0)

func test_defending_armies_share_one_side() -> void:
	_setup_army_field_rules()
	var first := army_field_rules_Fixture.army(1, 1, 2, ["peasant_levies", "peasant_levies"])
	var second := army_field_rules_Fixture.army(2, 1, 2, ["peasant_levies", "peasant_levies"])
	var side: Array[ArmyState] = ArmyForce.armies_of([first, second], 2, 1)
	assert_almost_eq(ArmyForce.side_strength(side), 12.0, 0.001)
	assert_eq(ArmyForce.side_regiments(side), 4)

func test_cavalry_wins_the_initiative_order() -> void:
	_setup_army_field_rules()
	var foot := army_field_rules_Fixture.army(1, 1, 3, ["peasant_levies"])
	foot.moved = true
	var horse := army_field_rules_Fixture.army(2, 2, 3, ["squires"])
	horse.moved = true
	var armies: Array[ArmyState] = [foot, horse]
	var expected: Array[int] = [2, 1]
	assert_eq(ArmyCombat.ordered_attackers(armies, 3, MapModel.NO_ID), expected)

func test_equal_initiative_is_broken_by_a_seeded_battle_roll() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["peasant_levies"])
	var lower := army_field_rules_Fixture.army(2, 2, 2, ["pikemen"])
	lower.moved = true
	var higher := army_field_rules_Fixture.army(3, 0, 2, ["pikemen"])
	higher.moved = true
	var armies: Array[ArmyState] = [defender, lower, higher]

	# Same initiative: the wiki wants one deterministic roll per battle context,
	# not the lexical faction id (combat § Initiative, § Multi-Attacker Chain).
	var first: Array[int] = ArmyCombat.ordered_attackers(armies, 2, 1, {"seed": 0})
	var again: Array[int] = ArmyCombat.ordered_attackers(armies, 2, 1, {"seed": 0})
	var other: Array[int] = ArmyCombat.ordered_attackers(armies, 2, 1, {"seed": 1})

	assert_eq(first, again, "identical state reproduces the same chain order")
	assert_eq(first, [2, 0], "the seeded roll, not faction id, decides the tie")
	assert_eq(other, [0, 2], "a different combat seed may flip the tied order")
	assert_eq(ArmyCombat.ordered_attackers(armies, 2, 1), first, "the default seed is 0")

func test_general_medals_add_to_initiative() -> void:
	_setup_army_field_rules()
	var horse: Array[ArmyState] = [army_field_rules_Fixture.army(1, 0, 3, ["squires"])]
	assert_almost_eq(ArmyCommand.initiative(horse), 50.0, 0.001)
	assert_almost_eq(ArmyCommand.initiative(horse, 2), 70.0, 0.001)

func test_medal_aura_redistributes_casualties() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, _army_field_rules_repeat("peasant_levies", 10))
	var attacker := army_field_rules_Fixture.army(2, 0, 2, _army_field_rules_repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	for _index in 4:
		roster.award(0, "general_1")
	var context: Dictionary = {"roster": roster, "army_general": {attacker.id: "general_1"}}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies, context)

	assert_eq(int(reports[0]["attacker_medals"]), 4)
	assert_gt(
		(reports[0]["defender_lost"] as Array).size(),
		(reports[0]["attacker_lost"] as Array).size()
	)

func test_mutual_annihilation_recovers_a_garrison_for_the_next_attacker() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["guards"], true)
	var first := army_field_rules_Fixture.army(2, 0, 2, ["peasant_levies"])
	first.moved = true
	var second := army_field_rules_Fixture.army(3, 2, 2, ["peasant_levies"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.MUTUAL_ANNIHILATION)
	assert_eq(int(reports[0]["garrison"]), 1)
	assert_eq(String(reports[0]["recovered_type"]), "guards")
	assert_eq(_army_field_rules_model.province_owner(2), 1)

func test_mutual_annihilation_without_further_attackers_leaves_the_province_empty() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["guards"], true)
	var attacker := army_field_rules_Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.MUTUAL_ANNIHILATION)
	assert_eq(int(reports[0]["garrison"]), 0)
	assert_eq(_army_field_rules_model.province_owner(2), 1)
	assert_eq(defender.count(), 0)

## A Minor Nation reforms its garrison at its effective military era, which the
## Minor Regiment Upgrade phase sets to the leading Great Power's level (wiki:
## combat § Garrison recovery type; factions § Minor military parity).
func test_a_minor_nations_reformed_garrison_keeps_its_parity_era() -> void:
	_setup_army_field_rules()
	_army_field_rules_model.get_province(2).owner = 6
	var defender := army_field_rules_Fixture.army(1, 6, 2, ["guards"], true)
	var first := army_field_rules_Fixture.army(2, 0, 2, ["peasant_levies"])
	first.moved = true
	var second := army_field_rules_Fixture.army(3, 2, 2, ["peasant_levies"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]
	var context: Dictionary = {"parity_era": 4}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.MUTUAL_ANNIHILATION)
	assert_eq(int(reports[0]["garrison"]), 1)
	assert_eq(String(reports[0]["recovered_type"]), "guards")

## Tribes get no parity: their effective military era is always 1 (wiki:
## combat § Garrison recovery type; factions § Tribes).
func test_a_tribes_reformed_garrison_stays_at_era_one() -> void:
	_setup_army_field_rules()
	_army_field_rules_model.get_province(2).owner = 9
	var defender := army_field_rules_Fixture.army(1, 9, 2, ["guards"], true)
	var first := army_field_rules_Fixture.army(2, 0, 2, ["peasant_levies"])
	first.moved = true
	var second := army_field_rules_Fixture.army(3, 2, 2, ["peasant_levies"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]
	var context: Dictionary = {"parity_era": 4}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies, context)

	assert_eq(int(reports[0]["garrison"]), 1)
	assert_eq(String(reports[0]["recovered_type"]), RegimentCatalog.garrison_type_for(1))

func test_recovery_era_follows_the_faction_type() -> void:
	_setup_army_field_rules()
	assert_eq(ArmyGarrison.era_for(1, {"parity_era": 1}), ArmyGarrison.GREAT_POWER_ERA)
	assert_eq(ArmyGarrison.era_for(6, {"parity_era": 3}), 3)
	assert_eq(ArmyGarrison.era_for(6, {}), ArmyGarrison.MINOR_ERA)
	assert_eq(ArmyGarrison.era_for(9, {"parity_era": 4}), ArmyGarrison.MINOR_ERA)

func test_ratio_bands_follow_the_documented_fractions() -> void:
	_setup_army_field_rules()
	assert_almost_eq(float(ArmyBands.for_ratio(2.0)["attacker"]), 0.15, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(2.0)["defender"]), 1.0, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(1.2)["attacker"]), 0.3, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(0.8)["attacker"]), 0.5, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(0.5)["attacker"]), 1.0, 0.001)

func test_the_067_boundary_belongs_to_the_defender_victory_band() -> void:
	_setup_army_field_rules()
	# wiki: combat § Auto-resolve ratio bands — `ratio <= 0.67` loses 1.0/0.15,
	# while the `0.67 < ratio < 1.0` row starts strictly above 0.67.
	assert_almost_eq(float(ArmyBands.for_ratio(0.67)["attacker"]), 1.0, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(0.67)["defender"]), 0.15, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(0.68)["attacker"]), 0.5, 0.001)

func test_great_powers_recover_era_four_infantry() -> void:
	_setup_army_field_rules()
	assert_eq(ArmyGarrison.era_for(0), ArmyGarrison.GREAT_POWER_ERA)
	assert_eq(ArmyGarrison.era_for(6), ArmyGarrison.MINOR_ERA)
	assert_eq(ArmyGarrison.era_for(9), ArmyGarrison.MINOR_ERA)

func test_outcome_labels_cover_every_result() -> void:
	_setup_army_field_rules()
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.ATTACKER_VICTORY), "attacker victory")
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.DEFENDER_VICTORY), "defender victory")
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.STALEMATE), "stalemate")
	assert_eq(
		ArmyCombat.outcome_label(ArmyCombat.Outcome.MUTUAL_ANNIHILATION),
		"mutual annihilation"
	)
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.CAPTURE), "province captured")

func test_peaceful_factions_do_not_fight() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := army_field_rules_Fixture.army(2, 0, 2, ["guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var at_peace := func(_a: int, _b: int) -> bool: return false

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(
		_army_field_rules_model, armies, {"hostile": at_peace}
	)

	assert_eq(reports.size(), 0, "peace holds: no battle, no capture")
	assert_eq(_army_field_rules_model.province_owner(2), 1)
	assert_eq(attacker.count(), 3)
	assert_eq(defender.count(), 1)
	var at_war := func(_a: int, _b: int) -> bool: return true
	var battles: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies, {"hostile": at_war})
	assert_eq(battles.size(), 1, "declared war fights")
	assert_eq(_army_field_rules_model.province_owner(2), 0)

func _army_field_rules_repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types

func test_each_military_tech_names_the_type_its_regiment_replaces() -> void:
	_setup_army_field_rules()
	var expected: Dictionary = {
		"organised_regiments": ["knights", "lancers"],
		"improved_iron_weapons": ["pikemen", "halberdiers"],
		"improved_infantry_tactics": ["peasant_levies", "calivermen"],
		"bayonet": ["halberdiers", "regulars"],
		"weapon_craftsmanship": ["arquebusiers", "musketeers"],
		"explosives": ["musketeers", "grenadiers"],
		"early_rifles": ["calivermen", "skirmishers"],
		"long_range_rifles": ["skirmishers", "sharpshooters"],
		"needle_guns": ["regulars", "rifle_infantry"],
		"elite_military_training": ["grenadiers", "guards"],
		"recruit_steppe_horsemen": ["squires", "cossacks"],
		"hussars": ["cossacks", "hussars"],
		"scouting": ["hussars", "scouts"],
		"improved_cavalry_weapons": ["harquebusiers", "cuirassiers"],
		"repeating_cavalry_carbine": ["cuirassiers", "carbine_cavalry"],
		"siege_engineering": ["culverin", "royal_artillery"],
		"light_artillery_tactics": ["horse_artillery", "light_artillery"],
		"heavy_artillery": ["royal_artillery", "heavy_artillery"],
		"field_artillery_tactics": ["light_artillery", "field_artillery"],
		"high_grade_steel": ["heavy_artillery", "siege_guns"],
	}
	for tech_id: Variant in expected.keys():
		var path: Dictionary = RegimentUpgrades.path_for(String(tech_id))
		var pair: Array = expected[tech_id]
		assert_eq(String(path.get("from", "")), String(pair[0]), String(tech_id))
		assert_eq(String(path.get("to", "")), String(pair[1]), String(tech_id))
		assert_eq(
			String(path.get("name", "")),
			"%s upgrade path" % RegimentCatalog.display_name(String(pair[0])),
			String(tech_id)
		)

func test_the_first_type_of_a_branch_and_its_dependants_open_no_path() -> void:
	_setup_army_field_rules()
	assert_true(RegimentUpgrades.path_for("improved_cavalry_tactics").is_empty())
	assert_true(RegimentUpgrades.path_for("horse_artillery").is_empty())
	assert_true(RegimentUpgrades.path_for("crucible_process").is_empty())
	assert_true(RegimentUpgrades.path_for("modern_forts").is_empty())
	assert_true(RegimentUpgrades.path_for("").is_empty())

func test_bowmen_knights_and_lancers_sit_at_the_top_of_their_ladders() -> void:
	_setup_army_field_rules()
	assert_eq(RegimentUpgrades.previous_type("bowmen"), "")
	assert_eq(RegimentUpgrades.previous_type("lancers"), "knights")
	assert_eq(RegimentUpgrades.previous_type("scouts"), "hussars")
	assert_eq(RegimentUpgrades.previous_type("not_a_regiment"), "")

func test_the_newest_buildable_type_in_the_category_wins() -> void:
	_setup_army_field_rules()
	assert_eq(RegimentUpgrades.target_type("pikemen", {}), "pikemen")
	assert_eq(
		RegimentUpgrades.target_type("pikemen", {"improved_iron_weapons": true}),
		"halberdiers"
	)
	assert_eq(
		RegimentUpgrades.target_type(
			"pikemen", {"improved_iron_weapons": true, "bayonet": true}
		),
		"regulars",
		"a court never stops at the first rung"
	)
	assert_eq(
		RegimentUpgrades.target_type("squires", {"bayonet": true}),
		"squires",
		"another branch's research never re-equips this one"
	)

func test_apply_re_equips_great_power_regiments_in_place() -> void:
	_setup_army_field_rules()
	var power: int = FactionCatalog.PLAYER_FACTION
	var other: int = FactionCatalog.great_power_ids()[1]
	var regions := MapRegionTable.new()
	var army: ArmyState = ArmyState.muster(1, power, 0, true, ["pikemen", "bowmen"], 1)
	var rival: ArmyState = ArmyState.muster(2, other, 0, true, ["squires"], 10)
	regions.set_region(0, [army, rival])

	var pikemen: String = army.regiments[0]
	var bowmen: String = army.regiments[1]
	var squires: String = rival.regiments[0]
	var report: Dictionary = RegimentUpgrades.apply(regions, {
		power: {"improved_iron_weapons": true},
		other: {"recruit_steppe_horsemen": true},
	})

	assert_eq(int(report["count"]), 2)
	assert_eq(int((report["by_faction"] as Dictionary).get(power, 0)), 1)
	assert_eq(army.type_of(pikemen), "halberdiers")
	assert_eq(army.type_of(bowmen), "bowmen", "bowmen have no upgrade path")
	assert_eq(rival.type_of(squires), "cossacks", "rivals re-equip off their own techs")
	assert_eq(army.regiments, [pikemen, bowmen], "instance ids never change")

func test_a_re_equipped_regiment_keeps_its_health_inside_the_new_pool() -> void:
	_setup_army_field_rules()
	var power: int = FactionCatalog.PLAYER_FACTION
	var whole: ArmyState = ArmyState.muster(1, power, 0, true, ["pikemen"], 1)
	var mauled: ArmyState = ArmyState.muster(2, power, 0, false, ["pikemen"], 10)
	var veteran: String = mauled.regiments[0]
	mauled.regiment_health[veteran] = RegimentCatalog.max_health("pikemen") / 2
	var regions := MapRegionTable.new()
	regions.set_region(0, [whole, mauled])

	RegimentUpgrades.apply(regions, {power: {"improved_iron_weapons": true}})

	for army: ArmyState in [whole, mauled]:
		var data: Dictionary = army.condition_of(army.regiments[0])
		assert_eq(String(data["type"]), "halberdiers")
		assert_eq(
			int(data["max"]), RegimentCatalog.max_health("halberdiers"),
			"the pool is the new type's, not the old one kept by a stale max"
		)
	assert_eq(
		int(whole.condition_of(whole.regiments[0])["hp"]),
		RegimentCatalog.max_health("halberdiers"),
		"an untouched regiment re-equips at full strength"
	)
	assert_true(
		float(mauled.condition_of(veteran)["fraction"]) < 1.0,
		"a mauled veteran keeps its wounds through the re-equip"
	)


func test_apply_skips_minors_tribes_and_courts_with_nothing_new() -> void:
	_setup_army_field_rules()
	var minor: int = FactionCatalog.minor_ids()[0]
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var power: int = FactionCatalog.PLAYER_FACTION
	var regions := MapRegionTable.new()
	var minor_army: ArmyState = ArmyState.muster(1, minor, 0, true, ["pikemen"], 1)
	var tribe_army: ArmyState = ArmyState.muster(2, tribe, 0, true, ["pikemen"], 10)
	var power_army: ArmyState = ArmyState.muster(3, power, 0, true, ["pikemen"], 20)
	regions.set_region(0, [minor_army, tribe_army, power_army])

	var report: Dictionary = RegimentUpgrades.apply(regions, {
		power: {"bayonet": true},
		minor: {"bayonet": true},
		tribe: {"bayonet": true},
	})

	assert_eq(int(report["count"]), 1)
	assert_eq(power_army.type_of(power_army.regiments[0]), "regulars")
	assert_eq(
		minor_army.type_of(minor_army.regiments[0]), "pikemen",
		"Minors follow the parity pass"
	)
	assert_eq(tribe_army.type_of(tribe_army.regiments[0]), "pikemen")
	assert_eq(int(RegimentUpgrades.apply(null, {})["count"]), 0)

# --- test_army_regiment_names ---

func test_every_muster_names_its_regiments_from_the_crown_pool() -> void:
	var army := ArmyState.muster(1, 0, 2, false, ["pikemen", "musketeers"], 1)

	for regiment_id: String in army.regiments:
		var title: String = RegimentNames.of(army, regiment_id)
		assert_false(title.is_empty(), "a mustered regiment is never anonymous")
		assert_true(
			RegimentNames.pool_for(0).has(title),
			"Spain christens from its own pool, got '%s'" % title
		)

func test_a_reload_speaks_the_same_titles() -> void:
	var army := ArmyState.muster(1, 0, 2, false, ["pikemen", "musketeers"], 1)
	var before: Dictionary = {}
	for regiment_id: String in army.regiments:
		before[regiment_id] = RegimentNames.of(army, regiment_id)

	var restored: ArmyState = ArmyState.from_dict(army.to_dict())

	for regiment_id: String in restored.regiments:
		assert_eq(RegimentNames.of(restored, regiment_id), String(before[regiment_id]))

func test_no_army_wears_the_same_title_twice() -> void:
	var army := ArmyState.muster(1, 0, 2, false, [], 1)
	for index in range(14):
		army.add_regiment("unit_%d" % (index + 1), "pikemen")

	var titles: Array[String] = []
	var numbered: bool = false
	for regiment_id: String in army.regiments:
		var title: String = RegimentNames.of(army, regiment_id)
		assert_false(titles.has(title), "'%s' is worn twice" % title)
		if title.ends_with(" II"):
			numbered = true
		titles.append(title)
	# Past the ten-title pool the repeats are numbered, never duplicated.
	assert_true(numbered, "a repeat is numbered, not duplicated")

func test_a_crown_with_no_pool_still_names_its_regiments() -> void:
	var army := ArmyState.muster(1, 9, 2, false, ["peasant_levies"], 1)

	assert_true(RegimentNames.GENERIC.has(RegimentNames.of(army, "unit_1")))

func test_a_detached_regiment_keeps_its_title_and_record() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen", "pikemen"])
	army.regiment_engagements["unit_102"] = 3
	army.regiment_wins["unit_102"] = 2
	var title: String = RegimentNames.of(army, "unit_102")
	var armies: Array[ArmyState] = [army]

	var result: Dictionary = ArmyRoster.split(armies, army, ["unit_102"], 2)

	assert_true(bool(result["ok"]), String(result["reason"]))
	var detached: ArmyState = result["army"] as ArmyState
	assert_eq(RegimentNames.of(detached, "unit_102"), title, "the veteran keeps its title")
	assert_eq(int(RegimentRecord.of(detached, "unit_102")["engagements"]), 3)
	assert_eq(int(RegimentRecord.of(detached, "unit_102")["wins"]), 2)

func test_a_combined_army_keeps_each_regiments_title_and_record() -> void:
	var first := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"], true)
	var second := army_regiment_names_Fixture.army(2, 0, 2, ["musketeers"])
	second.regiment_engagements["unit_201"] = 1
	second.regiment_wins["unit_201"] = 1
	var title: String = RegimentNames.of(second, "unit_201")
	var armies: Array[ArmyState] = [first, second]

	var result: Dictionary = ArmyRoster.combine(armies, [first, second])

	assert_true(bool(result["ok"]), String(result["reason"]))
	var target: ArmyState = result["army"] as ArmyState
	assert_eq(RegimentNames.of(target, "unit_201"), title)
	assert_eq(int(RegimentRecord.of(target, "unit_201")["wins"]), 1)

func test_a_battle_is_written_into_every_survivors_record() -> void:
	var model := army_regiment_names_Fixture.build()
	var defender := army_regiment_names_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := army_regiment_names_Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_false(attacker.is_empty(), "the winner keeps its standing regiments")
	for regiment_id: String in attacker.regiments:
		var record: Dictionary = RegimentRecord.of(attacker, regiment_id)
		assert_eq(int(record["engagements"]), 1, "one engagement is written down")
		assert_eq(int(record["wins"]), 1, "the field was won")
		assert_true(
			RegimentRecord.line(attacker, regiment_id).contains("1 engagement"),
			"the dossier line reads the same tally"
		)

func test_a_standoff_counts_an_engagement_but_no_win() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]

	RegimentRecord.note_battle(side, false)
	RegimentRecord.note_battle(side, true)

	var record: Dictionary = RegimentRecord.of(army, "unit_101")
	assert_eq(int(record["engagements"]), 2)
	assert_eq(int(record["wins"]), 1)

func test_the_dossier_line_is_empty_until_a_regiment_is_blooded() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])

	assert_eq(RegimentRecord.line(army, "unit_101"), "")

	army.regiment_engagements["unit_101"] = 4
	army.regiment_wins["unit_101"] = 3

	assert_eq(RegimentRecord.line(army, "unit_101"), "4 engagements · 3 won")

func test_land_an_old_save_is_christened_on_load() -> void:
	var army := ArmyState.muster(1, 0, 2, false, ["pikemen", "musketeers"], 1)
	var expected: Dictionary = {}
	for regiment_id: String in army.regiments:
		expected[regiment_id] = RegimentNames.of(army, regiment_id)
	var data: Dictionary = army.to_dict()
	data.erase("regiment_names")
	data.erase("regiment_engagements")
	data.erase("regiment_wins")

	var restored: ArmyState = ArmyState.from_dict(data)

	for regiment_id: String in restored.regiments:
		assert_eq(
			RegimentNames.of(restored, regiment_id),
			String(expected[regiment_id]),
			"the same arithmetic christens the same title"
		)
		assert_eq(int(RegimentRecord.of(restored, regiment_id)["engagements"]), 0)

func test_the_aftermath_names_a_mauled_regiment() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["guards"])
	var side: Array[ArmyState] = [army]

	var entries: Array[Dictionary] = RegimentCondition.entries(side)

	assert_eq(entries.size(), 1)
	assert_eq(String(entries[0]["name"]), RegimentNames.of(army, "unit_101"))



# --- battle honours beyond the chevron (wiki: naming § Regiment records;
# DR-20261112-02) ---


func test_a_won_battle_adds_the_province_to_every_surviving_colour() -> void:
	var model := army_regiment_names_Fixture.build()
	var defender := army_regiment_names_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := army_regiment_names_Fixture.army(2, 0, 2, ["guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(int(reports[0]["attacker_honours"]), attacker.count(), "every colour takes it")
	assert_eq(int(reports[0]["defender_honours"]), 0, "a broken side takes no colour")
	assert_true(defender.is_empty(), "the beaten side had no survivor to honour")
	for regiment_id: String in attacker.regiments:
		assert_eq(RegimentRecord.colours(attacker, regiment_id), [2])



func test_a_standoff_and_a_defeat_take_no_honour() -> void:
	var attacker := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var defender := army_regiment_names_Fixture.army(2, 1, 2, ["pikemen"], true)
	var standoff: Dictionary = {"province": 2, "outcome": ArmyCombat.Outcome.STALEMATE}
	var beaten: Dictionary = {"province": 2, "outcome": ArmyCombat.Outcome.DEFENDER_VICTORY}

	RegimentCondition.attach(standoff, [attacker], [defender], 0, 1)
	RegimentCondition.attach(beaten, [attacker], [defender], 0, 1)

	assert_eq(int(standoff["attacker_honours"]), 0, "a standoff wins no field")
	assert_eq(int(beaten["attacker_honours"]), 0, "the beaten side takes nothing")
	assert_eq(int(beaten["defender_honours"]), 1)
	assert_true(RegimentRecord.colours(attacker, "unit_101").is_empty())
	assert_eq(RegimentRecord.colours(defender, "unit_201"), [2])



func test_a_province_is_borne_once_and_the_newest_leads() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]

	RegimentRecord.award_honours(side, 2)
	RegimentRecord.award_honours(side, 6)
	RegimentRecord.award_honours(side, 6)

	assert_eq(RegimentRecord.colours(army, "unit_101"), [6, 2])
	assert_eq(int(RegimentRecord.of(army, "unit_101")["honours"].size()), 2)



func test_the_colours_survive_a_detach_and_a_save() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]
	RegimentRecord.award_honours(side, 2)
	var armies: Array[ArmyState] = [army]

	var result: Dictionary = ArmyRoster.split(armies, army, ["unit_101"], 2)

	assert_true(bool(result["ok"]), String(result["reason"]))
	var detached: ArmyState = result["army"] as ArmyState
	assert_eq(RegimentRecord.colours(detached, "unit_101"), [2], "the colour travels")
	var restored: ArmyState = ArmyState.from_dict(detached.to_dict())
	assert_eq(RegimentRecord.colours(restored, "unit_101"), [2], "the save carries it")



func test_the_dossier_line_names_the_colours() -> void:
	var model := army_regiment_names_Fixture.build()
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]
	army.regiment_engagements["unit_101"] = 5
	army.regiment_wins["unit_101"] = 4
	for province: int in [2, 6, 4, 0]:
		RegimentRecord.award_honours(side, province)

	assert_eq(
		RegimentRecord.line(army, "unit_101", model),
		"5 engagements · 4 won · Province 0 · Province 4 · +2 more",
		"the two newest colours, then the count of the rest"
	)
	assert_eq(
		RegimentRecord.line(army, "unit_101"),
		"5 engagements · 4 won",
		"without a chart the tally stands alone"
	)



func test_an_unhonoured_regiment_reads_only_its_tally() -> void:
	var model := army_regiment_names_Fixture.build()
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	army.regiment_engagements["unit_101"] = 1

	assert_eq(RegimentRecord.honour_line(army, "unit_101", model), "")
	assert_eq(RegimentRecord.line(army, "unit_101", model), "1 engagement · 0 won")


# --- citations and the despatch a regiment holds (wiki: naming § Regiment
# records; DR-20261112-10) ---


func test_a_won_field_is_written_into_every_survivors_despatch() -> void:
	var model := army_regiment_names_Fixture.build()
	var defender := army_regiment_names_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := army_regiment_names_Fixture.army(2, 0, 2, ["guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})

	var report: Dictionary = reports[0]
	assert_eq(int(report["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	var bled: int = 0
	for entry: Dictionary in report["attacker_health"]:
		if float(entry["fraction"]) < 1.0:
			bled += 1
	assert_eq(int(report["attacker_citations"]), bled, "every mauled colour is cited")
	assert_eq(int(report["defender_citations"]), 0, "a broken side takes no citation")
	for regiment_id: String in attacker.regiments:
		var fields: Array = RegimentDecorations.history(attacker, regiment_id)
		assert_eq(fields.size(), 1, "the field is written once")
		assert_eq(int(fields[0]["p"]), 2, "the field's province is kept")
		assert_true(bool(fields[0]["w"]), "the side won it")


func test_a_clean_win_cites_nobody_but_still_writes_the_field() -> void:
	var attacker := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var defender := army_regiment_names_Fixture.army(2, 1, 2, ["pikemen"], true)
	var won: Dictionary = {"province": 2, "outcome": ArmyCombat.Outcome.ATTACKER_VICTORY}

	RegimentCondition.attach(won, [attacker], [defender], 1, 0)

	assert_eq(int(won["attacker_citations"]), 0, "no colour bled, none is cited")
	assert_eq(RegimentDecorations.citations(attacker, "unit_101"), 0)
	var fields: Array = RegimentDecorations.history(attacker, "unit_101")
	assert_eq(fields.size(), 1, "the field is still on the record")
	assert_true(bool(fields[0]["w"]))
	assert_false(bool(fields[0]["c"]), "an untouched colour is not cited")


func test_a_lost_field_counts_but_cites_nothing() -> void:
	var attacker := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var defender := army_regiment_names_Fixture.army(2, 1, 2, ["pikemen"], true)
	var beaten: Dictionary = {"province": 2, "outcome": ArmyCombat.Outcome.DEFENDER_VICTORY}

	RegimentCondition.attach(beaten, [attacker], [defender], 0, 1)

	assert_eq(int(beaten["attacker_citations"]), 0)
	assert_eq(int(beaten["defender_citations"]), 0, "a clean defence cites nobody")
	assert_false(bool(RegimentDecorations.history(attacker, "unit_101")[0]["w"]))
	assert_true(bool(RegimentDecorations.history(defender, "unit_201")[0]["w"]))


func test_the_despatch_keeps_the_newest_fields_and_the_tally_counts_all() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]
	for province: int in 12:
		RegimentRecord.note_battle(side, true)
		RegimentDecorations.note(side, province, true)

	var fields: Array = RegimentDecorations.history(army, "unit_101")
	assert_eq(fields.size(), RegimentDecorations.KEPT, "the despatch is bounded")
	assert_eq(int(fields[0]["p"]), 11, "newest first")
	assert_eq(int(fields[fields.size() - 1]["p"]), 12 - RegimentDecorations.KEPT)
	assert_eq(int(RegimentRecord.of(army, "unit_101")["engagements"]), 12, "the tally counts all")


func test_the_ladder_names_a_cited_and_a_laurelled_regiment() -> void:
	var model := army_regiment_names_Fixture.build()
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]
	var top: int = int(army.condition_of("unit_101")["max"])

	RegimentRecord.note_battle(side, true)
	RegimentDecorations.note(side, 2, true)
	assert_eq(RegimentDecorations.rank(army, "unit_101"), "", "a clean win cites nobody")
	assert_eq(
		RegimentDecorations.line(army, "unit_101", model),
		"History — Province 2 won",
		"an undecorated record still names the field"
	)

	army.regiment_health["unit_101"] = top / 2
	RegimentRecord.note_battle(side, true)
	RegimentDecorations.note(side, 6, true)
	assert_eq(RegimentDecorations.citations(army, "unit_101"), 1)
	assert_eq(RegimentDecorations.rank(army, "unit_101"), "cited")
	assert_eq(
		RegimentDecorations.line(army, "unit_101", model),
		"Cited +5% — Province 6 won · Province 2 won",
		"the decoration leads the despatch and names the weight it buys"
	)

	RegimentRecord.note_battle(side, true)
	RegimentDecorations.note(side, 4, true)
	RegimentRecord.note_battle(side, true)
	RegimentDecorations.note(side, 0, true)
	assert_eq(RegimentDecorations.citations(army, "unit_101"), RegimentDecorations.LAUREL_AT)
	assert_eq(RegimentDecorations.rank(army, "unit_101"), "laurelled")
	assert_eq(
		RegimentDecorations.line(army, "unit_101", model),
		"Laurelled +10% — Province 0 won · Province 4 won · +2 earlier",
		"two newest fields, then the fields the record still counts"
	)


func test_a_green_regiment_holds_no_despatch() -> void:
	var model := army_regiment_names_Fixture.build()
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])

	assert_true(RegimentDecorations.history(army, "unit_101").is_empty())
	assert_eq(RegimentDecorations.rank(army, "unit_101"), "")
	assert_eq(RegimentDecorations.line(army, "unit_101", model), "", "a fresh roster stays short")


func test_a_citation_survives_a_detach_and_a_save() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]
	army.regiment_health["unit_101"] = int(army.condition_of("unit_101")["max"]) / 2
	RegimentDecorations.note(side, 2, true)
	var armies: Array[ArmyState] = [army]

	var result: Dictionary = ArmyRoster.split(armies, army, ["unit_101"], 2)

	assert_true(bool(result["ok"]), String(result["reason"]))
	var detached: ArmyState = result["army"] as ArmyState
	assert_eq(RegimentDecorations.citations(detached, "unit_101"), 1, "the citation travels")
	var restored: ArmyState = ArmyState.from_dict(detached.to_dict())
	assert_eq(RegimentDecorations.citations(restored, "unit_101"), 1, "the save carries it")
	assert_eq(int(RegimentDecorations.history(restored, "unit_101")[0]["p"]), 2)
	assert_eq(RegimentDecorations.rank(army, "unit_102"), "", "the colour left behind is bare")

# --- what a citation buys: weight in the line (wiki: combat § Strength;
# DR-20261113-04) ---


func test_a_citation_weighs_half_a_chevron_and_the_laurel_a_whole_one() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]

	assert_eq(
		RegimentDecorations.strength_multiplier(army, "unit_101"), 1.0,
		"a colours the crown never named weighs nothing extra"
	)
	var top: int = int(army.condition_of("unit_101")["max"])
	army.regiment_health["unit_101"] = top / 2
	RegimentDecorations.note(side, 2, true)
	assert_almost_eq(
		RegimentDecorations.strength_multiplier(army, "unit_101"),
		1.0 + RegimentDecorations.CITED_STEP, 0.0001,
		"one citation is half a chevron"
	)
	RegimentDecorations.note(side, 3, true)
	RegimentDecorations.note(side, 4, true)
	assert_eq(RegimentDecorations.rank(army, "unit_101"), "laurelled")
	assert_almost_eq(
		RegimentDecorations.strength_multiplier(army, "unit_101"),
		1.0 + RegimentDecorations.LAUREL_STEP, 0.0001,
		"the laurel is worth the whole chevron"
	)


func test_a_decorated_colour_weighs_its_step_in_the_side_strength() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]
	_cite_and_heal(army, "unit_102")

	var plain: float = ArmyModifiers.rank_of("pikemen", 0, 1.0)

	assert_almost_eq(
		ArmyModifiers.strength(side, 10, 1.0),
		plain * 2.0 + plain * RegimentDecorations.CITED_STEP, 0.0001,
		"only the cited colour's rank carries the step"
	)
	var line: Array[Dictionary] = ArmyModifiers.deployed(side, 1)
	assert_eq(
		String(line[0]["id"]), "unit_102",
		"the cited colours holds the line over a bare twin"
	)


func test_the_cited_colour_is_the_last_to_fall() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]
	var armies: Array[ArmyState] = [army]
	_cite_and_heal(army, "unit_102")

	var lost: Array[String] = ArmyForce.apply_losses(armies, side, 1)

	assert_eq(lost.size(), 1)
	assert_eq(lost[0], "unit_101", "the bare colour goes first, the decorated one holds")


## A citation is won mauled, so the colours are healed back to full before the
## weight is read: only the decoration tells the twins apart.
func _cite_and_heal(army: ArmyState, regiment_id: String) -> void:
	var side: Array[ArmyState] = [army]
	var top: int = int(army.condition_of(regiment_id)["max"])
	army.regiment_health[regiment_id] = top / 2
	RegimentDecorations.note(side, 2, true)
	army.regiment_health[regiment_id] = top


# --- test_military_parity ---

func test_no_research_leaves_the_floor_at_era_one() -> void:
	assert_eq(MilitaryParity.max_great_power_era({}), 1)
	assert_eq(MilitaryParity.max_great_power_era({0: {}}), 1)

func test_the_strongest_great_power_sets_the_era() -> void:
	var tech: Dictionary = {
		0: {"bayonet": true},
		1: {},
		2: {"needle_guns": true},
	}
	assert_eq(MilitaryParity.max_great_power_era(tech), 4)

func test_a_minor_upgrades_within_its_own_category() -> void:
	assert_eq(
		MilitaryParity.upgrade_type("squires", 3), "hussars",
		"light cavalry becomes the era-3 light cavalry"
	)
	assert_eq(
		MilitaryParity.upgrade_type("pikemen", 3), "regulars",
		"regular infantry becomes the era-3 regular infantry"
	)
	assert_eq(
		MilitaryParity.upgrade_type("culverin", 2), "royal_artillery",
		"heavy artillery follows its own row"
	)

func test_no_downgrade_and_unknown_types_are_safe() -> void:
	assert_eq(MilitaryParity.upgrade_type("guards", 2), "guards")
	assert_eq(MilitaryParity.upgrade_type("not_a_regiment", 4), "not_a_regiment")

func test_tribes_keep_level_one_while_minors_follow_the_powers() -> void:
	assert_eq(MilitaryParity.effective_level(FactionCatalog.minor_ids()[0], 3), 3)
	assert_eq(MilitaryParity.effective_level(FactionCatalog.tribe_ids()[0], 3), 1)

func test_apply_upgrades_minor_regiments_in_place_and_skips_others() -> void:
	var minor: int = FactionCatalog.minor_ids()[0]
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var regions := MapRegionTable.new()
	var minor_army: ArmyState = ArmyState.muster(
		1, minor, 0, true, ["squires", "pikemen"], 1
	)
	var tribe_army: ArmyState = ArmyState.muster(
		2, tribe, 0, true, ["pikemen"], 10
	)
	var power_army: ArmyState = ArmyState.muster(
		3, FactionCatalog.PLAYER_FACTION, 0, true, ["squires"], 20
	)
	regions.set_region(0, [minor_army, tribe_army, power_army])
	var report: Dictionary = MilitaryParity.apply(
		regions, {FactionCatalog.PLAYER_FACTION: {"bayonet": true}}
	)
	assert_eq(int(report["era"]), 3)
	assert_eq(int(report["count"]), 2)
	assert_eq(minor_army.type_of(minor_army.regiments[0]), "hussars")
	assert_eq(minor_army.type_of(minor_army.regiments[1]), "regulars")
	assert_eq(tribe_army.type_of(tribe_army.regiments[0]), "pikemen")
	assert_eq(power_army.type_of(power_army.regiments[0]), "squires")

func test_apply_without_a_table_is_safe() -> void:
	var report: Dictionary = MilitaryParity.apply(null, {0: {"bayonet": true}})
	assert_eq(int(report["count"]), 0)
	assert_eq(int(report["era"]), 3)

func test_no_research_keeps_every_regiment_as_it_stands() -> void:
	var minor: int = FactionCatalog.minor_ids()[0]
	var regions := MapRegionTable.new()
	var army: ArmyState = ArmyState.muster(1, minor, 0, true, ["squires"], 1)
	regions.set_region(0, [army])
	var report: Dictionary = MilitaryParity.apply(regions, {0: {}})
	assert_eq(int(report["count"]), 0)
	assert_eq(army.type_of(army.regiments[0]), "squires")

func test_a_category_with_no_higher_type_keeps_its_regiment() -> void:
	assert_eq(MilitaryParity.upgrade_type("bowmen", 4), "bowmen")

# --- test_difficulty ---

func test_ids_are_ordered_easiest_first_and_unknown_ids_fall_back() -> void:
	assert_eq(Difficulty.IDS.size(), 4)
	assert_eq(String(Difficulty.IDS[0]), "introductory")
	assert_eq(String(Difficulty.IDS[3]), "impossible")
	assert_eq(Difficulty.normalize(""), Difficulty.DEFAULT)
	assert_eq(Difficulty.normalize("Napoleon"), Difficulty.DEFAULT)
	assert_eq(Difficulty.normalize("  Hard "), "hard")
	assert_eq(Difficulty.index_of("hard"), 2)
	assert_eq(Difficulty.label("impossible"), "Impossible")

func test_percentages_rise_with_difficulty_and_normal_is_the_published_row() -> void:
	var previous_start: int = 0
	var previous_combat: int = 0
	for id: String in Difficulty.IDS:
		assert_gte(Difficulty.ai_start_percent(id), previous_start)
		assert_gte(Difficulty.ai_combat_percent(id), previous_combat)
		previous_start = Difficulty.ai_start_percent(id)
		previous_combat = Difficulty.ai_combat_percent(id)
	assert_eq(Difficulty.ai_start_percent(Difficulty.DEFAULT), 100)
	assert_eq(Difficulty.ai_combat_percent(Difficulty.DEFAULT), 100)
	assert_eq(Difficulty.ai_start_percent("introductory"), 60)
	assert_eq(Difficulty.ai_start_percent("impossible"), 180)
	assert_eq(Difficulty.ai_combat_percent("impossible"), 130)

func test_every_level_states_its_effect_in_plain_words() -> void:
	for id: String in Difficulty.IDS:
		assert_gt(Difficulty.hint(id).length(), 20, "%s needs a hint" % id)
	assert_true(Difficulty.hint("hard").contains("140%"))
	assert_true(Difficulty.hint("normal").contains("alike"))
	assert_ne(Difficulty.hint("hard"), Difficulty.hint("impossible"))

func test_start_quantities_scale_by_percent_and_floor_at_zero() -> void:
	assert_eq(Difficulty.scaled(2500, 140), 3500)
	assert_eq(Difficulty.scaled(6, 85), 5)
	assert_eq(Difficulty.scaled(0, 180), 0)
	assert_eq(Difficulty.scaled(-4, 180), 0)

func test_a_rival_ledger_is_founded_at_the_chosen_level_once() -> void:
	var play := PlaySession.new()
	play.difficulty = "hard"
	var ai: AiState = play.ensure_ai()
	assert_eq(ai.difficulty, "hard")
	var rival: PlayerEconomy = ai.economy_for(3)
	assert_eq(rival.treasury, Difficulty.scaled(PlayerEconomy.START_TREASURY, 140))
	assert_eq(rival.quantity("grain"), Difficulty.scaled(
		PlayerEconomy.START_PEASANTS * PlayerEconomy.START_GRAIN_TURNS, 140
	))
	var treasury: int = rival.treasury
	# Reading the same ledger again must not compound the scale.
	assert_eq(ai.economy_for(3).treasury, treasury)
	assert_eq(ai.economy_for(3), rival)

func test_normal_leaves_every_court_on_the_published_start_row() -> void:
	var play := PlaySession.new()
	var rival: PlayerEconomy = play.ensure_ai().economy_for(2)
	assert_eq(play.difficulty, Difficulty.DEFAULT)
	assert_eq(rival.treasury, PlayerEconomy.START_TREASURY)
	assert_eq(rival.quantity("grain"), PlayerEconomy.START_PEASANTS * PlayerEconomy.START_GRAIN_TURNS)
	assert_eq(rival.quantity("wool"), 4)

func test_the_human_crown_is_never_scaled() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "impossible"
	var multipliers: Dictionary = Difficulty.combat_multipliers(
		play.human_faction_id(), play.difficulty, FactionCatalog.great_power_ids()
	)
	assert_false(multipliers.has(2), "the human side keeps the published maths")
	assert_almost_eq(float(multipliers[1]), 1.3, 0.001)

func test_battle_context_carries_the_rival_multiplier_and_skips_the_human() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "introductory"
	var context: Dictionary = MapPlayLandTurn.battle_context(play)
	var difficulty: Dictionary = context["difficulty"] as Dictionary
	assert_false(difficulty.has(2))
	assert_almost_eq(float(difficulty[0]), 0.85, 0.001)

func test_an_introductory_rival_fails_an_assault_that_wins_at_normal() -> void:
	var normal: Dictionary = _assault({})
	var eased: Dictionary = _assault({1: 0.85})
	assert_true(bool(normal["captured"]), "six regiments carry four at the published maths")
	assert_false(bool(eased["captured"]), "the eased rival is turned back")
	assert_gt(
		int((eased["attacker_lost"] as Array).size()),
		int((normal["attacker_lost"] as Array).size())
	)
	assert_gt(
		int((normal["defender_lost"] as Array).size()),
		int((eased["defender_lost"] as Array).size())
	)

func test_a_hard_rival_holds_its_ground_where_normal_is_driven_off() -> void:
	var normal: Dictionary = _assault({})
	var hard: Dictionary = _assault({1: 1.3})
	assert_true(bool(normal["captured"]))
	assert_true(bool(hard["captured"]), "a stronger attacker still carries the province")
	assert_gte(
		int((hard["defender_lost"] as Array).size()),
		int((normal["defender_lost"] as Array).size())
	)

## Six rival regiments assault four of the human crown's in province 0.
func _assault(difficulty: Dictionary) -> Dictionary:
	var model: MapModel = difficulty_Fixture.build()
	var defending: Array[ArmyState] = [
		difficulty_Fixture.army(1, 0, 0, ["pikemen", "pikemen", "pikemen", "pikemen"], true)
	]
	var attacking: Array[ArmyState] = [
		difficulty_Fixture.army(2, 1, 0, ["pikemen", "pikemen", "pikemen", "pikemen", "pikemen", "pikemen"])
	]
	attacking[0].moved = true
	var armies: Array[ArmyState] = []
	armies.append_array(defending)
	armies.append_array(attacking)
	var context: Dictionary = {"quick_battle": false}
	if not difficulty.is_empty():
		context["difficulty"] = difficulty
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	assert_eq(reports.size(), 1, "one exchange in province 0")
	return reports[0] if not reports.is_empty() else {}

func test_the_naval_layer_scales_every_rival_and_never_the_crown() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "hard"
	var factors: Dictionary = MapPlayNavalTurn.strength_multipliers(play)
	assert_false(factors.has(2), "the crown's hulls keep the published maths")
	assert_almost_eq(float(factors[1]), 1.15, 0.001)
	assert_almost_eq(float(factors[0]), float(factors[4]), 0.001,
		"every rival sails under one factor")

func test_a_dead_even_squadron_action_turns_on_the_level() -> void:
	assert_eq(_engagement({}), NavalCombat.Outcome.STALEMATE,
		"equal hulls draw on the published maths")
	assert_eq(_engagement({1: 0.85}), NavalCombat.Outcome.SIDE2_VICTORY,
		"the eased rival is repelled")
	assert_eq(_engagement({1: 1.3}), NavalCombat.Outcome.SIDE1_VICTORY,
		"the risen rival holds the water")

func test_the_resolved_despatch_carries_the_scaled_strength() -> void:
	var raw_rival: float = NavalCombat.side_strength([_rival_squadron(1)])
	assert_almost_eq(_engagement_record({1: 1.3})["attacker_strength"],
		raw_rival * 1.3, 0.001)
	assert_almost_eq(_engagement_record({1: 1.3})["defender_strength"],
		NavalCombat.side_strength([_crown_squadron()]), 0.001,
		"the human side is never scaled")

func test_the_dossier_odds_read_the_same_factor() -> void:
	var fleets: Array = [_crown_squadron(), _rival_squadron(4)]
	var published: Dictionary = NavalStrength.zone(fleets, fleets[0])
	var hard: Dictionary = NavalStrength.zone(
		fleets, fleets[0], Callable(), {4: 1.3})
	assert_almost_eq(float(hard["foe"]), float(published["foe"]) * 1.3, 0.001)
	assert_lt(float(hard["share"]), float(published["share"]),
		"a stronger rival takes more of the zone")

func test_two_rivals_share_one_factor_so_their_ratio_stays_published() -> void:
	var fleets: Array = [_rival_squadron(1), _rival_squadron(4)]
	var published: Dictionary = NavalStrength.zone(fleets, fleets[0])
	var scaled: Dictionary = NavalStrength.zone(
		fleets, fleets[0], Callable(), {1: 1.3, 4: 1.3})
	assert_almost_eq(float(scaled["share"]), float(published["share"]), 0.0001,
		"the factor cancels between two rivals")

## One squadron of the human crown and one rival frigate pair, both afloat in
## zone 0; the rival carries the lower owner id, so it takes the initiative.
func _crown_squadron() -> FleetState:
	return FleetState.at_sea(
		10, 2, 0, ["h1", "h2"], {"h1": "frigate", "h2": "frigate"}
	)

func _rival_squadron(owner: int) -> FleetState:
	return FleetState.at_sea(
		10 + owner, owner, 0, ["r1", "r2"], {"r1": "frigate", "r2": "frigate"}
	)

func _engagement(factors: Dictionary) -> int:
	return int(_engagement_record(factors).get("outcome", NavalCombat.Outcome.NONE))

func _engagement_record(factors: Dictionary) -> Dictionary:
	var context: Dictionary = {}
	if not factors.is_empty():
		context["difficulty"] = factors
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[_crown_squadron(), _rival_squadron(1)], Callable(), context
	)
	assert_eq(battles.size(), 1, "one engagement in zone 0")
	return battles[0] if not battles.is_empty() else {}

## The published bar is 31, and the level's published percentage moves it by
## whole provinces: 85 / 100 / 115 / 130 % of 31 (wiki: victory § Military
## victory; ruleset-config § Difficulty; DR-20261111-28).
func test_the_crowns_bar_is_the_published_one_scaled_by_the_level() -> void:
	assert_eq(VictoryRules.crown_threshold("normal"), VictoryRules.MILITARY_THRESHOLD)
	assert_eq(VictoryRules.crown_threshold(""), 31, "a legacy campaign reads as published")
	assert_eq(VictoryRules.crown_threshold("introductory"), 26)
	assert_eq(VictoryRules.crown_threshold("hard"), 36)
	assert_eq(VictoryRules.crown_threshold("impossible"), 40)

## Every rival keeps the published bar at every level, so the layer never
## changes a rival-versus-rival ratio; the observer (no human) is published too.
func test_only_the_human_crowns_bar_moves() -> void:
	for level: String in Difficulty.IDS:
		assert_eq(VictoryRules.threshold_for(1, 2, level), VictoryRules.MILITARY_THRESHOLD)
		assert_eq(
			VictoryRules.threshold_for(2, 2, level),
			VictoryRules.crown_threshold(level),
			"%s moves the crown's own bar" % level
		)
		assert_eq(
			VictoryRules.threshold_for(2, MapModel.NO_ID, level),
			VictoryRules.MILITARY_THRESHOLD,
			"the full-AI observer stays on the published rows"
		)

## 31 provinces win the age at normal and fall short at hard, where the crown
## needs 36; the same 31 still wins for a rival on that level.
func test_the_level_decides_whether_the_crown_has_won_the_age() -> void:
	assert_not_null(VictoryRules.evaluate(land__world({2: 31}), 5, 2, "normal"))
	assert_null(VictoryRules.evaluate(land__world({2: 31}), 5, 2, "hard"))
	var won: VictoryState = VictoryRules.evaluate(land__world({2: 36}), 5, 2, "hard")
	assert_not_null(won)
	assert_eq(won.winner_player_id, 2)
	assert_not_null(
		VictoryRules.evaluate(land__world({1: 31}), 5, 2, "hard"),
		"a rival still wins at the published bar"
	)

## An eased campaign asks less of the crown: 26 provinces win at introductory
## where 25 do not.
func test_an_eased_campaign_asks_less_of_the_crown() -> void:
	assert_not_null(VictoryRules.evaluate(land__world({2: 26}), 5, 2, "introductory"))
	assert_null(VictoryRules.evaluate(land__world({2: 25}), 5, 2, "introductory"))

## The turn reads the session's own level and human slot; an observer passes
## NO_ID and gets the published maths for every crown.
func test_the_turn_reads_the_sessions_level_and_human_slot() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "hard"
	play.world = land__world({2: 31})
	assert_null(
		VictoryRules.resolve(play.victory, play.world, 9, play.human_faction_id(), play.difficulty)
	)
	play.world = land__world({2: 36})
	assert_not_null(
		VictoryRules.resolve(play.victory, play.world, 9, play.human_faction_id(), play.difficulty)
	)
	play.observer_mode = true
	play.world = land__world({2: 31})
	assert_not_null(
		VictoryRules.resolve(play.victory, play.world, 9, play.human_faction_id(), play.difficulty),
		"the observer keeps the published bar for every crown"
	)

## One Old World region holding `counts` provinces per owner.
func land__world(counts: Dictionary) -> WorldMap:
	var world := WorldMap.new()
	var model := MapModel.new()
	model.setup(1, 1)
	model.region_id = FactionCatalog.OLD_WORLD
	model.faction_ids = FactionCatalog.ids_in_region(FactionCatalog.OLD_WORLD)
	var next_id: int = 0
	for faction_id: int in counts.keys():
		for _index in int(counts[faction_id]):
			var tiles: Array[Vector2i] = []
			model.provinces.append(
				ProvinceState.create(
					next_id, "Province %d" % next_id, tiles, Vector2.ZERO, 1, faction_id
				)
			)
			next_id += 1
	world.add_region(model)
	return world

# --- test_quick_battle_rules ---

func test_land_quick_battle_is_deterministic_for_a_fixed_seed() -> void:
	var first: Dictionary = _quick_battle_rules_fight("balanced", land__guards(6), land__pikes(4))
	var second: Dictionary = _quick_battle_rules_fight("balanced", land__guards(6), land__pikes(4))

	assert_eq(int(first["outcome"]), int(second["outcome"]))
	assert_eq(
		(first["attacker_lost"] as Array).size(),
		(second["attacker_lost"] as Array).size()
	)
	assert_eq(
		(first["defender_lost"] as Array).size(),
		(second["defender_lost"] as Array).size()
	)
	assert_eq(land__round_count(first), land__round_count(second))

func test_land_quick_battle_runs_at_most_three_rounds() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", land__guards(6), land__pikes(6))
	var rounds: int = land__round_count(battle)
	assert_true(rounds >= 1)
	assert_true(rounds <= QuickBattleTerms.MAX_ROUNDS)

func test_land_the_players_plan_drives_the_action_script() -> void:
	var aggressive: Dictionary = _quick_battle_rules_fight("aggressive", land__guards(6), land__pikes(4))
	var defensive: Dictionary = _quick_battle_rules_fight("defensive", land__guards(6), land__pikes(4))
	assert_eq(String(aggressive["quick"]["plan"]), "aggressive")
	assert_eq(String(defensive["quick"]["plan"]), "defensive")

## The crown holds one plan and it binds the side it commands, even on the wall;
## a rival side keeps the rule-derived script instead (wiki: quick-battle § The
## crown's plan; DR-20261110-33).
func test_land_the_crowns_plan_holds_on_the_defending_side() -> void:
	var model := quick_battle_rules_Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, land__pikes(6), true)
	var attacker := quick_battle_rules_Fixture.army(2, 2, 2, land__guards(8))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = land__context("aggressive")
	context["player_faction"] = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	var quick: Dictionary = reports[0]["quick"]

	assert_eq(String(quick["defender_plan"]), "aggressive", "the crown's plan holds")
	assert_eq(String(quick["plan"]), "balanced", "the rival keeps its own script")

func test_land_quick_battle_removes_casualties_from_the_armies() -> void:
	var model := quick_battle_rules_Fixture.build()
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, land__pikes(6), true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, land__guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var before: int = ArmyForce.side_regiments(armies)

	ArmyCombat.resolve_turn(model, armies, land__context("balanced"))

	assert_true(ArmyForce.side_regiments(armies) < before)

func test_land_a_siege_fields_virtual_guns_and_downgrades_the_fort() -> void:
	var model := quick_battle_rules_Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, land__guards(20))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, land__context("balanced"))
	var battle: Dictionary = reports[0]

	assert_eq(String(battle["battle_mode"]), "siege")
	assert_eq(int(battle["quick"]["guns_start"]), 1)
	assert_true(bool(battle["quick"]["fort_downgraded"]))
	assert_eq(int(battle["quick"]["guns_lost"]), 1, "the battery is silenced")
	assert_eq(String(battle["quick"]["gun_type"]), "royal_artillery")
	assert_eq(int(battle["quick"]["fort_after"]), 0)
	assert_eq(model.province_data(2).fort_level, 0)

## The wall lanes are recorded for the despatch: infantry man the parapet, the
## battery and horse shelter behind it (wiki: siege-mechanics).
func test_land_a_siege_records_the_wall_lanes() -> void:
	var battle: Dictionary = _quick_battle_rules_fight(
		"balanced", land__guards(8), ["pikemen", "musketeers", "culverin"], 2
	)
	var lanes: Dictionary = battle["quick"]["lanes"]

	assert_eq(int(lanes["wall"]), 2, "two infantry regiments hold the wall")
	assert_eq(int(lanes["behind"]), 1, "the gun waits behind the parapet")

## Melee-only regiments cannot attack a wall or anything inside it; they need
## firearms or guns (wiki: siege-mechanics § Damage Reduction).
func test_land_melee_only_besiegers_are_turned_away() -> void:
	var model := quick_battle_rules_Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, land__pikes(8))
	attacker.moved = true
	var context: Dictionary = land__context("balanced")
	## A garrison that holds the wall gives the pikes nothing to hit.
	context["defender_battle_plan"] = "defensive"
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	var battle: Dictionary = reports[0]

	assert_eq((battle["defender_lost"] as Array).size(), 0, "the garrison is untouched")
	assert_eq(int(battle["quick"]["guns_lost"]), 0, "pikes cannot silence the battery")
	var turned: bool = false
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if int(action["turned"]) > 0:
				turned = true
	assert_true(turned, "the despatch says the wall turned the blow aside")

## A garrison that leaves the wall to sortie can hit back with every regiment,
## which is how a pike garrison hurts a siege at all.
func test_land_a_sortie_lets_a_pike_garrison_fight() -> void:
	var model := quick_battle_rules_Fixture.build()
	model.province_data(2).fort_level = 2
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, land__pikes(6), true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, land__guards(6))
	attacker.moved = true
	var context: Dictionary = land__context("aggressive")
	context["player_faction"] = 1
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_true(int(reports[0]["quick"]["sorties"]) > 0, "the defender chose to sortie")
	assert_true(
		(reports[0]["attacker_lost"] as Array).size() > 0,
		"outside the wall the pikes can reach the besiegers"
	)

## Regiment detail: the report counts the losses by regiment type, so the
## despatch can name them.
func test_land_the_report_tallies_losses_by_regiment_type() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", land__guards(10), ["peasant_levies", "pikemen"], 1)
	var detail: Dictionary = battle["defender_detail"]
	var counted: int = 0
	for type_id: Variant in detail.keys():
		counted += int(detail[type_id])
		assert_true(RegimentCatalog.has_type(String(type_id)))

	assert_eq(counted, (battle["defender_lost"] as Array).size())
	assert_false(RegimentCatalog.detail_text(detail).is_empty())

func test_land_rival_battles_keep_the_aggregate_path() -> void:
	var model := quick_battle_rules_Fixture.build()
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, land__pikes(3), true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, land__guards(5))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = land__context("balanced")
	context["player_faction"] = 2

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_false(reports[0].has("quick"), "a rival battle stays auto-resolve")

func test_land_a_weak_attacker_is_repulsed() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", land__pikes(2), land__guards(8))
	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)

## Side strength is tactical, not a head count: four guards outweigh four
## pikes, and four pikes outweigh four levies (wiki: quick-battle § Cohesion
## and effective strength).
func test_land_effective_strength_aggregates_fpn_and_fpm() -> void:
	var guards: Array[ArmyState] = land__lane_side(land__guards(4), 2)
	var pikes: Array[ArmyState] = land__lane_side(land__pikes(4), 1)
	var levies: Array[ArmyState] = land__lane_side(land__levies(4), 1)

	var guard_weight: float = QuickBattleTerms.effective_strength(guards, 10, 3, 1.0)
	var pike_weight: float = QuickBattleTerms.effective_strength(pikes, 10, 3, 1.0)
	var levy_weight: float = QuickBattleTerms.effective_strength(levies, 10, 3, 1.0)

	assert_almost_eq(guard_weight, 4.0 * 22.0, 0.01, "Σ (FPN + FPM) for the slice")
	assert_true(guard_weight > pike_weight)
	assert_true(pike_weight > levy_weight)
	assert_almost_eq(
		QuickBattleTerms.effective_strength(guards, 10, 0, 1.0), 0.0, 0.001,
		"a broken line has no strength"
	)
	assert_almost_eq(
		QuickBattleTerms.effective_strength(guards, 10, 3, 2.0), guard_weight * 2.0,
		0.01, "the side multiplier scales the whole slice"
	)

## Reserves behind the deployment limit never count, exactly as in
## auto-resolve (wiki: combat § Strength).
func test_land_only_the_deployed_slice_counts_toward_strength() -> void:
	var twelve: Array[ArmyState] = land__lane_side(land__guards(12), 2)

	assert_almost_eq(
		QuickBattleTerms.effective_strength(twelve, 10, 3, 1.0), 10.0 * 22.0, 0.01
	)

## A chevroned regiment weighs more than a fresh one, and health scales it the
## same way (wiki: combat § Strength).
func test_land_chevrons_and_health_raise_a_regiments_weight() -> void:
	var fresh: Array[ArmyState] = land__lane_side(land__guards(2), 2)
	var veteran: Array[ArmyState] = land__lane_side(land__guards(2), 2)
	var army: ArmyState = veteran[0]
	for regiment_id: String in army.regiments:
		army.regiment_medals[regiment_id] = RegimentCatalog.MAX_MEDALS
	var fresh_weight: float = QuickBattleTerms.effective_strength(fresh, 10, 3, 1.0)
	var veteran_weight: float = QuickBattleTerms.effective_strength(veteran, 10, 3, 1.0)

	assert_almost_eq(veteran_weight, fresh_weight * 1.4, 0.01)
	var first: String = army.regiments[0]
	army.regiment_health[first] = RegimentCatalog.max_health("guards") / 2
	assert_true(
		QuickBattleTerms.effective_strength(veteran, 10, 3, 1.0) < veteran_weight,
		"a mauled regiment shoulders less"
	)

## An action's blow is spent as weight, so the same volley from a guard line
## breaks more men than from a levy line (wiki: quick-battle § Cohesion and
## effective strength).
func test_land_a_stronger_line_breaks_more_of_the_enemy() -> void:
	var strong: Array[ArmyState] = land__lane_side(land__guards(4), 2)
	var levies: Array[ArmyState] = land__lane_side(land__levies(4), 1)
	var hard: Dictionary = QuickBattleActions.resolve(
		land__lane_joined(strong, levies), land__lane_state(strong, levies, 0),
		"attacker", "defender", "volley", [] as Array[Dictionary]
	)
	var levy_attackers: Array[ArmyState] = land__lane_side(land__levies(4), 2)
	var guard_defenders: Array[ArmyState] = land__lane_side(land__guards(4), 1)
	var soft: Dictionary = QuickBattleActions.resolve(
		land__lane_joined(levy_attackers, guard_defenders),
		land__lane_state(levy_attackers, guard_defenders, 0),
		"attacker", "defender", "volley", [] as Array[Dictionary]
	)

	assert_eq(int(hard["defender_lost"]), 4, "the guard volley breaks the levy line")
	assert_true(int(soft["defender_lost"]) < 4, "the levy volley cannot break four guards")

## The virtual battery weighs its emplaced gun type, scaled by its remaining
## HP, instead of a flat per-gun count (wiki: quick-battle § Emplaced fort
## artillery).
func test_land_the_battery_weighs_its_gun_type_and_remaining_health() -> void:
	var guns: Array[Dictionary] = QuickBattleBattery.make(1, {}, 1)
	var royal: float = float(RegimentCatalog.strength("royal_artillery"))

	assert_almost_eq(QuickBattleBattery.strength(guns), royal, 0.01)
	QuickBattleBattery.hit(guns, 1)
	assert_almost_eq(QuickBattleBattery.strength(guns), royal * 0.5, 0.01)
	QuickBattleBattery.hit(guns, 1)
	assert_almost_eq(QuickBattleBattery.strength(guns), 0.0, 0.01, "a silenced gun weighs nothing")

func test_land_a_quick_battle_win_awards_the_general() -> void:
	var model := quick_battle_rules_Fixture.build()
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, land__guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = land__context("balanced")
	context["roster"] = roster
	context["army_general"] = {attacker.id: "general_1"}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(String(reports[0]["medal_gain"]), "general_1")
	assert_eq(int(reports[0]["medal_owner"]), 0)

func test_land_a_siege_battery_fires_while_guns_stand() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", land__guards(6), land__guards(8), 3)
	assert_eq(int(battle["quick"]["guns_start"]), 3)
	assert_true(int(battle["quick"]["guns_left"]) < 3)
	var fired: bool = false
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if String(action["action"]) == "battery":
				fired = true
	assert_true(fired, "the emplaced battery answers the assault")

## The despatch copy reads `defender_lost` on an attacker's action as losses it
## inflicted and `attacker_lost` as its own cost, so the report must add up that
## way round: every loss a side suffered is either inflicted by the enemy or paid
## by its own action.
func test_land_round_despatches_add_up_to_each_sides_losses() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("aggressive", land__guards(6), land__pikes(8), 2)
	var quick: Dictionary = battle["quick"]
	var atk_inflicted: int = 0
	var atk_own: int = 0
	var def_inflicted: int = 0
	var def_own: int = 0
	for round: Dictionary in quick["rounds"]:
		for action: Dictionary in round["actions"]:
			var entry: Dictionary = action as Dictionary
			if int(entry["side"]) == int(battle["attacker"]):
				atk_inflicted += int(entry["defender_lost"])
				atk_own += int(entry["attacker_lost"])
			else:
				def_inflicted += int(entry["attacker_lost"])
				def_own += int(entry["defender_lost"])
	assert_eq(
		def_inflicted + atk_own,
		int(quick["attacker_start"]) - int(quick["attacker_left"]),
		"every attacker loss is a despatch number"
	)
	assert_eq(
		atk_inflicted + def_own,
		int(quick["defender_start"]) - int(quick["defender_left"]),
		"every defender loss is a despatch number"
	)

func _quick_battle_rules_fight(
	plan: String, attacker_types: Array[String], defender_types: Array[String],
	fort: int = 0
) -> Dictionary:
	var model := quick_battle_rules_Fixture.build()
	model.province_data(2).fort_level = fort
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, defender_types, true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, attacker_types)
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, land__context(plan))
	return reports[0]

func test_land_a_quick_battle_pays_the_attack_price_too() -> void:
	var model := quick_battle_rules_Fixture.build()
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, land__pikes(4), true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, land__guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var charged: Array = []
	var pay := func(owner: int, cost: int) -> int:
		charged.append([owner, cost])
		return mini(cost, 40)
	var context: Dictionary = land__context("balanced")
	context["pay_attack"] = pay

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(charged, [[0, 100]], "the plate charges the same price as auto-resolve")
	assert_eq(int(reports[0]["attack_cost"]), 100)
	assert_eq(int(reports[0]["attack_paid"]), 40, "a thin purse pays what it has")
	assert_true(reports[0].has("quick"))

func land__context(plan: String) -> Dictionary:
	return {
		"quick_battle": true,
		"player_faction": 0,
		"battle_plan": plan,
		"seed": 11,
	}

func land__round_count(battle: Dictionary) -> int:
	return (battle["quick"]["rounds"] as Array).size()

func land__guards(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	return types

func land__pikes(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("pikemen")
	return types

func land__levies(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("peasant_levies")
	return types

func test_land_the_garrison_splits_into_wall_and_behind() -> void:
	var side: Array[ArmyState] = land__lane_side(["pikemen", "musketeers", "squires", "culverin"], 1)

	assert_eq(SiegeLanes.wall_ids(side).size(), 2, "infantry man the wall")
	assert_eq(SiegeLanes.behind_ids(side).size(), 2, "horse and guns wait behind")
	assert_true(SiegeLanes.is_wall_type("guards"))
	assert_false(SiegeLanes.is_wall_type("squires"))
	assert_false(SiegeLanes.is_wall_type("culverin"))
	assert_eq(SiegeLanes.describe(side), "2 on the wall · 2 behind")

## A standing gun spends the besieger's blow before the lanes: the garrison is
## sheltered while the battery answers (wiki: siege-mechanics § Quick Battle
## lanes — "spends its blow on the battery before the lanes").
func test_land_a_standing_gun_spends_the_blow_before_the_lanes() -> void:
	var defender: Array[ArmyState] = land__lane_side(
		["peasant_levies", "peasant_levies", "peasant_levies"], 1
	)
	var attacker: Array[ArmyState] = land__lane_side(["musketeers", "musketeers"], 2)
	var armies: Array[ArmyState] = land__lane_joined(attacker, defender)
	var guns: Array[Dictionary] = QuickBattleBattery.make(1, {}, 1)
	var state: Dictionary = land__lane_state(attacker, defender, 1)

	var first: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)
	assert_eq(int(first["defender_lost"]), 0, "the gun drinks the volley")
	assert_eq(int(first["battery_hit"]), 1)
	assert_eq(int(first["guns_destroyed"]), 0, "one hit does not silence a gun")

	var second: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)
	assert_eq(int(second["guns_destroyed"]), 1, "the second volley silences it")
	assert_eq(int(second["defender_lost"]), 0, "the garrison is still under cover")

	var third: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)
	assert_eq(int(third["guns_destroyed"]), 0)
	assert_true(int(third["wall_lost"]) > 0, "with the battery quiet the wall takes the fire")

## One blow bleeds no more than the deployed slice: the two lanes share one
## deployment limit, so the reserves behind it still do not die in the same
## volley (wiki: combat § Auto-resolve casualty selection).
func test_land_a_siege_blow_bleeds_no_more_than_the_deployed_slice() -> void:
	var limit: int = ArmyModifiers.deployment_limit(0, false)
	var guns_only: Array[String] = []
	for _index in 18:
		guns_only.append("culverin")
	var thick: Array[String] = ["peasant_levies", "peasant_levies"]
	for _index in 20:
		thick.append("squires")
	var attacker: Array[ArmyState] = land__lane_side(guns_only, 2)
	var defended: Array[ArmyState] = land__lane_side(thick, 1)
	var armies: Array[ArmyState] = land__lane_joined(attacker, defended)

	var split: Dictionary = SiegeLanes.strike(armies, attacker, defended, 60, limit, 3, false)

	assert_eq((split["wall"] as Array).size(), 0, "a gun-only besieger hits nothing on the wall")
	assert_eq(
		(split["behind"] as Array).size(), limit,
		"the behind lane takes the deployed slice and no more"
	)


## A siege lane holds the side's **line**, never its reserve: a garrison that
## keeps foot behind the deployment limit cannot lose them to a blow it never
## meets (wiki: combat § The line and the reserve — "a reserve adds no strength,
## takes no casualties"; quick-battle § Wings and collapse — "the reserve is
## dealt nowhere").
func test_a_siege_blow_never_bleeds_the_reserves_foot() -> void:
	var limit: int = ArmyModifiers.deployment_limit(0, false)
	var types: Array[String] = []
	for _index in 20:
		types.append("pikemen")
	for _index in 4:
		types.append("hussars")
	var defended: Array[ArmyState] = land__lane_side(types, 1)
	var attacker: Array[ArmyState] = land__lane_side(["musketeers", "musketeers"], 2)
	var armies: Array[ArmyState] = land__lane_joined(attacker, defended)
	var line: Dictionary = SiegeLanes.line_ids(defended, limit)
	assert_eq((line["wall"] as Array).size(), limit - 4, "the line's foot man the wall")
	assert_eq((line["behind"] as Array).size(), 4, "the line's horse wait behind it")
	var reserve: Array[String] = []
	for regiment_id: String in defended[0].regiments:
		if not (line["wall"] as Array).has(regiment_id) \
			and not (line["behind"] as Array).has(regiment_id):
			reserve.append(regiment_id)
	assert_eq(reserve.size(), 14, "twenty-four regiments keep fourteen in reserve")

	var split: Dictionary = SiegeLanes.strike(
		armies, attacker, defended, 5, limit, 1, false, SiegeGates.gates_for(1)
	)

	assert_eq((split["wall"] as Array).size(), 4, "a wood wall spares a share of the blow")
	for raw: Variant in split["wall"]:
		assert_true((line["wall"] as Array).has(String(raw)), "only the line's foot falls")
	for regiment_id: String in reserve:
		assert_true(defended[0].regiments.has(regiment_id), "a reserve never falls")
	assert_eq(defended[0].count(), 20, "the garrison keeps every reserve")


## The behind lane is the line's horse and guns too: an artillery blow cannot
## reach the squadrons sheltering past the deployment limit.
func test_the_behind_lane_bleeds_the_lines_horse_not_the_reserve() -> void:
	var limit: int = ArmyModifiers.deployment_limit(0, false)
	var types: Array[String] = ["pikemen", "pikemen"]
	for _index in 20:
		types.append("squires")
	var defended: Array[ArmyState] = land__lane_side(types, 1)
	var guns: Array[String] = []
	for _index in 18:
		guns.append("culverin")
	var attacker: Array[ArmyState] = land__lane_side(guns, 2)
	var armies: Array[ArmyState] = land__lane_joined(attacker, defended)
	var line: Dictionary = SiegeLanes.line_ids(defended, limit)
	assert_eq(
		(line["behind"] as Array).size(), limit - 2, "the line's horse are behind the wall"
	)

	var split: Dictionary = SiegeLanes.strike(
		armies, attacker, defended, 12, limit, 2, false, SiegeGates.gates_for(2)
	)

	assert_true((split["behind"] as Array).size() > 0, "guns drop shot over the parapet")
	for raw: Variant in split["behind"]:
		assert_true(
			(line["behind"] as Array).has(String(raw)), "only the line's horse is struck"
		)
	assert_eq(defended[0].count(), 15, "the twelve reserve squadrons stand")


## The deployment slice is read before a lane's type filter tells: the strongest
## `limit` regiments of the side are the line whatever a filter asks for, so a
## filtered draw never promotes a reserve into it (wiki: combat § The line and
## the reserve).
func test_a_filtered_draw_comes_from_the_deployed_slice() -> void:
	var army := Fixture.army(
		1, 1, 2, ["pikemen", "pikemen", "pikemen", "guards", "guards"], true
	)
	var side: Array[ArmyState] = [army]
	var line: Array[String] = []
	for entry: Dictionary in ArmyModifiers.deployed(side, 3):
		line.append(String(entry["id"]))

	var lost: Array[String] = ArmyForce.apply_losses(
		side, side, 3, 3, func(type_id: String) -> bool: return type_id == "pikemen"
	)

	assert_eq(lost.size(), 1, "only the line's one pikeman can fall")
	assert_true(line.has(lost[0]), "the casualty is a regiment of the line")
	assert_eq(army.count(), 4, "the two pikemen in reserve stand")


## The line's ascending-id tie-break is the casualty slice's too: an army of
## fourteen identical regiments keeps its ten lowest ids in the line, so the four
## highest are reserves that never fall (wiki: combat § The line and the reserve
## — "the strongest `limit` regiments stand in the line, ties broken by ascending
## regiment id").
func test_identical_regiments_keep_their_highest_ids_in_reserve() -> void:
	var types: Array[String] = []
	for _index in 14:
		types.append("pikemen")
	var army := Fixture.army(1, 1, 2, types, true)
	var side: Array[ArmyState] = [army]
	var line: Array[String] = []
	for entry: Dictionary in ArmyModifiers.deployed(side, 10):
		line.append(String(entry["id"]))
	var reserve: Array[String] = []
	for regiment_id: String in army.regiments:
		if not line.has(regiment_id):
			reserve.append(regiment_id)
	assert_eq(reserve.size(), 4, "four of the fourteen stand in reserve")

	var lost: Array[String] = ArmyForce.apply_losses(side, side, 4, 10)

	assert_eq(lost.size(), 4)
	for regiment_id: String in lost:
		assert_true(line.has(regiment_id), "the line bears the loss")
	for regiment_id: String in reserve:
		assert_true(army.regiments.has(regiment_id), "a reserve never falls")


func test_land_melee_only_besiegers_cannot_touch_a_wall() -> void:
	var attacker: Array[ArmyState] = land__lane_side(["pikemen", "knights"], 2)
	var defender: Array[ArmyState] = land__lane_side(["peasant_levies"], 1)
	var armies: Array[ArmyState] = land__lane_joined(attacker, defender)
	var wanted: int = 3

	var split: Dictionary = SiegeLanes.strike(armies, attacker, defender, wanted, 10, 2, false)

	assert_eq(int(split["turned"]), wanted, "the wall turns the pikes aside")
	assert_eq((split["wall"] as Array).size(), 0)
	assert_eq(defender[0].count(), 1, "nobody on the wall is hurt")

func test_land_firearms_hit_the_wall_and_the_fort_blunts_the_blow() -> void:
	var open_field: int = land__struck_lane_losses(2 - 2, 4)
	var stone: int = land__struck_lane_losses(2, 4)

	assert_eq(open_field, 4, "an open field takes the whole blow")
	assert_eq(stone, ceili(4.0 * FortRules.loss_scale(2)), "the wall spares a share")
	assert_true(stone < open_field)

func test_land_only_artillery_reaches_behind_the_wall() -> void:
	var muskets: Array[ArmyState] = land__lane_side(["musketeers", "musketeers"], 2)
	var guns: Array[ArmyState] = land__lane_side(["musketeers", "musketeers", "culverin"], 2)
	var defender: Array[ArmyState] = land__lane_side(["pikemen", "pikemen", "pikemen", "culverin"], 1)
	var armies: Array[ArmyState] = land__lane_joined(guns, defender)

	assert_false(SiegeLanes.can_reach_behind(muskets), "small arms stay outside")
	var shot: Dictionary = SiegeLanes.strike(armies, guns, defender, 4, 10, 2, false)

	assert_true((shot["behind"] as Array).size() > 0, "guns drop shot over the parapet")
	assert_true((shot["wall"] as Array).size() > 0)

	var walls_only: Array[ArmyState] = land__lane_side(["pikemen", "pikemen", "pikemen", "culverin"], 1)
	var field_only: Array[ArmyState] = land__lane_joined(muskets, walls_only)
	var small: Dictionary = SiegeLanes.strike(field_only, muskets, walls_only, 4, 10, 2, false)
	assert_eq((small["behind"] as Array).size(), 0, "only artillery can hit behind")

func test_land_a_sortie_sheds_the_walls_protection() -> void:
	var sheltered: int = land__struck_lane_losses(2, 6, false)
	var sortied: int = land__struck_lane_losses(2, 6, true)

	assert_eq(sheltered, ceili(6.0 * FortRules.loss_scale(2)))
	assert_eq(sortied, 6, "outside the wall the garrison takes the whole blow")
	assert_true(sortied > sheltered)

func test_land_return_fire_follows_the_garrisons_range() -> void:
	var pikes: Array[ArmyState] = land__lane_side(["pikemen", "pikemen"], 1)
	var muskets: Array[ArmyState] = land__lane_side(["musketeers", "musketeers"], 1)
	var mixed: Array[ArmyState] = land__lane_side(["pikemen", "pikemen", "musketeers", "musketeers"], 1)

	assert_almost_eq(SiegeLanes.return_fire_share(pikes), 0.0, 0.001, "pikes cannot shoot")
	assert_almost_eq(SiegeLanes.return_fire_share(muskets), 1.0, 0.001)
	assert_almost_eq(SiegeLanes.return_fire_share(mixed), 0.5, 0.001)

func test_land_an_empty_garrison_absorbs_nothing() -> void:
	var attacker: Array[ArmyState] = land__lane_side(["musketeers"], 2)
	var defender: Array[ArmyState] = []
	var split: Dictionary = SiegeLanes.strike(
		attacker, attacker, defender, 3, 10, 2, false
	)

	assert_eq((split["wall"] as Array).size(), 0)
	assert_eq((split["behind"] as Array).size(), 0)
	assert_eq(int(split["turned"]), 0)
	assert_almost_eq(SiegeLanes.return_fire_share(defender), 0.0, 0.001)
	assert_false(SiegeLanes.can_reach_wall(defender))
	assert_eq(SiegeLanes.describe(defender), "0 on the wall · 0 behind")

## A hole in an army list (a pruned army) is skipped, never crashed on.
func test_land_a_null_army_is_skipped() -> void:
	var side: Array[ArmyState] = land__lane_side(["pikemen"], 1)
	side.append(null)

	assert_eq(SiegeLanes.wall_ids(side).size(), 1)
	assert_false(SiegeLanes.behind_ids(side).size() > 0)
	assert_true(SiegeLanes.can_reach_wall(land__lane_side(["musketeers"], 2)))
	assert_false(SiegeLanes.can_reach_behind(side))

func land__struck_lane_losses(fort: int, wanted: int, exposed: bool = false) -> int:
	var attacker: Array[ArmyState] = land__lane_side(["musketeers", "musketeers", "musketeers"], 2)
	var defender: Array[ArmyState] = land__lane_side(
		["peasant_levies", "peasant_levies", "peasant_levies", "peasant_levies",
		"peasant_levies", "peasant_levies"], 1
	)
	var armies: Array[ArmyState] = land__lane_joined(attacker, defender)
	var split: Dictionary = SiegeLanes.strike(
		armies, attacker, defender, wanted, 10, fort, exposed
	)
	return (split["wall"] as Array).size() + (split["behind"] as Array).size()

func land__lane_side(types: Array[String], owner: int) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(quick_battle_rules_Fixture.army(10 + owner, owner, 2, types, true))
	return side

func land__lane_joined(first: Array[ArmyState], second: Array[ArmyState]) -> Array[ArmyState]:
	var all: Array[ArmyState] = []
	all.append_array(first)
	all.append_array(second)
	return all

## Battle state for one scripted action, shaped the way [QuickBattle] builds it.
func land__lane_state(attacker: Array[ArmyState], defender: Array[ArmyState], fort: int) -> Dictionary:
	return {
		"attacker": {
			"side": attacker, "owner": 2, "limit": 10, "mods": {},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "balanced", "exposed": false,
		},
		"defender": {
			"side": defender, "owner": 1, "limit": 10, "mods": {"fort": fort},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "defensive", "exposed": false,
		},
	}

## Every blow that breaks a regiment must show the health it took from the men
## still standing: the plate's bars and damage numbers read from these hits.
func test_land_every_action_shows_the_health_it_took() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", land__guards(6), land__guards(20))
	var counted: int = 0
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			var losses: int = int(action["attacker_lost"]) + int(action["defender_lost"])
			var hits: Array = action["hits"] as Array
			if losses <= 0:
				continue
			counted += 1
			assert_true(not hits.is_empty(), "a blow that broke a regiment mauled the rest")
			assert_eq(int(action["mauled"]), hits.size())
			for hit: Dictionary in hits:
				assert_true(int(hit["damage"]) > 0)
				assert_true(int(hit["hp"]) < int(hit["max"]))
	assert_true(counted > 0, "the fight landed blows")

func test_land_round_logs_carry_a_condition_snapshot() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", land__guards(6), land__guards(6))
	var rounds: Array = battle["quick"]["rounds"] as Array
	assert_true(not rounds.is_empty())
	for round: Dictionary in rounds:
		assert_true(round.has("attacker_health"))
		assert_true(round.has("defender_health"))
		assert_true(float(round["attacker_strength"]) <= 1.0)
		assert_true(float(round["defender_strength"]) <= 1.0)
	var last: Dictionary = rounds[rounds.size() - 1] as Dictionary
	var mauled: int = 0
	var entries: Array = (last["attacker_health"] as Array) + (last["defender_health"] as Array)
	for entry: Dictionary in entries:
		if float(entry["fraction"]) < 1.0:
			mauled += 1
	assert_true(mauled > 0, "survivors carry wounds out of the battle")

func test_land_the_battle_report_carries_aftermath_condition_and_chevrons() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", land__guards(8), land__pikes(2))
	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_true((battle["attacker_health"] as Array).size() > 0)
	assert_true(int(battle["attacker_chevrons"]) > 0)
	assert_eq(int(battle["defender_chevrons"]), 0, "the broken side wins nothing")
	assert_true(int(battle["defender_mauled"]) >= 0)

func test_land_veterans_are_deployed_ahead_of_fresh_regiments() -> void:
	var army := quick_battle_rules_Fixture.army(1, 0, 2, ["guards", "guards"])
	var veteran: String = army.regiments[0]
	army.regiment_medals[veteran] = 4
	var side: Array[ArmyState] = [army]

	var deployed: Array[Dictionary] = ArmyModifiers.deployed(side, 1)

	assert_eq(String(deployed[0]["id"]), veteran, "the chevroned regiment leads")
	assert_eq(int(deployed[0]["medals"]), 4)

## The three stances and their ordered action lists are the rules: the page
## publishes them, so a replay must be able to read them here.
func test_land_the_published_plan_scripts_match_the_wiki() -> void:
	assert_eq(QuickBattleActions.actions_for("aggressive"), ["maneuver", "assault"])
	assert_eq(QuickBattleActions.actions_for("balanced"), ["volley", "entrench", "volley"])
	assert_eq(QuickBattleActions.actions_for("defensive"), ["fall_back", "volley"])

	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, true), ["entrench", "sortie"],
		"a siege garrison with an aggressive plan entrenches then sallies"
	)
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, false),
		["entrench", "volley", "volley"],
		"a sortie with no wall is ordinary volley fire"
	)
	assert_eq(QuickBattleActions.actions_for("balanced", true, true), ["volley", "entrench"])
	assert_eq(QuickBattleActions.actions_for("balanced", true, false), ["volley", "entrench"])
	assert_eq(QuickBattleActions.actions_for("defensive", true, true), ["fall_back", "volley"])
	assert_eq(QuickBattleActions.actions_for("defensive", true, false), ["fall_back", "volley"])

## 3 CP a side each round, and no action is ever taken without its price.
func test_land_a_side_spends_at_most_three_cp_a_round() -> void:
	for plan: String in ["aggressive", "balanced", "defensive"]:
		var battle: Dictionary = _quick_battle_rules_fight(plan, land__guards(6), land__pikes(6))
		var rounds: Array = battle["quick"]["rounds"] as Array
		assert_true(not rounds.is_empty())
		for round: Dictionary in rounds:
			for side: int in [int(battle["attacker"]), int(battle["defender"])]:
				var spent: int = land__cp_spent(round, side)
				assert_true(spent <= QuickBattleTerms.CP_PER_ROUND, "%s spends %d CP" % [plan, spent])

## The side the human does not command is chosen in the published order
## (wiki: quick-battle § The opposing script): a scenario plan, the crown's own,
## the firearmless sally, a cavalry share ≥ 0.3, then the side's default.
func test_land_the_opposing_script_follows_the_published_order() -> void:
	var pikes: Array[ArmyState] = land__rival(["pikemen", "pikemen"])
	var muskets: Array[ArmyState] = land__rival(["pikemen", "musketeers"])
	assert_eq(QuickBattleTerms.plan_for(pikes, 1, {}, true, true), "aggressive",
		"a wall with no firearm sallies")
	assert_eq(QuickBattleTerms.plan_for(muskets, 1, {}, true, true), "defensive",
		"a wall that can shoot holds")
	assert_eq(QuickBattleTerms.plan_for(land__rival(["squires", "pikemen", "pikemen"]), 1, {}, false),
		"aggressive", "cavalry share ≥ 0.3")
	assert_eq(QuickBattleTerms.plan_for(land__rival(["squires", "pikemen", "pikemen", "pikemen"]), 1, {}, true, false),
		"defensive", "cavalry share below 0.3")
	assert_eq(QuickBattleTerms.plan_for(land__rival(["squires", "pikemen"]), 0, {}, false), "aggressive")
	assert_eq(QuickBattleTerms.plan_for(land__rival(["pikemen", "pikemen"]), 0, {}, false), "balanced")
	## An explicit scenario plan outranks the ranking, and the crown's plan
	## outranks the automatic sally.
	assert_eq(
		QuickBattleTerms.plan_for(pikes, 1, {"defender_battle_plan": "balanced"}, true, true),
		"balanced"
	)
	assert_eq(
		QuickBattleTerms.plan_for(pikes, 1, {"player_faction": 1, "battle_plan": "defensive"}, true, true),
		"defensive", "the crown's plan holds its own wall"
	)

## A sally is a real sortie, not a label: the firearmless garrison leaves the
## wall (wiki: siege-mechanics § Gates and Sortie).
func test_land_a_firearmless_garrison_sallies_when_no_one_commands_it() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", land__guards(4), land__pikes(10), 1)
	assert_eq(String(battle["quick"]["defender_plan"]), "aggressive")
	assert_true(int(battle["quick"]["sorties"]) > 0, "the garrison left the wall")

## Any value the page does not publish is `balanced`, wherever it came from
## (wiki: quick-battle § The crown's plan).
func test_land_an_unknown_plan_is_balanced() -> void:
	assert_eq(QuickBattleActions.normalize_plan("hammer"), "balanced")
	assert_eq(QuickBattleActions.normalize_plan(""), "balanced")
	assert_eq(QuickBattleActions.normalize_plan("defensive"), "defensive")
	assert_eq(
		QuickBattleTerms.plan_for(
			land__rival(["pikemen"]), 0, {"player_faction": 0, "battle_plan": "hammer"}, false
		),
		"balanced", "a crown's unknown stance fights balanced"
	)

func land__rival(types: Array[String]) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(quick_battle_rules_Fixture.army(7, 1, 2, types, true))
	return side

func land__cp_spent(round: Dictionary, side: int) -> int:
	var spent: int = 0
	for entry: Dictionary in round["actions"] as Array:
		if int(entry["side"]) != side:
			continue
		spent += int(QuickBattleActions.ACTION_CP.get(String(entry["action"]), 0))
	return spent

# --- from test_army_markers.gd ---
## ArmyMarkers and ArmyMuster leave ArmyLayer.
## ArmyMarkers and ArmyMuster leave ArmyLayer: marker mint/clear/place and
## opening Home Army rosters stay testable without the map screen (REQ-P3-01,
## REQ-P3-04).


func test_muster_builds_a_home_army_per_capital() -> void:
	var model := MapModel.new()
	model.region_id = 0
	model.faction_ids = [0, 1]
	var seat_a := ProvinceState.new()
	seat_a.id = 0
	seat_a.owner = 0
	seat_a.capital = true
	seat_a.center = Vector2(1, 1)
	var seat_b := ProvinceState.new()
	seat_b.id = 1
	seat_b.owner = 1
	seat_b.capital = true
	seat_b.center = Vector2(2, 2)
	model.provinces = [seat_a, seat_b]
	var muster := ArmyMuster.new()
	var armies: Array[ArmyState] = muster.build(model)
	assert_eq(armies.size(), 2)
	assert_true(armies[0].is_home_army())
	assert_true(armies[1].is_home_army())
	assert_eq(armies[0].count(), ArmyMuster.GREAT_POWER_ROSTER.size())
	assert_eq(muster.next_army, 3)


func test_markers_mint_place_and_drop() -> void:
	var model := MapModel.new()
	model.region_id = 0
	var province := ProvinceState.new()
	province.id = 0
	province.owner = 0
	province.capital = true
	province.center = Vector2(3, 4)
	model.provinces = [province]
	var army := ArmyState.muster(1, 0, 0, true, ["peasant_levies", "pikemen"], 10)
	var helpers := ArmyMarkers.new()
	helpers.model = model
	var marker: ArmyMarker = helpers.make(army)
	assert_not_null(marker)
	assert_eq(helpers.markers.size(), 1)
	helpers.place_all([army])
	assert_eq(marker.position, province.center * ArmyMarkers.TILE_SIZE)
	helpers.refresh(army)
	assert_eq(helpers.find_army(army), marker)
	helpers.remove(marker)
	assert_eq(helpers.markers.size(), 0)
	assert_null(helpers.find(1))


func test_roster_counts_every_region() -> void:
	var regions := MapRegionTable.new()
	var home := ArmyState.muster(1, 0, 0, true, ["peasant_levies", "pikemen"], 10)
	var field := ArmyState.muster(2, 0, 1, false, ["bowmen"], 20)
	regions.set_region(0, [home])
	regions.set_region(1, [field])
	assert_eq(ArmyRoster.count_all(regions, 0), 3)
	assert_eq(ArmyRoster.count_all(regions, 1), 0)
	assert_true(ArmyRoster.food_upkeep_all(regions, 0) > 0)

# ==== merged from test_quick_battle_overlay.gd (one coverage boot; docs/testing.md § Speed rules) ====
## Quick Battle plate contracts: it replays the report, skips on one tap and
## Also includes battle sim (one Godot boot).
## hands the queue back through its finished signal (REQ-P5-06).

const overlay_Fixture = preload("res://tests/map_fixture.gd")
const NAMES: Array[String] = ["España", "England"]

## One mount for the HUD plate cases: under coverage a mount costs seconds and
## each case only needs a bare chart with the news lane and the plates reset, so
## they share the chart and re-seat from the pristine save (docs/testing.md
## § Speed rules). Non-underscore: gd-tools clones a fresh suite instance per
## test and does not copy underscore fields out of before_all.
var hud_mounted: MapScreen = null
var hud_pristine: Dictionary = {}
var hud_pristine_map: Array = []


func before_all() -> void:
	hud_pristine_map = overlay_Fixture.snapshot(overlay_Fixture.world())
	hud_mounted = overlay_Fixture.attach_screen(self)
	hud_pristine = overlay_Fixture.suite_capture(hud_mounted)


func after_all() -> void:
	if is_instance_valid(hud_mounted):
		hud_mounted.free()
	hud_mounted = null
	hud_pristine = {}
	hud_pristine_map = []


## A plate case starts on the pristine chart, as a mount did: the reset drops
## the previous case's plates, queues, news and sheets.
func _hud() -> MapScreen:
	overlay_Fixture.restore(overlay_Fixture.world(), hud_pristine_map)
	overlay_Fixture.suite_reset(hud_mounted, hud_pristine)
	return hud_mounted


func test_the_plate_shows_a_battle_and_finishes_on_skip() -> void:
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	var done: Array[bool] = [false]
	overlay.finished.connect(func() -> void: done[0] = true)

	overlay.show_battle(_battle(), "Flanders", NAMES)
	await get_tree().process_frame
	overlay.field.queue_redraw()
	await get_tree().process_frame
	assert_true(overlay.is_shown())
	assert_eq(overlay.field.attacker_start, 6)
	assert_eq(overlay.field.defender_start, 4)

	overlay.skip()
	assert_true(overlay._finished)
	assert_true(overlay._continue.visible)
	assert_true(String(overlay._outcome.text).contains("takes Flanders"))

	overlay._on_continue()
	assert_true(done[0])
	assert_false(overlay.is_shown())
	overlay.free()


func test_the_plate_handles_a_battle_without_rounds() -> void:
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	overlay.show_battle({"attacker": 0, "defender": 1, "outcome": 0}, "Flanders", NAMES)
	assert_true(overlay.is_shown())
	overlay.skip()
	assert_true(overlay._finished)
	overlay.free()


func test_the_hud_mounts_the_plate_and_queues_a_second_battle() -> void:
	var screen: MapScreen = _hud()
	screen.hud.show_quick_battle(_battle(), "Flanders")
	assert_true(screen.hud.is_quick_battle_shown())
	screen.hud.show_quick_battle(_battle(), "Burgundy")
	assert_eq(screen.hud._quick_queue.size(), 1, "a second battle waits its turn")
	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_true(screen.hud.is_quick_battle_shown(), "the queued battle takes the plate")
	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_false(screen.hud.is_quick_battle_shown())


## The court's news waits for the plates: a despatch raised while a battle plays
## sits under the plate and expires unread, so the HUD holds it and raises it
## once the last plate closes (REQ-P5-06).
func test_the_courts_news_waits_for_the_battle_plates() -> void:
	var screen: MapScreen = _hud()
	var raised: int = screen.hud.despatches.box.get_child_count()
	screen.hud.show_quick_battle(_battle(), "Flanders")
	screen.hud.toast("England occupies Burgundy unopposed")
	screen.hud.toast("England storms Flanders")

	assert_eq(screen.hud.despatches.box.get_child_count(), raised, "no despatch behind the plate")
	assert_eq(screen.hud.despatches.held().size(), 2, "the news waits its turn")

	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_eq(
		screen.hud.despatches.box.get_child_count(), raised + 2,
		"the court reads it after the battle"
	)
	assert_eq(screen.hud.despatches.held().size(), 0, "nothing is left waiting")


## A second battle of the same turn keeps the news waiting until the last plate
## closes, so an earlier despatch never slips out between the fights.
func test_the_news_waits_for_every_plate_of_the_turn() -> void:
	var screen: MapScreen = _hud()
	var raised: int = screen.hud.despatches.box.get_child_count()
	screen.hud.show_quick_battle(_battle(), "Flanders")
	screen.hud.show_quick_battle(_battle(), "Burgundy")
	screen.hud.toast("Spain takes Flanders")

	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_true(screen.hud.is_quick_battle_shown(), "the second battle takes the plate")
	assert_eq(screen.hud.despatches.box.get_child_count(), raised, "still hidden under a plate")

	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_eq(
		screen.hud.despatches.box.get_child_count(), raised + 1, "the news arrives at the end"
	)


## A long turn cannot bury the court in plates: the queue keeps the newest
## despatches, which are the ones the turn's orders produced.
func test_the_news_queue_keeps_the_newest_despatches() -> void:
	var screen: MapScreen = _hud()
	screen.hud.show_quick_battle(_battle(), "Flanders")
	for index in HudDespatches.QUEUE_CAP + 2:
		screen.hud.toast("news %d" % index)

	assert_eq(screen.hud.despatches.held().size(), HudDespatches.QUEUE_CAP)
	assert_eq(String(screen.hud.despatches.held()[0]), "news 2", "the oldest lines go first")


## A full queue spends the line the plate already told before the court's own
## news: the seat lost and the court's move must never be the price of a battle
## despatch the plate narrated (REQ-P5-06).
func test_the_plate_line_goes_before_the_courts_news() -> void:
	var screen: MapScreen = _hud()
	screen.hud.show_quick_battle(_battle(), "Flanders")
	screen.hud.toast_plate_line("England takes Flanders")
	for index in HudDespatches.QUEUE_CAP - 1:
		screen.hud.toast("news %d" % index)
	# Full: the next line must not cost the court its own news.
	screen.hud.toast("Spain moves its court to Cuenca")

	var held: PackedStringArray = screen.hud.despatches.held()
	assert_eq(held.size(), HudDespatches.QUEUE_CAP)
	assert_false(held.has("England takes Flanders"), "the plate's own line goes first")
	assert_true(held.has("Spain moves its court to Cuenca"), "the court's news stays")


## A despatch states what the action did to the other side; an assault's price
## is spelled out separately, and the battery reports the men it hit.
func test_a_despatch_reports_the_losses_it_inflicted() -> void:
	var battle: Dictionary = _battle()
	var assault := {
		"side": 1, "action": "assault", "label": "Assault",
		"attacker_lost": 3, "defender_lost": 1, "guns_destroyed": 0,
	}
	assert_eq(
		QuickBattleCopy.action_line(assault, battle, NAMES),
		"England — Assault · 3 lost · 1 of its own"
	)
	var battery := {
		"side": 1, "action": "battery", "label": "Emplaced battery",
		"attacker_lost": 2, "defender_lost": 0, "guns_destroyed": 0,
	}
	assert_eq(
		QuickBattleCopy.action_line(battery, battle, NAMES),
		"England — Emplaced battery · 2 lost"
	)
	var quiet := {
		"side": 0, "action": "entrench", "label": "Entrench",
		"attacker_lost": 0, "defender_lost": 0, "guns_destroyed": 1,
	}
	assert_eq(
		QuickBattleCopy.action_line(quiet, battle, NAMES),
		"España — Entrench · 1 gun silenced"
	)
	var turned := {
		"side": 0, "action": "volley", "label": "Volley fire",
		"attacker_lost": 0, "defender_lost": 0, "guns_destroyed": 0, "turned": 2,
	}
	assert_eq(
		QuickBattleCopy.action_line(turned, battle, NAMES),
		"España — Volley fire · the wall turns it aside"
	)
	var behind := {
		"side": 0, "action": "volley", "label": "Volley fire",
		"attacker_lost": 0, "defender_lost": 1, "guns_destroyed": 0, "behind_lost": 1,
	}
	assert_eq(
		QuickBattleCopy.action_line(behind, battle, NAMES),
		"España — Volley fire · 1 lost · 1 behind the wall"
	)
	## A blow the standing battery soaked says so, or the player reads a silent
	## action and cannot tell the guns are still answering.
	var soaked := {
		"side": 0, "action": "volley", "label": "Volley fire",
		"attacker_lost": 0, "defender_lost": 0, "guns_destroyed": 0, "battery_hit": 1,
	}
	assert_eq(
		QuickBattleCopy.action_line(soaked, battle, NAMES),
		"España — Volley fire · the battery takes the blow"
	)


## The aftermath names the dead and the wall: both are written into the log the
## player reads after the plate finishes.
func test_the_aftermath_logs_the_losses_and_the_siege() -> void:
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	var battle: Dictionary = _battle()
	battle["fort_level"] = 1
	battle["defender_detail"] = {"pikemen": 2}
	battle["quick"]["lanes"] = {"wall": 2, "behind": 0}
	battle["quick"]["guns_start"] = 1
	battle["quick"]["fort_downgraded"] = true
	battle["quick"]["fort_after"] = 0

	overlay.show_battle(battle, "Flanders", NAMES)
	overlay.skip()

	var text: String = ""
	for line: Label in overlay._log.get_children():
		text += String(line.text) + "\n"
	assert_true(text.contains("Losses — England: 2 Pikemen"), text)
	assert_true(text.contains("battery silenced"), text)
	overlay.free()


## The plate must lead with the plan the player set — on the defending side the
## report's `plan` belongs to the attacker, so reading it aloud confuses the
## player about the stance they chose.
func test_the_plate_leads_with_the_players_own_plan() -> void:
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	var battle: Dictionary = _battle()
	overlay.show_battle(battle, "Flanders", NAMES)
	assert_eq(overlay._plan_label.text, "Your plan: Aggressive · enemy: Defensive")
	battle["player_faction"] = 1
	(battle["quick"] as Dictionary)["guns_start"] = 1
	overlay.show_battle(battle, "Flanders", NAMES)
	assert_eq(
		overlay._plan_label.text,
		"Your plan: Defensive · enemy: Aggressive · 1 gun",
		"the defender reads their own stance, and one gun is not \"1 guns\""
	)
	overlay.free()


## The plate names the wall it is fought over before the first round plays: the
## fort, the protection it gives, its lanes and its gates are the terms every
## action is read against, and the opening line carries no outcome — the fight
## has not been watched yet (wiki: siege-mechanics § Quick Battle lanes,
## § Gates and Sortie; REQ-P5-05).
func test_the_plate_opens_with_the_wall_it_is_fought_over() -> void:
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	var battle: Dictionary = _battle()
	battle["fort_level"] = 2
	battle["quick"]["lanes"] = {"wall": 4, "behind": 2}
	battle["quick"]["gates"] = {"max": 3, "broken": 0, "damage": 0, "threshold": 7}
	battle["quick"]["fort_downgraded"] = true
	battle["quick"]["fort_after"] = 1

	overlay.show_battle(battle, "Flanders", NAMES)

	assert_true(overlay._wall_label.visible, "a siege plate shows its wall")
	var wall: String = overlay._wall_label.text
	assert_true(wall.contains("Stone fort"), wall)
	assert_true(wall.contains("45%"), wall)
	assert_true(wall.contains("4 on the wall, 2 behind"), wall)
	assert_true(wall.contains("3 gates hold"), wall)
	assert_false(wall.contains("falls to"), "the opening must not hand over the result")

	overlay.show_battle(_battle(), "Flanders", NAMES)
	assert_false(overlay._wall_label.visible, "a field battle carries no wall")
	overlay.free()


## The opening and the close read the same wall, and only the close says what
## the battery left behind.
func test_the_wall_line_differs_only_by_the_outcome() -> void:
	var battle: Dictionary = _battle()
	battle["fort_level"] = 3
	battle["quick"]["lanes"] = {"wall": 2, "behind": 1}
	battle["quick"]["fort_downgraded"] = true
	battle["quick"]["fort_after"] = 2

	var opened: String = QuickBattleSiegeCopy.siege_opening(battle)
	var closed: String = QuickBattleSiegeCopy.siege_line(battle)

	assert_eq(closed, opened + " — battery silenced, the fort falls to Stone", closed)
	assert_eq(QuickBattleSiegeCopy.siege_opening(_battle()), "", "no wall, no line")


## The siege despatch tells the lanes, the wall's protection and the level a
## silenced battery leaves behind; a field battle says nothing extra.
func test_the_siege_despatch_names_the_lanes_and_the_breach() -> void:
	var battle: Dictionary = _battle()
	battle["fort_level"] = 2
	battle["quick"]["lanes"] = {"wall": 4, "behind": 2}
	battle["quick"]["sorties"] = 1
	battle["quick"]["fort_downgraded"] = true
	battle["quick"]["fort_after"] = 1

	var line: String = QuickBattleSiegeCopy.siege_line(battle)

	assert_true(line.contains("Stone fort"), line)
	assert_true(line.contains("45%"), "the wall's damage reduction is told")
	assert_true(line.contains("4 on the wall, 2 behind"), line)
	assert_true(line.contains("1 sortie"), line)
	assert_true(line.contains("falls to Wood"), line)
	assert_eq(QuickBattleSiegeCopy.siege_line(_battle()), "", "a field battle has no siege line")


## Gates and ground: the siege despatch names the three gates and a breach, and
## the aftermath says what the ground did to the action tables.
func test_gates_and_ground_are_told() -> void:
	var battle: Dictionary = _battle()
	battle["fort_level"] = 2
	battle["quick"]["gates"] = {"max": 3, "broken": 0, "damage": 5, "threshold": 7}
	assert_true(QuickBattleSiegeCopy.siege_line(battle).contains("3 gates hold"))
	(battle["quick"] as Dictionary)["gates"] = {
		"max": 3, "broken": 1, "damage": 7, "threshold": 7,
	}
	assert_true(QuickBattleSiegeCopy.siege_line(battle).contains("1 of 3 gates breached"))
	assert_eq(QuickBattleSiegeCopy.gates_text(_battle()["quick"]), "", "no fort, no gates")

	var ground: Dictionary = _battle()
	ground["quick"]["terrain"] = "town"
	assert_eq(
		QuickBattleCopy.terrain_line(ground),
		"Ground — Town streets: assaults −45%, volleys −30%"
	)
	assert_eq(QuickBattleCopy.terrain_line(_battle()), "", "open ground needs no line")

	var action := {
		"side": 0, "action": "volley", "label": "Volley fire",
		"attacker_lost": 0, "defender_lost": 1, "guns_destroyed": 0,
		"gates_broken": 1,
	}
	assert_true(
		QuickBattleCopy.action_line(action, battle, NAMES).contains("1 gate breached")
	)


## The plate is drawn before the first round plays, so its wall line reads the
## wall as the siege found it: three gates standing, no sally made. The breach
## and the sally are the aftermath's news (REQ-P5-05, REQ-P5-06; wiki:
## siege-mechanics § Gates and Sortie).
func test_the_plate_opens_before_a_gate_is_breached() -> void:
	var battle: Dictionary = _battle()
	battle["fort_level"] = 2
	battle["quick"]["lanes"] = {"wall": 5, "behind": 0}
	battle["quick"]["gates_open"] = {"max": 3, "broken": 0, "damage": 0, "threshold": 7}
	battle["quick"]["gates"] = {"max": 3, "broken": 2, "damage": 14, "threshold": 7}
	battle["quick"]["sorties"] = 1

	var opened: String = QuickBattleSiegeCopy.siege_opening(battle)
	assert_true(opened.contains("3 gates hold"), opened)
	assert_false(opened.contains("breached"), "the opening must not name a breach")
	assert_false(opened.contains("sortie"), "nor a sally the garrison has yet to make")

	var closed: String = QuickBattleSiegeCopy.siege_line(battle)
	assert_true(closed.contains("2 of 3 gates breached"), closed)
	assert_true(closed.contains("1 sortie"), closed)


## The plate a player meets is populated before the replay starts, so the wall
## it prints carries no breach and no sally (REQ-P5-06).
func test_the_plate_shows_no_breach_before_the_replay() -> void:
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	var battle: Dictionary = _battle()
	battle["fort_level"] = 1
	battle["quick"]["gates_open"] = {"max": 3, "broken": 0, "damage": 0, "threshold": 4}
	battle["quick"]["gates"] = {"max": 3, "broken": 1, "damage": 5, "threshold": 4}
	battle["quick"]["sorties"] = 2

	overlay.show_battle(battle, "Flanders", NAMES)

	var wall: String = overlay._wall_label.text
	assert_true(wall.contains("Wood fort"), wall)
	assert_true(wall.contains("3 gates hold"), wall)
	assert_false(wall.contains("breached"), "the replay has not been watched yet")
	assert_false(wall.contains("sortie"), "the garrison has not sallied yet")
	overlay.free()


## The painted field opens on the wall's three gates and the deal's wings: the
## breach and the break arrive with the rounds that make them (REQ-P5-06).
func test_the_field_opens_with_no_breach_and_no_broken_wing() -> void:
	var field := QuickBattleField.new()
	add_child(field)
	var battle: Dictionary = _battle()
	battle["fort_level"] = 1
	battle["quick"]["gates"] = {"max": 3, "broken": 2, "damage": 9, "threshold": 4}
	battle["quick"]["wings_open"] = {
		"attacker": {"left": 1, "center": 2, "right": 1},
		"defender": {"left": 0, "center": 3, "right": 0},
	}
	battle["quick"]["wings_broken"] = {"attacker": [], "defender": ["center"]}

	field.set_battle(battle)

	assert_eq(field.gates_broken, 0, "the plate opens on three gates")
	assert_true((field.defender_broken as Array).is_empty(), "no wing has broken yet")
	field.set_round(0, 6, 2, 0, [], [], 1)
	assert_eq(field.gates_broken, 1, "the round that breached a gate shows it")
	field.free()


## Regiment detail in the aftermath: the named types each side lost.
func test_the_loss_line_names_the_regiments() -> void:
	var battle: Dictionary = _battle()
	battle["attacker_detail"] = {"guards": 2}
	battle["defender_detail"] = {"pikemen": 3, "culverin": 1}

	assert_eq(
		QuickBattleCopy.loss_line(battle, NAMES),
		"Losses — España: 2 Guards · England: Culverin · 3 Pikemen"
	)
	assert_eq(QuickBattleCopy.loss_line(_battle(), NAMES), "", "a quiet field has no loss line")


## The line and the reserve: only a side that kept one is named, and the
## despatch counts both sides' reserves (wiki: combat § The line and the
## reserve; DR-20261111-15).
func test_the_line_and_the_reserve_are_told() -> void:
	var battle: Dictionary = _battle()
	battle["attacker_deployed"] = 10
	battle["attacker_reserve"] = 4
	battle["defender_deployed"] = 4
	battle["defender_reserve"] = 0

	assert_eq(
		QuickBattleCopy.line_line(battle, NAMES),
		"Line — España: 10 of 14 in the line"
	)
	assert_eq(
		BattleReport.line_note(battle), " — 4 regiments held in reserve"
	)
	assert_eq(QuickBattleCopy.line_line(_battle(), NAMES), "", "a full line adds no line")
	assert_eq(BattleReport.line_note(_battle()), "", "a full line adds no tail")


func _battle() -> Dictionary:
	return {
		"attacker": 0,
		"defender": 1,
		"player_faction": 0,
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"quick": {
			"plan": "aggressive",
			"defender_plan": "defensive",
			"attacker_start": 6,
			"defender_start": 4,
			"attacker_left": 4,
			"defender_left": 0,
			"guns_start": 0,
			"guns_left": 0,
			"attacker_cohesion": 2,
			"defender_cohesion": 0,
			"rounds": [
				{
					"round": 1,
					"attacker_count": 6,
					"defender_count": 2,
					"guns": 0,
					"actions": [{
						"side": 0,
						"action": "assault",
						"label": "Assault",
						"attacker_lost": 1,
						"defender_lost": 2,
						"guns_destroyed": 0,
					}],
				},
				{
					"round": 2,
					"attacker_count": 5,
					"defender_count": 0,
					"guns": 0,
					"actions": [],
				},
			],
		},
	}

## The nomadic read: every blow names the men it mauled as well as the
## regiment it broke (wiki: combat § Strength).
func test_a_despatch_reports_the_mauled() -> void:
	var action := {
		"side": 0, "action": "volley", "label": "Volley fire",
		"attacker_lost": 0, "defender_lost": 1, "mauled": 4,
	}
	assert_eq(
		QuickBattleCopy.action_line(action, _battle(), NAMES),
		"España — Volley fire · 1 lost · 4 mauled"
	)


## The plate shows the condition it was told about: a mauled survivor and the
## chevrons won, both in the log and on the field's rail (REQ-P5-05).
func test_the_plate_reads_mauled_regiments_and_chevrons() -> void:
	var battle: Dictionary = _battle()
	battle["attacker_health"] = [
		{"id": "unit_1", "type": "guards", "hp": 60, "max": 120, "medals": 1, "fraction": 0.5},
		{"id": "unit_2", "type": "guards", "hp": 120, "max": 120, "medals": 0, "fraction": 1.0},
	]
	battle["defender_health"] = []
	battle["attacker_chevrons"] = 2

	assert_eq(QuickBattleCopy.health_line(battle, NAMES), "Mauled — España: Guards 50%")
	assert_eq(
		QuickBattleCopy.chevron_line(battle, NAMES),
		"Chevrons — España: 2 regiments rise a chevron"
	)
	assert_eq(QuickBattleCopy.health_line(_battle(), NAMES), "")
	assert_eq(QuickBattleCopy.chevron_line(_battle(), NAMES), "")

	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	overlay.show_battle(battle, "Flanders", NAMES)
	overlay.skip()
	assert_eq(overlay.field.attacker_health.size(), 2, "the rail reads the aftermath")
	var text: String = ""
	for line: Label in overlay._log.get_children():
		text += String(line.text) + "\n"
	assert_true(text.contains("Mauled — España: Guards 50%"), text)
	assert_true(text.contains("2 regiments rise a chevron"), text)
	overlay.free()


## The field's name added to the winner's colours: the aftermath line the plate
## prints, and none for a field every colour already bears (DR-20261112-02).
func test_the_plate_names_the_honours_won() -> void:
	var battle: Dictionary = _battle()
	battle["attacker_honours"] = 3

	assert_eq(
		QuickBattleCopy.honour_line(battle, "Flanders", NAMES),
		"Honours — España: Flanders added to 3 colours"
	)
	assert_eq(QuickBattleCopy.honour_line(_battle(), "Flanders", NAMES), "")
	assert_eq(QuickBattleCopy.honour_line(battle, "", NAMES), "")

	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	overlay.show_battle(battle, "Flanders", NAMES)
	overlay.skip()
	var text: String = ""
	for line: Label in overlay._log.get_children():
		text += String(line.text) + "\n"
	assert_true(text.contains("Honours — España: Flanders added to 3 colours"), text)
	overlay.free()


## The colours cited for a field won while mauled: the plate line names the
## weight a citation buys, and a clean win adds none (DR-20261112-10,
## DR-20261113-04).
func test_the_plate_names_the_cited_colours() -> void:
	var battle: Dictionary = _battle()
	battle["attacker_citations"] = 2

	assert_eq(
		QuickBattleCopy.citation_line(battle, "Flanders", NAMES),
		"Citations — España: 2 colours cited at Flanders (+5% each)"
	)
	battle["attacker_citations"] = 1
	assert_eq(
		QuickBattleCopy.citation_line(battle, "Flanders", NAMES),
		"Citations — España: 1 colour cited at Flanders (+5% each)"
	)
	assert_eq(QuickBattleCopy.citation_line(_battle(), "Flanders", NAMES), "")

	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	overlay.show_battle(battle, "Flanders", NAMES)
	overlay.skip()
	var text: String = ""
	for line: Label in overlay._log.get_children():
		text += String(line.text) + "\n"
	assert_true(
		text.contains("Citations — España: 1 colour cited at Flanders (+5% each)"), text
	)
	overlay.free()


## The field floats the damage an action recorded, over the side it struck.
func test_the_field_floats_the_damage_it_was_told() -> void:
	var battle: Dictionary = _battle()
	battle["quick"]["rounds"][0]["attacker_health"] = [
		{"id": "unit_1", "type": "guards", "hp": 40, "max": 120, "medals": 0, "fraction": 0.333},
	]
	battle["quick"]["rounds"][0]["actions"][0]["hits"] = [{
		"id": "unit_2", "type": "pikemen", "damage": 12, "hp": 80, "max": 110, "medals": 0,
	}]
	var overlay := QuickBattleOverlay.new()
	add_child(overlay)
	overlay.show_battle(battle, "Flanders", NAMES)
	overlay._enter_round(0)

	assert_eq(overlay.field._floaters.size(), 1, "one number per hit")
	assert_eq(String(overlay.field._floaters[0]["text"]), "-12")
	assert_eq(overlay.field.attacker_health.size(), 1, "the rail reads the round")
	overlay.free()

# --- battle_sim ---
## The Battle Simulator's rules glue (`BattleScenario`) and its scene. The
## sandbox must run the live Quick Battle resolver, not a parallel model
## (REQ-P2-03); the screen must paint the record it gets back.

const overlay_SIM_SCENE: PackedScene = preload("res://scenes/battle_sim.tscn")


func test_overlay_the_scenario_builds_the_requested_battle() -> void:
	var spec: Dictionary = {
		"attacker": ["musketeers", "musketeers", "musketeers", "culverin"],
		"defender": ["pikemen", "pikemen", "musketeers", "culverin"],
		"fort": 2, "terrain": "woods", "seed": 3,
	}
	var result: Dictionary = BattleScenario.fight(spec)
	var report: Dictionary = result["report"]
	var quick: Dictionary = report["quick"]

	assert_eq(int(report["fort_level"]), 2)
	assert_eq(String(report["battle_mode"]), "siege")
	assert_eq(String(quick["terrain"]), "woods")
	assert_eq(String(quick["terrain_label"]), "Woods")
	assert_eq(int(quick["guns_start"]), 2, "a stone fort fields two emplaced guns")
	assert_eq(int(quick["lanes"]["wall"]), 3)
	assert_eq(int(quick["lanes"]["behind"]), 1)
	assert_eq(int((quick["gates"] as Dictionary)["max"]), 3)
	assert_eq(int(quick["attacker_start"]), 4)
	assert_eq(int(quick["defender_start"]), 4)


func test_overlay_the_scenario_runs_the_live_resolver() -> void:
	var spec: Dictionary = {
		"attacker": ["guards", "guards", "guards", "guards", "culverin"],
		"defender": ["pikemen", "pikemen", "musketeers"], "fort": 1, "terrain": "town",
		"attacker_plan": "aggressive", "defender_plan": "balanced", "seed": 11,
	}
	var first: Dictionary = BattleScenario.fight(spec)
	var scene: Dictionary = BattleScenario.build(spec)
	var direct: Dictionary = QuickBattle.resolve_exchange(
		scene["model"], scene["armies"], scene["province"], scene["defender"],
		scene["attacker"], false, scene["context"]
	)
	var sandbox: Dictionary = first["report"]

	assert_eq(int(sandbox["outcome"]), int(direct["outcome"]))
	assert_eq(
		(sandbox["defender_lost"] as Array).size(),
		(direct["defender_lost"] as Array).size()
	)
	assert_eq(
		(sandbox["attacker_lost"] as Array).size(),
		(direct["attacker_lost"] as Array).size()
	)
	assert_eq(String(sandbox["quick"]["defender_plan"]), "balanced")


func test_overlay_the_scenario_normalises_unknown_types() -> void:
	var scene: Dictionary = BattleScenario.build({
		"attacker": ["not_a_regiment"], "defender": ["pikemen"], "terrain": "open",
	})
	var armies: Array[ArmyState] = scene["armies"]
	assert_eq(armies[1].count(), 1)
	assert_eq(armies[1].type_of(armies[1].regiments[0]), RegimentCatalog.DEFAULT_TYPE)


func test_overlay_a_field_scenario_has_no_wall() -> void:
	var result: Dictionary = BattleScenario.fight({
		"attacker": ["musketeers", "musketeers"], "defender": ["pikemen", "pikemen"],
		"fort": 0, "terrain": "hill",
	})
	var quick: Dictionary = result["report"]["quick"]
	assert_eq(String(result["report"]["battle_mode"]), "field")
	assert_true((quick["gates"] as Dictionary).is_empty(), "no fort, no gates")
	assert_eq(String(quick["terrain"]), "hill")


## The published marsh id is the ground the sandbox paints (wiki: quick-battle
## § Terrain): a swamp province fights on marsh, and BattleScenario must map
## that id onto MapModel.Terrain.SWAMP — not leave the match arm dead.
func test_overlay_the_marsh_scenario_paints_swamp_ground() -> void:
	var scene: Dictionary = BattleScenario.build({
		"attacker": ["musketeers"], "defender": ["pikemen"], "terrain": "marsh",
	})
	var model: MapModel = scene["model"]
	assert_eq(model.terrain[model.index_of(2, 1)], MapModel.Terrain.SWAMP)
	assert_eq(String(scene["context"]["terrain_override"]), "marsh")


func test_overlay_every_ground_paints() -> void:
	var field := QuickBattleField.new()
	field.custom_minimum_size = Vector2(480, 320)
	field.size = Vector2(480, 320)
	add_child(field)
	for terrain: String in ["open", "hill", "woods", "town", "marsh"]:
		field.terrain = terrain
		field.fort_level = 3 if terrain == "town" else 0
		field.gates_broken = 2
		field.attacker_count = 4
		field.defender_count = 4
		field.attacker_health = []
		field.defender_health = []
		field.queue_redraw()
		await get_tree().process_frame
	assert_eq(field.terrain, "marsh")
	field.free()


## A painted plate is only as good as the asset behind it: a moved or renamed
## texture must fail here, not on a playtester's screen.
func test_overlay_the_painted_plate_assets_exist() -> void:
	for terrain: String in BattlePlate.PLATES.keys():
		var entry: Dictionary = BattlePlate.PLATES[terrain]
		assert_true(
			ResourceLoader.exists(String(entry["path"])),
			"missing plate for %s" % terrain
		)
	for fort in [1, 2, 3]:
		assert_true(
			ResourceLoader.exists(BattlePlate.WALLS[fort]), "missing wall %d" % fort
		)
	for path: String in [
		BattlePlate.SOLDIER, BattlePlate.CANNON, BattlePlate.HORSE, BattlePlate.RUBBLE,
	]:
		assert_true(ResourceLoader.exists(path), "missing %s" % path)


## --- per-type miniatures (issue #427) ---------------------------------------
## Every playable type stands as its own miniature: one sprite per catalog id,
## all painted by tools/art/regiment_miniatures.py on one scale. A type that
## falls back to the shared musketeer is a missing asset, so this fails here.


func test_every_regiment_type_has_its_own_miniature() -> void:
	var seen: Dictionary = {}
	for type_id: String in RegimentCatalog.ids():
		assert_true(RegimentMiniatures.has_art(type_id), "no miniature for %s" % type_id)
		var path: String = RegimentMiniatures.art_path(type_id)
		assert_false(seen.has(path), "%s shares another type's art" % type_id)
		seen[path] = type_id
		var tex: Texture2D = RegimentMiniatures.texture(type_id)
		assert_true(tex != null, "miniature did not load for %s" % type_id)
		var image: Image = tex.get_image()
		assert_true(image != null and image.get_height() > 0, "empty art for %s" % type_id)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update(image.get_data())
		var digest: String = ctx.finish().hex_encode()
		assert_false(
			seen.has(digest), "%s is a copy of %s" % [type_id, String(seen.get(digest, ""))]
		)
		seen[digest] = type_id
	var unknown: Texture2D = RegimentMiniatures.texture("not_a_regiment")
	assert_true(unknown != null, "an unknown type still fields a miniature")
	assert_eq(RegimentMiniatures.art_path("not_a_regiment"),
		RegimentMiniatures.art_path(RegimentCatalog.DEFAULT_TYPE),
		"an unknown type normalises to the levy's art")


## Each miniature is painted on the foot figure's scale, so a gun is drawn low
## and a rider tall instead of every type filling the same box.
func test_the_miniatures_keep_their_natural_size() -> void:
	var foot: float = RegimentMiniatures.width("musketeers", 20.0)
	var horse: float = RegimentMiniatures.width("knights", 20.0)
	var gun: Texture2D = RegimentMiniatures.texture("culverin")
	assert_true(horse > foot, "a horseman stands wider than a file of musketeers")
	assert_true(
		float(gun.get_height()) < RegimentMiniatures.FIGURE_HEIGHT * 0.8,
		"a gun sprite is painted lower than a standing man"
	)
	assert_true(
		RegimentMiniatures.spacing(_slots(["culverin"]), 20.0)
			> RegimentMiniatures.spacing(_slots(["musketeers"]), 20.0),
		"a gun needs more room in the line"
	)


## The line stands in type blocks and the caption names them in the order they
## stand, so a player can point at a block and read its type.
func test_the_line_stands_in_type_blocks_and_names_them() -> void:
	var slots: Array[Dictionary] = _slots(["musketeers", "pikemen", "musketeers", ""])
	assert_eq(slots.size(), 4)
	var named: Array[String] = []
	for slot: Dictionary in slots:
		named.append(String(slot["type"]))
	assert_eq(
		"|".join(named), "|musketeers|musketeers|pikemen",
		"same types stand together, the unnamed slot first"
	)
	assert_eq(RegimentMiniatures.caption(slots), "2 Musketeers · Pikemen")
	assert_eq(RegimentMiniatures.caption(_slots([])), "", "no men, no caption")
	assert_eq(
		RegimentMiniatures.caption(_slots(["", ""])), "",
		"a record that names no type adds no caption"
	)


## A long composition is elided to the room it has, never drawn over the other
## side's caption (a phone plate is half a desktop one).
func test_the_caption_fits_the_room_it_has() -> void:
	var slots: Array[Dictionary] = _slots([
		"guards", "guards", "pikemen", "hussars", "culverin", "bowmen",
		"arquebusiers", "siege_guns",
	])
	var text: String = RegimentMiniatures.caption(slots)
	assert_true(text.ends_with("…"), text)
	var font: Font = UiTheme.serif()
	var narrow: String = RegimentMiniatures.fit(text, 60.0, font, 11)
	assert_true(narrow.ends_with("…"), narrow)
	assert_true(
		font.get_string_size(narrow, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x <= 60.0,
		"the cut caption still fits its room: %s" % narrow
	)
	assert_eq(
		RegimentMiniatures.fit("2 Pikemen", 400.0, font, 11), "2 Pikemen",
		"a caption with room to spare is untouched"
	)


## A cold cache loads the art once and keeps it; a caption with no room draws
## nothing rather than squeezing a word into a gap.
func test_the_miniature_table_loads_once_and_a_caption_needs_room() -> void:
	RegimentMiniatures._cache.clear()
	var first: Texture2D = RegimentMiniatures.texture("guards")
	var second: Texture2D = RegimentMiniatures.texture("guards")
	assert_true(first != null, "a cold cache still finds the miniature")
	assert_true(first == second, "the second read is the cached texture")
	var field := QuickBattleField.new()
	field.size = Vector2(200, 200)
	add_child(field)
	## No room, or nothing to say: the caption draws nothing (the field's own
	## frame covers the drawing path).
	RegimentMiniatures.draw_caption(field, "", Vector2.ZERO, 160.0, Palette.TEXT, 11)
	RegimentMiniatures.draw_caption(field, "2 Pikemen", Vector2.ZERO, 4.0, Palette.TEXT, 11)
	field.free()


## The plate itself: a battle record's types are painted and named on the field,
## both in the simulator and in the live plate (one shared view).
func test_the_field_paints_each_type_and_names_the_line() -> void:
	var field := QuickBattleField.new()
	field.custom_minimum_size = Vector2(520, 360)
	field.size = Vector2(520, 360)
	add_child(field)
	field.attacker_color = Palette.CRIMSON
	field.defender_color = Palette.NAVY
	field.attacker_count = 3
	field.defender_count = 2
	field.attacker_health = [
		{"id": "a", "type": "guards", "hp": 120, "max": 120, "medals": 0, "fraction": 1.0},
		{"id": "b", "type": "cuirassiers", "hp": 110, "max": 110, "medals": 1, "fraction": 1.0},
		{"id": "c", "type": "culverin", "hp": 80, "max": 80, "medals": 0, "fraction": 1.0},
	]
	field.defender_health = [
		{"id": "d", "type": "pikemen", "hp": 110, "max": 110, "medals": 0, "fraction": 0.6},
		{"id": "e", "type": "bowmen", "hp": 80, "max": 80, "medals": 0, "fraction": 1.0},
	]
	field.queue_redraw()
	await get_tree().process_frame

	var slots: Array[Dictionary] = RegimentMiniatures.slots(field.attacker_health, 3, 12)
	assert_eq(
		RegimentMiniatures.caption(slots), "Cuirassiers · Culverin · Guards",
		"the plate names what the attacker fielded"
	)
	assert_true(
		RegimentMiniatures.width("cuirassiers", 20.0) > RegimentMiniatures.width("guards", 20.0),
		"the rider is drawn on its own miniature, not the musketeer's"
	)
	var defender: Array[Dictionary] = RegimentMiniatures.slots(field.defender_health, 2, 12)
	assert_eq(RegimentMiniatures.caption(defender), "Bowmen · Pikemen")
	field.free()


func _slots(types: Array) -> Array[Dictionary]:
	var entries: Array = []
	for index in types.size():
		entries.append({"type": String(types[index]), "fraction": 1.0, "medals": 0})
	return RegimentMiniatures.slots(entries, entries.size(), 12)


## The wall must read as a fortification: taller than a man, with the garrison
## standing on the parapet above the field line.
func test_overlay_the_wall_towers_over_the_garrison() -> void:
	for fort in [1, 2, 3]:
		var wall: float = BattlePlate.wall_height(600.0, fort)
		assert_true(wall > BattlePlate.soldier_height(600.0) * 1.5, "wall too low")
		assert_true(BattlePlate.parapet_y(600.0, fort) < 600.0 * BattlePlate.GROUND)
	assert_true(
		BattlePlate.wall_height(600.0, 3) > BattlePlate.wall_height(600.0, 1),
		"a later fort stands taller"
	)


func test_overlay_the_simulator_scene_fights_and_steps() -> void:
	var screen: BattleSimScreen = overlay_SIM_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame

	screen._fight()
	assert_false(screen._result.is_empty(), "Fight resolves the current setup")
	assert_true(screen._log.text.contains("ROUND"), "the despatch is printed")
	assert_true(screen._log.text.contains("OUTCOME"))
	assert_true(screen._field.fort_level >= 0)

	screen._step()
	assert_true(screen._status.text.contains("Round") or screen._status.text.contains("No rounds"))
	screen._reset()
	assert_true(screen._result.is_empty())
	assert_eq(screen._field.attacker_count, 0)

	screen.free()


# --- the sea's despatch plate (wiki: ships-and-naval § Naval Combat Resolution)

func _sea_battle() -> Dictionary:
	return {
		"attacker": 0,
		"defender": 1,
		"attacker_strength": 182.0,
		"defender_strength": 121.0,
		"attacker_before": 6,
		"defender_before": 4,
		"attacker_hulls": [
			"galleon", "galleon", "galleon", "galleon", "sloop", "sloop",
		],
		"defender_hulls": ["carrack", "carrack", "carrack", "carrack"],
		"attacker_lost": [],
		"attacker_lost_names": [],
		"defender_lost": ["a", "b", "c", "d"],
		"defender_lost_names": ["Trinidad", "Concepcion"],
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"retreat": {},
	}


func test_the_sea_plate_tells_the_despatch_and_finishes_on_skip() -> void:
	var plate := NavalPlate.new()
	add_child(plate)
	var done: Array[bool] = [false]
	plate.finished.connect(func() -> void: done[0] = true)

	plate.show_engagement(_sea_battle(), "Mar Caribe", NAMES)
	assert_true(plate.is_shown())
	assert_true(plate._headline.text.contains("España against England"))
	assert_true(plate._headline.text.contains("Mar Caribe"))

	plate.skip()
	assert_true(plate._continue.visible, "the whole despatch is told at once")
	assert_true(plate._outcome.text.contains("España holds the Mar Caribe"))
	assert_true(plate._log.get_child_count() <= NavalPlate.LOG_LINES)
	var told: PackedStringArray = PackedStringArray()
	for child in plate._log.get_children():
		told.append(String((child as Label).text))
	assert_true(" ".join(told).contains("England loses 4 ships"), "the dead are named")

	plate._on_continue()
	assert_true(done[0])
	assert_false(plate.is_shown())
	plate.free()


func test_the_sea_plate_stands_one_medallion_per_hull_type() -> void:
	var plate := NavalPlate.new()
	add_child(plate)
	plate.show_engagement(_sea_battle(), "Mar Caribe", NAMES)
	plate.skip()
	# Two types under the attacker's line (Galleon, Sloop), one under England's.
	var chips: int = 0
	for line: HBoxContainer in plate.side_lines():
		chips += line.get_child_count() - 1
	assert_eq(chips, 3, "one medallion per type, the name aside")
	plate.free()


## The plates are the HUD's, not the chart's: this case rides the suite's one
## mount like its neighbours (`_hud()`), so a second `MapScreen` boot under
## coverage is not paid to read two queues (docs/testing.md § Speed rules).
func test_the_hud_replays_sea_and_land_plates_one_at_a_time() -> void:
	var screen: MapScreen = _hud()
	screen.hud.show_naval_dispatch(_sea_battle(), "Mar Caribe")
	assert_true(screen.hud.naval_plate.is_shown(), "the sea's despatch takes the court")
	screen.hud.show_naval_dispatch(_sea_battle(), "Golfo de México")
	assert_eq(screen.hud._naval_queue.size(), 1, "the second engagement waits its turn")
	screen.hud.show_quick_battle(_battle(), "Flanders")
	assert_eq(screen.hud._quick_queue.size(), 1, "a land battle queues behind the sea")
	screen.hud.naval_plate.skip()
	screen.hud.naval_plate._on_continue()
	assert_true(screen.hud.is_quick_battle_shown(), "land resolved first, so land is served first")
	screen.hud.quick_battle_overlay.skip()
	screen.hud.quick_battle_overlay._on_continue()
	assert_true(screen.hud.naval_plate.is_shown(), "the queued sea fight takes the plate")
	screen.hud.naval_plate.skip()
	screen.hud.naval_plate._on_continue()
	assert_false(screen.hud.is_quick_battle_shown())
	assert_false(screen.hud.naval_plate.is_shown())

# --- The line's wings (wiki: quick-battle § Wings and collapse; DR-20261117-08)


## The deployed line is dealt into three wings: the horse alternates between the
## flanks, strongest first, and the foot and guns hold the centre.
func test_the_line_is_dealt_into_three_wings() -> void:
	var side: Array[ArmyState] = _lane_side(
		["musketeers", "musketeers", "knights", "squires", "culverin"], 2
	)
	var held: Dictionary = QuickBattleWings.counts(QuickBattleWings.deploy(side, 10))

	assert_eq(int(held["center"]), 3, "foot and guns hold the centre")
	assert_eq(int(held["left"]), 1, "the strongest horse takes the left")
	assert_eq(int(held["right"]), 1, "the second horse the right")
	assert_eq(QuickBattleWings.describe(held), "L 1 · C 3 · R 1")
	assert_eq(
		QuickBattleWings.ids(QuickBattleWings.deploy(side, 10), "left").size(), 1,
		"a wing hands out the men who stand on it"
	)
	assert_eq(QuickBattleWings.ids({}, "left").size(), 0, "no wings, nobody to break")


## A crown that fields no horse leaves both flanks open: there is no wing there
## to lose, and nothing for a charge to fall on.
func test_a_line_with_no_horse_fights_on_its_centre() -> void:
	var side: Array[ArmyState] = _lane_side(["pikemen", "pikemen", "musketeers"], 2)
	var held: Dictionary = QuickBattleWings.counts(QuickBattleWings.deploy(side, 10))

	assert_eq(int(held["center"]), 3)
	assert_eq(int(held["left"]) + int(held["right"]), 0, "no horse, no flanks")


## Fire falls on the fullest part of the line, a charge on its thinnest, and an
## action that strikes nobody names no wing at all.
func test_fire_falls_on_the_fullest_wing_and_a_charge_on_the_thinnest() -> void:
	var held: Dictionary = {"left": 1, "center": 5, "right": 2}

	assert_eq(QuickBattleWings.target(held, "volley"), "center")
	assert_eq(QuickBattleWings.target(held, "assault"), "left")
	assert_eq(QuickBattleWings.target(held, "sortie"), "left")
	assert_eq(QuickBattleWings.target(held, "entrench"), "", "no blow, no wing")
	assert_eq(
		QuickBattleWings.target({"left": 0, "center": 0, "right": 0}, "volley"), "",
		"an empty line is no target"
	)


## The flank beside a broken wing is turned; a turn on the far side of the line
## does not reach across it.
func test_a_flank_beside_a_broken_wing_is_turned() -> void:
	assert_almost_eq(QuickBattleWings.turned_scale("center", []), 1.0, 0.001)
	assert_almost_eq(QuickBattleWings.turned_scale("center", ["left"]), 1.2, 0.001)
	assert_almost_eq(QuickBattleWings.turned_scale("center", ["left", "right"]), 1.35, 0.001)
	assert_almost_eq(
		QuickBattleWings.turned_scale("left", ["right"]), 1.0, 0.001,
		"a broken right does not turn the left"
	)


## A wing breaks when its last regiment falls, and the break is named once —
## never again on a later blow.
func test_a_wing_breaks_when_its_last_regiment_falls() -> void:
	var side: Array[ArmyState] = _lane_side(["pikemen", "knights"], 2)
	var state: Dictionary = {
		"attacker": {
			"side": side, "owner": 2, "limit": 10, "mods": {}, "cohesion": 3,
			"guard": 0.0, "lost": [] as Array[String], "plan": "balanced",
			"exposed": false,
			"wings": QuickBattleWings.deploy(side, 10),
			"broken": [] as Array[String],
		},
	}
	var horse: Array = (state["attacker"]["wings"] as Dictionary)["left"]
	assert_eq(horse.size(), 1, "the horseman holds the left alone")
	side[0].remove_regiment(String(horse[0]))

	assert_eq(QuickBattleWings.fell(state, "attacker"), ["left"] as Array[String])
	assert_eq(
		QuickBattleWings.fell(state, "attacker"), [] as Array[String], "named once"
	)
	assert_eq(
		(state["attacker"]["broken"] as Array).size(), 1, "the line remembers the wing"
	)


## A blow falls on one wing: the horse standing on the other flank of the same
## line takes nothing from it.
func test_a_blow_falls_on_one_wing_only() -> void:
	var target: Array[ArmyState] = _lane_side(
		["pikemen", "pikemen", "knights", "squires"], 1
	)
	var attacker: Array[ArmyState] = _lane_side(_guards(6), 2)
	var armies: Array[ArmyState] = _lane_joined(attacker, target)
	var state: Dictionary = _lane_state(attacker, target, 0)
	state["defender"]["wings"] = QuickBattleWings.deploy(target, 10)
	var wings: Dictionary = state["defender"]["wings"]
	var flanks: Array = (wings["left"] as Array) + (wings["right"] as Array)

	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", [] as Array[Dictionary]
	)

	assert_eq(String(entry["wing"]), "center", "the fire falls on the foot")
	assert_true(int(entry["defender_lost"]) > 0)
	for regiment_id: String in flanks:
		assert_true(
			target[0].regiments.has(regiment_id), "the horse on the flank is untouched"
		)


## The same volley into a line whose left wing has broken is heavier: the flank
## is turned.
func test_a_turned_flank_costs_the_line_more() -> void:
	assert_true(
		int(_wing_volley(["left"])["defender_lost"]) > int(_wing_volley([])["defender_lost"])
	)


## One volley into a levy line's centre, with the defender's broken wings given.
func _wing_volley(broken: Array) -> Dictionary:
	var target: Array[ArmyState] = _lane_side(_levies(10), 1)
	var attacker: Array[ArmyState] = _lane_side(_guards(8), 2)
	var armies: Array[ArmyState] = _lane_joined(attacker, target)
	var state: Dictionary = _lane_state(attacker, target, 0)
	state["defender"]["wings"] = QuickBattleWings.deploy(target, 10)
	state["defender"]["broken"] = broken
	return QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", [] as Array[Dictionary]
	)


## A battle in the open writes its wings into the record: the counts it opened
## with, and the wings each round left standing.
func test_a_field_battle_records_the_wings_its_lines_stand_in() -> void:
	var battle: Dictionary = _fight(
		"balanced",
		["guards", "guards", "knights", "squires"],
		["pikemen", "pikemen", "musketeers", "knights"]
	)
	var quick: Dictionary = battle["quick"]
	var opened: Dictionary = quick["wings_open"]["attacker"]

	assert_eq(int(opened["left"]), 1, "the horse holds the flanks")
	assert_eq(int(opened["right"]), 1)
	assert_eq(int(opened["center"]), 2, "the foot the centre")
	for round: Dictionary in quick["rounds"]:
		assert_true(round.has("wings"), "every round records the wings it left")
		assert_true(round.has("wings_broken"))
	assert_false(
		QuickBattleCopy.wings_line(battle, ["España", "England"]).is_empty(),
		"the plate can name the line's wings"
	)


## A wall has no wings: a garrison stands on its parapet and its lanes stay the
## wall and what waits behind it (wiki: siege-mechanics § Quick Battle lanes).
func test_a_siege_garrison_holds_no_wings() -> void:
	var battle: Dictionary = _fight(
		"balanced", _guards(8), ["pikemen", "musketeers", "culverin"], 2
	)
	var quick: Dictionary = battle["quick"]

	assert_eq(int(quick["wings_open"]["attacker"]["center"]), 8, "the siege line is deployed")
	assert_eq(
		int(quick["wings_open"]["defender"]["center"]), 0, "the garrison holds no wings"
	)
	assert_eq(int(quick["lanes"]["wall"]), 2, "the wall lanes are unchanged")


## The wings line names a break, and skips a side that holds no wings at all.
func test_the_wings_line_names_a_broken_wing() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"quick": {
			"wings_open": {
				"attacker": {"left": 1, "center": 2, "right": 1},
				"defender": {"left": 0, "center": 0, "right": 0},
			},
			"wings": {
				"attacker": {"left": 0, "center": 1, "right": 1},
				"defender": {"left": 0, "center": 0, "right": 0},
			},
			"wings_broken": {"attacker": ["left"], "defender": []},
		},
	}
	var text: String = QuickBattleCopy.wings_line(battle, ["España", "England"])

	assert_true(text.contains("L 1 · C 2 · R 1"), text)
	assert_true(text.contains("→ L 0 · C 1 · R 1"), text)
	assert_true(text.contains("left broken"), text)
	assert_false(text.contains("England"), "a side with no wings is not named")


## The wings line lists several breaks as prose, not as a chain of "and": a line
## that has lost all three wings reads "right, left and centre broken".
func test_the_wings_line_lists_three_breaks_as_prose() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"quick": {
			"wings_open": {"attacker": {"left": 1, "center": 2, "right": 1}},
			"wings": {"attacker": {"left": 0, "center": 0, "right": 0}},
			"wings_broken": {"attacker": ["left", "center", "right"]},
		},
	}
	var text: String = QuickBattleCopy.wings_line(battle, ["España", "England"])

	assert_true(text.contains("left, centre and right broken"), text)
	assert_false(text.contains(" and centre and "), text)


## A field battle's plate opens on the deal it was fought over, never on the
## breaks the fight has yet to make: the stand-through and the "→" tail are the
## aftermath's (REQ-P5-05, REQ-P5-06; wiki: quick-battle § Wings and collapse).
func test_the_plate_opens_on_the_deal_not_the_breaks() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"quick": {
			"wings_open": {
				"attacker": {"left": 1, "center": 2, "right": 1},
				"defender": {"left": 0, "center": 3, "right": 0},
			},
			"wings": {
				"attacker": {"left": 1, "center": 1, "right": 1},
				"defender": {"left": 0, "center": 0, "right": 0},
			},
			"wings_broken": {"attacker": [], "defender": ["center"]},
		},
	}

	var opened: String = QuickBattleCopy.wings_opening(battle, NAMES)

	assert_eq(opened, "Wings — España: L 1 · C 2 · R 1 · England: L 0 · C 3 · R 0", opened)
	assert_false(opened.contains("→"), "the opening must not read the aftermath")
	assert_false(opened.contains("broken"), "no wing has broken when the plate opens")

	var closed: String = QuickBattleCopy.wings_line(battle, NAMES)
	assert_true(closed.contains("→ L 0 · C 0 · R 0"), closed)
	assert_true(closed.contains("centre broken"), closed)


## A blow lands on a wing that still holds men: when the enemy line has lost its
## last regiment the blow names no wing at all, because a name would point at
## the fallen (wiki: quick-battle § Wings and collapse).
func test_a_blow_into_an_empty_line_names_no_wing() -> void:
	var attacker: Array[ArmyState] = _lane_side(_guards(6), 2)
	var spent: Array[ArmyState] = _lane_side([] as Array[String], 1)
	var armies: Array[ArmyState] = _lane_joined(attacker, spent)
	var state: Dictionary = _lane_state(attacker, spent, 0)
	state["defender"]["wings"] = QuickBattleWings.deploy(spent, 10)

	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", [] as Array[Dictionary]
	)

	assert_eq(String(entry["wing"]), "", "a name would point at the fallen")
	assert_eq(int(entry["defender_lost"]), 0)


## A wing beside one that has broken is taken in flank, and the blow keeps the
## scale so the despatch can say why the same fire cost more: one neighbour
## turned, both encircled (wiki: quick-battle § Wings and collapse).
func test_a_turned_flank_is_named_on_the_blow() -> void:
	var turned: Dictionary = _wing_volley(["left"])
	var encircled: Dictionary = _wing_volley(["left", "right"])

	assert_eq(float(turned["flank"]), QuickBattleWings.TURNED_SCALE, "one neighbour")
	assert_eq(float(encircled["flank"]), QuickBattleWings.ENCIRCLED_SCALE, "both")
	assert_true(_line_text(turned).contains("its flank is turned"), _line_text(turned))
	assert_true(
		_line_text(encircled).contains("taken from three sides"), _line_text(encircled)
	)
	assert_false(
		_line_text(_wing_volley([])).contains("flank"),
		"an intact wing reads plainly"
	)


## A break is named on the line whose wing it was: the enemy's as "the …", the
## actor's own as "its own …", and never merged into one clause (wiki:
## quick-battle § Wings and collapse).
func test_a_break_names_the_line_it_broke() -> void:
	var action: Dictionary = {
		"side": 2, "label": "Assault", "attacker_lost": 1, "defender_lost": 2,
		"wing": "right", "wing_broken": ["right"], "own_broken": ["left"],
	}

	var text: String = _line_text(action)

	assert_true(text.contains("into the right"), text)
	assert_true(text.contains("the right breaks"), text)
	assert_true(text.contains("its own left breaks"), text)
	assert_false(text.contains("right and left"), "the two lines are not merged")


## A sally is told where it costs: the sortie leaves the parapet, so the wall no
## longer shelters the garrison that round (wiki: quick-battle § Turn structure
## and actions — Sortie; siege-mechanics § Gates and Sortie).
func test_a_sortie_says_the_wall_stands_open() -> void:
	var action: Dictionary = {
		"side": 1, "label": "Sortie", "sortie": true,
		"attacker_lost": 2, "defender_lost": 1,
	}

	var text: String = _line_text(action)

	assert_true(text.contains("the wall stands open"), text)
	assert_false(
		_line_text({"side": 1, "label": "Volley fire"}).contains("wall"),
		"firing from the wall names no opening"
	)


## Two wings lost at once read as one plural clause: "the left and right break".
func test_two_wings_breaking_read_as_a_plural() -> void:
	var action: Dictionary = {
		"side": 2, "label": "Assault", "attacker_lost": 1, "defender_lost": 2,
		"wing": "right", "wing_broken": ["left", "right"],
	}

	var text: String = _line_text(action)

	assert_true(text.contains("the left and right break"), text)


## A line that has lost its last regiment spends no point and delivers no blow:
## the fight ends on the blow that emptied it, mid-round as between rounds
## (wiki: quick-battle § Outcome and integration).
func test_a_spent_line_takes_no_more_actions() -> void:
	var battle: Dictionary = _fight("balanced", _guards(12), _levies(1))
	var quick: Dictionary = battle["quick"]
	var emptied: bool = false
	for round: Dictionary in quick["rounds"] as Array:
		if int(round["defender_count"]) == 0:
			emptied = true
		for action: Dictionary in round["actions"] as Array:
			if int(action["side"]) != int(battle["defender"]):
				continue
			assert_false(
				emptied,
				"the emptied line still acted in round %s" % round["round"]
			)
	assert_true(emptied, "the fight emptied the defender's line")


## A battle whose own assault empties one of its wings writes that break on the
## actor's own line, never among the enemy's (wiki: quick-battle § Wings and
## collapse).
func test_the_record_keeps_the_actors_own_break_apart() -> void:
	var battle: Dictionary = _fight(
		"aggressive",
		["guards", "guards", "guards", "guards", "knights", "squires"],
		["pikemen", "pikemen", "musketeers", "lancers", "cossacks"]
	)
	var named: int = 0
	for round: Dictionary in battle["quick"]["rounds"] as Array:
		for action: Dictionary in round["actions"] as Array:
			if (action.get("own_broken", []) as Array).is_empty():
				continue
			named += 1
			assert_true(
				_line_text(action).contains("its own"), _line_text(action)
			)
	assert_true(named > 0, "an assault that breaks its own wing names it apart")


## The despatch of one blow, as the plate prints it.
func _line_text(action: Dictionary) -> String:
	return QuickBattleCopy.action_line(
		action, {"attacker": 2, "defender": 1}, ["España", "England"]
	)


## The garrison's emplaced guns are a blow like any other: they fire into one
## wing of the besieging line — the fullest — and the men on the other wings are
## untouched (wiki: quick-battle § Wings and collapse).
func test_the_battery_fires_into_one_wing() -> void:
	var line: Array[ArmyState] = _lane_side(
		["squires", "pikemen", "pikemen", "pikemen"], 0
	)
	var wings: Dictionary = QuickBattleWings.deploy(line, 10)
	var flank: Array = wings["left"] as Array
	assert_eq(flank.size(), 1, "the horseman holds the left alone")
	var state: Dictionary = _battery_state(line, wings)

	var shot: Dictionary = QuickBattleBattery.fire(
		line, state, QuickBattleBattery.make(2, {}, 1)
	)

	assert_eq(String(shot["wing"]), "center", "the guns are laid on the mass")
	assert_eq(int(shot["lost"]), 1)
	assert_true(line[0].regiments.has(String(flank[0])), "the flank takes nothing")


## A wing beside one the line has lost is taken in flank, and the garrison's
## guns are no exception: the same fire into a turned wing costs the line more.
func test_the_battery_takes_a_turned_flank() -> void:
	assert_eq(
		int(_battery_shot(["left"])["lost"]), 2, "the turned centre takes two"
	)
	assert_eq(
		int(_battery_shot([])["lost"]), 1, "the same fire into an intact wing takes one"
	)


## One round of the battery into a 14-regiment centre, with the wings already
## broken given. Two guns break `ceil(0.06 × 14 × turn)` men.
func _battery_shot(broken: Array) -> Dictionary:
	var line: Array[ArmyState] = _lane_side(_repeat("pikemen", 14), 0)
	var wings: Dictionary = QuickBattleWings.deploy(line, 20)
	var state: Dictionary = _battery_state(line, wings, broken)
	return QuickBattleBattery.fire(line, state, QuickBattleBattery.make(2, {}, 1))


## A battle state for one round of the garrison's guns, shaped the way
## [QuickBattle] builds it.
func _battery_state(
	line: Array[ArmyState], wings: Dictionary, broken: Array = []
) -> Dictionary:
	return {
		"attacker": {
			"side": line, "owner": 0, "limit": 20, "cohesion": 3, "guard": 0.0,
			"lost": [] as Array[String], "plan": "balanced", "exposed": false,
			"wings": wings, "broken": broken,
		},
	}


## A line with no wings at all (a hand-built state, a record made before wings
## existed) is still bled as one deployed slice, and names no wing.
func test_the_battery_bleeds_a_line_with_no_wings() -> void:
	var line: Array[ArmyState] = _lane_side(_repeat("pikemen", 20), 0)
	var state: Dictionary = _battery_state(line, {})

	var shot: Dictionary = QuickBattleBattery.fire(
		line, state, QuickBattleBattery.make(3, {}, 1)
	)

	assert_eq(String(shot["wing"]), "", "no wings, no wing named")
	assert_eq(int(shot["lost"]), 2, "three guns on twenty men: ceil(0.09 × 20)")


## The record the battery writes agrees with the line that stands: its rounds
## count the same men the wings do, it names the wing it fires into, and a wing
## its fire empties breaks on that blow, not on someone else's later action
## (wiki: quick-battle § Wings and collapse, § Outcome and integration).
func test_a_battery_blow_names_its_wing_and_the_break_it_makes() -> void:
	var battle: Dictionary = _fight(
		"balanced",
		["squires", "pikemen", "pikemen", "pikemen", "pikemen", "pikemen",
			"pikemen", "knights"],
		["musketeers", "musketeers", "musketeers", "culverin", "culverin"],
		2,
		## The garrison holds its wall (no fall back), so the fight is the guns'
		## own and no stance spends cohesion the record would have to explain.
		"balanced"
	)
	var quick: Dictionary = battle["quick"]
	assert_eq(int(quick["guns_start"]), 2, "a level-2 fort's battery stands")
	var fired: int = 0
	var broke_on_the_guns: bool = false
	for round: Dictionary in quick["rounds"]:
		var held: Dictionary = (round["wings"] as Dictionary)["attacker"]
		var standing: int = 0
		for wing: String in QuickBattleWings.WINGS:
			standing += int(held[wing])
		assert_eq(
			standing, int(round["attacker_count"]),
			"round %s's wings count the line that stands" % round["round"]
		)
		for action: Dictionary in round["actions"]:
			if String(action["action"]) != "battery":
				continue
			fired += 1
			assert_false(
				String(action.get("wing", "")).is_empty(),
				"the guns name the wing they fire into"
			)
			if not (action.get("wing_broken", []) as Array).is_empty():
				broke_on_the_guns = true
	assert_true(fired > 0, "the battery answers the siege")
	assert_true(broke_on_the_guns, "a wing the guns empty is named broken on their blow")
	var final: Dictionary = (quick["wings"] as Dictionary)["attacker"]
	assert_eq(
		int(final["left"]) + int(final["center"]) + int(final["right"]),
		int(quick["attacker_left"]), "the record's wings agree with the line left"
	)

# --- the line and the reserve in Quick Battle (wiki: combat § The line and the
# reserve; DR-20261111-15; quick-battle § Wings and collapse) ------------------


## A battle deals its line once, when it opens. A side that keeps a reserve
## keeps it whole: no blow breaks a man held behind the line, and no blow mauls
## him (wiki: combat § The line and the reserve — "a reserve adds no strength,
## takes no casualties, and takes no battle wear").
func test_a_reserve_is_never_broken_nor_mauled() -> void:
	var battle: Dictionary = _fight("balanced", _guards(60), _guards(14))
	var quick: Dictionary = battle["quick"]

	assert_eq(int(quick["defender_left"]), 4, "the four reserves stand")
	var survivors: Array = battle["defender_health"] as Array
	assert_eq(survivors.size(), 4, "every survivor was held in reserve")
	for entry: Dictionary in survivors:
		assert_almost_eq(
			float(entry["fraction"]), 1.0, 0.001,
			"a reserve takes no wear: %s" % String(entry["id"])
		)


## The plate names the line a side kept even when every man in it has fallen:
## the count is read when the battle opens, not from the survivors' strongest
## slice (wiki: combat § The line and the reserve — "the battle plate prints
## `Line — <crown> N of M in the line` for each side that kept a reserve").
func test_the_line_a_side_kept_is_named_after_its_line_falls() -> void:
	var battle: Dictionary = _fight("balanced", _guards(60), _guards(14))

	assert_eq(int(battle["defender_deployed"]), 10, "ten stood in the line")
	assert_eq(int(battle["defender_reserve"]), 4, "four were spared")
	var text: String = QuickBattleCopy.line_line(battle, FactionCatalog.names())
	assert_true(
		text.contains("10 of 14 in the line"),
		"the plate still names the line and the reserve: %s" % text
	)


## A reserve adds no strength: the outcome reads the line's survivors, so a side
## whose line is gone cannot out-weigh the enemy with men who never fought
## (wiki: combat § The line and the reserve; quick-battle § Outcome and
## integration).
func test_a_reserve_adds_no_strength_to_the_outcome() -> void:
	var side: Array[ArmyState] = [Fixture.army(2, 1, 2, _guards(14))]
	var line: Array[String] = ArmyForce.line_ids(side, 10)
	assert_eq(line.size(), 10, "ten of the fourteen are dealt into the line")
	for regiment_id: String in line:
		side[0].remove_regiment(regiment_id)

	assert_almost_eq(
		QuickBattleTerms.effective_strength(side, 10, 3, 1.0, 0.0, line), 0.0, 0.001,
		"four reserves weigh nothing"
	)
	assert_true(
		QuickBattleTerms.effective_strength(side, 10, 3, 1.0) > 0.0,
		"a state with no dealt line keeps the older read"
	)
	assert_eq(
		QuickBattleLine.standing({"defender": {"side": side, "limit": 10}}, "defender"),
		4
	)
	assert_eq(
		QuickBattleLine.standing(
			{"defender": {"side": side, "limit": 10, "line": line}}, "defender"
		),
		0, "the line is gone, so the side has no fight left"
	)


## ...and the auto-resolve report names the line it opened with, not the
## survivors' strongest slice (wiki: combat § The line and the reserve).
func test_an_auto_resolve_report_names_the_line_it_opened_with() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, _guards(14), true)
	var attacker := Fixture.army(2, 0, 2, _guards(14))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})
	var settled: Dictionary = reports[0] as Dictionary

	assert_eq(int(settled["attacker_deployed"]), 10)
	assert_eq(int(settled["attacker_reserve"]), 4, "the reserve is still named")
	assert_eq(
		int(settled["attacker_deployed"]) + int(settled["attacker_reserve"]), 14,
		"the line and the reserve still add up to the side it opened with"
	)


# --- fort capital grant (from test_fort_capital) --------------------------------
## An Old World capital opens behind a Wood wall, and a Great Power's fort tech
## lifts its own capital one level once (wiki: siege-mechanics § Fort Levels;
## issue #919). Hand-built charts: a province id is its index in `provinces`.

const OLD_WORLD: int = FactionCatalog.OLD_WORLD
const NEW_WORLD: int = FactionCatalog.NEW_WORLD

var great_power: int = FactionCatalog.PLAYER_FACTION
var other_power: int = FactionCatalog.great_power_ids()[1]
var minor: int = FactionCatalog.minor_ids()[0]


## One chart with one capital province per entry of `owners`, in order.
func _fort_capital_chart(region_id: int, owners: Array) -> MapModel:
	var model := MapModel.new()
	model.region_id = region_id
	model.setup(owners.size() * 2, 2)
	for index in owners.size():
		var tiles: Array[Vector2i] = []
		model.provinces.append(ProvinceState.create(
			index, "Province %d" % index, tiles, Vector2.ZERO, 1,
			int(owners[index]), true
		))
	return model


func _fort_capital_world(model: MapModel) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(model)
	return world


# --- start grant -------------------------------------------------------------


## Both kinds of Old World seat — Great Power and Minor — open behind a Wood
## wall, and the bootstrap reports what it raised.
func test_every_old_world_capital_opens_behind_a_wood_wall() -> void:
	var model: MapModel = _fort_capital_chart(OLD_WORLD, [great_power, other_power, minor])
	var report: Dictionary = WorldBootstrap.apply(model, LandWorks.new())
	assert_eq(int(report["capital_forts"]), 3, "every capital was walled")
	for province: ProvinceState in model.provinces:
		assert_eq(
			province.fort_level, FortCapital.START_LEVEL,
			"capital of %d is Wood" % province.owner
		)
		assert_eq(
			FortRules.level_name(province.fort_level), "Wood",
			"the start level is the Wood tier"
		)


## A New World chart keeps its tribe seats open: the grant is an Old World rule.
func test_a_new_world_seat_is_left_open() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var model: MapModel = _fort_capital_chart(NEW_WORLD, [tribe])
	var report: Dictionary = WorldBootstrap.apply(model, LandWorks.new())
	assert_eq(int(report["capital_forts"]), 0)
	assert_eq(model.provinces[0].fort_level, 0, "a tribe's seat carries no wall")


## The grant only raises: a hand-built chart that already walls its seat keeps
## the wall it drew.
func test_the_grant_never_lowers_a_wall() -> void:
	var model: MapModel = _fort_capital_chart(OLD_WORLD, [great_power])
	model.provinces[0].fort_level = FortRules.MAX_LEVEL
	assert_eq(FortCapital.seed(model), 0)
	assert_eq(model.provinces[0].fort_level, FortRules.MAX_LEVEL)


# --- the free bump -----------------------------------------------------------


## Mine Engineering lifts the crown's own capital to Stone and Modern Forts to
## Modern, each at its own unlock; a repeat read of the same study moves nothing.
func test_a_great_power_fort_tech_lifts_its_capital_once() -> void:
	var model: MapModel = _fort_capital_chart(OLD_WORLD, [great_power])
	var world: WorldMap = _fort_capital_world(model)
	FortCapital.seed(model)
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["mine_engineering"]}),
		FortCapital.LEVELS["mine_engineering"],
		"the crown's capital reaches Stone"
	)
	assert_eq(model.provinces[0].fort_level, 2)
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["mine_engineering"]}),
		0, "the same study never bumps twice"
	)
	assert_eq(model.provinces[0].fort_level, 2)
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["modern_forts"]}),
		FortCapital.LEVELS["modern_forts"],
		"Modern Forts carries the capital to the top tier"
	)
	assert_eq(model.provinces[0].fort_level, 3)


## A court that finishes a study without a wall in it keeps its wall as it was.
func test_a_study_with_no_fort_in_it_moves_nothing() -> void:
	var model: MapModel = _fort_capital_chart(OLD_WORLD, [great_power])
	var world: WorldMap = _fort_capital_world(model)
	FortCapital.seed(model)
	assert_eq(FortCapital.apply_research(world, great_power, {"researched": ["navigation"]}), 0)
	assert_eq(FortCapital.apply_research(world, great_power, {}), 0)
	assert_eq(model.provinces[0].fort_level, 1)


## Minors never take the free bump: their walls are what an Engineer builds
## (wiki: siege-mechanics § Fort Levels — the grant is a Great Power rule).
func test_a_minor_keeps_only_the_wall_it_built() -> void:
	var model: MapModel = _fort_capital_chart(OLD_WORLD, [minor])
	var world: WorldMap = _fort_capital_world(model)
	FortCapital.seed(model)
	assert_eq(model.provinces[0].owner, minor)
	assert_eq(FortCapital.apply_research(world, minor, {"researched": ["modern_forts"]}), 0)
	assert_eq(model.provinces[0].fort_level, 1, "a Minor stays at its Wood wall")


## The bump is a moment, not a floor: a capital taken down by a siege is not
## raised again by the rule that once lifted it. Only a later fort study of its
## own lifts it (Modern Forts below).
func test_a_siege_downgrade_is_not_restored() -> void:
	var model: MapModel = _fort_capital_chart(OLD_WORLD, [great_power])
	var world: WorldMap = _fort_capital_world(model)
	FortCapital.seed(model)
	FortCapital.apply_research(world, great_power, {"researched": ["mine_engineering"]})
	assert_eq(model.provinces[0].fort_level, 2)
	model.provinces[0].fort_level = 0  # the besieging train took the last gun
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["navigation"]}),
		0, "a later turn's study restores nothing"
	)
	assert_eq(model.provinces[0].fort_level, 0, "the wall stays down until rebuilt")
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["modern_forts"]}),
		FortCapital.LEVELS["modern_forts"], "only its own fort study lifts it again"
	)
	assert_eq(model.provinces[0].fort_level, 3)


## A capital already above the unlock's level is left where it stands.
func test_a_wall_above_the_unlock_is_left_alone() -> void:
	var model: MapModel = _fort_capital_chart(OLD_WORLD, [great_power])
	var world: WorldMap = _fort_capital_world(model)
	model.provinces[0].fort_level = FortRules.MAX_LEVEL
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["mine_engineering"]}),
		0
	)
	assert_eq(model.provinces[0].fort_level, FortRules.MAX_LEVEL)


# --- the turn close ----------------------------------------------------------


## The turn close reads both books: the rivals' rows and the crown's own report
## name the studies that finished, and each Great Power's capital follows its
## own ledger. A rival's row is the whole economy report, so its research phase
## rides under `research` — the shape `EconomyTurn.resolve` files and the
## Gazette and spy despatch read.
func test_the_turn_close_lifts_each_courts_own_capital() -> void:
	var model: MapModel = _fort_capital_chart(OLD_WORLD, [great_power, other_power, minor])
	FortCapital.seed(model)
	var play := PlaySession.new()
	play.world = _fort_capital_world(model)
	play.player_faction = great_power
	var book := MapPlayTurnFinish.TurnBook.new()
	book.crown_report = {"research": {"researched": ["modern_forts"]}}
	book.economy_report = {"factions": {
		other_power: {"resolved": {"research": {"researched": ["mine_engineering"]}}},
		minor: {"resolved": {"research": {"researched": ["modern_forts"]}}},
	}}
	MapPlayTurnFinish._fort_upgrades(play, book)
	assert_eq(model.provinces[0].fort_level, 3, "the crown's capital reached Modern")
	assert_eq(model.provinces[1].fort_level, 2, "the rival's capital reached Stone")
	assert_eq(model.provinces[2].fort_level, 1, "the Minor keeps its Wood wall")


## A rival's row is the economy report, not the research report: the step reads
## the nested `research` slot the ledger files. A row whose top level carries no
## research phase moves nothing, and a row that is not a report at all is
## skipped rather than trusted.
func test_the_turn_close_reads_the_nested_research_report() -> void:
	var model: MapModel = _fort_capital_chart(OLD_WORLD, [great_power, other_power])
	FortCapital.seed(model)
	var play := PlaySession.new()
	play.world = _fort_capital_world(model)
	play.player_faction = great_power
	var book := MapPlayTurnFinish.TurnBook.new()
	book.crown_report = {}
	book.economy_report = {"factions": {
		other_power: {"resolved": {"consumption": {}, "researched": ["mine_engineering"]}},
	}}
	MapPlayTurnFinish._fort_upgrades(play, book)
	assert_eq(
		model.provinces[1].fort_level, 1,
		"a study filed outside the research phase lifts no wall"
	)
	book.economy_report = {"factions": {other_power: {"resolved": null}}}
	MapPlayTurnFinish._fort_upgrades(play, book)
	assert_eq(model.provinces[1].fort_level, 1, "a row with no report is skipped")
	book.economy_report = {"factions": {other_power: {"resolved": {"research": null}}}}
	MapPlayTurnFinish._fort_upgrades(play, book)
	assert_eq(model.provinces[1].fort_level, 1, "a row with no research phase is skipped")


# --- the plan scripts' cohesion (wiki: quick-battle § Turn structure and actions)


## A manoeuvre is a reposition, never a rest: it hands no step of cohesion back.
func test_a_manoeuvre_never_banks_a_step_of_cohesion() -> void:
	var side: Array[ArmyState] = _lane_side(_guards(4), 2)
	var state: Dictionary = _cohesion_state(side, "open")
	state["attacker"]["cohesion"] = 1

	var entry: Dictionary = QuickBattleActions.resolve(
		_lane_joined(side, _lane_side(_levies(4), 1)), state, "attacker", "defender",
		"maneuver", [] as Array[Dictionary]
	)

	assert_eq(
		int(state["attacker"]["cohesion"]), 1, "the line keeps the footing it has"
	)
	assert_eq(int(entry["cohesion_lost"]), 0, "open ground, an intact line: no step")
	assert_eq(String(entry["cohesion_why"]), "")


## A manoeuvre costs a step only while the line is under pressure — it has
## already lost men — and nothing over broken ground with the line intact: the
## ground charges the blow itself (wiki: quick-battle § Turn structure and
## actions; DR-20261120-07).
func test_a_manoeuvre_costs_a_step_under_pressure() -> void:
	var intact: Dictionary = _manoeuvre("woods", [] as Array[String])
	assert_eq(
		int(intact["state"]["attacker"]["cohesion"]), 3,
		"broken ground alone costs no step: the blow is already the weaker for it"
	)
	assert_eq(int(intact["entry"]["defender_lost"]), 0, "a manoeuvre strikes nobody")

	var press: Dictionary = _manoeuvre("open", ["r1"] as Array[String])
	assert_eq(int(press["state"]["attacker"]["cohesion"]), 2, "pressure costs a step")
	assert_eq(String(press["entry"]["cohesion_why"]), "under pressure")


## One attacker manoeuvre from cohesion 3 over `terrain`, the acting line's own
## losses given.
func _manoeuvre(terrain: String, lost: Array[String]) -> Dictionary:
	var side: Array[ArmyState] = _lane_side(_guards(4), 2)
	var state: Dictionary = _cohesion_state(side, terrain)
	state["attacker"]["lost"] = lost
	var entry: Dictionary = QuickBattleActions.resolve(
		_lane_joined(side, _lane_side(_levies(4), 1)), state, "attacker", "defender",
		"maneuver", [] as Array[Dictionary]
	)
	return {"state": state, "entry": entry}


## A fall back trades a step of cohesion for the space it gives, and the
## despatch prices it in words (wiki: quick-battle § Turn structure and actions —
## "this trades space and cohesion for preservation of forces").
func test_a_fall_back_trades_a_step_of_cohesion() -> void:
	var side: Array[ArmyState] = _lane_side(_guards(4), 2)
	var state: Dictionary = _cohesion_state(side, "open")
	var entry: Dictionary = QuickBattleActions.resolve(
		_lane_joined(side, _lane_side(_levies(4), 1)), state, "attacker", "defender",
		"fall_back", [] as Array[Dictionary]
	)

	assert_eq(int(state["attacker"]["cohesion"]), 2, "the line gives a step")
	assert_true(float(entry["guard"]) > 0.0, "and keeps the shelter it fell back into")
	assert_eq(
		QuickBattleCopy.action_line(entry, {"attacker": 2}, ["", "", "Spain"]),
		"Spain — Fall back · cohesion -1, the line gives ground"
	)


## Cohesion never runs below zero: a line under pressure that has spent its
## footing spends no more, and the stance still lands.
func test_cohesion_never_falls_below_zero() -> void:
	var side: Array[ArmyState] = _lane_side(_guards(4), 2)
	var state: Dictionary = _cohesion_state(side, "town")
	state["attacker"]["cohesion"] = 0
	state["attacker"]["lost"] = ["r1"] as Array[String]

	var entry: Dictionary = QuickBattleActions.resolve(
		_lane_joined(side, _lane_side(_levies(4), 1)), state, "attacker", "defender",
		"maneuver", [] as Array[Dictionary]
	)

	assert_eq(int(state["attacker"]["cohesion"]), 0, "the floor holds")
	assert_eq(int(entry["cohesion_lost"]), 0, "a step it cannot pay is not printed")
	assert_eq(QuickBattleActions.cohesion_cost("maneuver", {"lost": []}), 0)


## Battle state shaped the way [QuickBattle] builds it, with the ground given.
func _cohesion_state(side: Array[ArmyState], terrain: String) -> Dictionary:
	var state: Dictionary = _lane_state(side, _lane_side(_levies(4), 1), 0)
	state["terrain"] = terrain
	state["attacker"]["line"] = ArmyForce.line_ids(side, 10)
	state["attacker"]["broken"] = [] as Array[String]
	return state
