class_name VisibilityModel
extends RefCounted
## Per-player tile visibility (wiki: fog-and-exploration).
## Pure rules state: no nodes, no rendering. One instance per Great Power, so the
## view, AI and tests all read the same engine (REQ-P3-03).

enum Level { UNKNOWN, FOGGED, FULLY_VISIBLE }

const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]

## How many coast tables to keep. The links are a pure function of the tile grid
## and every court charting one region (and every screen a suite mounts on the
## shared world) asks for the same table: a small bound keeps that free while an
## edited grid still builds its own.
const CACHE_LIMIT: int = 8
static var _coast_cache: Dictionary = {}
## Cache keys oldest-first, so a full shelf drops one grid rather than all.
static var _coast_order: Array[String] = []

var model: MapModel = null
var player_id: int = 0
var levels: PackedByteArray = PackedByteArray()
## Province -> sea zones sharing a P–S edge (inferred from the tile grid).
var province_sea_zones: Dictionary = {}
## Sea zone -> provinces sharing a P–S edge.
var sea_zone_provinces: Dictionary = {}
## Bumped whenever a tile changes level; baked views (the minimap) watch it.
var revision: int = 0


## Allocates the region baseline: the Old World starts fogged, the New World
## unknown, and no reveal applied yet (wiki: fog-and-exploration § Initial
## Visibility; Configurable Values).
func setup(p_model: MapModel, p_player_id: int) -> void:
	model = p_model
	player_id = p_player_id
	var count: int = model.width * model.height
	levels.resize(count)
	var initial: int = (
		Level.FOGGED if model.region_id == FactionCatalog.OLD_WORLD else Level.UNKNOWN
	)
	levels.fill(initial)
	_coast_links()


func level_at(x: int, y: int) -> int:
	if model == null or not model.in_bounds(x, y):
		return Level.UNKNOWN
	return levels[model.index_of(x, y)]


func level_at_index(index: int) -> int:
	if index < 0 or index >= levels.size():
		return Level.UNKNOWN
	return levels[index]


## Knowledge only grows through explicit reveal rules.
func raise_to(index: int, level: int) -> bool:
	if index < 0 or index >= levels.size():
		return false
	if levels[index] >= level:
		return false
	levels[index] = level
	revision += 1
	return true


## Only fog decay lowers knowledge, and it never reaches below `level`.
func lower_to(index: int, level: int) -> bool:
	if index < 0 or index >= levels.size():
		return false
	if levels[index] <= level:
		return false
	levels[index] = level
	revision += 1
	return true


## Game setup pass (wiki: Initial Visibility + Coastal sea zone visibility).
func apply_initial() -> Array:
	var changed: Array = []
	changed.append_array(_reveal_own_provinces())
	changed.append_array(_apply_coastal_sea_zones())
	return changed


## Ship reveal (wiki: ships-and-naval § Ship Reveal Mechanic): entering a sea
## zone makes its water fully visible and reveals the strict coastal ring — only
## land tiles sharing an orthogonal edge with that zone's water.
func reveal_sea_zone(zone_id: int) -> Array:
	var changed: Array = []
	var data: SeaZoneState = model.sea_zone_data(zone_id)
	if data == null:
		return changed
	var water: Array = data.tiles
	for tile: Vector2i in water:
		var index: int = model.index_of(tile.x, tile.y)
		if raise_to(index, Level.FULLY_VISIBLE):
			changed.append(index)
	for tile: Vector2i in water:
		for offset: Vector2i in NEIGHBORS:
			var nx: int = tile.x + offset.x
			var ny: int = tile.y + offset.y
			if not model.in_bounds(nx, ny) or not model.is_land(nx, ny):
				continue
			var index: int = model.index_of(nx, ny)
			if raise_to(index, Level.FULLY_VISIBLE):
				changed.append(index)
	return changed


## Explorer completion (wiki: fog-and-exploration § Exploration): every tile of
## the province becomes fully visible for this player.
func reveal_province(province_id: int) -> Array:
	var changed: Array = []
	for tile: Vector2i in model.province_tiles(province_id):
		var index: int = model.index_of(tile.x, tile.y)
		if raise_to(index, Level.FULLY_VISIBLE):
			changed.append(index)
	return changed


## A civilian goes ashore (wiki: fog-and-exploration § New World arrival;
## DR-20261109-04): the landing tile and its orthogonal neighbours become fully
## visible, while diagonals and the province interior stay as they were.
func reveal_landing(tile: Vector2i) -> Array:
	var changed: Array = []
	if model == null or not model.in_bounds(tile.x, tile.y):
		return changed
	var index: int = model.index_of(tile.x, tile.y)
	if raise_to(index, Level.FULLY_VISIBLE):
		changed.append(index)
	for offset: Vector2i in NEIGHBORS:
		var nx: int = tile.x + offset.x
		var ny: int = tile.y + offset.y
		if not model.in_bounds(nx, ny):
			continue
		var next: int = model.index_of(nx, ny)
		if raise_to(next, Level.FULLY_VISIBLE):
			changed.append(next)
	return changed


## End-of-turn resolution (wiki: fog-and-exploration). Order matters: fog decay,
## distant sea zone fog, explorer presence, own-province re-assert, coastal sea
## pass last. `at_sea_zones` lists zones holding this player's fleets at sea;
## fleets in port do not count. `held_provinces` lists provinces where this
## player keeps an Explorer, which holds them fully visible. Spies never
## survey `unknown` terrain, so their province is not held (DR-20261109-04).
func end_of_turn(at_sea_zones: Array, held_provinces: Array = []) -> Array:
	var changed: Array = []
	changed.append_array(_decay_foreign_provinces())
	changed.append_array(_apply_distant_sea_fog(at_sea_zones))
	for raw: Variant in held_provinces:
		changed.append_array(hold_explored_province(int(raw)))
	changed.append_array(_reveal_own_provinces())
	changed.append_array(_apply_coastal_sea_zones())
	return changed


## Explorer presence holds only what the player already charted
## (wiki: Explorer vs Spy; DR-20261109-04). Tiles still `unknown` stay unknown,
## so a Spy sheltered behind an Explorer cannot survey virgin coast.
func hold_explored_province(province_id: int) -> Array:
	var changed: Array = []
	for tile: Vector2i in model.province_tiles(province_id):
		var index: int = model.index_of(tile.x, tile.y)
		if levels[index] < Level.FOGGED:
			continue
		if raise_to(index, Level.FULLY_VISIBLE):
			changed.append(index)
	return changed


## True when a sea zone has a P–S edge to a province this player fully owns.
func owns_coast(zone_id: int) -> bool:
	for raw: Variant in sea_zone_provinces.get(zone_id, []):
		if model.province_owner(int(raw)) == player_id:
			return true
	return false


## Highest level any tile of the province holds for this player.
func province_visibility(province_id: int) -> int:
	var best: int = Level.UNKNOWN
	for tile: Vector2i in model.province_tiles(province_id):
		var level: int = level_at(tile.x, tile.y)
		if level > best:
			best = level
	return best


func is_province_known(province_id: int) -> bool:
	return province_visibility(province_id) >= Level.FOGGED


func is_province_fully_visible(province_id: int) -> bool:
	var tiles: Array = model.province_tiles(province_id)
	if tiles.is_empty():
		return false
	for tile: Vector2i in tiles:
		if level_at(tile.x, tile.y) < Level.FULLY_VISIBLE:
			return false
	return true


# --- internals --------------------------------------------------------------


## The coast table for this grid, built once per grid state and handed to every
## court that charts it. Keyed by content (not identity) so a restored map finds
## its own table again; the caller gets a copy, so no chart can edit another's.
func _coast_links() -> void:
	if model == null:
		return
	var key: String = "%dx%d|%d|%d|%d" % [
		model.width, model.height, hash(model.terrain), hash(model.province),
		hash(model.sea_zone)
	]
	var cached: Variant = _coast_cache.get(key, null)
	if cached != null:
		_coast_order.erase(key)
		_coast_order.append(key)
		province_sea_zones = (cached as Array)[0].duplicate(true)
		sea_zone_provinces = (cached as Array)[1].duplicate(true)
		return
	province_sea_zones.clear()
	sea_zone_provinces.clear()
	for y in model.height:
		for x in model.width:
			if not model.is_land(x, y):
				continue
			var province_id: int = model.province_at(x, y)
			if province_id == MapModel.NO_ID:
				continue
			for offset: Vector2i in NEIGHBORS:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if not model.in_bounds(nx, ny) or not model.is_sea(nx, ny):
					continue
				var zone_id: int = model.sea_zone_at(nx, ny)
				if zone_id == MapModel.NO_ID:
					continue
				_link(province_sea_zones, province_id, zone_id)
				_link(sea_zone_provinces, zone_id, province_id)
	while _coast_cache.size() >= CACHE_LIMIT and not _coast_order.is_empty():
		_coast_cache.erase(_coast_order.pop_front())
	_coast_cache[key] = [province_sea_zones.duplicate(true), sea_zone_provinces.duplicate(true)]
	_coast_order.append(key)


## Drops every coast table, so a following setup rebuilds rather than reuses.
static func clear_cache() -> void:
	_coast_cache.clear()
	_coast_order.clear()


func _link(table: Dictionary, key: int, value: int) -> void:
	if not table.has(key):
		table[key] = [] as Array[int]
	var values: Array[int] = table[key]
	if not values.has(value):
		values.append(value)
		values.sort()


## Own provinces are always fully visible and never decay. A purchased tile in a
## foreign province is held the same way, tile by tile.
func _reveal_own_provinces() -> Array:
	var changed: Array = []
	for province: ProvinceState in model.provinces:
		var province_id: int = province.id
		for tile: Vector2i in model.province_tiles(province_id):
			if model.owner_at(tile.x, tile.y) != player_id:
				continue
			var index: int = model.index_of(tile.x, tile.y)
			if raise_to(index, Level.FULLY_VISIBLE):
				changed.append(index)
	return changed


## Coastal sea zone pass: zones with a P–S edge to a province this player fully
## owns are fully visible, even where another rule had them fogged.
func _apply_coastal_sea_zones() -> Array:
	var changed: Array = []
	for raw: Variant in sea_zone_provinces.keys():
		var zone_id: int = int(raw)
		if not owns_coast(zone_id):
			continue
		changed.append_array(_raise_sea_zone_water(zone_id, Level.FULLY_VISIBLE))
	return changed


func _raise_sea_zone_water(zone_id: int, level: int) -> Array:
	var changed: Array = []
	var data: SeaZoneState = model.sea_zone_data(zone_id)
	for tile: Vector2i in data.tiles:
		var index: int = model.index_of(tile.x, tile.y)
		if raise_to(index, level):
			changed.append(index)
	return changed


## Fog decay: only stored fullyVisible tiles not held by this player fall back
## to fogged. Deeds inside a foreign province are held like any other holding.
func _decay_foreign_provinces() -> Array:
	var changed: Array = []
	for province: ProvinceState in model.provinces:
		for tile: Vector2i in province.tiles:
			if model.owner_at(tile.x, tile.y) == player_id:
				continue
			var index: int = model.index_of(tile.x, tile.y)
			if lower_to(index, Level.FOGGED):
				changed.append(index)
	return changed


## Distant sea zone fog: a zone without an owned coast and without a fleet at
## sea reverts to fogged; unknown tiles stay unknown.
func _apply_distant_sea_fog(at_sea_zones: Array) -> Array:
	var changed: Array = []
	for zone: SeaZoneState in model.sea_zones:
		var zone_id: int = zone.id
		if zone_id == MapModel.NO_ID:
			continue
		if owns_coast(zone_id) or at_sea_zones.has(zone_id):
			continue
		for tile: Vector2i in zone.tiles:
			var index: int = model.index_of(tile.x, tile.y)
			if lower_to(index, Level.FOGGED):
				changed.append(index)
	return changed


## Plain data for local saves: the per-tile knowledge grid.
func to_dict() -> Dictionary:
	return {"player_id": player_id, "levels": levels.duplicate()}


## Restores the grid onto an already-set-up model (coast links stay derived).
func apply_dict(data: Dictionary) -> bool:
	player_id = int(data.get("player_id", player_id))
	var raw: Variant = data.get("levels", PackedByteArray())
	var restored: PackedByteArray = raw if typeof(raw) == TYPE_PACKED_BYTE_ARRAY else PackedByteArray(raw)
	if model == null or restored.size() != model.width * model.height:
		return false
	levels = restored
	return true
