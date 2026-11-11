class_name NavalHullLoss
extends RefCounted
## The civilian hull a commerce raid can send down (wiki: ships-and-naval
## § Trade and Transport Interception; DR-20261111-17). Pure rules: price the
## chance, pick the hull and make the draw. NavalRaid owns the raid itself; the
## map layer only reports the hull this module removes.
##
## `shipLossChance = baseShipLoss × (1 − escortFactor) × civilianPenalty`, with
## the published civilian penalty and a clamped band. A warship is never the
## prize: escorts live in `escortFactor`, and the raider risks no hull of its own.

## A successful raid's chance to sink one merchant hull before escorts and the
## civilian penalty: baseShipLoss in the published formula.
const BASE_SHIP_LOSS: float = 0.2
## `civilianPenalty`: merchant hulls are twice as vulnerable as a warship would
## be (wiki: ships-and-naval § Trade and Transport Interception).
const CIVILIAN_PENALTY: float = 2.0
const MIN_SHIP_LOSS: float = 0.05
const MAX_SHIP_LOSS: float = 0.5


## Escort cover: `min(0.5, escortHull / cargoHull × 0.3)`, the wiki's
## `escortFactor`. Shared with the cargo chance so both raid terms agree.
static func escort_factor(home: FleetState) -> float:
	if home == null:
		return 0.0
	var cargo: float = 0.0
	var escort: float = 0.0
	for hull_id: String in home.hulls:
		var type_id: String = home.type_of(hull_id)
		var hull: float = float(ShipStats.entry(type_id).get("hull", 0))
		if ShipStats.is_warship(type_id):
			escort += hull
		else:
			cargo += hull
	if cargo <= 0.0:
		return 0.0
	return minf(0.5, escort / cargo * 0.3)


## Chance a successful raid sends one merchant hull down, before its own draw.
## A home fleet with no merchant hull offers no civilian target.
static func chance(home: FleetState) -> float:
	if at_risk(home).is_empty():
		return 0.0
	return clampf(
		BASE_SHIP_LOSS * (1.0 - escort_factor(home)) * CIVILIAN_PENALTY,
		MIN_SHIP_LOSS,
		MAX_SHIP_LOSS
	)


## The merchant hull a raid would send down: the richest prize first (largest
## cargo hold), the lower instance id breaking the tie. Warships are escorts,
## never prizes.
static func at_risk(home: FleetState) -> Dictionary:
	if home == null:
		return {}
	var pick_id: String = ""
	var pick_type: String = ""
	var pick_cargo: int = -1
	for hull_id: String in home.hulls:
		var type_id: String = home.type_of(hull_id)
		if ShipStats.is_warship(type_id):
			continue
		var cargo: int = int(ShipStats.entry(type_id).get("cargo", 0))
		if pick_id.is_empty() or cargo > pick_cargo:
			pick_id = hull_id
			pick_type = type_id
			pick_cargo = cargo
	if pick_id.is_empty():
		return {}
	return {
		"id": pick_id,
		"type_id": pick_type,
		"name": ShipNames.of(home, pick_id),
	}


## One draw: a roll inside `chance` removes one merchant hull from the victim's
## home fleet and returns her, with the chance and roll that decided it. A
## negative `roll_value` uses the deterministic salt. The rules own the draw so
## the same hull cannot be lost twice.
static func draw(
	home: FleetState,
	raider: int,
	seed_value: int,
	turn: int,
	zone: int,
	roll_value: float,
	tag: int
) -> Dictionary:
	var target: Dictionary = at_risk(home)
	if target.is_empty():
		return {"chance": 0.0, "roll": 1.0, "hull": {}}
	var found: float = chance(home)
	var rolled: float = roll_value
	if rolled < 0.0:
		rolled = NavalInterception.roll(seed_value, turn, zone, raider, 0, tag)
	if rolled >= found:
		return {"chance": found, "roll": rolled, "hull": {}}
	home.remove_hull(String(target["id"]))
	return {"chance": found, "roll": rolled, "hull": target}
