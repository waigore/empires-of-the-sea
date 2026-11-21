extends SceneTree
## Headless playtest drive for a routed host (wiki: military-armies § Movement
## and attacks, § Combat and province loss; combat § Outcomes): the crown's army
## loses a storm but keeps men, and stands on the beaten court's own ground. The
## drive reads the despatch that settles it, the army dossier's own place line
## and hint, every province the crown may still march to, the refusal a home
## march hears, and then walks the host out — one province at a time — until
## home is open again. A second pass seats the same beaten host in a rival
## province that borders the crown, so the first leg onto own land is read beside
## it.
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_routed_host.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const ADVANCED: String = "turns100"
## Six guards against seven lose the band between 0.67 and 1.0: half the line
## falls on each side and the field stands off (wiki: combat § Auto-resolve
## ratio bands).
const HOST_MEN: int = 6
const GARRISON_MEN: int = 7

var _steps: PackedStringArray = PackedStringArray()
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = await Launch.open_map(self, SEED_TEXT, 0, ADVANCED)
	if screen == null:
		_finish()
		return
	_play = screen.play
	_say("seed %s, turn %d — %s holds %d provinces in %s" % [
		SEED_TEXT, _play.turn, FactionCatalog.name_of(_play.player_faction),
		CapitalLoss.owned_provinces(_play.model, _play.player_faction).size(),
		FactionCatalog.region_label(_play.region_index),
	])
	var rival: int = _first_rival()
	if rival < 0:
		_say("no rival Great Power holds land in this region")
		_finish()
		return
	DiplomacyRules.declare_war(_play.diplomacy, _play.player_faction, rival)
	_say("war with %s" % FactionCatalog.name_of(rival))
	var stranded: int = _stranded_province(rival)
	var bordered: int = _bordered_province(rival)
	if stranded < 0:
		_say("no rival province without a crown neighbour — the stranded pass cannot run")
	else:
		_stranded_pass(stranded, rival)
	if bordered < 0:
		_say("no rival province beside crown land — the bordered pass cannot run")
	else:
		_bordered_pass(bordered, rival)
	_finish()


# --- passes ----------------------------------------------------------------


## The crown loses the storm and its survivors stand where no own land borders:
## the dossier, the tap list and the home march the crown would order.
func _stranded_pass(province: int, rival: int) -> void:
	_say("")
	_say("--- stranded: %s %s, beaten, standing in %s ---" % [
		FactionCatalog.name_of(_play.player_faction), _play.model.province_name(province),
		FactionCatalog.name_of(rival),
	])
	var host: ArmyState = _seat_fight(province, rival)
	if host == null:
		_say("the host was wiped — no routed army stands")
		return
	_host_readings(host, province)
	_walk_home(host, province)


## The same beaten host, but the rival province borders crown land: the first leg
## home is one march onto the own province beside it, and interior lines carry it
## to the seat from there — the walk the rule gives a host off its own ground.
func _bordered_pass(province: int, rival: int) -> void:
	_say("")
	_say("--- bordered: %s beaten in %s, which touches crown land ---" % [
		FactionCatalog.name_of(_play.player_faction), _play.model.province_name(province),
	])
	var host: ArmyState = _seat_fight(province, rival)
	if host == null:
		_say("the host was wiped — no routed army stands")
		return
	_host_readings(host, province)
	_first_leg_home(host, province)


## Presses the one own province beside the host, then the seat the next turn: the
## road home is a walk, and interior lines open only once the host is home.
func _first_leg_home(host: ArmyState, from: int) -> void:
	_say("")
	_say("--- the first leg home from %s ---" % _play.model.province_name(from))
	var destinations: Array[int] = ArmyMovement.destinations(_play.model, host)
	var leg: int = _own_destination(host, destinations)
	if leg < 0:
		_say("no own province beside the host — the first leg is not open")
		return
	var order: Dictionary = _play.army_layer.order(
		host, leg, MapPlayArmies.may_invade(_play, leg)
	)
	_say("step 1: march %s → %s: %s\"%s\"" % [
		_play.model.province_name(from), _play.model.province_name(leg),
		"ok " if bool(order.get("ok", false)) else "refused ",
		String(order.get("reason", "")),
	])
	if not bool(order.get("ok", false)):
		return
	host.moved = false
	var home: int = _play.capital_province
	var reached: Dictionary = _play.army_layer.order(
		host, home, MapPlayArmies.may_invade(_play, home)
	)
	_say("step 2: interior lines to %s: %s\"%s\" (now at %s)" % [
		_play.model.province_name(home),
		"ok " if bool(reached.get("ok", false)) else "refused ",
		String(reached.get("reason", "")), _play.model.province_name(host.province),
	])


## What the court reads about a beaten host: the dossier's own lines, the tap
## list, and the words a home march would answer.
func _host_readings(host: ArmyState, province: int) -> void:
	_say("host: %s %d at %s (owner %s)" % [
		FactionCatalog.name_of(host.owner), host.count(),
		_play.model.province_name(host.province),
		_owner_name(_play.model.province_owner(host.province)),
	])
	host.moved = false
	MapPlayArmies.select(_play, host)
	var panel: ArmyPanel = _play.hud.panels.army_panel
	_say("dossier place:  \"%s\"" % panel._location.text)
	_say("dossier status: \"%s\"" % panel._status.text)
	_say("dossier hint:   \"%s\"" % panel._hint.text)
	_say("dossier strength: \"%s\"" % panel._strength.text)
	var destinations: Array[int] = ArmyMovement.destinations(_play.model, host)
	var own: int = 0
	var list: PackedStringArray = []
	for id: int in destinations:
		var holder: int = _play.model.province_owner(id)
		if holder == host.owner:
			own += 1
		list.append("%s (%s)" % [_play.model.province_name(id), _owner_name(holder)])
	_say("tap list: %d provinces, %d of them ours — %s" % [
		destinations.size(), own, ", ".join(list) if not list.is_empty() else "none",
	])
	_say("home (%s) is in the tap list: %s" % [
		_play.model.province_name(_play.capital_province),
		str(destinations.has(_play.capital_province)),
	])
	MapPlayArmies.refresh_options(_play, host)
	_say("the overlay highlights %d province%s" % [
		_play.overlay.move_provinces.size(),
		"" if _play.overlay.move_provinces.size() == 1 else "s",
	])
	_say("the rule answers a home march with \"%s\"" % ArmyMovement.can_move(
		_play.model, host, _play.capital_province
	).get("reason", ""))


## Walks the host out the way a crown must: one adjacent province at a time,
## reading the tap list after each step until own land is open again.
func _walk_home(host: ArmyState, from: int) -> void:
	_say("")
	_say("--- the walk home from %s ---" % _play.model.province_name(from))
	var province: int = from
	for step in 4:
		var destinations: Array[int] = ArmyMovement.destinations(_play.model, host)
		if destinations.is_empty():
			_say("step %d: nothing left to march to" % (step + 1))
			return
		if destinations.has(_play.capital_province) or _own_destination(host, destinations) >= 0:
			_say("step %d: own land is open from %s at last — %d own province%s in the tap list" % [
				step + 1, _play.model.province_name(province),
				_own_destinations(host, destinations).size(),
				"" if _own_destinations(host, destinations).size() == 1 else "s",
			])
			return
		var next: int = _toward_home(host, destinations)
		var result: Dictionary = _play.army_layer.order(
			host, next, MapPlayArmies.may_invade(_play, next)
		)
		_say("step %d: march %s → %s (%s): %s\"%s\"" % [
			step + 1, _play.model.province_name(province),
			_play.model.province_name(next), _owner_name(_play.model.province_owner(next)),
			"ok " if bool(result.get("ok", false)) else "refused ",
			String(result.get("reason", "")),
		])
		if not bool(result.get("ok", false)):
			return
		province = host.province
		if host.is_empty():
			_say("step %d: the host fell on the road" % (step + 1))
			return
		host.moved = false


# --- seating ---------------------------------------------------------------


## Seats a garrison in the rival province and sends six of the crown's guards at
## it, then resolves the real battle pass. The garrison is grown until the crown
## loses the field and keeps men — the band a beaten side survives
## (wiki: combat § Auto-resolve ratio bands). Returns the crown's surviving army
## at that province (null when every attempt wiped it).
func _seat_fight(province: int, rival: int) -> ArmyState:
	for men: int in [GARRISON_MEN, 9, 10, 12, 14, 16]:
		var host: ArmyState = _attempt(province, rival, men)
		if host != null:
			return host
	_say("no garrison size left the host standing on the field")
	return null


func _attempt(province: int, rival: int, men: int) -> ArmyState:
	_play.army_layer.armies.clear()
	_play.army_layer._rebuild_markers()
	_play.model.province_data(province).owner = rival
	_play.model.province_data(province).fort_level = 0
	_seat(rival, province, men, 100, false)
	_seat(_play.player_faction, province, HOST_MEN, 200, true)
	var battles: Array[Dictionary] = _play.army_layer.resolve_battles(
		_play.world, MapPlayLandTurn.battle_context(_play)
	)
	if battles.is_empty():
		_say("no battle was fought")
		return null
	var survivors: ArmyState = null
	for army: ArmyState in _play.army_layer.armies:
		if army != null and army.owner == _play.player_faction and army.count() > 0:
			survivors = army
	for battle: Dictionary in battles:
		_say("battle (%d of the crown's %d against %d): %s v %s at %s — %s" % [
			HOST_MEN, HOST_MEN, men,
			FactionCatalog.name_of(int(battle["attacker"])),
			FactionCatalog.name_of(int(battle["defender"])),
			_play.model.province_name(int(battle["province"])),
			ArmyCombat.outcome_label(int(battle["outcome"])),
		])
	if survivors == null or int(battles[0]["outcome"]) == ArmyCombat.Outcome.ATTACKER_VICTORY:
		return null
	for battle: Dictionary in battles:
		_say("despatch: %s" % BattleReport.describe_land(
			battle, _play.model.province_name(int(battle["province"])),
			FactionCatalog.names()
		))
		_say("lost: attacker %d of %d, defender %d of %d; owner after %s" % [
			(battle.get("attacker_lost", []) as Array).size(), HOST_MEN,
			(battle.get("defender_lost", []) as Array).size(), men,
			_owner_name(_play.model.province_owner(province)),
		])
		_say("quick started: %d v %d" % [
			int((battle.get("quick", {}) as Dictionary).get("attacker_start", -1)),
			int((battle.get("quick", {}) as Dictionary).get("defender_start", -1)),
		])
	return survivors


func _seat(owner: int, province: int, count: int, offset: int, moved: bool) -> void:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	var army: ArmyState = ArmyState.muster(
		_play.army_layer.next_army + offset, owner, province, false, types,
		_play.army_layer.next_regiment + offset
	)
	army.moved = moved
	_play.army_layer.armies.append(army)
	_play.army_layer.add_marker(army)


# --- places ----------------------------------------------------------------


func _first_rival() -> int:
	for province: ProvinceState in _play.model.provinces:
		if province.owner == _play.player_faction or province.owner == MapModel.NO_ID:
			continue
		if FactionCatalog.type_of(province.owner) == FactionCatalog.Type.GREAT_POWER:
			return province.owner
	return -1


## A rival province no crown province touches, with at least one neighbour the
## crown may still walk into — the road home is a walk, not a march.
func _stranded_province(rival: int) -> int:
	for province: ProvinceState in _play.model.provinces:
		if province.owner != rival:
			continue
		var neighbours: Array[int] = []
		neighbours.assign(MapGeo.province_neighbors(_play.model, province.id))
		var own_beside: bool = false
		var walk: int = -1
		for id: int in neighbours:
			var holder: int = _play.model.province_owner(id)
			if holder == _play.player_faction:
				own_beside = true
			if holder != rival and walk < 0:
				walk = id
		if own_beside or walk < 0:
			continue
		return province.id
	return -1


## A rival province that touches crown land: one march home by interior lines.
func _bordered_province(rival: int) -> int:
	for province: ProvinceState in _play.model.provinces:
		if province.owner != rival:
			continue
		for id: int in MapGeo.province_neighbors(_play.model, province.id):
			if _play.model.province_owner(id) == _play.player_faction:
				return province.id
	return -1


# --- readings --------------------------------------------------------------


func _own_destinations(army: ArmyState, destinations: Array[int]) -> Array[int]:
	var own: Array[int] = []
	for id: int in destinations:
		if _play.model.province_owner(id) == army.owner:
			own.append(id)
	return own


func _own_destination(army: ArmyState, destinations: Array[int]) -> int:
	var own: Array[int] = _own_destinations(army, destinations)
	return own[0] if not own.is_empty() else -1


## The neighbour that puts the host nearest the seat, ties to the lowest id.
func _toward_home(army: ArmyState, destinations: Array[int]) -> int:
	var best: int = destinations[0]
	var best_gap: int = 1 << 20
	for id: int in destinations:
		var gap: int = ArmyMovement.land_reachable(_play.model, id, army.owner).size()
		var touches: bool = false
		for next: int in MapGeo.province_neighbors(_play.model, id):
			if _play.model.province_owner(next) == army.owner:
				touches = true
		var score: int = 0 if touches else 1000 - gap
		if score < best_gap:
			best = id
			best_gap = score
	return best


func _owner_name(faction: int) -> String:
	if faction == MapModel.NO_ID:
		return "unowned"
	return FactionCatalog.name_of(faction)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_routed_host: %d steps ---" % _steps.size())
	quit()
