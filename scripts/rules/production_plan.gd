class_name ProductionPlan
extends RefCounted
## One Great Power's production board: the next-phase assignment and the
## workshop batches still serving their turns (wiki: stockpiles-and-production;
## DR-20261112-11). Pure state — the turn resolver and the ledger read it, so
## the crown economy does not also own the plan (REQ-P3-01, REQ-P3-03).

## Desired output units for the next Production phase: array of
## {"recipe", "units"}.
var _assignments: Array[Dictionary] = []
## Workshop carried between turns: recipe id -> array of batches
## {"units", "turns_left"} still serving their turns. Inputs and labour were
## paid when each batch started; only the output is outstanding.
var wip: Dictionary = {}
## What the last Production phase turned out, recipe id -> whole units that left
## the workshop (wiki: production-recipes § Acceptance Criteria — the phase
## records which recipes ran and what each produced, `productionByRecipe`).
## Carried in the save, so the ledger still reads the last phase after a reload.
var made: Dictionary = {}


func copy() -> ProductionPlan:
	var clone := ProductionPlan.new()
	clone._assignments = _assignments.duplicate(true)
	clone.wip = wip.duplicate(true)
	clone.made = made.duplicate(true)
	return clone


# --- assignment --------------------------------------------------------------


func assignment_units(recipe_id: String) -> int:
	for entry: Dictionary in _assignments:
		if String(entry.get("recipe", "")) == recipe_id:
			return int(entry.get("units", 0))
	return 0


## Desired output units for the next Production phase; 0 or less clears the row.
func set_assignment(recipe_id: String, units: int) -> void:
	if not ProductionRecipes.known(recipe_id):
		return
	for index in _assignments.size():
		if String(_assignments[index].get("recipe", "")) == recipe_id:
			if units <= 0:
				_assignments.remove_at(index)
			else:
				_assignments[index] = {"recipe": recipe_id, "units": units}
			return
	if units > 0:
		_assignments.append({"recipe": recipe_id, "units": units})


func assignments() -> Array[Dictionary]:
	return _assignments.duplicate(true)


func clear_assignments() -> void:
	_assignments.clear()


func assigned_labour() -> int:
	var total: int = 0
	for entry: Dictionary in _assignments:
		var recipe_id: String = String(entry.get("recipe", ""))
		total += int(entry.get("units", 0)) * ProductionRecipes.labour(recipe_id)
	return total


func read_assignments(data: Variant) -> void:
	_assignments.clear()
	if typeof(data) != TYPE_ARRAY:
		return
	for raw: Variant in data:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var recipe_id: String = String(entry.get("recipe", ""))
		var units: int = int(entry.get("units", 0))
		if not recipe_id.is_empty() and units > 0:
			_assignments.append({"recipe": recipe_id, "units": units})


# --- workshop ----------------------------------------------------------------


## Units of this recipe started on an earlier turn whose output has not landed.
func wip_units(recipe_id: String) -> int:
	return ProductionWorkshop.units(wip, recipe_id)


## Phases until the next unit of this recipe lands; 0 when the workshop is idle.
func wip_turns(recipe_id: String) -> int:
	return ProductionWorkshop.soonest(wip, recipe_id)


func wip_total() -> int:
	var total: int = 0
	for recipe_id: Variant in wip.keys():
		total += ProductionWorkshop.units(wip, String(recipe_id))
	return total


## The workshop a save carries; a recipe the catalogue no longer knows, a batch
## with no units, or a batch already served is dropped rather than trusted. The
## row itself is read through the catalogue's batch reader, so a damaged save
## (a row that is not a list, an entry that is not a batch) drops instead of
## aborting the load (wiki: production-recipes § Acceptance Criteria).
func read_wip(data: Variant) -> void:
	wip = {}
	if typeof(data) != TYPE_DICTIONARY:
		return
	var stored: Dictionary = data
	for raw_recipe: Variant in stored.keys():
		var recipe_id: String = String(raw_recipe)
		if not ProductionRecipes.known(recipe_id):
			continue
		var batches: Array[Dictionary] = ProductionWorkshop.batches(stored, recipe_id)
		if not batches.is_empty():
			wip[recipe_id] = batches


func snapshot() -> Dictionary:
	return {
		"assignments": _assignments.duplicate(true),
		"production_wip": wip.duplicate(true),
		"production_made": made.duplicate(true),
	}


# --- last phase ---------------------------------------------------------------


## Whole units this recipe turned out in the last Production phase; 0 for a row
## that did not run. A multi-turn batch pays in the phase its unit lands, so this
## reads the landings, not the runs started (wiki: production-recipes
## § Acceptance Criteria; DR-20261113-02).
func made_units(recipe_id: String) -> int:
	return maxi(int(made.get(recipe_id, 0)), 0)


## Everything the workshop turned out in the last phase, whole units.
func made_total() -> int:
	var total: int = 0
	for recipe_id: Variant in made.keys():
		total += maxi(int(made[recipe_id]), 0)
	return total


## Records one Production phase's landings (`ProductionRecipes.plan`'s
## `completed`). Unknown recipes and non-positive counts are dropped, so the
## record is always something the ledger can name.
func set_made(completed: Variant) -> void:
	made = {}
	if typeof(completed) != TYPE_DICTIONARY:
		return
	var counts: Dictionary = completed
	for raw_recipe: Variant in counts.keys():
		var recipe_id: String = String(raw_recipe)
		var raw: Variant = counts[raw_recipe]
		if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
			continue
		var units: int = int(raw)
		if units > 0 and ProductionRecipes.known(recipe_id):
			made[recipe_id] = units


## The last phase's record as a save carries it: a damaged row (unknown recipe, a
## count that is not a number) drops instead of aborting the load, the way the
## workshop's batches do (wiki: production-recipes § Acceptance Criteria).
func read_made(data: Variant) -> void:
	set_made(data)
