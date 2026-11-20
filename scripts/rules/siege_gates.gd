class_name SiegeGates
extends RefCounted
## A fort's three gates and the breach they open for a siege (wiki:
## siege-mechanics § Gates and Sortie, § Damage Reduction).
##
## A besieger may not pass a gate; it must beat the wall down until one is
## breached. Each gate falls after `ceil(wall HP / 3)` casualties are drawn from
## the wall lane, after which the wall's reduction no longer shelters the
## garrison and the attackers pour through in the share of gates lost.
## The lanes and the blow that batters the gates are [SiegeLanes]' and the
## ground they stand on [SiegeGround]'s. Pure data and maths: no nodes
## (REQ-P3-01, REQ-P3-03).

## A fort has three gates; the wall is stormed through one at a time.
const GATES: int = 3


## Fresh gate state for a siege; empty in a field battle.
static func gates_for(fort: int) -> Dictionary:
	if fort <= 0:
		return {}
	return {
		"max": GATES, "broken": 0, "damage": 0,
		"threshold": breach_threshold(fort),
	}


## Wall casualties needed to open one gate. Three gates share the wall's HP.
static func breach_threshold(fort: int) -> int:
	if fort <= 0:
		return 0
	return ceili(FortRules.wall_hp(fort) / float(GATES))


## Books wall casualties against the gates; returns how many opened this blow.
static func batter(gates: Dictionary, wall_hits: int) -> int:
	if gates.is_empty() or int(gates.get("max", 0)) <= 0 or wall_hits <= 0:
		return 0
	gates["damage"] = int(gates.get("damage", 0)) + wall_hits
	var threshold: int = int(gates.get("threshold", 0))
	var reached: int = 0 if threshold <= 0 else int(gates["damage"]) / threshold
	var before: int = int(gates.get("broken", 0))
	# A gate already down stays down; new wall damage only opens more.
	gates["broken"] = maxi(before, mini(int(gates["max"]), reached))
	return int(gates["broken"]) - before


static func breached(gates: Dictionary) -> bool:
	return int(gates.get("broken", 0)) > 0


## Share of a fort's gates standing open, 0.0 while the wall holds.
static func breach_share(gates: Dictionary) -> float:
	var maximum: int = int(gates.get("max", 0))
	if maximum <= 0:
		return 0.0
	return float(int(gates.get("broken", 0))) / float(maximum)
