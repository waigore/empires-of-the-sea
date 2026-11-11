extends SceneTree
## Headless playtest drive for allied defence: a rival declares war on the
## court's formal ally, the human is called to arms, joins, and then fights the
## battle it did not start (wiki: diplomacy § Alliances § Mutual defence,
## § Breaking an alliance; quick-battle § Turn structure). Not a CI gate — run
## it by hand:
##   godot --headless --path . --script res://tests/playtest_allied_defence.gd
##
## The alliance is signed through the court's own order path; the war on the
## ally is a real `DiplomacyRules.declare_war`, the same call the rival planner
## makes; the answer, the suspended turn, the combat pass and the battle plate
## are the game's own helpers.

const Launch = preload("res://tests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
## The alliance order needs this much goodwill before a court signs.
const ALLIANCE_SCORE: float = 80.0

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("seed %s — player %s, %d provinces in %s" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction),
		_play.model.province_count(), FactionCatalog.region_label(_play.region_index),
	])
	var rivals: Array[int] = []
	for gp: int in FactionCatalog.great_power_ids():
		if gp != _play.player_faction:
			rivals.append(gp)
	if rivals.size() < 2:
		_say("need two rival Great Powers")
		_finish()
		return
	var ally: int = rivals[0]
	_ally_pass(ally, rivals[1])
	_second_call_pass(ally)
	_finish()


# --- passes ----------------------------------------------------------------


## Sign the alliance at court, then let a turn close: the treaty is on the
## preceding turn's books and any rival declaration on the ally raises the call
## the court must answer. Joining starts a war the court did not declare, and
## the rival's army standing on a player province fights the first battle.
func _ally_pass(ally: int, aggressor: int) -> void:
	_say("")
	_say("--- allied defence: %s allies with %s ---" % [
		FactionCatalog.name_of(_play.player_faction), FactionCatalog.name_of(ally),
	])
	_sign_alliance(ally)
	var raised: Dictionary = _take_turn(true)
	if not raised.is_empty():
		aggressor = int(raised["aggressor"])
		_say("a rival declared on the ally this turn and the court joined: now at war with %s" % (
			FactionCatalog.name_of(aggressor)
		))
	else:
		_say("alliance stands after a turn: %s (snapshot %s)" % [
			str(_relation(ally).formal_alliance),
			str(CallToArms.allied_in_snapshot(_play.diplomacy, _play.player_faction, ally)),
		])
		aggressor = _declare_on_ally(ally, aggressor)
		if aggressor < 0:
			return
	if not _relation(aggressor).at_war:
		_say("the court is not at war with %s — the call went unanswered" % (
			FactionCatalog.name_of(aggressor)
		))
		return
	_battle_pass(aggressor)


## A rival declares war on the ally: the court is asked, reads the banner, and
## joins. Returns the aggressor id, or -1 when no call was raised.
func _declare_on_ally(ally: int, aggressor: int) -> int:
	_say("--- %s declares war on %s ---" % [
		FactionCatalog.name_of(aggressor), FactionCatalog.name_of(ally),
	])
	var war: Dictionary = DiplomacyRules.declare_war(_play.diplomacy, aggressor, ally)
	_say("declaration: ok %s %s; news %s" % [
		str(war.get("ok", false)), String(war.get("reason", "")),
		str(war.get("calls", [])),
	])
	if not CallToArms.has_pending(_play.diplomacy, _play.player_faction):
		_say("no call reached the court")
		return -1
	_say("call waiting: pending %d" % _play.diplomacy.pending_calls.size())
	# The calendar stops on the call; the court opens on it.
	MapPlayTurn.end_turn(_play)
	_say("the calendar stops: suspended %s, court open %s, turn %d" % [
		str(_play.turn_suspended), str(_play.hud.panels.diplomacy_open), _play.turn,
	])
	_read_call_banner()
	_say("court pair with %s before the answer: %s" % [
		FactionCatalog.name_of(aggressor), _stand(_relation(aggressor)),
	])
	# The rival's army is already standing on a player province when the court
	# answers, so the war's first battle is fought in the same turn.
	var held: int = _player_province()
	if held >= 0:
		_play.model.province_data(held).owner = _play.player_faction
		_play.model.province_data(held).fort_level = 1
		_play.army_layer.armies.clear()
		_seat(_play.player_faction, held, 5, 300)
		_seat(aggressor, held, 7, 310, true)
		_play.battle_plan = "defensive"
		_say("%s stands in %s with 7 regiments; the court holds it with 5, plan %s" % [
			FactionCatalog.name_of(aggressor), _play.model.province_name(held),
			_play.battle_plan,
		])
	MapPlayTurn.answer_call(_play, true)
	_say("answer joined: suspended %s, war with %s %s, court pair %s" % [
		str(_play.turn_suspended), FactionCatalog.name_of(aggressor),
		str(_relation(aggressor).at_war), _stand(_relation(aggressor)),
	])
	_say("call banner still up: %s" % str(not _banner_text().is_empty()))
	return aggressor


## The battle the court did not start: a rival army on a player province, one
## real turn, and whatever the plate tells the defender.
func _battle_pass(aggressor: int) -> void:
	_say("")
	var held: int = _player_province()
	if held < 0:
		_say("no player province to defend")
		return
	_say("--- the battle the court did not start: %s comes for %s ---" % [
		FactionCatalog.name_of(aggressor), _play.model.province_name(held),
	])
	_play.model.province_data(held).owner = _play.player_faction
	_play.model.province_data(held).fort_level = 1
	_play.army_layer.armies.clear()
	_seat(_play.player_faction, held, 5, 400)
	_seat(aggressor, held, 7, 410, true)
	_play.battle_plan = "defensive"
	_say("before the turn: %s at %s; player at war with %s: %s; plan %s" % [
		FactionCatalog.name_of(aggressor), _play.model.province_name(held),
		FactionCatalog.name_of(aggressor), str(_relation(aggressor).at_war),
		_play.battle_plan,
	])
	var seen: Array[Dictionary] = []
	var recorder := func(battles: Array[Dictionary]) -> void:
		for battle: Dictionary in battles:
			seen.append(battle)
	_play.host.battle_resolved.connect(recorder)
	# One real turn, no draining: the plate the combat pass raises stays up.
	var guardian: int = 0
	while not _play.campaign_over() and guardian < 4:
		MapPlayTurn.end_turn(_play)
		if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
			_say("turn stopped for a call to arms — refused")
			MapPlayTurn.answer_call(_play, false)
		elif Intervention.has_pending(_play.diplomacy, _play.player_faction):
			_say("turn stopped for an intervention — stood aside")
			MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
			_say("turn stopped for a rival proposal — refused")
			MapPlayTurn.answer_offer(_play, false)
		else:
			break
		guardian += 1
	_play.host.battle_resolved.disconnect(recorder)
	_say("%d battle%s resolved; %d plate%s queued" % [
		seen.size(), "" if seen.size() == 1 else "s",
		_play.hud._quick_queue.size(), "" if _play.hud._quick_queue.size() == 1 else "s",
	])
	_read_plate(held)
	_say("the province: %s now held by %s; player regiments %d" % [
		_play.model.province_name(held),
		FactionCatalog.name_of(_play.model.province_owner(held)),
		_play.army_layer.regiment_count_all(_play.player_faction),
	])
	_say("wash over %s: %s" % [
		FactionCatalog.name_of(aggressor), _wash(aggressor),
	])


## Two rivals declare on the same ally in one turn: two calls wait, the court
## asks one at a time, closing the sheet without answering brings it back, and
## the refusal that answers the second carries the unified penalty
## (wiki: diplomacy § Alliances § Mutual defence, § Breaking an alliance).
func _second_call_pass(ally: int) -> void:
	_say("")
	if not _relation(ally).formal_alliance:
		_sign_alliance(ally)
		# The same freeze the close of a turn performs, so the treaty is on the
		# preceding turn's books (CallToArms reads only that snapshot).
		CallToArms.freeze_alliances(_play.diplomacy)
	var others: Array[int] = []
	for gp: int in FactionCatalog.great_power_ids():
		if gp != _play.player_faction and gp != ally and not _relation(gp).at_war:
			others.append(gp)
	if others.size() < 2:
		_say("fewer than two rivals left to declare")
		return
	var first: int = others[0]
	var second: int = others[1]
	var peer: int = others[2] if others.size() > 2 else -1
	_say("--- two declarations in one turn: %s and %s fall on %s ---" % [
		FactionCatalog.name_of(first), FactionCatalog.name_of(second),
		FactionCatalog.name_of(ally),
	])
	DiplomacyRules.declare_war(_play.diplomacy, first, ally)
	DiplomacyRules.declare_war(_play.diplomacy, second, ally)
	_say("calls waiting: %d" % _play.diplomacy.pending_calls.size())
	var score_before: float = _relation(ally).score
	var peer_before: float = _relation(peer).score if peer >= 0 else -1.0
	var turn_before: int = _play.turn
	MapPlayTurn.end_turn(_play)
	_say("the calendar stops: suspended %s, court open %s, turn %d" % [
		str(_play.turn_suspended), str(_play.hud.panels.diplomacy_open), _play.turn,
	])
	_read_call_banner()
	# Closing the sheet must not dismiss the decision: the calendar brings it back.
	DiplomacyHud.hide(_play.hud.panels)
	_say("sheet closed: open %s" % str(_play.hud.panels.diplomacy_open))
	MapPlayTurn.end_turn(_play)
	_say("end turn reopens the court: %s, banner up %s" % [
		str(_play.hud.panels.diplomacy_open), str(not _banner_text().is_empty()),
	])
	MapPlayTurn.answer_call(_play, true)
	_say("first call joined: turn %d, calls left %d, banner %s" % [
		_play.turn, _play.diplomacy.pending_calls.size(), _banner_text(),
	])
	MapPlayTurn.answer_call(_play, false)
	_say("second call refused: turn %d -> %d, alliance %s, with %s %.1f -> %.1f; %s %.1f -> %.1f" % [
		turn_before, _play.turn, str(_relation(ally).formal_alliance),
		FactionCatalog.name_of(ally), score_before, _relation(ally).score,
		FactionCatalog.name_of(peer), peer_before,
		_relation(peer).score if peer >= 0 else -1.0,
	])
	_say("war with %s: %s; war with %s: %s" % [
		FactionCatalog.name_of(first), str(_relation(first).at_war),
		FactionCatalog.name_of(second), str(_relation(second).at_war),
	])
	_drain_plates()


# --- reads -----------------------------------------------------------------


## What the player actually reads in the court's consent banner: caption, body
## and every button.
func _read_call_banner() -> void:
	var text: String = _banner_text()
	if text.is_empty():
		_say("banner: none")
		return
	_say("banner: %s" % text)
	_say("banner buttons: %s" % _banner_buttons())
	_say("court toast: %s" % _last_toast())


func _read_plate(held: int) -> void:
	var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
	if overlay == null or not overlay.is_shown():
		_say("no battle plate was raised for %s" % _play.model.province_name(held))
		return
	var battle: Dictionary = overlay.battle
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	_say("plate: %s v %s at %s — \"%s\"" % [
		FactionCatalog.name_of(int(battle.get("attacker", -1))),
		FactionCatalog.name_of(int(battle.get("defender", -1))),
		overlay.province_name, String(overlay._outcome.text),
	])
	_say("plate stance: %s" % QuickBattleCopy.plan_text(battle))
	_say("plate numbers: %d v %d, %d guns; plans %s / enemy %s" % [
		int(quick.get("attacker_start", 0)), int(quick.get("defender_start", 0)),
		int(quick.get("guns_start", 0)),
		String(quick.get("plan", "?")), String(quick.get("defender_plan", "?")),
	])
	overlay.skip()
	overlay._on_continue()


# --- seating and turn plumbing ---------------------------------------------


## Signs the treaty through the court's own order, with the goodwill a signing
## court needs (a seat, as the rules tests set it).
func _sign_alliance(ally: int) -> void:
	_relation(ally).score = ALLIANCE_SCORE
	var economy: PlayerEconomy = _play.economy.economy if _play.economy != null else null
	var result: Dictionary = DiplomacyOrders.apply(
		_play.diplomacy, _play.world, economy,
		{"kind": DiplomacyOrders.KIND_ALLIANCE, "from": _play.player_faction, "target": ally}
	)
	_say("alliance order: %s" % String(result.get("message", result.get("reason", ""))))


## One calendar turn, answering whatever consent decision it raises. Calls are
## answered by `join_calls`; the first call it raises is returned (empty when
## none came).
func _take_turn(join_calls: bool) -> Dictionary:
	var raised: Dictionary = {}
	var guardian: int = 0
	while not _play.campaign_over() and guardian < 4:
		MapPlayTurn.end_turn(_play)
		if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
			var call: Dictionary = CallToArms.pending_call_for(
				_play.diplomacy, _play.player_faction
			)
			_say("turn %d stopped for a call to arms: %s against %s" % [
				_play.turn, FactionCatalog.name_of(int(call["defender"])),
				FactionCatalog.name_of(int(call["aggressor"])),
			])
			_read_call_banner()
			if raised.is_empty():
				raised = call.duplicate()
			MapPlayTurn.answer_call(_play, join_calls)
		elif Intervention.has_pending(_play.diplomacy, _play.player_faction):
			_say("turn %d stopped for an intervention — stood aside" % _play.turn)
			MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
			_say("turn %d stopped for a rival proposal — refused" % _play.turn)
			MapPlayTurn.answer_offer(_play, false)
		else:
			break
		guardian += 1
	_drain_plates()
	return raised


func _drain_plates() -> void:
	var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
	var guardian: int = 0
	while overlay != null and overlay.is_shown() and guardian < 6:
		_say("plate: %s v %s at %s" % [
			FactionCatalog.name_of(int(overlay.battle.get("attacker", -1))),
			FactionCatalog.name_of(int(overlay.battle.get("defender", -1))),
			overlay.province_name,
		])
		overlay.skip()
		overlay._on_continue()
		guardian += 1


func _seat(owner: int, province: int, count: int, offset: int, moved: bool = false) -> void:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	var army: ArmyState = ArmyState.muster(
		_play.army_layer.next_army + offset,
		owner,
		province,
		false,
		types,
		_play.army_layer.next_regiment + offset
	)
	army.moved = moved
	_play.army_layer.armies.append(army)
	_play.army_layer.add_marker(army)


# --- text helpers ----------------------------------------------------------


func _relation(other: int) -> DiplomacyRelation:
	return _play.diplomacy.relation(_play.player_faction, other)


func _stand(record: DiplomacyRelation) -> String:
	if record == null:
		return "no envoy"
	var peer: int = record.other(_play.player_faction)
	var subsidy: int = _play.diplomacy.subsidy(_play.player_faction, peer)
	var line: String = "%s %.1f%s" % [
		"war" if record.at_war else "peace", record.score,
		", allied" if record.formal_alliance else "",
	]
	if subsidy > 0:
		line += ", subsidy %d%%" % subsidy
	return line


## Every label in the consent banner, top to bottom, plus the buttons' labels.
func _banner_text() -> String:
	var box: VBoxContainer = _play.hud._diplomacy_panel._call_box
	if box == null or not box.visible or box.get_child_count() == 0:
		return ""
	var parts: PackedStringArray = []
	_collect_labels(box, parts)
	return " / ".join(parts)


func _banner_buttons() -> String:
	var box: VBoxContainer = _play.hud._diplomacy_panel._call_box
	if box == null:
		return "none"
	var parts: PackedStringArray = []
	_collect_buttons(box, parts)
	return ", ".join(parts) if not parts.is_empty() else "none"


func _collect_labels(node: Node, into: PackedStringArray) -> void:
	if node is Label:
		into.append((node as Label).text)
	for child: Node in node.get_children():
		_collect_labels(child, into)


func _collect_buttons(node: Node, into: PackedStringArray) -> void:
	if node is Button:
		into.append("%s%s" % [
			(node as Button).text, "" if not (node as Button).disabled else " (disabled)",
		])
	for child: Node in node.get_children():
		_collect_buttons(child, into)


func _last_toast() -> String:
	if _play.hud.despatches.lane == null:
		return "none"
	var parts: PackedStringArray = []
	_collect_labels(_play.hud.despatches.lane, parts)
	return parts[parts.size() - 1] if not parts.is_empty() else "none"


## The political wash the lens paints over a crown's provinces.
func _wash(faction: int) -> String:
	var lens: DiplomacyLens = _play.diplomacy_lens
	if lens == null:
		return "no lens"
	var band: String = DiplomacySurvey.band_for(_play.diplomacy, _play.player_faction, faction)
	if lens.survey.is_empty():
		return "%s (lens not built)" % band
	return band


func _player_province() -> int:
	for province: ProvinceState in _play.model.provinces:
		if province.owner == _play.player_faction and not province.capital:
			return province.id
	return -1


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_allied_defence: %d steps ---" % _steps.size())
	quit()
