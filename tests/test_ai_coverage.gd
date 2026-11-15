extends GdToolsTest
## Shipped-rule → order-row coverage checklist (issue #605): every rule the
## full-AI observer's per-turn records prove a court exercised, every rule they
## prove it never did, and the ledger's word on a rule whose aim was ranked but
## never funded. Pure: synthetic records, no map (REQ-P3-03).


func _records() -> Array[Dictionary]:
	# Two resolved turns, two crowns: Portugal declares war and musters, Spain
	# spends the second turn pitching a train.
	return [
		{
			"turn": 2,
			"rows": [
				{
					"faction": 0,
					"last":
					{
						"actions": {"war": 1, "reinforce": 2},
						"objectives": {"rows": []},
					},
				},
			],
		},
		{
			"turn": 3,
			"rows": [
				{
					"faction": 0,
					"last": {"actions": {"war": 2}, "objectives": {"rows": []}},
				},
				{
					"faction": 1,
					"last":
					{
						"actions": {"hospital": 1},
						"objectives":
						{
							"rows":
							[
								{"id": "navy.build", "status": AiObjective.STATUS_DEFERRED},
							],
						},
					},
				},
			],
		},
	]


func _row(rows: Array[Dictionary], id: String) -> Dictionary:
	for row: Dictionary in rows:
		if String(row["id"]) == id:
			return row
	return {}


func test_every_shipped_rule_gets_a_row_even_on_an_empty_run() -> void:
	var rows: Array[Dictionary] = AiCoverage.scan([])
	assert_eq(rows.size(), AiCoverage.RULES.size(), "one row per catalogued rule")
	for row: Dictionary in rows:
		assert_eq(int(row["count"]), 0, "an empty run exercises nothing")
		assert_eq(int(row["first"]), -1, "no window on an empty run")


func test_a_row_counts_every_order_across_the_whole_run() -> void:
	var rows: Array[Dictionary] = AiCoverage.scan(_records())
	var war: Dictionary = _row(rows, "war.declare")
	assert_eq(int(war["count"]), 3, "every declaration in every turn is counted")
	assert_eq(int(war["first"]), 2, "the first turn it fired")
	assert_eq(int(war["last"]), 3, "the last turn it fired")
	assert_eq((war["courts"] as Array).size(), 1, "one crown issued them all")


func test_a_rule_with_no_order_row_reads_never_exercised() -> void:
	var rows: Array[Dictionary] = AiCoverage.scan(_records())
	assert_eq(int(_row(rows, "navy.launch")["count"]), 0, "no hull was laid")
	assert_true(
		AiCoverage.missing_major(rows).has("navy.launch"),
		"a major row at zero fails the checklist",
	)
	assert_true(
		not AiCoverage.missing_major(rows).has("army.hospital"),
		"a policy-gated row never fails the checklist",
	)
	assert_true(
		AiCoverage.report(rows).contains("never-exercised major"),
		"the report names the count",
	)


func test_an_aim_ranked_but_never_funded_reads_starved() -> void:
	var fixed: Array[Dictionary] = _records()
	var court: Dictionary = fixed[1]["rows"][1]
	var aim: Dictionary = (court["last"]["objectives"]["rows"] as Array)[0]
	aim["status"] = AiObjective.STATUS_FUNDED
	var funded: Array[Dictionary] = AiCoverage.scan(fixed)
	var build: Dictionary = _row(funded, "navy.launch")
	assert_eq(int(build["aims_ranked"]), 1, "the aim was ranked once")
	assert_eq(int(build["aims_funded"]), 1, "the ledger funded it once")
	assert_true(
		not AiCoverage.starved(funded).has("navy.launch"),
		"a funded aim is not starved",
	)
	aim["status"] = AiObjective.STATUS_BLOCKED
	var blocked: Array[Dictionary] = AiCoverage.scan(fixed)
	assert_eq(int(_row(blocked, "navy.launch")["aims_funded"]), 0, "blocked funds nothing")
	assert_true(
		AiCoverage.starved(blocked).has("navy.launch"),
		"a ranked aim nobody funds is the under-use the run proves",
	)


func test_a_second_run_merges_into_one_checklist() -> void:
	var rows: Array[Dictionary] = AiCoverage.scan(_records())
	var before: int = int(_row(rows, "war.declare")["count"])
	AiCoverage.merge(rows, AiCoverage.scan(_records()))
	assert_eq(int(_row(rows, "war.declare")["count"]), before * 2, "counts add")
	assert_eq((_row(rows, "war.declare")["courts"] as Array).size(), 1, "crowns are a set")
	assert_eq(int(_row(rows, "war.declare")["runs"]), 4, "runs add, 2 per scan")


func test_merge_takes_the_earliest_window_and_ignores_a_nameless_court() -> void:
	# A run whose only declaration is on t1, written by a record with no crown
	# id: the merged window starts before the first scan's and no phantom crown
	# joins the set.
	var rows: Array[Dictionary] = AiCoverage.scan(_records())
	var early: Array[Dictionary] = AiCoverage.scan(
		[{"turn": 1, "rows": [{"last": {"actions": {"war": 1}, "objectives": {"rows": []}}}]}]
	)
	AiCoverage.merge(rows, early)
	var war: Dictionary = _row(rows, "war.declare")
	assert_eq(int(war["count"]), 4, "the earlier run is counted")
	assert_eq(int(war["first"]), 1, "the window starts at the earliest turn")
	assert_eq(int(war["last"]), 3, "and ends at the latest")
	assert_eq((war["courts"] as Array).size(), 1, "a nameless record names no crown")


func test_merge_into_an_empty_checklist_adopts_the_run() -> void:
	# A second crown declaring war joins the set, and a checklist that has run
	# nothing yet takes the window whole.
	var rows: Array[Dictionary] = AiCoverage.scan([])
	AiCoverage.merge(rows, AiCoverage.scan(_records()))
	var war: Dictionary = _row(rows, "war.declare")
	assert_eq(int(war["first"]), 2, "an empty checklist adopts the first turn")
	var second: Array[Dictionary] = AiCoverage.scan(
		[{"turn": 4, "rows": [{"faction": 2, "last": {"actions": {"war": 1}, "objectives": {"rows": []}}}]}]
	)
	AiCoverage.merge(rows, second)
	assert_eq((_row(rows, "war.declare")["courts"] as Array).size(), 2, "a new crown joins")
	assert_eq(int(_row(rows, "war.declare")["last"]), 4, "the window widens")


func test_a_checklist_with_no_rows_reports_a_clean_zero() -> void:
	# `report` on no rows still prints its one summary line, so a caller that
	# scanned nothing reads "0 of 0" rather than a blank table.
	var text: String = AiCoverage.report([])
	assert_true(text.contains("Exercised 0 of 0"), "the summary still prints")
	assert_true(not text.contains("never-exercised major 1"), "and names no defect")
