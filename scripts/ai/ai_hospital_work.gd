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
## `context["larder_slack"]` — the grain the court's own harvest leaves after
## every mouth it already feeds — prices a ward against the larder that must
## carry it: a ward is a permanent `HospitalRules.RATION_PER_LEVEL` mouth, so a
## court whose slack is under that raises no ward, or it strikes itself into the
## famine its own works made (issue #807, evidence/issue-766). A caller that
## does not know the larder passes no key and keeps the old reading.
static func best_candidate(query: AiWorkQuery) -> Dictionary:
	var best: Dictionary = {}
	if query.config == null or query.model == null or query.unit == null:
		return best
	if query.works == null:
		return best
	# The larder gate: a ward is a permanent two-food mouth, so a court whose
	# harvest leaves less than one ward's ration after every mouth it feeds
	# raises none (issue #807).
	if query.context.has("larder_slack"):
		var slack: int = int(query.context["larder_slack"])
		if slack < HospitalRules.RATION_PER_LEVEL:
			return best
	var weight: int = query.config.parameter("civilian.hospital_weight")
	for province: ProvinceState in query.model.provinces:
		if province.owner != query.unit.owner or not province.has_town():
			continue
		if HospitalRules.level_at(query.model, province.id) >= HospitalRules.MAX_LEVEL:
			continue
		var tile: Vector2i = HospitalRules.site_tile(query.model, province.id)
		if tile.x < 0 or query.reserved.has(tile):
			continue
		var score: int = weight
		if query.at_war():
			score += 25
		if province.capital:
			score += 15
		score += province.town_level() * 5
		var candidate: Dictionary = AiCivilianCandidate.make(
			query, "build_hospital", tile, score
		)
		best = AiCivilianCandidate.better(best, candidate)
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
