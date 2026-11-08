extends GdToolsTest
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
