class_name AdvancedSeas
extends RefCounted
## The New World sea lanes an advanced start inherits (wiki: advanced-starts
## § NW sea-zone visibility). Pure zone arithmetic over the map's S–S topology:
## no nodes, no rendering (REQ-P3-03).
##
## A crown charts the water that touches a flood-filled province and the lanes
## that reach it from the Passage, at `fogged` — charted, not surveyed. Water off
## the lane and off a revealed shore stays `unknown`, so an advanced start still
## leaves a coast to discover.

## Sea knowledge for a revealed-but-not-owned shore: charted, not surveyed.
const CHARTED: int = VisibilityModel.Level.FOGGED

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


## Every sea zone the inherited chart holds for one crown: the zones P–S adjacent
## to a charted province, plus the zones on a shortest S–S lane from a warp entry
## to one of them, in id order.
static func charted(model: MapModel, entries: Array[int], provinces: Array[int]) -> Array[int]:
	var shores: Array[int] = []
	if model == null:
		return shores
	for province_id: int in provinces:
		for zone: int in NavalMovement.province_sea_zones(model, province_id):
			if not shores.has(zone):
				shores.append(zone)
	shores.sort()
	if shores.is_empty() or entries.is_empty():
		return shores
	var lanes: Array[int] = []
	var from_entry: Dictionary = hops(model, entries)
	for goal: int in shores:
		if not from_entry.has(goal):
			continue
		var span: int = int(from_entry[goal])
		var to_goal: Dictionary = hops(model, [goal])
		for raw: Variant in to_goal.keys():
			var zone: int = int(raw)
			if int(from_entry.get(zone, span + 1)) + int(to_goal[zone]) != span:
				continue
			if not lanes.has(zone):
				lanes.append(zone)
	lanes.sort()
	return lanes


## Zone -> S–S hops from the nearest of `starts`, over the map's sea neighbours.
static func hops(model: MapModel, starts: Array[int]) -> Dictionary:
	var seen: Dictionary = {}
	var queue: Array[int] = []
	for zone: int in starts:
		if seen.has(zone):
			continue
		seen[zone] = 0
		queue.append(zone)
	var head: int = 0
	while head < queue.size():
		var zone: int = queue[head]
		head += 1
		for next: int in MapGeo.sea_zone_neighbors(model, zone):
			if seen.has(next):
				continue
			seen[next] = int(seen[zone]) + 1
			queue.append(next)
	return seen


## Paints one inherited zone for a crown: `fullyVisible` when the crown holds a
## tile on its shore (the standard coastal pass), `fogged` water otherwise.
static func chart(model: MapModel, visibility: VisibilityModel, zone: int, faction: int) -> void:
	if model == null or visibility == null:
		return
	if owns_shore(model, zone, faction):
		visibility.reveal_sea_zone(zone)
		return
	var data: SeaZoneState = model.sea_zone_data(zone)
	if data == null:
		return
	for tile: Vector2i in data.tiles:
		visibility.raise_to(model.index_of(tile.x, tile.y), CHARTED)


## True when a land tile touching the zone's water belongs to the crown — a
## colony's beach, or a deed bought inside a foreign province.
static func owns_shore(model: MapModel, zone: int, faction: int) -> bool:
	var data: SeaZoneState = model.sea_zone_data(zone)
	if data == null:
		return false
	for tile: Vector2i in data.tiles:
		for offset: Vector2i in NEIGHBOURS:
			var x: int = tile.x + offset.x
			var y: int = tile.y + offset.y
			if not model.in_bounds(x, y) or not model.is_land(x, y):
				continue
			if model.owner_at(x, y) == faction:
				return true
	return false
