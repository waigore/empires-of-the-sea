class_name SpyRules
extends RefCounted
## Spy presence, counter-espionage and research intelligence (wiki:
## civilian-units § Spy, research-state § Spy RP boost, diplomacy § Spy-death
## penalty). Pure rules: state in, events out, so the map adapter applies the
## consequences and tests drive the dice without a screen (REQ-P3-03).

const TYPE: String = "spy"
const WORK_COUNTER: String = "counter_spy"
## Each rival Great Power holding one of the researcher's spies adds +15% RP to
## slots whose tech that rival already knows (wiki: research-state).
const RP_BOOST_PCT: int = 15
## One spy on counter_spy anywhere gives empire-wide +5% kill chance against
## enemy spies in owned provinces (wiki: civilian-units § Work Order Summary).
const KILL_PCT: int = 5
## Survivors of the kill roll defect on 10% per turn (wiki: civilian-units).
const DEFECT_PCT: int = 10
## A spy killed in foreign territory cools relations by 8 (wiki: diplomacy
## § Spy-death diplomacy penalty).
const KILL_RELATION_PENALTY: float = 8.0


static func is_spy(unit: CivilianState) -> bool:
	return unit != null and unit.type_id == TYPE


## Spy locations are invisible to every other court (wiki: civilian-units
## § Spy (4)). `viewer` is the crown whose map is being drawn; a negative
## viewer means no filter (rules fixtures).
static func hidden_from(unit: CivilianState, viewer: int) -> bool:
	if unit == null or viewer < 0 or unit.owner == viewer:
		return false
	return unit.type_id == TYPE


## A spy standing on land its own crown does not hold, with no province means
## no counter-espionage and no court to report on.
static func is_foreign(model: MapModel, unit: CivilianState) -> bool:
	if model == null or not is_spy(unit) or unit.is_embarked():
		return false
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	if province == MapModel.NO_ID:
		return false
	return model.province_owner(province) != unit.owner


## One spy on counter_spy anywhere grants the empire-wide screen.
static func has_counter_spy(units: Array, owner: int) -> bool:
	for raw: Variant in units:
		var unit: CivilianState = raw as CivilianState
		if unit == null or unit.owner != owner or not unit.is_working():
			continue
		if unit.work_action() == WORK_COUNTER:
			return true
	return false


## Provinces where this owner keeps a spy and does not hold the land.
static func presence_provinces(
	model: MapModel, units: Array, owner: int
) -> Array[int]:
	var result: Array[int] = []
	for raw: Variant in units:
		var unit: CivilianState = raw as CivilianState
		if unit == null or unit.owner != owner or not is_foreign(model, unit):
			continue
		var province: int = model.province_at(unit.tile.x, unit.tile.y)
		if not result.has(province):
			result.append(province)
	result.sort()
	return result


## Rival Great Powers where this owner keeps a spy: the court-report and RP
## boost observers (wiki: civilian-units § Spy (2), (5)).
static func qualifying_rivals(
	model: MapModel, units: Array, owner: int
) -> Array[int]:
	var result: Array[int] = []
	for raw: Variant in units:
		var unit: CivilianState = raw as CivilianState
		if unit == null or unit.owner != owner or not is_foreign(model, unit):
			continue
		var province: int = model.province_at(unit.tile.x, unit.tile.y)
		var rival: int = model.province_owner(province)
		if rival == owner or FactionCatalog.type_of(rival) != FactionCatalog.Type.GREAT_POWER:
			continue
		if not result.has(rival):
			result.append(rival)
	result.sort()
	return result


## Tech id -> additive RP percentage. Each qualifying rival that already knows
## the tech adds RP_BOOST_PCT (wiki: research-state § Spy RP boost).
static func research_bonus(
	tech_ids: Array, rival_techs: Dictionary, qualifying: Array[int]
) -> Dictionary:
	var bonus: Dictionary = {}
	for raw: Variant in tech_ids:
		var tech_id: String = String(raw)
		if tech_id.is_empty():
			continue
		var count: int = 0
		for rival: int in qualifying:
			var known: Dictionary = rival_techs.get(rival, {})
			if bool(known.get(tech_id, false)):
				count += 1
		if count > 0:
			bonus[tech_id] = RP_BOOST_PCT * count
	return bonus


## Pre-Research spy resolution. Mutates the roster: killed spies are removed,
## defected spies change owner to the province owner. Returns one event per
## consequence: {kind: "killed"|"defected", unit, owner, province,
## territory_owner}. Dice are seeded per spy so a saved turn replays exactly.
static func resolve_turn(
	model: MapModel, units: Array[CivilianState], turn: int, game_seed: int
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if model == null:
		return events
	var screened: Dictionary = _screened_owners(model, units)
	if screened.is_empty():
		return events
	var index: int = 0
	while index < units.size():
		var unit: CivilianState = units[index]
		if unit == null or not is_foreign(model, unit):
			index += 1
			continue
		var province: int = model.province_at(unit.tile.x, unit.tile.y)
		var territory_owner: int = model.province_owner(province)
		if not screened.has(territory_owner):
			index += 1
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = _roll_seed(game_seed, turn, unit.owner, unit.id)
		if rng.randf() < float(KILL_PCT) / 100.0:
			events.append({
				"kind": "killed",
				"unit": unit,
				"owner": unit.owner,
				"province": province,
				"territory_owner": territory_owner,
			})
			units.remove_at(index)
			continue
		if rng.randf() < float(DEFECT_PCT) / 100.0:
			var former: int = unit.owner
			unit.owner = territory_owner
			unit.clear_work()
			unit.moved = true
			events.append({
				"kind": "defected",
				"unit": unit,
				"owner": former,
				"province": province,
				"territory_owner": territory_owner,
			})
		index += 1
	return events


## Owners whose provinces hold a counter-spy screen this turn.
static func _screened_owners(model: MapModel, units: Array) -> Dictionary:
	var screened: Dictionary = {}
	for raw: Variant in units:
		var unit: CivilianState = raw as CivilianState
		if unit == null or not unit.is_working() or unit.work_action() != WORK_COUNTER:
			continue
		var province: int = model.province_at(unit.tile.x, unit.tile.y)
		if province == MapModel.NO_ID:
			continue
		if model.province_owner(province) == unit.owner:
			screened[unit.owner] = true
	return screened


## Stable per-spy seed: same save, turn and spy always roll the same dice.
static func _roll_seed(game_seed: int, turn: int, owner: int, unit_id: int) -> int:
	return ("%d:%d:%d:%d" % [game_seed, turn, owner, unit_id]).hash()
