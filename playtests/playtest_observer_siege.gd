extends SceneTree
## Headless free-playtest drive for a rival's siege as the full-AI observer shows
## it (wiki: turn-trace-interpretation § Observer export; docs/ai-observer.md
## § Metrics). The observer has no human seat, no plate and no Gazette, so the
## observatory panel's "Recent orders" feed and the per-turn trace are the only
## narration a run has. This drive seats one siege between two rival Great
## Powers — a mid-level wall with a garrison, a besieging train with guns — lets
## a real Combat phase resolve it, and then reads every observer surface:
##
##   1. before the turn: the panel's feed, the two courts' cards, the standing.
##   2. the battle the rules actually resolved (the despatch the crown would
##      read in a live game, printed for comparison only).
##   3. after the turn: the panel's feed and cards again, the merged turn record
##      (`play.ai_turns`, the shape `tools/ai_vs_ai.gd` exports), the province's
##      owner and fort level, and the two courts' standing rows.
##
## The siege is seated because no session raises a rival wall on demand; every
## outcome read after that is the game's own. Not a CI gate, run it by hand:
##   godot --headless --path . --script res://playtests/playtest_observer_siege.gd

const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")
const SEED: int = 1500
const NO_ID: int = MapModel.NO_ID
## The garrison behind the wall: infantry on the parapet, one halberd with them
## and a troop of horse under cover (the lane split SiegeLanes reports).
const WALL_TYPES: Array[String] = ["musketeers", "musketeers", "halberdiers", "hussars"]
## The besieging train: guns enough to answer two emplaced pieces and infantry
## that can reach a parapet.
const STORM_TYPES: Array[String] = [
	"royal_artillery", "royal_artillery", "musketeers", "musketeers", "halberdiers",
]

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _battles: Array[Dictionary] = []
var _target: int = -1
var _attacker: int = -1
var _defender: int = -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = SCENE.instantiate()
	_screen.map_seed = SEED
	_screen.map_width = int(GameConfig.SIZES[1]["width"])
	_screen.map_height = int(GameConfig.SIZES[1]["height"])
	_screen.observer_mode = true
	_screen.infinite_mode = true
	# A headless run skips the pure-view follow-up (docs/ai-observer.md
	# § Performance budget); the observer's own panel is mounted regardless.
	MapPlayTurn.view_live = false
	root.add_child(_screen)
	for _frame in 3:
		await process_frame
	_play = _screen.play
	if _play == null:
		print("playtest: the observer built no session — update playtests/playtest_observer_siege.gd")
		quit(1)
		return
	_screen.battle_resolved.connect(_on_battle_resolved)
	_say("observer: seed %d, turn %d, human seat %d (empty)" % [
		_play.map_seed, _play.turn, _play.human_faction_id(),
	])
	await _read_turn()
	_finish()


# --- the seated siege --------------------------------------------------------


## Seats the wall, its garrison and a besieging train next door, then orders the
## march. The war and the order are the game's own; only the seats are fixtures.
func _seat_siege() -> void:
	var seat: Dictionary = _siege_seat()
	if seat.is_empty():
		_say("no two rival provinces border each other — no siege can be seated")
		return
	_target = int(seat["province"])
	_defender = int(seat["defender"])
	_attacker = int(seat["attacker"])
	var data: ProvinceState = _play.model.province_data(_target)
	data.fort_level = 2
	var garrison: ArmyState = _mint(_defender, _target, WALL_TYPES)
	garrison.moved = true
	_say("the wall: %s holds %s (fort %d) with %d regiments" % [
		FactionCatalog.name_of(_defender), _play.model.province_name(_target),
		FortRules.level_at(_play.model, _target), garrison.count(),
	])
	var staging: int = int(seat["staging"])
	var train: ArmyState = _mint(_attacker, staging, STORM_TYPES)
	var war: Dictionary = DiplomacyRules.declare_war(
		_play.diplomacy, _attacker, _defender
	)
	_say("%s declares on %s: %s" % [
		FactionCatalog.name_of(_attacker), FactionCatalog.name_of(_defender),
		"ok" if bool(war.get("ok", false)) else String(war.get("reason", "refused")),
	])
	var moved: Dictionary = _play.army_layer.order(train, _target, true)
	if not bool(moved.get("ok", false)):
		_say("the march was refused: %s" % String(moved.get("reason", "")))
		_target = -1
		return
	_say("the train: %d regiments (%s) marches on %s" % [
		train.count(), _types(train), _play.model.province_name(_target),
	])
	# The observer's own surfaces, before the turn fights.
	_say("")
	_say("--- the observer before the turn ---")
	_dump_observer()
	_say("the trace names: %s" % _trace_events(_play.turn))


## A town province of one Great Power bordering another Great Power's province,
## where the attacker can actually reach the war this turn: a pair already at
## war first, then one the rules let declare. Returns {} when no pair qualifies.
func _siege_seat() -> Dictionary:
	var free: Dictionary = {}
	for province in _play.model.province_count():
		var owner: int = _play.model.province_owner(province)
		if FactionCatalog.type_of(owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		for neighbour: int in MapGeo.province_neighbors(_play.model, province):
			var rival: int = _play.model.province_owner(neighbour)
			if rival == owner or rival == NO_ID:
				continue
			if FactionCatalog.type_of(rival) != FactionCatalog.Type.GREAT_POWER:
				continue
			var seat: Dictionary = {
				"province": province, "defender": owner,
				"attacker": rival, "staging": neighbour,
			}
			if DiplomacyRules.at_war_with(_play.diplomacy, rival, owner):
				return seat
			if free.is_empty() and bool(DiplomacyRules.can_declare_war(
				_play.diplomacy, rival, owner
			).get("ok", false)):
				free = seat
	return free


func _mint(owner: int, province: int, types: Array[String]) -> ArmyState:
	var made: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, owner, province, false, types, 1000
	)
	_play.army_layer.next_army += 1
	_play.army_layer.armies.append(made)
	_play.army_layer.prune_markers()
	return made


# --- the turn ----------------------------------------------------------------


func _on_battle_resolved(battles: Array[Dictionary]) -> void:
	_battles.append_array(battles)


func _read_turn() -> void:
	_say("")
	_say("--- the turn that fights the siege ---")
	var before_owner: int = _play.model.province_owner(_play.model.province_count() - 1)
	var was: int = _play.turn
	# The observer's own diplomacy phase runs first (the rival pass answers its
	# own offers, so a war seated before it can be made away); the siege is
	# seated after it, then the same finish every observer turn runs.
	MapPlayDiplomacy.resolve_turn(_play)
	await _seat_siege()
	if _target < 0:
		return
	before_owner = _play.model.province_owner(_target)
	MapPlayTurnFinish.run(_play)
	for _frame in 3:
		await process_frame
	_say("turn %d -> %d (attacker %s, defender %s)" % [
		was, _play.turn, FactionCatalog.name_of(_attacker),
		FactionCatalog.name_of(_defender),
	])
	var fought: bool = false
	for battle: Dictionary in _battles:
		if int(battle.get("province", -1)) != _target:
			continue
		fought = true
		_say("the rules resolved: %s" % BattleReport.describe_land(
			battle, _play.model.province_name(_target), FactionCatalog.names()
		))
	if not fought:
		_say("no battle was fought at the wall this turn")
	_say("the province: %s now holds it (was %s); fort %d" % [
		FactionCatalog.name_of(_play.model.province_owner(_target)),
		FactionCatalog.name_of(before_owner),
		FortRules.level_at(_play.model, _target),
	])
	_say("")
	_say("--- the observer after the turn ---")
	_dump_observer()


## Every surface the observer actually reads: the panel's feed and cards, the
## standing, and the merged turn record the headless export writes.
func _dump_observer() -> void:
	var panel := _screen.get_node_or_null("AiObserver") as AiObserverPanel
	if panel == null:
		_say("the observatory panel is not mounted")
		return
	_say("panel feed:")
	var feed: String = panel._log.text
	if feed.is_empty():
		_say("  (empty)")
	for line: String in feed.split("\n"):
		_say("  · %s" % line)
	var snap: Dictionary = MapPlayObserver.snapshot(_play)
	_say("standing: %s" % String(snap["result"]))
	for row: Dictionary in snap["rows"]:
		if int(row["faction"]) != _attacker and int(row["faction"]) != _defender:
			continue
		_say("  #%d %s — %d OW · army %d · last: %s" % [
			int(row["rank"]), String(row["name"]), int(row["provinces_old"]),
			int(row["regiments"]), String(row["headline"]),
		])
	var card: Dictionary = panel._cards.get(_attacker, {})
	if not card.is_empty():
		_say("  %s's card reads: \"%s\"" % [
			FactionCatalog.name_of(_attacker), String(card["last"].text),
		])
	_say("the trace names: %s" % _trace_events(maxi(_play.turn - 1, 1)))


## The merged turn record's own events, the shape the export writes.
func _trace_events(turn: int) -> String:
	for merged: Dictionary in _play.ai_turns:
		if int(merged.get("turn", -1)) != turn:
			continue
		var lines: PackedStringArray = PackedStringArray()
		for event: Dictionary in merged.get("events", []):
			lines.append(String(event.get("text", "")))
		return " | ".join(lines) if not lines.is_empty() else "nothing"
	return "no record for the turn"


# --- reads ------------------------------------------------------------------


func _types(army: ArmyState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for regiment_id: String in army.regiments:
		parts.append(army.type_of(regiment_id))
	return ", ".join(parts)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_observer_siege: %d steps ---" % _steps.size())
	quit()
