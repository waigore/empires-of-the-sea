class_name MapPlaySpyPick
extends RefCounted
## The spies the court's own espionage pass would move, station or keep this
## turn, named on THE CROWN'S EYES before it presses anything, and the spies the
## pass orders (a walk, a screen) marked `▸` on their rows (wiki: civilian-units
## § Spy; DR-20261121-11, DR-20261122-18).
##
## The reading is not a second opinion: it is `MapPlayCivilianPick.picks` — the
## same pass the crew's own sheet and the chart's mark read — narrowed to the
## crown's spies, so the ledger cannot name a watch, a march or a screen the
## pass would not book (REQ-P2-03, REQ-P3-03).
##
## A reading only: nothing here moves a spy, sets an order or spends a paper,
## and the crown still presses her own sheet (REQ-P5-06).

## The pass would walk the spy toward the ground its next legal step lands on.
const KIND_WALK: String = "walk"
## The pass would set the counter-espionage screen with this spy.
const KIND_SCREEN: String = "screen"
## The pass books nothing for the spy: it stays where it stands.
const KIND_KEEP: String = "keep"

## The one spy order in the rules (`SpyRules`), so a screen is never guessed.
const ACTION_SCREEN: String = SpyRules.WORK_COUNTER

## The sheet's sentence: the pick's own clause, capitalised and closed — the
## same one wording every pick surface prints (REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession, snapshot: Dictionary = {}) -> String:
	return MapPlayPickProse.sentence_of(pick(play, snapshot))

## The ledger's pick as the eyes sheet prints it: `{kind, spies, keys, line}`,
## where each spy is `{region, unit_id, kind, place, line}` and `keys` holds the
## spies the pass gives an order, keyed the way the sheet's own rows look
## themselves up. Empty when the session runs no planner for the crown, an
## observer session, a decided campaign, a crown with no ledger, a session with
## no civilian layer, or a crown with no spy standing.
static func pick(play: PlaySession, snapshot: Dictionary = {}) -> Dictionary:
	if not MapPlayPickProse.crown_crew_ready(play):
		return {}
	var faction: int = play.player_faction
	return of(_spies(play, faction), snapshot)

## The spies the pass books something for, in the sheet's own row order when the
## snapshot carries it: one entry per spy the crown holds, each naming the order
## the published planner would give it this turn.
static func _spies(play: PlaySession, faction: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var picks: Dictionary = MapPlayCivilianPick.picks(play, faction)
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		# Unit ids are minted per roster, so the pick is read on its own chart:
		# a spy of id 5 on the New World is not the Old World's id 5 (REQ-P2-03).
		for raw: Variant in MapPlaySpyAi.roster_for(play, region):
			var unit: CivilianState = raw as CivilianState
			if unit == null or unit.owner != faction or not SpyRules.is_spy(unit):
				continue
			# A spy aboard a squadron is off the map: the pass gives it no duty,
			# so the line names it nowhere (wiki: civilian-units § Overseas
			# deployment; the eyes sheet prints its `aboard` row).
			if unit.is_embarked():
				continue
			var pick: Dictionary = picks.get(unit.id, {})
			if not pick.is_empty() and int(pick.get("region", -1)) != region:
				pick = {}
			found.append(_spy(model, unit, region, pick))
	return found

## One spy's own words: the order the pass would give it, and the ground that
## order lands on.
static func _spy(
	model: MapModel, unit: CivilianState, region: int, pick: Dictionary
) -> Dictionary:
	if not pick.is_empty() and String(pick.get("action", "")) == ACTION_SCREEN:
		return _entry(region, unit, KIND_SCREEN, _place(model, unit.tile))
	if not pick.is_empty():
		var tile: Variant = pick.get("tile", CivilianState.NO_TILE)
		if tile is Vector2i and (tile as Vector2i).x >= 0:
			return _entry(region, unit, KIND_WALK, _place(model, tile as Vector2i))
	# A spy already standing where the pass wants it takes no order: it keeps
	# the watch, the status the sheet's own rows print (REQ-P2-03).
	return _entry(region, unit, KIND_KEEP, _place(model, unit.tile))

static func _entry(
	region: int, unit: CivilianState, kind: String, place: String
) -> Dictionary:
	return {
		"region": region,
		"unit_id": unit.id,
		"kind": kind,
		"place": place,
		"line": _clause({"kind": kind, "place": place}),
	}

## The province a spy's ground stands in, or the wilds off any province.
static func _place(model: MapModel, tile: Vector2i) -> String:
	return MapPlayCivilianPickWords.place(model, model.province_at(tile.x, tile.y))

## The pick, worded off the spy list and the sheet's own snapshot: each spy in
## the order the sheet prints its rows, or empty when the crown holds none. Pure
## — a sheet and its suite drive it without a session.
static func of(spies: Array[Dictionary], snapshot: Dictionary = {}) -> Dictionary:
	if spies.is_empty():
		return {}
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(
		spies, snapshot.get("rows", []), "unit_id"
	)
	return {
		"kind": String(ordered[0].get("kind", "")),
		"spies": ordered,
		"keys": keys_of(ordered),
		"line": pick_line(ordered),
	}


## The spies the reading puts to an order, by `MapPlayPickProse.row_key` — what
## the sheet's own rows look themselves up by, so the one spy the court would walk
## or screen is found among the network and a spy it keeps on watch never looks
## busy (DR-20261122-18).
static func keys_of(spies: Array[Dictionary]) -> Dictionary:
	var keys: Dictionary = {}
	for spy: Dictionary in spies:
		# A spy the pass gives no order keeps its watch where it stands: the line
		# names it, and no row wears a mark for a reading that orders nothing.
		if String(spy.get("kind", "")) == KIND_KEEP:
			continue
		keys[MapPlayPickProse.row_key(spy, "unit_id")] = true
	return keys


## "the court would walk its Spy toward Genoa, keep its Spy at Cádiz and set its
## Spy at Madrid to counter-espionage". Beyond three the line counts the spies it
## cannot name (`… and 2 more`) so a busy screen stays one line of chrome.
static func pick_line(spies: Array[Dictionary]) -> String:
	var clauses: Array[String] = []
	for spy: Dictionary in spies:
		clauses.append(_clause(spy))
	return MapPlayPickProse.court_line("the court would", clauses, "")

## One spy's clause: the order the rules would give it, in the pass's own words.
static func _clause(spy: Dictionary) -> String:
	var place: String = String(spy.get("place", ""))
	match String(spy.get("kind", "")):
		KIND_SCREEN:
			return "set its Spy at %s to counter-espionage" % place
		KIND_WALK:
			return "walk its Spy toward %s" % place
	return "keep its Spy at %s" % place
