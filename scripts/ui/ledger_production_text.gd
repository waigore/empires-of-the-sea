class_name LedgerProductionText
extends RefCounted
## Plain-text (and pure) formatting for the PRODUCTION tab: a recipe's title and
## tooltip and the next-turn figure beside a holding. No visual nodes, so it is
## cheap to unit test (REQ-P3-03).


## "Planks (Timber)" — output plus its single input when the recipe has one.
static func recipe_title(recipe_id: String) -> String:
	var text: String = CommodityCatalog.label(ProductionRecipes.output(recipe_id))
	var inputs: Dictionary = ProductionRecipes.inputs(recipe_id)
	if inputs.size() == 1:
		text += " (%s)" % CommodityCatalog.label(String(inputs.keys()[0]))
	return text


## "Timber ×2  +  Iron ×1  →  1 Planks  ·  4 labour". A multi-turn row names
## its wait: "· 2 turns per run" (wiki: production-recipes § Turns per unit).
static func recipe_tooltip(recipe_id: String) -> String:
	var parts: PackedStringArray = []
	var inputs: Dictionary = ProductionRecipes.inputs(recipe_id)
	for commodity: Variant in inputs.keys():
		parts.append("%s ×%d" % [CommodityCatalog.label(String(commodity)), int(inputs[commodity])])
	var text: String = "  +  ".join(parts) + "  →  1 %s  ·  %d labour" % [
		CommodityCatalog.label(ProductionRecipes.output(recipe_id)),
		ProductionRecipes.labour(recipe_id),
	]
	var turns: int = ProductionRecipes.turns(recipe_id)
	if turns > 1:
		text += "  ·  %d turns per run" % turns
	return text


## The next-turn figure beside a holding: "" when the phase leaves the store
## alone, so no row carries a column of "+0" (wiki: stockpiles-and-production
## § Production flow; REQ-P5-05).
static func stock_delta_text(delta: int) -> String:
	if delta == 0:
		return ""
	return "%+d" % delta
