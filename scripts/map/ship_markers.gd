class_name ShipMarkers
extends RefCounted
## Marker bookkeeping for one region's fleet roster: mint one [Ship] per fleet,
## refit it after an order and drop it when the squadron leaves the map.
## ShipLayer keeps orders and signals; ShipTurnPass owns battles; this helper
## owns the node lifecycle so the layer stays under the soft size bar
## (REQ-P3-01, REQ-P3-03). The layer adds every minted node to itself.

const TILE_SIZE: float = 22.0

var model: MapModel = null
var ships: Array[Ship] = []
var selected_ship: Ship = null
var rng := RandomNumberGenerator.new()
## The chart's zoom, so a marker minted by a rebuild, a merge or a launch reads
## the chart it is drawn on (wiki: ships-and-naval § Sighted strength).
var zoom: float = 1.0


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
	apply_zoom(ship)
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


## The chart's own reading on one marker: a closer chart scales the silhouette
## in and prints the strength to one decimal, fit zoom keeps a whole number and
## the full silhouette (wiki: ships-and-naval § Sighted strength, REQ-P1-07).
## Applied at mint, so a marker repainted by a split, a merge, a region mount or
## a launch reads the chart as it stands instead of falling back to fit zoom.
func apply_zoom(ship: Ship) -> void:
	if ship == null:
		return
	ship.scale = Vector2.ONE * clampf(1.0 / zoom, 0.6, 1.0)
	ship.detail = zoom >= Ship.DETAIL_ZOOM


func set_zoom(value: float) -> void:
	zoom = maxf(value, 0.001)
	for ship: Ship in ships:
		apply_zoom(ship)


## Drops the marker of every squadron the roster no longer carries (sunk this
## turn): a marker without a command could still be tapped and ordered.
func prune(fleets: Array) -> void:
	var alive: Dictionary = {}
	for fleet: FleetState in fleets:
		if fleet != null:
			alive[fleet.id] = true
	for ship: Ship in ships.duplicate():
		if not alive.has(ship.fleet_id):
			remove(ship)


## Moves markers for a beaten squadron that escaped a naval battle: each one
## sails to its haven and reports the new zone (wiki: ships-and-naval § Naval
## Retreat Formula).
func retreat(battle: Dictionary, fleets: Array[FleetState]) -> Array[Ship]:
	var moved: Array[Ship] = []
	var retreat: Dictionary = battle.get("retreat", {})
	if not bool(retreat.get("success", false)):
		return moved
	for raw: Variant in retreat.get("fleets", []):
		var fleet: FleetState = FleetRosters.find(fleets, int(raw))
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


## Lays every marker out for her station: the crown's squadrons fan out in a
## short row, and the rest of hers and every rival's ride one stack whose head
## draws the hull (wiki: ships-and-naval § Fleets in one station;
## DR-20261119-08). Cheap and idempotent, so a selection, a launch, a merge, a
## battle, a passage or the fog's close re-reads it.
func layout(fleets: Array, player: int) -> void:
	var selected_id: int = -1
	if selected_ship != null and is_instance_valid(selected_ship):
		selected_id = selected_ship.fleet_id
	var hidden: Array[int] = []
	for ship: Ship in ships:
		if not ship.visible:
			hidden.append(ship.fleet_id)
	var plan: Dictionary = FleetLanes.plan(fleets, player, selected_id, hidden)
	var lanes: Dictionary = plan["lanes"]
	var stacks: Dictionary = plan["stacks"]
	var stations: Dictionary = plan["stations"]
	for ship: Ship in ships:
		var seat: Variant = lanes.get(ship.fleet_id)
		var offset: Vector2 = Vector2.ZERO
		if seat is Vector2:
			offset = seat
		var here: Array[int] = []
		var seats: Variant = stations.get(ship.fleet_id)
		if seats is Array:
			here.assign(seats)
		ship.set_lane(
			offset, _behind(ship, stacks, fleets, hidden), not lanes.has(ship.fleet_id), here
		)
		var order: Variant = stacks.get(ship.fleet_id)
		ship.stack.assign(order if order is Array else [])


## The next squadron a tap on a stack picks: the cycle walks every squadron the
## chart draws, so crowded water is read one command at a time — and a rival the
## fog withholds is never handed over (wiki: ships-and-naval § Fleets in one
## station, § Sighted strength). Null when she stands alone.
func next_in_stack(ship: Ship) -> Ship:
	if ship == null or ship.stack.size() < 2:
		return null
	var start: int = maxi(ship.stack.find(ship.fleet_id), 0)
	for step in range(1, ship.stack.size()):
		var next: Ship = find(ship.stack[(start + step) % ship.stack.size()])
		if next != null and next.visible:
			return next
	return null


## The courts standing behind one marker in her stack, one pip per squadron. A
## squadron the chart does not draw rides nothing: her court's colour would print
## the presence the fog withholds (wiki: ships-and-naval § Sighted strength).
func _behind(ship: Ship, stacks: Dictionary, fleets: Array, hidden: Array[int]) -> Array[int]:
	var behind: Array[int] = []
	var order: Variant = stacks.get(ship.fleet_id)
	if not (order is Array):
		return behind
	for raw: Variant in order:
		var other: FleetState = FleetRosters.find(fleets, int(raw))
		if other != null and other.id != ship.fleet_id and not hidden.has(other.id):
			behind.append(other.owner)
	return behind


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
		ship.position = port_position(model, fleet.province)
		ship.docked = true
		ship.zone = -1
		ship.province = fleet.province
		return
	ship.position = model.sea_zone_center(fleet.sea_zone) * TILE_SIZE
	ship.docked = false
	ship.zone = fleet.sea_zone
	ship.province = MapModel.NO_ID


## Where a squadron's marker berths in port: the province's registered port
## tile, or its centre when a reassigned seat is coastal without one (wiki:
## ships-and-naval § Ports that change hands; DR-20261109-12). The sail orders
## take their target from here too, so a docking never lands twice.
static func port_position(model: MapModel, province_id: int) -> Vector2:
	if model == null:
		return Vector2.ZERO
	var data: ProvinceState = model.province_data(province_id)
	var port: Vector2i = data.port_tile if data != null else Vector2i(-1, -1)
	if port.x < 0 or port.y < 0:
		return model.province_center(province_id) * TILE_SIZE
	return MapGeo.tile_center(port.x, port.y, TILE_SIZE)


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
