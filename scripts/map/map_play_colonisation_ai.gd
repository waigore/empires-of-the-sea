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
	# The workshop's appetite, read once per court per turn: the ground each
	# colonist lands on is the ground its own recipes feed (DR-20261119-05).
	var appetites: Dictionary = {}
	var visible_touched: bool = false
	for region: int in play.ship_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var fleets: Array = MapPlayCourt.region_fleets(play, region)
		var civilians: Array = []
		civilians.assign(play.civilian_layer.regions.value(region, []))
		# The full-AI observer has no human court: the former player slot runs
		# every planner like any rival (wiki: game-setup § Human/AI slot
		# assignment; docs/ai-observer.md).
		for faction: int in MapPlayCourt.planning_factions(play):
			var kind: String = AiControl.court_kind(play, faction)
			if kind == AiControl.KIND_RANDOM:
				continue
			var config: Variant = AiBind.config(kind, faction, play.map_seed)
			# A court on a war footing keeps its hulls for the fleet: the posture
			# closes the voyage before the planner picks a step (DR-20261113-15) —
			# unless the court is on **earn**, whose gold is overseas
			# (DR-20261113-19).
			var posture: String = AiBind.phase_for(kind, config, play.diplomacy)
			var earning: bool = MapPlaySeaStep.earning(play, faction, kind, config)
			var target: int = WorldMap.NEW_WORLD if region == WorldMap.OLD_WORLD else WorldMap.OLD_WORLD
			var order: Dictionary = AiBindCampaign.colonisation_plan(
				kind, config, play.world, region, model, fleets, civilians,
				_abroad(play, target, faction), play.court_charts,
				_voyage_posture(play, faction, posture), earning,
				_appetite(play, faction, kind, appetites)
			)
			if order.is_empty():
				continue
			var crossing: FleetState = null
			var leaving: Array[int] = []
			if String(order.get("kind", "")) == "cross":
				crossing = MapPlayCourt.fleet_in(play, region, int(order.get("fleet", -1)))
				if crossing != null:
					for unit_id: int in crossing.embarked_civilians:
						leaving.append(unit_id)
			var applied: Dictionary = _apply(play, region, model, order)
			if not bool(applied.get("ok", false)):
				continue
			trace.append(applied)
			# A voyage that moors at the court's own seat folds into the home
			# fleet, in the same roster this pass writes back (wiki:
			# ships-and-naval § Home Fleet — "any naval move that docks at the
			# capital resolves by merging").
			if String(order.get("kind", "")) == "dock":
				var moored: FleetState = MapPlayCourt.fleet_in(
					play, region, int(order.get("fleet", -1))
				)
				if moored != null:
					MapPlayHomeMerge.fold(play, model, fleets, moored)
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
		MapPlaySeaStep.merge_stored(stored_fleets, fleets)
		play.ship_layer.regions.set_region(region, fleets)
		var stored_civilians: Array = []
		stored_civilians.assign(play.civilian_layer.regions.value(region, []))
		MapPlaySeaStep.merge_stored(stored_civilians, civilians)
		play.civilian_layer.regions.set_region(region, civilians)
	if visible_touched:
		MapPlayCourt.refresh_hulls(play)
	return trace


## The footing the voyage reads: the court's own ledger decides whether the
## expedition was funded, and a funded parent opens the voyage even at war — the
## peace-window child is what bought it (issue #491 T4). A court with no ledger
## yet (the opening turn, an old save, a fixture) keeps the published footing, so
## the war gate still holds until the first ledger is written.
static func _voyage_posture(play: PlaySession, faction: int, posture: String) -> String:
	if AiPhasePlanner.opens(posture, AiPhasePlanner.SLOT_VOYAGE):
		return posture
	var claim: Dictionary = play.ai.objectives_for(faction) if play.ai != null else {}
	if claim.is_empty():
		return posture
	var funded: Array = claim.get("funded_ids", [])
	return AiPhasePlanner.PHASE_PEACE if funded.has("colonise.new_world") else posture


static func _apply(
	play: PlaySession, region: int, model: MapModel, order: Dictionary
) -> Dictionary:
	var kind: String = String(order.get("kind", ""))
	var fleet: FleetState = MapPlayCourt.fleet_in(
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
			entry["province_name"] = model.province_name(fleet.province)
		"sail":
			var zone: int = int(order.get("zone", -1))
			if not MapPlaySeaStep.sail(play, model, region, fleet, zone):
				return {}
			entry["zone"] = zone
		"dock":
			var province: int = int(order.get("province", -1))
			if not MapPlaySeaStep.dock(model, fleet, province):
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
			entry["province_name"] = model.province_name(
				model.province_at(tile.x, tile.y)
			)
		_:
			return {}
	entry["ok"] = true
	return entry


## Crosses a passage and carries the fleet and its passengers into the other
## region's rosters. The view never follows a rival's squadron.
static func _cross(play: PlaySession, region: int, fleet: FleetState) -> Dictionary:
	var result: Dictionary = MapPlaySeaStep.cross(play, region, fleet)
	if not bool(result.get("ok", false)):
		return result
	var to_region: int = int(result["to_region"])
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


static func _erase_unit(units: Array, unit_id: int) -> void:
	var index: int = -1
	for cursor in units.size():
		var unit: CivilianState = units[cursor]
		if unit != null and unit.id == unit_id:
			index = cursor
			break
	if index >= 0:
		units.remove_at(index)


## The raws this court's workshop can turn and does not hold in number, read
## once per court per turn and remembered for the region loop: a landing is the
## one ground a court takes overseas, so it names the ground its own recipes
## feed (DR-20261119-05). A frozen baseline keeps its published walk, so it reads
## none — its planner is origin/main's and takes the compass order.
static func _appetite(
	play: PlaySession, faction: int, kind: String, cache: Dictionary
) -> Dictionary:
	if cache.has(faction):
		return cache[faction] as Dictionary
	var appetite: Dictionary = {}
	if kind != AiControl.KIND_BASELINE and play.ai != null:
		var economy: PlayerEconomy = play.ai.economy_for(faction)
		var config: Variant = AiBind.config(kind, faction, play.map_seed)
		if economy != null and config is AiConfig:
			appetite = AiEconomyPlanner.ground_appetite(
				config as AiConfig, economy, TownIndustry.best_level(play.world, faction)
			)
	cache[faction] = appetite
	return appetite
