class_name TownIndustry
extends RefCounted
## Town manufacturing bonus (wiki: extraction-and-improvements § Town
## manufacturing bonus). A developed town (level 2 or 4) turns town-connected
## raw extraction into manufactured goods during Extraction: no labour, no input
## consumption, no cargo. Pure maths; Extraction supplies the delivered raw.

## level -> output multiplier; levels 1 and 3 grant no bonus.
const MULTIPLIERS: Dictionary = {2: 1, 4: 2}
## Raw units needed per bonus output unit.
const INPUT_PER_OUTPUT: int = 4


static func multiplier(town_level: int) -> int:
	return int(MULTIPLIERS.get(town_level, 0))


## Bonus outputs for one province's delivered town-connected raw this turn.
static func bonus_for_province(
	raw: Dictionary, town_level: int, tech_unlocked: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {}
	var scale: int = multiplier(town_level)
	if scale <= 0 or raw.is_empty():
		return result
	for recipe_id: String in ProductionRecipes.available_ids(tech_unlocked):
		var needed: Dictionary = ProductionRecipes.inputs(recipe_id)
		if needed.is_empty():
			continue
		var limiting: int = 1 << 30
		var all_raw: bool = true
		for commodity: Variant in needed.keys():
			var id: String = String(commodity)
			if not CommodityCatalog.is_raw(id):
				all_raw = false
				break
			limiting = mini(limiting, int(raw.get(id, 0)))
		if not all_raw or limiting <= 0:
			continue
		var runs: int = int(limiting / INPUT_PER_OUTPUT)
		if runs <= 0:
			continue
		var output: String = ProductionRecipes.output(recipe_id)
		if output.is_empty():
			continue
		result[output] = int(result.get(output, 0)) + runs * scale
	return result
