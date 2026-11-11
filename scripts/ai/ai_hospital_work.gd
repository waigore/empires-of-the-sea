class_name AiHospitalWork
extends RefCounted
## Rival engineer policy for province hospitals (wiki: combat § Regiment
## condition; civilian-work-planner § Playable slice; DR-20261111-16).
##
## A hospital quickens the rest every army in its province takes and blunts the
## wear the province owner's battle leaves behind, so a court at war wants one
## where its armies come home: the seat first, then the best-developed town.
## Every candidate runs the same CivilianWork validation the player's dossier
## does, so the planner can never invent an outcome or spend a commodity twice
## (REQ-P2-03, REQ-P3-03). Pure rules: state in, candidate out.

## The hospital is a second legal work in a province that already hosts a fort
## project, so this scorer reads the province, never the town's occupancy.
static func best_candidate(
	config: AiConfig,
	model: MapModel,
	unit: CivilianState,
	units: Array,
	works: LandWorks,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary,
	reserved: Dictionary
) -> Dictionary:
	var best: Dictionary = {}
	if config == null or model == null or unit == null or works == null:
		return best
	var weight: int = config.parameter("civilian.hospital_weight")
	var at_war: bool = bool(context.get("at_war", false))
	for province: ProvinceState in model.provinces:
		if province.owner != unit.owner or not province.has_town():
			continue
		if HospitalRules.level_at(model, province.id) >= HospitalRules.MAX_LEVEL:
			continue
		var tile: Vector2i = HospitalRules.site_tile(model, province.id)
		if tile.x < 0 or reserved.has(tile):
			continue
		var score: int = weight
		if at_war:
			score += 25
		if province.capital:
			score += 15
		score += province.town_level() * 5
		var candidate: Dictionary = AiCivilianCandidate.make(
			model, unit, "build_hospital", tile, works, units, stockpile,
			tech_caps, tech_unlocked, context, score
		)
		best = _better(best, candidate)
	return best


## Whether this Engineer holds a war work while a province town still waits on
## its link. A fort is the court's own defence; at war a hospital is the tempo
## that keeps its armies in the field (DR-20261111-16). Both finish in a turn or
## two, then the sweep resumes.
static func holds_over_town_link(best: Dictionary, context: Dictionary) -> bool:
	var action: String = String(best.get("action", ""))
	if action == "build_fort":
		return true
	return action == "build_hospital" and bool(context.get("at_war", false))


## Higher score wins; row-major tile then action name break ties, matching the
## civilian planner's own ordering.
static func _better(best: Dictionary, candidate: Dictionary) -> Dictionary:
	if candidate.is_empty():
		return best
	if best.is_empty():
		return candidate
	if int(candidate["score"]) != int(best["score"]):
		return candidate if int(candidate["score"]) > int(best["score"]) else best
	var left: Vector2i = candidate["tile"]
	var right: Vector2i = best["tile"]
	if left.y != right.y:
		return candidate if left.y < right.y else best
	if left.x != right.x:
		return candidate if left.x < right.x else best
	return candidate if String(candidate["action"]) < String(best["action"]) else best
