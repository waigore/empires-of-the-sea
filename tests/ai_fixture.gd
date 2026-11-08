extends RefCounted
## Shared fixtures for the AI suites: hand-built worlds and planner contexts.
## Provinces are stubs (id/owner/resource only) because the AI reads ownership,
## region membership and resource ids — never terrain (REQ-P3-03).


## One Old World region with `owners.size()` provinces, one per entry.
static func world(owners: Array[int], resources: Dictionary = {}) -> WorldMap:
	var model := MapModel.new()
	model.setup(maxi(owners.size(), 1), 1)
	for index in owners.size():
		var tiles: Array[Vector2i] = [Vector2i(index, 0)]
		var province := ProvinceState.create(
			index,
			"P%d" % index,
			tiles,
			Vector2(float(index), 0.0),
			1,
			owners[index],
			false
		)
		if resources.has(index):
			province.resource = int(resources[index])
			province.resource_tile = Vector2i(index, 0)
		model.provinces.append(province)
	var world_map := WorldMap.new()
	world_map.add_region(model)
	return world_map


## Planner context with absolute power scores (and optional unit counts).
static func context(power: Dictionary, regiments: Dictionary = {}, ships: Dictionary = {}) -> Dictionary:
	return {"power": power, "regiments": regiments, "ships": ships}
