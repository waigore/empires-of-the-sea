extends RefCounted
## Fifth step of the e2e smoke: every sheet and reading the bar can raise — the
## crown-road and defence lenses with their keys, the muster roll, the province
## ledger, the crown's towns, the crown's eyes, the command pool and the crown's
## navy — opened from the door the player uses and set aside without placing an
## order (DR-20261113-12, DR-20261115-09/10/11/12/14).
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.


static func step(run) -> void:
	var screen: MapScreen = run.screen
	await _crown_road_lens(run, screen)
	await _defence_lens(run, screen)
	await _survey_lens(run, screen)
	await _muster_roll(run, screen)
	await _province_ledger(run, screen)
	await _town_ledger(run, screen)
	await _wall_ledger(run, screen)
	await _spy_ledger(run, screen)
	await _command_ledger(run, screen)
	await _navy_ledger(run, screen)
	await _bid_budget(run, screen)


## Map readings: the crown-road lens mounts on the real map, fills its survey
## and hands the key cartouche back when it closes.
static func _crown_road_lens(run, screen: MapScreen) -> void:
	MapPlayInput.set_crown_lens(screen.play, true)
	await run.tree.process_frame
	var lens: CrownRoadLens = screen.play.crown_lens
	run.check(lens != null and lens.active, "crown road lens raises")
	run.check(screen.hud.lens_legend.visible, "crown road key shown")
	run.check(
		screen.hud.lens_legend.kind == LensLegend.KIND_CROWN_ROAD,
		"crown road key reads the lens"
	)
	var road: int = int(lens.survey.get("tiles", {}).get(CrownRoadSurvey.STATE_ROAD, 0))
	run.check(road > 0, "crown road surveyed")
	MapPlayInput.set_crown_lens(screen.play, false)
	await run.tree.process_frame
	run.check(not screen.hud.lens_legend.visible, "crown road key closes")


## The defence reading mounts on the real map: the key follows it and closes
## with it, and every charted province carries a garrison or a wall line.
static func _defence_lens(run, screen: MapScreen) -> void:
	MapPlayInput.set_defence_lens(screen.play, true)
	await run.tree.process_frame
	var lens: DefenceLens = screen.play.defence_lens
	run.check(lens != null and lens.active, "defence lens raises")
	run.check(screen.hud.lens_legend.visible, "defence key shown")
	run.check(
		screen.hud.lens_legend.kind == LensLegend.KIND_DEFENCE,
		"defence key reads the lens"
	)
	run.check(
		(lens.survey.get("provinces", []) as Array).size() > 0,
		"defence reading covers the chart"
	)
	MapPlayInput.set_defence_lens(screen.play, false)
	await run.tree.process_frame
	run.check(not screen.hud.lens_legend.visible, "defence key closes")


## The survey reading mounts on the real map: the key follows it and closes with
## it, and a plate reads its province by resource type with a built/linked/held
## badge (issue #698). No estate is raised and no Explorer is sent.
static func _survey_lens(run, screen: MapScreen) -> void:
	MapPlayInput.set_lens(screen.play, true)
	await run.tree.process_frame
	var lens: ResourceLens = screen.play.lens
	run.check(lens != null and lens.active, "survey lens raises")
	run.check(screen.hud.lens_legend.visible, "survey key shown")
	run.check(screen.hud.lens_legend.kind == LensLegend.KIND_SURVEY, "survey key reads the lens")
	var provinces: Array = lens.survey.get("provinces", [])
	run.check(not provinces.is_empty(), "the survey reading covers the chart")
	var types: Array = [] if provinces.is_empty() else (provinces[0] as Dictionary)["types"]
	run.check(not types.is_empty(), "a plate names its resource types")
	if not types.is_empty():
		run.check(
			String((types[0] as Dictionary)["badge"]).count("/") == 2,
			"a type's badge counts built, linked and held"
		)
	MapPlayInput.set_lens(screen.play, false)
	await run.tree.process_frame
	run.check(not screen.hud.lens_legend.visible, "survey key closes")


## The muster roll: the cartouche seal raises the whole-empire force ledger on
## the real map, prints the crown's own rows, narrows to one kind and sets
## itself aside (DR-20261113-12). No order is placed, so the turn is untouched.
static func _muster_roll(run, screen: MapScreen) -> void:
	run.check(screen.hud.muster_roll != null, "muster roll mounted")
	screen.hud.muster_roll_pressed.emit()
	await run.tree.process_frame
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	run.check(panel.is_open(), "muster roll opens from the seal")
	run.check(int(panel._snapshot.get("total", 0)) > 0, "the muster lists the crown's forces")
	run.check(run.has_text(panel._rows, "strength"), "a row prints its strength")
	panel._on_filter(ForceLedger.KIND_SQUADRON, false)
	await run.tree.process_frame
	run.check(panel._reading == ForceLedger.KIND_SQUADRON, "the ledger narrows to squadrons")
	var only_squadrons: bool = true
	for child: Node in panel._rows.get_children():
		var row := child as ForceLedgerRow
		if row != null and String(row.data.get("kind", "")) != ForceLedger.KIND_SQUADRON:
			only_squadrons = false
	run.check(only_squadrons, "every printed row is a squadron")
	panel.close()
	await run.tree.process_frame
	run.check(not panel.is_open(), "the muster roll sets itself aside")


## The province ledger: the dossier's Realm door raises the whole-empire
## province reading on the real map, prints the crown's own holdings, narrows to
## one reading and sets itself aside (DR-20261115-09). No order is placed.
static func _province_ledger(run, screen: MapScreen) -> void:
	run.check(screen.hud.province_ledger != null, "province ledger mounted")
	var door: Button = null
	for node: Node in screen.hud._panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Realm":
			door = button
			break
	run.check(door != null, "the province dossier carries the realm door")
	if door == null:
		return
	door.pressed.emit()
	await run.tree.process_frame
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	run.check(panel.is_open(), "province ledger opens from the realm door")
	run.check(int(panel._snapshot.get("total", 0)) > 0, "the ledger lists the crown's provinces")
	run.check(run.has_text(panel._rows, "Town"), "a row prints what the province is built to")
	panel._on_filter(ProvinceLedger.FILTER_UNGARRISONED, false)
	await run.tree.process_frame
	run.check(
		panel._reading == ProvinceLedger.FILTER_UNGARRISONED, "the ledger narrows to one reading"
	)
	panel.close()
	await run.tree.process_frame
	run.check(not panel.is_open(), "the province ledger sets itself aside")


## The towns ledger: the realm ledger's Towns door raises the crown's towns on
## the real map, prints the step a town waits on, narrows to one reading and
## sets itself aside (DR-20261115-12). No Builder is sent, so no order is placed.
static func _town_ledger(run, screen: MapScreen) -> void:
	run.check(screen.hud.towns_ledger != null, "towns ledger mounted")
	screen.hud.provinces_pressed.emit()
	await run.tree.process_frame
	var door: Button = null
	for node: Node in screen.hud.province_ledger.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Towns ›":
			door = button
			break
	run.check(door != null, "the realm ledger carries the towns door")
	if door == null:
		return
	door.pressed.emit()
	await run.tree.process_frame
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	run.check(panel.is_open(), "the towns ledger opens from the realm's door")
	run.check(int(panel._snapshot.get("total", 0)) > 0, "the ledger lists the crown's towns")
	run.check(
		run.has_text(panel._rows, "READY")
		or run.has_text(panel._rows, "AT WORK")
		or run.has_text(panel._rows, "NO BUILDER")
		or run.has_text(panel._rows, "LOCKED")
		or run.has_text(panel._rows, "DEVELOPED"),
		"a row names what its town waits on"
	)
	panel._on_filter(TownLedger.FILTER_READY, false)
	await run.tree.process_frame
	run.check(panel._reading == TownLedger.FILTER_READY, "the ledger narrows to one reading")
	panel.close()
	await run.tree.process_frame
	run.check(not panel.is_open(), "the towns ledger sets itself aside")


## The walls ledger: the realm ledger's Walls door raises the crown's walls on
## the real map and sets itself aside (DR-20261116-01). No Engineer is sent.
static func _wall_ledger(run, screen: MapScreen) -> void:
	run.check(screen.hud.walls_ledger != null, "walls ledger mounted")
	screen.hud.provinces_pressed.emit()
	await run.tree.process_frame
	var door: Button = null
	for node: Node in screen.hud.province_ledger.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Walls ›":
			door = button
			break
	run.check(door != null, "the realm ledger carries the walls door")
	if door == null:
		return
	door.pressed.emit()
	await run.tree.process_frame
	var panel: WallLedgerPanel = screen.hud.walls_ledger
	run.check(panel.is_open(), "the walls ledger opens from the realm's door")
	run.check(int(panel._snapshot.get("total", 0)) > 0, "the ledger lists the crown's walls")
	run.check(run.has_text(panel._rows, "Fort") or run.has_text(panel._rows, "wall"),
		"a row reads the wall that stands or the one next")
	panel.close()
	await run.tree.process_frame
	run.check(not panel.is_open(), "the walls ledger sets itself aside")


## The crown's eyes: the court ledger's EYES door raises the intelligence
## reading on the real map, prints the courts it shadows and sets itself aside
## (DR-20261115-10). No spy is moved and no order is placed.
static func _spy_ledger(run, screen: MapScreen) -> void:
	run.check(screen.hud.spy_ledger != null, "the crown's eyes mounted")
	screen.hud.diplomacy_pressed.emit()
	await run.tree.process_frame
	var door: Button = null
	for node: Node in screen.hud._diplomacy_panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text.begins_with("EYES"):
			door = button
			break
	run.check(door != null, "the court ledger carries the eyes door")
	if door == null:
		return
	door.pressed.emit()
	await run.tree.process_frame
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	run.check(panel.is_open(), "the crown's eyes open from the court's door")
	run.check(run.has_text(panel._rows, "THE COURTS"), "the sheet prints the courts it reads")
	run.check(run.has_text(panel._rows, "THE SCREEN"), "and whether the screen is up")
	panel.close()
	await run.tree.process_frame
	run.check(not panel.is_open(), "the crown's eyes set themselves aside")


## The command ledger: the army dossier's Commanders door raises the crown's
## pool on the real map, prints the cap road and the medal note, and sets itself
## aside (DR-20261115-11). No commander is appointed and no order is placed.
static func _command_ledger(run, screen: MapScreen) -> void:
	run.check(screen.hud.command_ledger != null, "command ledger mounted")
	var door: Button = null
	for node: Node in screen.hud._army_panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Commanders":
			door = button
			break
	run.check(door != null, "the army dossier carries the command door")
	if door == null:
		return
	door.pressed.emit()
	await run.tree.process_frame
	var panel: CommandLedgerPanel = screen.hud.command_ledger
	run.check(panel.is_open(), "the command ledger opens from the dossier's door")
	run.check(run.has_text(panel._road, "Cap 2"), "the sheet prints the road to the next commander")
	run.check(run.has_text(panel._medal, "Each medal"), "and what a medal buys in the field")
	panel.close()
	await run.tree.process_frame
	run.check(not panel.is_open(), "the command ledger sets itself aside")


## The crown's navy: the muster roll's navy door raises the hull-by-hull reading
## on the real map, prints a squadron heading with her hulls and sets itself
## aside (DR-20261115-14). No hull is launched, docked or ordered.
static func _navy_ledger(run, screen: MapScreen) -> void:
	run.check(screen.hud.navy_ledger != null, "navy ledger mounted")
	screen.hud.muster_roll_pressed.emit()
	await run.tree.process_frame
	var door: Button = null
	for node: Node in screen.hud.muster_roll.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text.begins_with("The crown's navy"):
			door = button
			break
	run.check(door != null, "the muster roll carries the navy door")
	if door == null:
		return
	door.pressed.emit()
	await run.tree.process_frame
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	run.check(panel.is_open(), "the navy ledger opens from the roll's door")
	if int(panel._snapshot.get("total", 0)) > 0:
		run.check(run.has_text(panel._rows, "SQUADRON — "), "a heading names the squadron")
		run.check(run.has_text(panel._rows, "strength"), "a heading prints her strength")
	else:
		run.check(run.has_text(panel._rows, "hull"), "an empty navy names the yard")
	panel.close()
	await run.tree.process_frame
	run.check(not panel.is_open(), "the navy ledger sets itself aside")
	screen.hud.muster_roll.close()
	await run.tree.process_frame
	run.check(not screen.hud.muster_roll.is_open(), "the muster roll sets itself aside again")


## The ledger's market tab prints the purse the auction may spend before a bid
## is staged (wiki: world-market § Treasury budget for bids; DR-20261115-13).
static func _bid_budget(run, screen: MapScreen) -> void:
	screen.hud.economy_pressed.emit()
	await run.tree.process_frame
	var panel: EconomyPanel = screen.hud._economy_panel
	if panel == null:
		run.check(false, "the ledger opens from the purse")
		return
	panel.select_tab(1)
	await run.tree.process_frame
	run.check(panel._market_page != null, "the market tab mounts")
	run.check(run.has_text(panel._market_page, "BIDS"), "the budget line prints")
	screen.hud.panels.hide_economy()
