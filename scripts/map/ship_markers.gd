class_name ShipMarkers
extends RefCounted
## Marker bookkeeping for one region's fleet roster: mint one [Ship] per fleet,
## refit it after an order and drop it when the squadron leaves the map.
## ShipLayer keeps orders, battles and signals; this helper owns the node
## lifecycle so the layer stays under the soft size bar (REQ-P3-01, REQ-P3-03).
## The layer adds every minted node to itself.

const TILE_SIZE: float = 22.0

var model: MapModel = null
var ships: Array[Ship] = []
var selected_ship: Ship = null
var rng := RandomNumberGenerator.new()


## Mints a marker and places it where the fleet already stands.
func make(fleet: FleetState) -> Ship:
	var ship := Ship.new()
	ship.fleet_id = fleet.id
	ship.faction = fleet.owner
	ship.bob_phase = rng.randf() * TAU
	ship.speed = 26.0 + rng.randf() * 16.0
	place(ship, fleet)
	ships.append(ship)
	return ship


## Keeps the marker in step with the fleet's location and colours.
func refit(ship: Ship, fleet: FleetState) -> void:
	ship.faction = fleet.owner
	place(ship, fleet)


## Frees every marker and clears the selection.
func clear() -> void:
	for ship: Ship in ships:
		ship.queue_free()
	ships.clear()
	selected_ship = null


## Drops one marker, clearing the selection when it was the selected hull.
func remove(ship: Ship) -> void:
	if ship == null:
		return
	if selected_ship == ship:
		selected_ship = null
	ships.erase(ship)
	ship.queue_free()


## Marker for a fleet id, or null when that squadron has no node.
func find(fleet_id: int) -> Ship:
	for ship: Ship in ships:
		if ship.fleet_id == fleet_id:
			return ship
	return null


func place(ship: Ship, fleet: FleetState) -> void:
	if model == null:
		return
	if fleet.is_in_port():
		var data: ProvinceState = model.province_data(fleet.province)
		var port: Vector2i = data.port_tile if data != null else Vector2i(-1, -1)
		if port.x < 0 or port.y < 0:
			# A reassigned seat may be coastal without a registered port tile
			# (wiki: ships-and-naval § Ports that change hands; DR-20261109-12).
			ship.position = model.province_center(fleet.province) * TILE_SIZE
		else:
			ship.position = MapGeo.tile_center(port.x, port.y, TILE_SIZE)
		ship.docked = true
		ship.zone = -1
		ship.province = fleet.province
		return
	ship.position = model.sea_zone_center(fleet.sea_zone) * TILE_SIZE
	ship.docked = false
	ship.zone = fleet.sea_zone
	ship.province = MapModel.NO_ID
