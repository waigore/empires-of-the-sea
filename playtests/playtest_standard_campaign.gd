extends SceneTree
## Headless free-playtest drive: a whole standard campaign played turn by turn
## through the crown's own seat (Auto) so the late game is reachable in one
## session. Prints what a player reads at each close (the cartouche's plaques,
## the court's news, the ledger's promise) beside what the rules paid, and
## checks the wiki's standing invariants after every turn, so a curve that stops
## moving, a purse that stops paying or a court that stops acting names itself.
##
##   godot --headless --path . --script res://playtests/playtest_standard_campaign.gd
##   godot --headless --path . --script res://playtests/playtest_standard_campaign.gd -- --turns=40 --seed=1500
##
## Options: --turns=N (default 100), --seed=TEXT (default 1500), --size=0|1|2
## (default 1 = Standard, the setup screen's middle preset), --faction=ID
## (default the setup's own player slot), --audit-every=N (default 10; 0 = off),
## --advanced=ID (default none: the ordinary turn-0 campaign), --auto=0 (keep the
## crown's seat and close every turn from its own seal, so the household plays
## alone — slower, and the seat commissions nothing either way).
##
## The run stops at the turn cap or the moment the campaign is decided, and says
## which: a decided age is a reading, not a stall.
##
## Not a CI gate: a hundred Standard turns take several minutes.

const Launch = preload("res://playtests/playtest_launch.gd")
const MAX_DRAIN_TICKS: int = 90

var _turns: int = 100
var _seed_text: String = "1500"
var _size: int = 1
var _faction: int = -1
var _audit_every: int = 10
var _advanced: String = AdvancedStart.NONE
var _auto: bool = true

var _play: PlaySession = null
var _violations: Array[String] = []
var _notes: Array[String] = []
var _last_income: int = 0
var _purse_before: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--turns="):
			_turns = int(arg.trim_prefix("--turns="))
		elif arg.begins_with("--seed="):
			_seed_text = arg.trim_prefix("--seed=")
		elif arg.begins_with("--size="):
			_size = int(arg.trim_prefix("--size="))
		elif arg.begins_with("--faction="):
			_faction = int(arg.trim_prefix("--faction="))
		elif arg.begins_with("--audit-every="):
			_audit_every = int(arg.trim_prefix("--audit-every="))
		elif arg.begins_with("--advanced="):
			_advanced = AdvancedStart.normalize(arg.trim_prefix("--advanced="))
		elif arg.begins_with("--auto="):
			_auto = arg.trim_prefix("--auto=") != "0"
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = await Launch.open_map(self, _seed_text, _size, _advanced, _faction)
	if screen == null:
		_say("the launch flow did not reach the map screen")
		quit(1)
		return
	_play = screen.play
	_say("--- opening ---")
	_say("seed %s · %s chart · %s · turn %d (%d) · %d provinces" % [
		_seed_text, String(GameConfig.SIZES[_size]["label"]),
		FactionCatalog.name_of(_play.player_faction), _play.turn,
		TurnTime.year_for_turn(_play.turn), _play.model.province_count(),
	])
	_say("capital %s at %s" % [
		_play.model.province_name(_play.capital_province), str(_play.capital_tile),
	])
	_read_bar("turn 1, before anything is pressed")
	_purse_before = _play.treasury()
	await _audit("turn 1 (start)")
	# One turn closed by the court's own seal: the boundary Auto arms at.
	_close_turn()
	_report_turn("turn 1 closed by the crown")
	if _auto:
		MapPlayAuto.arm(_play)
		_close_turn()
		_say("seat handed to Auto: active=%s at turn %d" % [_play.auto_active, _play.turn])
	while not _play.campaign_over() and _play.turn <= _turns:
		var before: int = _play.turn
		if _auto:
			_drain()
		else:
			_close_turn()
		await process_frame
		if _play.turn == before:
			if _play.campaign_over():
				_say("the campaign closed on turn %d — the calendar stops there" % _play.turn)
			else:
				_note("turn %d did not advance — a decision held the calendar" % before)
			break
		_report_turn("")
		if _audit_every > 0 and _play.turn % _audit_every == 0 and not _play.campaign_over():
			await _audit("turn %d" % _play.turn)
	_say("")
	_say("--- closing at turn %d (%d) ---" % [_play.turn, TurnTime.year_for_turn(_play.turn)])
	_say("campaign over: %s · victory %s · defeat %s · halted %s" % [
		_play.campaign_over(), _play.victory != null, _play.defeat != null,
		_play.campaign_halted,
	])
	_read_bar("at the close")
	_read_standing()
	_finish()


# --- the drive --------------------------------------------------------------


## One turn from the crown's seat: press the turn, answer whatever consent the
## court leaves waiting, let it resolve (the boundary Auto changes hands at).
func _close_turn() -> void:
	var start: int = _play.turn
	MapPlayTurn.end_turn(_play)
	var guard: int = 0
	while _play.turn_suspended and guard < 8:
		guard += 1
		match ConsentLadder.pending_kind(_play.diplomacy, _play.player_faction):
			ConsentLadder.CALL:
				MapPlayTurn.answer_call(_play, false)
			ConsentLadder.INTERVENTION:
				MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
			ConsentLadder.OFFER:
				MapPlayTurn.answer_offer(_play, false)
			_:
				_play.turn_suspended = false
	if _play.turn == start and not _play.campaign_over():
		_note("turn %d would not close from the crown's own seal" % start)


## Spends the Auto driver's ticks until the turn in flight closes.
func _drain() -> void:
	var guard: int = 0
	MapPlayAuto.tick(_play)
	while _play.auto_book != null and guard < MAX_DRAIN_TICKS:
		MapPlayAuto.tick(_play)
		guard += 1
	if guard >= MAX_DRAIN_TICKS:
		_note("turn %d: the Auto driver spent %d ticks without closing" % [
			_play.turn, MAX_DRAIN_TICKS,
		])


# --- what the player reads --------------------------------------------------


## The cartouche's plaques and the news the court has not been told yet.
func _read_bar(label: String) -> void:
	var stats: HudStatChips = _play.hud.stats
	var treasury_text: String = "?"
	var income_text: String = "?"
	var fleet_text: String = "?"
	var civilian_text: String = "?"
	var army_text: String = "?"
	if stats != null:
		if stats.treasury_label != null:
			treasury_text = stats.treasury_label.text
		if stats.income_label != null:
			income_text = stats.income_label.text
		if stats.fleet_label != null:
			fleet_text = stats.fleet_label.text
		if stats.civilian_label != null:
			civilian_text = stats.civilian_label.text
		if stats.army_label != null:
			army_text = stats.army_label.text
	_say("bar %s: purse %s (%s/turn) · ships %s · civilians %s · troops %s" % [
		label, treasury_text, income_text, fleet_text, civilian_text, army_text,
	])
	var waiting: PackedStringArray = PackedStringArray()
	if _play.hud.despatches != null:
		waiting = _play.hud.despatches.waiting()
	if not waiting.is_empty():
		for line: String in waiting:
			_say("  undelivered news: " + line)


## One turn's numbers as the rules paid them beside what the bar promised.
func _report_turn(label: String) -> void:
	var treasury: int = _play.treasury()
	var delta: int = treasury - _purse_before
	_purse_before = treasury
	var line: String = (
		"turn %3d (%d) · %7d ducats (%+d, bar said %+d) · %2d regs · %2d hulls"
		+ " · %2d civs · %2d/%2d provinces"
	) % [
		_play.turn, TurnTime.year_for_turn(_play.turn), treasury, delta, _last_income,
		_play.army_layer.regiment_count_all(_play.player_faction),
		_play.ship_layer.hull_count_all(_play.player_faction),
		_play.civilian_layer.unit_count_all(_play.player_faction),
		_owned(0), _owned(1),
	]
	if not label.is_empty():
		line += " · " + label
	_say(line)
	var logs: Array[String] = _play.auto_log.duplicate()
	for entry: String in logs:
		_say("    " + entry)
	_play.auto_log.clear()
	var stats: HudStatChips = _play.hud.stats
	if stats != null and stats.income_label != null:
		_last_income = _int_of(stats.income_label.text)
	_check_invariants()
	if not _play.campaign_over() and _play.hud.plates != null:
		var plates: int = _play.hud.plates.land_queue.size() + _play.hud.plates.sea_queue.size()
		if plates > 0:
			_say("    %d battle plate(s) still waiting" % plates)


## The courts the campaign is actually between: every Great Power's holdings and
## its land after the close, so a crown that stopped conquering reads.
func _read_standing() -> void:
	var orders: Dictionary = MapPlayCourtHoldings.public_orders(_play)
	var strength: Dictionary = orders.get("strength", {}) as Dictionary
	var ships: Dictionary = orders.get("ships", {}) as Dictionary
	for faction: int in FactionCatalog.great_power_ids():
		_say("  %-10s %2d provinces · %2d hulls · strength %6.1f" % [
			FactionCatalog.name_of(faction), _owned_by(faction),
			int(ships.get(faction, 0)), float(strength.get(faction, 0.0)),
		])


func _int_of(text: String) -> int:
	var cleaned: String = text.replace(",", "").replace("+", "").replace("−", "-")
	return int(cleaned.strip_edges())


func _owned(region: int) -> int:
	if region >= _play.world.region_count():
		return 0
	return _play.world.owned_provinces(region, _play.player_faction)


## Holdings across both charts: the campaign's own measure of a crown's reach.
func _owned_by(faction: int) -> int:
	var total: int = 0
	for region in _play.world.region_count():
		total += _play.world.owned_provinces(region, faction)
	return total


# --- the panels a player opens ----------------------------------------------


## Opens every whole-empire sheet and the province sheet once, printing what is
## on screen, so a panel that reads nothing — or reads a number the rules do not
## hold — names itself.
func _audit(label: String) -> void:
	_say("")
	_say("--- panel audit: %s ---" % label)
	var capital: int = _play.capital_province
	if capital != MapModel.NO_ID and _play.model.province_data(capital) != null:
		var data: ProvinceState = _play.model.province_data(capital)
		MapPlayInput.select_province(
			_play, capital, MapGeo.tile_center(data.center.x, data.center.y, PlaySession.TILE_SIZE)
		)
		await process_frame
		_dump_visible(
			"capital sheet (%s)" % _play.model.province_name(capital),
			_play.hud.panels.panel, 40
		)
		_play.hud.panels.hide_province()
		await process_frame
	for key: String in [
		HudLedgerDoors.CIVILIANS, HudLedgerDoors.MUSTER, HudLedgerDoors.PROVINCES,
		HudLedgerDoors.EYES, HudLedgerDoors.COLONIES, HudLedgerDoors.COMMAND,
		HudLedgerDoors.NAVY, HudLedgerDoors.ARMY,
	]:
		await _audit_sheet(key)
	_play.economy.open_panel()
	await process_frame
	_dump_visible("ledger", _play.hud.panels.economy_panel, 40)
	_play.hud.panels.hide_economy()
	await process_frame
	_play.economy.open_research()
	await process_frame
	_dump_visible("college", _play.hud.panels.research_panel, 30)
	_play.hud.panels.hide_research()
	await process_frame
	MapPlayDiplomacy.open(_play)
	await process_frame
	_dump_visible("court", _play.hud.panels.diplomacy_panel, 30)
	_play.hud.panels.close_sheets()
	await process_frame


func _audit_sheet(key: String) -> void:
	HudLedgerDoors.open(_play.hud, key)
	await process_frame
	_dump_visible(key + " ledger", _play.hud.ledger_doors.sheet(key), 40)
	HudLedgerDoors.dismiss_open(_play.hud)
	await process_frame


## Every line inside `root` that the player can actually see, deduplicated.
func _dump_visible(label: String, root: Node, cap: int) -> void:
	var lines: PackedStringArray = PackedStringArray()
	_collect(root, lines)
	var printed: int = 0
	for line: String in lines:
		if printed >= cap:
			break
		_say("    [%s] %s" % [label, line])
		printed += 1
	if printed == 0:
		_say("    [%s] NOTHING ON SCREEN" % label)


func _collect(node: Node, out: PackedStringArray) -> void:
	if node is Control and not (node as Control).is_visible_in_tree():
		return
	if node is Label:
		var text: String = (node as Label).text.strip_edges()
		if not text.is_empty():
			out.append(text)
	elif node is Button:
		var caption: String = (node as Button).text.strip_edges()
		if not caption.is_empty():
			out.append("[btn] " + caption)
	for child in node.get_children():
		_collect(child, out)


# --- the wiki's standing invariants -----------------------------------------


func _check_invariants() -> void:
	_check_armies()
	_check_fleets()
	_check_prices()


## military-armies § Definition / § Home Army: one army per regiment, one
## province per army, one Home Army at each seat.
func _check_armies() -> void:
	var seen: Dictionary = {}
	var homes: Dictionary = {}
	for region in _play.world.region_count():
		var model: MapModel = _play.world.region(region)
		if model == null:
			continue
		var roster: Array = _play.army_layer.regions.value(region, [])
		for raw: Variant in roster:
			var army: ArmyState = raw as ArmyState
			if army == null:
				continue
			for regiment_id: String in army.regiments:
				if seen.has(regiment_id):
					_violation("turn %d: regiment %s stands in two armies" % [_play.turn, regiment_id])
				seen[regiment_id] = true
			if not army.is_embarked():
				if army.province == MapModel.NO_ID or model.province_data(army.province) == null:
					_violation("turn %d: army %d of %s holds no province" % [
						_play.turn, army.id, FactionCatalog.name_of(army.owner),
					])
				if army.home:
					homes[army.owner] = int(homes.get(army.owner, 0)) + 1
					var capital: int = _play.world.capital_province_of(region, army.owner)
					if capital != MapModel.NO_ID and army.province != capital:
						_violation("turn %d: Home Army of %s stands at %s, not its seat %s" % [
							_play.turn, FactionCatalog.name_of(army.owner),
							model.province_name(army.province), model.province_name(capital),
						])
	for faction: int in FactionCatalog.great_power_ids():
		if int(homes.get(faction, 0)) > 1:
			_violation("turn %d: %s keeps %d Home Armies" % [
				_play.turn, FactionCatalog.name_of(faction), int(homes[faction]),
			])


## ships-and-naval § Fleet location / § Ship instances: a fleet in port sits on
## its owner's ground and no hull lives in two fleets.
func _check_fleets() -> void:
	var seen: Dictionary = {}
	for region in _play.world.region_count():
		var model: MapModel = _play.world.region(region)
		if model == null:
			continue
		var fleets: Array[FleetState] = []
		fleets.assign(_play.ship_layer.regions.value(region, []))
		for fleet: FleetState in fleets:
			if fleet == null:
				continue
			for hull_id: String in fleet.hulls:
				if seen.has(hull_id):
					_violation("turn %d: hull %s stands in two fleets" % [_play.turn, hull_id])
				seen[hull_id] = true
			if not fleet.is_in_port():
				continue
			var data: ProvinceState = model.province_data(fleet.province)
			if data == null:
				_violation("turn %d: fleet %d is in port at no province" % [_play.turn, fleet.id])
			elif data.owner != fleet.owner:
				_violation("turn %d: fleet %d (%s) lies in port at %s, %s's ground" % [
					_play.turn, fleet.id, FactionCatalog.name_of(fleet.owner),
					model.province_name(fleet.province), FactionCatalog.name_of(data.owner),
				])


## world-market § Price discovery: no price clears under 30% of its default.
func _check_prices() -> void:
	var market: WorldMarket = _play.economy.market
	if market == null:
		return
	for commodity: String in market.prices.keys():
		var price: int = int(market.prices[commodity])
		var base: int = CommodityCatalog.base_price(commodity)
		if base <= 0:
			continue
		if price < int(floor(float(base) * 0.3)):
			_violation("turn %d: %s clears at %d, under its floor" % [_play.turn, commodity, price])


# --- report -----------------------------------------------------------------


func _violation(line: String) -> void:
	if _violations.has(line):
		return
	_violations.append(line)
	print("VIOLATION ", line)


func _note(line: String) -> void:
	if _notes.has(line):
		return
	_notes.append(line)
	print("NOTE ", line)


func _say(line: String) -> void:
	print("playtest: ", line)


func _finish() -> void:
	_say("")
	_say("--- %d violation(s), %d note(s) ---" % [_violations.size(), _notes.size()])
	for line: String in _violations:
		_say("  VIOLATION " + line)
	for line: String in _notes:
		_say("  NOTE " + line)
	quit(0)
