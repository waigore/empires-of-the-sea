extends SceneTree
## Headless free-playtest drive for the Join Empire rung (wiki: diplomacy
## § Join Empire, § GP–Minor Rules — Join Empire, § GP–Tribe Rules — Join
## Empire; DR-20261115-19). The last rung needs the whole overture chain, the
## Empire Building tech, a warm court and a purse that covers the price, so no
## ordinary turn reaches it. The drive seats the chain and reads what the court
## is told at the gate:
##
## 1. the row's own words for a Great Power target, against the two roads the
##    rule accepts on (nearly defeated, or the offerer's power twice the
##    target's);
## 2. the warmth gate at 50 and at 51, against the herald word the sheet prints;
## 3. a press the target answers no, and the second press the turn refuses;
## 4. a Minor's absorption — what joins the empire, and what the hint names;
## 5. a Tribe's colony — the road that keeps its land;
## 6. a nearly defeated Great Power absorbed, read down to the provinces and
##    hulls that change flags;
## 7. the words a rival's Join Empire offer would print if the court raised one.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_join_empire.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
const WARM_SCORE: float = 60.0
const GATE_SCORE: float = DiplomacyCatalog.JOIN_EMPIRE_MIN_SCORE
const TURN_COST_FLOOR: int = 40000

var _steps: PackedStringArray = PackedStringArray()
var _play: PlaySession = null
## The crowns a pass has already spent this turn's one overture on, so the next
## pass seats its chain with a court that can still be offered.
var _used: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = await Launch.open_map(
		self, SEED_TEXT, SETUP_SIZE_INDEX, AdvancedStart.TURNS100
	)
	if screen == null:
		_finish()
		return
	_play = screen.play
	var player: int = _play.player_faction
	# Empire Building is era 4, behind a whole college: the drive seats the study
	# rather than spending a hundred turns on it.
	_play.economy.economy.tech_unlocked["empire_building"] = true
	_say("seed %s — %s, turn %d, treasury %s; Empire Building seated" % [
		SEED_TEXT, FactionCatalog.name_of(player), _play.turn,
		DiplomacyCatalog.money(_play.treasury()),
	])
	_orders_pass(player)
	var target: int = _gp_target(player)
	if target < 0:
		_say("no Great Power at peace is in contact — the gate cannot open")
		_finish()
		return
	_words_pass(target, player)
	_warmth_pass(target, player)
	_target_says_no_pass(player)
	_minor_pass(player)
	_tribe_pass(player)
	_defeat_pass(player)
	_answering_pass(player)
	_finish()


# --- the published power the gate reads --------------------------------------


func _orders_pass(player: int) -> void:
	_say("")
	_say("--- the public order of battle the gate reads ---")
	var power: Dictionary = MapPlayDiplomacy.public_power(_play)
	var orders: Dictionary = MapPlayCourt.public_orders(_play)
	for faction: int in FactionCatalog.great_power_ids():
		_say("  %s: power %d · strength %.1f · hulls %d · provinces %d · %s" % [
			FactionCatalog.name_of(faction),
			int(power.get(faction, 0)),
			float((orders.get("strength", {}) as Dictionary).get(faction, 0.0)),
			int((orders.get("ships", {}) as Dictionary).get(faction, 0)),
			DiplomacyRules.provinces_owned(_play.world, faction),
			"us" if faction == player else "",
		])


# --- 1. the row's words, against the rule's two roads ------------------------


func _words_pass(target: int, player: int) -> void:
	_say("")
	_say("--- the last rung's row: %s ---" % FactionCatalog.name_of(target))
	_ensure_relation(player, target, WARM_SCORE)
	_play.diplomacy.set_overture(player, target, DiplomacyCatalog.STAGE_NAP)
	_play.diplomacy.set_overture(target, player, DiplomacyCatalog.STAGE_NAP)
	_read_sheet(target, "the court at the pact")
	var row: Dictionary = _join_row(target, player)
	if row.is_empty():
		_say("  no Join Empire row is offered")
		return
	var hint: String = String(row.get("hint", ""))
	var power: Dictionary = MapPlayDiplomacy.public_power(_play)
	var near: bool = DiplomacyRules.nearly_defeated(_play.world, target)
	var live: bool = DiplomacyRules.answer_join_empire(_play.world, player, target, power)
	var theirs: int = maxi(int(power.get(target, 1)), 1)
	var doubled: bool = DiplomacyRules.answer_join_empire(
		_play.world, player, target, {player: theirs * 2, target: theirs}
	)
	_say("  rule: nearly defeated %s · accepts at our published power %s · accepts at twice its power %s" % [
		str(near), str(live), str(doubled),
	])
	_say("  the hint: %s" % hint)
	_say("  the hint names the near-defeat road: %s; the power road: %s" % [
		str(hint.contains("nearly")), str(hint.contains("twice") or hint.contains("power")),
	])
	_say("  the hint names what changes flag: provinces %s · regiments %s · hulls %s" % [
		str(hint.contains("province")), str(hint.contains("regiment") or hint.contains("arm")),
		str(hint.contains("hull") or hint.contains("ship") or hint.contains("fleet")),
	])


# --- 2. the warmth gate, against the herald's word ---------------------------


func _warmth_pass(target: int, player: int) -> void:
	_say("")
	_say("--- the warmth gate, either side of %s ---" % str(GATE_SCORE))
	for score: float in [GATE_SCORE - 1.0, GATE_SCORE]:
		_ensure_relation(player, target, score)
		var row: Dictionary = _join_row(target, player)
		_say("  score %.0f: herald reads \"%s\"; the row is %s%s" % [
			score,
			_play.diplomacy.relation(player, target).meter_label(),
			"on" if bool(row.get("ok", false)) else "off",
			"" if bool(row.get("ok", false)) else " — " + String(row.get("reason", "")),
		])
	_ensure_relation(player, target, WARM_SCORE)


# --- 3. the press the target answers no --------------------------------------


func _target_says_no_pass(player: int) -> void:
	_say("")
	var target: int = _gp_target(player)
	if target < 0:
		_say("--- no second Great Power at peace to press ---")
		return
	_say("--- the press a standing crown answers: %s ---" % FactionCatalog.name_of(target))
	_ensure_relation(player, target, WARM_SCORE)
	_play.diplomacy.set_overture(player, target, DiplomacyCatalog.STAGE_NAP)
	_play.diplomacy.set_overture(target, player, DiplomacyCatalog.STAGE_NAP)
	_say("  nearly defeated %s · our power %d of its %d" % [
		str(DiplomacyRules.nearly_defeated(_play.world, target)),
		int(MapPlayDiplomacy.public_power(_play).get(player, 0)),
		int(MapPlayDiplomacy.public_power(_play).get(target, 0)),
	])
	var before: int = _play.treasury()
	_press(target, player)
	_say("  press: %s (purse %s → %s)" % [
		_last_toast(), DiplomacyCatalog.money(before), DiplomacyCatalog.money(_play.treasury()),
	])
	_press(target, player)
	_say("  second press: %s" % _last_toast())


# --- 4. a Minor's absorption ------------------------------------------------


func _minor_pass(player: int) -> void:
	_say("")
	var minor: int = _minor_target(player)
	if minor < 0:
		_say("--- no Minor Nation in contact to absorb ---")
		return
	_say("--- a Minor Nation absorbed: %s ---" % FactionCatalog.name_of(minor))
	_ensure_relation(player, minor, WARM_SCORE)
	_play.diplomacy.set_overture(player, minor, DiplomacyCatalog.STAGE_NAP)
	_play.diplomacy.set_overture(minor, player, DiplomacyCatalog.STAGE_NAP)
	_say("  before: our provinces %d · its provinces %d · our hulls %d · its hulls %d" % [
		DiplomacyRules.provinces_owned(_play.world, player),
		DiplomacyRules.provinces_owned(_play.world, minor),
		_hulls(player), _hulls(minor),
	])
	_read_sheet(minor, "the Minor's court at the pact")
	_press(minor, player)
	_say("  press: %s" % _last_toast())
	_say("  after: our provinces %d · its provinces %d · our hulls %d · its hulls %d" % [
		DiplomacyRules.provinces_owned(_play.world, player),
		DiplomacyRules.provinces_owned(_play.world, minor),
		_hulls(player), _hulls(minor),
	])


# --- 5. a Tribe's colony ----------------------------------------------------


func _tribe_pass(player: int) -> void:
	_say("")
	var tribe: int = _tribe_target(player)
	if tribe < 0:
		_say("--- no Tribe in contact to colonize ---")
		return
	_say("--- a Tribe bought as a colony: %s ---" % FactionCatalog.name_of(tribe))
	_ensure_relation(player, tribe, WARM_SCORE)
	_play.diplomacy.set_overture(player, tribe, DiplomacyCatalog.STAGE_NAP)
	_play.diplomacy.set_overture(tribe, player, DiplomacyCatalog.STAGE_NAP)
	_say("  before: its provinces %d · colony of %s" % [
		DiplomacyRules.provinces_owned(_play.world, tribe),
		FactionCatalog.name_of(_play.diplomacy.colony_of(tribe)),
	])
	_read_sheet(tribe, "the Tribe's court at the pact")
	_press(tribe, player)
	_say("  press: %s" % _last_toast())
	_say("  after: its provinces %d · colony of %s" % [
		DiplomacyRules.provinces_owned(_play.world, tribe),
		FactionCatalog.name_of(_play.diplomacy.colony_of(tribe)),
	])


# --- 6. a nearly defeated crown absorbed -----------------------------------


func _defeat_pass(player: int) -> void:
	_say("")
	var target: int = _gp_target(player)
	if target < 0:
		_say("--- no Great Power left to strip ---")
		return
	_say("--- a nearly defeated crown absorbed: %s ---" % FactionCatalog.name_of(target))
	_strip_to_nearly_defeated(target)
	_ensure_relation(player, target, WARM_SCORE)
	_play.diplomacy.set_overture(player, target, DiplomacyCatalog.STAGE_NAP)
	_play.diplomacy.set_overture(target, player, DiplomacyCatalog.STAGE_NAP)
	_say("  seated: provinces %d · seat %s · nearly defeated %s" % [
		DiplomacyRules.provinces_owned(_play.world, target),
		_seat_name(target),
		str(DiplomacyRules.nearly_defeated(_play.world, target)),
	])
	_say("  before: our provinces %d · our hulls %d · its hulls %d" % [
		DiplomacyRules.provinces_owned(_play.world, player), _hulls(player), _hulls(target),
	])
	_read_sheet(target, "the stripped crown's court at the pact")
	_press(target, player)
	_say("  press: %s" % _last_toast())
	_say("  after: our provinces %d · our hulls %d · its provinces %d · its hulls %d" % [
		DiplomacyRules.provinces_owned(_play.world, player), _hulls(player),
		DiplomacyRules.provinces_owned(_play.world, target), _hulls(target),
	])


# --- 7. the answering court's words ---------------------------------------


func _answering_pass(player: int) -> void:
	_say("")
	_say("--- the words a rival's Join Empire offer would print ---")
	var rival: int = -1
	for faction: int in FactionCatalog.great_power_ids():
		if faction != player:
			rival = faction
			break
	if rival < 0:
		_say("  no rival crown")
		return
	_say("  body: %s" % ConsentCopy.proposal_body(
		rival, DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_JOIN_EMPIRE
	))
	var raised: Dictionary = DiplomacyProposals.queue(
		_play.diplomacy, _play.world, rival,
		DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_JOIN_EMPIRE
	)
	_say("  a rival raising it: %s — %s" % [
		str(bool(raised.get("ok", false))),
		String(raised.get("reason", raised.get("message", ""))),
	])


# --- reading ----------------------------------------------------------------


## The Join Empire row as the rules build it for the sheet: the label, the cost,
## the hint under it and whether the press is on.
func _join_row(target: int, player: int) -> Dictionary:
	var options: Array[Dictionary] = DiplomacyOrders.options(
		_play.diplomacy, _play.world, _play.treasury(), player, target, _tech()
	)
	for option: Dictionary in options:
		if String(option.get("label", "")) == "Offer Join Empire":
			return option
	return {}


func _read_sheet(target: int, when: String) -> void:
	MapPlayDiplomacy.open(_play)
	var panel: DiplomacyPanel = _play.hud.panels.diplomacy_panel
	if panel == null:
		_say("  no diplomacy panel")
		return
	panel.select_faction(target)
	_say("  --- %s ---" % when)
	var detail: Node = panel.get("_detail") as Node
	if detail == null:
		return
	for line: String in _sheet_lines(detail):
		_say("    " + line)


func _sheet_lines(node: Node) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for child: Node in node.get_children():
		if child is Label:
			var text: String = (child as Label).text.strip_edges()
			if not text.is_empty():
				lines.append(text)
		elif child is Button:
			var button := child as Button
			var label: String = button.text.strip_edges()
			if not label.is_empty():
				lines.append("[%s] %s" % ["off" if button.disabled else "on", label])
		lines.append_array(_sheet_lines(child))
	return lines


## Presses the Join Empire row through the controller a player's tap reaches.
func _press(target: int, player: int) -> void:
	MapPlayDiplomacy.on_order(
		_play, DiplomacyOrders.KIND_OVERTURE, target, DiplomacyCatalog.STAGE_JOIN_EMPIRE
	)


# --- seating ----------------------------------------------------------------


func _ensure_relation(a: int, b: int, score: float) -> void:
	if not _play.diplomacy.has_relation(a, b):
		_play.diplomacy.ensure_relation(a, b, _play.turn)
	_play.diplomacy.relation(a, b).score = score
	if _play.diplomacy.relation(b, a) != null:
		_play.diplomacy.relation(b, a).score = score


## The two criteria the rules read: three or fewer provinces, the original capital
## no longer held (wiki: diplomacy § Nearly defeated).
func _strip_to_nearly_defeated(faction: int) -> void:
	for model: MapModel in _play.world.regions:
		var seat: int = CapitalLoss.seat_of(model, faction)
		if seat < 0:
			continue
		var data: ProvinceState = model.province_data(seat)
		if data != null:
			data.owner = MapModel.NO_ID
			CapitalLoss.clear_seat(data)
	var kept: int = 0
	for model: MapModel in _play.world.regions:
		for province: ProvinceState in model.provinces:
			if province.owner != faction:
				continue
			kept += 1
			if kept <= 3:
				continue
			province.owner = MapModel.NO_ID


# --- targets ----------------------------------------------------------------


func _gp_target(player: int) -> int:
	var best: int = -1
	var best_power: int = 0
	var power: Dictionary = MapPlayDiplomacy.public_power(_play)
	for faction: int in FactionCatalog.great_power_ids():
		if faction == player:
			continue
		if _used.has(faction):
			continue
		if not _play.diplomacy.has_relation(player, faction):
			continue
		if world_owner_alive(faction) == false:
			continue
		var record: DiplomacyRelation = _play.diplomacy.relation(player, faction)
		if record == null or record.at_war:
			continue
		var their_power: int = int(power.get(faction, 0))
		if best < 0 or their_power < best_power:
			best = faction
			best_power = their_power
	if best >= 0:
		_used.append(best)
	return best


func _minor_target(player: int) -> int:
	var best: int = -1
	var best_hulls: int = -1
	for faction: int in FactionCatalog.minor_ids():
		if not _play.diplomacy.has_relation(player, faction):
			continue
		if DiplomacyRules.provinces_owned(_play.world, faction) < 1:
			continue
		var record: DiplomacyRelation = _play.diplomacy.relation(player, faction)
		if record != null and record.at_war:
			continue
		if _hulls(faction) > best_hulls:
			best = faction
			best_hulls = _hulls(faction)
	return best


func _tribe_target(player: int) -> int:
	for faction: int in FactionCatalog.tribe_ids():
		if not _play.diplomacy.has_relation(player, faction):
			continue
		if DiplomacyRules.provinces_owned(_play.world, faction) < 1:
			continue
		if _play.diplomacy.colony_of(faction) >= 0:
			continue
		var record: DiplomacyRelation = _play.diplomacy.relation(player, faction)
		if record != null and record.at_war:
			continue
		return faction
	return -1


## A crown with no provinces left has been absorbed; the drive skips it.
func world_owner_alive(faction: int) -> bool:
	return DiplomacyRules.provinces_owned(_play.world, faction) > 0


# --- helpers ----------------------------------------------------------------


func _tech() -> Dictionary:
	return _play.economy.economy.tech_unlocked


func _hulls(faction: int) -> int:
	var orders: Dictionary = MapPlayCourt.public_orders(_play)
	return int((orders.get("ships", {}) as Dictionary).get(faction, 0))


func _seat_name(faction: int) -> String:
	for model: MapModel in _play.world.regions:
		var seat: int = CapitalLoss.seat_of(model, faction)
		if seat >= 0:
			return _play.model.province_name(seat)
	return "none"


func _last_toast() -> String:
	var despatches: HudDespatches = _play.hud.despatches
	if despatches == null:
		return "no despatch"
	var waiting: PackedStringArray = despatches.waiting()
	if not waiting.is_empty():
		return waiting[waiting.size() - 1]
	var newest: String = despatches.newest_live_text()
	return newest if not newest.is_empty() else "no despatch"


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_join_empire: %d steps ---" % _steps.size())
	quit()
