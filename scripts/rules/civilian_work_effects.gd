class_name CivilianWorkEffects
extends RefCounted
## Completion effects for civilian work orders (wiki: civilian-units § Work
## Types, fog-and-exploration, extraction-and-improvements, siege-mechanics
## § Fort Levels). Pure rules: CivilianWork.resolve_turn advances the clock;
## this module writes the tile and province changes (REQ-P3-01, REQ-P3-03).


## Apply one finished order. Returns tile indices the view should refresh;
## may annotate `report` with fort / purchase outcomes.
static func apply(
	model: MapModel,
	unit: CivilianState,
	action: String,
	tile: Vector2i,
	works: LandWorks,
	visibility: VisibilityModel,
	economy: PlayerEconomy = null,
	report: Dictionary = {}
) -> Array:
	var province: int = model.province_at(tile.x, tile.y)
	match action:
		"explore":
			if visibility != null:
				return visibility.reveal_province(province)
			return []
		"prospect":
			works.set_prospected(unit.owner, model, tile)
			return [model.index_of(tile.x, tile.y)]
		"build_improvement":
			works.set_improvement(model, tile, works.improvement_at(model, tile) + 1)
			return [model.index_of(tile.x, tile.y)]
		"upgrade_town":
			var town_data: ProvinceState = model.province_data(province)
			if town_data != null:
				town_data.town_development = CivilianWorkPlan.town_after_upgrade(
					town_data.town_development, int(unit.work_detail("town_level"))
				)
			return [model.index_of(tile.x, tile.y)]
		"build_fort":
			# The level it found and the level it raised: a duplicate project
			# finishing after the wall stands reports no raise (wiki § Fort Levels).
			var fort_before: int = FortRules.level_at(model, province)
			FortRules.apply_build(
				model.province_data(province), unit.work_detail("fort_level")
			)
			report["fort_before"] = fort_before
			report["fort_level"] = FortRules.level_at(model, province)
			return [model.index_of(tile.x, tile.y)]
		"build_hospital":
			return HospitalRules.work_complete(model, province, unit, tile)
		"purchase_land":
			# `complete` records the town level it actually set (DR-20261112-01).
			if LandPurchase.complete(model, tile, unit.owner, economy, report):
				return [model.index_of(tile.x, tile.y)]
			return []
	if CivilianTransport.knows(action):
		return CivilianTransport.apply(model, action, tile, works)
	return []
