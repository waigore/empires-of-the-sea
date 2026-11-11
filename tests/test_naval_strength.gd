extends GdToolsTest
## The naval combat maths as the court reads it: the squadron's stat totals, the
## weighted strength the resolver fights with, the hull pool, and the share of a
## sea zone each side holds (wiki: ships-and-naval § Naval Strength Aggregation
## Formula, § Naval Combat Resolution). Pure rules: no scene, no nodes.

## A squadron of two carracks and a frigate: the worked example the dossier
## prints, kept small enough to check by hand.
func _squadron() -> FleetState:
	return FleetState.at_sea(
		4, 0, 1, ["ship_1", "ship_2", "ship_3"],
		{"ship_1": "carrack", "ship_2": "carrack", "ship_3": "frigate"}
	)


func test_the_squadron_totals_every_hull() -> void:
	var row: Dictionary = NavalStrength.squadron(_squadron())
	var totals: Dictionary = row["totals"]

	assert_eq(int(row["count"]), 3)
	assert_eq(int(totals["frp"]), 2 + 2 + 4)
	assert_eq(int(totals["rng"]), 1 + 1 + 3)
	assert_eq(int(totals["arm"]), 1 + 1 + 2)
	assert_eq(int(totals["hull"]), 2 + 2 + 4)
	assert_eq(int(totals["mv"]), 2 + 2 + 3)


func test_rows_aggregate_distinct_hulls_of_one_type() -> void:
	var rows: Array = NavalStrength.squadron(_squadron())["types"]

	assert_eq(rows.size(), 2, "two types, three hulls")
	assert_eq(String(rows[0]["type_id"]), "carrack")
	assert_eq(int(rows[0]["count"]), 2)
	assert_eq(String(rows[1]["type_id"]), "frigate")
	assert_eq(int(rows[1]["count"]), 1)
	assert_false(bool(rows[0]["warship"]))
	assert_true(bool(rows[1]["warship"]))


func test_strength_and_pool_match_the_resolver() -> void:
	var fleet: FleetState = _squadron()
	var row: Dictionary = NavalStrength.squadron(fleet)

	assert_almost_eq(float(row["strength"]), 2.75 + 2.75 + 5.8, 0.0001)
	assert_almost_eq(float(row["strength"]), NavalCombat.side_strength([fleet]), 0.0001)
	assert_almost_eq(
		float(row["durability"]), NavalCombat.side_durability([fleet]), 0.0001
	)
	assert_almost_eq(NavalStrength.strength(null), 0.0, 0.0001)
	assert_almost_eq(NavalStrength.durability(null), 0.0, 0.0001)


func test_an_empty_squadron_reads_as_nothing() -> void:
	var row: Dictionary = NavalStrength.squadron(FleetState.empty_in_port(9, 0, 1))

	assert_eq(int(row["count"]), 0)
	assert_almost_eq(float(row["strength"]), 0.0, 0.0001)
	assert_eq((row["types"] as Array).size(), 0)
	assert_eq(int((row["totals"] as Dictionary)["frp"]), 0)


func test_the_formula_names_every_weight() -> void:
	var row: Dictionary = NavalStrength.squadron(_squadron())
	var formula: String = String(row["formula"])

	assert_true(formula.contains("FRP 8"), formula)
	assert_true(formula.contains("RNG 5×0.4"), formula)
	assert_true(formula.contains("ARM 4×0.15"), formula)
	assert_true(formula.contains("MV 7×0.1"), formula)
	# 2.2 + 2.2 + 4.8: the pool is summed per hull, never 8 × (1 + 4/10).
	assert_almost_eq(float(row["durability"]), 9.2, 0.0001)
	assert_true(String(row["pool"]).contains("9.2"), String(row["pool"]))


func test_a_hull_line_names_its_own_numbers() -> void:
	assert_eq(
		NavalStrength.hull_line("frigate"),
		"FRP 4 · RNG 3 · ARM 2 · HULL 4 · MV 3 · 5.8 strength"
	)


# --- the odds of a contested zone --------------------------------------------


func test_an_edge_wins_and_an_even_split_is_a_draw() -> void:
	var win: Dictionary = NavalStrength.odds(60.0, 40.0)
	assert_eq(NavalStrength.outcome_of(win), NavalStrength.OUTCOME_WIN)
	assert_eq(NavalStrength.share_text(win), "60%")

	var loss: Dictionary = NavalStrength.odds(40.0, 60.0)
	assert_eq(NavalStrength.outcome_of(loss), NavalStrength.OUTCOME_LOSS)

	# The resolver calls anything inside ±3% of an even split a stalemate, so the
	# boundary itself is a draw (wiki: § Naval Combat Resolution).
	assert_eq(
		NavalStrength.outcome_of(NavalStrength.odds(53.0, 47.0)),
		NavalStrength.OUTCOME_DRAW
	)
	assert_eq(
		NavalStrength.outcome_of(NavalStrength.odds(53.1, 46.9)),
		NavalStrength.OUTCOME_WIN
	)
	assert_almost_eq(NavalStrength.need(), 0.53, 0.0001)


func test_no_strength_anywhere_is_a_draw() -> void:
	var even: Dictionary = NavalStrength.odds(0.0, 0.0)

	assert_eq(NavalStrength.outcome_of(even), NavalStrength.OUTCOME_DRAW)
	assert_almost_eq(float(even["share"]), 0.5, 0.0001)


func test_the_zone_sums_friend_and_hostile_sides() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var second: FleetState = FleetState.at_sea(2, 0, 0, ["ship_2"], {"ship_2": "carrack"})
	var theirs: FleetState = FleetState.at_sea(3, 1, 0, ["ship_3"], {"ship_3": "frigate"})
	var far: FleetState = FleetState.at_sea(4, 1, 1, ["ship_4"], {"ship_4": "frigate"})
	var moored: FleetState = FleetState.in_port(5, 1, 1, ["ship_5"], {"ship_5": "frigate"})

	var row: Dictionary = NavalStrength.zone([mine, second, theirs, far, moored], mine)

	assert_almost_eq(float(row["own"]), 5.5, 0.0001, "two of ours fight as one side")
	assert_almost_eq(float(row["foe"]), 5.8, 0.0001, "the other zone and the port stay out")
	assert_eq(int(row["own_hulls"]), 2)
	assert_eq(int(row["foe_hulls"]), 1)
	assert_true((row["foes"] as Array).has(1))
	assert_eq(NavalStrength.outcome_of(row), NavalStrength.OUTCOME_DRAW)


func test_a_peaceful_flag_is_no_threat() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var theirs: FleetState = FleetState.at_sea(3, 1, 0, ["ship_3"], {"ship_3": "frigate"})
	var peace := func(_a: int, _b: int) -> bool: return false

	var row: Dictionary = NavalStrength.zone([mine, theirs], mine, peace)

	assert_almost_eq(float(row["foe"]), 0.0, 0.0001)
	assert_eq((row["foes"] as Array).size(), 0)


func test_a_moored_squadron_gets_no_odds() -> void:
	var moored: FleetState = FleetState.in_port(5, 0, 1, ["ship_5"], {"ship_5": "frigate"})

	assert_eq(NavalStrength.zone([moored], moored).size(), 0)
	assert_eq(NavalStrength.zone([], null).size(), 0)


func test_the_zone_falls_back_to_the_squadron_it_was_asked_about() -> void:
	var lone: FleetState = FleetState.at_sea(7, 0, 1, ["ship_7"], {"ship_7": "sloop"})

	var row: Dictionary = NavalStrength.zone([], lone)

	assert_almost_eq(float(row["own"]), 3.25, 0.0001)
	assert_eq(int(row["own_hulls"]), 1)
