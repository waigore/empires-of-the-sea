extends GdToolsTest
## Pure catalog contracts (leaders, factions, regiments, tech, civilians,
## commodities, ships, recipes, soundtrack, regiment economy).
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).

const ROLE_NAMES: Dictionary = {
	"explorer": "Explorer",
	"engineer": "Engineer",
	"builder": "Builder",
	"spy": "Spy",
	"merchant": "Merchant",
	"rail_builder": "Rail Builder",
}
const MANUFACTURED_ROWS: Dictionary = {
	"lumber": 60,
	"fabric": 80,
	"castIron": 160,
	"refinedSugar": 70,
	"cigars": 80,
	"furHats": 110,
	"steel": 170,
	"paper": 60,
	"bronze": 145,
}
const ROSTER: Array[String] = [
	"carrack",
	"fluyte",
	"sloop",
	"trader",
	"galleon",
	"indiaman",
	"frigate",
	"raider",
	"ship_of_the_line",
	"clipper",
	"merchant_steamship",
	"ironclad",
]

# --- from test_leader_catalog.gd ---
## Leader roster, key matching and the faction -> leaderKey map
## (wiki: leader-bonuses, naming § Naming Model).


func test_every_great_power_fields_exactly_one_default_leader() -> void:
	var seen: Dictionary = {}
	for faction: int in FactionCatalog.great_power_ids():
		var keys: Array[String] = LeaderCatalog.keys_for(faction)
		assert_eq(keys.size(), 1, "crown %d fields one leader variant" % faction)
		assert_eq(LeaderCatalog.default_key(faction), keys[0], "first variant is the default")
		var key: String = keys[0]
		assert_false(seen.has(key), "leader key %s is not shared" % key)
		seen[key] = true
		assert_true(LeaderCatalog.label(key) != "")


func test_minors_tribes_and_unknown_factions_reserve_the_neutral_leader() -> void:
	for faction: int in FactionCatalog.minor_ids() + FactionCatalog.tribe_ids():
		assert_eq(LeaderCatalog.default_key(faction), LeaderCatalog.DEFAULT_KEY)
		assert_true(LeaderCatalog.keys_for(faction).is_empty())
	assert_eq(LeaderCatalog.default_key(-1), LeaderCatalog.DEFAULT_KEY)


func test_bonus_table_matches_the_documented_multipliers() -> void:
	assert_almost_eq(LeaderCatalog.multiplier_for("napoleon"), 1.25, 0.001)
	assert_almost_eq(LeaderCatalog.multiplier_for("frederick"), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.multiplier_for("reserve"), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.multiplier_for(""), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.multiplier_for("isabella"), 1.0, 0.001)
	assert_eq(LeaderCatalog.bonus_percent("napoleon"), 25)
	assert_eq(LeaderCatalog.bonus_percent("isabella"), 0)


func test_variant_ids_match_exactly_first_then_by_substring() -> void:
	assert_almost_eq(LeaderCatalog.multiplier_for("france_napoleon_leader"), 1.25, 0.001)
	assert_almost_eq(LeaderCatalog.multiplier_for("Prussia_Frederick_Leader"), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.multiplier_for("unknown_court"), 1.0, 0.001)


func test_roster_assigns_the_choice_to_the_human_crown_only() -> void:
	var roster: Dictionary = LeaderCatalog.roster(2, "napoleon")
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(roster.has(faction), "crown %d has a leader" % faction)
	assert_eq(roster[2], "napoleon")
	assert_eq(roster[0], LeaderCatalog.default_key(0), "rivals keep their config leader")
	var refused: Dictionary = LeaderCatalog.roster(2, "isabella")
	assert_eq(refused[2], "napoleon", "a crown cannot field another crown's leader")


func test_saved_map_keeps_known_keys_and_backfills_missing_crowns() -> void:
	var saved: Dictionary = {0: "isabella", 2: "napoleon", 3: "invented_leader", 99: "napoleon"}
	var restored: Dictionary = LeaderCatalog.from_saved(saved)
	assert_eq(restored[0], "isabella")
	assert_eq(restored[2], "napoleon")
	assert_eq(restored[3], LeaderCatalog.default_key(3), "unknown keys are dropped")
	assert_false(restored.has(99), "non-Great-Power rows are ignored")
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(restored.has(faction), "crown %d backfilled" % faction)


func test_ai_personality_reads_the_same_default_leader() -> void:
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(AiPersonality.leader_for(faction), LeaderCatalog.default_key(faction))

# --- from test_faction_catalog.gd ---
## Faction roster and capability table (wiki: factions).


func test_default_roster_matches_the_configured_counts() -> void:
	assert_eq(FactionCatalog.great_power_ids().size(), 6)
	assert_eq(FactionCatalog.minor_ids().size(), 3)
	assert_eq(FactionCatalog.tribe_ids().size(), 10)
	assert_eq(FactionCatalog.count(), 19)


func test_ids_are_unique_and_resolvable() -> void:
	var seen: Dictionary = {}
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		assert_false(seen.has(id), "duplicate faction id %d" % id)
		seen[id] = true
		assert_eq(int(FactionCatalog.get_faction(id)["id"]), id)
		assert_true(FactionCatalog.name_of(id) != "")


func test_only_great_powers_win_and_submit_orders() -> void:
	for id: int in FactionCatalog.great_power_ids():
		assert_true(FactionCatalog.can_win(id))
		assert_true(FactionCatalog.submits_orders(id))
		assert_true(FactionCatalog.has_navy(id))
	for id: int in FactionCatalog.minor_ids() + FactionCatalog.tribe_ids():
		assert_false(FactionCatalog.can_win(id))
		assert_false(FactionCatalog.submits_orders(id))
		assert_false(FactionCatalog.has_navy(id))


func test_region_ownership_matches_faction_type() -> void:
	for id: int in FactionCatalog.great_power_ids():
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.OLD_WORLD))
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.NEW_WORLD))
	for id: int in FactionCatalog.minor_ids():
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.OLD_WORLD))
		assert_false(FactionCatalog.can_own_region(id, FactionCatalog.NEW_WORLD))
	for id: int in FactionCatalog.tribe_ids():
		assert_false(FactionCatalog.can_own_region(id, FactionCatalog.OLD_WORLD))
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.NEW_WORLD))


func test_minors_have_military_parity_but_tribes_do_not() -> void:
	for id: int in FactionCatalog.minor_ids():
		assert_true(FactionCatalog.has_military_parity(id))
	for id: int in FactionCatalog.tribe_ids():
		assert_false(FactionCatalog.has_military_parity(id))


func test_unknown_ids_fall_back_to_unclaimed() -> void:
	assert_eq(FactionCatalog.name_of(-1), "Unclaimed")
	assert_eq(FactionCatalog.type_of(-1), -1)
	assert_false(FactionCatalog.can_own_region(-1, FactionCatalog.OLD_WORLD))
	assert_false(FactionCatalog.has_faction(999))


func test_region_labels_and_keys_are_defined() -> void:
	assert_eq(FactionCatalog.region_label(FactionCatalog.OLD_WORLD), "Old World")
	assert_eq(FactionCatalog.region_label(FactionCatalog.NEW_WORLD), "New World")
	assert_eq(FactionCatalog.region_key(FactionCatalog.NEW_WORLD), "new_world")
	assert_eq(FactionCatalog.ids_in_region(FactionCatalog.NEW_WORLD), FactionCatalog.tribe_ids())


func test_names_are_indexed_by_faction_id() -> void:
	var names: Array[String] = FactionCatalog.names()
	assert_eq(names.size(), FactionCatalog.count())
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		assert_eq(names[id], FactionCatalog.name_of(id))

# --- from test_regiment_catalog.gd ---
## Regiment roster and economy values (wiki: military-units § Regiment Table,
## military-generals § Regiment treasury cost scale).


func test_catalog_lists_every_regiment_once() -> void:
	var ids: Array[String] = RegimentCatalog.ids()
	assert_eq(ids.size(), 29)
	var seen: Dictionary = {}
	for type_id: String in ids:
		assert_false(seen.has(type_id), "duplicate regiment %s" % type_id)
		seen[type_id] = true
		assert_eq(RegimentCatalog.display_name(type_id), String(RegimentCatalog.row(type_id)["name"]))


func test_tactical_stats_match_the_wiki_table() -> void:
	assert_eq(RegimentCatalog.stat("peasant_levies", "fpn"), 0)
	assert_eq(RegimentCatalog.stat("peasant_levies", "fpm"), 3)
	assert_eq(RegimentCatalog.stat("guards", "fpn"), 12)
	assert_eq(RegimentCatalog.stat("guards", "fpm"), 10)
	assert_eq(RegimentCatalog.stat("siege_guns", "rng"), 12)
	assert_eq(RegimentCatalog.stat("carbine_cavalry", "mvr"), 9)
	assert_eq(RegimentCatalog.era("guards"), 4)
	assert_eq(RegimentCatalog.era("culverin"), 1)


func test_categories_drive_cavalry_and_infantry_rules() -> void:
	assert_true(RegimentCatalog.is_cavalry("squires"))
	assert_true(RegimentCatalog.is_cavalry("cuirassiers"))
	assert_false(RegimentCatalog.is_cavalry("guards"))
	assert_true(RegimentCatalog.is_artillery("royal_artillery"))
	assert_false(RegimentCatalog.is_infantry("field_artillery"))
	assert_true(RegimentCatalog.is_infantry("bowmen"))
	assert_true(RegimentCatalog.is_infantry("peasant_levies"))


func test_treasury_costs_follow_the_canonical_scale() -> void:
	assert_eq(RegimentCatalog.treasury_cost("peasant_levies"), 2000)
	assert_eq(RegimentCatalog.treasury_cost("arquebusiers"), 5000)
	assert_eq(RegimentCatalog.treasury_cost("siege_guns"), 22000)


func test_food_upkeep_keeps_cavalry_and_artillery_highest() -> void:
	assert_eq(RegimentCatalog.food_upkeep("peasant_levies"), 1)
	assert_eq(RegimentCatalog.food_upkeep("pikemen"), 2)
	assert_eq(RegimentCatalog.food_upkeep("guards"), 3)
	assert_eq(RegimentCatalog.food_upkeep("squires"), 3)
	assert_eq(RegimentCatalog.food_upkeep("culverin"), 3)


func test_unknown_types_fall_back_to_peasant_levies() -> void:
	assert_eq(RegimentCatalog.normalize("dragoons"), RegimentCatalog.DEFAULT_TYPE)
	assert_eq(RegimentCatalog.display_name("dragoons"), "Regiment")
	assert_false(RegimentCatalog.has_type("dragoons"))


func test_garrison_recovery_uses_the_most_advanced_infantry_for_the_era() -> void:
	assert_eq(RegimentCatalog.garrison_type_for(4), "guards")
	assert_eq(RegimentCatalog.garrison_type_for(1), "arquebusiers")
	assert_eq(RegimentCatalog.garrison_type_for(9), RegimentCatalog.DEFAULT_TYPE)

# --- from test_tech_catalog.gd ---
## The static tech catalog and its audit (wiki: tech-tree § Catalog,
## tech-and-extraction-cap § Static catalog validation).


func test_catalog_holds_the_full_wiki_tree() -> void:
	assert_eq(TechCatalog.TECHS.size(), TechAudit.EXPECTED_COUNT)
	assert_eq(TechCatalog.ids().size(), TechCatalog.TECHS.size())
	assert_eq(TechAudit.validate(), [] as Array[String])
	assert_true(TechCatalog.roots().size() >= 7, "several starting techs")


func test_costs_follow_the_era_formula() -> void:
	var costs: Dictionary = {}
	for tech_id: String in TechCatalog.ids():
		costs[TechCatalog.cost(tech_id)] = true
	assert_eq(costs.size(), 4)
	assert_true(costs.has(1800))
	assert_true(costs.has(2400))
	assert_true(costs.has(3000))
	assert_true(costs.has(3600))
	assert_eq(TechCatalog.cost("crop_rotation"), 1800)
	assert_eq(TechCatalog.cost("saw_mill"), 1800)
	assert_eq(TechCatalog.cost("wind_saw_mill"), 2400)
	assert_eq(TechCatalog.cost("circular_saw"), 3000)
	assert_eq(TechCatalog.cost("safety_lamp"), 3600)


func test_prerequisites_cross_categories() -> void:
	assert_has(TechCatalog.prerequisites("circular_saw"), "university")
	assert_has(TechCatalog.prerequisites("dynamite"), "banking")
	assert_has(TechCatalog.prerequisites("dynamite"), "explosives")
	assert_has(TechCatalog.prerequisites("large_tobacco_plantations"), "seed_drill")
	assert_has(TechCatalog.dependents("university"), "advanced_hull_design")
	assert_eq(TechCatalog.prerequisites("crop_rotation"), [] as Array[String])


func test_extraction_caps_default_to_one() -> void:
	assert_eq(TechCatalog.extraction_caps({}), {})
	assert_eq(TechCatalog.cap_for("grain", {}), 1)
	assert_eq(TechCatalog.cap_for("timber", {"land_enclosure": true}), 1)
	assert_eq(TechCatalog.cap_for("horses", {"crop_rotation": true}), 1)


func test_gathering_techs_lift_the_cap_per_resource() -> void:
	var unlocked: Dictionary = {"land_enclosure": true}
	assert_eq(TechCatalog.cap_for("grain", unlocked), 2)
	unlocked["seed_drill"] = true
	assert_eq(TechCatalog.cap_for("grain", unlocked), 3)
	unlocked["moldboard_plow"] = true
	assert_eq(TechCatalog.cap_for("grain", unlocked), 4)
	assert_eq(TechCatalog.extraction_caps(unlocked), {"grain": 4})


func test_cap_chains_stop_at_the_wiki_exceptions() -> void:
	var wool: Dictionary = {"sheep_ranching": true, "scientific_sheep_breeding": true}
	assert_eq(TechCatalog.cap_for("wool", wool), TechCatalog.CAP_EXCEPTIONS["wool"])
	assert_eq(TechCatalog.CAP_EXCEPTIONS["horses"], 1)
	var iron: Dictionary = {
		"iron_mining": true, "steam_in_mining": true, "industrial_iron_mining": true,
	}
	assert_eq(TechCatalog.cap_for("iron", iron), 4)
	var copper: Dictionary = {
		"copper_and_tin_mining": true, "large_copper_and_tin_mines": true,
		"efficient_extraction_of_copper_and_tin": true,
	}
	assert_eq(TechCatalog.cap_for("copper", copper), 4)
	assert_eq(TechCatalog.cap_for("tin", copper), 4)


func test_discovery_techs_name_their_resources() -> void:
	assert_eq(TechCatalog.discovery_resources("discovery_of_sugar"), ["sugarCane"])
	assert_eq(
		TechCatalog.discovery_resources("discovery_of_gold_or_silver"),
		["gold", "silver"]
	)
	assert_eq(TechCatalog.discovery_resources("saw_mill"), [] as Array[String])
	assert_eq(TechCatalog.display_name("discovery_of_sugar"), "Discovery of Sugar")


func test_effect_text_uses_the_fixed_phrases() -> void:
	assert_true(TechCatalog.effect_text("saw_mill").contains("Improves:"))
	assert_true(TechCatalog.effect_text("saw_mill").to_lower().contains("timber"))
	assert_true(TechCatalog.effect_text("land_enclosure").contains("Unlocks:"))
	assert_true(TechCatalog.effect_text("discovery_of_sugar").contains("Enables:"))
	assert_true(TechCatalog.effect_text("clipper_ships").contains("Unlocks:"))
	assert_true(TechCatalog.effect_text("crop_rotation").contains("Unlocks:"))

# --- from test_civilian_catalog.gd ---
## Civilian roster and training costs (wiki: civilian-units § Civilian Types).


func test_catalog_covers_all_six_wiki_types() -> void:
	assert_eq(CivilianCatalog.TYPES.size(), 6)
	assert_eq(CivilianCatalog.ORDER.size(), 6)
	for type_id: String in CivilianCatalog.ORDER:
		assert_true(CivilianCatalog.known(type_id), type_id)
		assert_eq(CivilianCatalog.display_name(type_id), String(ROLE_NAMES[type_id]))


func test_training_costs_match_the_wiki() -> void:
	for type_id: String in ["explorer", "engineer", "builder"]:
		assert_eq(CivilianCatalog.treasury_cost(type_id), 1000, type_id)
		assert_eq(CivilianCatalog.paper_cost(type_id), 2, type_id)
	for type_id: String in ["spy", "merchant", "rail_builder"]:
		assert_eq(CivilianCatalog.treasury_cost(type_id), 2000, type_id)
		assert_eq(CivilianCatalog.paper_cost(type_id), 4, type_id)


func test_the_playable_roster_includes_the_spy_merchant_and_rail_builder() -> void:
	assert_eq(
		CivilianCatalog.playable_types(),
		["explorer", "engineer", "builder", "spy", "merchant", "rail_builder"]
	)
	assert_true(CivilianCatalog.is_implemented("spy"), "Spy")
	for type_id: String in CivilianCatalog.playable_types():
		assert_true(CivilianCatalog.is_implemented(type_id), type_id)
		assert_eq(CivilianCatalog.deferred_reason(type_id), "")


func test_tech_gated_types_unlock_on_research() -> void:
	assert_eq(CivilianCatalog.unlock_tech("explorer"), "")
	assert_eq(CivilianCatalog.unlock_tech("rail_builder"), "early_steam_engine")
	assert_eq(CivilianCatalog.unlock_tech("merchant"), "merchant_companies")
	assert_true(CivilianCatalog.is_unlocked("explorer"))
	assert_false(CivilianCatalog.is_unlocked("rail_builder"))
	assert_true(CivilianCatalog.is_unlocked("rail_builder", {"early_steam_engine": true}))


func test_work_lists_match_the_wiki_table() -> void:
	assert_eq(CivilianCatalog.works("explorer"), ["explore", "prospect"])
	assert_eq(CivilianCatalog.works("builder"), ["build_improvement", "upgrade_town"])
	assert_eq(CivilianCatalog.works("engineer"), ["build_road", "build_port", "build_fort"])
	assert_eq(CivilianCatalog.works("spy"), ["counter_spy"], "screen plus passive tradecraft")
	assert_eq(CivilianCatalog.works("merchant"), ["purchase_land"])
	assert_eq(CivilianCatalog.works("rail_builder"), ["build_rail"])


func test_affordability_needs_cash_and_paper() -> void:
	assert_true(CivilianCatalog.can_afford("explorer", 1000, 2))
	assert_false(CivilianCatalog.can_afford("explorer", 999, 2))
	assert_false(CivilianCatalog.can_afford("explorer", 1000, 1))
	assert_false(CivilianCatalog.can_afford("merchant", 1999, 4))


func test_training_cost_text_reads_as_a_purse_line() -> void:
	assert_eq(CivilianCatalog.training_cost_text("explorer"), "1,000 cash + 2 paper")
	assert_eq(CivilianCatalog.training_cost_text("merchant"), "2,000 cash + 4 paper")


func test_unknown_types_fall_back_to_a_known_row() -> void:
	assert_false(CivilianCatalog.known("privateer"))
	assert_true(CivilianCatalog.known(CivilianCatalog.normalize("privateer")))
	assert_eq(CivilianCatalog.normalize("privateer"), CivilianCatalog.DEFAULT_TYPE)

# --- from test_commodity_catalog.gd ---
## Commodity catalog (wiki: commodity-catalog).


func test_catalog_covers_the_wiki_lists() -> void:
	assert_eq(CommodityCatalog.FOOD, ["grain", "meat"] as Array[String])
	assert_eq(CommodityCatalog.RAW.size(), 11)
	assert_eq(CommodityCatalog.MANUFACTURED.size(), 9)
	assert_eq(CommodityCatalog.LUXURY.size(), 0)
	assert_eq(CommodityCatalog.RICHES, ["gold", "silver", "gems", "diamonds"] as Array[String])
	assert_eq(CommodityCatalog.ADVANCED, ["spices"] as Array[String])
	assert_eq(CommodityCatalog.all_ids().size(), 27)


func test_categories_match_the_table() -> void:
	assert_eq(CommodityCatalog.category_of("grain"), CommodityCatalog.Category.FOOD)
	assert_eq(CommodityCatalog.category_of("timber"), CommodityCatalog.Category.RAW)
	assert_eq(CommodityCatalog.category_of("castIron"), CommodityCatalog.Category.MANUFACTURED)
	assert_eq(CommodityCatalog.category_of("gold"), CommodityCatalog.Category.RICHES)
	assert_eq(CommodityCatalog.category_of("spices"), CommodityCatalog.Category.ADVANCED)
	assert_eq(CommodityCatalog.category_of("silk"), CommodityCatalog.NO_CATEGORY)
	assert_false(CommodityCatalog.known("silk"))
	assert_eq(CommodityCatalog.category_label(CommodityCatalog.Category.RAW), "Raw materials")


func test_tradeable_excludes_riches_and_spices() -> void:
	assert_true(CommodityCatalog.is_tradeable("timber"))
	assert_true(CommodityCatalog.is_tradeable("lumber"))
	assert_true(CommodityCatalog.is_tradeable("grain"))
	assert_false(CommodityCatalog.is_tradeable("gold"))
	assert_false(CommodityCatalog.is_tradeable("diamonds"))
	assert_false(CommodityCatalog.is_tradeable("spices"))
	assert_false(CommodityCatalog.is_tradeable("silk"))
	var tradeable: int = 0
	for id: String in CommodityCatalog.all_ids():
		if CommodityCatalog.is_tradeable(id):
			tradeable += 1
	assert_eq(tradeable, 22)


func test_manufactured_prices_are_break_even() -> void:
	for id: String in MANUFACTURED_ROWS.keys():
		assert_eq(CommodityCatalog.base_price(id), int(MANUFACTURED_ROWS[id]), id)


func test_raw_and_riches_prices_match_the_rules() -> void:
	assert_eq(CommodityCatalog.base_price("grain"), 50)
	assert_eq(CommodityCatalog.base_price("timber"), 30)
	assert_eq(CommodityCatalog.base_price("iron"), 80)
	assert_eq(CommodityCatalog.base_price("coal"), 90)
	assert_eq(CommodityCatalog.base_price("spices"), 50)
	assert_eq(CommodityCatalog.base_price("gold"), 166)
	assert_eq(CommodityCatalog.base_price("diamonds"), 500)
	assert_eq(CommodityCatalog.base_price("silk"), 0)


func test_labels_are_readable_and_stable() -> void:
	assert_eq(CommodityCatalog.label("grain"), "Grain")
	assert_eq(CommodityCatalog.label("castIron"), "Cast Iron")
	assert_eq(CommodityCatalog.label("sugarCane"), "Sugar Cane")
	assert_eq(CommodityCatalog.label("furHats"), "Fur Hats")


func test_ids_in_returns_a_copy_of_the_category() -> void:
	var food: Array[String] = CommodityCatalog.ids_in(CommodityCatalog.Category.FOOD)
	assert_eq(food, ["grain", "meat"] as Array[String])
	food.append("silk")
	assert_eq(CommodityCatalog.ids_in(CommodityCatalog.Category.FOOD).size(), 2)
	assert_eq(CommodityCatalog.ids_in(CommodityCatalog.Category.LUXURY).size(), 0)

# --- from test_ship_stats.gd ---
## Canonical ship catalog (wiki: ships-and-naval § Ship combat and cargo stats).


func test_ship_stats_cover_the_whole_roster() -> void:
	assert_eq(ShipStats.STATS.size(), ROSTER.size())
	for ship_id: String in ROSTER:
		assert_true(ShipStats.known(ship_id), ship_id)


func test_frozen_merchant_rows_match_the_wiki() -> void:
	var carrack: Dictionary = ShipStats.entry("carrack")
	assert_eq(int(carrack["frp"]), 2)
	assert_eq(int(carrack["rng"]), 1)
	assert_eq(int(carrack["arm"]), 1)
	assert_eq(int(carrack["hull"]), 2)
	assert_eq(int(carrack["mv"]), 2)
	assert_eq(int(carrack["cargo"]), 3)
	var fluyte: Dictionary = ShipStats.entry("fluyte")
	assert_eq(int(fluyte["hull"]), 1)
	assert_eq(int(fluyte["flee"]), 3)
	assert_eq(int(fluyte["cargo"]), 4)


func test_line_and_steam_rows_match_the_wiki() -> void:
	var line: Dictionary = ShipStats.entry("ship_of_the_line")
	assert_eq(int(line["frp"]), 6)
	assert_eq(int(line["hull"]), 8)
	assert_eq(int(line["intercept"]), 2)
	var ironclad: Dictionary = ShipStats.entry("ironclad")
	assert_eq(int(ironclad["arm"]), 8)
	assert_eq(int(ironclad["cargo"]), 0)
	var steamer: Dictionary = ShipStats.entry("merchant_steamship")
	assert_eq(int(steamer["cargo"]), 9)
	assert_eq(int(steamer["arm"]), 3)


func test_role_split_and_cargo_holds() -> void:
	assert_true(ShipStats.is_warship("sloop"))
	assert_true(ShipStats.is_warship("ship_of_the_line"))
	assert_false(ShipStats.is_warship("galleon"))
	for ship_id: String in ROSTER:
		var cargo: int = int(ShipStats.entry(ship_id)["cargo"])
		if ShipStats.is_warship(ship_id):
			assert_eq(cargo, 0, ship_id)
		else:
			assert_gt(cargo, 0, ship_id)


func test_strength_weights_firepower_range_armour_and_speed() -> void:
	# carrack: 2*1.0 + 1*0.4 + 1*0.15 + 2*0.1
	assert_almost_eq(ShipStats.strength("carrack"), 2.75, 0.0001)
	# ironclad: 5 + 1.2 + 1.2 + 0.3
	assert_almost_eq(ShipStats.strength("ironclad"), 7.7, 0.0001)
	# sloop: 2 + 0.8 + 0.15 + 0.3
	assert_almost_eq(ShipStats.strength("sloop"), 3.25, 0.0001)


func test_durability_is_hull_times_armour_bonus() -> void:
	# HULL * (1 + ARM/10)
	assert_almost_eq(ShipStats.durability("carrack"), 2.2, 0.0001)
	assert_almost_eq(ShipStats.durability("ironclad"), 10.8, 0.0001)
	assert_almost_eq(ShipStats.durability("fluyte"), 1.1, 0.0001)


func test_unknown_ship_stats_fall_back_to_the_carrack() -> void:
	assert_false(ShipStats.known("dromon"))
	assert_eq(ShipStats.normalize("dromon"), "carrack")
	assert_eq(ShipStats.entry("dromon"), ShipStats.entry("carrack"))
	assert_almost_eq(ShipStats.strength("dromon"), 2.75, 0.0001)


func test_display_names_are_period_readable() -> void:
	assert_eq(ShipStats.display_name("ship_of_the_line"), "Ship of the Line")
	assert_eq(ShipStats.display_name("merchant_steamship"), "Merchant Steamship")
	assert_eq(ShipStats.display_name("dromon"), "Carrack")

# --- from test_ship_economy.gd ---
## Ship build economy and food upkeep (wiki: ships-and-naval).


func test_ship_economy_covers_the_whole_roster() -> void:
	assert_eq(ShipEconomy.ENTRIES.size(), ROSTER.size())
	for ship_id: String in ROSTER:
		assert_true(ShipEconomy.known(ship_id), ship_id)
		assert_true(ShipStats.known(ship_id), ship_id)


func test_frozen_baseline_rows_match_the_wiki() -> void:
	assert_eq(ShipEconomy.treasury_cost("carrack"), 8000)
	assert_eq(ShipEconomy.build_inputs("carrack"), {"lumber": 2, "fabric": 1})
	assert_true(ShipEconomy.is_always_buildable("carrack"))
	assert_eq(ShipEconomy.unlock_era("carrack"), 0)
	assert_eq(ShipEconomy.treasury_cost("fluyte"), 6000)
	assert_eq(ShipEconomy.build_inputs("fluyte"), {"lumber": 1, "fabric": 1})
	assert_eq(ShipEconomy.unlock_era("fluyte"), 1)


func test_steam_and_line_rows_match_the_wiki() -> void:
	assert_eq(ShipEconomy.treasury_cost("ship_of_the_line"), 16500)
	assert_eq(ShipEconomy.build_inputs("ship_of_the_line"), {"lumber": 5, "fabric": 3})
	assert_eq(ShipEconomy.unlock_era("ship_of_the_line"), 3)
	assert_eq(ShipEconomy.treasury_cost("ironclad"), 21000)
	assert_eq(
		ShipEconomy.build_inputs("ironclad"), {"lumber": 2, "fabric": 2, "castIron": 5}
	)
	assert_eq(ShipEconomy.unlock_era("ironclad"), 4)
	assert_eq(ShipEconomy.treasury_cost("merchant_steamship"), 15500)
	assert_eq(
		ShipEconomy.build_inputs("merchant_steamship"),
		{"lumber": 2, "fabric": 2, "coal": 3}
	)
	assert_eq(ShipEconomy.treasury_cost("raider"), 11500)
	assert_eq(
		ShipEconomy.build_inputs("raider"), {"lumber": 2, "fabric": 1, "castIron": 2}
	)


func test_roles_align_with_ship_stats() -> void:
	for ship_id: String in ROSTER:
		var role: String = String(ShipEconomy.entry(ship_id)["role"])
		if ShipStats.is_warship(ship_id):
			assert_eq(role, "warship", ship_id)
		else:
			assert_eq(role, "merchant", ship_id)


func test_unknown_ship_economy_falls_back_to_the_carrack() -> void:
	assert_false(ShipEconomy.known("dromon"))
	assert_eq(ShipEconomy.entry("dromon"), ShipEconomy.entry("carrack"))
	assert_eq(ShipEconomy.treasury_cost("dromon"), 8000)


func test_food_upkeep_is_two_per_hull() -> void:
	assert_eq(ShipEconomy.FOOD_UPKEEP_PER_SHIP, 2)
	assert_eq(ShipEconomy.food_upkeep_per_ship("carrack"), 2)
	assert_eq(ShipEconomy.food_upkeep_per_ship("ironclad"), 2)
	var fleet: FleetState = FleetState.at_sea(
		1, 0, 3, ["ship_1", "ship_2", "ship_3"], {"ship_1": "sloop", "ship_2": "carrack"}
	)
	assert_eq(ShipEconomy.food_upkeep_for_fleet(fleet), 6)
	var minted: FleetState = FleetState.at_sea(2, 0, 3, [])
	# Factory still mints one default hull when none are given.
	assert_eq(ShipEconomy.food_upkeep_for_fleet(minted), 2)
	var sunk: FleetState = FleetState.at_sea(3, 0, 3, ["ship_9"])
	sunk.remove_hull("ship_9")
	assert_eq(ShipEconomy.food_upkeep_for_fleet(sunk), 0)
	assert_eq(ShipEconomy.food_upkeep_for_fleet(null), 0)


func test_food_upkeep_sums_owned_fleets_only() -> void:
	var fleets: Array[FleetState] = [
		FleetState.at_sea(1, 0, 1, ["ship_1", "ship_2"]),
		FleetState.at_sea(2, 1, 2, ["ship_3", "ship_4", "ship_5"]),
		FleetState.in_port(3, 0, 4, ["ship_6"]),
	]
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 0), 6)
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 1), 6)
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 2), 0)


func test_can_afford_checks_treasury_and_materials() -> void:
	var stock: Dictionary = {"lumber": 2, "fabric": 1}
	assert_true(ShipEconomy.can_afford("carrack", 8000, stock))
	assert_false(ShipEconomy.can_afford("carrack", 7999, stock))
	assert_false(ShipEconomy.can_afford("carrack", 8000, {"lumber": 1, "fabric": 1}))
	assert_true(ShipEconomy.can_afford("sloop", 5500, {"lumber": 1, "fabric": 1}))
	assert_false(
		ShipEconomy.can_afford("ironclad", 21000, {"lumber": 2, "fabric": 2, "castIron": 4})
	)
	assert_true(
		ShipEconomy.can_afford("ironclad", 21000, {"lumber": 2, "fabric": 2, "castIron": 5})
	)


func test_missing_inputs_lists_shortfalls() -> void:
	var short: Dictionary = ShipEconomy.missing_inputs(
		"raider", {"lumber": 1, "fabric": 1, "castIron": 0}
	)
	assert_eq(short, {"lumber": 1, "castIron": 2})
	assert_eq(ShipEconomy.missing_inputs("carrack", {"lumber": 2, "fabric": 1}), {})

# --- from test_production_recipes.gd ---
## Production recipes (wiki: production-recipes).


func test_catalog_has_the_published_recipes() -> void:
	assert_eq(ProductionRecipes.ids().size(), 10)
	assert_eq(ProductionRecipes.output("lumber"), "lumber")
	assert_eq(ProductionRecipes.inputs("lumber"), {"timber": 2})
	assert_eq(ProductionRecipes.labour("lumber"), 2)
	assert_eq(ProductionRecipes.inputs("bronze"), {"copper": 1, "tin": 1})
	assert_eq(ProductionRecipes.labour("bronze"), 3)
	assert_eq(ProductionRecipes.output("fabric_from_wool"), "fabric")
	assert_false(ProductionRecipes.known("silk_gown"))


func test_inputs_are_returned_as_a_copy() -> void:
	var inputs: Dictionary = ProductionRecipes.inputs("lumber")
	inputs["timber"] = 99
	assert_eq(ProductionRecipes.inputs("lumber"), {"timber": 2})


func test_cotton_fabric_needs_its_technology() -> void:
	assert_true(ProductionRecipes.available("fabric_from_wool", {}))
	assert_false(ProductionRecipes.available("fabric_from_cotton", {}))
	assert_true(ProductionRecipes.available("fabric_from_cotton", {"cotton_weaving": true}))
	assert_false(ProductionRecipes.available("fabric_from_cotton", {"cotton_weaving": false}))
	var gated: Array[String] = ProductionRecipes.available_ids({})
	assert_false(gated.has("fabric_from_cotton"))
	assert_true(gated.has("fabric_from_wool"))
	assert_true(ProductionRecipes.available("steel", {}))


func test_max_runs_is_limited_by_inputs_and_labour() -> void:
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 10}, 6), 3)
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 3}, 20), 1)
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 0}, 20), 0)
	assert_eq(ProductionRecipes.max_runs("bronze", {"copper": 5, "tin": 2}, 9), 2)
	assert_eq(ProductionRecipes.max_runs("bronze", {"copper": 5, "tin": 2}, 2), 0)
	assert_eq(ProductionRecipes.max_runs("unknown", {"timber": 10}, 10), 0)


func test_plan_runs_whole_recipes_and_scales_io() -> void:
	var stock: Dictionary = {"timber": 5}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "lumber", "units": 3}], stock, 6, {}
	)
	assert_eq(report["runs"], {"lumber": 2})
	assert_eq(report["consumed"], {"timber": 4})
	assert_eq(report["produced"], {"lumber": 2})
	assert_eq(report["labour_used"], 4)
	assert_eq(stock["timber"], 1)
	assert_eq(stock["lumber"], 2)


func test_plan_skips_recipes_it_cannot_run_once() -> void:
	var stock: Dictionary = {"timber": 1}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "lumber", "units": 4}], stock, 10, {}
	)
	assert_eq(report["runs"], {})
	assert_eq(report["produced"], {})
	assert_eq(stock["timber"], 1)
	assert_eq(report["labour_used"], 0)


func test_plan_respects_assignment_order_and_labour_budget() -> void:
	var stock: Dictionary = {"iron": 4, "coal": 2}
	var report: Dictionary = ProductionRecipes.plan(
		[
			{"recipe": "steel", "units": 2},
			{"recipe": "castIron", "units": 2},
		],
		stock,
		4,
		{}
	)
	assert_eq(report["runs"], {"steel": 2})
	assert_eq(stock["steel"], 2)
	assert_eq(stock["iron"], 2)
	assert_eq(stock["coal"], 0)
	assert_eq(report["labour_used"], 4)


func test_plan_ignores_unavailable_and_zero_unit_rows() -> void:
	var stock: Dictionary = {"cotton": 4, "timber": 4}
	var report: Dictionary = ProductionRecipes.plan(
		[
			{"recipe": "fabric_from_cotton", "units": 2},
			{"recipe": "lumber", "units": 0},
			{"recipe": "lumber", "units": -3},
		],
		stock,
		10,
		{}
	)
	assert_eq(report["runs"], {})
	assert_eq(stock["cotton"], 4)
	assert_eq(stock["timber"], 4)
	var allowed: Dictionary = ProductionRecipes.plan(
		[{"recipe": "fabric_from_cotton", "units": 2}], stock, 10, {"cotton_weaving": true}
	)
	assert_eq(allowed["runs"], {"fabric_from_cotton": 2})
	assert_eq(stock["cotton"], 0)
	assert_eq(stock["fabric"], 2)


func test_plan_cannot_drive_quantities_negative() -> void:
	var stock: Dictionary = {"iron": 1, "coal": 1, "timber": 0}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "steel", "units": 5}], stock, 3, {}
	)
	assert_eq(report["runs"], {"steel": 1})
	assert_eq(stock["iron"], 0)
	assert_eq(stock["coal"], 0)

# --- from test_music_playlist.gd ---
## Score catalogue: era beds follow the campaign calendar and every track exists
## on disk (REQ-P1-06, period-fitting music).


func test_every_track_points_at_a_shipped_file() -> void:
	var ids: Array[String] = MusicPlaylist.ids()
	assert_gte(ids.size(), 6)
	for track_id: String in ids:
		var path: String = MusicPlaylist.path_for(track_id)
		assert_true(path.begins_with(MusicPlaylist.ROOT), track_id)
		assert_true(FileAccess.file_exists(path), path)
	assert_true(FileAccess.file_exists(MusicPlaylist.AMBIENCE))


func test_unknown_track_has_no_path() -> void:
	assert_true(MusicPlaylist.track("sea_shanty_404").is_empty())
	assert_eq(MusicPlaylist.path_for("sea_shanty_404"), "")


func test_eras_open_on_the_consort_and_close_on_the_minuet() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(1500), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_id_for_year(1549), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_id_for_year(1550), MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_id_for_year(1699), MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_id_for_year(1700), MusicPlaylist.GILDED_MINUET)
	assert_eq(MusicPlaylist.bed_id_for_year(1800), MusicPlaylist.GILDED_MINUET)


func test_years_before_the_start_fall_back_to_the_first_bed() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(1400), MusicPlaylist.AGE_OF_DISCOVERY)


func test_beds_follow_the_turn_calendar() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(TurnTime.year_for_turn(1)),
		MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_for_turn(1)["id"], MusicPlaylist.AGE_OF_DISCOVERY)
	# 1500 + 2 years per turn: turn 30 is 1558, turn 101 is 1700.
	assert_eq(MusicPlaylist.bed_for_turn(30)["id"], MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_for_turn(101)["id"], MusicPlaylist.GILDED_MINUET)


func test_beds_carry_period_metadata() -> void:
	for bed: Dictionary in MusicPlaylist.ERA_BEDS:
		assert_true(bed.has("title"), "title")
		assert_true(bed.has("era"), "era")
		assert_gt(int(bed["from_year"]), 0)


func test_only_stingers_are_one_shots() -> void:
	assert_true(MusicPlaylist.loops(MusicPlaylist.SPANISH_MAIN))
	assert_true(MusicPlaylist.loops(MusicPlaylist.BROADSIDES))
	assert_false(MusicPlaylist.loops(MusicPlaylist.VICTORY))
	assert_false(MusicPlaylist.loops(MusicPlaylist.DEFEAT))

# --- from test_regiment_economy.gd ---
## Regiment training economy (wiki: military-units § Training Costs,
## military-generals § Regiment Economy, tech-tree-military § Unlocks).


func test_every_regiment_has_a_training_row() -> void:
	for type_id: String in RegimentCatalog.ids():
		assert_true(RegimentEconomy.TECH.has(type_id), "%s has a tech row" % type_id)
		var tech: String = RegimentEconomy.tech_for(type_id)
		if not tech.is_empty():
			assert_true(TechCatalog.known(tech), "%s maps to a real tech" % type_id)


func test_cavalry_inputs_match_the_published_table() -> void:
	var squires: Dictionary = RegimentEconomy.training_inputs("squires")
	assert_eq(int(squires["fabric"]), 1)
	assert_eq(int(squires["castIron"]), 1)
	assert_eq(int(squires["horses"]), 2)
	var knights: Dictionary = RegimentEconomy.training_inputs("knights")
	assert_eq(int(knights["castIron"]), 2)
	assert_eq(int(knights["horses"]), 2)
	var lancers: Dictionary = RegimentEconomy.training_inputs("lancers")
	assert_false(lancers.has("horses"), "lancers need no horses")


func test_start_regiments_are_buildable_and_later_ones_are_tech_gated() -> void:
	assert_true(RegimentEconomy.buildable("peasant_levies", {}))
	assert_true(RegimentEconomy.buildable("culverin", {}))
	assert_false(RegimentEconomy.buildable("lancers", {}))
	assert_true(RegimentEconomy.buildable("lancers", {"organised_regiments": true}))
	assert_false(RegimentEconomy.buildable("guards", {"needle_guns": true}))
	assert_true(RegimentEconomy.buildable("guards", {"elite_military_training": true}))


func test_blocked_reasons_follow_the_ledger() -> void:
	var stock: Dictionary = {"fabric": 5, "castIron": 5, "bronze": 5}
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 0, stock, 5, {}),
		"Insufficient treasury"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 99999, {}, 5, {}),
		"Insufficient materials"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 99999, stock, 0, {}),
		"Insufficient workers"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("lancers", 99999, stock, 5, {}),
		"Requires Organised Regiments"
	)
	assert_eq(RegimentEconomy.blocked_reason("pikemen", 99999, stock, 5, {}), "")


func test_cost_text_lists_cash_materials_and_the_worker() -> void:
	var text: String = RegimentEconomy.cost_text("peasant_levies")
	assert_true(text.contains("2,000 ducats"), text)
	assert_true(text.contains("Fabric"), text)
	assert_true(text.contains("1 worker"), text)


func test_recruit_deducts_the_ledger_and_joins_the_home_army() -> void:
	var economy := PlayerEconomy.starting()
	var home := ArmyState.muster(1, 0, 4, true, [] as Array[String], 1)
	var treasury: int = economy.treasury
	var fabric: int = economy.quantity("fabric")
	var peasants: int = economy.available_peasants()

	var result: Dictionary = ArmyTraining.recruit(economy, home, "peasant_levies", "unit_9")

	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(home.count(), 1)
	assert_eq(home.type_of("unit_9"), "peasant_levies")
	assert_eq(economy.treasury, treasury - RegimentCatalog.treasury_cost("peasant_levies"))
	assert_eq(economy.quantity("fabric"), fabric - 1)
	assert_eq(economy.available_peasants(), peasants - 1)


func test_recruit_refuses_a_field_army() -> void:
	var economy := PlayerEconomy.starting()
	var field := ArmyState.muster(2, 0, 4, false, [] as Array[String], 1)
	var result: Dictionary = ArmyTraining.recruit(economy, field, "peasant_levies", "unit_9")
	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Regiments muster only in the Home Army.")
	assert_eq(field.count(), 0)


func test_rows_lead_with_what_the_crown_can_muster_today() -> void:
	var economy := PlayerEconomy.starting()
	var rows: Array[Dictionary] = ArmyTraining.rows(economy)
	assert_eq(rows.size(), RegimentCatalog.ROWS.size())
	assert_true(bool(rows[0]["ok"]), "first row is buildable")
	var seen_locked: bool = false
	for row: Dictionary in rows:
		if not bool(row["ok"]):
			seen_locked = true
		elif seen_locked:
			assert_true(false, "buildable rows must come before locked rows")
