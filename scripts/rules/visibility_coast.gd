class_name VisibilityCoast
extends RefCounted
## Province–sea coast tables inferred from the tile grid (wiki: fog-and-
## exploration § Coastal sea zone visibility). Pure derivation: every court that
## charts one region asks for the same table, so a small cache keyed by grid
## content keeps that free while an edited grid still builds its own
## (REQ-P3-01, REQ-P3-03).
##
## [VisibilityModel] owns the per-tile knowledge grid; this module only fills the
## P–S edge tables the coastal and distant-sea fog passes read.

const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]

## How many coast tables to keep. The links are a pure function of the tile grid
## and every court charting one region (and every screen a suite mounts on the
## shared world) asks for the same table: a small bound keeps that free while an
## edited grid still builds its own.
const CACHE_LIMIT: int = 8
static var _cache: Dictionary = {}
## Cache keys oldest-first, so a full shelf drops one grid rather than all.
static var _order: Array[String] = []


## Drops every coast table, so a following setup rebuilds rather than reuses.
static func clear_cache() -> void:
	_cache.clear()
	_order.clear()


## Fills `chart.province_sea_zones` and `chart.sea_zone_provinces` from the
## chart's model. The caller gets a copy of any cached tables, so no chart can
## edit another's.
static func bind(chart: VisibilityModel) -> void:
	if chart == null or chart.model == null:
		return
	var model: MapModel = chart.model
	var key: String = "%dx%d|%d|%d|%d" % [
		model.width, model.height, hash(model.terrain), hash(model.province),
		hash(model.sea_zone)
	]
	var cached: Variant = _cache.get(key, null)
	if cached != null:
		_order.erase(key)
		_order.append(key)
		chart.province_sea_zones = (cached as Array)[0].duplicate(true)
		chart.sea_zone_provinces = (cached as Array)[1].duplicate(true)
		return
	chart.province_sea_zones.clear()
	chart.sea_zone_provinces.clear()
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
				_link(chart.province_sea_zones, province_id, zone_id)
				_link(chart.sea_zone_provinces, zone_id, province_id)
	while _cache.size() >= CACHE_LIMIT and not _order.is_empty():
		_cache.erase(_order.pop_front())
	_cache[key] = [
		chart.province_sea_zones.duplicate(true),
		chart.sea_zone_provinces.duplicate(true),
	]
	_order.append(key)


static func _link(table: Dictionary, key: int, value: int) -> void:
	if not table.has(key):
		table[key] = [] as Array[int]
	var values: Array[int] = table[key]
	if not values.has(value):
		values.append(value)
		values.sort()
