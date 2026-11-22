extends RefCounted
## The court's readings on the bar's ledgers: every sheet that names the orders
## the crown's own passes would give this turn — the estates, the people, the
## navy, the army, the muster, the colonies, the realm, the production, the
## market and the workers tabs — opens from the door the player uses, prints its
## one gold line, and orders nothing
## (DR-20261121-05/06/07/09/12/13/14/16/17/19/21, DR-20261122-01/03/04/06/08/12).
##
## The court ledger's own envoy and the sound desk stay in the HUD step; this
## step owns the counsel readings and the tallies that prove they move nothing.
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.

const SmokeFind = preload("res://tools/smoke/smoke_find.gd")


static func step(run) -> void:
	var screen: MapScreen = run.screen
	await _estates(run, screen)
	await _people(run, screen)
	await _navy(run, screen)
	await _army(run, screen)
	await _muster(run, screen)
	await _colonies(run, screen)
	await _realm(run, screen)
	await _production(run, screen)
	await _market(run, screen)
	await _workers(run, screen)
	await _yards(run, screen)


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
		_marked_estates(screen.improvements) == (pick.get("keys", {}) as Dictionary).size(),
		"every estate the court would raise wears the mark"
	)
	screen.improvements.close()


## THE CROWN'S PEOPLE names the work the court's own civilian pass would put its
## crews to this turn, in one gold line under its filters — and orders nothing
## (wiki: civilian-units § Empire roster; DR-20261121-12).
static func _people(run, screen: MapScreen) -> void:
	var working_before: int = _working_crews(screen)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	await run.tree.process_frame
	var roster: CivilianRosterPanel = screen.hud.civilian_roster
	run.check(roster != null and roster.is_open(), "the crown's people open")
	if roster == null:
		return
	var counsel: String = roster.counsel_text()
	run.check(
		counsel.is_empty() or counsel.begins_with("The court would put "),
		"the people name the work the court would give"
	)
	run.check(
		roster._counsel.visible == not counsel.is_empty(),
		"the people's counsel stands with its reading"
	)
	# Every crew the court's reading names wears the counsel's mark, and no other
	# row does, so the work is found among a long roster (DR-20261122-06).
	var pick: Dictionary = MapPlayPeoplePick.pick(screen.play, roster._snapshot)
	var keys: Dictionary = pick.get("keys", {})
	var honest: bool = true
	var named: int = 0
	for child: Node in roster._rows.get_children():
		var row := child as CivilianRosterRow
		if row == null:
			continue
		var marked: bool = keys.has(MapPlayPickProse.row_key(row.data, "unit_id"))
		honest = honest and row.court == marked
		if marked:
			named += 1
	run.check(honest, "the people mark exactly the crews their reading names")
	run.check(
		_marked_crews(roster) == keys.size() and named == keys.size(),
		"every crew the court would spend wears the mark"
	)
	run.check(_working_crews(screen) == working_before, "the reading orders nothing")
	roster.close()


## THE CROWN'S NAVY names the sails the court's own naval pass would order its
## squadrons this turn, in one gold line above the hulls it answers — and orders
## nothing (wiki: ships-and-naval § The crown's navy; DR-20261121-13).
static func _navy(run, screen: MapScreen) -> void:
	var before: Array = _fleet_orders(screen)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.NAVY)
	await run.tree.process_frame
	var navy: NavalLedgerPanel = screen.hud.navy_ledger
	run.check(navy != null and navy.is_open(), "the crown's navy opens")
	if navy == null:
		return
	var counsel: String = navy.counsel_text()
	run.check(
		counsel.is_empty() or counsel.begins_with("The court would send "),
		"the navy names the sails the court would order"
	)
	run.check(
		navy._counsel.visible == not counsel.is_empty(),
		"the navy's counsel stands with its reading"
	)
	run.check(_fleet_orders(screen) == before, "the navy's reading orders nothing")
	# Every squadron heading the court's reading names wears the counsel's mark,
	# and no other heading does (DR-20261122-05).
	var keys: Dictionary = MapPlayNavyPick.pick(screen.play, navy._snapshot).get("keys", {})
	var named: int = 0
	var honest: bool = true
	for group: Dictionary in NavalLedger.groups(
		navy._snapshot, LedgerRows.REGION_ALL, NavalLedger.READING_ALL
	):
		var marked: bool = keys.has(MapPlayPickProse.row_key(group, "fleet"))
		honest = honest and navy._is_marked(group) == marked
		if marked:
			named += 1
	run.check(honest, "the navy marks exactly the squadrons its reading names")
	run.check(
		_marked_headings(navy._rows) == named,
		"the navy's marks are painted on the headings they answer"
	)
	navy.close()


## THE CROWN'S ARMY names the orders the court's own staff would give its
## standards this turn, in one gold line above the regiments it answers — and
## marches nothing (wiki: military-armies § The crown's army; DR-20261121-14).
static func _army(run, screen: MapScreen) -> void:
	var before: Array = _army_orders(screen)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.ARMY)
	await run.tree.process_frame
	var army: ArmyLedgerPanel = screen.hud.army_ledger
	run.check(army != null and army.is_open(), "the crown's army opens")
	if army == null:
		return
	var counsel: String = army.counsel_text()
	run.check(
		counsel.is_empty()
		or counsel.begins_with("The court would send ")
		or counsel == MapPlayPickProse.sentence(MapPlayArmyOrdersPick.NO_ORDER_LINE),
		"the army names the orders the court would give"
	)
	run.check(
		army._counsel.visible == not counsel.is_empty(),
		"the army's counsel stands with its reading"
	)
	run.check(_army_orders(screen) == before, "the army's reading orders nothing")
	# Every standard heading the court's reading names wears the counsel's mark,
	# and no other heading does (DR-20261122-05).
	var keys: Dictionary = MapPlayArmyOrdersPick.pick(screen.play, army._snapshot).get("keys", {})
	var named: int = 0
	var honest: bool = true
	for group: Dictionary in ArmyLedger.groups(
		army._snapshot, LedgerRows.REGION_ALL, ArmyLedger.READING_ALL
	):
		var marked: bool = keys.has(MapPlayPickProse.row_key(group, "army"))
		honest = honest and army._is_marked(group) == marked
		if marked:
			named += 1
	run.check(honest, "the army marks exactly the standards its reading names")
	run.check(
		_marked_headings(army._rows) == named,
		"the army's marks are painted on the headings they answer"
	)
	army.close()


## THE CROWN'S MUSTER names the orders the court's own staff would give every
## force this turn — both the army's standards and the navy's squadrons in one
## gold line under the chips — and every force the line answers leads with the
## counsel's mark (wiki: military-armies § The muster roll; DR-20261121-17,
## DR-20261122-03).
static func _muster(run, screen: MapScreen) -> void:
	var before: Array = _army_orders(screen)
	before.append_array(_fleet_orders(screen))
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	await run.tree.process_frame
	var muster: ForceLedgerPanel = screen.hud.muster_roll
	run.check(muster != null and muster.is_open(), "the muster roll opens")
	if muster == null:
		return
	var counsel: String = muster.counsel_text()
	run.check(
		counsel.is_empty()
		or counsel.begins_with("The court would send ")
		or counsel == MapPlayPickProse.sentence(MapPlayForceCounsel.NO_ORDER_LINE),
		"the muster names the orders the court would give"
	)
	run.check(
		muster._counsel.visible == not counsel.is_empty(),
		"the muster's counsel stands with its reading"
	)
	var muster_pick: Dictionary = MapPlayForceCounsel.pick(screen.play, muster._snapshot)
	run.check(
		_marked_forces(muster) == (muster_pick.get("keys", {}) as Dictionary).size(),
		"every force the court would send wears the mark"
	)
	var after: Array = _army_orders(screen)
	after.append_array(_fleet_orders(screen))
	run.check(after == before, "the muster's reading orders nothing")
	muster.close()


## THE COLONIES names the Tribe the court's own envoy is drawing into the empire
## this turn, in one gold line above the roll — and signs no overture
## (wiki: diplomacy § GP–Tribe Rules; DR-20261121-16).
static func _colonies(run, screen: MapScreen) -> void:
	var before: Array = _colony_overtures(screen)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COLONIES)
	await run.tree.process_frame
	var colonies: ColonyLedgerPanel = screen.hud.colonies_ledger
	run.check(colonies != null and colonies.is_open(), "the colonies open")
	if colonies == null:
		return
	var counsel: String = colonies.counsel_text()
	run.check(
		counsel.is_empty()
		or counsel.begins_with("The court would offer ")
		or counsel.begins_with("The court's chain with ")
		or counsel == MapPlayPickProse.sentence(MapPlayColonyPick.CLOSED_LINE),
		"the colonies name the Tribe the court is buying"
	)
	run.check(
		colonies._counsel.visible == not counsel.is_empty(),
		"the colonies' counsel stands with its reading"
	)
	run.check(_colony_overtures(screen) == before, "the colonies' reading signs nothing")
	colonies.close()


## The realm names the provinces the court would act in this turn, and every
## such row leads with the counsel's mark (wiki: world-model § The crown's
## provinces; DR-20261121-21). The province sheet itself is read in the HUD step.
static func _realm(run, screen: MapScreen) -> void:
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.PROVINCES)
	await run.tree.process_frame
	var realm: ProvinceLedgerPanel = screen.hud.province_ledger
	run.check(realm.is_open(), "the realm ledger opens")
	var realm_counsel: String = realm.counsel_text()
	run.check(
		realm_counsel.is_empty()
		or realm_counsel.begins_with("The court would act in ")
		or realm_counsel == MapPlayPickProse.sentence(MapPlayRealmCounsel.NO_ORDER_LINE),
		"the realm names the provinces the court would act in"
	)
	run.check(
		realm._counsel.visible == not realm_counsel.is_empty(),
		"the realm's counsel stands with its reading"
	)
	var realm_pick: Dictionary = MapPlayRealmCounsel.pick(screen.play)
	run.check(
		_marked_rows(realm) == (realm_pick.get("keys", {}) as Dictionary).size(),
		"every province the court would act in wears the mark"
	)
	realm.close()


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
			_marked_recipes(page) == runs.size(),
			"every run the court would set wears the mark (%d marked, %d booked)"
			% [_marked_recipes(page), runs.size()]
		)
		run.check(
			_printed(page, LedgerProduction.COURT_LEGEND) == (not runs.is_empty()),
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
			_marked_goods(page) == book.size(),
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
	run.check(
		screen.economy.economy.workers.counts == before,
		"the workers' reading enlists nobody"
	)
	screen.hud.panels.hide_economy()


## The yards mark the one row their gold line names: the drill yard's pattern, the
## slip's hull and the capital rail's crew, each off the same pick the line is
## worded from, and a yard that names nothing marks nothing (wiki:
## military-armies § Home Army, ships-and-naval § Ship build economy,
## civilian-units § Training; DR-20261122-12).
static func _yards(run, screen: MapScreen) -> void:
	var play: PlaySession = screen.play
	var before: Dictionary = {
		"regiments": play.army_layer.regiment_count_all(play.player_faction),
		"treasury": play.economy.economy.treasury,
	}
	# The drill yard, in the Home Army's own dossier (DR-20261121-03).
	MapPlayArmies.open_muster(play)
	await run.tree.process_frame
	var army_panel: ArmyPanel = screen.hud.panels.army_panel
	var yard: ArmyMusterBlock = army_panel._muster_box if army_panel != null else null
	run.check(yard != null, "the drill yard stands in the Home Army's dossier")
	if yard != null:
		var home: ArmyState = ArmyTraining.home_army(
			play.army_layer.armies, play.player_faction
		)
		var muster: Dictionary = MapPlayMusterPick.pick(play, home)
		run.check(
			yard.pick_line() == MapPlayPickProse.sentence_of(muster),
			"the drill yard prints the court's own muster"
		)
		run.check(
			yard.mark_type() == String(muster.get("type", "")),
			"the drill yard marks the pattern its line names"
		)
		run.check(
			_marked_yard_rows(yard, ArmyMusterBlock.COURT_MARK)
			== (1 if not yard.mark_type().is_empty() else 0),
			"and paints the mark on that pattern's row alone"
		)
	# The capital slip, from the door the province dossier opens (DR-20261121-02).
	MapPlayFleetYard.open(play)
	await run.tree.process_frame
	var fleet_panel: FleetPanel = screen.hud.panels.fleet_panel
	var slip: FleetYardBlock = fleet_panel._yard if fleet_panel != null else null
	run.check(slip != null, "the slip stands in the capital's dossier")
	if slip != null:
		var laid: Dictionary = MapPlayYardPick.pick(play)
		run.check(
			slip.pick_line() == MapPlayPickProse.sentence_of(laid),
			"the slip prints the court's own claim"
		)
		run.check(
			slip.mark_type() == String(laid.get("type", "")),
			"the slip marks the hull its line names"
		)
	# The capital rail's craft rows (DR-20261121-06).
	var seat: int = int(MapPlayCourt.crown_seat(play).get("province", -1))
	run.check(seat >= 0, "the crown keeps a seat to hire at")
	if seat >= 0:
		MapPlayInput.select_province(
			play, seat, screen.model.province_center(seat) * MapScreen.TILE_SIZE
		)
		await run.tree.process_frame
		var sheet: ProvincePanel = screen.hud.panels.panel
		run.check(sheet != null, "the capital's sheet opens")
		if sheet != null:
			var hire: Dictionary = MapPlayHirePick.pick(play)
			var crew: String = String(hire.get("crew", ""))
			run.check(
				sheet.hire_line_text() == String(hire.get("line", "")),
				"the rail prints the court's own hire"
			)
			run.check(
				sheet.hire_mark_crew() == crew,
				"the rail marks the craft its line names"
			)
			if not crew.is_empty():
				var row: Dictionary = sheet._orders.training_row(crew)
				run.check(
					String((row.get("button", null) as Button).text).begins_with(
						ProvinceOrdersSection.COURT_MARK
					),
					"and paints the mark on that craft's row"
				)
	run.check(
		play.army_layer.regiment_count_all(play.player_faction)
		== int(before["regiments"]),
		"the yards' readings raise no regiment"
	)
	run.check(
		play.economy.economy.treasury == int(before["treasury"]),
		"the yards' readings spend nothing"
	)


## The drill-yard rows wearing the counsel's mark.
static func _marked_yard_rows(block: ArmyMusterBlock, mark: String) -> int:
	var seen: int = 0
	for child: Node in block.get_children():
		if not (child is VBoxContainer) or child.is_queued_for_deletion():
			continue
		var top := (child as VBoxContainer).get_child(0) as HBoxContainer
		if top == null or top.get_child_count() < 2:
			continue
		if String((top.get_child(1) as Label).text).begins_with(mark):
			seen += 1
	return seen


## Every squadron's station and move flag, so a reading that sailed one shows.
static func _fleet_orders(screen: MapScreen) -> Array:
	var seen: Array = []
	for region: int in screen.play.ship_layer.regions.region_ids():
		for fleet: FleetState in MapPlayCourt.region_fleets(screen.play, region):
			if fleet == null:
				continue
			seen.append("%d:%s:%s" % [fleet.id, fleet.mission, fleet.moved])
	seen.sort()
	return seen


## Every Tribe's overture stage with the crown, so a reading that signed one
## shows.
static func _colony_overtures(screen: MapScreen) -> Array:
	var seen: Array = []
	for tribe: int in FactionCatalog.tribe_ids():
		seen.append(screen.play.diplomacy.overture(screen.play.player_faction, tribe))
	return seen


## Every standard's place and move flag, so a reading that marched one shows.
static func _army_orders(screen: MapScreen) -> Array:
	var seen: Array = []
	for region: int in screen.play.army_layer.regions.region_ids():
		for army: ArmyState in MapPlayCourt.visible_armies(screen.play, region):
			if army == null:
				continue
			seen.append("%d:%d:%s" % [army.id, army.province, army.moved])
	seen.sort()
	return seen


## How many of the crown's crews hold a running order: the tally a reading may
## not move.
static func _working_crews(screen: MapScreen) -> int:
	var working: int = 0
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit != null and unit.owner == screen.play.player_faction and unit.is_working():
			working += 1
	return working


## How many realm rows wear the counsel's mark: the ground the court would act
## in, as the sheet prints it.
static func _marked_rows(panel: ProvinceLedgerPanel) -> int:
	var marked: int = 0
	for child: Node in panel._rows.get_children():
		var row := child as ProvinceLedgerRow
		if row != null and row.court:
			marked += 1
	return marked


## How many estate rows wear the counsel's mark, so the smoke can hold the count
## to the reading's own keys (DR-20261122-04).
static func _marked_estates(panel: ImprovementPanel) -> int:
	var marked: int = 0
	for child: Node in panel._rows.get_children():
		var row := child as ImprovementRow
		if row != null and row.court:
			marked += 1
	return marked


## How many roster rows wear the counsel's mark, so the smoke can hold the count
## to the reading's own keys (DR-20261122-06).
static func _marked_crews(panel: CivilianRosterPanel) -> int:
	var marked: int = 0
	for child: Node in panel._rows.get_children():
		var row := child as CivilianRosterRow
		if row != null and row.court:
			marked += 1
	return marked


## How many muster rows wear the court's mark, so the smoke can hold the count to
## the reading's own keys (DR-20261122-03).
static func _marked_forces(panel: ForceLedgerPanel) -> int:
	var marked: int = 0
	for child: Node in panel._rows.get_children():
		var row := child as ForceLedgerRow
		if row != null and row.court:
			marked += 1
	return marked


## How many standard or squadron headings wear the counsel's mark, so the smoke
## can hold the marks painted to the headings the reading names
## (DR-20261122-05).
static func _marked_headings(rows: VBoxContainer) -> int:
	var marked: int = 0
	for child: Node in rows.get_children():
		var box := child as VBoxContainer
		if box == null or box.get_child_count() == 0:
			continue
		var label := box.get_child(0) as Label
		if label != null and label.text.begins_with(ForceLedgerRow.COURT_MARK):
			marked += 1
	return marked


## How many market rows wear the counsel's mark, so the smoke can hold the count
## to the reading's own book (DR-20261122-08).
static func _marked_goods(page: LedgerMarket) -> int:
	var marked: int = 0
	var prefix: String = MarketRow.COURT_MARK + " "
	for label: Label in page.find_children("*", "Label", true, false):
		if label.text.begins_with(prefix):
			marked += 1
	return marked


## How many workshop rows wear the counsel's mark, so the smoke can hold the
## count to the reading's own runs (DR-20261122-10). The heading's legend wears
## the same glyph and is not a row.
static func _marked_recipes(page: LedgerProduction) -> int:
	var marked: int = 0
	var prefix: String = LedgerProduction.COURT_MARK + " "
	for label: Label in page.find_children("*", "Label", true, false):
		if label.text == LedgerProduction.COURT_LEGEND:
			continue
		if label.text.begins_with(prefix):
			marked += 1
	return marked


## Whether a sheet prints one line of exactly this text: the legend under a
## section's heading, which nothing else on the page reads.
static func _printed(page: Node, text: String) -> bool:
	for label: Label in page.find_children("*", "Label", true, false):
		if label.text == text:
			return true
	return false
