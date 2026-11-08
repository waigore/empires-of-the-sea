extends RefCounted
## Synthetic map shared by rules tests: two coastal provinces, two adjacent sea
## zones, one owned harbour each. Kept tiny so expectations stay readable.


static func build() -> MapModel:
	var model := MapModel.new()
	model.setup(7, 3)
	_fill_land(model, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], 0)
	_fill_land(model, [Vector2i(5, 0), Vector2i(5, 1)], 1)
	# Neutral land keeps the two coasts apart.
	for tile: Vector2i in [Vector2i(3, 0), Vector2i(4, 0)]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
	for tile: Vector2i in [
		Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	]:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 0
	for tile: Vector2i in [
		Vector2i(3, 1), Vector2i(4, 1), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2),
	]:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 1
	model.provinces = [
		{
			"id": 0,
			"name": "Cádiz",
			"tiles": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
			"center": Vector2(0.5, 0.5),
			"area": 3,
			"owner": 0,
			"capital": true,
			"port_tile": Vector2i(1, 0),
		},
		{
			"id": 1,
			"name": "Coro",
			"tiles": [Vector2i(5, 0), Vector2i(5, 1)],
			"center": Vector2(5.0, 0.5),
			"area": 2,
			"owner": 1,
			"capital": false,
			"port_tile": Vector2i(5, 1),
		},
	]
	model.sea_zones = [
		{
			"id": 0,
			"name": "Mar Caribe",
			"tiles": [
				Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1),
				Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
			],
			"center": Vector2(1.5, 1.5),
			"area": 6,
		},
		{
			"id": 1,
			"name": "Golfo de México",
			"tiles": [
				Vector2i(3, 1), Vector2i(4, 1), Vector2i(3, 2), Vector2i(4, 2),
				Vector2i(5, 2),
			],
			"center": Vector2(4.0, 1.5),
			"area": 5,
		},
	]
	return model


static func _fill_land(model: MapModel, tiles: Array, province_id: int) -> void:
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = province_id
