class_name FleetVisibility
extends RefCounted
## Fog changes caused by fleets (wiki: fog-and-exploration, ships-and-naval).
## Returns tile/zone sets; the overlay applies them, so visibility rules stay
## testable without a viewport (REQ-P3-03).

const ORTHOGONAL: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


## Water tiles of one sea zone.
static func water_tiles(model: MapModel, zone_id: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var data: Dictionary = model.sea_zone_data(zone_id)
	for tile: Vector2i in data.get("tiles", []):
		if model.is_sea(tile.x, tile.y):
			tiles.append(tile)
	return tiles


## Everything a fleet reveals on entering a zone: the zone's water plus the
## coastal land ring (land tiles orthogonally adjacent to that water).
static func ring_tiles(model: MapModel, zone_id: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in water_tiles(model, zone_id):
		if not tiles.has(tile):
			tiles.append(tile)
		for offset: Vector2i in ORTHOGONAL:
			var nx: int = tile.x + offset.x
			var ny: int = tile.y + offset.y
			if not model.is_land(nx, ny):
				continue
			var land: Vector2i = Vector2i(nx, ny)
			if not tiles.has(land):
				tiles.append(land)
	return tiles


## Sea zones bordering any province fully owned by `owner`.
static func coastal_zones(model: MapModel, owner: int) -> Array[int]:
	var zones: Array[int] = []
	for province: Dictionary in model.provinces:
		if int(province.get("owner", MapModel.NO_ID)) != owner:
			continue
		var province_id: int = int(province.get("id", MapModel.NO_ID))
		for zone: int in NavalMovement.province_sea_zones(model, province_id):
			if not zones.has(zone):
				zones.append(zone)
	zones.sort()
	return zones


## Zones that revert to fogged this turn: no owned coast and no fleet at sea
## there. Unknown tiles are never promoted by this rule; the overlay enforces
## that when it applies the downgrade.
static func zones_to_refog(
	model: MapModel, owner: int, occupied_zones: Array[int]
) -> Array[int]:
	var coastal: Array[int] = coastal_zones(model, owner)
	var zones: Array[int] = []
	for zone: Dictionary in model.sea_zones:
		var zone_id: int = int(zone.get("id", MapModel.NO_ID))
		if zone_id == MapModel.NO_ID:
			continue
		if coastal.has(zone_id) or occupied_zones.has(zone_id):
			continue
		zones.append(zone_id)
	zones.sort()
	return zones
