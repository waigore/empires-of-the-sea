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
## Town development tops out at 4 (wiki: civilian-units § Builder upgrade_town).
const MAX_LEVEL: int = 4


static func multiplier(town_level: int) -> int:
	return int(MULTIPLIERS.get(town_level, 0))


## Base-price worth of one turn's bonus output, so a court can weigh a town
## upgrade against an estate, a road or a market order on one scale.
static func value(bonus: Dictionary) -> int:
	var total: int = 0
	for raw: Variant in bonus.keys():
		total += int(bonus[raw]) * CommodityCatalog.base_price(String(raw))
	return total


## Per-turn worth of finishing this town: the bonus at level 4 less the bonus it
## already pays. A level-3 town pays nothing, so its gain is the whole level-4
## output; a fully developed town gains nothing. Zero when the raw is missing —
## an overseas province with no delivered cargo is worth no upgrade at all
## (wiki: extraction-and-improvements § Town manufacturing bonus).
static func marginal_gain(
	raw: Dictionary, town_level: int, tech_unlocked: Dictionary = {}
) -> int:
	if town_level >= MAX_LEVEL or raw.is_empty():
		return 0
	return (
		value(bonus_for_province(raw, MAX_LEVEL, tech_unlocked))
		- value(bonus_for_province(raw, town_level, tech_unlocked))
	)


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
