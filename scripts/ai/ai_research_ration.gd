class_name AiResearchRation
extends RefCounted
## The standing study's ration ladder (wiki: ai-architecture § Research planner;
## issue #1059). A banked court keeps the ration-estate cap study — the cheapest
## unfinished grain/meat cap it already holds — on the standing slot, so the
## farms outgrow the army's mouths behind the chest. Pure rules: the state moves
## its own rows, the planner funds them (REQ-P3-01, REQ-P3-03).

## The army's mouths' commodities: the ration-estate caps.
const RATION_COMMODITIES: Array[String] = ["grain", "meat"]


## Move the cheapest unfinished ration-cap study onto the standing slot. A
## study already on it stays; one still below its ceiling and on another slot
## swaps places with the standing row.
static func keep(state: ResearchState, economy: PlayerEconomy, standing: int) -> void:
	if state == null or economy == null:
		return
	for row: Dictionary in state.researching():
		var slot: int = int(row.get("slot", -1))
		if slot == standing or not _is_ration(String(row.get("tech", "")), economy):
			continue
		_swap(state, slot, standing)
		return


## True when the tech lifts a ration-estate cap this court has not reached yet.
static func _is_ration(tech_id: String, economy: PlayerEconomy) -> bool:
	var caps: Dictionary = TechCatalog.caps_of(tech_id)
	for raw: Variant in caps.keys():
		var commodity: String = String(raw)
		if not RATION_COMMODITIES.has(commodity):
			continue
		if TechCatalog.cap_for(commodity, economy.tech_unlocked) < int(caps[raw]):
			return true
	return false


## The row move through the state's public row API: the progress is read, then
## restored, so the swap cancels nothing.
static func _swap(state: ResearchState, from_slot: int, to_slot: int) -> void:
	var from_tech: String = state.tech_at(from_slot)
	var to_tech: String = state.tech_at(to_slot)
	if from_slot == to_slot or from_tech.is_empty() or to_tech.is_empty():
		return
	var from_funding: String = state.funding_at(from_slot)
	var to_funding: String = state.funding_at(to_slot)
	var from_progress: int = state.progress_of(from_tech)
	var to_progress: int = state.progress_of(to_tech)
	state.cancel(from_slot)
	state.cancel(to_slot)
	state.assign(from_tech, from_funding, to_slot)
	state.assign(to_tech, to_funding, from_slot)
	if from_progress > 0:
		state.add_progress(from_tech, from_progress)
	if to_progress > 0:
		state.add_progress(to_tech, to_progress)
