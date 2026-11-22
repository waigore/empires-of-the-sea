extends SceneTree
## Headless free-playtest drive for THE COLONIES' gold counsel line — the Tribe
## the court's own envoy is drawing in this turn (wiki: diplomacy § GP–Tribe
## Rules — Join Empire; DR-20261121-16).
##
## The line is a reading of `AiTribeColony.best`, and it claims `the court would
## offer … this turn`. The drive holds that claim to the crown's own press: it
## seats a chain at each rung a late campaign reaches, opens THE COLONIES, reads
## the gold line, then presses the envoy's own overture row through
## `MapPlayDiplomacy.on_order` (the controller a tap reaches) and reads what the
## court answers. It also reads the diplomacy sheet's envoy counsel, the same
## pass's one order, so two sheets of one turn can be compared.
##
## Passes:
## 1. a pact with a court too cold for the Join Empire;
## 2. the same court warmed — the bond the press signs;
## 3. a second chain — the overture already made this turn;
## 4. a third chain — the study that holds the Embassy, then the honest link;
## 5. a fifth chain read on both sheets at once — a colony line may promise the
##    link only when the court's own one order (THE COURT's counsel) takes it,
##    and otherwise names the wait and the court that order went to
##    (DR-20261121-18).
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_colony_counsel.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const ADVANCED: String = AdvancedStart.TURNS100
## Below `DiplomacyCatalog.JOIN_EMPIRE_MIN_SCORE` (51) and above the pact's own
## floor: a court that holds a Non-Aggression Pact and is still too cold to be
## bought (wiki: diplomacy § Join Empire).
const COLD_SCORE: float = 40.0
const WARM_SCORE: float = 60.0
const WARMER_SCORE: float = 70.0

var _steps: PackedStringArray = PackedStringArray()
var _failures: int = 0
var _play: PlaySession = null
var _panel: ColonyLedgerPanel = null
## The Tribes this drive has spent, so the next pass seats a court whose envoy
## has not already been in.
var _used: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = await Launch.open_map(self, SEED_TEXT, 0, ADVANCED, 0)
	if screen == null:
		_finish()
		return
	_play = screen.play
	_say("seed %s — %s, turn %d, treasury %d" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		_play.treasury(),
	])
	var tribes: Array[int] = _tribes()
	_say("tribes in contact: %d" % tribes.size())
	if tribes.size() < 3:
		_say("three Tribes are needed for the drive's passes")
		_finish()
		return
	for tribe: int in tribes:
		# A common rung, so the deepest chain is always the one a pass seats.
		_play.diplomacy.set_overture(_play.player_faction, tribe, DiplomacyCatalog.STAGE_CONSULATE)
		_ensure_relation(tribe, DiplomacyCatalog.INITIAL_SCORE)
	_say("seated every contacted Tribe at a Trade Consulate, score %.0f" % (
		DiplomacyCatalog.INITIAL_SCORE
	))
	_open_sheet()
	_pass_cold_bond(tribes[0])
	_used.append(tribes[0])
	_pass_claim()
	_pass_study_and_link()
	_finish()


# --- 1. the pact with a court too cold to be bought --------------------------


func _pass_cold_bond(tribe: int) -> void:
	_say("")
	_say("--- 1. a Non-Aggression Pact with a cold %s ---" % FactionCatalog.name_of(tribe))
	_seat(tribe, COLD_SCORE, DiplomacyCatalog.STAGE_NAP)
	var pick: Dictionary = _read_counsel("at the pact, score %.0f" % COLD_SCORE)
	var row: Dictionary = _option(tribe, DiplomacyCatalog.STAGE_JOIN_EMPIRE)
	var refusal: String = String(row.get("reason", ""))
	_say("  the envoy row: %s%s" % [
		"on" if bool(row.get("ok", false)) else "off",
		"" if refusal.is_empty() else " — " + refusal,
	])
	_check(
		int(pick.get("target", -1)) == tribe,
		"the gold line names the deepest chain"
	)
	_check(
		String(pick.get("kind", "")) != MapPlayColonyPick.KIND_CHAIN,
		"the gold line promises no link the crown's own press refuses",
		"the gold line promises the Join Empire at score %.0f, where the envoy "
		% COLD_SCORE + "row is off"
	)
	_check(
		refusal.is_empty() or MapPlayPickProse.sentence(
			String(pick.get("line", ""))
		).contains(refusal.trim_suffix(".")),
		"the gold line names the reason the envoy row gives",
		"the gold line does not say why the press is off"
	)
	_press(tribe, DiplomacyCatalog.STAGE_JOIN_EMPIRE)
	_say("  press: %s" % _last_toast())
	_check(
		_play.diplomacy.colony_of(tribe) < 0,
		"no colony stands on a press the rule refuses",
		"a colony was bought at score %.0f" % COLD_SCORE
	)
	# 2. the same court warmed: the bond the press signs.
	_say("")
	_say("--- 2. the same %s warmed to %.0f ---" % [
		FactionCatalog.name_of(tribe), WARM_SCORE,
	])
	_ensure_relation(tribe, WARM_SCORE)
	var warm: Dictionary = _read_counsel("warmed, score %.0f" % WARM_SCORE)
	_check(
		String(warm.get("kind", "")) == MapPlayColonyPick.KIND_CHAIN,
		"a warm court reads the bond it can sign"
	)
	_press(tribe, DiplomacyCatalog.STAGE_JOIN_EMPIRE)
	_say("  press: %s" % _last_toast())
	_check(
		_play.diplomacy.colony_of(tribe) == _play.player_faction,
		"the warm bond the gold line named signs",
		"the warm court refuses the bond the gold line promised"
	)
	_check(
		int(warm.get("cost", 0)) > 0,
		"the pick prices the link it names (%d ducats)" % int(warm.get("cost", 0)),
		"the pick names a link with no price"
	)


# --- 3. the overture already made this turn ----------------------------------


func _pass_claim() -> void:
	_say("")
	var first: Dictionary = MapPlayColonyPick.pick(_play)
	var tribe: int = int(first.get("target", -1))
	if tribe < 0:
		_say("--- 3. no second chain is named, so the claim cannot be read ---")
		return
	_say("--- 3. a second chain: %s ---" % FactionCatalog.name_of(tribe))
	_seat(tribe, WARM_SCORE, DiplomacyCatalog.STAGE_EMBASSY)
	var before: Dictionary = _read_counsel("before the overture")
	var stage: String = String(before.get("stage", ""))
	if stage.is_empty():
		_say("  the gold line names no link — the claim cannot be read")
		return
	_check(
		bool(_option(tribe, stage).get("ok", false)),
		"the link the gold line names is on before the press (%s)"
		% DiplomacyCatalog.stage_label(stage),
		"the link the gold line names is off before the press"
	)
	_press(tribe, stage)
	_say("  press: %s" % _last_toast())
	_check(
		_play.diplomacy.overture(_play.player_faction, tribe) == stage,
		"the named link lands (%s)" % DiplomacyCatalog.stage_label(stage),
		"the press did not land the link the gold line named"
	)
	var after: Dictionary = _read_counsel("the same turn, after the press")
	var next_stage: String = DiplomacyCatalog.next_stage(
		_play.diplomacy.overture(_play.player_faction, tribe)
	)
	var again: Dictionary = _option(tribe, next_stage)
	var said: String = _refusal(tribe, next_stage)
	_say("  the second press this turn (%s): %s%s" % [
		DiplomacyCatalog.stage_label(next_stage),
		"on" if bool(again.get("ok", false)) else "off",
		"" if said.is_empty() else " — " + said,
	])
	_check(
		String(after.get("kind", "")) != MapPlayColonyPick.KIND_CHAIN,
		"the gold line names no link the same turn its chain already moved",
		"the gold line still promises an offer: " + said
	)
	_check(
		String(after.get("kind", "")) != MapPlayColonyPick.KIND_GATE
		or MapPlayPickProse.sentence(String(after.get("line", ""))).contains(
			said.trim_suffix(".")
		),
		"the gold line names the reason the second press is off",
		"the gold line does not say why the second press is off"
	)
	# Hand the Tribe back at the common rung, so the study pass names a court
	# whose envoy has not already been in.
	_seat(tribe, DiplomacyCatalog.INITIAL_SCORE, DiplomacyCatalog.STAGE_CONSULATE)
	_used.append(tribe)


# --- 4. the study that holds the chain, and the honest link ------------------


func _pass_study_and_link() -> void:
	_say("")
	var tribe: int = _unspent_tribe()
	if tribe < 0:
		_say("--- 4. no unspent Tribe is left in contact, so the study cannot be read ---")
		return
	_say("--- 4. a third chain: %s ---" % FactionCatalog.name_of(tribe))
	_seat(tribe, WARMER_SCORE, DiplomacyCatalog.STAGE_CONSULATE)
	_play.economy.economy.tech_unlocked.erase("diplomatic_expertise")
	var gated: Dictionary = _read_counsel("the Embassy's study stood down")
	_check(
		String(gated.get("kind", "")) == MapPlayColonyPick.KIND_STUDY,
		"a chain whose study is missing reads the door it owes",
		"a missing study reads as a link"
	)
	_play.economy.economy.tech_unlocked["diplomatic_expertise"] = 1
	var opened: Dictionary = _read_counsel("the study seated again")
	_check(
		String(opened.get("kind", "")) == MapPlayColonyPick.KIND_CHAIN,
		"the study in hand reads the link the court can press"
	)
	var stage: String = String(opened.get("stage", ""))
	_check(
		bool(_option(tribe, stage).get("ok", false)),
		"the link the gold line names is on (%s)" % DiplomacyCatalog.stage_label(stage),
		"the link the gold line names is off"
	)
	var cost: int = int(opened.get("cost", 0))
	_press(tribe, stage)
	_say("  press: %s" % _last_toast())
	_check(
		_play.diplomacy.overture(_play.player_faction, tribe) == stage,
		"the honest link lands",
		"the honest link does not land"
	)
	_say("  the link's price on the pick: %d ducats" % cost)
	_used.append(tribe)
	_pass_two_sheets()
	_pass_door()


# --- 5. two sheets, one turn --------------------------------------------------


## A chain the press can take, read on both sheets at once: the colony line may
## promise the link only when the court's own one order takes it, and otherwise
## names the wait and the court that order went to (DR-20261121-18).
func _pass_two_sheets() -> void:
	var tribe: int = _unspent_tribe()
	if tribe < 0:
		_say("")
		_say("--- 5. no unspent Tribe is left in contact, so the two sheets cannot be read ---")
		return
	_say("")
	_say("--- 5. two sheets, one turn: %s ---" % FactionCatalog.name_of(tribe))
	_seat(tribe, WARM_SCORE, DiplomacyCatalog.STAGE_NAP)
	var pick: Dictionary = _read_counsel("a chain the press can take")
	var action: Dictionary = MapPlayDiplomacyPick.plan(_play).get("action", {}) as Dictionary
	var wants: Dictionary = {
		"target": tribe,
		"stage": DiplomacyCatalog.next_stage(
			_play.diplomacy.overture(_play.player_faction, tribe)
		),
	}
	_say("  the envoy's own counsel: %s" % MapPlayPickProse.sentence_of(
		MapPlayDiplomacyPick.picks(_play).get(tribe, {}) as Dictionary
	))
	if MapPlayColonyPick.envoy_gives(action, wants):
		_check(
			String(pick.get("kind", "")) == MapPlayColonyPick.KIND_CHAIN,
			"the colony line promises the link the envoy's one order takes"
		)
		return
	_check(
		String(pick.get("kind", "")) == MapPlayColonyPick.KIND_ENVOY,
		"the colony line names the wait behind the envoy's one order",
		"the colony line promises a link the court's one order does not take"
	)
	var other: int = int(action.get("target", -1))
	if other >= 0:
		_check(
			MapPlayPickProse.sentence(String(pick.get("line", ""))).contains(
				FactionCatalog.name_of(other)
			),
			"the wait names the court the one order went to",
			"the wait does not say where the one order went"
		)


# --- 6. the door the line's own court answers ---------------------------------


## The sheet's door (DR-20261123-02): a Tribe the crown has not bought has no
## colony row, so the chain the gold line names is pressed on THE COURT — and the
## press under the line takes the crown there, stands the sheet it opened, and
## signs nothing.
func _pass_door() -> void:
	_say("")
	_say("--- 6. the door the gold line's own court answers ---")
	_open_sheet()
	var pick: Dictionary = _read_counsel("the reading the door follows")
	var court: int = MapPlayColonyPick.door(pick)
	if court < 0:
		_say("  the line names no court, so the door cannot be read")
		return
	_say("  the door names: %s" % FactionCatalog.name_of(court))
	var press: Button = _panel.follow_press()
	_check(press != null, "the sheet carries the door")
	if press == null:
		return
	_check(press.visible, "the door stands while the line names a court")
	_check(_panel.door_court() == court, "the door names the court the line names")
	_check(
		MapPlayDiplomacy.can_open_court(_play.diplomacy, _play.player_faction, court),
		"the crown is in contact with the court the door names"
	)
	var treasury: int = _play.treasury()
	var overture: String = _play.diplomacy.overture(_play.player_faction, court)
	press.pressed.emit()
	_check(
		_play.hud.panels.is_diplomacy_open(), "the door opens THE COURT",
		"the door left no court sheet open"
	)
	_check(
		_play.hud.panels.diplomacy_panel.selected_faction() == court,
		"THE COURT stands on the court the line named",
		"THE COURT stands on another court"
	)
	_check(not _panel.is_open(), "the colony sheet steps aside for it")
	_say("  THE COURT on %s: %s" % [
		FactionCatalog.name_of(court),
		_play.hud.panels.diplomacy_panel.counsel_text(),
	])
	_check(
		_play.diplomacy.overture(_play.player_faction, court) == overture
		and _play.diplomacy.colony_of(court) < 0,
		"the door signs and buys nothing",
		"the door moved the chain it named"
	)
	_check(_play.treasury() == treasury, "the door spends nothing")
	DiplomacyHud.hide(_play.hud.panels)


# --- the sheet ---------------------------------------------------------------


func _open_sheet() -> void:
	if _panel == null or not _panel.is_open():
		HudLedgerDoors.open(_play.hud, HudLedgerDoors.COLONIES)
	_panel = _play.hud.colonies_ledger
	if _panel == null:
		_say("no colonies sheet is mounted")
		return
	_panel.refresh()


## The gold line as the open sheet paints it, plus the pick behind it and the
## envoy's one order the pick is now held to (DR-20261121-18).
func _read_counsel(when: String) -> Dictionary:
	_say("  --- %s ---" % when)
	if _panel != null:
		_panel.refresh()
		_say("    gold: %s" % _panel.counsel_text())
	else:
		_say("    gold: %s" % MapPlayColonyPick.line(_play))
	_say_one_order()
	return MapPlayColonyPick.pick(_play)


## THE COURT's own counsel: where the crown's one envoy order goes this turn.
func _say_one_order() -> void:
	var action: Dictionary = MapPlayDiplomacyPick.plan(_play).get("action", {}) as Dictionary
	if action.is_empty():
		_say("    the envoy's one order: none this turn")
		return
	var target: int = int(action.get("target", -1))
	_say("    the envoy's one order: %s %s" % [
		String(action.get("kind", "")),
		"nowhere" if target < 0 else FactionCatalog.name_of(target),
	])


# --- seating -----------------------------------------------------------------


func _seat(tribe: int, score: float, stage: String) -> void:
	_ensure_relation(tribe, score)
	_play.diplomacy.set_overture(_play.player_faction, tribe, stage)


func _ensure_relation(tribe: int, score: float) -> void:
	var player: int = _play.player_faction
	if not _play.diplomacy.has_relation(player, tribe):
		_play.diplomacy.ensure_relation(player, tribe, _play.turn)
	_play.diplomacy.relation(player, tribe).score = score
	if _play.diplomacy.relation(tribe, player) != null:
		_play.diplomacy.relation(tribe, player).score = score


# --- pressing ----------------------------------------------------------------


func _option(tribe: int, stage: String) -> Dictionary:
	if stage.is_empty():
		return {}
	var options: Array[Dictionary] = DiplomacyOrders.options(
		_play.diplomacy, _play.world, _play.treasury(), _play.player_faction, tribe,
		_play.economy.economy.tech_unlocked
	)
	var label: String = "Offer " + DiplomacyCatalog.stage_label(stage)
	for option: Dictionary in options:
		if String(option.get("label", "")) == label:
			return option
	_say("  no \"%s\" row among %d offers" % [label, options.size()])
	return {}


## The rule's own answer to a press, so a pass can hold the gold line to it.
func _refusal(tribe: int, stage: String) -> String:
	if stage.is_empty():
		return ""
	var gate: Dictionary = DiplomacyRules.can_establish_overture(
		_play.diplomacy, _play.world, _play.player_faction, tribe, stage,
		_play.treasury(), _play.economy.economy.tech_unlocked
	)
	return "" if bool(gate.get("ok", false)) else String(gate.get("reason", ""))


func _press(tribe: int, stage: String) -> void:
	MapPlayDiplomacy.on_order(_play, DiplomacyOrders.KIND_OVERTURE, tribe, stage)


# --- reading -----------------------------------------------------------------


## The first contacted Tribe this drive has not seated a chain with.
func _unspent_tribe() -> int:
	for tribe: int in _tribes():
		if not _used.has(tribe):
			return tribe
	return -1


func _tribes() -> Array[int]:
	var out: Array[int] = []
	for tribe: int in FactionCatalog.tribe_ids():
		if not _play.diplomacy.has_relation(_play.player_faction, tribe):
			continue
		if DiplomacyRules.provinces_owned(_play.world, tribe) < 1:
			continue
		if _play.diplomacy.colony_of(tribe) >= 0:
			continue
		var record: DiplomacyRelation = _play.diplomacy.relation(
			_play.player_faction, tribe
		)
		if record == null or record.at_war:
			continue
		if not AiTribeColony.charted(
			_play.world, _play.court_charts, _play.player_faction, tribe
		):
			continue
		out.append(tribe)
	return out


func _last_toast() -> String:
	var despatches: HudDespatches = _play.hud.despatches
	if despatches == null:
		return "no despatch"
	var waiting: PackedStringArray = despatches.waiting()
	if not waiting.is_empty():
		return waiting[waiting.size() - 1]
	return ""


func _say(text: String) -> void:
	_steps.append(text)
	print(text)


func _check(ok: bool, said: String, broken: String = "") -> void:
	if ok:
		_say("    ok: " + said)
		return
	_failures += 1
	_say("    FAIL: " + (broken if not broken.is_empty() else said))


func _finish() -> void:
	print("\n--- playtest_colony_counsel: %d steps, %d failed ---" % [
		_steps.size(), _failures,
	])
	quit(1 if _failures > 0 else 0)
