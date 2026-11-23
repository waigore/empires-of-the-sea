extends SceneTree
## Headless free-playtest drive for a crown whose seat falls while its own war
## is still under way (wiki: capital-and-connectivity § Capital loss and
## reassignment; military-armies § Movement and attacks, § Combat and province
## loss; victory § Great Power defeat).
##
## Two passes, each read only from what the court shows:
##
##   1. `_move_pass` — the crown is invading a rival (its host marches into the
##      rival's province the same turn) when a second rival storms the seat and
##      the court moves. Reads the court's news, the new seat, the invading
##      host's dossier and road home, the province it just took, and the seat's
##      own orders after the move.
##   2. `_fall_pass` — the crown holds no province in its original region (its
##      New World colonies stand) and its host is abroad when the seat is taken:
##      the crown falls outright, so its provinces in every region pass to the
##      conqueror and its remaining regiments and squadrons leave play.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_seat_lost_mid_invasion.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SaveDrive = preload("res://playtests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
const ADVANCED: String = AdvancedStart.TURNS100
## The invading host: enough men to walk into an empty province and hold it.
const HOST_MEN: int = 6
## The storming host: far more than any one-province garrison answers, so the
## seat is taken outright instead of a stand-off that keeps the province.
const STORM_MEN: int = 80

var _steps: PackedStringArray = PackedStringArray()
var _play: PlaySession = null
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0, ADVANCED)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	var seat: int = _play.capital_province
	_say("seed %s · turn %d · %s · seat %s on the %s chart" % [
		SEED_TEXT, _play.turn, FactionCatalog.name_of(_play.player_faction),
		_province_name(seat), FactionCatalog.region_label(_play.region_index),
	])
	_say("holdings: Old World %d provinces, New World %d" % [
		CapitalLoss.owned_provinces(_old_world(), _play.player_faction).size(),
		CapitalLoss.owned_provinces(_new_world(), _play.player_faction).size(),
	])
	var rivals: Array[int] = _rivals()
	if rivals.size() < 2:
		_say("need two rival Great Powers — the drive cannot run")
		_finish()
		return
	await _move_pass()
	await _walk_in_pass()
	await _fall_pass()
	_finish()


# --- passes ----------------------------------------------------------------


## The court moves while the crown's own invasion is under way: one rival's
## province is taken the same turn the seat is stormed by another.
func _move_pass() -> void:
	_say("")
	var seat: int = _play.capital_province
	var stage: Dictionary = _invasion_stage()
	if stage.is_empty():
		_say("no rival Great Power holds a province beside crown land — the invasion cannot be staged")
		return
	var invaded: int = int(stage["rival"])
	var staging: int = int(stage["from"])
	var target: int = int(stage["target"])
	var stormer: int = _other_rival(invaded)
	if stormer < 0:
		_say("no second rival Great Power stands to storm the seat")
		return
	_say("--- the crown's war under way: %s marches %s → %s, then %s storms %s ---" % [
		FactionCatalog.name_of(_play.player_faction), _province_name(staging),
		_province_name(target), FactionCatalog.name_of(stormer), _province_name(seat),
	])
	target = _fixture_ground(target)
	DiplomacyRules.declare_war(_play.diplomacy, _play.player_faction, invaded)
	DiplomacyRules.declare_war(_play.diplomacy, stormer, _play.player_faction)
	# A clean field: the crown's invading host, one regiment left at the seat (the
	# Home Army a crown keeps there), and the storm.
	_play.army_layer.armies.clear()
	_play.army_layer._rebuild_markers()
	var host: ArmyState = _place(_play.player_faction, staging, HOST_MEN, 300)
	var order: Dictionary = _play.army_layer.order(
		host, target, MapPlayArmies.may_invade(_play, target)
	)
	_say("order march %s → %s: %s\"%s\"" % [
		_province_name(staging), _province_name(target),
		"ok " if bool(order.get("ok", false)) else "refused ",
		String(order.get("reason", "")),
	])
	_fixture_ground(seat)
	_place(_play.player_faction, seat, 1, 310, false, true)
	_place(stormer, seat, STORM_MEN, 320, true)
	_say("before the turn: own %d provinces in the Old World; seat %s; host %d men at %s, marching on %s" % [
		CapitalLoss.owned_provinces(_old_world(), _play.player_faction).size(),
		_province_name(seat), host.count(), _province_name(host.province),
		_province_name(target),
	])
	_say("chart model is the world's own region: %s" % str(_play.model == _old_world()))
	for army: ArmyState in _play.army_layer.armies:
		if army == null:
			continue
		_say("  army %d owner %s home %s moved %s at %s (%d men)" % [
			army.id, FactionCatalog.name_of(army.owner), str(army.home), str(army.moved),
			_province_name(army.province), army.count(),
		])
	var seen: int = _toast_count()
	_take_turn()
	_say("court news raised this turn:")
	for line: String in _toasts_since(seen):
		_say("  · %s" % line)
	var new_seat: int = _play.capital_province
	_say("after: seat %s (was %s); old seat owned by %s, capital flag %s; new seat capital %s, town level %d" % [
		_province_name(new_seat), _province_name(seat),
		FactionCatalog.name_of(_old_world().province_owner(seat)),
		str(_old_world().province_data(seat).capital),
		str(_old_world().province_data(new_seat).capital),
		_old_world().province_data(new_seat).town_development,
	])
	_say("seat reads: CapitalLoss.seat_of %s · world.capital_province_of %s · play.capital_province %s · chart %s" % [
		_province_name(CapitalLoss.seat_of(_old_world(), _play.player_faction)),
		_province_name(_play.world.capital_province_of(FactionCatalog.OLD_WORLD, _play.player_faction)),
		_province_name(_play.capital_province),
		FactionCatalog.region_label(_play.region_index),
	])
	_say("crown capital flags: %s" % _capital_flags())
	_say("the invaded province: %s now held by %s; host %s (%d men)" % [
		_province_name(target), FactionCatalog.name_of(_old_world().province_owner(target)),
		_province_name(host.province), host.count(),
	])
	_invader_readings(host, new_seat)
	await _seat_orders_after_move(new_seat)


## What the invading host reads once its own court has moved: the dossier's own
## lines, the road home to the new seat, and the words a march to it answers.
func _invader_readings(host: ArmyState, seat: int) -> void:
	_say("")
	_say("--- the invading host after the court moved ---")
	if host.is_empty():
		_say("the host fell in the turn — nothing stands abroad")
		return
	host.moved = false
	MapPlayArmies.select(_play, host)
	var panel: ArmyPanel = _play.hud.panels.army_panel
	_say("dossier place:  \"%s\"" % panel._location.text)
	_say("dossier status: \"%s\"" % panel._status.text)
	_say("dossier hint:   \"%s\"" % panel._hint.text)
	_say("army counsel:   \"%s\"" % MapPlayArmyPick.line(_play, host))
	_say("army sheet:     \"%s\"" % MapPlayArmyOrdersPick.line(_play))
	var destinations: Array[int] = ArmyMovement.destinations(_play.model, host)
	_say("tap list: %d provinces; the new seat (%s) is in it: %s" % [
		destinations.size(), _province_name(seat), str(destinations.has(seat)),
	])
	var own: PackedStringArray = PackedStringArray()
	for id: int in destinations:
		if _old_world().province_owner(id) == _play.player_faction:
			own.append(_province_name(id))
	_say("own provinces in the tap list: %s" % (
		", ".join(own) if not own.is_empty() else "none"
	))
	_say("the rule answers a march to the new seat with \"%s\"" % String(
		ArmyMovement.can_move(_play.model, host, seat).get("reason", "")
	))
	var data: ProvinceState = _old_world().province_data(host.province)
	_say("the ground the host holds: town %d, capital %s, owner %s" % [
		data.town_development, str(data.capital),
		FactionCatalog.name_of(data.owner),
	])


## The seat's own orders once the court has moved: a hire queued at the new seat
## lands where the sheets promise, and the Home Army is named where it stands.
func _seat_orders_after_move(seat: int) -> void:
	_say("")
	_say("--- the new seat's own orders ---")
	_say("crown seat read: region %d, province %s" % [
		int(MapPlayCourt.crown_seat(_play)["region"]),
		_province_name(int(MapPlayCourt.crown_seat(_play)["province"])),
	])
	_play.screen.switch_region(int(MapPlayCourt.crown_seat(_play)["region"]))
	await process_frame
	_say("Home Army stands at %s" % _home_army_place())
	MapPlayInput.select_province(_play, seat, Vector2.ZERO)
	var before: int = _civilian_count()
	_clear_toasts()
	MapPlayInput.on_panel_action(_play, "train_explorer")
	_say("ordered a hire at %s: \"%s\"" % [_province_name(seat), _toasts_line()])
	var seen: int = _toast_count()
	_take_turn()
	_say("court news raised this turn:")
	for line: String in _toasts_since(seen):
		_say("  · %s" % line)
	_say("crews: %d → %d; the court stands at %s; Home Army at %s" % [
		before, _civilian_count(), _province_name(_play.capital_province),
		_home_army_place(),
	])
	var new_crews: PackedStringArray = PackedStringArray()
	for raw: Variant in _play.civilian_layer.regions.value(_play.region_index, []):
		var unit: CivilianState = raw
		if unit == null or unit.owner != _play.player_faction:
			continue
		var province: int = _play.world.region(_play.region_index).province_at(
			unit.tile.x, unit.tile.y
		)
		new_crews.append("%s at %s" % [unit.type_id, _province_name(province)])
	_say("crown crews here: %s" % (
		", ".join(new_crews) if not new_crews.is_empty() else "none"
	))


## The crown's Home Army standard and the province it stands in.
func _home_army_place() -> String:
	for army: ArmyState in _play.army_layer.armies:
		if army != null and army.owner == _play.player_faction and army.is_home_army():
			return "%s (%d men)" % [_army_place(army), army.count()]
	return "no Home Army"


## The seat walked into with no battle fought: a rival's host marches into the
## crown's undefended capital, so the province changes hands in the march pass and
## the land pass raises no clash. The rule's trigger is the seat's loss, so the
## court must move on the same turn (wiki: capital-and-connectivity § Capital
## loss and reassignment).
func _walk_in_pass() -> void:
	_say("")
	var seat: int = _seat_now()
	var rival: int = _other_rival(-1)
	if seat < 0 or rival < 0:
		_say("no seat and rival stand for the walk-in pass")
		return
	# One more province stays the crown's, so this pass reads a court move rather
	# than a fall.
	var other: int = _another_holding(seat)
	var keep: Array[int] = [seat]
	if other >= 0:
		keep.append(other)
	_hand_over_but(keep, rival)
	_clear_field()
	_say("--- the seat walked into: %s left holding %s in the Old World, %d colonies in the New ---" % [
		FactionCatalog.name_of(_play.player_faction), _holding_list(_old_world()),
		CapitalLoss.owned_provinces(_new_world(), _play.player_faction).size(),
	])
	var host: int = _stage_walk_in(seat, rival)
	if host < 0:
		_say("no ground beside the seat to march a rival's host from")
		return
	_say("the rival musters %d men at %s and no crown regiment holds the seat" % [
		STORM_MEN, _province_name(host),
	])
	_say("capital verdicts before the turn: seat %s, capital flag %s, chart reads %s" % [
		_province_name(seat), str(_old_world().province_data(seat).capital),
		_province_name(_play.world.capital_province_of(FactionCatalog.OLD_WORLD, _play.player_faction)),
	])
	var seen: int = _toast_count()
	_take_turn()
	_say("court news raised this turn:")
	for line: String in _toasts_since(seen):
		_say("  · %s" % line)
	var after: int = _seat_now()
	_say("after: seat %s (was %s); the old seat is %s's, capital flag %s" % [
		_province_name(after), _province_name(seat),
		FactionCatalog.name_of(_old_world().province_owner(seat)),
		str(_old_world().province_data(seat).capital),
	])
	_say("seat reads: CapitalLoss.seat_of %s · world.capital_province_of %s · play.capital_province %s" % [
		_province_name(CapitalLoss.seat_of(_old_world(), _play.player_faction)),
		_province_name(_play.world.capital_province_of(FactionCatalog.OLD_WORLD, _play.player_faction)),
		_province_name(_play.capital_province),
	])
	_say("Home Army at %s" % _home_army_place())
	if after >= 0:
		# The sheet is opened on the seat the court moved to: the press below is
		# the province sheet's own intent, and its answer names the capital.
		_play.selected_province = after
		var before: int = _play.economy.economy.recruits.pending(
			RecruitQueue.KIND_CIVILIAN, "explorer"
		)
		MapPlayInput.on_panel_action(_play, "train_explorer")
		_say("a hire pressed on the seat the court just moved to: %d pending at the press, %d after" % [
			before,
			_play.economy.economy.recruits.pending(RecruitQueue.KIND_CIVILIAN, "explorer"),
		])


## The crown left with no province in its original region while its host stands
## abroad: the fall takes every province in every region and the host leaves play
## (wiki: capital-and-connectivity § Great Power fall).
func _fall_pass() -> void:
	_say("")
	var seat: int = _seat_now()
	var rival: int = _other_rival(-1)
	if seat < 0 or rival < 0:
		_say("no seat and rival stand for the fall pass")
		return
	var colonies: int = CapitalLoss.owned_provinces(_new_world(), _play.player_faction).size()
	if colonies == 0:
		_say("no New World colony stands — the fall pass cannot read a crossing")
	var colony_ids: Array[int] = _colony_ids()
	var abroad: int = _abroad_province()
	_hand_over_but([seat], rival)
	_clear_field()
	if abroad >= 0:
		_place(_play.player_faction, abroad, HOST_MEN, 340)
		_say("the crown's host stands abroad at %s on the %s chart" % [
			_province_name(abroad), FactionCatalog.region_label(_new_world().region_id),
		])
	_say("--- terminal fall with a host abroad: %s left holding only %s in the Old World, %d colonies in the New ---" % [
		FactionCatalog.name_of(_play.player_faction), _province_name(seat), colonies,
	])
	if _stage_walk_in(seat, rival) < 0:
		_say("no ground beside the seat to march a rival's host from")
		return
	_say("before the turn: crown regiments %d, hulls %d, crews %d, colonies %d" % [
		_play.army_layer.regiment_count_all(_play.player_faction),
		_play.ship_layer.hull_count_all(_play.player_faction),
		_civilian_count(), colonies,
	])
	var seen: int = _toast_count()
	_take_turn()
	_say("court news raised this turn:")
	for line: String in _toasts_since(seen):
		_say("  · %s" % line)
	_say("campaign over: %s; defeat: %s" % [
		str(_play.campaign_over()), _defeat_text(),
	])
	_say("after: crown regiments %d, hulls %d, crews %d; Old World holdings %d, New World %d" % [
		_play.army_layer.regiment_count_all(_play.player_faction),
		_play.ship_layer.hull_count_all(_play.player_faction),
		_civilian_count(),
		CapitalLoss.owned_provinces(_old_world(), _play.player_faction).size(),
		CapitalLoss.owned_provinces(_new_world(), _play.player_faction).size(),
	])
	var still: PackedStringArray = PackedStringArray()
	for army: ArmyState in _play.army_layer.armies:
		if army != null and army.owner == _play.player_faction:
			still.append("%d men at %s" % [army.count(), _army_place(army)])
	_say("crown hosts still on the chart: %s" % (
		", ".join(still) if not still.is_empty() else "none"
	))
	if colonies > 0:
		var owners: PackedStringArray = PackedStringArray()
		for province: ProvinceState in _new_world().provinces:
			if province.id in colony_ids:
				owners.append("%s: %s" % [
					province.name, FactionCatalog.name_of(province.owner),
				])
		_say("the colonies after the fall: %s" % ", ".join(owners))
	var overlay: VictoryOverlay = _play.hud.victory_overlay
	if overlay != null and overlay.is_visible_in_tree():
		var plate: PackedStringArray = PackedStringArray()
		SaveDrive.collect_text(overlay, "", plate)
		_say("defeat plate: %s" % " | ".join(plate))


# --- turns -----------------------------------------------------------------


## One calendar turn through MapPlayTurn, reading every battle plate the turn
## raises and answering whatever consent decision it stops on. The shared closer
## presses once per turn: a decision that runs the suspended turn to its end is
## not pressed a second time.
func _take_turn() -> void:
	SaveDrive.advance(_play, _release_plate)


func _release_plate() -> void:
	SaveDrive.release_plate(_play)


# --- readings --------------------------------------------------------------


func _toasts_since(start: int) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var box: VBoxContainer = _play.hud.despatches.box
	if box != null:
		for index in range(start, box.get_child_count()):
			SaveDrive.collect_text(box.get_child(index), "", lines)
	lines.append_array(_play.hud.despatches.waiting())
	return lines


func _toasts_line() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var box: VBoxContainer = _play.hud.despatches.box
	if box != null and box.get_child_count() > 0:
		SaveDrive.collect_text(box.get_child(box.get_child_count() - 1), "", lines)
	return " / ".join(lines) if not lines.is_empty() else "(no toast)"


func _toast_count() -> int:
	var box: VBoxContainer = _play.hud.despatches.box
	return box.get_child_count() if box != null else 0


func _clear_toasts() -> void:
	var box: VBoxContainer = _play.hud.despatches.box
	if box == null:
		return
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _defeat_text() -> String:
	return "none" if _play.defeat == null else _play.defeat.summary()


func _army_place(army: ArmyState) -> String:
	if army.is_embarked():
		return "aboard a squadron"
	if _play.model != null and army.province >= 0:
		return _play.model.province_name(army.province)
	return "province %d" % army.province


func _civilian_count() -> int:
	var total: int = 0
	for region: int in _play.world.region_count():
		for raw: Variant in _play.civilian_layer.regions.value(region, []):
			var unit: CivilianState = raw
			if unit != null and unit.owner == _play.player_faction:
				total += 1
	return total


# --- places ----------------------------------------------------------------


func _old_world() -> MapModel:
	return _play.world.region(FactionCatalog.OLD_WORLD)


func _new_world() -> MapModel:
	return _play.world.region(FactionCatalog.NEW_WORLD)


func _province_name(province: int) -> String:
	if _play.model == null or province < 0:
		return "—"
	return _play.model.province_name(province)


func _rivals() -> Array[int]:
	var ids: Array[int] = []
	for gp: int in FactionCatalog.great_power_ids():
		if gp != _play.player_faction:
			ids.append(gp)
	return ids


## A crown province in the Old World beside a rival Great Power's ground, with
## the province a player would march into: `{rival, from, target}`.
func _invasion_stage() -> Dictionary:
	var rivals: Array[int] = _rivals()
	for province: ProvinceState in _old_world().provinces:
		if province.owner != _play.player_faction:
			continue
		for id: int in MapGeo.province_neighbors(_old_world(), province.id):
			var holder: int = _old_world().province_owner(id)
			if holder in rivals and FactionCatalog.type_of(holder) == FactionCatalog.Type.GREAT_POWER:
				return {"rival": holder, "from": province.id, "target": id}
	return {}


## Another rival Great Power than `avoid`, or the first one when `avoid` is -1.
func _other_rival(avoid: int) -> int:
	for id: int in _rivals():
		if id != avoid:
			return id
	return -1


## The crown's provinces on one chart, by name.
func _holding_list(model: MapModel) -> String:
	var names: PackedStringArray = PackedStringArray()
	for province: ProvinceState in model.provinces:
		if province.owner == _play.player_faction:
			names.append(province.name)
	return ", ".join(names) if not names.is_empty() else "none"


## Every province on the seat's chart carrying a capital flag, with its owner.
func _capital_flags() -> String:
	var flags: PackedStringArray = PackedStringArray()
	for province: ProvinceState in _old_world().provinces:
		if province.capital:
			flags.append("%s (%s)" % [province.name, FactionCatalog.name_of(province.owner)])
	return ", ".join(flags) if not flags.is_empty() else "none"


## A rival host mustered on ground beside the seat, at war with the crown, with
## no order given: the court's own march pass walks it in. Returns the province
## it musters on, or -1 when nothing borders the seat.
func _stage_walk_in(seat: int, rival: int) -> int:
	var base: int = -1
	for id: int in MapGeo.province_neighbors(_old_world(), seat):
		if _old_world().province_owner(id) == rival:
			base = id
			break
	if base < 0:
		var neighbours: Array[int] = []
		neighbours.assign(MapGeo.province_neighbors(_old_world(), seat))
		neighbours.sort()
		for id: int in neighbours:
			if ProvinceHandover.hand_over(_old_world(), id, rival):
				base = id
				break
	if base < 0:
		return -1
	_place(rival, base, STORM_MEN, 380)
	DiplomacyRules.declare_war(_play.diplomacy, rival, _play.player_faction)
	return base


## The crown's seat as the rules read it, falling back to the session's framing.
func _seat_now() -> int:
	var seat: int = CapitalLoss.seat_of(_old_world(), _play.player_faction)
	return seat if seat >= 0 else _play.capital_province


## Another Old World province the crown holds, or -1.
func _another_holding(seat: int) -> int:
	for province: ProvinceState in _old_world().provinces:
		if province.owner == _play.player_faction and province.id != seat:
			return province.id
	return -1


## Hands every crown province in the Old World that is not in `keep` to `rival`.
func _hand_over_but(keep: Array[int], rival: int) -> void:
	for province: ProvinceState in _old_world().provinces:
		if province.owner == _play.player_faction and not keep.has(province.id):
			ProvinceHandover.hand_over(_old_world(), province.id, rival)


## Clears the field: every standard leaves the chart, so no garrison stands in
## the way of the walk the next pass stages.
func _clear_field() -> void:
	_play.army_layer.armies.clear()
	_play.army_layer._rebuild_markers()


## A New World province the crown holds, or -1.
func _abroad_province() -> int:
	var owned: Array[int] = CapitalLoss.owned_provinces(_new_world(), _play.player_faction)
	return owned[0] if not owned.is_empty() else -1


func _colony_ids() -> Array[int]:
	return CapitalLoss.owned_provinces(_new_world(), _play.player_faction)


## Ground a storm can take: no fort, no garrison of its own. The province keeps
## its owner until the battle pass hands it over.
func _fixture_ground(province: int) -> int:
	var data: ProvinceState = _old_world().province_data(province)
	if data != null:
		data.fort_level = 0
	for army: ArmyState in _play.army_layer.armies.duplicate():
		if army != null and army.province == province and army.owner != _play.player_faction:
			_play.army_layer.armies.erase(army)
			_play.army_layer.remove_marker(army)
	return province


# --- seating ---------------------------------------------------------------


func _seat(
	owner: int, province: int, count: int, offset: int, moved: bool = false,
	home: bool = false
) -> ArmyState:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	var army: ArmyState = ArmyState.muster(
		_play.army_layer.next_army + offset,
		owner,
		province,
		home,
		types,
		_play.army_layer.next_regiment + offset
	)
	army.moved = moved
	return army


## Seats a host on the layer and draws its marker: the fixture every pass uses
## for the army a player would have raised and marched there.
func _place(
	owner: int, province: int, count: int, offset: int, moved: bool = false,
	home: bool = false
) -> ArmyState:
	var army: ArmyState = _seat(owner, province, count, offset, moved, home)
	_play.army_layer.armies.append(army)
	_play.army_layer.add_marker(army)
	return army


# --- finish ----------------------------------------------------------------


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_seat_lost_mid_invasion: %d steps ---" % _steps.size())
	quit()