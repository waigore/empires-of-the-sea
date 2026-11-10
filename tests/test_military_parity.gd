extends GdToolsTest
## Minor Nation regiment parity (wiki: factions § Minor military parity).
## The phase upgrades Minor land regiments in place to the strongest Great
## Power's buildable era, never downgrades, and leaves Tribes at level 1.


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
