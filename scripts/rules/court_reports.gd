class_name CourtReports
extends RefCounted
## A shadowed court's turn, read back to the crown that watches it (wiki:
## civilian-units § Spy, § Court reports). A Spy that survives the turn on a
## rival's land earns a despatch: that court's diplomatic acts, the battles it
## fought, the provinces it took or lost, and the technologies it finished.
##
## Facts are collected once at the close of a resolved turn and formatted on
## demand for the viewing crown, so a report never reads a hidden agenda and
## never names a court the viewer has not met (REQ-P2-03, REQ-P3-03). Pure
## RefCounted: no nodes, no stored rules state.

## Lines a despatch keeps; the newest turn's news, not a chronicle.
const MAX_LINES: int = 8

const KIND_DIPLOMACY: String = "diplomacy"
const KIND_BATTLE: String = "battle"
const KIND_NAVAL: String = "naval"
const KIND_TECH: String = "tech"

const SIDE_ATTACKER: String = "attacker"
const SIDE_DEFENDER: String = "defender"


## Facts for every shadowed court's turn, in reading order: diplomacy, land,
## sea, then research. `from_index` is the chronicle mark left by the previous
## turn, so only this turn's acts are read. `land_battles` and `naval_battles`
## are the Combat phase's own report dictionaries; `tech_gained` is faction ->
## Array[String] from [method techs_gained]. `shadowed` names the rival Great
## Powers a Spy covers.
static func collect(
	diplomacy: DiplomacyState,
	from_index: int,
	land_battles: Array,
	naval_battles: Array,
	tech_gained: Dictionary,
	shadowed: Array
) -> Array[Dictionary]:
	var facts: Array[Dictionary] = []
	_collect_diplomacy(facts, diplomacy, from_index, shadowed)
	for raw: Variant in land_battles:
		_collect_land(facts, raw as Dictionary, shadowed)
	for raw: Variant in naval_battles:
		_collect_naval(facts, raw as Dictionary, shadowed)
	for raw: Variant in tech_gained.keys():
		var faction: int = int(raw)
		if not shadowed.has(faction):
			continue
		for tech: Variant in tech_gained[raw]:
			facts.append({"kind": KIND_TECH, "subject": faction, "tech": String(tech)})
	return facts


## Technologies each court finished in the pass: rows set after but absent
## before. `before` and `after` are faction -> unlocked table, so a plain diff
## never needs the research resolver.
static func techs_gained(before: Dictionary, after: Dictionary) -> Dictionary:
	var gained: Dictionary = {}
	for raw: Variant in after.keys():
		var faction: int = int(raw)
		var was: Dictionary = before.get(raw, {}) as Dictionary
		var now: Dictionary = after[raw] as Dictionary
		var fresh: Array[String] = []
		for key: Variant in now.keys():
			if not bool(now[key]) or bool(was.get(key, false)):
				continue
			fresh.append(String(key))
		if fresh.is_empty():
			continue
		fresh.sort()
		gained[faction] = fresh
	return gained


## The court whose act an event records. A proposal is the receiver's answer,
## so its actor sits in `b`; every other narrated act is `a`'s own doing.
static func actor_of(event: Dictionary) -> int:
	var kind: String = String(event.get("kind", ""))
	if kind == "proposalAccepted" or kind == "proposalRefused":
		return int(event.get("b", -1))
	if kind == "joinEmpire":
		return int(event.get("a", -1))
	return int(event.get("a", -1))


## One court's despatch lines for the viewer, masked and capped. Facts of other
## subjects are ignored, so the panel can hand the whole turn in.
static func digest(
	facts: Array, state: DiplomacyState, world: WorldMap, viewer: int, subject: int
) -> Array[String]:
	var lines: Array[String] = []
	for raw: Variant in facts:
		var fact: Dictionary = raw as Dictionary
		if int(fact.get("subject", -1)) != subject:
			continue
		var line: String = _line(fact, state, world, viewer)
		if line.is_empty() or lines.has(line):
			continue
		lines.append(line)
		if lines.size() >= MAX_LINES:
			break
	return lines


static func _collect_diplomacy(
	facts: Array[Dictionary], diplomacy: DiplomacyState, from_index: int, shadowed: Array
) -> void:
	if diplomacy == null:
		return
	for index in range(from_index, diplomacy.events.size()):
		var event: Dictionary = diplomacy.events[index] as Dictionary
		var actor: int = actor_of(event)
		if not shadowed.has(actor):
			continue
		facts.append({"kind": KIND_DIPLOMACY, "subject": actor, "event": event})


static func _collect_land(
	facts: Array[Dictionary], battle: Dictionary, shadowed: Array
) -> void:
	var province: int = int(battle.get("province", -1))
	var attacker: int = int(battle.get("attacker", -1))
	var defender: int = int(battle.get("defender", -1))
	if province < 0 or attacker < 0 or defender < 0:
		return
	var base: Dictionary = {
		"kind": KIND_BATTLE,
		"province": province,
		"region": int(battle.get("region", FactionCatalog.OLD_WORLD)),
		"captured": bool(battle.get("captured", false)),
		"outcome": int(battle.get("outcome", -1)),
	}
	if shadowed.has(attacker):
		var fact: Dictionary = base.duplicate()
		fact["subject"] = attacker
		fact["side"] = SIDE_ATTACKER
		fact["opponent"] = defender
		facts.append(fact)
	if shadowed.has(defender) and defender != attacker:
		var fact: Dictionary = base.duplicate()
		fact["subject"] = defender
		fact["side"] = SIDE_DEFENDER
		fact["opponent"] = attacker
		facts.append(fact)


static func _collect_naval(
	facts: Array[Dictionary], battle: Dictionary, shadowed: Array
) -> void:
	var attacker: int = int(battle.get("attacker", -1))
	var defender: int = int(battle.get("defender", -1))
	if attacker < 0 or defender < 0:
		return
	var base: Dictionary = {
		"kind": KIND_NAVAL,
		"zone": int(battle.get("zone", -1)),
		"region": int(battle.get("region", FactionCatalog.OLD_WORLD)),
		"outcome": int(battle.get("outcome", NavalCombat.Outcome.NONE)),
	}
	if shadowed.has(attacker):
		var fact: Dictionary = base.duplicate()
		fact["subject"] = attacker
		fact["side"] = SIDE_ATTACKER
		fact["opponent"] = defender
		facts.append(fact)
	if shadowed.has(defender) and defender != attacker:
		var fact: Dictionary = base.duplicate()
		fact["subject"] = defender
		fact["side"] = SIDE_DEFENDER
		fact["opponent"] = attacker
		facts.append(fact)


static func _line(
	fact: Dictionary, state: DiplomacyState, world: WorldMap, viewer: int
) -> String:
	match String(fact.get("kind", "")):
		KIND_DIPLOMACY:
			return DiplomacyHistory.describe(state, fact["event"] as Dictionary, viewer)
		KIND_BATTLE:
			return _land_line(fact, state, world, viewer)
		KIND_NAVAL:
			return _naval_line(fact, state, world, viewer)
		KIND_TECH:
			return "%s finished %s." % [
				_name(state, viewer, int(fact["subject"])),
				TechCatalog.display_name(String(fact["tech"])),
			]
	return ""


## Land news in the voice of whichever side the reader is shadowing: the
## attacker's storm, or the defender's stand.
static func _land_line(
	fact: Dictionary, state: DiplomacyState, world: WorldMap, viewer: int
) -> String:
	var subject: int = int(fact["subject"])
	var other: int = int(fact["opponent"])
	var who: String = _name(state, viewer, subject)
	var them: String = _name(state, viewer, other)
	var place: String = _place(world, fact)
	var attacker: bool = String(fact["side"]) == SIDE_ATTACKER
	if bool(fact["captured"]):
		if attacker:
			return "%s took %s from %s." % [who, place, them]
		return "%s lost %s to %s." % [who, place, them]
	match int(fact["outcome"]):
		ArmyCombat.Outcome.DEFENDER_VICTORY:
			if attacker:
				return "%s's assault on %s was broken by %s." % [who, place, them]
			return "%s threw back %s's assault on %s." % [who, them, place]
		ArmyCombat.Outcome.ATTACKER_ADVANTAGE:
			if attacker:
				return "%s held the field at %s against %s." % [who, place, them]
			return "%s kept %s, though %s held the field." % [who, place, them]
		ArmyCombat.Outcome.MUTUAL_ANNIHILATION:
			return "The armies of %s and %s destroyed one another at %s." % [
				who, them, place
			]
		ArmyCombat.Outcome.STALEMATE:
			return "%s and %s stood undecided at %s." % [who, them, place]
	return ""


static func _naval_line(
	fact: Dictionary, state: DiplomacyState, world: WorldMap, viewer: int
) -> String:
	var subject: int = int(fact["subject"])
	var other: int = int(fact["opponent"])
	var who: String = _name(state, viewer, subject)
	var them: String = _name(state, viewer, other)
	var sea: String = _sea_zone(world, fact)
	var outcome: int = int(fact["outcome"])
	var attacker: bool = String(fact["side"]) == SIDE_ATTACKER
	var won: bool = (
		outcome == NavalCombat.Outcome.SIDE1_VICTORY
		if attacker
		else outcome == NavalCombat.Outcome.SIDE2_VICTORY
	)
	if outcome == NavalCombat.Outcome.STALEMATE:
		return "Squadrons of %s and %s fought to a standstill in the %s." % [who, them, sea]
	if won:
		return "%s's squadron broke %s's in the %s." % [who, them, sea]
	if (
		outcome == NavalCombat.Outcome.SIDE1_VICTORY
		or outcome == NavalCombat.Outcome.SIDE2_VICTORY
	):
		return "%s's squadron was broken by %s's in the %s." % [who, them, sea]
	return ""


## Province name in the battle's own region; a regionless fixture still reads.
static func _place(world: WorldMap, fact: Dictionary) -> String:
	if world == null:
		return "an unnamed province"
	var model: MapModel = world.region(int(fact.get("region", FactionCatalog.OLD_WORLD)))
	if model == null:
		return "an unnamed province"
	return model.province_name(int(fact["province"]))


static func _sea_zone(world: WorldMap, fact: Dictionary) -> String:
	var zone: int = int(fact.get("zone", -1))
	if world == null or zone < 0:
		return "open sea"
	var model: MapModel = world.region(int(fact.get("region", FactionCatalog.OLD_WORLD)))
	if model == null:
		return "open sea"
	return model.sea_zone_name(zone)


## Names follow the chronicle's rule: the viewer itself, a court it has met, and
## every stranger masked (wiki: diplomacy § Diplomatic History).
static func _name(state: DiplomacyState, viewer: int, faction: int) -> String:
	return DiplomacyHistory.name_for(state, viewer, faction)
