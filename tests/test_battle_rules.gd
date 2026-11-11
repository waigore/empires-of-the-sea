extends GdToolsTest
## Pure battle contracts: army modifiers, army state, battle reports, naval
## combat and generals.
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).

const Fixture = preload("res://tests/army_fixture.gd")
const FACTIONS: Array[String] = ["España", "England", "France", "Portugal"]

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
	assert_almost_eq(ArmyModifiers.leader_multiplier("frederick"), 1.15, 0.001)
	assert_almost_eq(ArmyModifiers.leader_multiplier(""), 1.0, 0.001)
	assert_eq(ArmyModifiers.fallback_medals("napoleon"), 4)
	assert_eq(ArmyModifiers.fallback_medals("frederick"), 2)
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

	var lost: Array[String] = ArmyCombat.apply_losses([army], side, 4, 10)

	assert_eq(lost.size(), 4)
	for regiment_id: String in reserve_ids:
		assert_true(army.regiments.has(regiment_id), "a reserve is never a casualty")


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

	var result: Dictionary = ArmyState.split(armies, army, ids, 2)

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
	assert_false(bool(ArmyState.split(armies, army, none, 2)["ok"]))
	var foreign: Array[String] = ["unit_999"]
	assert_false(bool(ArmyState.split(armies, army, foreign, 2)["ok"]))
	assert_eq(army.count(), 1)


func test_emptying_a_field_army_removes_it_but_the_home_army_persists() -> void:
	var home := Fixture.army(1, 0, 0, ["pikemen"], true)
	var field := Fixture.army(2, 0, 1, ["pikemen"])
	var armies: Array[ArmyState] = [home, field]
	var home_ids: Array[String] = ["unit_101"]
	var field_ids: Array[String] = ["unit_201"]

	ArmyState.split(armies, field, field_ids, 3)
	ArmyState.split(armies, home, home_ids, 4)

	assert_false(armies.has(field))
	assert_true(armies.has(home))
	assert_true(home.is_empty())


func test_combine_uses_the_home_army_as_the_target() -> void:
	var field := Fixture.army(1, 0, 0, ["pikemen"])
	var home := Fixture.army(2, 0, 0, ["squires"], true)
	var armies: Array[ArmyState] = [field, home]
	var selected: Array[ArmyState] = [field, home]

	var result: Dictionary = ArmyState.combine(armies, selected)

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

	var result: Dictionary = ArmyState.combine(armies, selected)

	assert_true(bool(result["ok"]))
	assert_eq(result["army"], first)
	assert_eq(first.count(), 2)
	assert_false(armies.has(second))


func test_combine_rejects_armies_in_different_provinces() -> void:
	var here := Fixture.army(1, 0, 0, ["pikemen"])
	var there := Fixture.army(2, 0, 1, ["pikemen"])
	var armies: Array[ArmyState] = [here, there]
	var selected: Array[ArmyState] = [here, there]

	var result: Dictionary = ArmyState.combine(armies, selected)

	assert_false(bool(result["ok"]))
	assert_eq(armies.size(), 2)
	assert_eq(here.count(), 1)
	assert_eq(there.count(), 1)


func test_combine_requires_two_armies() -> void:
	var army := Fixture.army(1, 0, 0, ["pikemen"])
	var armies: Array[ArmyState] = [army]
	var selected: Array[ArmyState] = [army]
	assert_false(bool(ArmyState.combine(armies, selected)["ok"]))


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

	var result: Dictionary = ArmyState.split(armies, army, ids, 2)

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

	var result: Dictionary = ArmyState.combine(armies, selected)

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
	ArmyState.prune(armies)
	assert_eq(armies.size(), 1)
	assert_true(armies.has(home))

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
		"España takes Flanders — England loses 2 regiments"
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
		"España holds the field at Flanders — 1 regiments lost"
	)


func test_a_land_repulse_reads_as_a_hold() -> void:
	var battle: Dictionary = {
		"attacker": 1,
		"defender": 2,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"attacker_lost": ["a"],
		"defender_lost": [],
	}
	assert_eq(
		BattleReport.describe_land(battle, "Burgundy", FACTIONS),
		"France holds Burgundy — England loses 1 regiments"
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
	assert_eq(ArmyCommand.medals(side, {"leaders": {0: "frederick"}}), 2)
	assert_eq(ArmyCommand.medals(side, {}), 0)


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
	assert_eq(QuickBattle.actions_for("aggressive"), ["maneuver", "assault"])
	assert_eq(QuickBattleActions.actions_for("defensive"), ["fall_back", "volley"])
	assert_eq(QuickBattleActions.actions_for("unknown"), ["volley", "entrench", "volley"])


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
		"England seize 5 cargo (3 grain, 2 timber) off the Mar Caribe — no hull lost"
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
		"England seize 3 grain off the Mar Caribe and sink the Fluyte Vrouw Maria"
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

	var split: Dictionary = ArmyState.split(armies, army, [pikes], 9)
	assert_true(bool(split["ok"]))
	var field: ArmyState = split["army"] as ArmyState
	assert_eq(int(field.condition_of(pikes)["hp"]), 40, "the wounded stay wounded")
	assert_eq(int(field.condition_of(pikes)["medals"]), 3, "the chevrons travel")

	var selected: Array[ArmyState] = [army, field]
	var merged: Dictionary = ArmyState.combine(armies, selected)
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
