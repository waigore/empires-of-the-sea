extends RefCounted
## The reading half of the counsel step: the estates card on the cartouche, the
## ledger's PRODUCTION plan, MARKET trade and WORKERS tiers, and the crown's
## eyes — each opened from the door the player uses, printing its gold line,
## marking the rows it answers, and setting nothing (REQ-P1-07, REQ-P5-06;
## DR-20261121-07/09/11, DR-20261122-01/08/10/18, DR-20261123-08).
##
## The bar's sheets (smoke_counsel_sheets.gd), the three yards
## (smoke_counsel_yards.gd) and the shared tally (smoke_counsel_reads.gd) make
## the rest of the step.
##
## No `class_name`: the counsel step (tools/smoke/smoke_counsel.gd) preloads
## this file.

const SmokeReads = preload("res://tools/smoke/smoke_counsel_reads.gd")


static func step(run, screen: MapScreen) -> void:
	await _estates(run, screen)
	await _production(run, screen)
	await _market(run, screen)
	await _workers(run, screen)
	await _eyes(run, screen)


## The estates door on the cartouche opens the crown's works ledger (REQ-P1-07).
static func _estates(run, screen: MapScreen) -> void:
	var estates_door: Button = screen.hud.top_row.find_child(
		"EstatesSeal", true, false
	) as Button
	run.check(estates_door != null, "estates door on the bar")
	estates_door.pressed.emit()
	await run.tree.process_frame
	run.check(screen.improvements.is_open(), "estates ledger opens")
	run.check(
		screen.improvements._data.has("counts"),
		"estates ledger builds a snapshot"
	)
	# The one press under the chips names the ready estates the view prints
	# (REQ-P5-04; DR-20261116-06).
	var ready: int = screen.improvements.ready_tiles().size()
	run.check(
		screen.improvements._batch.visible == (ready > 0), "estates press stands"
	)
	# Every row prices the raise it offers: the next level's harvest, or the cap
	# that holds it flat (REQ-P5-06; DR-20261117-03).
	var priced: bool = false
	for row: Dictionary in screen.improvements._data.get("estates", []):
		if (
			int(row.get("level", 0)) < ImprovementCatalog.MAX_LEVEL
			and not bool(row.get("working", false))
			and not String(row.get("preview_text", "")).is_empty()
		):
			priced = true
			break
	run.check(priced, "an estate row prices its raise")
	# The card names the estates the court's own Builder pass would raise, or the
	# gate that leaves the page with nothing to name (REQ-P5-06; DR-20261121-10).
	var counsel: String = screen.improvements.counsel_text()
	run.check(
		counsel.is_empty() or counsel.begins_with("The court would raise "),
		"estates counsel names the court's own raise"
	)
	run.check(
		screen.improvements._counsel.visible == not counsel.is_empty(),
		"estates counsel stands with its reading"
	)
	# Every estate the reading names wears the counsel's mark, and no other row
	# does, so the raise is found among a long page (DR-20261122-04).
	var pick: Dictionary = MapPlayEstatesPick.pick(screen.play, screen.improvements._data)
	run.check(
		SmokeReads.marked_estates(screen.improvements) == (pick.get("keys", {}) as Dictionary).size(),
		"every estate the court would raise wears the mark"
	)
	# The card says what that mark means beside it, where a phone that drops the
	# footer still reads it (DR-20261123-03/07).
	run.check(
		screen.improvements.legend_text() == ImprovementPanel.MARK_LEGEND,
		"the estates card names its mark"
	)
	run.check(
		screen.improvements.legend_shown()
			== not (pick.get("keys", {}) as Dictionary).is_empty(),
		"the estates legend stands with the marks it explains"
	)
	screen.improvements.close()


## The ledger's PRODUCTION tab names the runs the crown's own economy pass would
## book this phase, in the tab's gold line above the rows it answers — and sets
## nothing (wiki: stockpiles-and-production § Production flow; DR-20261121-07).
static func _production(run, screen: MapScreen) -> void:
	var set_before: int = screen.economy.economy.production.assignments().size()
	screen.economy.open_panel()
	await run.tree.process_frame
	run.check(screen.hud.panels.is_economy_open(), "ledger opens")
	var page: LedgerProduction = (
		screen.hud.panels.economy_panel.page_body(EconomyPanel.TAB_PRODUCTION)
		as LedgerProduction
	)
	run.check(page != null, "the PRODUCTION tab stands")
	if page != null:
		run.check(
			not page.counsel_text().is_empty(),
			"the ledger names the plan the court would run"
		)
		# Every run the plan books leads its row with the counsel's mark, and no
		# other row wears one, so the good is found among the whole catalogue
		# (DR-20261122-10).
		var pick: Dictionary = MapPlayProductionPick.pick(screen.play)
		var runs: Dictionary = pick.get("runs", {}) as Dictionary
		run.check(
			SmokeReads.marked_recipes(page) == runs.size(),
			"every run the court would set wears the mark (%d marked, %d booked)"
			% [SmokeReads.marked_recipes(page), runs.size()]
		)
		run.check(
			SmokeReads.printed(page, LedgerProduction.COURT_LEGEND) == (not runs.is_empty()),
			"the workshop's heading names the mark it prints"
		)
	run.check(
		screen.economy.economy.production.assignments().size() == set_before,
		"the plan reading sets nothing"
	)
	screen.hud.panels.hide_economy()


## The ledger's MARKET tab names the trade the crown's own market pass would
## book this phase, in the tab's gold line above the orders it answers, and
## marks the goods that plan names on their own rows — and stages nothing
## (wiki: world-market § Trade orders; DR-20261121-09, DR-20261122-08).
static func _market(run, screen: MapScreen) -> void:
	var orders_before: int = screen.economy.market.book.orders_for(
		screen.player_faction
	).size()
	screen.economy.open_panel()
	await run.tree.process_frame
	var page: LedgerMarket = (
		screen.hud.panels.economy_panel.page_body(EconomyPanel.TAB_MARKET)
		as LedgerMarket
	)
	run.check(page != null, "the MARKET tab stands")
	if page != null:
		run.check(
			not page.counsel_text().is_empty(),
			"the ledger names the trade the court would book"
		)
		# Every good the court's plan names leads its own row with the counsel's
		# mark, and the book the page holds is the one the line was worded from
		# (DR-20261122-08).
		var book: Dictionary = page.court_marks()
		run.check(
			book == LedgerMarket.court_rows(MapPlayMarketPick.pick(screen.play)),
			"the market marks the plan its reading words"
		)
		run.check(
			SmokeReads.marked_goods(page) == book.size(),
			"every good the court would trade wears the mark"
		)
	run.check(
		screen.economy.market.book.orders_for(screen.player_faction).size()
		== orders_before,
		"the trade reading stages nothing"
	)
	screen.hud.panels.hide_economy()


## The ledger's WORKERS tab names the workers the crown's own economy pass would
## recruit this phase, in the tab's gold line above the tier rows it answers, and
## marks those rows — and enlists nobody (wiki: workers-and-population
## § Recruiting; DR-20261122-01).
static func _workers(run, screen: MapScreen) -> void:
	var before: Array[int] = screen.economy.economy.workers.counts.duplicate()
	screen.economy.open_panel()
	await run.tree.process_frame
	var page: LedgerWorkers = (
		screen.hud.panels.economy_panel.page_body(EconomyPanel.TAB_WORKERS)
		as LedgerWorkers
	)
	run.check(page != null, "the WORKERS tab stands")
	if page != null:
		var counsel: String = page.counsel_text()
		run.check(
			counsel.is_empty() or counsel.begins_with("The court would recruit "),
			"the ledger names the workers the court would recruit"
		)
		run.check(
			page._counsel.visible == not counsel.is_empty(),
			"the workers' counsel stands with its reading"
		)
		# The tab keeps no footer, so the sentence that says what a marked tier
		# means stands under the line (DR-20261123-08).
		var tiers: Dictionary = MapPlayRecruitPick.pick(screen.play).get("tiers", {})
		run.check(
			page.legend_text() == LedgerWorkers.MARK_LEGEND,
			"the workers' tab names its mark"
		)
		run.check(
			page.legend_shown() == not tiers.is_empty(),
			"the workers' legend stands with the marks it explains"
		)
	run.check(
		screen.economy.economy.workers.counts == before,
		"the workers' reading enlists nobody"
	)
	screen.hud.panels.hide_economy()


## THE CROWN'S EYES names the spies the court's own espionage pass would book and
## marks every spy it would walk or screen, off the one pick the gold line is
## worded from — and orders nothing (wiki: civilian-units § Spy; DR-20261121-11,
## DR-20261122-18).
static func _eyes(run, screen: MapScreen) -> void:
	var before: Array = SmokeReads.spy_orders(screen)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.EYES)
	await run.tree.process_frame
	var eyes: SpyLedgerPanel = screen.hud.spy_ledger
	run.check(eyes != null and eyes.is_open(), "the crown's eyes open")
	if eyes == null:
		return
	var counsel: String = eyes.counsel_text()
	run.check(
		counsel.is_empty() or counsel.begins_with("The court would "),
		"the eyes name the spies the court would book"
	)
	run.check(
		eyes._counsel.visible == not counsel.is_empty(),
		"the eyes' counsel stands with its reading"
	)
	var pick: Dictionary = MapPlaySpyPick.pick(screen.play, eyes._snapshot)
	var keys: Dictionary = pick.get("keys", {}) as Dictionary
	run.check(
		SmokeReads.marked_spies(eyes) == keys.size(),
		"every spy the court would order wears the mark"
	)
	run.check(
		SmokeReads.spy_orders(screen) == before,
		"the eyes' reading orders nothing"
	)
	eyes.close()
