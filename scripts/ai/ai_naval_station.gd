class_name AiNavalStation
extends RefCounted
## The naval policy's two station sails: a squadron running for home and a
## warship working the enemy's trade. [AiNavalPlanner] owns the turn's policy;
## this module owns the water each order crosses, so the raid's goal scan and the
## homeward leg read [AiSquadronReads] instead of copying it (REQ-P3-01).
## Pure rules: state in, orders out; the map layer applies them through
## NavalMovement so the AI never invents an outcome (REQ-P2-03, REQ-P3-03).

## A squadron bound for its own harbour: dock beside it, or sail the next leg.
const KIND_HOME: String = "home"
## A warship with no squadron to fight works a hostile coast (DR-20261111-17).
const KIND_RAID: String = "raid"


## One step home for an unengaged squadron: dock when the home harbour borders
## its zone, else the next charted zone on the sea path. A squadron on a station
## (patrol, blockade, beachhead) or carrying an expedition keeps its post, unless
## `release` says the court needs its holds ashore more than its station
## (issue #530).
static func home_order(
	model: MapModel, fleet: FleetState, owner: int, charts: CourtCharts,
	release: bool = false
) -> Dictionary:
	if fleet.is_in_port():
		return {}
	# An expedition's hulls are the invasion planner's, holds and all.
	if fleet.has_beachhead() or not fleet.embarked_civilians.is_empty():
		return {}
	if stationed(fleet) and not release:
		return {}
	var port: int = NavalMovement.home_harbour(model, owner)
	if port < 0:
		return {}
	if NavalMovement.dockable_provinces(model, fleet).has(port):
		return {
			"kind": KIND_HOME,
			"dock": true,
			"province": port,
			"zone": MapModel.NO_ID,
			"threat": 0,
		}
	var goals: Array[int] = NavalMovement.province_sea_zones(model, port)
	var step: int = AiSeaRoute.sail_toward(model, fleet, goals)
	if step < 0 or not AiSquadronReads.charts_water(charts, owner, model.region_id, step):
		return {}
	return {
		"kind": KIND_HOME,
		"dock": false,
		"province": MapModel.NO_ID,
		"zone": step,
		"threat": 0,
	}


## A squadron with orders of its own does not run for home: a station spends its
## turn where it is, and an expedition's hulls belong to the invasion planner.
static func stationed(fleet: FleetState) -> bool:
	if fleet.has_beachhead():
		return true
	if not fleet.embarked_civilians.is_empty():
		return true
	return fleet.mission != FleetState.Mission.NONE and fleet.mission != FleetState.Mission.DEFEND


## A warship with no squadron to fight works the enemy's trade: one legal step
## toward a hostile coast, where the station pass posts a blockade and the raid
## takes cargo and merchant hulls (DR-20261111-17). A home squadron sorties out
## of the seat to do it (DR-20261109-17), but only when the water beside the port
## is clear: a fight it declines is still a threat to its own harbour, so it
## keeps the seat instead. A coast whose seat holds a laden merchant squadron is
## worth the farther trip; a merchant-only squadron stays out of it, and a
## warship already on a hostile coast holds for its station instead of sailing
## away.
static func raid_order(
	model: MapModel,
	fleets: Array,
	fleet: FleetState,
	faction: int,
	hostile: Dictionary,
	charts: CourtCharts
) -> Dictionary:
	if not AiSquadronReads.has_warship(fleet):
		return {}
	if NavalMovement.is_home_fleet(model, fleet) and AiSquadronReads.hostile_beside(
		model, fleets, fleet, hostile
	):
		return {"hold": true}
	var laden: Array[int] = []
	var coasts: Array[int] = []
	trade_goals(model, fleets, faction, hostile, charts, laden, coasts)
	if laden.has(fleet.sea_zone):
		return {"hold": true}
	var step: int = step_for(model, fleet, laden)
	if step < 0:
		step = step_for(model, fleet, coasts)
	if step < 0:
		return {"hold": true} if coasts.has(fleet.sea_zone) else {}
	if not AiSquadronReads.charts_water(charts, faction, model.region_id, step):
		return {}
	return {"kind": KIND_RAID, "zone": step, "threat": 0}


## Charted sea zones beside a hostile coast, split into the coasts whose seat
## holds merchant tonnage (`laden`) and every other hostile shore (`coasts`).
static func trade_goals(
	model: MapModel,
	fleets: Array,
	faction: int,
	hostile: Dictionary,
	charts: CourtCharts,
	laden: Array[int],
	coasts: Array[int]
) -> void:
	for province: ProvinceState in model.provinces:
		if province == null:
			continue
		var owner: int = model.province_owner(province.id)
		if owner == faction or not hostile.has(owner):
			continue
		var rich: bool = home_holds(fleets, owner, province.id)
		for zone: int in NavalMovement.province_sea_zones(model, province.id):
			if not AiSquadronReads.charts_water(charts, faction, model.region_id, zone):
				continue
			var bucket: Array[int] = laden if rich else coasts
			if not bucket.has(zone):
				bucket.append(zone)


## First leg toward the nearest goal, or -1 when already there or unreachable.
static func step_for(model: MapModel, fleet: FleetState, goals: Array[int]) -> int:
	if goals.is_empty() or goals.has(fleet.sea_zone):
		return -1
	return AiSeaRoute.sail_toward(model, fleet, goals)


## True when `owner` keeps a merchant squadron in port at `province`, the laden
## home fleet a raid can actually strip of cargo and hulls.
static func home_holds(fleets: Array, owner: int, province: int) -> bool:
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner or not fleet.is_in_port():
			continue
		if fleet.province == province and TradeCargo.fleet_holds(fleet) > 0:
			return true
	return false
