class_name VictoryStandings
extends RefCounted
## The age's race, read exactly as the victory reads it (wiki: victory
## § Military victory, § Victory Check): Old World provinces per Great Power
## against the bar that crown must clear. Pure rules over the map — no nodes —
## so the court panel and the turn's warning print the numbers the end-of-turn
## check acts on (REQ-P2-03, REQ-P3-03).

## A crown within this many provinces of its bar is named at the close of the
## turn, so the endgame is never a surprise. This is a reading threshold for
## the despatch only: it changes no winner, no check and no AI decision.
const WARN_WITHIN: int = 3


## One row per Great Power, ordered as the race stands: most Old World
## provinces first, ties broken by player id so a draw never reshuffles
## between turns (the same determinism the victory check uses).
static func rows(
	world: WorldMap,
	human: int = MapModel.NO_ID,
	difficulty: String = Difficulty.DEFAULT
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world == null:
		return result
	for faction_id: int in FactionCatalog.great_power_ids():
		var holdings: int = VictoryRules.old_world_holdings(world, faction_id)
		var bar: int = VictoryRules.threshold_for(faction_id, human, difficulty)
		result.append({
			"id": faction_id,
			"name": FactionCatalog.name_of(faction_id),
			"holdings": holdings,
			"bar": bar,
			"need": maxi(bar - holdings, 0),
			"human": faction_id == human,
		})
	result.sort_custom(_ranked)
	return result


## The human crown's row, or an empty dictionary when the session has no crown
## (the full-AI observer).
static func crown_row(standings: Array[Dictionary], human: int) -> Dictionary:
	for row: Dictionary in standings:
		if bool(row.get("human", false)):
			return row
	return {}


## The crown closest to its bar — the race's leader, the threat when it is not
## the reader.
static func leader(standings: Array[Dictionary]) -> Dictionary:
	return standings[0] if not standings.is_empty() else {}


## The crown nearest the age among the rivals, or an empty dictionary when the
## only row is the reader's own.
static func next_rival(standings: Array[Dictionary]) -> Dictionary:
	for row: Dictionary in standings:
		if not bool(row.get("human", false)):
			return row
	return {}


## The race in one readable line for the court panel: where the crown stands,
## who leads, and how much calendar the campaign has left (wiki: victory
## § Military victory; turn-time-mapping § Campaign calendar cap).
static func line(
	world: WorldMap,
	turn: int,
	human: int = MapModel.NO_ID,
	difficulty: String = Difficulty.DEFAULT,
	infinite: bool = false
) -> String:
	var standings: Array[Dictionary] = rows(world, human, difficulty)
	var crown: Dictionary = crown_row(standings, human)
	if crown.is_empty():
		return ""
	var parts: PackedStringArray = [
		"The age: you hold %d of %d Old World provinces"
		% [int(crown["holdings"]), int(crown["bar"])]
	]
	var lead: Dictionary = leader(standings)
	if int(lead.get("id", human)) == human:
		var next: Dictionary = next_rival(standings)
		parts.append(
			"you lead"
			if next.is_empty()
			else "you lead, %s follows with %d of %d" % [
				String(next["name"]), int(next["holdings"]), int(next["bar"])
			]
		)
	else:
		parts.append(
			"%s leads with %d of %d"
			% [String(lead["name"]), int(lead["holdings"]), int(lead["bar"])]
		)
	parts.append("no calendar closes this age" if infinite else _calendar(turn))
	return "%s." % "; ".join(parts)


## The turn's warning, or "" while the age is still a distant thing. Only the
## reader and the nearest rival are named, so the despatch stays one breath.
static func warning(
	world: WorldMap,
	human: int = MapModel.NO_ID,
	difficulty: String = Difficulty.DEFAULT
) -> String:
	var standings: Array[Dictionary] = rows(world, human, difficulty)
	var parts: PackedStringArray = []
	var crown: Dictionary = crown_row(standings, human)
	if not crown.is_empty() and _close(int(crown["need"])):
		parts.append(
			"Your crown stands %s from the age (%d of %d Old World)."
			% [_provinces(int(crown["need"])), int(crown["holdings"]), int(crown["bar"])]
		)
	var rival: Dictionary = next_rival(standings)
	if not rival.is_empty() and _close(int(rival["need"])):
		parts.append(
			"%s stands %s from the age (%d of %d Old World)."
			% [
				String(rival["name"]),
				_provinces(int(rival["need"])),
				int(rival["holdings"]),
				int(rival["bar"]),
			]
		)
	return " ".join(parts)


static func _ranked(left: Dictionary, right: Dictionary) -> bool:
	if int(left["holdings"]) != int(right["holdings"]):
		return int(left["holdings"]) > int(right["holdings"])
	return str(int(left["id"])) < str(int(right["id"]))


static func _close(need: int) -> bool:
	return need > 0 and need <= WARN_WITHIN


static func _provinces(count: int) -> String:
	return "%d province%s" % [count, "" if count == 1 else "s"]


## The turns the calendar still has, read from the same cap the halt reads.
static func _calendar(turn: int) -> String:
	var left: int = TurnTime.cap_turn() - turn
	if left <= 0:
		return "the calendar closes this turn"
	return "the calendar closes in %d turn%s" % [left, "" if left == 1 else "s"]
