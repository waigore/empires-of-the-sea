class_name MapPlayInvasionAi
extends RefCounted
## Applies rival overseas invasions (docs/ai.md). AiInvasionPlanner picks one
## legal step; this adapter moves the army and squadron rosters between regions
## and asks the shared rules to execute it, so the AI never invents an outcome
## (REQ-P2-03, REQ-P3-03). It runs before the land pass: the expedition's army is
## aboard before the field armies march.

const KIND_SPLIT: String = AiInvasionPlanner.KIND_SPLIT


static func run(play: PlaySession) -> Array[Dictionary]:
	var trace: Array[Dictionary] = []
	if (
		play == null or play.world == null or play.ship_layer == null
		or play.army_layer == null or play.diplomacy == null
	):
		return trace
	var touched: bool = false
	for region: int in play.ship_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var fleets: Array = MapPlayCourt.region_fleets(play, region)
		var armies: Array[ArmyState] = MapPlayCourt.visible_armies(play, region)
		for faction: int in MapPlayCourt.planning_factions(play):
			var kind: String = AiControl.court_kind(play, faction)
			if kind == AiControl.KIND_RANDOM:
				continue
			var config: Variant = AiBind.config(kind, faction, play.map_seed)
			# A court on **earn** sails for the far coast even while a war sits on
			# its border: the gold that ends its impasse is overseas
			# (DR-20261113-19). Defence still comes first on its own soil, which
			# the planner guards.
			var earning: bool = AiBind.wants_income(
				kind, config, play.ledger_for(faction), MapPlayCourt.at_war(play, faction),
				MapPlayCourt.regiments(play, faction)
			)
			touched = _split(
				play, model, fleets, armies, faction, config, kind, trace, earning
			) or touched
			var order: Dictionary = AiBind.invasion_plan(
				kind, config, play.diplomacy, play.world, region, model, fleets, armies,
				play.turn, play.court_charts, earning
			)
			if order.is_empty():
				continue
			var applied: Dictionary = _apply(play, model, region, fleets, armies, order)
			if applied.is_empty():
				continue
			trace.append(applied)
			touched = true
		_store(play, region, fleets, armies)
	if touched:
		_refresh_visible(play)
	return trace


## Detaches the crossing army through ArmyRoster.split, keeping the Home Army.
static func _split(
	play: PlaySession,
	model: MapModel,
	fleets: Array,
	armies: Array[ArmyState],
	faction: int,
	config: Variant,
	kind: String,
	trace: Array[Dictionary],
	wants_income: bool = false
) -> bool:
	var split_any: bool = false
	for action: Dictionary in AiBind.invasion_split(
		kind, config, play.diplomacy, play.world, model, fleets, armies, play.court_charts,
		wants_income
	):
		var home: ArmyState = MapPlayCourt.army_by_id(armies, int(action.get("army_id", -1)))
		if home == null:
			continue
		var ids: Array[String] = []
		ids.assign(action.get("regiments", []))
		var split: Dictionary = ArmyRoster.split(
			armies, home, ids, play.army_layer.next_army
		)
		if not bool(split.get("ok", false)):
			continue
		play.army_layer.next_army += 1
		split_any = true
		var field: ArmyState = split["army"] as ArmyState
		trace.append({
			"faction": faction,
			"kind": KIND_SPLIT,
			"army": field.id,
			"province": field.province,
			"province_name": model.province_name(field.province),
			"region": model.region_id,
		})
	return split_any


static func _apply(
	play: PlaySession,
	model: MapModel,
	region: int,
	fleets: Array,
	armies: Array,
	order: Dictionary
) -> Dictionary:
	var kind: String = String(order.get("kind", ""))
	var fleet: FleetState = MapPlayCourt.fleet_by_id(fleets, int(order.get("fleet", -1)))
	if fleet == null:
		return {}
	var entry: Dictionary = {
		"faction": fleet.owner, "kind": kind, "fleet": fleet.id, "region": region,
	}
	match kind:
		AiInvasionPlanner.KIND_EMBARK:
			var army: ArmyState = MapPlayCourt.army_by_id(armies, int(order.get("army", -1)))
			if not bool(NavalTransport.embark(model, army, fleet).get("ok", false)):
				return {}
			entry["army"] = army.id
		AiInvasionPlanner.KIND_DOCK:
			var dock: int = int(order.get("province", -1))
			var docked: Dictionary = NavalMovement.apply_move(
				model, fleet, FleetState.Location.IN_PORT, dock
			)
			if not bool(docked.get("ok", false)):
				return {}
			entry["province"] = dock
			entry["province_name"] = model.province_name(dock)
		AiInvasionPlanner.KIND_SAIL:
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
			entry["zone_name"] = model.sea_zone_name(zone)
		AiInvasionPlanner.KIND_CROSS:
			var crossed: Dictionary = _cross(play, region, fleets, armies, fleet)
			if not bool(crossed.get("ok", false)):
				return {}
			MapPlayCourtFog.note_fleet_entry(
				play, int(crossed.get("to_region", -1)), fleet,
				int(crossed.get("to_zone", -1))
			)
			entry["to_region"] = int(crossed.get("to_region", -1))
			entry["zone"] = int(crossed.get("to_zone", -1))
		AiInvasionPlanner.KIND_BEACHHEAD:
			var coast: int = int(order.get("province", -1))
			var marked: Dictionary = NavalTransport.establish_beachhead(
				model, fleet, coast, play.turn, _hostile(play)
			)
			if not bool(marked.get("ok", false)):
				return {}
			entry["province"] = coast
			entry["province_name"] = model.province_name(coast)
		AiInvasionPlanner.KIND_LAND:
			var landed: Dictionary = _land(play, model, armies, fleet, order)
			if landed.is_empty():
				return {}
			entry.merge(landed, true)
		_:
			return {}
	entry["ok"] = true
	return entry


## Lands the carried army; the rules own the beachhead gate.
static func _land(
	play: PlaySession,
	model: MapModel,
	armies: Array,
	fleet: FleetState,
	order: Dictionary
) -> Dictionary:
	var army: ArmyState = _carried_army(armies, fleet)
	var province: int = int(order.get("province", -1))
	var result: Dictionary = NavalTransport.disembark(
		model, army, fleet, province, play.turn, _hostile(play)
	)
	if not bool(result.get("ok", false)):
		return {}
	_report_landing(play, model, fleet.owner, province)
	return {
		"army": army.id,
		"province": province,
		"province_name": model.province_name(province),
	}


## Crosses a Passage: the squadron and the army it carries move into the other
## region's stored rosters. The source copy must lose them so the write-back
## does not duplicate a seat.
static func _cross(
	play: PlaySession, region: int, fleets: Array, armies: Array, fleet: FleetState
) -> Dictionary:
	var result: Dictionary = WarpTravel.apply_crossing(play.world, region, fleet)
	if not bool(result.get("ok", false)):
		return result
	var to_region: int = int(result["to_region"])
	fleets.erase(fleet)
	var source: Array = MapPlayCourt.region_fleets(play, region)
	source.erase(fleet)
	play.ship_layer.regions.set_region(region, source)
	var carried: Array[ArmyState] = []
	for raw: Variant in armies.duplicate():
		var army: ArmyState = raw
		if army != null and army.embarked_fleet == fleet.id:
			carried.append(army)
	# The seat is renumbered in the new region, so the troops follow it after.
	fleet.id = FleetRosters.next_id_all(play.ship_layer.regions)
	var destination: Array = MapPlayCourt.region_fleets(play, to_region)
	destination.append(fleet)
	play.ship_layer.regions.set_region(to_region, destination)
	for army: ArmyState in carried:
		ArmyTransport.move_to_region(play.army_layer, army.id, to_region)
		army.embarked_fleet = fleet.id
		armies.erase(army)
	return result


## Rivals' landings are never silent on the human's own coast (REQ-P5-05).
static func _report_landing(
	play: PlaySession, model: MapModel, owner: int, province: int
) -> void:
	if play.hud == null or model.region_id != play.region_index:
		return
	if model.province_owner(province) != play.player_faction:
		return
	play.hud.toast(
		"%s's army storms ashore at %s"
		% [FactionCatalog.name_of(owner), model.province_name(province)]
	)


## Re-reads the on-screen markers after a rival moved troops or hulls; the
## human's selections survive the rebuild when they are still in the region.
static func _refresh_visible(play: PlaySession) -> void:
	if play.ship_layer.model != null:
		MapPlayCourt.refresh_hulls(play)
	if play.army_layer.model != null:
		var selected: ArmyState = play.army_layer.selected_army
		play.army_layer.spawn(play.army_layer.model)
		if selected != null and play.army_layer.armies.has(selected):
			play.army_layer.select(selected)
	if play.hud != null:
		play.hud.set_fleets(MapPlayCourt.ships(play, play.player_faction))


static func _store(play: PlaySession, region: int, fleets: Array, armies: Array) -> void:
	_merge_stored(MapPlayCourt.region_fleets(play, region), fleets)
	_merge_stored(MapPlayCourt.visible_armies(play, region), armies)
	play.ship_layer.regions.set_region(region, fleets)
	play.army_layer.regions.set_region(region, armies)


## Keeps anything a crossing from a later-iterated region already landed here.
static func _merge_stored(stored: Array, local: Array) -> void:
	for entity: Variant in stored:
		if entity != null and not local.has(entity):
			local.append(entity)


## The invadable test the planner weighs, in the form it expects.
static func _hostile(play: PlaySession) -> Callable:
	return func(a: int, b: int) -> bool:
		return DiplomacyRules.invadable(play.diplomacy, a, b)


static func _carried_army(armies: Array, fleet: FleetState) -> ArmyState:
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army != null and army.owner == fleet.owner and army.embarked_fleet == fleet.id:
			return army
	return null
