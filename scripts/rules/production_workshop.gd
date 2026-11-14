class_name ProductionWorkshop
extends RefCounted
## The batches a court has already paid for, waiting out their turns
## (wiki: production-recipes § Turns per unit; DR-20261112-11, DR-20261113-02).
##
## The recipe catalogue owns what a row costs and whether it may run; this owner
## only tracks the workshop: cleaning a save's batches, reading what is in
## flight, and serving the landings a Production phase pays. It knows nothing of
## recipes, so the catalogue and the ledger both read the same batch rules
## (REQ-P3-01, REQ-P3-03).


## One workshop row, cleaned: a batch with whole units and turns left, or {} when
## the value is not a batch at all. A hand-edited or damaged save is dropped,
## never trusted (wiki: production-recipes § Acceptance Criteria; DR-20261112-11).
static func clean_batch(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var units: int = int((raw as Dictionary).get("units", 0))
	var turns_left: int = int((raw as Dictionary).get("turns_left", 0))
	if units <= 0 or turns_left <= 0:
		return {}
	return {"units": units, "turns_left": turns_left}


## The batches a recipe's workshop entry holds. An entry of any other shape holds
## none, so the phase, the save and the ledger all read a malformed row as an
## empty workshop instead of failing on the cast.
static func batches(wip: Dictionary, recipe_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw_entry: Variant = wip.get(recipe_id, [])
	if typeof(raw_entry) != TYPE_ARRAY:
		return out
	for raw: Variant in (raw_entry as Array):
		var cleaned: Dictionary = clean_batch(raw)
		if not cleaned.is_empty():
			out.append(cleaned)
	return out


## Units of this recipe still in the workshop: started on an earlier turn, their
## output not landed yet (DR-20261112-11).
static func units(wip: Dictionary, recipe_id: String) -> int:
	var total: int = 0
	for cleaned: Dictionary in batches(wip, recipe_id):
		total += int(cleaned["units"])
	return total


## Phases until the next unit of this recipe lands; 0 when the workshop is idle.
## The soonest batch speaks for the row: a later batch cannot delay the unit that
## is already one phase from the store (DR-20261113-02's "the next landing").
static func soonest(wip: Dictionary, recipe_id: String) -> int:
	var all: Array[Dictionary] = batches(wip, recipe_id)
	if all.is_empty():
		return 0
	var soonest_turns: int = int(all[0]["turns_left"])
	for cleaned: Dictionary in all:
		soonest_turns = mini(soonest_turns, int(cleaned["turns_left"]))
	return soonest_turns


## Units one batch of this row lands in a Production phase: a multi-turn batch
## lands **one** and keeps the rest for the phases after it; a one-turn row never
## waits, so a carried batch of it (only a damaged or hand-edited save can hold
## one) lands whole (wiki: production-recipes § Turns per unit; DR-20261113-02).
static func landing(units_in_batch: int, turns_per_run: int) -> int:
	if turns_per_run <= 1:
		return maxi(units_in_batch, 0)
	return mini(1, maxi(units_in_batch, 0))


## Units that leave the workshop in the next Production phase: one per batch
## whose turns are served, so a court that left the row set and has two batches
## on the anvil lands two a phase. The row's reading uses this so the note never
## promises fewer landings than the phase pays (wiki: production-recipes
## § Turns per unit; DR-20261113-02).
static func ready_units(wip: Dictionary, recipe_id: String, turns_per_run: int) -> int:
	var total: int = 0
	for cleaned: Dictionary in batches(wip, recipe_id):
		if int(cleaned["turns_left"]) > 1:
			continue
		total += landing(int(cleaned["units"]), turns_per_run)
	return total


## Serves one Production phase for a recipe: every batch spends a turn, and the
## ones whose turns are done land. Returns {"landed": units, "kept": batches} so
## the caller owns the stockpile and output accounting while this owner keeps the
## batch rules in one place (DR-20261113-02).
static func serve(wip: Dictionary, recipe_id: String, turns_per_run: int) -> Dictionary:
	var landed: int = 0
	var kept: Array[Dictionary] = []
	for carried: Dictionary in batches(wip, recipe_id):
		var units_in_batch: int = int(carried["units"])
		var turns_left: int = int(carried["turns_left"]) - 1
		if turns_left > 0:
			kept.append({"units": units_in_batch, "turns_left": turns_left})
			continue
		var landing_units: int = landing(units_in_batch, turns_per_run)
		landed += landing_units
		if units_in_batch > landing_units:
			kept.append({"units": units_in_batch - landing_units, "turns_left": 1})
	return {"landed": landed, "kept": kept}
