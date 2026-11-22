extends GdToolsTest
## Shared counsel-pick chrome: one sentence, one prose join, one capped line, one
## court line, one gate and one row order.


func test_sentence_opens_and_closes() -> void:
	assert_eq(MapPlayPickProse.sentence(""), "", "no clause, no sentence")
	assert_eq(
		MapPlayPickProse.sentence("the court would raise the farm"),
		"The court would raise the farm.",
		"one capital and a full stop"
	)


func test_a_pick_prints_as_one_sentence() -> void:
	assert_eq(MapPlayPickProse.sentence_of({}), "", "no pick, no sentence")
	assert_eq(
		MapPlayPickProse.sentence_of({"line": "the court would raise the farm"}),
		"The court would raise the farm.",
		"the pick's own clause is the sentence"
	)


func test_join_reads_as_prose() -> void:
	assert_eq(MapPlayPickProse.join([]), "", "empty list")
	assert_eq(MapPlayPickProse.join(["A"]), "A", "one part")
	assert_eq(MapPlayPickProse.join(["A", "B"]), "A and B", "two parts")
	assert_eq(
		MapPlayPickProse.join(["A", "B", "C"]),
		"A, B and C",
		"three parts take a comma and a final and"
	)


func test_capped_counts_the_rest() -> void:
	assert_eq(MapPlayPickProse.capped([], 3), "", "nothing named")
	assert_eq(
		MapPlayPickProse.capped(["A", "B", "C"], 3),
		"A, B and C",
		"under the limit keeps prose join"
	)
	assert_eq(
		MapPlayPickProse.capped(["A", "B", "C", "D", "E"], 3),
		"A, B, C and 2 more",
		"over the limit commas the heads and counts the rest"
	)
	assert_eq(
		MapPlayPickProse.capped(["A", "B"], 3, 2),
		"A, B and 2 more",
		"a repeated clause still counts the crews behind it"
	)
	assert_eq(
		MapPlayPickProse.capped(["A"], 3, 1),
		"A and 1 more",
		"one clause standing for two crews says so"
	)
	assert_eq(MapPlayPickProse.capped(["A"], 0), "", "no room, no line")


func test_a_repeated_clause_collapses_and_still_counts_its_crews() -> void:
	var unique: Dictionary = MapPlayPickProse.unique_clauses(["A", "A", "", "B", "A"])
	var kept: Array[String] = []
	kept.assign(unique.get("clauses", []))
	assert_eq(kept.size(), 2, "each order is named once")
	assert_eq(kept[0], "A", "the first wording holds its place")
	assert_eq(kept[1], "B", "the rest keeps its order")
	assert_eq(int(unique.get("extra", 0)), 2, "both repeats are counted")
	var none: Dictionary = MapPlayPickProse.unique_clauses([])
	assert_eq(int(none.get("extra", 0)), 0, "nothing to count")
	assert_eq((none.get("clauses", []) as Array).size(), 0, "nothing to name")


func test_the_court_line_caps_and_drops_blanks() -> void:
	assert_eq(
		MapPlayPickProse.court_line("the court would send", []),
		"",
		"nothing named, no line"
	)
	assert_eq(
		MapPlayPickProse.court_line("the court would send", ["", ""]),
		"",
		"blank clauses name nothing"
	)
	assert_eq(
		MapPlayPickProse.court_line("the court would send", ["the Leopard", "", "the Tern"]),
		"the court would send the Leopard and the Tern this turn",
		"blanks drop out and a pair reads as prose"
	)
	assert_eq(
		MapPlayPickProse.court_line(
			"the court would put", ["A", "B", "C", "D"], "this phase"
		),
		"the court would put A, B, C and 1 more this phase",
		"a busy line caps and counts the rest"
	)
	assert_eq(
		MapPlayPickProse.court_line("the court would", ["walk its Spy"], ""),
		"the court would walk its Spy",
		"an empty tail closes on the clause alone"
	)


func test_a_sheet_can_name_more_than_the_common_cap() -> void:
	assert_eq(
		MapPlayPickProse.court_line_capped(
			"the court would run", ["A", "B", "C", "D"], "this phase", 4
		),
		"the court would run A, B, C and D this phase",
		"a wide sheet's own cap names the fourth row"
	)
	assert_eq(
		MapPlayPickProse.court_line_capped(
			"the court would run", ["A", "B", "C", "D", "E"], "this phase", 4
		),
		"the court would run A, B, C, D and 1 more this phase",
		"past its own cap it still counts the rest"
	)
	assert_eq(
		MapPlayPickProse.court_line_capped("the court would run", [], "this phase", 4),
		"",
		"nothing named, no line"
	)


## The sheets read their chrome from one place (REQ-P3-01): a sheet that names
## nothing hands the shared line an empty list and prints no headless sentence
## instead of the sheet keeping its own copy of the rule (REQ-P3-02).
func test_a_sheet_that_names_nothing_prints_no_line() -> void:
	assert_eq(MapPlayMarketPick.list_line({}, "offer"), "", "market: no rows")
	assert_eq(MapPlayProductionPick.run_line({}), "", "production: no runs")
	assert_eq(MapPlayRecruitPick.recruit_line({}), "", "recruit: no tiers")


func test_a_silent_pass_earns_a_gate_only_when_something_waited() -> void:
	assert_true(MapPlayPickProse.gate(0, "crews", "none").is_empty(), "nobody waiting")
	var gate: Dictionary = MapPlayPickProse.gate(2, "squadrons", "no sail")
	assert_eq(String(gate["line"]), "no sail", "the gate names the silence")
	assert_eq((gate["squadrons"] as Array).size(), 0, "a gate carries no rows")
	assert_false(gate.has("crews"), "the rows key is the sheet's own")


func test_a_row_key_reads_the_chart_and_the_id() -> void:
	assert_eq(
		MapPlayPickProse.row_key({"region": 2, "army": 7}, "army"),
		"2:7",
		"chart and id"
	)
	assert_eq(
		MapPlayPickProse.row_key({"army": 7}, "army"),
		"-1:7",
		"a row with no chart still keys"
	)
	assert_eq(
		MapPlayPickProse.row_key({"region": 0, "fleet": 3}, "fleet_id", "fleet"),
		"0:3",
		"a heading's own name fills in for the pick's"
	)
	assert_eq(
		MapPlayPickProse.row_key({"region": 0, "fleet_id": 4, "fleet": 3}, "fleet_id", "fleet"),
		"0:4",
		"the pick's own name wins when both are there"
	)


func test_rows_keep_the_order_the_sheet_prints() -> void:
	var rows: Array[Dictionary] = [
		{"region": 0, "army": 2}, {"region": 0, "army": 1}, {"region": 0, "army": 3},
	]
	var printed: Array = [
		{"region": 0, "army": 1}, {"region": 0, "army": 2}, {"region": 0, "army": 3},
	]
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(rows, printed, "army")
	assert_eq(int(ordered[0]["army"]), 1, "the sheet's first row leads")
	assert_eq(int(ordered[1]["army"]), 2, "the sheet's second row follows")
	assert_eq(int(ordered[2]["army"]), 3, "the sheet's third row closes")


func test_rows_the_sheet_does_not_print_keep_the_passs_order() -> void:
	var rows: Array[Dictionary] = [
		{"region": 0, "unit_id": 9},
		{"region": 0, "unit_id": 2},
		{"region": 0, "unit_id": 4},
	]
	var printed: Array = [{"region": 0, "unit_id": 2}]
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(rows, printed, "unit_id")
	assert_eq(int(ordered[0]["unit_id"]), 2, "the printed row leads")
	assert_eq(int(ordered[1]["unit_id"]), 4, "unprinted rows close behind, id first")
	assert_eq(int(ordered[2]["unit_id"]), 9, "unprinted rows close behind, id first")


func test_an_empty_snapshot_keeps_the_passs_order() -> void:
	var rows: Array[Dictionary] = [{"region": 0, "army": 2}, {"region": 0, "army": 1}]
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(rows, [], "army")
	assert_true(ordered == rows, "no printed rows, the pass's own order stands")
	assert_eq(int(ordered[0]["army"]), 2, "the pass's first row leads")


func test_a_duplicated_heading_reads_once_and_ids_break_ties() -> void:
	var rows: Array[Dictionary] = [
		{"region": 0, "army": 5}, {"region": 0, "army": 4}, {"region": 0, "army": 3},
	]
	# Both groups name army 3, so the second copy adds no place on the page.
	var printed: Array = [
		{"region": 0, "army": 3}, {"region": 0, "army": 3},
	]
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(rows, printed, "army")
	assert_eq(int(ordered[0]["army"]), 3, "the printed row leads")
	assert_eq(int(ordered[1]["army"]), 4, "the id breaks the tie")
	assert_eq(int(ordered[2]["army"]), 5, "the id breaks the tie")


func test_the_heading_name_reads_a_squadron_group() -> void:
	var squadrons: Array[Dictionary] = [
		{"region": 0, "fleet_id": 2}, {"region": 0, "fleet_id": 1},
	]
	var groups: Array = [{"region": 0, "fleet": 1}, {"region": 0, "fleet": 2}]
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(
		squadrons, groups, "fleet_id", "fleet"
	)
	assert_eq(int(ordered[0]["fleet_id"]), 1, "a heading's fleet name orders the pick")
	assert_eq(int(ordered[1]["fleet_id"]), 2, "a heading's fleet name orders the pick")


func test_crown_crew_ready_refuses_a_missing_session() -> void:
	assert_false(
		MapPlayPickProse.crown_crew_ready(null),
		"no session, no counsel pick"
	)


func test_crown_ready_refuses_a_missing_session() -> void:
	assert_false(MapPlayPickProse.crown_ready(null), "no session, no counsel pick")


func test_the_crew_gate_stands_on_the_crown_gate() -> void:
	var slim: PlaySession = PlaySession.new()
	slim.ai_mode = AiControl.NOOP
	assert_false(
		MapPlayPickProse.crown_crew_ready(slim),
		"a court with no planner earns no crew counsel either"
	)
	assert_false(
		MapPlayPickProse.crown_ready(slim),
		"a court with no planner reads no counsel at all"
	)
