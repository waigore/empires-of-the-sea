class_name ProductionRecipes
extends RefCounted
## Production recipe catalog (wiki: production-recipes). Each run consumes whole
## input units from the post-consumption stockpile and labour from idle workers,
## then adds its output. Runs are always whole; a recipe that cannot run once is
## skipped without partial consumption (REQ-P2-03).
##
## A run may occupy the workshop for more than one turn ("turns", default 1).
## Its inputs and labour are paid when it starts; the output lands after that
## many Production phases, seat counting as the first (DR-20261112-11). The two
## alloys combine two inputs, and a cigar ages while a fur hat cures, so the
## alloy and luxury rows are the catalogue's two-turn work (DR-20261114-10).
##
## A batch then lands **one unit a phase** rather than all at once: a batch of
## three steel started in turn 1 delivers one in turn 2, the last in turn 4
## (wiki: production-recipes § Turns per unit; DR-20261113-02). Drip-feeding the
## same runs phase by phase builds the same output from the same inputs, so a
## batch buys no front-loading and no larger order is punished beyond its wait.
##
## A row may also need a **trained hand**: `min_tier` names the lowest worker
## tier whose presence opens it (a higher tier satisfies it), checked wherever a
## row is offered or run — the phase, the ledger's ceiling and the AI's
## candidates (wiki: production-recipes § Worker-tier gates; DR-20261114-07).
##
## A slow row's bench holds **three pieces**: a fourth run of the same row waits
## for a landing, so a court cannot pay ten turns of inputs ahead (wiki:
## production-recipes § Workshop queue; DR-20261114-12).
##
## A row may also need the **town's works**: `min_town` names the lowest town
## level whose presence opens it, read as the crown's best town in any province
## — a presence test like the hand gate, not a per-province count (wiki:
## production-recipes § Town-works gates; DR-20261116-04). The two second-stage
## rows are the catalogue's own: garments from fabric and rum from refined
## sugar, both two-turn work.
##
## The catalogue owns the rows and their gates; `ProductionPhase` runs the phase
## plan, and the batches a court has already paid for are read and served by
## `ProductionWorkshop`.

## Fabric has two interchangeable raw inputs; the cotton row is tech-gated.
const RECIPES: Dictionary = {
	"lumber": {"output": "lumber", "inputs": {"timber": 2}, "labour": 2},
	"fabric_from_wool": {"output": "fabric", "inputs": {"wool": 2}, "labour": 2},
	"fabric_from_cotton":
	{
		"output": "fabric",
		"inputs": {"cotton": 2},
		"labour": 2,
		"requires": "cotton_weaving",
	},
	"castIron": {"output": "castIron", "inputs": {"iron": 2}, "labour": 2},
	"refinedSugar": {"output": "refinedSugar", "inputs": {"sugarCane": 2}, "labour": 2},
	"cigars": {"output": "cigars", "inputs": {"tobacco": 2}, "labour": 2, "min_tier": 1, "turns": 2},
	"furHats": {"output": "furHats", "inputs": {"furs": 2}, "labour": 2, "min_tier": 2, "turns": 2},
	"steel":
	{
		"output": "steel",
		"inputs": {"iron": 1, "coal": 1},
		"labour": 2,
		"turns": 2,
	},
	"paper": {"output": "paper", "inputs": {"timber": 2}, "labour": 2},
	"bronze":
	{
		"output": "bronze",
		"inputs": {"copper": 1, "tin": 1},
		"labour": 3,
		"turns": 2,
	},
	"garments":
	{
		"output": "garments",
		"inputs": {"fabric": 2},
		"labour": 2,
		"turns": 2,
		"min_town": 2,
	},
	"rum":
	{
		"output": "rum",
		"inputs": {"refinedSugar": 2},
		"labour": 2,
		"turns": 2,
		"min_town": 4,
	},
}

const OUTPUT_PER_RUN: int = 1


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in RECIPES.keys():
		out.append(String(id))
	out.sort()
	return out


static func known(recipe_id: String) -> bool:
	return RECIPES.has(recipe_id)


static func entry(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {})


static func output(recipe_id: String) -> String:
	return String(entry(recipe_id).get("output", ""))


static func inputs(recipe_id: String) -> Dictionary:
	return (entry(recipe_id).get("inputs", {}) as Dictionary).duplicate()


## The raw commodities one refinement hop from `commodity` (issue #995's bank).
static func raw_sources(commodity_id: String) -> Array[String]:
	var sources: Array[String] = []
	for recipe_id: String in ids():
		if output(recipe_id) != commodity_id:
			continue
		for raw: Variant in inputs(recipe_id).keys():
			var id: String = String(raw)
			if not sources.has(id):
				sources.append(id)
	return sources


static func labour(recipe_id: String) -> int:
	return int(entry(recipe_id).get("labour", 0))


static func required_tech(recipe_id: String) -> String:
	return String(entry(recipe_id).get("requires", ""))


## The lowest worker tier whose presence opens the row; 0 when any hand may run
## it (wiki: production-recipes § Worker-tier gates; DR-20261114-07).
static func min_tier(recipe_id: String) -> int:
	return int(entry(recipe_id).get("min_tier", 0))


## True when the court's pool holds a worker at or above the row's gate. A gate
## is a presence test, not a headcount: one master satisfies a journeyman row,
## and a court with no pool at all (a projection without workers) fails closed.
static func tier_met(recipe_id: String, workers: WorkerPool) -> bool:
	var need: int = min_tier(recipe_id)
	if need <= 0:
		return true
	if workers == null:
		return false
	for tier: int in range(need, WorkerPool.TIER_COUNT):
		if workers.count(tier) > 0:
			return true
	return false


## The lowest town level whose works open the row; 0 when any town may run it
## (wiki: production-recipes § Town-works gates; DR-20261116-04).
static func min_town(recipe_id: String) -> int:
	return int(entry(recipe_id).get("min_town", 0))


## True when the crown owns a town at or above the row's works gate. The reading
## is the crown's best town in any province — a presence test like the hand gate,
## so a court with no town at all (a projection without a world) fails closed.
static func town_met(recipe_id: String, town_level: int) -> bool:
	var need: int = min_town(recipe_id)
	return need <= 0 or town_level >= need


## Both gates a row declares plus the town's works: the study, the hand and the
## town the crown's best town stands at.
static func available_for(
	recipe_id: String,
	tech_unlocked: Dictionary,
	workers: WorkerPool,
	town_level: int = 0
) -> bool:
	return (
		available(recipe_id, tech_unlocked)
		and tier_met(recipe_id, workers)
		and town_met(recipe_id, town_level)
	)


## Rows a court may actually run: tech, hand and town's works all open
## (REQ-P2-03).
static func available_ids_for(
	tech_unlocked: Dictionary, workers: WorkerPool, town_level: int = 0
) -> Array[String]:
	var out: Array[String] = []
	for recipe_id: String in ids():
		if available_for(recipe_id, tech_unlocked, workers, town_level):
			out.append(recipe_id)
	return out


## Turns one run occupies the workshop before its output lands; 1 unless the
## row declares more (wiki: production-recipes § Turns per unit).
static func turns(recipe_id: String) -> int:
	return maxi(int(entry(recipe_id).get("turns", 1)), 1)


## A recipe with no required technology is available to everyone; a gated recipe
## only to players whose tech set holds it (wiki: production-recipes § tech gates).
static func available(recipe_id: String, tech_unlocked: Dictionary) -> bool:
	if not known(recipe_id):
		return false
	var tech: String = required_tech(recipe_id)
	return tech.is_empty() or bool(tech_unlocked.get(tech, false))


static func available_ids(tech_unlocked: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for recipe_id: String in ids():
		if available(recipe_id, tech_unlocked):
			out.append(recipe_id)
	return out
