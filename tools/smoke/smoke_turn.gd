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
		run.check(screen.hud.gazette_plate.is_shown(), "news opens the soft plate")
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
	screen.hud.panels.hide_economy()
	run.check(not screen.hud.panels.is_economy_open(), "ledger closes")


## The college's tree tab prints the whole catalog and what stands between the
## crown and any advance, so a goal can be aimed at from far out (REQ-P5-03).
static func _college(run, screen: MapScreen) -> void:
	screen.economy.open_research()
	await run.tree.process_frame
	run.check(screen.hud.panels.is_research_open(), "college opens")
	var college: ResearchPanel = screen.hud.panels.research_panel
	college.select_tab(2)
	var tree: ResearchTreeTab = college._tree
	run.check(
		tree != null and tree._body.get_child_count() == TechCatalog.ids().size(),
		"the tree tab lists every advance"
	)
	run.check(run.has_text(tree, "Needs "), "a locked advance names what it needs")
	screen.hud.panels.hide_research()
	run.check(not screen.hud.panels.is_research_open(), "college closes")
	run.check(
		TurnTime.year_for_turn(screen.turn) == TurnTime.START_YEAR + 2,
		"turn maps to expected year"
	)


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
