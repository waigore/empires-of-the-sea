extends GdToolsTest
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
