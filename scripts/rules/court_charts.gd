class_name CourtCharts
extends RefCounted
## Every court's chart of the map (wiki: fog-and-exploration; DR-20261110-21).
##
## The human court's per-region models live in PlaySession.visibility_by_region;
## this holds one VisibilityModel per rival Great Power and region, so a rival
## reads the same pure engine the player's view paints and no court plans
## against a tile it has never charted (REQ-P2-03, REQ-P3-03).
##
## Nothing here reads the difficulty layer: every level explores the same fog,
## and a harder level buys stores and land strength, never sight.

var human_faction: int = MapModel.NO_ID
## Faction -> region -> VisibilityModel, for every rival Great Power this
## session has charted. A rival's grid is built the first time a rule reads it
## (see `_ensure`), so mounting a campaign screen no longer pays for five
## courts' grids that nobody has looked at yet.
var courts: Dictionary = {}
## The session's human table, held by reference so the view and the planners
## share one grid instead of two copies that could drift.
var _human_views: Dictionary = {}
## The world the rivals' initial grids are cut from; null in a fixture that
## never charted a world, which keeps `model_for` answering null as before.
var _world: WorldMap = null


## Remembers the world the rivals chart; safe to call again as regions load. The
## human court is never copied — `model_for` routes it to the session's table.
## The rivals' grids themselves are cut on first read, not here.
func setup(world: WorldMap, human: int, human_views: Dictionary) -> void:
	human_faction = human
	_human_views = human_views
	if world != null:
		_world = world


## A court's fog for one region: the human's own grid, or a rival's model,
## which is cut from the world if this is the first rule to read it.
func model_for(owner: int, region: int) -> VisibilityModel:
	if owner == human_faction:
		var human_view: Variant = _human_views.get(region, null)
		return human_view as VisibilityModel
	_ensure(owner, region)
	var by_region: Dictionary = courts.get(owner, {})
	var view: Variant = by_region.get(region, null)
	return view as VisibilityModel


## Region -> model table for one court, as TechDiscovery and the save expect.
## A rival's full table is cut here, because the caller reads every region.
func regions_of(owner: int) -> Dictionary:
	if owner == human_faction:
		return _human_views
	_ensure_faction(owner)
	var by_region: Dictionary = courts.get(owner, {})
	return by_region


## Builds one rival's grid for one region when it is missing. A restored grid
## (see `apply_dict`) is never replaced, so a load keeps what the court charted.
func _ensure(owner: int, region: int) -> void:
	if _world == null:
		return
	var by_region: Dictionary = courts.get(owner, {})
	if by_region.has(region):
		return
	var model: MapModel = _world.region(region)
	if model == null:
		return
	var view := VisibilityModel.new()
	view.setup(model, owner)
	view.apply_initial()
	by_region[region] = view
	courts[owner] = by_region


## Builds every region for one rival (the save and the research reads want the
## whole table, not one region of it).
func _ensure_faction(owner: int) -> void:
	if _world == null:
		return
	for index in _world.region_count():
		_ensure(owner, index)


## Builds every rival's every grid, so a save always carries the full charts.
func _ensure_all() -> void:
	if _world == null:
		return
	for faction: int in FactionCatalog.great_power_ids():
		if faction == human_faction:
			continue
		_ensure_faction(faction)


## True when at least one tile of the province is charted (fogged or better).
func knows_province(owner: int, region: int, province_id: int) -> bool:
	var view: VisibilityModel = model_for(owner, region)
	return view != null and view.is_province_known(province_id)


## True when at least one water tile of the sea zone is charted. Old World water
## starts fogged for every court, so only the uncharted New World can refuse.
func knows_zone(owner: int, region: int, zone_id: int) -> bool:
	var view: VisibilityModel = model_for(owner, region)
	if view == null:
		return false
	var data: SeaZoneState = view.model.sea_zone_data(zone_id)
	if data == null:
		return false
	for tile: Vector2i in data.tiles:
		if view.level_at(tile.x, tile.y) >= VisibilityModel.Level.FOGGED:
			return true
	return false


## Sea zones with any charted water, in id order.
func known_zones(owner: int, region: int) -> Array[int]:
	var zones: Array[int] = []
	var view: VisibilityModel = model_for(owner, region)
	if view == null:
		return zones
	for zone: SeaZoneState in view.model.sea_zones:
		if knows_zone(owner, region, zone.id):
			zones.append(zone.id)
	zones.sort()
	return zones


## The subset of `tiles` this court has charted, in the order given. A court
## with no chart (a fixture) keeps the list as it is.
func charted_tiles(owner: int, region: int, tiles: Array[Vector2i]) -> Array[Vector2i]:
	var view: VisibilityModel = model_for(owner, region)
	if view == null:
		return tiles
	var kept: Array[Vector2i] = []
	for tile: Vector2i in tiles:
		if view.level_at(tile.x, tile.y) >= VisibilityModel.Level.FOGGED:
			kept.append(tile)
	return kept


func reveal_sea_zone(owner: int, region: int, zone_id: int, extra_land_rings: int = 0) -> Array:
	var view: VisibilityModel = model_for(owner, region)
	if view == null:
		return []
	return view.reveal_sea_zone(zone_id, extra_land_rings)


func reveal_landing(owner: int, region: int, tile: Vector2i) -> Array:
	var view: VisibilityModel = model_for(owner, region)
	if view == null:
		return []
	return view.reveal_landing(tile)


func reveal_province(owner: int, region: int, province_id: int) -> Array:
	var view: VisibilityModel = model_for(owner, region)
	if view == null:
		return []
	return view.reveal_province(province_id)


## Plain data for a local save: the rivals' grids (the human's own table is
## captured beside the world half by SaveWorld).
func to_dict() -> Dictionary:
	_ensure_all()
	var by_faction: Dictionary = {}
	for raw: Variant in courts.keys():
		var faction: int = int(raw)
		var by_region: Dictionary = courts[faction]
		var entry: Dictionary = {}
		for region: Variant in by_region.keys():
			var view: VisibilityModel = by_region[region]
			if view != null:
				entry[int(region)] = view.to_dict()
		by_faction[faction] = entry
	return {"courts": by_faction}


## Restores the rivals' grids onto an already-generated world. A payload without
## a `courts` entry (a save from before rival fog) is left as the baseline the
## setup pass built, rather than cleared.
func apply_dict(world: WorldMap, data: Variant) -> bool:
	if world == null or typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has("courts"):
		return false
	var by_faction: Variant = data["courts"]
	if typeof(by_faction) != TYPE_DICTIONARY:
		return false
	var stored_courts: Dictionary = by_faction
	courts.clear()
	for raw: Variant in stored_courts.keys():
		var faction: int = int(raw)
		var by_region: Dictionary = stored_courts[raw]
		for region_key: Variant in by_region.keys():
			var region: int = int(region_key)
			var model: MapModel = world.region(region)
			var entry: Variant = by_region[region_key]
			if model == null or typeof(entry) != TYPE_DICTIONARY:
				continue
			var view := VisibilityModel.new()
			view.setup(model, faction)
			if not view.apply_dict(entry):
				continue
			var stored: Dictionary = courts.get(faction, {})
			stored[region] = view
			courts[faction] = stored
	return not courts.is_empty()
