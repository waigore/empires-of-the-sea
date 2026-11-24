extends RefCounted
## Eighth step of the e2e smoke: one real turn, closed through MapPlayTurn and
## read phase by phase — the calendar, Build/work's deliveries, the Gazette's
## first watch, the rival courts' pass, the ledger's auction and college, the
## works that resolve, and the sound desk's cues (wiki: workers-and-population
## § Phase placement, the-gazette § When it appears).
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.

const SmokeFind = preload("res://tools/smoke/smoke_find.gd")


static func step(run) -> void:
	var screen: MapScreen = run.screen
	var turn_before: int = screen.turn
	# The desk's fades are already landed by the HUD step (`fade_scale = 0`), so
	# the bed this turn keeps costs no frame to hear (docs/testing.md § Speed
	# rules). Nothing about what the turn resolves changes.
	MapPlayTurn.end_turn(screen.play)
	await run.tree.process_frame
	await _answer_proposal(run, screen, turn_before)
	run.check(screen.turn == turn_before + 1, "end turn advances calendar")
	_mustered(run, screen)
	_gazette(run, screen, turn_before)
	await _ledger(run, screen)
	await _college(run, screen)
	_works(run, screen)
	_audio(run)


## A rival proposal suspends the phase until the court answers; accept it so the
## calendar can close (wiki: diplomacy § Court proposals).
static func _answer_proposal(run, screen: MapScreen, turn_before: int) -> void:
	if not DiplomacyProposals.has_pending(screen.play.diplomacy, MapScreen.PLAYER_FACTION):
		return
	run.check(screen.turn == turn_before, "a rival proposal holds the calendar")
	run.check(
		screen.hud.panels.diplomacy_panel._call_box.visible,
		"the court opens for the proposal"
	)
	MapCourtOrders.apply(
		screen.play, DiplomacyProposals.KIND_ACCEPT, MapScreen.PLAYER_FACTION, ""
	)
	await run.tree.process_frame
	run.check(
		not DiplomacyProposals.has_pending(
			screen.play.diplomacy, MapScreen.PLAYER_FACTION
		),
		"the court answer closes the proposal"
	)


## Build/work delivered this turn's queued orders (wiki: workers-and-population
## § Phase placement).
static func _mustered(run, screen: MapScreen) -> void:
	if run.works.has("hire"):
		run.check(
			screen.civilian_layer.unit_count_all(MapScreen.PLAYER_FACTION)
			> int(run.works["hire"]),
			"Build/work musters the queued hire"
		)
	if not run.works.has("regiments"):
		return
	var mustered: ArmyState = SmokeFind.home_army(screen)
	run.check(
		mustered != null and mustered.count() > int(run.works["regiments"]),
		"Build/work musters the queued regiment"
	)
	run.check(
		screen.hud._army_label.text
		== str(screen.army_layer.regiment_count_all(MapScreen.PLAYER_FACTION)),
		"troop chip counts the new regiment"
	)


## The crown's sheet files the resolved turn and opens when it has news (wiki:
## the-gazette § When it appears); every rival court then took its turn.
static func _gazette(run, screen: MapScreen, turn_before: int) -> void:
	run.check(screen.play.gazette != null, "the gazette keeps its watchlist")
	run.check(screen.play.gazette.has_sheet(turn_before), "the resolved turn is filed")
	if not Gazette.is_empty(screen.play.gazette.sheet_for(turn_before)):
		run.check(screen.hud.gazette_plate.is_shown(), "news opens the crown's sheet")
		screen.hud.gazette_plate.dismiss()
		run.check(not screen.hud.gazette_plate.is_shown(), "one press sets the sheet aside")
	run.check(screen.play.ai_trace.size() == 5, "rival AI courts took their turn")
	run.check(SmokeFind.rival_research_started(screen), "rivals filled their research slots")


## The crown's purse and the world market: the ledger reads the economy, stages
## an import and a bid on a court's harvest, and every order fills on the
## turn-end auction (wiki: market § Clearing; DR-20261112-11).
static func _ledger(run, screen: MapScreen) -> void:
	run.check(screen.economy != null, "economy wired")
	run.check(
		screen.treasury == screen.economy.economy.treasury,
		"treasury reads from the economy ledger"
	)
	run.check(screen.economy.economy.total_units() > 0, "stockpile holds goods")
	run.check(
		screen.economy.extraction().size() > 0,
		"owned provinces yield commodities"
	)
	screen.economy.open_panel()
	await run.tree.process_frame
	run.check(screen.hud.panels.is_economy_open(), "ledger opens")
	run.check(
		int(screen.economy.trade_cargo().get("holds", 0)) > 0,
		"the home fleet carries trade cargo"
	)
	run.check(
		bool((screen.economy.trade_cargo().get("crossing", {}) as Dictionary).get("known", false)),
		"the ledger reads the crossing its holds will make"
	)
	run.check(
		run.has_text(
			screen.hud.panels.economy_panel.page_body(EconomyPanel.TAB_MARKET), "CONVOY"
		),
		"the market sheet names what covers the convoy"
	)
	var grain_before: int = screen.economy.economy.quantity("grain")
	screen.economy.orders.trade("grain", 1, true)
	run.check(
		screen.economy.market.book.pending_buy_units(screen.player_faction) == 1,
		"the ledger stages imports against cargo holds"
	)
	SmokeFind.clear_market(screen)
	run.check(
		screen.economy.economy.quantity("grain") == grain_before + 1,
		"the turn-end auction fills the import"
	)
	var offers: Array[Dictionary] = screen.economy.market.minor_offers
	run.check(not offers.is_empty(), "the minor courts publish their harvest")
	if not offers.is_empty():
		var offer: Dictionary = offers[0]
		var offer_id: String = String(offer["id"])
		var offer_good: String = String(offer["commodity"])
		var offer_stock: int = screen.economy.economy.quantity(offer_good)
		screen.hud.panels.economy_panel.emit_signal("offer_requested", offer_id, 1)
		run.check(
			screen.economy.market.book.pending_buy_units(screen.player_faction) == 1,
			"the ledger stages a bid on a court's offer"
		)
		SmokeFind.clear_market(screen)
		run.check(
			screen.economy.economy.quantity(offer_good) == offer_stock + 1,
			"the turn-end auction fills the offer bid"
		)
	screen.economy.orders.set_production("lumber", 1)
	run.check(
		screen.economy.economy.production.assignment_units("lumber") == 1,
		"production assignment sticks"
	)
	# A two-turn alloy names its wait on the row, so a phone player is not left
	# wondering why the stockpile did not move (DR-20261112-11).
	var production_body: Node = screen.hud.panels.economy_panel.page_body(
		EconomyPanel.TAB_PRODUCTION
	)
	run.check(run.has_text(production_body, "2t"), "the alloy rows name their two-turn wait")
	# The second-stage rows are on the page too, so a crown can see the works a
	# garment or a rum waits on (wiki: production-recipes § Town-works gates;
	# DR-20261116-04).
	run.check(run.has_text(production_body, "Garments"), "the works rows are on the page")
	# Runs are set row by row: the Queue-all press is gone (issue #1196).
	run.check(
		not run.has_text(production_body, "Queue all ready ("),
		"the production tab sets runs one row at a time"
	)
	screen.hud.panels.hide_economy()
	run.check(not screen.hud.panels.is_economy_open(), "ledger closes")


## The college's chart door prints the whole catalog as a graph and what stands
## between the crown and any advance, so a goal can be aimed at from far out
## (REQ-P5-03; DR-20261115-15).
static func _college(run, screen: MapScreen) -> void:
	screen.economy.open_research()
	await run.tree.process_frame
	run.check(screen.hud.panels.is_research_open(), "college opens")
	var college: ResearchPanel = screen.hud.panels.research_panel
	# An open advance names what the study opens under its price, so a touch
	# crown reads the payoff before the press (REQ-P1-05; DR-20261118-04).
	run.check(
		run.has_text(college, "Improves: extraction cap Timber 2."),
		"an open advance names what it opens"
	)
	# The court's own counsel rides the first idle slot: the study the published
	# policy would open there, in one sentence (wiki: tech-tree § Research Model;
	# DR-20261121-01).
	var counsel: String = college.pick_line()
	run.check(
		(counsel.is_empty() and screen.economy.economy.research.free_slot() < 0)
		or (counsel.begins_with("The court would open ") and counsel.ends_with(".")),
		"the college names the study it would open"
	)
	# The advance that sentence names wears `▸` in the AVAILABLE list — the mark
	# the chart sets on the same advance — so the row the crown would press is
	# found without scanning the list (wiki: tech-tree § Research Model;
	# DR-20261122-19).
	var college_tech: String = college.pick_tech()
	run.check(
		counsel.is_empty() == college_tech.is_empty(),
		"the counsel names the advance it marks, and no counsel marks none"
	)
	run.check(
		college_tech.is_empty()
		or run.has_text(college, "▸ %s" % TechCatalog.display_name(college_tech)),
		"the college marks the study it would open"
	)
	var door: Button = _door(college)
	run.check(door != null, "the college offers the chart")
	var free_before: int = screen.economy.economy.research.free_slot()
	if door != null:
		door.pressed.emit()
	await run.tree.process_frame
	var chart: TechTreePanel = screen.hud.tech_tree
	run.check(chart.is_open(), "the chart opens over the college")
	run.check(
		chart._canvas.node_count() == TechCatalog.ids().size(),
		"the chart places every advance"
	)
	# The chart names the study the court would open and marks it `▸`, so the
	# crown sees where the court would go on the chart itself (wiki: tech-tree
	# § Research Model; DR-20261121-20).
	run.check(
		chart.counsel_source.is_valid(),
		"the chart binds the court's reading"
	)
	var chart_line: String = chart.counsel_text()
	run.check(
		chart_line.is_empty() or chart_line.begins_with("The court would open "),
		"the chart names the study the court would open"
	)
	var court_tech: String = chart.court_tech()
	run.check(
		court_tech.is_empty()
		or (chart._canvas.node(court_tech) != null
			and chart._canvas.node(court_tech).text.contains("▸")),
		"the chart marks the court's own study"
	)
	run.check(
		screen.economy.economy.research.free_slot() == free_before,
		"the chart's reading assigns nothing"
	)
	chart._canvas.node("safety_lamp").pressed.emit()
	run.check(run.has_text(chart, "extraction cap"), "a tapped advance reads what it grants")
	var aim: Button = _button(chart, "Set as research goal")
	run.check(aim != null, "the reading carries the goal door")
	if aim != null:
		aim.pressed.emit()
	run.check(
		screen.economy.economy.research.goal == "safety_lamp",
		"the chart aims the queue at the tapped advance"
	)
	chart.close()
	run.check(not chart.is_open(), "the chart closes back to the college")
	screen.hud.panels.hide_research()
	run.check(not screen.hud.panels.is_research_open(), "college closes")
	run.check(
		TurnTime.year_for_turn(screen.turn) == TurnTime.START_YEAR + 2,
		"turn maps to expected year"
	)


## The first button under `root` whose caption begins with `prefix`.
static func _button(root: Node, prefix: String) -> Button:
	if root is Button and String((root as Button).text).begins_with(prefix):
		return root as Button
	for child: Node in root.get_children():
		var found: Button = _button(child, prefix)
		if found != null:
			return found
	return null


static func _door(college: ResearchPanel) -> Button:
	return _button(college, "TECH TREE")


## The work the civilian pass queued resolves on the turn it was given.
static func _works(run, screen: MapScreen) -> void:
	var improvement: Vector2i = run.works.get("improvement", Vector2i(-1, -1))
	if improvement.x >= 0:
		run.check(
			screen.land_works.improvement_at(screen.model, improvement) == 1,
			"builder work resolves on end turn"
		)
	var road: Vector2i = run.works.get("road", Vector2i(-1, -1))
	if road.x >= 0:
		run.check(
			screen.land_works.transport_at(screen.model, road) >= LandWorks.TRANSPORT_ROAD,
			"engineer road resolves on end turn"
		)
	var prospect: Vector2i = run.works.get("prospect", Vector2i(-1, -1))
	if prospect.x >= 0:
		run.check(
			screen.land_works.is_prospected(
				MapScreen.PLAYER_FACTION, screen.model, prospect
			),
			"prospect completes on end turn"
		)


## The turn spoke: the desk fired its cues and keeps a music bed (REQ-P1-06).
static func _audio(run) -> void:
	if run.audio == null:
		return
	run.check(run.audio.sfx_played >= run.cues_before + 3, "turn cues fired")
	# Only war resolves a battle now; either bed is fine, silence is not.
	var bed: String = run.audio.current_track_id()
	run.check(
		bed == MusicPlaylist.AGE_OF_DISCOVERY or bed == MusicPlaylist.BROADSIDES,
		"music keeps a bed after the turn (%s)" % bed
	)
