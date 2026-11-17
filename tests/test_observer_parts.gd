extends GdToolsTest
## The AI observatory's read-only halves read out of the panel: [ObserverTurnFeed]
## words the order feed and its caption, [ObserverCrownCard] paints one court's
## standing, so the panel only drives the calendar (REQ-P3-01, REQ-P3-03).

## The feed prints every row of the turns it keeps, newest row first, and counts
## what it holds (REQ-P5-05).
func test_the_feed_prints_every_row_of_the_turns_it_keeps() -> void:
	assert_eq(ObserverTurnFeed.text([]), ObserverTurnFeed.EMPTY_TEXT)
	assert_eq(ObserverTurnFeed.caption([]), "Recent orders", "an empty feed counts none")
	assert_eq(
		ObserverTurnFeed.caption([{"turn": 1, "events": [{"text": "Marched."}]}]),
		"Recent orders  ·  1 rows over 1 turn, newest first",
		"one turn's one row prints as written"
	)
	assert_eq(
		ObserverTurnFeed.text([{"turn": 7, "events": []}]),
		ObserverTurnFeed.EMPTY_TEXT,
		"a turn that filed nothing prints no line"
	)
	var ai_turns: Array = []
	for turn in [1, 2, 3, 4]:
		var events: Array = []
		for index in 2:
			events.append({"text": "T%d order %d." % [turn, index]})
		ai_turns.append({"turn": turn, "events": events})
	var text: String = ObserverTurnFeed.text(ai_turns)
	var lines: PackedStringArray = text.split("\n")
	assert_eq(lines.size(), 4, "two whole turns, two rows each")
	assert_eq(
		String(lines[0]), "T4  T4 order 1.", "the newest order leads the feed"
	)
	assert_eq(
		String(lines[3]), "T3  T3 order 0.",
		"the kept turn's first order is kept, not cut"
	)
	assert_false(text.contains("T2"), "the turns before the window are dropped")
	assert_eq(ObserverTurnFeed.first_kept(4), 2, "the two newest turns are kept")
	assert_eq(
		ObserverTurnFeed.caption(ai_turns),
		"Recent orders  ·  4 rows over 2 turns, newest first"
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
