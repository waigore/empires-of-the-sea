extends GdToolsTest
## The AI observatory's read-only halves read out of the panel: [ObserverTurnFeed]
## words the order feed and its caption, [ObserverCrownCard] paints one court's
## standing, so the panel only drives the calendar (REQ-P3-01, REQ-P3-03).


## One turn's record, carrying `rows` orders.
func _turn(number: int, rows: int) -> Dictionary:
	var events: Array = []
	for index in rows:
		events.append({"text": "T%d order %d." % [number, index]})
	return {"turn": number, "events": events}


## The feed prints every row of the turns it keeps, newest row first, and counts
## what it holds (REQ-P5-05).
func test_the_feed_prints_every_row_of_the_turns_it_keeps() -> void:
	assert_eq(ObserverTurnFeed.text([]), ObserverTurnFeed.EMPTY_TEXT)
	assert_eq(ObserverTurnFeed.caption([]), "Recent orders", "an empty feed counts none")
	assert_eq(
		ObserverTurnFeed.caption([{"turn": 1, "events": [{"text": "Marched."}]}]),
		"Recent orders  ·  T1  ·  1 row over 1 turn, newest first",
		"one turn's one row prints as written"
	)
	assert_eq(
		ObserverTurnFeed.text([{"turn": 7, "events": []}]),
		ObserverTurnFeed.EMPTY_TEXT,
		"a turn that filed nothing prints no line"
	)


## The window is a row budget, not a turn count: a crowded campaign keeps the
## newest turns whole up to the budget and never cuts a busy turn's first row
## (REQ-P5-05, REQ-P4-01).
func test_the_window_stops_at_its_row_budget() -> void:
	var ai_turns: Array = []
	for turn in range(1, 21):
		ai_turns.append(_turn(turn, 10))
	var text: String = ObserverTurnFeed.text(ai_turns)
	var lines: PackedStringArray = text.split("\n")
	var turns_kept: int = ObserverTurnFeed.ROW_BUDGET / 10
	assert_eq(lines.size(), ObserverTurnFeed.ROW_BUDGET, "the budget is the row count held")
	assert_eq(
		ObserverTurnFeed.first_kept(ai_turns), 20 - turns_kept,
		"the window reaches back exactly the turns the budget buys"
	)
	assert_eq(
		String(lines[0]), "T20  T20 order 9.", "the newest order leads the feed"
	)
	assert_eq(
		String(lines[lines.size() - 1]), "T%d  T%d order 0." % [
			21 - turns_kept, 21 - turns_kept,
		],
		"the oldest kept turn keeps its first order, not a cut one"
	)
	assert_false(text.contains("T%d  " % (20 - turns_kept)), "the turn before the window drops")
	assert_eq(
		ObserverTurnFeed.caption(ai_turns),
		"Recent orders  ·  T%d–T20  ·  %d rows over %d turns, newest first" % [
			21 - turns_kept, ObserverTurnFeed.ROW_BUDGET, turns_kept,
		],
		"the caption names the turns the window reaches back to"
	)


## A quiet campaign buys more history than a crowded one: the same budget holds
## every turn of a lean run, so a late watcher reads the whole story (REQ-P5-05).
func test_a_quiet_run_keeps_more_turns_than_a_busy_one() -> void:
	var quiet: Array = []
	for turn in range(1, 41):
		quiet.append(_turn(turn, 2))
	assert_eq(ObserverTurnFeed.first_kept(quiet), 0, "every lean turn fits the budget")
	assert_eq(
		ObserverTurnFeed.caption(quiet),
		"Recent orders  ·  T1–T40  ·  80 rows over 40 turns, newest first"
	)


## The floor: however busy the newest turns are, the feed keeps a pair of them,
## so the order that caused the latest one is never the row that drops
## (REQ-P5-05).
func test_a_turn_busier_than_the_budget_still_prints_whole() -> void:
	var busy: Array = [_turn(1, ObserverTurnFeed.ROW_BUDGET * 2), _turn(2, 3)]
	assert_eq(ObserverTurnFeed.first_kept(busy), 0, "the floor keeps both turns")
	var lines: PackedStringArray = ObserverTurnFeed.text(busy).split("\n")
	assert_eq(
		lines.size(), ObserverTurnFeed.ROW_BUDGET * 2 + 3,
		"every row of both turns reaches the feed"
	)


## One crown's card reads rank, standing toward the bar, profile, ledger and last
## order from a single snapshot row (DR-20261114-04).
func test_a_crowns_card_reads_one_snapshot_row() -> void:
	var card := ObserverCrownCard.new()
	add_child(card)
	var row: Dictionary = {
		"faction": 3, "rank": 2, "name": "Spain", "alive": true,
		"leader": "Felipe", "agenda": "Bourbon", "profile": "trader",
		"posture": "patient", "intent": "hold", "headline": "Marched on Lisbon.",
		"provinces_old": 11, "provinces_new": 2, "power": 40, "regiments": 6,
		"ships": 4, "civilians": 3, "treasury": 900, "stock": 12, "workers": 5,
		"wars": ["Portugal"], "pressure_stage": AiVictoryPressure.STAGE_NEAR,
	}
	card.fill(row)
	assert_eq(card.rank.text, "#2")
	assert_eq(card.name_label.text, "Spain")
	assert_true(card.progress.text.ends_with("pressing"), "the endgame court is marked")
	assert_true(
		card.progress.text.begins_with(
			"%d/%d" % [11, VictoryRules.MILITARY_THRESHOLD]
		),
		"the standing leads the line"
	)
	assert_true(card.meta.text.contains("Felipe"), "the profile line names the court")
	assert_true(card.stats.text.contains("wars: Portugal"), "the ledger names the war")
	assert_eq(card.last.text, "Last turn: Marched on Lisbon.")
	row["alive"] = false
	row["pressure_stage"] = AiVictoryPressure.STAGE_FAR
	card.fill(row)
	assert_true(card.name_label.text.ends_with("(fallen)"), "a fallen crown says so")
	assert_false(card.progress.text.ends_with("pressing"), "a far court is not")
	card.free()
