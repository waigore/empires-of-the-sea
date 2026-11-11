class_name RegimentRecord
extends RefCounted
## A regiment's service record: the engagements it stood in and the ones its
## side won (wiki: naming § Regiment records; DR-20261111-18). Display and
## identity only — strength, casualties and chevrons still read the condition
## fields, so the record never changes an outcome (REQ-P2-03). Pure data, no
## nodes (REQ-P3-03).


## Zeroes a freshly minted instance and christens it, so a recruit, a scenario
## muster and a reload all enter the roster titled. Called by `ArmyState`.
static func start(army: ArmyState, regiment_id: String) -> void:
	army.regiment_names[regiment_id] = RegimentNames.christen(army, regiment_id)
	army.regiment_engagements[regiment_id] = 0
	army.regiment_wins[regiment_id] = 0


## Releases a title and record when the instance leaves the roster.
static func forget(army: ArmyState, regiment_id: String) -> void:
	army.regiment_names.erase(regiment_id)
	army.regiment_engagements.erase(regiment_id)
	army.regiment_wins.erase(regiment_id)


## Carries the title and record of `ids` to another army (a detach).
static func take(source: ArmyState, target: ArmyState, ids: Array[String]) -> void:
	for regiment_id: String in ids:
		_carry_one(source, target, regiment_id)


## Carries every instance's title and record (a combine).
static func carry(source: ArmyState, target: ArmyState) -> void:
	for regiment_id: String in source.regiments:
		_carry_one(source, target, regiment_id)


static func _carry_one(source: ArmyState, target: ArmyState, regiment_id: String) -> void:
	target.regiment_names[regiment_id] = RegimentNames.of(source, regiment_id)
	target.regiment_engagements[regiment_id] = int(
		source.regiment_engagements.get(regiment_id, 0)
	)
	target.regiment_wins[regiment_id] = int(source.regiment_wins.get(regiment_id, 0))


## One regiment's record, zeroed for a regiment that has never been blooded.
static func of(army: ArmyState, regiment_id: String) -> Dictionary:
	if army == null or regiment_id.is_empty():
		return {"engagements": 0, "wins": 0}
	return {
		"engagements": int(army.regiment_engagements.get(regiment_id, 0)),
		"wins": int(army.regiment_wins.get(regiment_id, 0)),
	}


## Counts one engagement for every regiment on a side; `won` credits the win.
## Called from the one place a battle attaches its aftermath, so auto-resolve
## and Quick Battle tally alike. Returns how many records were written.
static func note_battle(side: Array[ArmyState], won: bool) -> int:
	var noted: int = 0
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			army.regiment_engagements[regiment_id] = (
				int(army.regiment_engagements.get(regiment_id, 0)) + 1
			)
			if won:
				army.regiment_wins[regiment_id] = (
					int(army.regiment_wins.get(regiment_id, 0)) + 1
				)
			noted += 1
	return noted


## "3 engagements · 2 won", or empty for a regiment that has not yet marched
## under fire, so a fresh roster gains no line.
static func line(army: ArmyState, regiment_id: String) -> String:
	var record: Dictionary = of(army, regiment_id)
	var fought: int = int(record["engagements"])
	if fought <= 0:
		return ""
	return "%d engagement%s · %d won" % [
		fought, "" if fought == 1 else "s", int(record["wins"])
	]


## The army's own tally, read from its regiments' records: every engagement
## counted once per regiment that stood. Empty when the army is green.
static func army_line(army: ArmyState) -> String:
	if army == null:
		return ""
	var fought: int = 0
	var won: int = 0
	for regiment_id: String in army.regiments:
		var record: Dictionary = of(army, regiment_id)
		fought += int(record["engagements"])
		won += int(record["wins"])
	if fought <= 0:
		return ""
	return "%d engagement%s · %d won" % [
		fought, "" if fought == 1 else "s", won
	]
