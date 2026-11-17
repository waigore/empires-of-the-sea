class_name VisibilityModel
extends RefCounted
## Per-player tile visibility (wiki: fog-and-exploration).
## Pure rules state: no nodes, no rendering. One instance per Great Power, so the
## view, AI and tests all read the same engine (REQ-P3-03).
##
## Coast tables live in [VisibilityCoast]; end-of-turn fog decay and coastal
## re-assert live in [VisibilityFog] — each owns one seam so this grid stays
## under the soft size bar (REQ-P3-01).

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
## Bumped whenever a tile changes level; baked views (the minimap) watch it.
var revision: int = 0
## The charted grace a departed Spy leaves behind, one clock per province
## (wiki: fog-and-exploration § Spy timer expiry). Saved with the grid.
var spy_charter: SpyCharter = SpyCharter.new()


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
	VisibilityCoast.bind(self)


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
	changed.append_array(VisibilityFog.reveal_own_provinces(self))
	changed.append_array(VisibilityFog.apply_coastal_sea_zones(self))
	return changed


## Ship reveal (wiki: ships-and-naval § Ship Reveal Mechanic): entering a sea
## zone makes its water fully visible and reveals the strict coastal ring — only
## land tiles sharing an orthogonal edge with that zone's water. `extra_land_rings`
## grows that coastal band by further orthogonal land steps, all `fullyVisible`
## (wiki: leader-bonuses § Bonus Table — Henry the Navigator). Water never
## spreads the extra rings: only land does.
func reveal_sea_zone(zone_id: int, extra_land_rings: int = 0) -> Array:
	var changed: Array = []
	var data: SeaZoneState = model.sea_zone_data(zone_id)
	if data == null:
		return changed
	var water: Array = data.tiles
	for tile: Vector2i in water:
		var index: int = model.index_of(tile.x, tile.y)
		if raise_to(index, Level.FULLY_VISIBLE):
			changed.append(index)
	var coast: Array[Vector2i] = []
	for tile: Vector2i in water:
		for offset: Vector2i in NEIGHBORS:
			var nx: int = tile.x + offset.x
			var ny: int = tile.y + offset.y
			if not model.in_bounds(nx, ny) or not model.is_land(nx, ny):
				continue
			var index: int = model.index_of(nx, ny)
			coast.append(Vector2i(nx, ny))
			if raise_to(index, Level.FULLY_VISIBLE):
				changed.append(index)
	for _ring in maxi(extra_land_rings, 0):
		var frontier: Array[Vector2i] = []
		for tile: Vector2i in coast:
			for offset: Vector2i in NEIGHBORS:
				var nx: int = tile.x + offset.x
				var ny: int = tile.y + offset.y
				if not model.in_bounds(nx, ny) or not model.is_land(nx, ny):
					continue
				var step := Vector2i(nx, ny)
				if frontier.has(step):
					continue
				frontier.append(step)
				var index: int = model.index_of(nx, ny)
				if raise_to(index, Level.FULLY_VISIBLE):
					changed.append(index)
		coast = frontier
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


## End-of-turn resolution (wiki: fog-and-exploration). See [VisibilityFog].
func end_of_turn(
	at_sea_zones: Array, held_provinces: Array = [], spy_provinces: Array = []
) -> Array:
	return VisibilityFog.end_of_turn(self, at_sea_zones, held_provinces, spy_provinces)


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


## Drops every coast table, so a following setup rebuilds rather than reuses.
static func clear_cache() -> void:
	VisibilityCoast.clear_cache()


## Plain data for local saves: the per-tile knowledge grid.
func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"levels": levels.duplicate(),
		"spy_hold": spy_charter.to_dict(),
	}


## Restores the grid onto an already-set-up model (coast links stay derived).
## A save written before the Spy charter existed carries no clocks, and its
## provinces simply start with none.
func apply_dict(data: Dictionary) -> bool:
	player_id = int(data.get("player_id", player_id))
	var raw: Variant = data.get("levels", PackedByteArray())
	var restored: PackedByteArray = raw if typeof(raw) == TYPE_PACKED_BYTE_ARRAY else PackedByteArray(raw)
	if model == null or restored.size() != model.width * model.height:
		return false
	levels = restored
	spy_charter.apply_dict(data.get("spy_hold", {}))
	return true
