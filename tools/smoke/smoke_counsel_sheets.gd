extends RefCounted
## The bar's sheets in the counsel step: the people, the navy, the army, the
## muster, the colonies and the realm — each opened from the door the player
## uses, printing one gold line and marking the rows it answers, and ordering
## nothing (DR-20261121-12/13/14/17/21, DR-20261122-03).
##
## The court ledger's own envoy and the sound desk stay in the HUD step. The
## estates card and the ledger's tabs (smoke_counsel_ledger.gd), the three yards
## (smoke_counsel_yards.gd) and one shared tally (smoke_counsel_reads.gd) make
## the rest of the step.
##
## No `class_name`: the counsel step (tools/smoke/smoke_counsel.gd) preloads
## this file.

const SmokeReads = preload("res://tools/smoke/smoke_counsel_reads.gd")


static func step(run, screen: MapScreen) -> void:
	await _people(run, screen)
	await _navy(run, screen)
	await _army(run, screen)
	await _muster(run, screen)
	await _colonies(run, screen)
	await _realm(run, screen)


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


## THE CROWN'S PEOPLE names the work the court's own civilian pass would put its
## crews to this turn, in one gold line under its filters — and orders nothing
## (wiki: civilian-units § Empire roster; DR-20261121-12).
static func _people(run, screen: MapScreen) -> void:
	var working_before: int = SmokeReads.working_crews(screen)
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
		SmokeReads.marked_crews(roster) == keys.size() and named == keys.size(),
		"every crew the court would spend wears the mark"
	)
	run.check(SmokeReads.working_crews(screen) == working_before, "the reading orders nothing")
	roster.close()


## THE CROWN'S NAVY names the sails the court's own naval pass would order its
## squadrons this turn, in one gold line above the hulls it answers — and orders
## nothing (wiki: ships-and-naval § The crown's navy; DR-20261121-13).
static func _navy(run, screen: MapScreen) -> void:
	var before: Array = SmokeReads.fleet_orders(screen)
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
	run.check(SmokeReads.fleet_orders(screen) == before, "the navy's reading orders nothing")
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
		SmokeReads.marked_headings(navy._rows) == named,
		"the navy's marks are painted on the headings they answer"
	)
	# The sentence that says what the mark means rides with the mark, on the
	# sheet rather than in the footer a phone drops (DR-20261123-03).
	run.check(
		navy.legend_shown() == not keys.is_empty(),
		"the navy's legend stands with the marks it explains"
	)
	navy.close()


## THE CROWN'S ARMY names the orders the court's own staff would give its
## standards this turn, in one gold line above the regiments it answers — and
## marches nothing (wiki: military-armies § The crown's army; DR-20261121-14).
static func _army(run, screen: MapScreen) -> void:
	var before: Array = SmokeReads.army_orders(screen)
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
	run.check(SmokeReads.army_orders(screen) == before, "the army's reading orders nothing")
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
		SmokeReads.marked_headings(army._rows) == named,
		"the army's marks are painted on the headings they answer"
	)
	# The legend says what `▸` means, beside the mark, on every screen
	# (DR-20261123-03).
	run.check(
		army.legend_shown() == not keys.is_empty(),
		"the army's legend stands with the marks it explains"
	)
	army.close()


## THE CROWN'S MUSTER names the orders the court's own staff would give every
## force this turn — both the army's standards and the navy's squadrons in one
## gold line under the chips — and every force the line answers leads with the
## counsel's mark (wiki: military-armies § The muster roll; DR-20261121-17,
## DR-20261122-03).
static func _muster(run, screen: MapScreen) -> void:
	var before: Array = SmokeReads.army_orders(screen)
	before.append_array(SmokeReads.fleet_orders(screen))
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
		SmokeReads.marked_forces(muster) == (muster_pick.get("keys", {}) as Dictionary).size(),
		"every force the court would send wears the mark"
	)
	var after: Array = SmokeReads.army_orders(screen)
	after.append_array(SmokeReads.fleet_orders(screen))
	run.check(after == before, "the muster's reading orders nothing")
	muster.close()


## THE COLONIES names the Tribe the court's own envoy is drawing into the empire
## this turn, in one gold line above the roll — and signs no overture
## (wiki: diplomacy § GP–Tribe Rules; DR-20261121-16).
static func _colonies(run, screen: MapScreen) -> void:
	var before: Array = SmokeReads.colony_overtures(screen)
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
	# The door the line's own court answers (DR-20261123-05): a reading that names
	# a court stands the press; a footing that shuts new chains stands none.
	var door: Button = colonies.follow_press()
	var door_court: int = MapPlayColonyPick.door(MapPlayColonyPick.pick(screen.play))
	run.check(
		door != null and door.visible == (door_court >= 0),
		"the colonies' door follows its line"
	)
	run.check(
		door_court < 0 or colonies.door_court() == door_court,
		"the door names the court its line names"
	)
	run.check(
		SmokeReads.colony_overtures(screen) == before,
		"the colonies' reading signs nothing"
	)
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
		SmokeReads.marked_rows(realm)
		== (realm_pick.get("keys", {}) as Dictionary).size(),
		"every province the court would act in wears the mark"
	)
	realm.close()
