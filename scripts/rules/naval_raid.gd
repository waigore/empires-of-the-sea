class_name NavalRaid
extends RefCounted
## Trade and transport raiding by patrol/blockade squadrons (wiki:
## ships-and-naval § Trade and Transport Interception). Pure rules: the home
## fleet's imports this turn are the cargo at risk; escorts cut the chance and
## a successful raid skims a fraction of every delivered commodity.
##
## A raid is a commerce raid: it pinches **cargo** and may send one **merchant
## hull** to the bottom, never a warship and never a hull on the raider's own
## side (DR-20261111-17). The hull term lives in [NavalHullLoss]; which
## squadrons work a coast is [NavalStation]'s reading (`coast_zones`,
## `hostile_groups`). This module owns the roll, the skim and the prize walk
## (REQ-P3-01).

const BLOCKADE_BONUS: float = 1.25
const MIN_EFFICIENCY: float = 0.3
const MAX_EFFICIENCY: float = 0.7
## Roll salt for the raid the crown suffers this turn.
const ROLL_TAG: int = 77
## The hull roll is its own draw, so cargo and a hull are never decided by one
## unlucky number (DR-20261111-17).
const HULL_TAG: int = 1777
## Prizes roll on their own salts, one per victim, so a crown can lose cargo and
## take it in the same zone without both raids sharing a single roll.
const PRIZE_TAG_BASE: int = 977
const HULL_PRIZE_TAG_BASE: int = 2777


## One raider group tries the home fleet's cargo. `roll_value` is for tests; a
## negative value uses the deterministic campaign roll. `has_tech` is the
## crown-tech query: a raider holding Privateering Companies raids better
## (wiki: ships-and-naval § Trade and Transport Interception).
static func resolve(
	model: MapModel,
	fleets: Array,
	victim: int,
	home: FleetState,
	imports: Dictionary,
	hostile: Callable = Callable(),
	seed_value: int = 0,
	turn: int = 0,
	roll_value: float = -1.0,
	has_tech: Callable = Callable(),
	hull_roll: float = -1.0
) -> Dictionary:
	if model == null or home == null or imports.is_empty():
		return _nothing("no cargo at sea", victim)
	return _raid(
		model, fleets, victim, home, imports, hostile,
		seed_value, turn, roll_value, has_tech, -1, ROLL_TAG, HULL_TAG, hull_roll,
		true
	)


## Every raid the crown's own Patrol/Blockade squadrons work on rival trade this
## turn. `victims` is faction -> `{ "imports": {id: units}, "home": FleetState }`
## for each howling rival the crown has cargo to take from; only a declared war
## pays. Returns one raid per victim, in ascendum, with the cargo to seize (the
## caller moves it into the crown's stockpile) and any merchant hull sent down
## (already removed from the rival's home fleet).
static func resolve_prizes(
	model: MapModel,
	fleets: Array,
	crown: int,
	victims: Dictionary,
	hostile: Callable = Callable(),
	seed_value: int = 0,
	turn: int = 0,
	has_tech: Callable = Callable(),
	roll_value: float = -1.0,
	hull_roll: float = -1.0
) -> Array[Dictionary]:
	var raids: Array[Dictionary] = []
	if model == null or fleets.is_empty() or victims.is_empty():
		return raids
	var order: Array[int] = []
	for raw: Variant in victims.keys():
		order.append(int(raw))
	order.sort()
	for victim: int in order:
		if victim == crown:
			continue
		var entry: Dictionary = victims[victim] as Dictionary
		var imports: Dictionary = entry.get("imports", {}) as Dictionary
		var home: FleetState = entry.get("home", null) as FleetState
		if home == null or imports.is_empty():
			continue
		var raid: Dictionary = _raid(
			model, fleets, victim, home, imports, hostile,
			seed_value, turn, roll_value, has_tech, crown,
			PRIZE_TAG_BASE + victim, HULL_PRIZE_TAG_BASE + victim, hull_roll
		)
		if bool(raid.get("ok", false)):
			raids.append(raid)
	return raids


## The trade-raid chance one group rolls against a laden home fleet: the common
## base times the blockade bonus times the escort cover, clamped (wiki:
## ships-and-naval § Trade and Transport Interception). Shared with the dossier
## so the number the player reads is the number the rules roll.
static func trade_chance(
	group: Array, home: FleetState, mission: int, has_tech: Callable = Callable()
) -> float:
	if group.is_empty() or home == null:
		return 0.0
	# The trade-raid formula uses a common base chance times the blockade
	# bonus; the movement table's own mission factor would double-count it.
	var base: float = NavalInterception.chance(
		group, [home], FleetState.Mission.PATROL, has_tech
	)
	var bonus: float = BLOCKADE_BONUS if mission == FleetState.Mission.BLOCKADE else 1.0
	return clampf(
		base * bonus * (1.0 - NavalHullLoss.escort_factor(home)),
		NavalInterception.MIN_CHANCE,
		NavalInterception.MAX_CHANCE
	)


## What a station's raid is worth before the player commits: the chance it rolls
## and the cargo it would skim, from the same maths the raid itself uses, so the
## dossier can never promise a roll the rules do not make (REQ-P2-03).
static func preview(
	group: Array,
	home: FleetState,
	imports: Dictionary,
	mission: int,
	has_tech: Callable = Callable()
) -> Dictionary:
	var stock: int = total_of(imports)
	if group.is_empty() or home == null or stock <= 0:
		return {
			"chance": 0.0, "efficiency": MIN_EFFICIENCY, "expected": 0,
			"hull_chance": 0.0, "hull_at_risk": "",
		}
	var efficiency: float = _efficiency(_group_strength(group), _hull_strength(home))
	var target: Dictionary = NavalHullLoss.at_risk(home)
	return {
		"chance": trade_chance(group, home, mission, has_tech),
		"efficiency": efficiency,
		"expected": maxi(1, int(floor(float(stock) * efficiency))),
		"hull_chance": NavalHullLoss.chance(home),
		"hull_at_risk": String(target.get("type_id", "")),
	}


## Chance a successful raid sends one merchant hull down. Kept on this module so
## callers price a raid in one place; the rule lives in [NavalHullLoss].
static func hull_loss_chance(home: FleetState) -> float:
	return NavalHullLoss.chance(home)


## The shared raid: roll, skim cargo and roll again for one merchant hull.
## `only_owner` limits the raiders to one crown (a prize raid); the tags keep a
## crown's losses and its prizes on separate rolls. `weigh_together` makes the
## groups one raid: the strongest of them rolls, so the crown off whose coast
## they stand meets the best raid of the turn and only that one (wiki:
## ships-and-naval § Trade and Transport Interception; DR-20261111-20 § Change).
static func _raid(
	model: MapModel,
	fleets: Array,
	victim: int,
	home: FleetState,
	imports: Dictionary,
	hostile: Callable,
	seed_value: int,
	turn: int,
	roll_value: float,
	has_tech: Callable,
	only_owner: int,
	roll_tag: int,
	hull_tag: int,
	hull_roll: float,
	weigh_together: bool = false
) -> Dictionary:
	var groups: Dictionary = NavalStation.hostile_groups(
		model, fleets, victim, hostile, only_owner
	)
	var keys: Array[Vector2i] = []
	for raw: Variant in groups.keys():
		var key: Vector2i = raw
		keys.append(key)
	keys.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x if a.x != b.x else a.y < b.y
	)
	var best_chance: float = 0.0
	# The raid a crown suffers is **one** raid: the raiders off its coast are
	# weighed together and the best one rolls, in her own water and at her own
	# efficiency (DR-20261111-20 § Change). Separate rolls would hand the crown
	# whichever weaker squadron beat its own number. A prize raid keeps the walk,
	# because each raider there rolls its own salt, one prize per victim.
	if weigh_together and not keys.is_empty():
		var best: Dictionary = _weighed(model, groups, keys, home, hostile, has_tech)
		if best.is_empty():
			return _nothing("nothing taken", victim)
		var chosen: Vector2i = best["key"]
		best_chance = float(best["chance"])
		keys.clear()
		keys.append(chosen)
	for key: Vector2i in keys:
		var group: Array = groups[key] as Array
		var mission: int = FleetMissions.station_mission(model, group, hostile)
		if mission == FleetState.Mission.NONE:
			continue
		var found: float = trade_chance(group, home, mission, has_tech)
		best_chance = maxf(best_chance, found)
		var rolled: float = roll_value
		if rolled < 0.0:
			rolled = NavalInterception.roll(
				seed_value, turn, key.x, key.y, roll_tag
			)
		if rolled >= found:
			continue
		var efficiency: float = _efficiency(
			_group_strength(group), _hull_strength(home)
		)
		var losses: Dictionary = _losses(imports, efficiency)
		var total: int = total_of(losses)
		var sunk: Dictionary = NavalHullLoss.draw(
			home, key.y, seed_value, turn, key.x, hull_roll, hull_tag
		)
		var hulls: Array[Dictionary] = []
		var hull: Dictionary = sunk.get("hull", {}) as Dictionary
		if not hull.is_empty():
			hulls.append(hull)
		return {
			"ok": total > 0 or not hulls.is_empty(),
			"chance": found,
			"roll": rolled,
			"efficiency": efficiency,
			"raider": key.y,
			"victim": victim,
			"zone": key.x,
			"losses": losses,
			"lost_total": total,
			# The commerce raid's second ledger: at most one merchant hull.
			"hulls_lost": hulls,
			"hull_chance": float(sunk.get("chance", 0.0)),
			"hull_roll": float(sunk.get("roll", 1.0)),
		}
	var idle: Dictionary = _nothing("nothing taken", victim)
	idle["chance"] = best_chance
	return idle


## The strongest raid the groups off the victim's coast can make: the group key
## and the chance it rolls, weighed by the number the dossier prices them with
## (`trade_chance`), so the water the crown reads and the water that raids it are
## one read. Ties keep the lower key: the walk takes only a strictly better raid.
static func _weighed(
	model: MapModel,
	groups: Dictionary,
	keys: Array[Vector2i],
	home: FleetState,
	hostile: Callable,
	has_tech: Callable
) -> Dictionary:
	var best: Dictionary = {}
	for key: Vector2i in keys:
		var group: Array = groups[key] as Array
		var mission: int = FleetMissions.station_mission(model, group, hostile)
		if mission == FleetState.Mission.NONE:
			continue
		var found: float = trade_chance(group, home, mission, has_tech)
		if best.is_empty() or found > float(best["chance"]):
			best = {"key": key, "chance": found}
	return best


## Raid efficiency rises with the raider's hull strength against the laden home
## fleet's, inside the documented 0.3…0.7 band.
static func _efficiency(raider_strength: float, defender_strength: float) -> float:
	return clampf(
		MIN_EFFICIENCY
		+ (MAX_EFFICIENCY - MIN_EFFICIENCY)
		* raider_strength / maxf(raider_strength + defender_strength, 0.001),
		MIN_EFFICIENCY,
		MAX_EFFICIENCY
	)


## Skims floor(total × efficiency) units, at least one when any cargo is at sea,
## and spreads the loss across the commodities.
static func _losses(imports: Dictionary, efficiency: float) -> Dictionary:
	var ids: Array[String] = []
	var total_qty: int = 0
	for raw_id: Variant in imports.keys():
		ids.append(String(raw_id))
		total_qty += maxi(int(imports[raw_id]), 0)
	ids.sort()
	if total_qty <= 0:
		return {}
	var target: int = maxi(1, int(floor(float(total_qty) * efficiency)))
	var losses: Dictionary = {}
	var assigned: int = 0
	for id: String in ids:
		var quantity: int = maxi(int(imports[id]), 0)
		var take: int = mini(int(floor(float(quantity) * efficiency)), quantity)
		losses[id] = take
		assigned += take
	var remainder: int = target - assigned
	while remainder > 0:
		var pick: String = ""
		var room: int = 0
		for id: String in ids:
			var left: int = maxi(int(imports[id]), 0) - int(losses.get(id, 0))
			if left > room:
				room = left
				pick = id
		if pick.is_empty():
			break
		losses[pick] = int(losses[pick]) + 1
		remainder -= 1
	return losses


## Units in a cargo dictionary (losses, prizes): the one place a raid totals.
static func total_of(cargo: Dictionary) -> int:
	var total: int = 0
	for raw_id: Variant in cargo.keys():
		total += maxi(int(cargo[raw_id]), 0)
	return total


## Σ HULL over a group's hulls: the raider side of the efficiency term. Same
## published hull pool [NavalStrength] totals, so a raid never prices a weight
## the dossier would not print (REQ-P2-03).
static func _group_strength(group: Array) -> float:
	var total: float = 0.0
	for fleet: FleetState in group:
		total += _hull_strength(fleet)
	return total


static func _hull_strength(home: FleetState) -> float:
	if home == null:
		return 0.0
	return float(NavalStrength.squadron(home)["totals"].get("hull", 0))


static func _nothing(reason: String, victim: int) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"chance": 0.0,
		"victim": victim,
		"losses": {},
		"lost_total": 0,
		"hulls_lost": [],
		"hull_chance": 0.0,
		"hull_roll": 1.0,
	}
