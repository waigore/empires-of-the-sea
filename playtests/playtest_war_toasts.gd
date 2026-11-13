extends SceneTree
## Headless repro for bogus / duplicated war-declaration toasts on turn close
## (GitHub #426). Ends several real turns, then compares HUD war lines to the
## diplomacy chronicle and live At War flags. Not a CI gate:
##   godot --headless --path . --script res://playtests/playtest_war_toasts.gd
##   # or: tools/run.sh --script res://playtests/playtest_war_toasts.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
const ADVANCED: String = "turns100"
const TURNS: int = 8
const SPY: String = "spy"

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _dup_turns: int = 0
var _toast_only_turns: int = 0
var _war_toast_total: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX, ADVANCED)
	if _screen == null:
		_finish(1)
		return
	var play: PlaySession = _screen.play
	_say("seed %s · %s · start turn %d · player %s" % [
		SEED_TEXT, ADVANCED, play.turn, FactionCatalog.name_of(play.player_faction),
	])
	_seat_spies(play)
	_forced_double_channel(play)
	for _i in TURNS:
		await _one_turn(play)
	_say("")
	_say("--- summary ---")
	_say("war-related toast lines across drive: %d" % _war_toast_total)
	_say("turns with duplicate war wording (AI toast + spy/other): %d" % _dup_turns)
	_say("turns with war toast but no new warDeclared that turn: %d" % _toast_only_turns)
	_finish(0 if _dup_turns > 0 or _toast_only_turns > 0 or _war_toast_total > 0 else 1)


## Put a crown spy on every rival Great Power that has land, so spy despatches
## fire when those courts act (the second toast channel in #426).
func _seat_spies(play: PlaySession) -> void:
	var player: int = play.player_faction
	var spies: Array[CivilianState] = []
	for unit: CivilianState in play.civilian_layer.units:
		if unit.owner == player and unit.type_id == SPY:
			spies.append(unit)
	_say("spies on roster: %d" % spies.size())
	var seat: int = 0
	for faction: int in FactionCatalog.great_power_ids():
		if faction == player:
			continue
		var tile: Vector2i = _any_land(play, faction)
		if tile == CivilianState.NO_TILE:
			continue
		var spy: CivilianState = null
		if seat < spies.size():
			spy = spies[seat]
		else:
			spy = play.civilian_layer.add_unit(player, SPY, tile)
			spies.append(spy)
		spy.tile = tile
		spy.moved = true
		seat += 1
		_say("  spy on %s @ %s" % [
			FactionCatalog.name_of(faction), play.model.province_name(
				play.model.province_at(tile.x, tile.y)
			),
		])


## Controlled micro-repro: one real declare_war toast path + spy report from the
## same ai_trace action, without waiting for the planner.
func _forced_double_channel(play: PlaySession) -> void:
	_say("")
	_say("--- forced double-channel (AI toast + spy rewrite) ---")
	var player: int = play.player_faction
	var rival: int = -1
	var target: int = -1
	for gp: int in FactionCatalog.great_power_ids():
		if gp == player:
			continue
		if rival < 0:
			rival = gp
			continue
		target = gp
		break
	if rival < 0 or target < 0:
		_say("need two rival GPs")
		return
	if not play.diplomacy.has_relation(rival, target):
		play.diplomacy.ensure_relation(rival, target)
	var before_war: bool = play.diplomacy.relation(rival, target).at_war
	_clear_toasts()
	var war: Dictionary = DiplomacyRules.declare_war(play.diplomacy, rival, target, false)
	play.ai_trace = [{
		"faction": rival,
		"action": {"kind": AiDiplomacyPlanner.KIND_DECLARE_WAR, "target": target},
		"result": war,
		"message": String(war.get("message", "")),
	}]
	if play.hud != null and bool(war.get("ok", false)):
		play.hud.toast(String(war.get("message", "")))
	MapPlaySpies.report(play, [], [], {})
	var toasts: Array[String] = _war_toasts()
	_say("declare_war ok=%s (was at_war=%s, now=%s)" % [
		str(bool(war.get("ok", false))), str(before_war),
		str(play.diplomacy.relation(rival, target).at_war),
	])
	_say("message from rules: %s" % String(war.get("message", "")))
	for line: String in toasts:
		_say("  toast: %s" % line)
	_war_toast_total += toasts.size()
	if toasts.size() >= 2:
		_dup_turns += 1
		_say("EVIDENCE: same declaration surfaced %d times (diplomacy toast + spy report)" % toasts.size())
	# Restore peace so the multi-turn pass starts clean for this pair.
	if bool(war.get("ok", false)):
		play.diplomacy.relation(rival, target).at_war = false


func _one_turn(play: PlaySession) -> void:
	var turn_before: int = play.turn
	var events_before: int = play.diplomacy.events.size()
	_say("")
	_say("--- end turn %d ---" % turn_before)
	_clear_toasts()
	await process_frame
	_run_turn(play)
	await process_frame
	var resolved: int = maxi(play.turn - 1, 1)
	var toasts: Array[String] = _war_toasts()
	_war_toast_total += toasts.size()
	var declared: Array[Dictionary] = _war_events_since(play, events_before, resolved)
	_say("calendar: %d -> %d · war toasts: %d · new warDeclared (turn %d): %d" % [
		turn_before, play.turn, toasts.size(), resolved, declared.size(),
	])
	_say("  ai_trace declare_war rows this turn:")
	for row: Dictionary in _trace_wars(play):
		_say("    %s -> %s · ok=%s · message=%s" % [
			FactionCatalog.name_of(int(row["faction"])),
			FactionCatalog.name_of(int(row["target"])),
			str(bool(row["ok"])), String(row["message"]),
		])
	for line: String in toasts:
		_say("  toast: %s" % line)
	for event: Dictionary in declared:
		_say("  chronicle: %s declared war on %s (turn %d)" % [
			FactionCatalog.name_of(int(event.get("a", -1))),
			FactionCatalog.name_of(int(event.get("b", -1))),
			int(event.get("turn", -1)),
		])
	_say("  live At War for toast-named GP pairs:")
	var seen_pair: Dictionary = {}
	for line: String in toasts:
		_note_pairs_from_toast(play, line, seen_pair)
	if seen_pair.is_empty() and not toasts.is_empty():
		_say("    (could not parse faction names from toasts)")
	var dup: bool = _has_duplicate_wording(toasts)
	if dup:
		_dup_turns += 1
		_say("EVIDENCE: duplicate war wording in one turn's toast list")
	var bogus_replay: Array[String] = _replay_toasts(toasts, declared, play)
	if not bogus_replay.is_empty():
		_toast_only_turns += 1
		_say("EVIDENCE: %d war toast(s) with no matching new warDeclared this turn:" % bogus_replay.size())
		for line: String in bogus_replay:
			_say("    bogus: %s" % line)
	elif not toasts.is_empty() and declared.is_empty() and not _toasts_only_consent(toasts):
		_toast_only_turns += 1
		_say("EVIDENCE: war toast(s) with no new warDeclared event for resolved turn %d" % resolved)


func _run_turn(play: PlaySession) -> void:
	var turn: int = play.turn
	MapPlayTurn.end_turn(play)
	var guard: int = 0
	while play.turn == turn and not play.campaign_over() and guard < 16:
		guard += 1
		if CallToArms.has_pending(play.diplomacy, play.player_faction):
			_say("  consent: call to arms — refused")
			MapPlayTurn.answer_call(play, false)
		elif Intervention.has_pending(play.diplomacy, play.player_faction):
			_say("  consent: intervention — stood aside")
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
			_say("  consent: proposal — refused")
			MapPlayTurn.answer_offer(play, false)
		else:
			break


func _war_events_since(play: PlaySession, from_index: int, turn: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var events: Array = play.diplomacy.events
	for index in range(maxi(from_index, 0), events.size()):
		var event: Dictionary = events[index]
		if String(event.get("kind", "")) != "warDeclared":
			continue
		if int(event.get("turn", -1)) != turn:
			continue
		out.append(event)
	return out


func _war_toasts() -> Array[String]:
	var out: Array[String] = []
	if _screen == null or _screen.play == null or _screen.play.hud == null:
		return out
	for panel: Node in _screen.play.hud._toast_box.get_children():
		for text: String in _labels(panel):
			var lower: String = text.to_lower()
			if (
				lower.contains("declares war")
				or lower.contains("declared war")
				or lower.contains("war is proclaimed")
				or lower.contains("thrown down the glove")
				or lower.contains("cast the glove")
			):
				out.append(text)
	return out


func _toasts_only_consent(toasts: Array[String]) -> bool:
	for line: String in toasts:
		var lower: String = line.to_lower()
		if lower.contains("calls on our alliance"):
			continue
		if lower.contains("has declared war on") and (
			lower.contains("embassy") or lower.contains("deed") or lower.contains("intervene")
		):
			continue
		return false
	return not toasts.is_empty()


func _has_duplicate_wording(toasts: Array[String]) -> bool:
	var seen: Dictionary = {}
	for line: String in toasts:
		var key: String = line.to_lower().replace("spy report — ", "")
		# Collapse "England declares war on France." vs spy-prefixed same claim.
		var needle: String = key
		var idx: int = key.find("declares war")
		if idx >= 0:
			needle = key.substr(idx)
		elif key.find("declared war") >= 0:
			needle = key.substr(key.find("declared war"))
		if seen.has(needle):
			return true
		seen[needle] = true
	return false


func _note_pairs_from_toast(play: PlaySession, line: String, seen: Dictionary) -> void:
	for a: int in FactionCatalog.great_power_ids():
		var an: String = FactionCatalog.name_of(a)
		if not line.contains(an):
			continue
		for b: int in FactionCatalog.great_power_ids():
			if a == b:
				continue
			var bn: String = FactionCatalog.name_of(b)
			if not line.contains(bn):
				continue
			var key: String = play.diplomacy.pair_key(a, b)
			if seen.has(key):
				continue
			seen[key] = true
			var record: DiplomacyRelation = play.diplomacy.relation(a, b)
			var standing: String = "no relation"
			if record != null:
				standing = "At War" if record.at_war else "At Peace"
			_say("    %s ↔ %s: %s" % [an, bn, standing])


func _any_land(play: PlaySession, owner: int) -> Vector2i:
	for y in play.model.height:
		for x in play.model.width:
			if play.model.owner_at(x, y) == owner and play.model.is_land(x, y):
				return Vector2i(x, y)
	return CivilianState.NO_TILE


func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child: Node in node.get_children():
		var label: Label = child as Label
		if label != null and not label.text.is_empty():
			out.append(label.text)
		out.append_array(_labels(child))
	return out


func _trace_wars(play: PlaySession) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Dictionary in play.ai_trace:
		var action: Dictionary = raw.get("action", {}) as Dictionary
		if String(action.get("kind", "")) != AiDiplomacyPlanner.KIND_DECLARE_WAR:
			continue
		var result: Dictionary = raw.get("result", {}) as Dictionary
		out.append({
			"faction": int(raw.get("faction", -1)),
			"target": int(action.get("target", -1)),
			"ok": bool(result.get("ok", false)),
			"message": String(raw.get("message", "")),
		})
	return out


## Toast lines that claim a declaration but do not match a warDeclared event
## recorded for the resolved turn (spy rewrite of a failed/old act, or a stale
## plate). Consent banners that name a stake are excluded.
func _replay_toasts(
	toasts: Array[String], declared: Array[Dictionary], play: PlaySession
) -> Array[String]:
	var keys: Dictionary = {}
	for event: Dictionary in declared:
		keys[_pair_names(int(event.get("a", -1)), int(event.get("b", -1)))] = true
	var out: Array[String] = []
	for line: String in toasts:
		var lower: String = line.to_lower()
		if lower.contains("embassy") or lower.contains("deed") or lower.contains("intervene"):
			continue
		if lower.contains("calls on our alliance"):
			continue
		if not (lower.contains("declares war") or lower.contains("declared war")):
			continue
		var matched: bool = false
		for key: Variant in keys.keys():
			var parts: PackedStringArray = String(key).split("|")
			if parts.size() != 2:
				continue
			if line.contains(parts[0]) and line.contains(parts[1]):
				matched = true
				break
		if not matched:
			out.append(line)
	return out


func _pair_names(a: int, b: int) -> String:
	var left: String = FactionCatalog.name_of(mini(a, b))
	var right: String = FactionCatalog.name_of(maxi(a, b))
	# Order-independent key using catalog names as they appear in toasts.
	var an: String = FactionCatalog.name_of(a)
	var bn: String = FactionCatalog.name_of(b)
	if an < bn:
		return "%s|%s" % [an, bn]
	return "%s|%s" % [bn, an]


func _clear_toasts() -> void:
	if _screen == null or _screen.play == null or _screen.play.hud == null:
		return
	# Free immediately so the next sample does not count fading plates from the
	# previous turn (queue_free is deferred one frame).
	var box: Node = _screen.play.hud._toast_box
	while box.get_child_count() > 0:
		var child: Node = box.get_child(0)
		box.remove_child(child)
		child.free()
	if _screen.play.hud.despatches != null:
		_screen.play.hud.despatches.set_covered(false)
		_screen.play.hud.despatches._queue = PackedStringArray()
		_screen.play.hud.despatches._queue_narrated.clear()


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish(code: int) -> void:
	printerr("playtest: finishing exit=%d" % code)
	print("\n--- playtest_war_toasts: %d steps ---" % _steps.size())
	quit(code)
