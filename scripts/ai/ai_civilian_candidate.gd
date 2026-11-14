class_name AiCivilianCandidate
extends RefCounted
## Shared candidate gate for the rival civilian planners: every order they
## consider runs the same CivilianWork validation the player's dossier uses, so
## a planner can never invent an outcome or spend a commodity twice
## (REQ-P2-03, REQ-P3-03). Pure rules: state in, candidate out.
##
## Ranking lives here too: every work module orders its candidates with
## [method better], so one tie-break rule keeps two closures over one tile
## deterministic and identical across the planners.


## Higher score wins; a tie goes to the earlier tile in row-major order, then to
## the earlier action name, so the same state always produces the same order and
## two plans that score alike never depend on evaluation order.
static func better(best: Dictionary, candidate: Dictionary) -> Dictionary:
	if candidate.is_empty():
		return best
	if best.is_empty():
		return candidate
	if int(candidate["score"]) != int(best["score"]):
		return candidate if int(candidate["score"]) > int(best["score"]) else best
	var first: Vector2i = rank_tile(candidate)
	var held: Vector2i = rank_tile(best)
	if first.y != held.y:
		return candidate if first.y < held.y else best
	if first.x != held.x:
		return candidate if first.x < held.x else best
	return candidate if String(candidate["action"]) < String(best["action"]) else best


## The tile a closure is ranked on: the work site, else the target, else the
## unit's stand. Scorers that decide somewhere other than where they stand
## (a colony for a `sail`, a charter for a trade) rank by that site.
static func rank_tile(row: Dictionary) -> Vector2i:
	for key: String in ["tile", "target"]:
		var at: Variant = row.get(key, null)
		if at is Vector2i and (at as Vector2i).x >= 0:
			return at
	if row.has("unit"):
		var unit: CivilianState = row["unit"] as CivilianState
		if unit != null:
			return unit.tile
	return CivilianState.NO_TILE


## Returns an order-shaped dictionary, or {} when the shared rules refuse it.
## The court's own chart, when the caller puts one in `context["visibility"]`,
## gates the order exactly as the player's dossier is gated (DR-20261110-21).
## The order names the caller's `tile`; when `target` is given the rules check
## that site instead, for work the court names somewhere other than where it may
## stand.
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
	score: int,
	target: Vector2i = CivilianState.NO_TILE
) -> Dictionary:
	var roster: Array[CivilianState] = []
	roster.assign(units)
	var view: VisibilityModel = context.get("visibility", null)
	var site: Vector2i = tile if target.x < 0 else target
	var check: Dictionary = CivilianWork.validate(
		model, unit, action, works, roster, stockpile, view, site, tech_caps,
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


## The better of two candidates under one shared ranking: higher score wins;
## row-major tile order then action name break ties, so the same state always
## makes the same order. Every civilian planner ranks through here.
static func better(best: Dictionary, candidate: Dictionary) -> Dictionary:
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
