extends SceneTree
## Headless playtest drive for the court's third consent decision: a rival's
## proposal (wiki: diplomacy § GP AI policy — court hand-off; dialogue-and-mood
## § Mood machine). A call to arms and an intervention already have a drive
## (`playtest_allied_defence`); an offer answered at the court, and the same
## offer waiting while the campaign is saved, do not.
##
## The drive plays **England**, not Spain: the catalog's player slot (0) is
## Spain, so a court bug that reads a defaulted faction instead of the crown the
## session resumes as is invisible in every Spain-only drive.
##
##   godot --headless --path . --script res://tests/playtest_court_proposal.gd
##
## Every answer is pressed on the banner's own button, so the drive walks the
## panel's intent path, the router and the turn resolver, and it reads what a
## player reads: the consent banner, its buttons, the despatch and the court's
## pair line. A flow change fails the drive (non-zero exit) instead of printing
## a number nobody compares.

const Launch = preload("res://tests/playtest_launch.gd")
const SaveDrive = preload("res://tests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
## England: a Great Power that is not FactionCatalog.PLAYER_FACTION.
const NATION: int = 1
const DIR: String = "user://playtest_court_proposal"
const SLOT: int = 1
## Goodwill a court needs before a rival puts an alliance or a pact to it.
const FRIENDLY_SCORE: float = 70.0

var _steps: PackedStringArray = PackedStringArray()
var _failures: int = 0
var _screen: MapScreen = null
var _play: PlaySession = null
var _main: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveDrive.clean_dir(DIR)
	_screen = await Launch.open_map(self, SEED_TEXT, 0, "", NATION)
	if _screen == null:
		_finish()
		return
	_main = _screen.get_parent()
	_screen.save_dir = DIR
	_play = _screen.play
	_say("seed %s — %s (faction %d), turn %d, treasury %d" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.player_faction,
		_play.turn, _play.treasury(),
	])
	_say("the court answers for faction %d" % _play.diplomacy.human_faction)
	var rivals: Array[int] = []
	for gp: int in FactionCatalog.great_power_ids():
		if gp != _play.player_faction:
			rivals.append(gp)
	if rivals.size() < 4:
		_say("need four rival Great Powers")
		_finish()
		return
	_peace_pass(rivals[0])
	_alliance_pass(rivals[1])
	_ftp_pass(rivals[2])
	_nap_pass(rivals[4])
	await _save_pass(rivals[3], rivals[1], rivals[2])
	_finish()


# --- passes ----------------------------------------------------------------


## A white peace the rival puts to the court: the calendar stops, the court
## opens on the banner, and the court's own Accept button signs it and closes
## the turn (wiki: diplomacy § GP–GP Rules — peace needs both sides).
func _peace_pass(rival: int) -> void:
	_say("")
	_say("--- %s offers a white peace ---" % FactionCatalog.name_of(rival))
	DiplomacyRules.declare_war(_play.diplomacy, _play.player_faction, rival)
	_check("the court is at war", _relation(rival).at_war)
	var queued: Dictionary = DiplomacyProposals.queue(
		_play.diplomacy, _play.world, rival, DiplomacyProposals.KIND_PEACE
	)
	_check("the rival's offer waits", bool(queued.get("ok", false)))
	var turn_before: int = _play.turn
	MapPlayTurn.end_turn(_play)
	_check("the offer suspends the calendar", _play.turn_suspended)
	_check("the court opens on the offer", _play.hud.panels.is_diplomacy_open())
	_check("the turn did not close", _play.turn == turn_before)
	_read_banner()
	_check("the banner offers both answers", _buttons_has("Accept") and _buttons_has("Refuse"))
	_press("Accept")
	_say("after Accept: at war %s, turn %d -> %d, banner %s" % [
		str(_relation(rival).at_war), turn_before, _play.turn, _banner_text(),
	])
	_check("accepting signs the peace", not _relation(rival).at_war)
	_check("the answered offer leaves the banner", _banner_text().is_empty())
	_check("the answer closes the waiting turn", _play.turn > turn_before)
	_check("the calendar runs again", not _play.turn_suspended)
	_check("the court returns to the ledger", _play.hud.panels.is_diplomacy_open())
	_say("despatch: %s" % _toast())
	_say("court pair with %s: %s" % [FactionCatalog.name_of(rival), _stand(rival)])
	_say("court chronicle with %s: %s" % [FactionCatalog.name_of(rival), _court_chronicle(rival)])
	_drain_plates()


## A formal alliance the rival puts to the court: accepting binds both crowns,
## so the prompt must say what it is and the treaty must land on this crown.
func _alliance_pass(rival: int) -> void:
	_say("")
	_say("--- %s proposes a formal alliance ---" % FactionCatalog.name_of(rival))
	_relation(rival).score = FRIENDLY_SCORE
	var queued: Dictionary = DiplomacyProposals.queue(
		_play.diplomacy, _play.world, rival, DiplomacyProposals.KIND_ALLIANCE
	)
	_check("the alliance offer waits", bool(queued.get("ok", false)))
	var turn_before: int = _play.turn
	MapPlayTurn.end_turn(_play)
	_read_banner()
	_press("Accept")
	_say("after Accept: allied %s, turn %d -> %d" % [
		str(_relation(rival).formal_alliance), turn_before, _play.turn,
	])
	_check("accepting binds the alliance", _relation(rival).formal_alliance)
	_check("the answer closes the waiting turn", _play.turn > turn_before)
	_say("despatch: %s" % _toast())
	_say("court chronicle with %s: %s" % [FactionCatalog.name_of(rival), _court_chronicle(rival)])
	_drain_plates()


## A favoured trading pact: the pact changes what the court pays for that
## court's goods, so the prompt a player answers has to carry the terms
## (wiki: world-market § FTP; diplomacy § Trade terms).
func _ftp_pass(rival: int) -> void:
	_say("")
	_say("--- %s proposes a favoured trading pact ---" % FactionCatalog.name_of(rival))
	_relation(rival).score = FRIENDLY_SCORE
	var queued: Dictionary = DiplomacyProposals.queue(
		_play.diplomacy, _play.world, rival, DiplomacyProposals.KIND_FTP
	)
	_check("the pact offer waits", bool(queued.get("ok", false)))
	var turn_before: int = _play.turn
	MapPlayTurn.end_turn(_play)
	_read_banner()
	var terms_line: String = _banner_text()
	_check("the pact's prompt names its rate", terms_line.contains("95%") and terms_line.contains("105%"))
	_check("the pact's prompt carries the envoy's word", terms_line.contains("“"))
	_press("Accept")
	_say("after Accept: pact %s, turn %d -> %d" % [
		str(DiplomacyTrade.is_ftp(_play.diplomacy, _play.player_faction, rival)),
		turn_before, _play.turn,
	])
	_check(
		"accepting signs the pact",
		DiplomacyTrade.is_ftp(_play.diplomacy, _play.player_faction, rival)
	)
	_check("the answer closes the waiting turn", _play.turn > turn_before)
	_say("despatch: %s" % _toast())
	_say("the ledger's terms after the pact: %s" % _terms())
	_drain_plates()


## A Non-Aggression Pact: the one overture stage a rival offers while its
## treasury is untracked, so accepting must land the stage and leave the human
## purse untouched — the proposing rival pays (wiki: diplomacy § Court
## proposals; § GP–GP Rules).
func _nap_pass(rival: int) -> void:
	_say("")
	_say("--- %s proposes the Non-Aggression Pact ---" % FactionCatalog.name_of(rival))
	_relation(rival).score = FRIENDLY_SCORE
	var queued: Dictionary = DiplomacyProposals.queue(
		_play.diplomacy, _play.world, rival, DiplomacyProposals.KIND_OVERTURE,
		DiplomacyCatalog.STAGE_NAP
	)
	_check("the pact overture waits", bool(queued.get("ok", false)))
	var turn_before: int = _play.turn
	var purse_before: int = _play.treasury()
	MapPlayTurn.end_turn(_play)
	_read_banner()
	_check(
		"the pact's prompt never promises the stage beside it",
		not _banner_text().to_lower().contains("consul")
	)
	_press("Accept")
	var stage: String = _play.diplomacy.overture(_play.player_faction, rival)
	_say("after Accept: overture %s, purse %d -> %d, turn %d -> %d" % [
		stage, purse_before, _play.treasury(), turn_before, _play.turn,
	])
	_check("accepting signs the pact overture", stage == DiplomacyCatalog.STAGE_NAP)
	_check("the proposing court pays, not the court that answers", _play.treasury() == purse_before)
	_check("the answer closes the waiting turn", _play.turn > turn_before)
	_say("despatch: %s" % _toast())
	_say("court pair with %s: %s" % [FactionCatalog.name_of(rival), _stand(rival)])
	_drain_plates()


## The offer a save carries: the campaign is written while the court waits, and
## the loaded session must ask the same question of the same crown and land the
## answer on it. Then a declaration on the crown's ally must still reach the
## court, since consent lives in the restored ledger (wiki: campaign-persistence
## § Load and resume; diplomacy § Alliances § Mutual defence).
func _save_pass(rival: int, ally: int, aggressor: int) -> void:
	_say("")
	_say("--- a waiting offer, saved and reloaded ---")
	DiplomacyRules.declare_war(_play.diplomacy, _play.player_faction, rival)
	var queued: Dictionary = DiplomacyProposals.queue(
		_play.diplomacy, _play.world, rival, DiplomacyProposals.KIND_PEACE
	)
	_check("the rival's offer waits", bool(queued.get("ok", false)))
	MapPlayTurn.end_turn(_play)
	var waiting: String = _banner_text()
	var turn_before: int = _play.turn
	_say("saved while the court waits: suspended %s, turn %d, banner '%s'" % [
		str(_play.turn_suspended), _play.turn, waiting,
	])
	_check("the offer suspends the calendar", _play.turn_suspended)
	_say("save: '%s'" % SaveDrive.save_slot(_screen, SLOT))
	_screen = SaveDrive.load_slot(_screen, _main, SLOT)
	if _screen == null:
		_say("the load replaced the screen with something else")
		_check("the slot reloads", false)
		_finish()
		return
	_play = _screen.play
	await process_frame
	_say("after the load: %s (faction %d), court answers for %d, turn %d, suspended %s" % [
		FactionCatalog.name_of(_play.player_faction), _play.player_faction,
		_play.diplomacy.human_faction, _play.turn, str(_play.turn_suspended),
	])
	_say("court open: %s, pending offers %d" % [
		str(_play.hud.panels.is_diplomacy_open()), _play.diplomacy.pending_offers.size(),
	])
	_check("the loaded court answers for this crown", _play.diplomacy.human_faction == _play.player_faction)
	_check("the waiting offer comes back", _play.diplomacy.pending_offers.size() == 1)
	_check("the loaded turn is still suspended", _play.turn_suspended)
	_check("the court reopens on the offer", _play.hud.panels.is_diplomacy_open())
	_say("banner after the load: '%s'" % _banner_text())
	_check("the banner comes back unchanged", _banner_text() == waiting)
	_say("despatch after the load: %s" % _toast())
	_press("Accept")
	_say("after Accept: at war %s, turn %d -> %d, banner %s" % [
		str(_relation(rival).at_war), turn_before, _play.turn, _banner_text(),
	])
	_check("the answer lands on the crown that was asked", not _relation(rival).at_war)
	_check("the loaded answer closes the waiting turn", _play.turn > turn_before)
	_drain_plates()

	# Consent is not only the offer queue: the same ledger decides whether an
	# ally's war is put to the court. A restored campaign must still ask.
	_say("")
	_say("--- after the load: %s declares war on the court's ally %s ---" % [
		FactionCatalog.name_of(aggressor), FactionCatalog.name_of(ally),
	])
	_check("the ally is bound by treaty", _relation(ally).formal_alliance)
	CallToArms.freeze_alliances(_play.diplomacy)
	var war: Dictionary = DiplomacyRules.declare_war(_play.diplomacy, aggressor, ally)
	_say("declaration: ok %s, news %s, calls waiting %d" % [
		str(war.get("ok", false)), str(war.get("calls", [])),
		_play.diplomacy.pending_calls.size(),
	])
	_check("a declaration on the ally still reaches the court", _play.diplomacy.pending_calls.size() == 1)
	MapPlayTurn.end_turn(_play)
	_read_banner()
	_check("the call suspends the restored calendar", _play.turn_suspended)
	if _buttons_has("Join the war"):
		_press("Join the war")
		_say("joined: at war with %s %s, suspended %s" % [
			FactionCatalog.name_of(aggressor), str(_relation(aggressor).at_war),
			str(_play.turn_suspended),
		])
		_check("joining the call starts the war", _relation(aggressor).at_war)
		_check("the answer runs the restored turn", not _play.turn_suspended)
	_drain_plates()


# --- reads -----------------------------------------------------------------


## What the court shows above its ledger: caption, the envoy's proposal and its
## own words, and every button.
func _read_banner() -> void:
	var text: String = _banner_text()
	if text.is_empty():
		_say("banner: none")
		return
	_say("banner: %s" % text)
	_say("banner buttons: %s" % _banner_buttons())
	_say("despatch: %s" % _toast())


## The trade terms the ledger publishes for the court, as the market reads them.
func _terms() -> String:
	var terms: Dictionary = DiplomacyTrade.terms_for_court(
		_play.diplomacy, _play.world, _play.player_faction
	)
	var buy: Dictionary = terms.get("buy", {})
	var sell: Dictionary = terms.get("sell", {})
	return "imports %d%%, exports %d%%" % [
		roundi(float(buy.get("*", 1.0)) * 100.0),
		roundi(float(sell.get("*", 1.0)) * 100.0),
	]


# --- presses ---------------------------------------------------------------


## Presses a button of the consent banner by its label, as the player would.
func _press(label: String) -> bool:
	var button: Button = _find_button(label)
	if button == null:
		_say("no '%s' button in the banner" % label)
		_check("the banner offers '%s'" % label, false)
		return false
	button.emit_signal("pressed")
	return true


func _find_button(label: String) -> Button:
	var box: VBoxContainer = _call_box()
	if box == null:
		return null
	var found: Array[Button] = []
	_collect_buttons(box, found)
	for button: Button in found:
		if button.text == label:
			return button
	return null


func _buttons_has(label: String) -> bool:
	return _find_button(label) != null


# --- text plumbing ---------------------------------------------------------


func _call_box() -> VBoxContainer:
	if _play == null or _play.hud == null or _play.hud._diplomacy_panel == null:
		return null
	return _play.hud._diplomacy_panel._call_box


## Every label in the consent banner, top to bottom.
func _banner_text() -> String:
	var box: VBoxContainer = _call_box()
	if box == null or not box.visible or box.get_child_count() == 0:
		return ""
	var parts: PackedStringArray = []
	_collect_labels(box, parts)
	return " / ".join(parts)


func _banner_buttons() -> String:
	var box: VBoxContainer = _call_box()
	if box == null:
		return "none"
	var found: Array[Button] = []
	_collect_buttons(box, found)
	var parts: PackedStringArray = []
	for button: Button in found:
		parts.append("%s%s" % [button.text, "" if not button.disabled else " (disabled)"])
	return ", ".join(parts) if not parts.is_empty() else "none"


func _collect_labels(node: Node, into: PackedStringArray) -> void:
	if node is Label:
		var label: Label = node
		if label.visible and not label.text.is_empty():
			into.append(label.text)
	for child: Node in node.get_children():
		_collect_labels(child, into)


func _collect_buttons(node: Node, into: Array[Button]) -> void:
	if node is Button:
		into.append(node as Button)
	for child: Node in node.get_children():
		_collect_buttons(child, into)


func _toast() -> String:
	if _play == null or _play.hud == null or _play.hud._toast_box == null:
		return "none"
	var parts: PackedStringArray = []
	_collect_labels(_play.hud._toast_box, parts)
	return parts[parts.size() - 1] if not parts.is_empty() else "none"


## The lines the court's own chronicle shows for a pair, newest first — the
## record the panel draws, not the raw log behind it (wiki: diplomacy § The
## court chronicle).
func _court_chronicle(other: int) -> String:
	var panel: DiplomacyPanel = _play.hud._diplomacy_panel
	if panel == null or panel._detail == null:
		return "no court sheet"
	panel.select_faction(other)
	var labels: PackedStringArray = []
	_collect_labels(panel._detail, labels)
	var lines: PackedStringArray = []
	for label: String in labels:
		if label.begins_with("Year "):
			lines.append(label)
	return " | ".join(lines) if not lines.is_empty() else "none"


func _relation(other: int) -> DiplomacyRelation:
	return _play.diplomacy.relation(_play.player_faction, other)


func _stand(other: int) -> String:
	var record: DiplomacyRelation = _relation(other)
	if record == null:
		return "no envoy"
	return "%s %.1f%s%s" % [
		"war" if record.at_war else "peace", record.score,
		", allied" if record.formal_alliance else "",
		", pact" if DiplomacyTrade.is_ftp(
			_play.diplomacy, _play.player_faction, other
		) else "",
	]


# --- turn plumbing ---------------------------------------------------------


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


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _check(label: String, held: bool) -> void:
	if held:
		_say("  ok   %s" % label)
		return
	_failures += 1
	_say("  FAIL %s" % label)


func _finish() -> void:
	print("\\n--- playtest_court_proposal: %d steps ---" % _steps.size())
	print("RESULT: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)