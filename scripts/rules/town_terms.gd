class_name TownTerms
extends RefCounted
## What one town level buys, named where the crown signs for it: the manufacture
## bonus the Extraction phase pays a developed town, and the workshop rows that
## level's works open (wiki: extraction-and-improvements § Town manufacturing
## bonus; production-recipes § Town-works gates; civilian-units § Builder;
## DR-20261118-06). Pure reads of the bonus table and the recipe catalogue, so a
## surface can promise nothing the Extraction phase or the workshop would refuse
## (REQ-P2-03, REQ-P3-03).
##
## The bonus sits at levels 2 and 4 only: level 2 returns one manufacture for
## every four raw a province's own town-connected estates deliver, level 4
## returns two, and level 3 returns none — that step exists to reach the top
## level ([TownIndustry]). The row says so plainly, so no crown pays eight lumber
## and eight cast iron for a level that pays nothing of its own
## ([DR-20261115-12]'s sheet note states the rule once; this names it per step).

## The first level a Builder's order can land on: nothing raises a town to I.
const FIRST_STEP: int = 2


## What a finished step to `level` pays in the province that signs for it, in the
## ledgers' own shorthand: the manufacture bonus first, the works its level opens
## after. A level that pays no bonus says so. Empty for a level no order lands on,
## so a row never prices a step the rules refuse.
static func level_line(level: int) -> String:
	if level < FIRST_STEP or level > TownIndustry.MAX_LEVEL:
		return ""
	var scale: int = TownIndustry.multiplier(level)
	if scale <= 0:
		return "L%d pays no manufacture — it is the road to L%d" % [
			level, TownIndustry.MAX_LEVEL
		]
	var clauses: PackedStringArray = PackedStringArray()
	clauses.append("L%d pays %s" % [level, bonus_text(scale)])
	var works: String = works_text(level)
	if not works.is_empty():
		clauses.append(works)
	return " · ".join(clauses)


## "1 manufacture per 4 raw its own estates deliver" — the formula the Extraction
## phase applies, in the words a crown reads beside the price.
static func bonus_text(scale: int) -> String:
	return "%d manufacture%s per %d raw its own estates deliver" % [
		scale,
		MoneyText.plural(scale),
		TownIndustry.INPUT_PER_OUTPUT,
	]


## The workshop rows this level's works open, in the catalogue's own names. The
## gate is the crown's **best** town — a presence test, not this province's level
## — so the line names the level the works need instead of claiming this town is
## the one that opens them (wiki: production-recipes § Town-works gates). A row
## that also waits on a study is left to the ledger that sells it: a town never
## opens it alone.
static func works_text(level: int) -> String:
	var names: PackedStringArray = PackedStringArray()
	for recipe_id: String in ProductionRecipes.ids():
		if ProductionRecipes.min_town(recipe_id) != level:
			continue
		if not ProductionRecipes.required_tech(recipe_id).is_empty():
			continue
		var output: String = ProductionRecipes.output(recipe_id)
		if output.is_empty():
			continue
		names.append(CommodityCatalog.label(output))
	if names.is_empty():
		return ""
	return "the %s works need a level-%d town" % [join_and(names), level]


## The step the province under `tile` would take next, read off the work plan's
## own target level so the row and the order can never disagree about it. Empty
## where the ground carries no town to raise, or the town already stands at the
## top: those rows file no order, so they price nothing.
static func order_line(model: MapModel, tile: Vector2i) -> String:
	if model == null:
		return ""
	var province: ProvinceState = model.province_data(model.province_at(tile.x, tile.y))
	if province == null or not province.has_town():
		return ""
	if province.town_level() >= TownIndustry.MAX_LEVEL:
		return ""
	return level_line(CivilianWorkPlan.town_upgrade_level(model, tile))


## "Garments", "Garments and Rum" — a list of works read as one clause.
static func join_and(names: PackedStringArray) -> String:
	if names.is_empty():
		return ""
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return "%s and %s" % [names[0], names[1]]
	return "%s and %s" % [
		", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]
	]
