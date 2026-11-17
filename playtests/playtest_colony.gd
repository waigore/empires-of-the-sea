extends SceneTree
## Headless free-playtest drive for the colony chain (wiki: diplomacy § GP–Tribe
## Rules, § Overture chain; world-market § Favoured trading partner; the-gazette
## § Item catalog). A Tribe is New World only, so the chain sits behind a
## Passage, a charted province, four overture stages, a relation floor and a
## per-province price — the hardest diplomatic gate in the game.
##
## The drive opens the turn-100 advanced start (the New World fully charted, so
## first contact has already fired) and then plays the chain the way a court
## does: it reads the court sheet, presses the sheet's own buttons, closes real
## turns, and prints what the crown was told at each step. Not a CI gate — run
## it by hand:
##   godot --headless --path . --script res://playtests/playtest_colony.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
const MAX_TURNS: int = 8

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = await _open_game()
	if screen == null:
		_finish()
		return
	_screen = screen
	var play: PlaySession = screen.play
	_say("seed %s — turn %d, treasury %s, %d provinces" % [
		SEED_TEXT, play.turn, DiplomacyCatalog.money(play.treasury()),
		play.model.province_count(),
	])
	var tribe: int = _first_tribe(play)
	if tribe < 0:
		_say("no Tribe is in contact — the chain cannot start")
		_finish()
		return
	_say("first contact: %s (%d provinces, relation %.1f)" % [
		FactionCatalog.name_of(tribe), _provinces(play, tribe),
		play.diplomacy.relation(play.player_faction, tribe).score,
	])
	MapPlayDiplomacy.open(play)
	var panel: DiplomacyPanel = play.hud.panels.diplomacy_panel
	panel.select_faction(tribe)
	_read_sheet(panel, "the court on first contact")
	_walk(play, panel, tribe)
	_finish()


# --- the chain --------------------------------------------------------------


func _walk(play: PlaySession, panel: DiplomacyPanel, tribe: int) -> void:
	var stage: String = play.diplomacy.overture(play.player_faction, tribe)
	_say("the chain stands at %s" % DiplomacyCatalog.stage_label(stage))
	for _step in 6:
		var next: String = DiplomacyCatalog.next_stage(stage)
		if next.is_empty():
			_say("the chain is complete")
			return
		var label: String = "Offer %s" % DiplomacyCatalog.stage_label(next)
		var press: Dictionary = _press(panel, label)
		if not bool(press["found"]):
			_say("the sheet offers no \"%s\" — the chain stops here" % label)
			return
		if bool(press["disabled"]):
			_say("the sheet shows \"%s\" disabled — %s" % [label, String(press["reason"])])
			if next != DiplomacyCatalog.STAGE_JOIN_EMPIRE:
				return
			# The lever the sheet offers: aid is +5 and needs the embassy.
			var aid: Dictionary = _press(panel, "Grant Aid")
			if not bool(aid["found"]) or bool(aid["disabled"]):
				_say("the sheet offers no usable \"Grant Aid\" — %s" % String(aid["reason"]))
				return
			_say("pressed \"Grant Aid\" — %s" % _last_toast(play))
			_read_sheet(panel, "after the aid")
			press = _press(panel, label)
			if bool(press["disabled"]):
				_say("\"%s\" is still disabled — %s" % [label, String(press["reason"])])
				return
		_say("pressed \"%s\" — %s" % [label, _last_toast(play)])
		_read_sheet(panel, "after the %s" % DiplomacyCatalog.stage_label(next))
		if next == DiplomacyCatalog.STAGE_JOIN_EMPIRE:
			break
		_end_turn(play)
		panel.select_faction(tribe)
		_read_sheet(panel, "the next turn's sheet")
		stage = play.diplomacy.overture(play.player_faction, tribe)
	_read_colony(play, tribe)
	_read_again(play, panel, tribe)
	_read_boycott(play, panel, tribe)


## The colony a turn later: does the court still offer to buy what it already
## holds, and at what price?
func _read_again(play: PlaySession, panel: DiplomacyPanel, tribe: int) -> void:
	_end_turn(play)
	panel.select_faction(tribe)
	_read_sheet(panel, "the colony a turn later")
	var before: int = play.treasury()
	var press: Dictionary = _press(panel, "Offer Join Empire")
	if not bool(press["found"]):
		_say("the sheet no longer offers Join Empire")
		return
	if bool(press["disabled"]):
		_say("Join Empire is disabled on a standing colony — %s" % String(press["reason"]))
		return
	_say("pressed \"Offer Join Empire\" on a standing colony — %s" % _last_toast(play))
	_say("treasury %s -> %s" % [
		DiplomacyCatalog.money(before), DiplomacyCatalog.money(play.treasury()),
	])


## What the crown can now read about the colony it holds.
func _read_colony(play: PlaySession, tribe: int) -> void:
	var state: DiplomacyState = play.diplomacy
	_say("colony_of(%s) = %d" % [
		FactionCatalog.name_of(tribe), state.colony_of(tribe),
	])
	_say("survey standing: %s" % DiplomacySurvey.standing_text(
		state, play.player_faction, tribe
	))
	for event: Dictionary in state.events:
		if String(event.get("kind", "")) != "colonyFormed":
			continue
		_say("chronicle: %s" % DiplomacyHistory.describe(state, event, play.player_faction))
	_say("dialogue beat: %s" % str(DialogueEvents.for_pair(
		state, play.player_faction, tribe
	).get("text", "none")))


## The boycott is the colony's other privilege: it appears only once a colony
## stands, and it is issued against a Great Power, not the Tribe.
func _read_boycott(play: PlaySession, panel: DiplomacyPanel, tribe: int) -> void:
	var gp: int = -1
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		if play.diplomacy.has_relation(play.player_faction, faction):
			gp = faction
			break
	if gp < 0:
		_say("no rival court to boycott")
		return
	panel.select_faction(gp)
	_read_sheet(panel, "a rival court, now that a colony stands")
	var press: Dictionary = _press(panel, "Boycott Their Trade")
	if not bool(press["found"]):
		_say("the sheet offers no boycott")
		return
	if bool(press["disabled"]):
		_say("the boycott is disabled — %s" % String(press["reason"]))
		return
	_say("pressed \"Boycott Their Trade\" — %s" % _last_toast(play))
	_say("boycotting %s: %s" % [
		FactionCatalog.name_of(gp),
		str(DiplomacyTrade.is_boycotting(play.diplomacy, play.player_faction, gp)),
	])
	_read_sheet(panel, "after the boycott")
	panel.select_faction(tribe)


# --- reading ----------------------------------------------------------------


## Prints the open court's sheet the way a player reads it: every label and
## every button, with a disabled button's own reason under it.
func _read_sheet(panel: DiplomacyPanel, when: String) -> void:
	_say("--- %s ---" % when)
	for line: String in _sheet_lines(panel):
		_say("  " + line)


func _sheet_lines(panel: DiplomacyPanel) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var detail: Node = panel.get("_detail") as Node
	if detail == null:
		return lines
	_collect(detail, lines)
	return lines


func _collect(node: Node, lines: PackedStringArray) -> void:
	for child: Node in node.get_children():
		if child is Label:
			var text: String = (child as Label).text.strip_edges()
			if not text.is_empty():
				lines.append(text)
		elif child is Button:
			var button := child as Button
			var text: String = button.text.strip_edges()
			if not text.is_empty():
				lines.append("[%s] %s" % ["off" if button.disabled else "on", text])
		_collect(child, lines)


## Presses the sheet's own button whose text starts with `prefix`. A disabled
## button is not pressed — the sheet's own reason line under it is returned
## instead, which is all a player gets.
func _press(panel: DiplomacyPanel, prefix: String) -> Dictionary:
	var detail: Node = panel.get("_detail") as Node
	if detail == null:
		return {"found": false, "disabled": false, "reason": ""}
	var button: Button = _find_button(detail, prefix)
	if button == null:
		return {"found": false, "disabled": false, "reason": ""}
	if button.disabled:
		return {"found": true, "disabled": true, "reason": _reason_under(button)}
	button.pressed.emit()
	return {"found": true, "disabled": false, "reason": ""}


## The caption the sheet prints under a refused order: the next label sibling.
func _reason_under(button: Button) -> String:
	var parent: Node = button.get_parent()
	if parent == null:
		return "no reason given"
	var index: int = button.get_index()
	for offset in range(index + 1, parent.get_child_count()):
		var sibling: Node = parent.get_child(offset)
		if sibling is Label:
			return (sibling as Label).text.strip_edges()
		if sibling is Button:
			break
	return "no reason given"


func _find_button(node: Node, prefix: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
			return child as Button
		var found: Button = _find_button(child, prefix)
		if found != null:
			return found
	return null


## The newest despatch the court was handed, live or queued.
func _last_toast(play: PlaySession) -> String:
	var despatches: HudDespatches = play.hud.despatches
	if despatches == null:
		return "no despatch"
	var waiting: PackedStringArray = despatches.waiting()
	if not waiting.is_empty():
		return waiting[waiting.size() - 1]
	var newest: String = ""
	for child: Node in despatches.box.get_children():
		var text: String = String(child.get_meta("toast_text", ""))
		if not text.is_empty():
			newest = text
	return newest if not newest.is_empty() else "no despatch"


# --- helpers ----------------------------------------------------------------


func _open_game() -> MapScreen:
	return await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX, AdvancedStart.TURNS100)


## The Tribe the crown has met, preferring the smallest (cheapest Join Empire).
func _first_tribe(play: PlaySession) -> int:
	var best: int = -1
	var best_provinces: int = 1 << 30
	for tribe: int in FactionCatalog.tribe_ids():
		if not play.diplomacy.has_relation(play.player_faction, tribe):
			continue
		var provinces: int = _provinces(play, tribe)
		if provinces < 1:
			continue
		if provinces < best_provinces:
			best = tribe
			best_provinces = provinces
	return best


func _provinces(play: PlaySession, faction: int) -> int:
	return DiplomacyRules.provinces_owned(play.world, faction)


## Closes one real turn, answering any consent prompt the phase raises, and
## returns only once the calendar has actually moved — a suspended turn is the
## same turn, so its sheet would read as if nothing had been spent.
func _end_turn(play: PlaySession) -> void:
	var start_turn: int = play.turn
	for _attempt in 12:
		MapPlayTurn.end_turn(play)
		if play.turn != start_turn:
			return
		var human: int = play.player_faction
		if CallToArms.has_pending(play.diplomacy, human):
			MapCourtOrders.apply(play, CallToArms.KIND_REFUSE, human, "")
			continue
		if Intervention.has_pending(play.diplomacy, human):
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
			continue
		if DiplomacyProposals.has_pending(play.diplomacy, human):
			MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, human, "")
			continue
		return
	_say("the turn would not close")


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_colony: %d steps ---" % _steps.size())
	quit()
