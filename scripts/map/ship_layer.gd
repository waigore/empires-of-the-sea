class_name ShipLayer
extends Node2D
## Owns fleet markers: spawns them in sea zones, sails them along S-S edges and
## reports zone entries so exploration can reveal the map (wiki: ships-and-naval).

signal zone_entered(zone_id: int, ship: Ship)
signal ship_selected(ship: Ship)

const TILE_SIZE: float = 22.0

var model: MapModel = null
var ships: Array[Ship] = []
var selected_ship: Ship = null

var _rng := RandomNumberGenerator.new()
var _zoom: float = 1.0


func spawn(p_model: MapModel, count: int, seed_value: int) -> void:
	model = p_model
	_rng.seed = seed_value
	for ship: Ship in ships:
		ship.queue_free()
	ships.clear()
	if model.sea_zone_count() == 0:
		return
	for i in count:
		var zone: int = _rng.randi_range(0, model.sea_zone_count() - 1)
		var ship := Ship.new()
		ship.faction = i % Palette.FACTION_COLORS.size()
		ship.zone = zone
		ship.bob_phase = _rng.randf() * TAU
		ship.speed = 26.0 + _rng.randf() * 16.0
		ship.position = model.sea_zone_center(zone) * TILE_SIZE
		ship.target_zone = _pick_next_zone(zone)
		add_child(ship)
		ships.append(ship)


func set_zoom(value: float) -> void:
	_zoom = maxf(value, 0.001)
	for ship: Ship in ships:
		var scale_factor: float = clampf(1.0 / _zoom, 0.6, 1.0)
		ship.scale = Vector2.ONE * scale_factor


func select(ship: Ship) -> void:
	if selected_ship != null and is_instance_valid(selected_ship):
		selected_ship.set_selected(false)
	selected_ship = ship
	if ship != null:
		ship.set_selected(true)
	ship_selected.emit(ship)


func ship_at(world_position: Vector2, radius: float = 26.0) -> Ship:
	var best: Ship = null
	var best_distance: float = radius
	for ship: Ship in ships:
		var distance: float = ship.position.distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = ship
	return best


func _process(delta: float) -> void:
	if model == null:
		return
	for ship: Ship in ships:
		if ship.target_zone < 0:
			ship.target_zone = _pick_next_zone(ship.zone)
			continue
		var target: Vector2 = model.sea_zone_center(ship.target_zone) * TILE_SIZE
		var to_target: Vector2 = target - ship.position
		var step: float = ship.speed * delta
		if to_target.length() <= step:
			ship.position = target
			ship.zone = ship.target_zone
			zone_entered.emit(ship.zone, ship)
			ship.target_zone = _pick_next_zone(ship.zone)
		else:
			ship.position += to_target.normalized() * step
			ship.facing = 1.0 if to_target.x >= 0.0 else -1.0


func _pick_next_zone(from_zone: int) -> int:
	var neighbors: Array = model.sea_zone_neighbors(from_zone)
	if neighbors.is_empty():
		return -1
	return int(neighbors[_rng.randi_range(0, neighbors.size() - 1)])
