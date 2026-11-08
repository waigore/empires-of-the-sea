class_name TechDiscovery
extends RefCounted
## Which commodities the crown has actually seen this campaign (wiki: tech-tree
## § Discovery prerequisites; fog-and-exploration). Discovery techs stay locked
## until a tile holding their resource is revealed — and, for prospect-only
## minerals, prospected by this player.

## Commodity id -> true across every region the player has charted.
static func revealed(
	world: WorldMap,
	visibility_by_region: Dictionary,
	works: LandWorks,
	owner: int
) -> Dictionary:
	var found: Dictionary = {}
	if world == null:
		return found
	for region in world.region_count():
		var model: MapModel = world.region(region)
		var visibility: VisibilityModel = visibility_by_region.get(region)
		if model == null or visibility == null:
			continue
		_scan(model, visibility, works, owner, found)
	return found


static func _scan(
	model: MapModel,
	visibility: VisibilityModel,
	works: LandWorks,
	owner: int,
	found: Dictionary
) -> void:
	for y in model.height:
		for x in model.width:
			if not model.is_land(x, y):
				continue
			var resource: int = model.resource_at(x, y)
			var commodity: String = Extraction.commodity_for_resource(resource)
			if commodity.is_empty() or found.has(commodity):
				continue
			if visibility.level_at(x, y) < VisibilityModel.Level.FOGGED:
				continue
			if (
				ImprovementCatalog.needs_prospecting(resource)
				and (works == null or not works.is_prospected(owner, model, Vector2i(x, y)))
			):
				continue
			found[commodity] = true
