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


## Mints a marker and places it where the fleet already stands. `crown_view`
## answers what the crown's chart says of one squadron (`drawn`, `read`), so a
## marker reminted by a merge, a passage or a captured port starts where the
## chart stands instead of handing back what the fog withholds (wiki:
## ships-and-naval § Sighted strength; fog-and-exploration § Visibility Levels).
func make(fleet: FleetState, crown_view: Callable = Callable()) -> Ship:
	var ship := Ship.new()
	ship.fleet_id = fleet.id
	ship.faction = fleet.owner
	ship.bob_phase = rng.randf() * TAU
	ship.speed = 26.0 + rng.randf() * 16.0
	refit(ship, fleet)
	if crown_view.is_valid():
		var view: Dictionary = crown_view.call(fleet)
		ship.visible = bool(view.get("drawn", true))
		ship.set_intel(bool(view.get("read", false)))
	ships.append(ship)
	return ship


## Keeps the marker in step with the fleet's location, colours and squadron: a
## launch, a breaking up, a merge or a battle all change the hulls it flies.
func refit(ship: Ship, fleet: FleetState) -> void:
	ship.faction = fleet.owner
	ship.set_squadron(fleet.ship_count(), NavalStrength.strength(fleet))
	place(ship, fleet)


## Re-reads one squadron's hulls and strength, leaving its berth and any sail
## under way alone: a launch or a breaking up never moves the marker.
func hulls(fleet: FleetState) -> void:
	var ship: Ship = find(fleet.id)
	if ship != null:
		ship.set_squadron(fleet.ship_count(), NavalStrength.strength(fleet))


## Re-reads every roster fleet onto its marker: battles change hulls without
## moving anyone, and a stale count would mislead the court.
func sync(fleets: Array) -> void:
	for fleet: FleetState in fleets:
		hulls(fleet)


## Moves markers for a beaten squadron that escaped a naval battle: each one
## sails to its haven and reports the new zone (wiki: ships-and-naval § Naval
## Retreat Formula).
func retreat(battle: Dictionary, fleets: Array) -> Array[Ship]:
	var moved: Array[Ship] = []
	var retreat: Dictionary = battle.get("retreat", {})
	if not bool(retreat.get("success", false)):
		return moved
	for raw: Variant in retreat.get("fleets", []):
		var fleet: FleetState = _fleet(fleets, int(raw))
		if fleet == null:
			continue
		var ship: Ship = find(fleet.id)
		if ship == null:
			continue
		ship.zone = fleet.sea_zone
		ship.docked = false
		ship.province = MapModel.NO_ID
		sail(ship, model.sea_zone_center(fleet.sea_zone) * TILE_SIZE)
		moved.append(ship)
	return moved


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


static func _fleet(fleets: Array, fleet_id: int) -> FleetState:
	for fleet: FleetState in fleets:
		if fleet != null and fleet.id == fleet_id:
			return fleet
	return null


## Sails one marker to a new berth, replacing any sail already under way.
static func sail(ship: Ship, target: Vector2) -> void:
	if ship.has_meta("sail_tween"):
		var previous: Tween = ship.get_meta("sail_tween") as Tween
		if previous != null and previous.is_valid():
			previous.kill()
	var tween: Tween = ship.create_tween()
	tween.tween_property(ship, "position", target, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_IN_OUT
	)
	ship.set_meta("sail_tween", tween)
