class_name RegimentRecord
extends RefCounted
## A regiment's condition and service record: the chevrons and health that feed
## its strength, and the engagements, wins and battle honours its colours bear
## (wiki: naming § Regiment records; DR-20261111-18, DR-20261112-02). This module
## owns the per-instance store's life on an army — christened at the first entry
## (`start`), re-equipped in place (`retype`) and released at the last
## (`forget`) — so an add, drop or re-equip through `ArmyState` leaves nothing
## behind and keeps health inside its type's pool.
## Display and identity only for the record half: strength, casualties and
## chevrons still read the condition fields, so the record never changes an
## outcome (REQ-P2-03). Pure data, no nodes (REQ-P3-03).

## Honours printed under a regiment's name; the rest collapse to `+N more`.
const HONOURS_SHOWN: int = 2


## Zeroes a freshly minted instance and christens it, so a recruit or a scenario
## muster enters the roster titled and at full strength. `ArmyState` calls it
## after recording the instance's type; a load enters through `set_regiments`.
static func start(army: ArmyState, regiment_id: String) -> void:
	var top: int = RegimentCatalog.max_health(army.type_of(regiment_id))
	army.regiment_health[regiment_id] = top
	army.regiment_medals[regiment_id] = 0
	army.regiment_names[regiment_id] = RegimentNames.christen(army, regiment_id)
	army.regiment_engagements[regiment_id] = 0
	army.regiment_wins[regiment_id] = 0
	army.regiment_honours[regiment_id] = []
	army.regiment_history[regiment_id] = RegimentDecorations.blank()


## Re-equips one instance: the type swaps and its health scales to the same
## fraction of the new pool, so a reload reads the condition it left. Called by
## `ArmyState.set_type`, the one path `RegimentUpgrades`/`MilitaryParity` take.
static func retype(army: ArmyState, regiment_id: String, type_id: String) -> void:
	## Read the old pool before the swap; `condition_of` sees the new type after.
	var before: Dictionary = army.condition_of(regiment_id)
	army.regiment_types[regiment_id] = RegimentCatalog.normalize(type_id)
	var top: int = RegimentCatalog.max_health(army.regiment_types[regiment_id])
	var keep: float = float(before["hp"]) / float(maxi(int(before["max"]), 1))
	army.regiment_health[regiment_id] = clampi(ceili(float(top) * keep), 0, top)


## Releases an instance's whole store — type, condition and record — when it
## leaves the roster, so a departed regiment leaves nothing behind.
static func forget(army: ArmyState, regiment_id: String) -> void:
	army.regiment_types.erase(regiment_id)
	army.regiment_health.erase(regiment_id)
	army.regiment_medals.erase(regiment_id)
	army.regiment_names.erase(regiment_id)
	army.regiment_engagements.erase(regiment_id)
	army.regiment_wins.erase(regiment_id)
	army.regiment_honours.erase(regiment_id)
	army.regiment_history.erase(regiment_id)


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
	target.regiment_honours[regiment_id] = colours(source, regiment_id)
	target.regiment_history[regiment_id] = RegimentDecorations.history_of(
		source.regiment_history.get(regiment_id, {})
	)


## The provinces on one regiment's colours, newest first.
static func colours(army: ArmyState, regiment_id: String) -> Array:
	if army == null:
		return []
	var worn: Variant = army.regiment_honours.get(regiment_id, [])
	return (worn as Array).duplicate() if worn is Array else []


## One regiment's record, zeroed for a regiment that has never been blooded.
static func of(army: ArmyState, regiment_id: String) -> Dictionary:
	if army == null or regiment_id.is_empty():
		return {"engagements": 0, "wins": 0, "honours": []}
	return {
		"engagements": int(army.regiment_engagements.get(regiment_id, 0)),
		"wins": int(army.regiment_wins.get(regiment_id, 0)),
		"honours": colours(army, regiment_id),
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


## Writes `province` onto the colours of every surviving regiment on a winning
## side — line and reserve alike, the same set the chevron reaches — once per
## province, newest first (DR-20261112-02). Returns how many colours gained it,
## so the plate can say what the field added. No RNG, no rule reads the list.
static func award_honours(side: Array[ArmyState], province: int) -> int:
	var gained: int = 0
	if province < 0:
		return gained
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			var worn: Array = colours(army, regiment_id)
			if worn.has(province):
				continue
			worn.push_front(province)
			army.regiment_honours[regiment_id] = worn
			gained += 1
	return gained


## A save's honour maps, keys as strings and values as plain int lists, so a
## round-trip through JSON restores what was won.
static func honours_from(raw: Variant) -> Dictionary:
	var mapped: Dictionary = {}
	if not raw is Dictionary:
		return mapped
	for key: Variant in (raw as Dictionary).keys():
		var worn: Array = []
		var value: Variant = (raw as Dictionary)[key]
		if value is Array:
			for entry: Variant in (value as Array):
				worn.append(int(entry))
		mapped[String(key)] = worn
	return mapped


## "3 engagements · 2 won", or empty for a regiment that has not yet marched
## under fire, so a fresh roster gains no line. With a chart at hand the
## colours follow: `4 engagements · 3 won · Évora · Lisboa · +2 more`.
static func line(army: ArmyState, regiment_id: String, model: MapModel = null) -> String:
	var record: Dictionary = of(army, regiment_id)
	var fought: int = int(record["engagements"])
	if fought <= 0:
		return ""
	var text: String = "%d engagement%s · %d won" % [
		fought, "" if fought == 1 else "s", int(record["wins"])
	]
	var honours: String = honour_line(army, regiment_id, model)
	if not honours.is_empty():
		text += " · " + honours
	return text


## The newest honours by province name, then `+N more` for the rest; empty when
## the colours are bare or no chart is at hand (DR-20261112-02).
static func honour_line(
	army: ArmyState, regiment_id: String, model: MapModel = null
) -> String:
	if model == null:
		return ""
	var worn: Array = colours(army, regiment_id)
	var shown: int = mini(worn.size(), HONOURS_SHOWN)
	var names: PackedStringArray = PackedStringArray()
	for index in shown:
		var title: String = model.province_name(int(worn[index]))
		if not title.is_empty():
			names.append(title)
	if names.is_empty():
		return ""
	var text: String = " · ".join(names)
	var rest: int = worn.size() - shown
	if rest > 0:
		text += " · +%d more" % rest
	return text
