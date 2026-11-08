class_name VisibilityModel
extends RefCounted
## Per-player tile visibility (wiki: fog-and-exploration).
## Pure rules state: no nodes, no rendering. One instance per Great Power, so the
## view, AI and tests all read the same engine (REQ-P3-03).

enum Level { UNKNOWN, FOGGED, FULLY_VISIBLE }

const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]

var model: MapModel = null
var player_id: int = 0
var levels: PackedByteArray = PackedByteArray()
## Province -> sea zones sharing a P–S edge (inferred from the tile grid).
var province_sea_zones: Dictionary = {}
## Sea zone -> provinces sharing a P–S edge.
var sea_zone_provinces: Dictionary = {}


## Allocates the Old World baseline: fogged everywhere, no reveal applied yet.
func setup(p_model: MapModel, p_player_id: int) -> void:
	model = p_model
	player_id = p_player_id
	var count: int = model.width * model.height
	levels.resize(count)
	levels.fill(Level.FOGGED)
	_build_coast_links()


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
	return true


## Only fog decay lowers knowledge, and it never reaches below `level`.
func lower_to(index: int, level: int) -> bool:
	if index < 0 or index >= levels.size():
		return false
	if levels[index] <= level:
		return false
	levels[index] = level
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
	var data: Dictionary = model.sea_zone_data(zone_id)
	if data.is_empty():
		return changed
	var water: Array = data.get("tiles", [])
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


## End-of-turn resolution (wiki: fog-and-exploration). Order matters: fog decay,
## distant sea zone fog, explorer presence, own-province re-assert, coastal sea
## pass last. `at_sea_zones` lists zones holding this player's fleets at sea;
## fleets in port do not count. `held_provinces` lists provinces where this
## player keeps a civilian, which holds them fully visible.
func end_of_turn(at_sea_zones: Array, held_provinces: Array = []) -> Array:
	var changed: Array = []
	changed.append_array(_decay_foreign_provinces())
	changed.append_array(_apply_distant_sea_fog(at_sea_zones))
	for raw: Variant in held_provinces:
		changed.append_array(reveal_province(int(raw)))
	changed.append_array(_reveal_own_provinces())
	changed.append_array(_apply_coastal_sea_zones())
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


func _build_coast_links() -> void:
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


func _link(table: Dictionary, key: int, value: int) -> void:
	if not table.has(key):
		table[key] = [] as Array[int]
	var values: Array[int] = table[key]
	if not values.has(value):
		values.append(value)
		values.sort()


## Own provinces are always fully visible and never decay.
func _reveal_own_provinces() -> Array:
	var changed: Array = []
	for province: Dictionary in model.provinces:
		if int(province.get("owner", MapModel.NO_ID)) != player_id:
			continue
		var province_id: int = int(province["id"])
		for tile: Vector2i in model.province_tiles(province_id):
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
	var data: Dictionary = model.sea_zone_data(zone_id)
	for tile: Vector2i in data.get("tiles", []):
		var index: int = model.index_of(tile.x, tile.y)
		if raise_to(index, level):
			changed.append(index)
	return changed


## Fog decay: only stored fullyVisible tiles in other factions' provinces fall
## back to fogged; own provinces and unknown/fogged tiles are never touched.
func _decay_foreign_provinces() -> Array:
	var changed: Array = []
	for province: Dictionary in model.provinces:
		if int(province.get("owner", MapModel.NO_ID)) == player_id:
			continue
		for tile: Vector2i in province.get("tiles", []):
			var index: int = model.index_of(tile.x, tile.y)
			if lower_to(index, Level.FOGGED):
				changed.append(index)
	return changed


## Distant sea zone fog: a zone without an owned coast and without a fleet at
## sea reverts to fogged; unknown tiles stay unknown.
func _apply_distant_sea_fog(at_sea_zones: Array) -> Array:
	var changed: Array = []
	for zone: Dictionary in model.sea_zones:
		var zone_id: int = int(zone.get("id", MapModel.NO_ID))
		if zone_id == MapModel.NO_ID:
			continue
		if owns_coast(zone_id) or at_sea_zones.has(zone_id):
			continue
		for tile: Vector2i in zone.get("tiles", []):
			var index: int = model.index_of(tile.x, tile.y)
			if lower_to(index, Level.FOGGED):
				changed.append(index)
	return changed
