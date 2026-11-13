class_name MapPlayColonisationAi
extends RefCounted
## Applies rival colonisation voyages (docs/ai.md). AiColonisationPlanner picks
## one legal step; this adapter moves the fleet and civilian rosters and asks the
## shared rules to execute it. It runs before the naval planner so an expedition
## squadron is not steered into a battle mid-crossing (REQ-P2-03, REQ-P3-03).


static func run(play: PlaySession) -> Array[Dictionary]:
	var trace: Array[Dictionary] = []
	if (
		play == null or play.world == null or play.ship_layer == null
		or play.civilian_layer == null
	):
		return trace
	var visible_touched: bool = false
	for region: int in play.ship_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var fleets: Array = []
		fleets.assign(play.ship_layer.regions.value(region, []))
		var civilians: Array = []
		civilians.assign(play.civilian_layer.regions.value(region, []))
		for faction: int in FactionCatalog.great_power_ids():
			# The full-AI observer has no human court: the former player slot runs
			# every planner like any rival (wiki: game-setup § Human/AI slot
			# assignment; docs/ai-observer.md).
			if faction == play.player_faction and not play.observer_mode:
				continue
			if not AiControl.plans(play, faction):
				continue
			var config: AiConfig = AiConfig.build(faction, play.map_seed)
			# A court on a war footing keeps its hulls for the fleet: the posture
			# closes the voyage before the planner picks a step (DR-20261113-15) —
			# unless the court is on **earn**, whose gold is overseas
			# (DR-20261113-19).
			var posture: String = AiPhasePlanner.phase_for(config, play.diplomacy)
			var earning: bool = AiIncome.wants_income(
				config, play.ledger_for(faction), _at_war(play, faction),
				_regiments(play, faction)
			)
			var target: int = WorldMap.NEW_WORLD if region == WorldMap.OLD_WORLD else WorldMap.OLD_WORLD
			var order: Dictionary = AiColonisationPlanner.plan(
				config, play.world, region, model, fleets, civilians,
				_abroad(play, target, faction), play.court_charts, posture, earning
			)
			if order.is_empty():
				continue
			var crossing: FleetState = null
			var leaving: Array[int] = []
			if String(order.get("kind", "")) == "cross":
				crossing = _fleet_by_id_any(play, region, int(order.get("fleet", -1)))
				if crossing != null:
					for unit_id: int in crossing.embarked_civilians:
						leaving.append(unit_id)
			var applied: Dictionary = _apply(play, region, model, order)
			if not bool(applied.get("ok", false)):
				continue
			trace.append(applied)
			# A crossing already moved the fleet and its passengers; the local
			# snapshot must not write them back into this region.
			if crossing != null:
				fleets.erase(crossing)
				for unit_id: int in leaving:
					_erase_unit(civilians, unit_id)
			if play.model != null and play.model.region_id == region:
				visible_touched = true
		# Keep any fleet a passage already carried into this roster (a crossing
		# from a later-iterated region lands here before this pass writes back).
		var stored_fleets: Array = []
		stored_fleets.assign(play.ship_layer.regions.value(region, []))
		for fleet: FleetState in stored_fleets:
			if fleet != null and not fleets.has(fleet):
				fleets.append(fleet)
		play.ship_layer.regions.set_region(region, fleets)
		var stored_civilians: Array = []
		stored_civilians.assign(play.civilian_layer.regions.value(region, []))
		for unit: CivilianState in stored_civilians:
			if unit != null and not civilians.has(unit):
				civilians.append(unit)
		play.civilian_layer.regions.set_region(region, civilians)
	if visible_touched:
		_refresh_visible(play)
	return trace


static func _apply(
	play: PlaySession, region: int, model: MapModel, order: Dictionary
) -> Dictionary:
	var kind: String = String(order.get("kind", ""))
	var fleet: FleetState = _fleet_by_id_any(
		play, region, int(order.get("fleet", -1))
	)
	if fleet == null:
		return {}
	var entry: Dictionary = {
		"faction": fleet.owner,
		"kind": kind,
		"fleet": fleet.id,
		"region": region,
	}
	match kind:
		"embark":
			var unit: CivilianState = CivilianVoyageMap.by_id(
				play.civilian_layer, int(order.get("unit", -1))
			)
			var boarded: Dictionary = CivilianVoyage.embark(model, unit, fleet)
			if not bool(boarded.get("ok", false)):
				return {}
			CivilianVoyageMap.hide(play.civilian_layer, unit)
			entry["unit"] = unit.id
		"sail":
			var zone: int = int(order.get("zone", -1))
			var sailed: Dictionary = NavalMovement.apply_move(
				model, fleet, FleetState.Location.AT_SEA, zone
			)
			if not bool(sailed.get("ok", false)):
				sailed = FleetSortie.apply(model, fleet, zone)
			if not bool(sailed.get("ok", false)):
				return {}
			MapPlayCourtFog.note_fleet_entry(play, region, fleet, zone)
			entry["zone"] = zone
		"dock":
			var province: int = int(order.get("province", -1))
			var docked: Dictionary = NavalMovement.apply_move(
				model, fleet, FleetState.Location.IN_PORT, province
			)
			if not bool(docked.get("ok", false)):
				return {}
			entry["province"] = province
		"cross":
			var crossed: Dictionary = _cross(play, region, fleet)
			if not bool(crossed.get("ok", false)):
				return {}
			MapPlayCourtFog.note_fleet_entry(
				play, int(crossed.get("to_region", -1)), fleet,
				int(crossed.get("to_zone", -1))
			)
			entry["to_region"] = int(crossed.get("to_region", -1))
			entry["to_zone"] = int(crossed.get("to_zone", -1))
		"land":
			var unit: CivilianState = CivilianVoyageMap.by_id(
				play.civilian_layer, int(order.get("unit", -1))
			)
			var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
			var landed: Dictionary = CivilianVoyage.disembark(model, unit, fleet, tile)
			if not bool(landed.get("ok", false)):
				return {}
			MapPlayCourtFog.note_landing(play, region, fleet.owner, unit.tile)
			_ensure_works(play, region)
			CivilianVoyageMap.show_ashore(play.civilian_layer, unit)
			entry["unit"] = unit.id
			entry["tile"] = tile
		_:
			return {}
	entry["ok"] = true
	return entry


## Crosses a passage and carries the fleet and its passengers into the other
## region's rosters. The view never follows a rival's squadron.
static func _cross(play: PlaySession, region: int, fleet: FleetState) -> Dictionary:
	var result: Dictionary = WarpTravel.apply_crossing(play.world, region, fleet)
	if not bool(result.get("ok", false)):
		return result
	var to_region: int = int(result["to_region"])
	var source: Array = []
	source.assign(play.ship_layer.regions.value(region, []))
	source.erase(fleet)
	play.ship_layer.regions.set_region(region, source)
	fleet.id = FleetRosters.next_id_all(play.ship_layer.regions)
	var destination: Array = []
	destination.assign(play.ship_layer.regions.value(to_region, []))
	destination.append(fleet)
	play.ship_layer.regions.set_region(to_region, destination)
	for unit_id: int in fleet.embarked_civilians.duplicate():
		CivilianVoyageMap.move_to_region(play.civilian_layer, unit_id, to_region)
	_ensure_works(play, to_region)
	return result


static func _ensure_works(play: PlaySession, region: int) -> void:
	if play.civilian_layer.works_regions.value(region, null) == null:
		play.civilian_layer.works_regions.set_region(region, LandWorks.new())


## This crown's civilians already in `region`, counted by type, so a court sends
## one Explorer to chart, then a Merchant to claim, then a Builder to work.
static func _abroad(play: PlaySession, region: int, owner: int) -> Dictionary:
	var counts: Dictionary = {}
	if region < 0 or play.civilian_layer == null:
		return counts
	var roster: Array = []
	if play.model != null and play.model.region_id == region:
		roster.assign(play.civilian_layer.units)
	else:
		roster.assign(play.civilian_layer.regions.value(region, []))
	for raw: Variant in roster:
		var unit: CivilianState = raw
		if unit != null and unit.owner == owner:
			counts[unit.type_id] = int(counts.get(unit.type_id, 0)) + 1
	return counts


## True when any court holds a declared war on this one: the reserve the court
## must hold is read against it (DR-20261113-19).
static func _at_war(play: PlaySession, faction: int) -> bool:
	if play.diplomacy == null:
		return false
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record.at_war:
			return true
	return false


## Land regiments this court holds in every region, as the muster target reads
## them. A session with no army layer reads none.
static func _regiments(play: PlaySession, faction: int) -> int:
	if play.army_layer == null:
		return 0
	return play.army_layer.regiment_count_all(faction)


static func _fleet_by_id_any(
	play: PlaySession, region: int, fleet_id: int
) -> FleetState:
	var roster: Array = []
	roster.assign(play.ship_layer.regions.value(region, []))
	for raw: Variant in roster:
		var fleet: FleetState = raw
		if fleet != null and fleet.id == fleet_id:
			return fleet
	return null


static func _erase_unit(units: Array, unit_id: int) -> void:
	var index: int = -1
	for cursor in units.size():
		var unit: CivilianState = units[cursor]
		if unit != null and unit.id == unit_id:
			index = cursor
			break
	if index >= 0:
		units.remove_at(index)


## Rebuilds the visible markers after a rival moved a squadron or a colonist.
static func _refresh_visible(play: PlaySession) -> void:
	if play.ship_layer.model == null:
		return
	var selected: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	play.ship_layer.spawn(
		play.ship_layer.model, 0, 0, -1, false, play.player_faction
	)
	if selected != null:
		play.ship_layer.select(play.ship_layer.ship_for(selected))
