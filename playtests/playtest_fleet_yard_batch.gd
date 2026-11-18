extends SceneTree
## Headless free-playtest drive for the shipyard's one press (wiki:
## ships-and-naval § Ship muster and the breaker's yard; DR-20261118-08;
## DR-20261118-07 for the drill yard's sibling).
##
##   godot --headless --path . --script res://playtests/playtest_fleet_yard_batch.gd
##
## The press is a two-tap arm over an order the crown cannot take back, so the
## drive reads it the way a player meets it: the face before the first tap, the
## face between the taps, the receipt, and — the part no rule test covers — what
## the slip still prints **after** the press has spent the line. The slip with no
## squadron afloat is its own state (the first launch founds the home fleet), so
## the drive sits a crown in it by breaking up every hull she keeps in port, as a
## player does with the drawer's own break-up intent.
##
## Not a CI gate. A failure prints "FAIL: …" and the run exits non-zero.
## Every finding fails the drive instead of printing a number nobody compares.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
## England: a Great Power that is not FactionCatalog.PLAYER_FACTION, so a panel
## that reads a defaulted crown instead of the session's own is visible here.
const NATION: int = 1

var _steps: PackedStringArray = PackedStringArray()
var _failures: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0, "", NATION)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("%s (faction %d), seed %s, turn %d, purse %d, peasants %d" % [
		FactionCatalog.name_of(_play.player_faction), _play.player_faction, SEED_TEXT,
		_play.turn, _purse(), _peasants(),
	])
	_opening_read()
	_arm_and_file()
	_seat_a_mid_game_purse()
	await _arm_across_a_refresh()
	await _drill_yard_pass()
	await _empty_slip_pass()
	_finish()


## The opening purse cannot arm a second line (one press of the opening slip
## spends 19,500 of 20,000), so the later passes read a ledger a mid-game crown
## holds — the state these taps are actually taken in.
func _seat_a_mid_game_purse() -> void:
	_play.economy.economy.treasury = 60000
	_play.economy.economy.workers.set_count(WorkerPool.Tier.PEASANT, 12)
	_say("")
	_say("ledger seated at %d ducats and %d peasants for the mid-game passes" % [
		_purse(), _peasants(),
	])


# --- the opening read --------------------------------------------------------


## The yard as a player opens it: the capital's own slip, its rows, and the face
## of the press before anything is spent.
func _opening_read() -> void:
	_say("")
	_say("--- the capital yard as it opens ---")
	var capital: int = _play.capital_province
	_say("capital %d %s, harbour %s, home fleet %s" % [
		capital, _play.model.province_name(capital),
		str(NavalMovement.has_harbour(_play.model, capital)),
		str(_home() != null),
	])
	_check(NavalMovement.has_harbour(_play.model, capital), "the crown's capital has a yard to open")
	MapPlayFleetYard.open(_play)
	var yard: FleetYardBlock = _yard_block()
	_check(yard != null, "the shipyard drawer opened")
	if yard == null:
		return
	var press: RaiseBatchPress = yard._batch
	_check(press != null, "the slip carries the one press")
	_check(press.visible, "the press stands while the slip has ready hulls")
	var ready: int = _ready_rows(yard)
	_check(ready > 0, "the opening slip prints at least one payable hull")
	_check(press.text == "Launch all ready (%d)" % ready, "the face names the count: %s" % press.text)
	_say("rows %d, ready %d, face \"%s\"" % [yard._rows.size(), ready, press.text])


# --- the two taps ------------------------------------------------------------


## The arm, the receipt and what the slip reads afterwards — with a squadron
## still afloat, where the panel is redrawn from the ledger.
func _arm_and_file() -> void:
	_say("")
	_say("--- the two taps (home fleet afloat) ---")
	var yard: FleetYardBlock = _yard_block()
	var press: RaiseBatchPress = yard._batch
	var ready: int = _ready_rows(yard)
	var purse: int = _purse()
	press.pressed.emit()
	_check(press.is_armed(), "the first tap arms the press")
	_check(
		press.text == "Confirm — launch %d hulls" % ready,
		"the armed face names what the second tap files: %s" % press.text
	)
	var toasts: int = _toast_count()
	press.pressed.emit()
	_check(not press.is_armed(), "the second tap files and stands the arm down")
	_check(_toast_count() > toasts, "the court reads a receipt")
	_say("receipt: \"%s\"" % _last_toast())
	var filed_line: String = (
		"%d hulls are laid down" % ready if ready != 1 else "One hull is laid down"
	)
	_check(_last_toast().begins_with(filed_line), "the receipt names the hulls filed")
	_check(_purse() == purse, "a launch is paid at Build/work, not on the press")
	var rows: Array[Dictionary] = _yard_block()._rows
	for row: Dictionary in rows:
		if bool(row["ok"]):
			_check(
				int(row["pending"]) >= 1,
				"the redrawn row prints her order under orders (%s)" % row["type_id"]
			)
	_check(not _yard_block()._batch.visible, "every ready hull waits, so the press stands down")
	_say("after the press: %d ships under orders, %d peers rent" % [
		_play.economy.economy.recruits.pending_kind(RecruitQueue.KIND_SHIP),
		_play.economy.economy.available_peasants(),
	])
	var hulls: int = _screen.ship_layer.hull_count_all(_play.player_faction)
	MapPlayRecruits.complete(_play)
	_check(
		_screen.ship_layer.hull_count_all(_play.player_faction) == hulls + ready,
		"the whole line launches at Build/work"
	)
	_say("hulls %d -> %d at Build/work" % [hulls, _screen.ship_layer.hull_count_all(_play.player_faction)])


## An armed press whose sheet is redrawn under it: a player who arms the batch
## and then takes one row's own press must not find the second tap already
## loaded against a count the arm never named.
func _arm_across_a_refresh() -> void:
	_say("")
	_say("--- the arm across a redraw ---")
	MapPlayFleetYard.open(_play)
	await process_frame
	var yard: FleetYardBlock = _yard_block()
	var press: RaiseBatchPress = yard._batch
	if press == null or not press.visible:
		_say("the slip offers nothing to arm this turn — pass skipped")
		return
	var ready: int = _ready_rows(yard)
	press.pressed.emit()
	_check(press.is_armed(), "the batch arms")
	# A row's own Launch, taken while the arm stands: the drawer redraws.
	var type_id: String = ""
	for row: Dictionary in yard._rows:
		if bool(row.get("batch_ready", false)):
			type_id = String(row["type_id"])
			break
	MapPlayFleetYard.on_action(_play, "yard:build:%s" % type_id)
	await process_frame
	var after: RaiseBatchPress = _yard_block()._batch
	var now: int = _ready_rows(_yard_block())
	_say("armed at %d hulls, one row launched, redrawn at %d, face \"%s\", armed %s" % [
		ready, now, after.text, str(after.is_armed()),
	])
	_check(
		not after.is_armed() or after.text == "Confirm — launch %d hulls" % now,
		"a redraw past the arm does not leave a stale confirm loaded"
	)
	_check(
		not after.is_armed(),
		"the redraw forgets the arm the player gave a sheet that no longer stands"
	)


# --- the drill yard, the press's other sheet ---------------------------------


## The shared arm stands on the drill yard too (DR-20261118-07), so the same
## redraw is read there: a batch armed, then one row's own Muster taken, must
## not leave a loaded confirm behind.
func _drill_yard_pass() -> void:
	_say("")
	_say("--- the drill yard: the same arm on the other sheet ---")
	var home: ArmyState = ArmyTraining.home_army(
		_play.army_layer.armies, _play.player_faction
	)
	_check(home != null, "the crown keeps a Home Army to drum into")
	if home == null:
		return
	MapPlayArmies.select(_play, home)
	MapPlayArmies.open_muster(_play)
	await process_frame
	var box: ArmyMusterBlock = _screen.hud.panels.army_panel._muster_box
	var press: RaiseBatchPress = box._batch if box != null else null
	if press == null:
		_check(false, "the drill yard carries the one press")
		return
	var ready: Array[String] = ArmyTraining.batch_types(_play.economy.economy)
	_say("drill yard: %d ready, face \"%s\"" % [ready.size(), press.text])
	_check(press.visible and press.text == "Muster all ready (%d)" % ready.size(),
		"the drill yard's face names its count")
	if ready.is_empty():
		return
	press.pressed.emit()
	_check(press.is_armed(), "the drill yard arms on the first tap")
	MapPlayArmies.on_action(_play, "recruit:%s" % ready[0])
	await process_frame
	var after: RaiseBatchPress = _screen.hud.panels.army_panel._muster_box._batch
	_check(not after.is_armed(), "one row's own press forgets the drill yard's arm")
	_say("after the row: face \"%s\", armed %s" % [after.text, str(after.is_armed())])


# --- the slip with no squadron afloat ---------------------------------------


## Breaking up the last hull retires the home fleet, and the yard then offers the
## slip that founds a new one. The batch there files orders against a panel whose
## fleet is still null — the state no rule test covers.
func _empty_slip_pass() -> void:
	_say("")
	_say("--- the slip with no squadron afloat ---")
	_break_up_the_home_fleet()
	_check(_home() == null, "the home squadron retired with her last hull")
	MapPlayFleetYard.open(_play)
	await process_frame
	var yard: FleetYardBlock = _yard_block()
	if yard == null:
		_check(false, "the slip opened after the fleet retired")
		return
	var press: RaiseBatchPress = yard._batch
	var ready: int = _ready_rows(yard)
	_say("slip: rows %d, ready %d, purse %d, face \"%s\"" % [
		yard._rows.size(), ready, _purse(), press.text if press != null else "-",
	])
	_check(ready > 0, "a purse a crown can spend prints ready hulls on the slip")
	_check(press != null and press.visible, "the slip carries the one press")
	_check(_panel_reads_slip(), "the panel says the first launch founds the fleet")
	if press == null or not press.visible:
		return
	var hulls: int = _screen.ship_layer.hull_count_all(_play.player_faction)
	var before_pending: int = _play.economy.economy.recruits.pending_kind(RecruitQueue.KIND_SHIP)
	press.pressed.emit()
	press.pressed.emit()
	var filed: int = _play.economy.economy.recruits.pending_kind(RecruitQueue.KIND_SHIP) - before_pending
	_say("receipt: \"%s\" — %d hulls filed" % [_last_toast(), filed])
	_check(filed == ready, "the press files the line it named")
	# The panel is read again without any other input: this is what the crown
	# still sees after the press spent the line.
	var after: RaiseBatchPress = _yard_block()._batch
	var rows: Array[Dictionary] = _yard_block()._rows
	var claimed: int = 0
	for row: Dictionary in rows:
		claimed += int(row.get("pending", 0))
	_say("after the press: face \"%s\", visible %s, rows claiming %d orders" % [
		after.text, str(after.visible), claimed,
	])
	_check(
		claimed == _play.economy.economy.recruits.pending_kind(RecruitQueue.KIND_SHIP),
		"the redrawn slip prints the orders it holds"
	)
	_check(not after.visible, "the slip stands the press down once her line waits on orders")
	# A press the face still offers, taken again: the court must hear something.
	var toasts: int = _toast_count()
	after.pressed.emit()
	after.pressed.emit()
	_say("a second press: %d new despatch(es), %d hulls under orders" % [
		_toast_count() - toasts,
		_play.economy.economy.recruits.pending_kind(RecruitQueue.KIND_SHIP),
	])
	_check(
		_toast_count() > toasts or not after.visible,
		"a press that files nothing either stands down or says why"
	)
	_check(
		_play.economy.economy.recruits.pending_kind(RecruitQueue.KIND_SHIP) == before_pending + filed,
		"a second press cannot double the line"
	)
	# The promise the press made is kept at Build/work — with the row's own order
	# from the pass above, queued in the same turn.
	var before: int = _screen.ship_layer.hull_count_all(_play.player_faction)
	var promised: int = _play.economy.economy.recruits.pending_kind(RecruitQueue.KIND_SHIP)
	MapPlayRecruits.complete(_play)
	_check(
		_screen.ship_layer.hull_count_all(_play.player_faction) == before + promised,
		"the line the slip promised launches at Build/work"
	)
	_say("hulls %d -> %d — the founded fleet: %s" % [
		before, _screen.ship_layer.hull_count_all(_play.player_faction),
		str(_home() != null),
	])


## Breaks up every hull the crown keeps in its capital port, through the drawer's
## own intent, so the squadron retires as a player's would.
func _break_up_the_home_fleet() -> void:
	var fleet: FleetState = _home()
	if fleet == null:
		return
	MapPlayFleetYard.refresh(_play, fleet)
	var ids: Array[String] = fleet.hulls.duplicate()
	for hull_id: String in ids:
		MapPlayFleetYard.on_action(_play, "yard:scrap:%s" % hull_id)
	_say("broke up %d hull(s): home fleet %s" % [ids.size(), str(_home() != null)])


# --- readings ----------------------------------------------------------------


func _yard_block() -> FleetYardBlock:
	if _screen == null or _screen.hud == null or _screen.hud.panels == null:
		return null
	var panel: FleetPanel = _screen.hud.panels.fleet_panel
	return panel._yard if panel != null else null


func _ready_rows(yard: FleetYardBlock) -> int:
	var ready: int = 0
	for row: Dictionary in yard._rows:
		if bool(row.get("batch_ready", false)):
			ready += 1
	return ready


## The slip's own words for a crown with nothing afloat.
func _panel_reads_slip() -> bool:
	var panel: FleetPanel = _screen.hud.panels.fleet_panel
	return panel != null and panel._ships.text.contains("No home fleet")


func _home() -> FleetState:
	return _play.ship_layer.home_fleet(_play.capital_province)


func _purse() -> int:
	return _play.economy.economy.treasury


func _peasants() -> int:
	return _play.economy.economy.available_peasants()


func _toast_count() -> int:
	return _screen.hud._toast_box.get_child_count()


func _last_toast() -> String:
	var box: VBoxContainer = _screen.hud._toast_box
	if box.get_child_count() == 0:
		return ""
	var plate: Control = box.get_child(box.get_child_count() - 1) as Control
	for child: Node in plate.get_children():
		if child is Label:
			return (child as Label).text
	return ""


# --- reporting ---------------------------------------------------------------


func _check(ok: bool, what: String) -> void:
	if ok:
		_say("  ok   %s" % what)
		return
	_failures.append(what)
	_say("  FAIL %s" % what)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	_say("")
	if _failures.is_empty():
		_say("%d checks passed — the one press names its line, files it, and the slip reads what it filed" % _steps.size())
	else:
		_say("%d checks FAILED:" % _failures.size())
		for failure: String in _failures:
			_say("  - %s" % failure)
	print("\n--- playtest_fleet_yard_batch: %d steps, %d failures ---" % [_steps.size(), _failures.size()])
	quit(1 if not _failures.is_empty() else 0)