class_name NavalStrength
extends RefCounted
## The naval combat maths as plain data (wiki: ships-and-naval § Naval Strength
## Aggregation Formula): per-type hull rows, the squadron's FRP/RNG/ARM/HULL/MV
## totals, the weighted strength the battle resolver uses, the hull pool that
## absorbs damage, and the share of strength each side holds in a sea zone.
## Node-free, so the map marker, the fleet dossier and the despatch read the
## same numbers the resolver fights with (REQ-P2-03, REQ-P3-03).

const STAT_KEYS: Array[String] = ["frp", "rng", "arm", "hull", "mv"]
const OUTCOME_UNKNOWN: int = -1
const OUTCOME_WIN: int = 0
const OUTCOME_DRAW: int = 1
const OUTCOME_LOSS: int = 2


## One aggregated row per hull type, first-seen order, with its weighted
## strength and durability. Instance ids stay in FleetState; this is a reading.
## Named for the squadron it reads, so a caller's `fleet` variable never shadows
## it.
static func squadron(fleet: FleetState) -> Dictionary:
	var rows: Array[Dictionary] = []
	var totals: Dictionary = _zero_totals()
	var strength: float = 0.0
	var durability: float = 0.0
	if fleet == null:
		return _snapshot(rows, totals, strength, durability)
	for hull_id: String in fleet.hulls:
		var type_id: String = fleet.type_of(hull_id)
		var data: Dictionary = ShipStats.entry(type_id)
		for key: String in STAT_KEYS:
			totals[key] = int(totals[key]) + int(data[key])
		strength += ShipStats.strength(type_id)
		durability += ShipStats.durability(type_id)
		var row: Dictionary = _row(rows, type_id)
		row["count"] = int(row["count"]) + 1
	return _snapshot(rows, totals, strength, durability)


## Weighted strength of one squadron; the resolver's own aggregation, so the
## dossier can never print a number the battle would not use.
static func strength(fleet: FleetState) -> float:
	if fleet == null:
		return 0.0
	return NavalCombat.side_strength([fleet])


static func durability(fleet: FleetState) -> float:
	if fleet == null:
		return 0.0
	return NavalCombat.side_durability([fleet])


## The dossier's reading of one squadron: its own maths, plus — when it is at
## sea — the share of the zone it would fight for. The one call the fleet
## dossier makes, so the view never assembles the numbers itself. `factors`
## carries the difficulty layer's per-owner strength multiplier and `leaders` the
## crown's roster, so the odds printed are the odds the resolver will strike
## (REQ-P2-03).
static func dossier(
	fleets: Array,
	fleet: FleetState,
	hostile: Callable = Callable(),
	factors: Dictionary = {},
	leaders: Dictionary = {},
	known: Callable = Callable()
) -> Dictionary:
	if fleet == null:
		return {}
	var row: Dictionary = squadron(fleet)
	var zone: Dictionary = NavalStrength.zone(fleets, fleet, hostile, factors, leaders, known)
	if not zone.is_empty():
		row["zone"] = zone
	return row


## A sighted squadron the crown has not yet read: the dossier prints `???` and
## no maths at all, so a first sighting never leaks her weight (wiki:
## ships-and-naval § Sighted strength).
static func fogged() -> Dictionary:
	return {"count": 1, "known": false, "strength": 0.0, "durability": 0.0}


## Share of a contested sea zone each side holds. Own strength aggregates every
## squadron the fleet's owner keeps in that zone (a side fights as one); the foe
## aggregates every hostile squadron at sea there. Ports never fight, so a
## moored squadron gets no odds. Empty when the fleet is in port or absent.
## `factors` is the difficulty layer's per-owner multiplier (wiki: ruleset-config
## § Difficulty): two rivals share one factor, so their mutual ratio stays
## published, and the human crown carries none. `leaders` applies the one
## published naval row (de Ruyter's +15%), exactly as the resolver does.
static func zone(
	fleets: Array,
	fleet: FleetState,
	hostile: Callable = Callable(),
	factors: Dictionary = {},
	leaders: Dictionary = {},
	known: Callable = Callable()
) -> Dictionary:
	if fleet == null or not fleet.is_at_sea():
		return {}
	var own: float = 0.0
	var own_hulls: int = 0
	var foe: float = 0.0
	var foe_hulls: int = 0
	var foes: Array[int] = []
	var unread: bool = false
	for other: FleetState in fleets:
		if other == null or not other.is_at_sea() or other.sea_zone != fleet.sea_zone:
			continue
		if other.owner == fleet.owner:
			own += strength(other) * _factor(factors, other.owner) * _leader(leaders, other.owner)
			own_hulls += other.ship_count()
			continue
		if not Hostility.between(hostile, fleet.owner, other.owner):
			continue
		# A rival the crown has not read weighs in with nothing: the share stays
		# unknown until her watch closes (wiki: ships-and-naval § Sighted strength).
		if known.is_valid() and not bool(known.call(other)):
			unread = true
			continue
		foe += strength(other) * _factor(factors, other.owner) * _leader(leaders, other.owner)
		foe_hulls += other.ship_count()
		if not foes.has(other.owner):
			foes.append(other.owner)
	if own_hulls == 0:
		own = strength(fleet) * _factor(factors, fleet.owner) * _leader(leaders, fleet.owner)
		own_hulls = fleet.ship_count()
	var row: Dictionary = {
		"own": own,
		"own_hulls": own_hulls,
		"foe": foe,
		"foe_hulls": foe_hulls,
		"foes": foes,
		"unread": unread,
	}
	row.merge(odds(own, foe))
	if unread:
		row["outcome"] = OUTCOME_UNKNOWN
	return row


## The battle's arithmetic: the share of combined strength a side holds, and
## whether that share wins, loses or leaves the zone undecided. The resolver
## calls a stalemate inside ±WIN_EDGE of an even split (wiki: § Naval Combat
## Resolution), so the boundary itself is a draw.
static func odds(own: float, foe: float) -> Dictionary:
	var total: float = own + foe
	var share: float = 0.5
	var outcome: int = OUTCOME_DRAW
	if total > 0.0:
		share = own / total
		if share > need():
			outcome = OUTCOME_WIN
		elif share < 1.0 - need():
			outcome = OUTCOME_LOSS
	return {"share": share, "need": need(), "outcome": outcome}


## Strength share that wins a contested zone: an even split plus the resolver's
## edge. A share inside the band either side of even is the resolver's stalemate.
static func need() -> float:
	return 0.5 + NavalCombat.WIN_EDGE


## "FRP 8 + RNG 5×0.4 + ARM 4×0.15 + MV 7×0.1": every stat the weighted strength
## spends, with its weight, so the number on the dossier can be checked by hand.
static func formula(totals: Dictionary) -> String:
	return "FRP %d + RNG %d×%.1f + ARM %d×%.2f + MV %d×%.1f" % [
		int(totals.get("frp", 0)),
		int(totals.get("rng", 0)),
		ShipStats.RNG_WEIGHT,
		int(totals.get("arm", 0)),
		ShipStats.ARM_WEIGHT,
		int(totals.get("mv", 0)),
		ShipStats.MV_WEIGHT,
	]


## "FRP 4 · RNG 3 · ARM 2 · HULL 4 · MV 3 · 5.8 strength": one hull's line in the
## yard, where a hull is broken up and its numbers matter most.
static func hull_line(type_id: String) -> String:
	var data: Dictionary = ShipStats.entry(type_id)
	return "FRP %d · RNG %d · ARM %d · HULL %d · MV %d · %.1f strength" % [
		int(data["frp"]), int(data["rng"]), int(data["arm"]),
		int(data["hull"]), int(data["mv"]), ShipStats.strength(type_id),
	]


## "Hull pool 9.2 — each hull sinks at HULL × (1 + ARM/10)": the damage the
## victor's guns must spend. The pool is summed per hull, so a mixed squadron is
## never one multiplication of its totals (REQ-P2-03).
static func pool_text(durability: float) -> String:
	return "Hull pool %.1f — each hull sinks at HULL × (1 + ARM/10)" % durability


static func outcome_of(odds_row: Dictionary) -> int:
	return int(odds_row.get("outcome", OUTCOME_UNKNOWN))


## "56%": the share as the court reads it.
static func share_text(odds_row: Dictionary) -> String:
	return "%d%%" % int(round(float(odds_row.get("share", 0.5)) * 100.0))


static func _snapshot(
	rows: Array[Dictionary], totals: Dictionary, strength_value: float, durability: float
) -> Dictionary:
	return {
		"count": _hull_total(rows),
		"types": rows,
		"totals": totals,
		"strength": strength_value,
		"durability": durability,
		"formula": formula(totals),
		"pool": pool_text(durability),
	}


static func _row(rows: Array[Dictionary], type_id: String) -> Dictionary:
	for row: Dictionary in rows:
		if String(row["type_id"]) == type_id:
			return row
	var data: Dictionary = ShipStats.entry(type_id)
	var fresh: Dictionary = {
		"type_id": type_id,
		"name": ShipStats.display_name(type_id),
		"count": 0,
		"warship": ShipStats.is_warship(type_id),
		"strength": ShipStats.strength(type_id),
		"durability": ShipStats.durability(type_id),
	}
	for key: String in STAT_KEYS:
		fresh[key] = int(data[key])
	rows.append(fresh)
	return fresh


static func _hull_total(rows: Array[Dictionary]) -> int:
	var total: int = 0
	for row: Dictionary in rows:
		total += int(row["count"])
	return total


static func _zero_totals() -> Dictionary:
	var totals: Dictionary = {}
	for key: String in STAT_KEYS:
		totals[key] = 0
	return totals


## The difficulty layer's factor for one owner; an unrecorded side fights as
## published, so a hand-built read (tests, an observer) needs no table.
static func _factor(factors: Dictionary, owner: int) -> float:
	return float(factors.get(owner, 1.0))


## The leader's published naval row for a side: de Ruyter's +15%, else 1.0
## (wiki: leader-bonuses § When Bonuses Apply).
static func _leader(leaders: Dictionary, owner: int) -> float:
	return LeaderCatalog.naval_multiplier(String(leaders.get(owner, "")))
