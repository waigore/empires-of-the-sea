class_name VisibilityFog
extends RefCounted
## End-of-turn fog decay and coastal re-assert (wiki: fog-and-exploration).
## Order matters: fog decay, distant sea zone fog, presence holds, own-province
## re-assert, coastal sea pass last. Pure rules on a [VisibilityModel] chart —
## no nodes (REQ-P3-01, REQ-P3-03).
##
## The chart owns raise/lower; this module only walks the turn's fog pipeline
## so the grid file stays under the soft size bar.


## End-of-turn resolution. `at_sea_zones` lists zones holding this player's
## fleets at sea; fleets in port do not count. `held_provinces` lists the
## provinces where this player keeps an Explorer or a Spy, so a crew's presence
## holds the ground it charted — and the last Spy leaving fogs its province in
## this same pass, with no grace (wiki: fog-and-exploration § Fog Decay;
## civilian-units § Spy (1); DR-20261110-03).
static func end_of_turn(
	chart: VisibilityModel,
	at_sea_zones: Array,
	held_provinces: Array = []
) -> Array:
	var held: Array = held_provinces.duplicate()
	var changed: Array = []
	changed.append_array(decay_foreign_provinces(chart))
	changed.append_array(apply_distant_sea_fog(chart, at_sea_zones))
	for raw: Variant in held:
		changed.append_array(chart.hold_explored_province(int(raw)))
	changed.append_array(reveal_own_provinces(chart))
	changed.append_array(apply_coastal_sea_zones(chart))
	return changed


## Own provinces are always fully visible and never decay. A purchased tile in a
## foreign province is held the same way, tile by tile.
static func reveal_own_provinces(chart: VisibilityModel) -> Array:
	var changed: Array = []
	var model: MapModel = chart.model
	for province: ProvinceState in model.provinces:
		var province_id: int = province.id
		for tile: Vector2i in model.province_tiles(province_id):
			if model.owner_at(tile.x, tile.y) != chart.player_id:
				continue
			var index: int = model.index_of(tile.x, tile.y)
			if chart.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE):
				changed.append(index)
	return changed


## Coastal sea zone pass: zones with a P–S edge to a province this player fully
## owns are fully visible, even where another rule had them fogged.
static func apply_coastal_sea_zones(chart: VisibilityModel) -> Array:
	var changed: Array = []
	for raw: Variant in chart.sea_zone_provinces.keys():
		var zone_id: int = int(raw)
		if not chart.owns_coast(zone_id):
			continue
		changed.append_array(
			raise_sea_zone_water(chart, zone_id, VisibilityModel.Level.FULLY_VISIBLE)
		)
	return changed


static func raise_sea_zone_water(
	chart: VisibilityModel, zone_id: int, level: int
) -> Array:
	var changed: Array = []
	var data: SeaZoneState = chart.model.sea_zone_data(zone_id)
	for tile: Vector2i in data.tiles:
		var index: int = chart.model.index_of(tile.x, tile.y)
		if chart.raise_to(index, level):
			changed.append(index)
	return changed


## Fog decay: only stored fullyVisible tiles not held by this player fall back
## to fogged. Deeds inside a foreign province are held like any other holding.
static func decay_foreign_provinces(chart: VisibilityModel) -> Array:
	var changed: Array = []
	var model: MapModel = chart.model
	for province: ProvinceState in model.provinces:
		for tile: Vector2i in province.tiles:
			if model.owner_at(tile.x, tile.y) == chart.player_id:
				continue
			var index: int = model.index_of(tile.x, tile.y)
			if chart.lower_to(index, VisibilityModel.Level.FOGGED):
				changed.append(index)
	return changed


## Distant sea zone fog: a zone without an owned coast and without a fleet at
## sea reverts to fogged; unknown tiles stay unknown.
static func apply_distant_sea_fog(
	chart: VisibilityModel, at_sea_zones: Array
) -> Array:
	var changed: Array = []
	for zone: SeaZoneState in chart.model.sea_zones:
		var zone_id: int = zone.id
		if zone_id == MapModel.NO_ID:
			continue
		if chart.owns_coast(zone_id) or at_sea_zones.has(zone_id):
			continue
		for tile: Vector2i in zone.tiles:
			var index: int = chart.model.index_of(tile.x, tile.y)
			if chart.lower_to(index, VisibilityModel.Level.FOGGED):
				changed.append(index)
	return changed
