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
## stand. The reading itself — crew, roster, works, stores, studies, docket and
## claims — arrives as one [AiWorkQuery].
static func make(
	query: AiWorkQuery,
	action: String,
	tile: Vector2i,
	score: int,
	target: Vector2i = CivilianState.NO_TILE
) -> Dictionary:
	var site: Vector2i = tile if target.x < 0 else target
	var check: Dictionary = CivilianWork.validate(
		query.model, query.unit, action, query.works, query.roster(),
		query.stockpile, query.view(), site, query.tech_caps,
		query.tech_unlocked, query.context
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
