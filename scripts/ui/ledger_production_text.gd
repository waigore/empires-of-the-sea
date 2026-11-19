class_name LedgerProductionText
extends RefCounted
## Plain-text (and pure) formatting for the PRODUCTION tab: a recipe's title and
## tooltip, the next-turn figure beside a holding, the gate a closed row names,
## and the MANUFACTURED heading's hint. No visual nodes, so it is cheap to unit
## test (REQ-P3-03).


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


## The court's available recipes for one good: fabric is woven from wool or —
## once Cotton Weaving is known — from cotton, and each weave is its own row. An
## ungated row reads first, so the always-available path sits at the top
## (wiki: production-recipes § Technology-gated recipes).
static func recipes_for_output(output_id: String, tech_unlocked: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for recipe_id: String in ProductionRecipes.available_ids(tech_unlocked):
		if ProductionRecipes.output(recipe_id) != output_id:
			continue
		if ProductionRecipes.required_tech(recipe_id).is_empty():
			out.insert(0, recipe_id)
			continue
		out.append(recipe_id)
	return out


## The hand a row waits for, said on the row itself: a touch player never sees a
## hover hint, so the gate is text, not a tooltip (wiki: production-recipes
## § Worker-tier gates; DR-20261114-07). A row that waits on the town's works
## names that first: the town is the outer gate (DR-20261116-04).
static func gate_note(recipe_id: String, town_level: int) -> String:
	var town: int = ProductionRecipes.min_town(recipe_id)
	if town > 0 and not ProductionRecipes.town_met(recipe_id, town_level):
		return "needs a level-%d town" % town
	var tier: int = ProductionRecipes.min_tier(recipe_id)
	if tier <= 0:
		return ""
	var hand: String = WorkerPool.TIER_ONE[tier]
	var article: String = "an" if hand.begins_with("A") else "a"
	return "needs %s %s" % [article, hand]


## What the gate asks and where the court trains it.
static func gate_tooltip(recipe_id: String, town_level: int) -> String:
	var town: int = ProductionRecipes.min_town(recipe_id)
	if town > 0 and not ProductionRecipes.town_met(recipe_id, town_level):
		return (
			"This row is the town's own work: it needs a town at level %d. "
			+ "Raise one in the TOWNS sheet and the workshop will take it."
		) % town
	var tier: int = ProductionRecipes.min_tier(recipe_id)
	if tier <= 0:
		return ""
	var hand: String = WorkerPool.TIER_ONE[tier]
	var article: String = "an" if hand.begins_with("A") else "a"
	return (
		"This row is a trained hand's work: it needs %s %s. Train one in the "
		+ "WORKERS tab and the workshop will take it."
	) % [article, hand]


## The MANUFACTURED heading's hint, plus what the workshop turned out in the last
## Production phase: the phase's own record, so the page remembers the work the
## court just paid for (wiki: production-recipes § Acceptance Criteria,
## `productionByRecipe`).
static func manufacture_hint(made_total: int) -> String:
	var hint: String = "Set this turn's output on each row: labour and raw inputs cap the rest."
	if made_total <= 0:
		return hint
	var plural: String = MoneyText.plural(made_total)
	return "%s Last phase the workshop made %d good%s." % [hint, made_total, plural]
