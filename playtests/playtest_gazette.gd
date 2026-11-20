extends SceneTree
## Headless free-playtest drive for the crown's news sheet: the turn-start
## Gazette, its watchlist, its archive and the tiers of knowledge it may print
## (wiki: the-gazette; DR-20261110-14, DR-20261110-28, DR-20261115-06).
##
## The surface is mid-campaign: the sheet only speaks from the second turn, its
## interest page needs a watched court's fight on the crown's own chart, and the
## archive only becomes a walk after a run of turns. This drive reaches it two
## ways — a real campaign played through the seal (Spain, seed 1500, turn 0 and
## the turn-100 advanced start), and probes on the real collector for the tiers
## no hand play arrives at in a session. It reads what the crown is shown: the
## plate's own body, stamp, chips, walk buttons and watchlist rows, beside the
## sheets [GazetteState] filed. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_gazette.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SaveDrive = preload("res://playtests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
const SAVE_DIR: String = "user://playtest_gazette"
const SLOT: int = 1
## Turns played on the advanced start before the archive is read.
const CAMPAIGN_TURNS: int = 5
## A host that can take a defended province: shot to break the wall, foot and
## horse to hold what is left.
const HOST: Array[String] = [
	"musketeers", "musketeers", "musketeers", "musketeers", "musketeers",
	"musketeers", "musketeers", "musketeers", "musketeers", "musketeers",
	"musketeers", "musketeers", "musketeers", "musketeers", "musketeers",
	"halberdiers", "halberdiers", "halberdiers", "halberdiers", "halberdiers",
	"hussars", "hussars", "hussars", "hussars",
	"siege_guns", "siege_guns", "siege_guns", "field_artillery", "field_artillery",
]

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _main: Node = null
## Every battle the screen reported during the turn the drive closed.
var _battles: Array[Dictionary] = []
## How many of those the capture audit has already read.
var _audited: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveDrive.clean_dir(SAVE_DIR)
	await _opening_pass()
	await _campaign_pass()
	await _delivery_pass()
	await _battle_pass()
	await _mask_pass()
	await _watchlist_pass()
	await _archive_pass()
	await _persistence_pass()
	_finish()


# --- the opening turn -------------------------------------------------------


## Turn 1 never opens a sheet (nothing has resolved), and the watchlist is drawn
## from the bonds the campaign opens with (wiki: the-gazette § When it appears,
## § Courts of interest).
func _opening_pass() -> void:
	_say("")
	_say("=== the opening turn ===")
	if not await _open(""):
		return
	_say("%s, turn %d, purse %d" % [
		FactionCatalog.name_of(_play.player_faction), _play.turn, _play.treasury(),
	])
	_say("plate at the open: up %s; gazette state %s" % [
		str(_plate_shown()), "filed" if _play.gazette != null else "none",
	])
	MapPlayGazette.open_archive(_play)
	_say("the cartouche seal: the plate reads:")
	_dump_plate()
	_say("watchlist (seeded on this open): %s" % _watched_text())
	_audit_bonds()
	_plate_tab(GazettePlate.Mode.WATCHLIST)
	_say("the watchlist tab reads:")
	_dump_plate()
	_release_gazette()
	var opened: int = _take_turn()
	_say("the seal: the calendar now reads turn %d, plate up %s" % [opened, str(_plate_shown())])
	if opened < 0:
		_say("the opening turn never closed")
		return
	_dump_live("the sheet the turn raised")
	_say("sheets filed: %s" % _sheet_turns())


# --- a real campaign --------------------------------------------------------


## Every turn of a played campaign: the sheet names the turn that resolved, its
## classes stand in the published order, and its own numbers hold (wiki:
## the-gazette § Classes, § What the crown can know).
func _campaign_pass() -> void:
	_say("")
	_say("=== five turns of a campaign ===")
	if not await _open(AdvancedStart.TURNS100):
		return
	for _index in CAMPAIGN_TURNS:
		if _play.campaign_over():
			_say("the campaign ended at turn %d" % _play.turn)
			break
		var before: int = _play.turn
		var opened: int = _take_turn()
		if opened < 0:
			_say("turn %d never closed" % before)
			break
		var sheet: Dictionary = _sheet_of(before)
		_say("turn %d closed; the calendar reads %d; filed %s; plate up %s" % [
			before, opened, "yes" if not sheet.is_empty() else "no", str(_plate_shown()),
		])
		if _plate_shown():
			_say("  the plate prints the sheet for turn %d" % int(
				_play.hud.gazette_plate._sheet.get("turn", -1)
			))
		_dump_live("the sheet for turn %d" % before)
		_audit_sheet(sheet)
		_audit_captures()
		_release_gazette()
	_say("sheets filed: %s" % _sheet_turns())
	_say("archive tallies: %s" % _tally_text())
	_release_gazette()


# --- the turn's deliveries --------------------------------------------------


## A crown's own orders land as news: one line per delivery, naming the tier or
## unit (and the capital), with a launched hull keeping its christened name
## (wiki: the-gazette § Item catalog — Our court, "Every Build/work delivery").
func _delivery_pass() -> void:
	_say("")
	_say("=== the turn's deliveries ===")
	if not await _open(AdvancedStart.TURNS100):
		return
	var economy: PlayerEconomy = _play.economy.economy
	if economy == null:
		_say("no crown ledger to order from")
		return
	var before: Dictionary = _counts()
	var queued: PackedStringArray = PackedStringArray()
	queued.append(str(economy.queue_recruit(WorkerPool.Tier.APPRENTICE, 1)))
	economy.queue_build(RecruitQueue.KIND_CIVILIAN, CivilianCatalog.DEFAULT_TYPE)
	economy.queue_build(RecruitQueue.KIND_REGIMENT, "musketeers")
	var hull: String = _launchable_hull()
	if hull.is_empty():
		_say("no hull the slip will take this turn")
	else:
		economy.queue_build(RecruitQueue.KIND_SHIP, hull)
	_say("queued: %s" % str(economy.recruits.snapshot()))
	await _clear_toasts()
	var turn: int = _play.turn
	var opened: int = _take_turn()
	if opened < 0:
		_say("the turn never closed")
		return
	_say("counts before %s -> after %s" % [_counts_text(before), _counts_text(_counts())])
	for text: String in _toasts():
		_say("despatch: %s" % text)
	var sheet: Dictionary = _sheet_of(turn)
	_say("the sheet for turn %d, Our court page:" % turn)
	var deliveries: int = 0
	for raw: Variant in sheet.get("items", []) as Array:
		var item: Dictionary = raw
		if int(item.get("class", -1)) != Gazette.Class.COURT:
			continue
		var kind: String = String(item.get("kind", ""))
		if kind not in ["workerRecruited", "civilianMustered", "regimentMustered", "shipLaunched"]:
			continue
		deliveries += 1
		_say("  %-18s %s" % [kind, String(item.get("text", ""))])
	if deliveries == 0:
		_say("  (no delivery line reached the sheet)")
	_say("the home fleet's newest hull is %s" % _newest_hull_name())
	_release_gazette()


## A watched court's battle: printed without casualty numbers where the crown's
## chart reaches, absent where it does not (wiki: the-gazette § What the crown can
## know; DR-20261110-28). Probed on the real collector with the session's own
## chart and a chart that reaches nothing — at the turn-100 start the crown holds
## every province, so no hand play arrives at the withheld half.
func _mask_pass() -> void:
	_say("")
	_say("=== a watched court's battle ===")
	if _play == null:
		_say("no campaign to probe")
		return
	var rival: int = _watched_rival()
	if rival < 0:
		_say("no watched rival to seat a battle for")
		return
	var other: int = _second_rival(rival)
	if other < 0:
		_say("no second rival for the fight")
		return
	var charted: Dictionary = _charted_province()
	if charted.is_empty():
		_say("no charted province to seat the fight on")
		return
	var battle: Dictionary = _battle_record(
		int(charted["region"]), int(charted["province"]), rival, other
	)
	_say("watched %s fights %s at %s" % [
		FactionCatalog.name_of(rival), FactionCatalog.name_of(other),
		_place_text(charted),
	])
	var seen: Dictionary = Gazette.collect(
		_play.player_faction, _play.turn, _play.world, _play.diplomacy, [rival],
		[battle], [], [], {}, 0, [], _play.court_charts, []
	)
	_say("the crown's chart holds the place: %s" % _lines_text(seen))
	var blind := CourtCharts.new()
	blind.setup(_play.world, _play.player_faction, {})
	var hidden: Dictionary = Gazette.collect(
		_play.player_faction, _play.turn, _play.world, _play.diplomacy, [rival],
		[battle], [], [], {}, 0, [], blind, []
	)
	_say("a chart that reaches nothing: %s" % _lines_text(hidden))
	# The crown's own clash in the same place keeps its numbers.
	var ours: Dictionary = _battle_record(
		int(charted["region"]), int(charted["province"]), _play.player_faction, other
	)
	var own_sheet: Dictionary = Gazette.collect(
		_play.player_faction, _play.turn, _play.world, _play.diplomacy, [rival],
		[ours], [], [], {}, 0, [], _play.court_charts, []
	)
	_say("our crown's clash there: %s" % _lines_text(own_sheet))


# --- the crown's own battle -------------------------------------------------


## A battle the crown fights: its own page prints the numbers, and the crown's
## own dead are among them (wiki: the-gazette § What the crown can know).
func _battle_pass() -> void:
	_say("")
	_say("=== the crown's own battle ===")
	if not await _open(AdvancedStart.TURNS100):
		return
	var seat: Dictionary = _war_seat()
	if seat.is_empty():
		_say("no rival province to march on")
		return
	var rival: int = int(seat["rival"])
	if not DiplomacyRules.invadable(_play.diplomacy, _play.player_faction, rival):
		var war: Dictionary = DiplomacyRules.declare_war(
			_play.diplomacy, _play.player_faction, rival
		)
		_say("war on %s: %s" % [FactionCatalog.name_of(rival), str(bool(war.get("ok", false)))])
	_seat_defenders(int(seat["target"]), rival)
	var host: Array[String] = []
	host.assign(HOST)
	var army: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, _play.player_faction, int(seat["staging"]), false,
		host, 1000
	)
	_play.army_layer.next_army += 1
	_play.army_layer.armies.append(army)
	_play.army_layer.prune_markers()
	_say("the crown's host of %d musters at %s and marches on %s (%d defenders)" % [
		army.count(), _play.model.province_name(int(seat["staging"])),
		_play.model.province_name(int(seat["target"])), _garrison(int(seat["target"])),
	])
	var moved: Dictionary = _play.army_layer.order(army, int(seat["target"]), true)
	_say("the order: %s" % (
		"ok" if bool(moved.get("ok", false)) else String(moved.get("reason", "refused"))
	))
	_battles.clear()
	var turn: int = _play.turn
	var opened: int = _take_turn()
	if opened < 0:
		_say("the turn never closed")
		return
	for battle: Dictionary in _battles:
		if int(battle.get("attacker", -1)) != _play.player_faction \
			and int(battle.get("defender", -1)) != _play.player_faction:
			continue
		_say("the record: %s vs %s, outcome %d, our dead %d, theirs %d, captured %s" % [
			FactionCatalog.name_of(int(battle.get("attacker", -1))),
			FactionCatalog.name_of(int(battle.get("defender", -1))),
			int(battle.get("outcome", -1)),
			_own_size(battle), _their_size(battle), str(bool(battle.get("captured", false))),
		])
	for text: String in _toasts():
		if text.contains("takes") or text.contains("holds") or text.contains("loses"):
			_say("despatch: %s" % text)
	var sheet: Dictionary = _sheet_of(turn)
	for raw: Variant in sheet.get("items", []) as Array:
		var item: Dictionary = raw
		if int(item.get("class", -1)) != Gazette.Class.COURT:
			continue
		if not String(item.get("kind", "")).begins_with("battle") \
			and not String(item.get("kind", "")).begins_with("sea"):
			continue
		_say("the sheet's line: %s" % String(item.get("text", "")))
	_release_gazette()


## A rival province with a crown province next door: `{staging, target, rival}`.
func _war_seat() -> Dictionary:
	for region: int in _play.world.region_count():
		var model: MapModel = _play.world.region(region)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province.owner != _play.player_faction:
				continue
			for neighbour: int in MapGeo.province_neighbors(model, province.id):
				var owner: int = model.province_owner(neighbour)
				if owner == _play.player_faction or owner == MapModel.NO_ID:
					continue
				if FactionCatalog.type_of(owner) != FactionCatalog.Type.GREAT_POWER:
					continue
				return {"staging": province.id, "target": neighbour, "rival": owner}
	return {}


## Hands the target a real garrison, so the clash is fought and not a walk-in.
func _seat_defenders(target: int, rival: int) -> void:
	if _garrison(target) > 0:
		return
	var types: Array[String] = [
		"musketeers", "musketeers", "musketeers", "halberdiers", "halberdiers",
		"halberdiers", "hussars", "hussars",
	]
	var guard: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, rival, target, false, types, 1000
	)
	_play.army_layer.next_army += 1
	_play.army_layer.armies.append(guard)
	_play.army_layer.prune_markers()


func _garrison(province: int) -> int:
	var count: int = 0
	for army: ArmyState in _play.army_layer.armies:
		if army != null and army.province == province and army.owner != _play.player_faction:
			count += army.count()
	return count


func _own_size(battle: Dictionary) -> int:
	var side: String = (
		"attacker" if int(battle.get("attacker", -1)) == _play.player_faction else "defender"
	)
	return (battle.get(side + "_lost", []) as Array).size()


func _their_size(battle: Dictionary) -> int:
	var side: String = (
		"defender" if int(battle.get("attacker", -1)) == _play.player_faction else "attacker"
	)
	return (battle.get(side + "_lost", []) as Array).size()


# --- the watchlist ----------------------------------------------------------


## A court struck off stays off, even when a new war binds it again; a court
## added by hand stays on after peace (wiki: the-gazette § Courts of interest).
func _watchlist_pass() -> void:
	_say("")
	_say("=== the watchlist ===")
	if _play == null:
		_say("no campaign to edit")
		return
	var watched: Array[int] = _play.gazette.watched.duplicate() if _play.gazette != null else []
	if watched.is_empty():
		_say("nothing is followed, so nothing can be struck off")
		return
	var struck: int = watched[0]
	MapPlayGazette.toggle_watch(_play, struck)
	_say("struck off %s: watched %s" % [FactionCatalog.name_of(struck), _watched_text()])
	var rival: int = _unwatched_rival(struck)
	if rival >= 0:
		MapPlayGazette.toggle_watch(_play, rival)
		_say("added %s by hand: watched %s" % [FactionCatalog.name_of(rival), _watched_text()])
	var war: Dictionary = DiplomacyRules.declare_war(_play.diplomacy, struck, _play.player_faction)
	_say("a new war with the struck court: %s" % str(bool(war.get("ok", false))))
	MapPlayGazette.ensure(_play)
	_say("after the reseed: watched %s; %s still struck off %s" % [
		_watched_text(), FactionCatalog.name_of(struck),
		str(not _play.gazette.is_watched(struck)),
	])
	_plate_tab(GazettePlate.Mode.WATCHLIST)
	_say("the watchlist tab reads:")
	_dump_plate()
	_release_gazette()


# --- the archive ------------------------------------------------------------


## The history screen's reading: a chip per class, each tallying the archive's
## lines of that class; the walk counts its pages; a quiet turn is filed and
## skipped by a class filter (wiki: the-gazette § History screen; DR-20261115-06).
func _archive_pass() -> void:
	_say("")
	_say("=== the archive ===")
	if _play == null or _play.gazette == null:
		_say("no archive to read")
		return
	MapPlayGazette.open_archive(_play)
	_plate_tab(GazettePlate.Mode.ARCHIVE)
	var room: GazetteArchiveRoom = _play.hud.gazette_plate._archive_room
	_say("the archive opens: %s over %d page(s); walk %s" % [
		room.position_text(), room.pages().size(), _nav_text(),
	])
	_say("chips: %s" % _chip_text(room))
	for cls: int in GazetteArchive.ORDER:
		room._press(cls)
		_say("%s: %s pages, %s; the page reads %s" % [
			GazetteArchive.label(cls), str(room.pages().size()), room.position_text(),
			_lines_text(GazetteArchive.sheet(room.pages()[0], cls)) if not room.pages().is_empty()
			else "\"%s\"" % GazetteArchive.NONE_LINE,
		])
		if room.pages().size() > 1:
			_play.hud.gazette_plate._step(1)
			_say("  one press of Older: %s, %s; the page reads %s" % [
				room.position_text(), _play.hud.gazette_plate._stamp.text,
				_lines_text(GazetteArchive.sheet(room.pages()[room.at], room.filter)),
			])
	_plate_tab(GazettePlate.Mode.AGE)
	_say("the age tab: %s" % _play.hud.gazette_plate._stamp.text)
	for line: String in _plate_lines():
		_say("  | %s" % line)
	_plate_tab(GazettePlate.Mode.ARCHIVE)
	_dump_plate()

	_probe_reading()


# --- a saved campaign -------------------------------------------------------


## The watchlist and every filed sheet are the campaign's, so a save carries
## them (wiki: the-gazette § Courts of interest, § History screen;
## campaign-persistence).
func _persistence_pass() -> void:
	_say("")
	_say("=== a saved campaign ===")
	if _screen == null or _play == null or _play.gazette == null:
		_say("no campaign to save")
		return
	_screen.save_dir = SAVE_DIR
	var watched: String = _watched_text()
	var sheets: String = _sheet_turns()
	_say("before the save: watched %s; sheets %s" % [watched, sheets])
	_say("save: %s" % SaveDrive.save_slot(_screen, SLOT))
	var loaded: MapScreen = SaveDrive.load_slot(_screen, _main, SLOT)
	if loaded == null:
		_say("the load was refused")
		return
	_screen = loaded
	_play = loaded.play
	_say("after the load: watched %s; sheets %s" % [_watched_text(), _sheet_turns()])
	_say("the watchlist %s; the sheets %s" % [
		"survived" if _watched_text() == watched else "changed",
		"survived" if _sheet_turns() == sheets else "changed",
	])


# --- the drives' plumbing ---------------------------------------------------


func _open(advanced: String) -> bool:
	_screen = await Launch.open_map(self, SEED_TEXT, 0, advanced)
	if _screen == null:
		_say("the map never opened")
		return false
	_main = _screen.get_parent()
	_play = _screen.play
	if not _screen.battle_resolved.is_connected(_on_battle):
		_screen.battle_resolved.connect(_on_battle)
	return true


func _on_battle(battles: Array) -> void:
	for raw: Variant in battles:
		if typeof(raw) == TYPE_DICTIONARY:
			_battles.append(raw)


## Plays one turn through the seal: a waiting consent is answered (answering one
## ends the suspended turn), then the turn runs to its close. Returns the turn
## the calendar opened, or -1 when the calendar never moved.
func _take_turn() -> int:
	var start: int = _play.turn
	for _attempt in SaveDrive.MAX_TURN_ATTEMPTS:
		MapPlayTurn.end_turn(_play)
		_release_plate()
		if _play.turn != start or _play.campaign_over():
			return _play.turn
		if not SaveDrive.answer_pending(_play):
			break
		# Answering a consent ends the suspended turn, so the calendar may have
		# moved already: one press, one turn.
		if _play.turn != start:
			break
	return -1 if _play.turn == start else _play.turn


func _release_plate() -> void:
	var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
	var guard: int = 0
	while overlay != null and overlay.is_shown() and guard < 6:
		overlay.skip()
		overlay._on_continue()
		guard += 1


func _release_gazette() -> void:
	if _play == null or _play.hud == null or _play.hud.gazette_plate == null:
		return
	_play.hud.gazette_plate.dismiss()


func _plate_tab(mode: int) -> void:
	if _play.hud.gazette_plate == null:
		return
	if not _plate_shown():
		MapPlayGazette.open_archive(_play)
	_play.hud.gazette_plate._go(mode)


func _plate_shown() -> bool:
	return _play != null and _play.hud != null and _play.hud.gazette_plate != null \
		and _play.hud.gazette_plate.is_shown()


# --- reads ------------------------------------------------------------------


func _dump_live(label: String) -> void:
	_say(label + ": plate up %s" % str(_plate_shown()))
	if not _plate_shown():
		return
	_dump_plate()


func _dump_plate() -> void:
	if not _plate_shown():
		_say("  (the plate is not up)")
		return
	var plate: GazettePlate = _play.hud.gazette_plate
	_say("  title: %s  ·  stamp: %s" % [plate._title.text, plate._stamp.text])
	if plate._nav != null and plate._nav.visible:
		_say("  walk: %s (%s)" % [_nav_text(), plate._nav_label.text])
	for line: String in _plate_lines():
		_say("  | %s" % line)


func _plate_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _play == null or _play.hud.gazette_plate == null:
		return out
	_collect_visible(_play.hud.gazette_plate._body, out)
	return out


## The lines the crown actually sees: a mode that is hidden keeps its rows in the
## tree, so the read has to respect the tree's visibility, not each node's flag.
func _collect_visible(node: Node, into: PackedStringArray) -> void:
	if node == null or not node.is_visible_in_tree():
		return
	if node is Label:
		into.append((node as Label).text)
	elif node is Button:
		into.append("[%s]" % (node as Button).text)
	for child: Node in node.get_children():
		_collect_visible(child, into)


func _nav_text() -> String:
	if _play == null or _play.hud.gazette_plate == null:
		return "no plate"
	var plate: GazettePlate = _play.hud.gazette_plate
	if plate._nav == null or not plate._nav.visible:
		return "no walk"
	return "newer %s, older %s" % [
		"shut" if plate._newer.disabled else "open",
		"shut" if plate._older.disabled else "open",
	]


func _chip_text(room: GazetteArchiveRoom) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: Variant in room.filter_buttons().keys():
		var chip: Button = room.filter_buttons()[key] as Button
		parts.append("%s%s" % [chip.text, "*" if chip.button_pressed else ""])
	return ", ".join(parts) if not parts.is_empty() else "no chips"


func _sheet_of(turn: int) -> Dictionary:
	if _play == null or _play.gazette == null:
		return {}
	return _play.gazette.sheet_for(turn)


## The first hull the capital slip will take this turn, or "".
func _launchable_hull() -> String:
	if _play == null or _play.economy == null or _play.economy.economy == null:
		return ""
	for row: Dictionary in FleetYard.rows(
		_play.economy.economy, true, MapPlayFleetYard.flown(_play)
	):
		if bool(row.get("ok", false)):
			return String(row.get("type_id", ""))
	return ""


## The counters a delivery moves: hands, crews, regiments, hulls.
func _counts() -> Dictionary:
	var out: Dictionary = {}
	if _play == null:
		return out
	out["hands"] = _play.economy.economy.workers.count(WorkerPool.Tier.APPRENTICE) \
		if _play.economy != null and _play.economy.economy != null else 0
	out["crews"] = _play.civilian_layer.unit_count_all(_play.player_faction) \
		if _play.civilian_layer != null else 0
	out["regiments"] = _play.army_layer.regiment_count_all(_play.player_faction) \
		if _play.army_layer != null else 0
	out["hulls"] = _play.ship_layer.hull_count_all(_play.player_faction) \
		if _play.ship_layer != null else 0
	return out


func _counts_text(counts: Dictionary) -> String:
	return "%d apprentice(s), %d crew(s), %d regiment(s), %d hull(s)" % [
		int(counts.get("hands", 0)), int(counts.get("crews", 0)),
		int(counts.get("regiments", 0)), int(counts.get("hulls", 0)),
	]


## The newest hull in the home fleet, by the name the launch gave her.
func _newest_hull_name() -> String:
	if _play == null or _play.ship_layer == null:
		return "none"
	var fleet: FleetState = MapPlayRaids.home_fleet(_play, _play.player_faction)
	if fleet == null or fleet.hulls.is_empty():
		return "no home fleet"
	var hull: String = String(fleet.hulls[fleet.hulls.size() - 1])
	return String(fleet.hull_names.get(hull, "(unnamed)"))


func _toasts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _play == null or _play.hud == null or _play.hud.despatches == null:
		return out
	SaveDrive.collect_text(_play.hud.despatches, "", out)
	return out


func _clear_toasts() -> void:
	if _play == null or _play.hud == null or _play.hud.despatches.box == null:
		return
	for child: Node in _play.hud.despatches.box.get_children():
		child.queue_free()
	await process_frame


func _sheet_turns() -> String:
	if _play == null or _play.gazette == null:
		return "no gazette"
	var turns: PackedStringArray = PackedStringArray()
	for sheet: Dictionary in _play.gazette.history():
		var count: int = (sheet.get("items", []) as Array).size()
		turns.append("%d(%d)" % [int(sheet.get("turn", 0)), count])
	return ", ".join(turns) if not turns.is_empty() else "none"


func _watched_text() -> String:
	if _play == null or _play.gazette == null:
		return "no gazette"
	var names: PackedStringArray = PackedStringArray()
	for faction: int in _play.gazette.watched:
		names.append(FactionCatalog.name_of(faction))
	return ", ".join(names) if not names.is_empty() else "none"


func _tally_text() -> String:
	if _play == null or _play.gazette == null:
		return "no gazette"
	var sheets: Array[Dictionary] = _play.gazette.history()
	var parts: PackedStringArray = PackedStringArray()
	for cls: int in GazetteArchive.ORDER:
		parts.append("%s %d" % [GazetteArchive.label(cls), GazetteArchive.tally(sheets, cls)])
	return ", ".join(parts)


func _lines_text(sheet: Dictionary) -> String:
	var items: Array = sheet.get("items", []) as Array
	if items.is_empty():
		return "(nothing)"
	var parts: PackedStringArray = PackedStringArray()
	for raw: Variant in items:
		var item: Dictionary = raw
		parts.append("[%s/%s] %s" % [
			_class_name(int(item.get("class", -1))), String(item.get("kind", "")),
			String(item.get("text", "")),
		])
	return " || ".join(parts)


func _class_name(cls: int) -> String:
	match cls:
		Gazette.Class.WORLD:
			return "world"
		Gazette.Class.COURT:
			return "court"
		Gazette.Class.INTEREST:
			return "interest"
	return "?"


# --- audits -----------------------------------------------------------------


## Notes the class order, the interest page's own rules (no numbers for another
## court) and any item that reached the sheet without a line.
func _audit_sheet(sheet: Dictionary) -> void:
	if sheet.is_empty():
		_say("  audit: no sheet filed for that turn")
		return
	var last: int = -1
	var interest: int = 0
	for raw: Variant in sheet.get("items", []) as Array:
		var item: Dictionary = raw
		var cls: int = int(item.get("class", -1))
		var text: String = String(item.get("text", ""))
		if cls < last:
			_say("  audit: %s printed after %s — the published order is World, Our court, Courts of interest" % [
				_class_name(cls), _class_name(last),
			])
		last = cls
		if text.is_empty():
			_say("  audit: an item of class %s (%s) reached the sheet with no line" % [
				_class_name(cls), String(item.get("kind", "")),
			])
		if cls == Gazette.Class.INTEREST:
			interest += 1
			if _has_digit(text):
				_say("  audit: another court's line counts its losses: \\\"%s\\\"" % text)
	_say("  audit: %d item(s), %d on the interest page" % [
		(sheet.get("items", []) as Array).size(), interest,
	])
	for raw: Variant in sheet.get("items", []) as Array:
		var item: Dictionary = raw
		_say("    %-8s %-20s %s" % [
			_class_name(int(item.get("class", -1))), String(item.get("kind", "")),
			String(item.get("text", "")),
		])


func _has_digit(text: String) -> bool:
	for index in text.length():
		if text[index].is_valid_int():
			return true
	return false


## A capture the sheet narrates must be the map's own state: the province the
## record calls taken is held by the victor when the turn closes.
func _audit_captures() -> void:
	while _audited < _battles.size():
		var battle: Dictionary = _battles[_audited]
		_audited += 1
		if not bool(battle.get("captured", false)) or battle.has("zone"):
			continue
		var region: int = int(battle.get("region", -1))
		var province: int = int(battle.get("province", -1))
		var model: MapModel = _play.world.region(region) if region >= 0 else null
		if model == null or province < 0:
			continue
		var victor: int = int(battle.get("attacker", -1))
		var holder: int = model.province_owner(province)
		if holder != victor:
			_say("  audit: %s was taken by %s, and the map now reads %s" % [
				model.province_name(province), FactionCatalog.name_of(victor),
				FactionCatalog.name_of(holder) if holder != MapModel.NO_ID else "nobody",
			])


## Every bonded court is followed and every followed court is bonded — the sheet
## can only report the doings of courts the crown follows (wiki: the-gazette
## § Courts of interest).
func _audit_bonds() -> void:
	if _play == null or _play.gazette == null or _play.diplomacy == null:
		return
	for faction: int in FactionCatalog.great_power_ids() + FactionCatalog.minor_ids() + FactionCatalog.tribe_ids():
		if faction == _play.player_faction:
			continue
		var bonded: bool = GazetteState.bonded(_play.diplomacy, _play.player_faction, faction)
		var followed: bool = _play.gazette.is_watched(faction)
		if bonded and not followed:
			_say("  audit: %s is bonded but not followed" % FactionCatalog.name_of(faction))
		if followed and not bonded and not _play.gazette.removed.has(faction):
			_say("  audit: %s is followed but holds no seed bond" % FactionCatalog.name_of(faction))


## A quiet turn filed with nothing, and a class the archive never printed: the
## room prints its own line for each (wiki: the-gazette § When it appears,
## § History screen).
func _probe_reading() -> void:
	var state := GazetteState.new()
	state.append({"turn": 7, "items": []})
	state.append({"turn": 8, "items": [
		{"class": Gazette.Class.WORLD, "kind": "warDeclared", "text": "Two courts go to war."},
	]})
	state.append({"turn": 9, "items": [
		{"class": Gazette.Class.COURT, "kind": "techFinished", "text": "A study finishes."},
	]})
	var room := GazetteArchiveRoom.new()
	root.add_child(room)
	room.fill(state, GazetteArchive.ALL)
	_say("  all news: %s pages, %s" % [str(room.pages().size()), room.position_text()])
	_say("  chips: %s" % _chip_text(room))
	room.at = 1
	_say("  the quiet sheet on screen: %s" % _room_lines(room))
	room._press(Gazette.Class.INTEREST)
	_say("  courts of interest: %s pages, reads %s" % [
		str(room.pages().size()), _room_lines(room),
	])
	room.queue_free()


func _room_lines(room: GazetteArchiveRoom) -> String:
	var out: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(room._page, "", out)
	return " | ".join(out) if not out.is_empty() else "(blank)"


# --- seating ----------------------------------------------------------------


## A rival the crown follows, or -1.
func _watched_rival() -> int:
	if _play == null or _play.gazette == null:
		return -1
	for faction: int in _play.gazette.watched:
		if faction != _play.player_faction:
			return faction
	return -1


## A Great Power the crown does not follow, or -1.
func _unwatched_rival(skip: int) -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction == _play.player_faction or faction == skip:
			continue
		if _play.gazette != null and _play.gazette.is_watched(faction):
			continue
		return faction
	return -1


## Any Great Power but `skip` and the crown: the mask probe only needs one
## watched party, so the other may be followed too.
func _second_rival(skip: int) -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction != _play.player_faction and faction != skip:
			return faction
	return -1


## The first province the crown's own chart holds: `{region, province}`.
func _charted_province() -> Dictionary:
	if _play == null or _play.court_charts == null:
		return {}
	for region: int in _play.world.region_count():
		var model: MapModel = _play.world.region(region)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if _play.court_charts.knows_province(_play.player_faction, region, province.id):
				return {"region": region, "province": province.id}
	return {}


func _place_text(spot: Dictionary) -> String:
	if spot.is_empty():
		return "nowhere"
	var model: MapModel = _play.world.region(int(spot["region"]))
	var name: String = model.province_name(int(spot["province"])) if model != null else "?"
	return "%s (%d, %d)" % [name, int(spot["region"]), int(spot["province"])]


## A land battle record in the shape the Combat phase writes (see
## [ArmyCombat] / [ArmyBattles]): the attacker takes the province with two
## regiments of the defender broken and one of its own.
func _battle_record(region: int, province: int, attacker: int, defender: int) -> Dictionary:
	return {
		"region": region,
		"province": province,
		"attacker": attacker,
		"defender": defender,
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"captured": true,
		"attacker_lost": ["a1"],
		"defender_lost": ["d1", "d2"],
		"garrison": 0,
	}


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	SaveDrive.clean_dir(SAVE_DIR)
	print("\n--- playtest_gazette: %d steps ---" % _steps.size())
	quit()
