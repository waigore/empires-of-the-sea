class_name MapPlayCourt
extends RefCounted
## Which courts run a planner this session, where the crown's seat stands, and
## whether a court is at war — so every rival pass asks the same question once
## instead of carrying its own copy (REQ-P2-03, REQ-P3-01, REQ-P3-02).
##
## The answers live where their owners do: the seat and the war footing in
## [MapPlayCourtHoldings], a named army or squadron in [MapPlayCourtRoster].
## These names keep the one call site that predates the split working without
## a second copy of any read. Pure state reads: nothing here issues an order or
## changes a roster.

## `-1` reads as "any owner" for the roster lookups.
const NO_OWNER: int = -1


## The chart the crown's seat stands on: `{region, province, model}`. See
## [method MapPlayCourtHoldings.crown_seat].
static func crown_seat(play: PlaySession) -> Dictionary:
	return MapPlayCourtHoldings.crown_seat(play)


## The Great Powers that run a planner this session, in catalog order. See
## [method MapPlayCourtHoldings.planning_factions].
static func planning_factions(play: PlaySession) -> Array[int]:
	return MapPlayCourtHoldings.planning_factions(play)


## True while the crown still holds a province in either world. See
## [method MapPlayCourtHoldings.holds_land].
static func holds_land(play: PlaySession, faction: int) -> bool:
	return MapPlayCourtHoldings.holds_land(play, faction)


## True when any court holds a declared war on this one. See
## [method MapPlayCourtHoldings.at_war].
static func at_war(play: PlaySession, faction: int) -> bool:
	return MapPlayCourtHoldings.at_war(play, faction)


## The courts at war with this one, in relation order. See
## [method MapPlayCourtHoldings.at_war_with].
static func at_war_with(play: PlaySession, faction: int) -> Array[int]:
	return MapPlayCourtHoldings.at_war_with(play, faction)


## Land regiments this court holds in every region. See
## [method MapPlayCourtHoldings.regiments].
static func regiments(play: PlaySession, faction: int) -> int:
	return MapPlayCourtHoldings.regiments(play, faction)


## Hulls of every kind this court holds. See
## [method MapPlayCourtHoldings.ships].
static func ships(play: PlaySession, faction: int) -> int:
	return MapPlayCourtHoldings.ships(play, faction)


## The published order of battle every map read shares. See
## [method MapPlayCourtHoldings.public_orders].
static func public_orders(play: PlaySession) -> Dictionary:
	return MapPlayCourtHoldings.public_orders(play)


## Land strength per faction over the whole roster. See
## [method MapPlayCourtHoldings.public_strength].
static func public_strength(play: PlaySession) -> Dictionary:
	return MapPlayCourtHoldings.public_strength(play)


## Hull count of every Great Power. See
## [method MapPlayCourtHoldings.public_ships].
static func public_ships(play: PlaySession) -> Dictionary:
	return MapPlayCourtHoldings.public_ships(play)


## Hulls of a court that can fight. See
## [method MapPlayCourtHoldings.warships].
static func warships(play: PlaySession, owner: int) -> int:
	return MapPlayCourtHoldings.warships(play, owner)


## Hulls of every court at war with this one. See
## [method MapPlayCourtHoldings.hostile_ships].
static func hostile_ships(play: PlaySession, faction: int) -> int:
	return MapPlayCourtHoldings.hostile_ships(play, faction)


## Fighting hulls of every court at war with this one. See
## [method MapPlayCourtHoldings.hostile_warships].
static func hostile_warships(play: PlaySession, faction: int) -> int:
	return MapPlayCourtHoldings.hostile_warships(play, faction)


## The purse this court must hold before it may lay a hull. See
## [method MapPlayCourtHoldings.navy_chest].
static func navy_chest(play: PlaySession, faction: int) -> int:
	return MapPlayCourtHoldings.navy_chest(play, faction)


## Hull types this court flies or has flown. See
## [method MapPlayCourtHoldings.hull_types].
static func hull_types(play: PlaySession, faction: int) -> Array[String]:
	return MapPlayCourtHoldings.hull_types(play, faction)


## Squadrons stored in one region. See
## [method MapPlayCourtRoster.region_fleets].
static func region_fleets(play: PlaySession, region: int) -> Array[FleetState]:
	return MapPlayCourtRoster.region_fleets(play, region)


## Armies stored in one region. See
## [method MapPlayCourtRoster.region_armies].
static func region_armies(play: PlaySession, region: int) -> Array[ArmyState]:
	return MapPlayCourtRoster.region_armies(play, region)


## Armies in one region as the view holds them. See
## [method MapPlayCourtRoster.visible_armies].
static func visible_armies(play: PlaySession, region: int) -> Array[ArmyState]:
	return MapPlayCourtRoster.visible_armies(play, region)


## The squadron with this id in a roster. See
## [method MapPlayCourtRoster.fleet_by_id].
static func fleet_by_id(roster: Array, fleet_id: int, owner: int = NO_OWNER) -> FleetState:
	return MapPlayCourtRoster.fleet_by_id(roster, fleet_id, owner)


## The army with this id in a roster. See
## [method MapPlayCourtRoster.army_by_id].
static func army_by_id(armies: Array, army_id: int, owner: int = NO_OWNER) -> ArmyState:
	return MapPlayCourtRoster.army_by_id(armies, army_id, owner)


## The one row every rival land order records. See
## [method MapPlayCourtRoster.army_trace].
static func army_trace(
	model: MapModel, faction: int, kind: String, army: int, province: int
) -> Dictionary:
	return MapPlayCourtRoster.army_trace(model, faction, kind, army, province)


## The squadron with this id stored in `region`. See
## [method MapPlayCourtRoster.fleet_in].
static func fleet_in(
	play: PlaySession, region: int, fleet_id: int, owner: int = NO_OWNER
) -> FleetState:
	return MapPlayCourtRoster.fleet_in(play, region, fleet_id, owner)


## Rebuilds the on-screen hull markers after a rival moved a squadron. See
## [method MapPlayCourtRoster.refresh_hulls].
static func refresh_hulls(play: PlaySession) -> void:
	MapPlayCourtRoster.refresh_hulls(play)
