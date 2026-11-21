class_name MapPlayEstatesPick
extends RefCounted
## The estates the court's own Builder pass would raise this phase, named on the
## estates ledger before the crown presses a row (wiki:
## extraction-and-improvements § Estates ledger; civilian-build-planner
## § Architecture; DR-20261121-10).
##
## The reading is not a second opinion: it is `MapPlayCivilianPick.picks` — the
## same pass the crew's own sheet and the chart's mark read — narrowed to the
## estates it would raise, so the ledger cannot name a raise the pass would not
## book (REQ-P2-03, REQ-P3-03).
##
## A reading only: nothing here dispatches a Builder, spends a material or
## reserves a tile, and the crown still presses her own rows (REQ-P5-06).

## The plan raises at least one estate: the phase would put a Builder on it.
const KIND_RAISE: String = "raise"
## No estate is raised because no Builder stands idle to raise one.
const KIND_NO_BUILDER: String = "no_builder"

## The action a Builder's estate raise carries (`CivilianWork`).
const ACTION_ESTATE: String = "build_improvement"

## The most estates one line names before it counts the rest, so a handset's
## reading stays one line of chrome (REQ-P5-07).
const NAMED_LIMIT: int = 3

const NO_BUILDER_LINE: String = (
	"the court would raise no estate this phase — no Builder stands idle"
)

## The sheet's sentence: the pick's own clause, capitalised and closed — the
## same one wording every pick surface prints (REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession, snapshot: Dictionary = {}) -> String:
	return MapPlayPickProse.sentence_of(pick(play, snapshot))

## The ledger's pick as the estates sheet prints it: `{kind, estates, line}`,
## where each estate is `{tile, name, place}`. Empty when the session runs no
## planner for the crown, an observer session, a decided campaign, a crown with
## no ledger or a session with no civilian layer.
static func pick(play: PlaySession, snapshot: Dictionary = {}) -> Dictionary:
	if not MapPlayPickProse.crown_crew_ready(play):
		return {}
	var faction: int = play.player_faction
	return of(_estates(play, faction), snapshot)

## The estate picks the pass books, in the pass's own order: the raise each
## Builder would take, named by the catalogue and the province it stands in.
static func _estates(play: PlaySession, faction: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var picks: Dictionary = MapPlayCivilianPick.picks(play, faction)
	for raw: Variant in picks.values():
		var pick: Dictionary = raw
		if String(pick.get("action", "")) != ACTION_ESTATE:
			continue
		var tile: Variant = pick.get("tile", CivilianState.NO_TILE)
		if not (tile is Vector2i) or (tile as Vector2i).x < 0:
			continue
		var model: MapModel = play.world.region(int(pick.get("region", -1)))
		if model == null:
			continue
		found.append(_estate(model, tile as Vector2i))
	return found

## One estate's own words: the catalogue's name and the province it stands in,
## so two lumber camps in two provinces read apart.
static func _estate(model: MapModel, tile: Vector2i) -> Dictionary:
	var name: String = MapPlayCivilianPickWords.lower_first(
		ImprovementCatalog.base_name(model.resource_at(tile.x, tile.y))
	)
	var province: int = model.province_at(tile.x, tile.y)
	return {
		"tile": tile,
		"name": name,
		"place": MapPlayCivilianPickWords.place(model, province),
	}

## The pick, worded off the estate list and the ledger's own snapshot: the
## estates in the order the sheet prints its rows, or the gate that leaves the
## page with nothing to name. Pure — a sheet and its suite drive it without a
## session.
static func of(estates: Array[Dictionary], snapshot: Dictionary = {}) -> Dictionary:
	if not estates.is_empty():
		var ordered: Array[Dictionary] = _in_row_order(estates, snapshot)
		return {"kind": KIND_RAISE, "estates": ordered, "line": raise_line(ordered)}
	# No estate is raised: the ledger's own count says whether a Builder stood
	# idle to raise one. A snapshot that carries no count names no gate, because
	# the sheet has not read the roster yet.
	var counts: Variant = snapshot.get("counts", null)
	if not (counts is Dictionary):
		return {}
	if int((counts as Dictionary).get("idle_builders", 0)) > 0:
		return {}
	return {"kind": KIND_NO_BUILDER, "estates": [], "line": NO_BUILDER_LINE}

## The estates in the order the sheet prints its rows — the ledger's own groups
## and rows — so the line reads down the page it answers. An estate the snapshot
## does not print keeps the pass's order after them.
static func _in_row_order(
	estates: Array[Dictionary], snapshot: Dictionary
) -> Array[Dictionary]:
	var order: Dictionary = {}
	var index: int = 0
	for raw_group: Variant in snapshot.get("groups", []):
		var group: Dictionary = raw_group
		for raw_row: Variant in group.get("rows", []):
			var row: Dictionary = raw_row
			var tile: Variant = row.get("tile", null)
			if tile is Vector2i and not order.has(tile):
				order[tile] = index
				index += 1
	if order.is_empty():
		return estates
	var keyed: Array[Dictionary] = estates.duplicate()
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: int = int(order.get(a.get("tile"), 1 << 30))
		var right: int = int(order.get(b.get("tile"), 1 << 30))
		if left != right:
			return left < right
		var at: Vector2i = a.get("tile", Vector2i.ZERO)
		var bt: Vector2i = b.get("tile", Vector2i.ZERO)
		if at.y != bt.y:
			return at.y < bt.y
		return at.x < bt.x
	)
	return keyed

## "the court would raise the lumber camp at Cádiz, the mine at Sevilla and the
## farm at Toledo this phase". The estates come in the sheet's own row order, and
## beyond three it counts the rows it cannot name (`… and 2 more`) so a rich plan
## stays one line of chrome.
static func raise_line(estates: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for estate: Dictionary in estates:
		parts.append(
			"the %s at %s" % [
				String(estate.get("name", "")), String(estate.get("place", ""))
			]
		)
	var joined: String = MapPlayPickProse.capped(parts, NAMED_LIMIT)
	if joined.is_empty():
		return ""
	return "the court would raise %s this phase" % joined

