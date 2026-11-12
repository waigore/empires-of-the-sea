class_name ResearchState
extends RefCounted
## One Great Power's research: slots, funding, progress and unlocked techs
## (wiki: research-state § Model, tech-tree § Research Model). Pure state — the
## research phase, the extraction caps and the research ledger read it, so no
## screen keeps a second copy of "what is known" (REQ-P3-03).

const DEFAULT_SLOTS: int = 3
const UNIVERSITY_SLOTS: int = 4
const UNIVERSITY: String = "university"
const EMPTY_TECH: String = ""

## Tech id -> true once researched (wiki: research-state § techUnlocked).
var unlocked: Dictionary = {}
## Tech id -> RP accumulated; keys are the techs currently in research.
var progress: Dictionary = {}
## Slot index -> {tech, funding}. An empty tech id means a free slot.
var slots: Array[Dictionary] = []
## Commodity id -> true for resources this player has revealed (and, for
## prospect-only minerals, prospected); discovery techs need one of these.
var revealed: Dictionary = {}
## The college ledger's goal: a catalog tech id the queue sorts toward, or ""
## for catalog order. Client state — the Research phase never reads it — kept in
## the snapshot so a load reopens the same queue (wiki: tech-tree § Goal slot;
## DR-20261111-21).
var goal: String = ""


static func make() -> ResearchState:
	var state := ResearchState.new()
	state.ensure_slots()
	return state


# --- slots -------------------------------------------------------------------


func slot_count() -> int:
	if is_unlocked(UNIVERSITY):
		return UNIVERSITY_SLOTS
	return DEFAULT_SLOTS


## Grows the roster to the current slot count; never shrinks, so a slot that is
## already researching is not silently forfeited.
func ensure_slots() -> void:
	while slots.size() < slot_count():
		slots.append({"tech": EMPTY_TECH, "funding": ResearchFunding.DEFAULT})


func tech_at(slot: int) -> String:
	if slot < 0 or slot >= slots.size():
		return EMPTY_TECH
	return String(slots[slot].get("tech", EMPTY_TECH))


func funding_at(slot: int) -> String:
	if slot < 0 or slot >= slots.size():
		return "none"
	return String(slots[slot].get("funding", ResearchFunding.DEFAULT))


func slot_of(tech_id: String) -> int:
	for index in slots.size():
		if tech_at(index) == tech_id:
			return index
	return -1


func is_active(tech_id: String) -> bool:
	return slot_of(tech_id) >= 0


func free_slot() -> int:
	ensure_slots()
	for index in slots.size():
		if tech_at(index).is_empty():
			return index
	return -1


## Puts a tech in a slot (wiki: research-state § Slot Occupancy Persistence).
func assign(tech_id: String, funding: String = ResearchFunding.DEFAULT, slot: int = -1) -> Dictionary:
	ensure_slots()
	if not TechCatalog.known(tech_id):
		return _no("Unknown technology.")
	if is_unlocked(tech_id):
		return _no("%s is already known." % TechCatalog.display_name(tech_id))
	if is_active(tech_id):
		return _no("%s already holds a research slot." % TechCatalog.display_name(tech_id))
	if not prerequisites_met(tech_id):
		return _no("Its prerequisites are not yet known.")
	if not discovered(tech_id):
		return _no("An explorer must find the resource first.")
	var index: int = slot if slot >= 0 else free_slot()
	if index < 0 or index >= slots.size():
		return _no("All research slots are taken.")
	if not tech_at(index).is_empty():
		return _no("That slot is already occupied.")
	slots[index] = {
		"tech": tech_id,
		"funding": funding if ResearchFunding.known(funding) else ResearchFunding.DEFAULT,
	}
	if not progress.has(tech_id):
		progress[tech_id] = 0
	return {
		"ok": true,
		"reason": "",
		"message": "%s enters the scholars' study." % TechCatalog.display_name(tech_id),
	}


## Cancelling a slot forfeits its progress (wiki: tech-tree § Research Model).
func cancel(slot: int) -> Dictionary:
	if slot < 0 or slot >= slots.size() or tech_at(slot).is_empty():
		return _no("That slot is already free.")
	var tech_id: String = tech_at(slot)
	slots[slot] = {"tech": EMPTY_TECH, "funding": ResearchFunding.DEFAULT}
	progress.erase(tech_id)
	return {
		"ok": true,
		"reason": "",
		"message": "%s is abandoned; its progress is lost." % TechCatalog.display_name(tech_id),
	}


func set_funding(slot: int, funding: String) -> bool:
	if slot < 0 or slot >= slots.size() or tech_at(slot).is_empty():
		return false
	if not ResearchFunding.known(funding):
		return false
	slots[slot]["funding"] = funding
	return true


func cycle_funding(slot: int) -> String:
	var next: String = ResearchFunding.next(funding_at(slot))
	set_funding(slot, next)
	return next


# --- knowledge ---------------------------------------------------------------


func is_unlocked(tech_id: String) -> bool:
	return bool(unlocked.get(tech_id, false))


func unlock(tech_id: String) -> void:
	unlocked[tech_id] = true
	progress.erase(tech_id)
	var slot: int = slot_of(tech_id)
	if slot >= 0:
		slots[slot] = {"tech": EMPTY_TECH, "funding": ResearchFunding.DEFAULT}
	ensure_slots()


func unlocked_ids() -> Array[String]:
	var out: Array[String] = []
	for tech_id: Variant in unlocked.keys():
		out.append(String(tech_id))
	out.sort()
	return out


func progress_of(tech_id: String) -> int:
	return int(progress.get(tech_id, 0))


func add_progress(tech_id: String, amount: int) -> int:
	var total: int = progress_of(tech_id) + maxi(amount, 0)
	progress[tech_id] = total
	return total


func prerequisites_met(tech_id: String) -> bool:
	for prereq: String in TechCatalog.prerequisites(tech_id):
		if not is_unlocked(prereq):
			return false
	return true


func discovered(tech_id: String) -> bool:
	var resources: Array[String] = TechCatalog.discovery_resources(tech_id)
	if resources.is_empty():
		return true
	for commodity: String in resources:
		if bool(revealed.get(commodity, false)):
			return true
	return false


## Techs whose prerequisites are known and whose discovery gate is open
## (wiki: tech-tree — derived, never stored).
func researchable() -> Array[String]:
	var out: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		if is_unlocked(tech_id):
			continue
		if prerequisites_met(tech_id) and discovered(tech_id):
			out.append(tech_id)
	return out


## Rows for the research ledger: one per occupied slot.
func researching() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index in slots.size():
		var tech_id: String = tech_at(index)
		if tech_id.is_empty():
			continue
		rows.append({
			"slot": index,
			"tech": tech_id,
			"name": TechCatalog.display_name(tech_id),
			"funding": funding_at(index),
			"progress": progress_of(tech_id),
			"cost": TechCatalog.cost(tech_id),
		})
	return rows


func set_revealed(resources: Dictionary) -> void:
	revealed = resources.duplicate()


func treasury_floor() -> int:
	return ResearchFunding.floor_for(unlocked)


func copy() -> ResearchState:
	var clone := ResearchState.new()
	clone.unlocked = unlocked.duplicate()
	clone.progress = progress.duplicate()
	clone.slots = slots.duplicate(true)
	clone.revealed = revealed.duplicate()
	clone.goal = goal
	return clone


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": reason}

