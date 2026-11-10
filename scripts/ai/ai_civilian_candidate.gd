class_name AiCivilianCandidate
extends RefCounted
## Shared candidate gate for the rival civilian planners: every order they
## consider runs the same CivilianWork validation the player's dossier uses, so
## a planner can never invent an outcome or spend a commodity twice
## (REQ-P2-03, REQ-P3-03). Pure rules: state in, candidate out.


## Returns an order-shaped dictionary, or {} when the shared rules refuse it.
## The court's own chart, when the caller puts one in `context["visibility"]`,
## gates the order exactly as the player's dossier is gated (DR-20261110-21).
static func make(
	model: MapModel,
	unit: CivilianState,
	action: String,
	tile: Vector2i,
	works: LandWorks,
	units: Array,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary,
	score: int
) -> Dictionary:
	var roster: Array[CivilianState] = []
	roster.assign(units)
	var view: VisibilityModel = context.get("visibility", null)
	var check: Dictionary = CivilianWork.validate(
		model, unit, action, works, roster, stockpile, view, tile, tech_caps,
		tech_unlocked, context
	)
	if not bool(check.get("ok", false)):
		return {}
	return {
		"action": action,
		"tile": tile,
		"score": score,
		"cost": check.get("cost", {}),
		"duration": int(check.get("duration", 1)),
	}
