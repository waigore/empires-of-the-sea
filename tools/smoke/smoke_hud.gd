extends RefCounted
## Fourth step of the e2e smoke: the bar's doors and the courts — the estates
## seal, the court ledger's war and peace orders, the sound desk's mute, and one
## tap on an inland province that must stick (REQ-P5-01, REQ-P5-07). The director
## and its cue count stay on the run for the end-of-turn read.
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
	await _court(run, screen)
	_audio(run, screen)
	await _province(run, screen)
	await _production(run, screen)
	await _market(run, screen)


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
	var ready: int = screen.improvements._ready_tiles().size()
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
	navy.close()


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
	army.close()


## THE CROWN'S MUSTER names the orders the court's own staff would give every
## force this turn — both the army's standards and the navy's squadrons in one
## gold line under the chips — and moves nothing (wiki: military-armies § The
## muster roll; DR-20261121-17).
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


## The court ledger: seeded relations, a declaration, a peace, and the court's
## own voice and intelligence reading (wiki: diplomacy).
static func _court(run, screen: MapScreen) -> void:
	MapPlayDiplomacy.open(screen.play)
	await run.tree.process_frame
	run.check(screen.play.diplomacy != null, "diplomacy state seeded")
	run.check(
		screen.play.diplomacy.relations.size() >= 81,
		"same-region relations seeded"
	)
	run.check(screen.hud.panels.is_diplomacy_open(), "court ledger opens")
	MapPlayDiplomacy.on_order(screen.play, DiplomacyOrders.KIND_WAR, 1, "")
	run.check(screen.play.diplomacy.relation(0, 1).at_war, "war order applies")
	screen.hud.panels.diplomacy_panel.select_faction(1)
	# The court's own envoy: the one order her staff's planner would spend this
	# turn, printed above the presses it answers (DR-20261121-05).
	var counsel: String = screen.hud.panels.diplomacy_panel.counsel_text()
	run.check(not counsel.is_empty(), "the court names the order its envoy would spend")
	run.check(
		run.has_text(screen.hud.panels.diplomacy_panel._detail, counsel),
		"the envoy's counsel is on the court's sheet"
	)
	run.check(
		run.has_text(screen.hud.panels.diplomacy_panel._detail, "THEIR ENVOY"),
		"the court answers a declaration in its own voice"
	)
	run.check(
		run.has_text(screen.hud.panels.diplomacy_panel._detail, "DOSSIER"),
		"the court carries its intelligence reading"
	)
	run.check(
		run.has_text(screen.hud.panels.diplomacy_panel._detail, "Holds "),
		"the dossier counts the court's public behaviour"
	)
	MapPlayDiplomacy.on_order(screen.play, DiplomacyOrders.KIND_PEACE, 1, "")
	run.check(not screen.play.diplomacy.relation(0, 1).at_war, "peace order applies")
	DiplomacyHud.hide(screen.hud.panels)
	run.check(not screen.hud.panels.is_diplomacy_open(), "court ledger closes")


## The sound desk: one opening bed, sea ambience, a counted cue, and a mute that
## silences the music (REQ-P1-06).
static func _audio(run, screen: MapScreen) -> void:
	run.audio = run.main.get_node_or_null("Audio") as AudioDirector
	var controls: SoundDesk = screen.game_menu.sound_desk
	run.check(run.audio != null, "audio director present")
	run.check(controls != null, "sound desk in the pause menu")
	if run.audio == null:
		return
	# The drive is a wall-clock gate, so every fade it asks for lands at once:
	# a bed nobody waits out buys frames, not quieter rules (docs/testing.md
	# § Speed rules). The knobs the asserts read below are the live ones.
	run.audio.fade_scale = 0.0
	run.check(
		run.audio.current_track_id() == MusicPlaylist.AGE_OF_DISCOVERY, "opening bed playing"
	)
	run.check(run.audio._ambience.playing, "sea ambience playing")
	run.cues_before = run.audio.sfx_played
	run.check(run.audio.play_event(AudioEvents.UI_CLICK), "ui cue fires")
	run.check(run.audio.sfx_played == run.cues_before + 1, "ui cue counted")
	run.audio.set_muted(true)
	run.check(
		run.audio._active_player().volume_db == AudioDirector.SILENT_DB, "mute silences music"
	)
	run.audio.set_muted(false)
	# A driven run ends its fades on the frame it asks for them (fade_scale 0),
	# so nothing keeps resolving after the asserts above — a killed frame would
	# leave the next step's boot or the exit waiting on it (docs/testing.md
	# § Speed rules).
	run.audio.land_fades()


## One tap on an inland province: the selection sticks and its dossier opens.
static func _province(run, screen: MapScreen) -> void:
	var province_id: int = SmokeFind.inland_province(screen)
	run.check(province_id >= 0, "inland province available")
	if province_id < 0:
		return
	var world: Vector2 = screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	MapPlayInput.on_tapped(screen.play, world)
	await run.tree.process_frame
	run.check(screen.selected_province == province_id, "province selection sticks")
	run.check(screen.hud.panels.is_panel_open(), "province panel opens")
	# The capital's rail carries the court's own hire pick: the crew the published
	# hire order takes next, or the gate that holds it (wiki: civilian-units
	# § Training; DR-20261121-06). Any other province hires nobody and says so.
	MapPlayInput.select_province(
		screen.play, screen.capital_province,
		screen.model.province_center(screen.capital_province) * MapScreen.TILE_SIZE
	)
	await run.tree.process_frame
	run.check(
		not screen.hud.panels.panel.hire_line_text().is_empty(),
		"the capital rail names the hire the court takes"
	)
	run.check(
		screen.play.economy.economy.recruits.is_empty(),
		"the hire reading queues nothing"
	)
	# The dossier also names the orders the court would give on this province's
	# ground: the work its civilian pass would put crews to here and the hosts
	# its land pass would send here, or nothing (wiki: world-model § The crown's
	# provinces; DR-20261121-19).
	run.check(
		screen.hud.panels.panel.counsel_source.is_valid(),
		"the province sheet binds the court's reading"
	)
	var counsel: String = screen.hud.panels.panel.counsel_text()
	run.check(
		counsel.is_empty()
		or counsel.begins_with("The court would order ")
		or counsel == MapPlayPickProse.sentence(MapPlayProvinceCounsel.NO_WORK_LINE),
		"the province sheet names the orders the court would give here"
	)
	run.check(
		screen.play.economy.economy.recruits.is_empty(),
		"the province reading queues nothing"
	)
	# The realm names the provinces the court would act in this turn, and every
	# such row leads with the counsel's mark (wiki: world-model § The crown's
	# provinces; DR-20261121-21).
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


## How many realm rows wear the counsel's mark: the ground the court would act
## in, as the sheet prints it.
static func _marked_rows(panel: ProvinceLedgerPanel) -> int:
	var marked: int = 0
	for child: Node in panel._rows.get_children():
		var row := child as ProvinceLedgerRow
		if row != null and row.court:
			marked += 1
	return marked


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
	run.check(
		screen.economy.economy.production.assignments().size() == set_before,
		"the plan reading sets nothing"
	)
	screen.hud.panels.hide_economy()


## The ledger's MARKET tab names the trade the crown's own market pass would
## book this phase, in the tab's gold line above the orders it answers — and
## stages nothing (wiki: world-market § Trade orders; DR-20261121-09).
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
	run.check(
		screen.economy.market.book.orders_for(screen.player_faction).size()
		== orders_before,
		"the trade reading stages nothing"
	)
	screen.hud.panels.hide_economy()
