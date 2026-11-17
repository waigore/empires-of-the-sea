class_name CivilianWorkGates
extends RefCounted
## Per-action start gates for civilian work orders (wiki: civilian-units § Work
## Types, extraction-and-improvements, siege-mechanics § Fort Levels). Pure
## rules: one refusal dictionary shared by CivilianWork.validate so the dossier
## and AI planners never invent a second gate (REQ-P3-01, REQ-P3-03).


static func deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": {}, "duration": 0}


## Action-specific start check after the unit, tile and province are already
## known to be legal work targets.
static func check_action(
	model: MapModel,
	unit: CivilianState,
	action: String,
	tile: Vector2i,
	province: int,
	works: LandWorks,
	units: Array[CivilianState],
	visibility: VisibilityModel,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {},
	context: Dictionary = {}
) -> Dictionary:
	match action:
		"explore":
			var explore_gate: String = CivilianExplorerGates.explore_refusal(
				model, unit.owner, province, context
			)
			if not explore_gate.is_empty():
				return deny(explore_gate)
			if visibility != null and visibility.is_province_fully_visible(province):
				return deny("%s is already charted." % model.province_name(province))
			return {"ok": true}
		"prospect":
			var prospect_gate: String = CivilianExplorerGates.prospect_refusal(
				model, unit.owner, unit.tile, tile, works, visibility, context
			)
			if not prospect_gate.is_empty():
				return deny(prospect_gate)
			return {"ok": true}
		"build_improvement":
			var owned: Dictionary = owned_land(model, unit, tile)
			if not bool(owned["ok"]):
				return owned
			var resource: int = model.resource_at(tile.x, tile.y)
			if resource == MapModel.NO_ID:
				return deny("Improvements need a tile with a resource.")
			if works.improvement_at(model, tile) >= LandWorks.MAX_IMPROVEMENT:
				return deny("This tile is already fully improved.")
			if (
				ImprovementCatalog.needs_prospecting(resource)
				and not works.is_prospected(unit.owner, model, tile)
			):
				return deny("An Explorer must prospect this tile before a mine can rise.")
			var commodity: String = ImprovementCatalog.commodity(resource)
			var tech_cap: int = ImprovementCatalog.tech_cap_for(commodity, tech_caps)
			if works.improvement_at(model, tile) + 1 > tech_cap:
				return deny(
					"Requires %s extraction tech (cap %d) to raise this estate."
					% [ImprovementCatalog.commodity_label(commodity), tech_cap]
				)
			var terrain_cap: int = TerrainCaps.hard_cap(
				model.terrain_at(tile.x, tile.y), commodity
			)
			if works.improvement_at(model, tile) + 1 > terrain_cap:
				return deny("Terrain caps %s extraction at level %d here."
					% [ImprovementCatalog.commodity_label(commodity), terrain_cap])
			return CivilianTransport.exclusive(units, unit, tile)
		"upgrade_town":
			var held_town: Dictionary = owned_land(model, unit, tile)
			if not bool(held_town["ok"]):
				return held_town
			var town_data: ProvinceState = model.province_data(province)
			if town_data == null or not town_data.is_town_tile(tile):
				return deny("Towns are upgraded on the province's town tile.")
			var gate: String = CivilianWorkRefusals.town_upgrade(town_data, tech_unlocked)
			if not gate.is_empty():
				return deny(gate)
			return CivilianTransport.exclusive(units, unit, tile)
		"build_fort":
			var held: Dictionary = owned_land(model, unit, tile)
			if not bool(held["ok"]):
				return held
			var wall_gate: String = CivilianWorkRefusals.fort(
				FortRules.level_at(model, province), tech_unlocked
			)
			if not wall_gate.is_empty():
				return deny(wall_gate)
			# Two projects in one province may run; the later completion cannot
			# leap a level (wiki: siege-mechanics § Fort Levels), so the town
			# tile is not exclusive the way an estate tile is.
			return {"ok": true}
		"build_hospital":
			return HospitalRules.work_check(model, unit, tile, province, tech_unlocked)
		"build_road", "build_port", "build_rail":
			return CivilianTransport.check(
				model, unit, action, tile, works, units, tech_unlocked
			)
		"purchase_land":
			return LandPurchase.check(model, unit, tile, works, units, context)
		"counter_spy":
			# Empire-wide screen: the target is any owned province, and one spy
			# anywhere covers every province (wiki: civilian-units § Spy).
			if model.province_owner(province) != unit.owner:
				return deny("Counter-espionage is kept in your own provinces.")
			return {"ok": true}
	return deny("The %s has no such work order." % unit.display_name())


static func owned_land(model: MapModel, unit: CivilianState, tile: Vector2i) -> Dictionary:
	if model.owner_at(tile.x, tile.y) != unit.owner:
		return deny("This land is not held by your crown.")
	return {"ok": true}
