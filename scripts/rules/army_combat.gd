class_name ArmyCombat
extends RefCounted
## Field battles and unopposed captures (wiki: combat, military-armies).
## Auto-resolve: side strength is Σ (FPN + FPM) over the deployed slice, scaled
## by general medals, feeding, leader and terrain modifiers; casualties follow
## the documented ratio bands; army elimination is applied before a province
## flips. Pre-combat general binding arrives in `context` from the caller.
## Forts, siege walls, Quick Battle and difficulty stay deferred (REQ-P2-02).

enum Outcome { ATTACKER_VICTORY, DEFENDER_VICTORY, STALEMATE, MUTUAL_ANNIHILATION, CAPTURE }

const INITIATIVE_CAVALRY_WEIGHT: float = 50.0
const RECOVERY_SHARE: float = 0.2
## Great Power military era for garrison recovery; Minors/Tribes stay at 1
## until parity and tech are wired (wiki: factions).
const GREAT_POWER_ERA: int = 4
const MINOR_ERA: int = 1

## Ratio bands (wiki: combat § Auto-resolve ratio bands and loss fractions).
const BANDS: Array[Dictionary] = [
	{"min": 1.5, "attacker": 0.15, "defender": 1.0},
	{"min": 1.0, "attacker": 0.3, "defender": 0.6},
	{"min": 0.67, "attacker": 0.5, "defender": 0.4},
	{"min": 0.0, "attacker": 1.0, "defender": 0.15},
]


## Provinces where a Great Power army ended movement in land it does not own.
static func contested_provinces(model: MapModel, armies: Array[ArmyState]) -> Array[int]:
	var provinces: Array[int] = []
	if model == null:
		return provinces
	for army: ArmyState in armies:
		if army == null or not army.moved or army.province < 0:
			continue
		if FactionCatalog.type_of(army.owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		if model.province_owner(army.province) == army.owner:
			continue
		if not provinces.has(army.province):
			provinces.append(army.province)
	provinces.sort()
	return provinces


## Resolves every contested province, mutating armies and province ownership.
## `context` carries {"roster", "army_general", "feeding", "leaders", "tech"} and
## an optional `hostile(a, b)` war query; unset means every faction is hostile.
static func resolve_turn(
	model: MapModel, armies: Array[ArmyState], context: Dictionary = {}
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	if model == null:
		return reports
	ArmyState.prune(armies)
	for province: int in contested_provinces(model, armies):
		var defender: int = model.province_owner(province)
		var attackers: Array[int] = ordered_attackers(armies, province, defender, context)
		if attackers.is_empty():
			continue
		var defending: Array[ArmyState] = armies_of(armies, province, defender)
		if side_regiments(defending) == 0:
			if has_third_party(armies, province, defender, attackers):
				continue
			var capturer: int = _lowest(attackers)
			_flip(model, province, capturer)
			reports.append(_capture_report(province, capturer, defender))
			continue
		reports.append_array(_resolve_chain(model, armies, province, defender, attackers, context))
		ArmyState.prune(armies)
	return reports


## One defender versus attackers in initiative order, without healing between
## exchanges; the chain stops when the defender is eliminated or all attackers
## have had their exchange.
static func _resolve_chain(
	model: MapModel,
	armies: Array[ArmyState],
	province: int,
	defender: int,
	attackers: Array[int],
	context: Dictionary
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for index in attackers.size():
		var attacker: int = attackers[index]
		var defending: Array[ArmyState] = armies_of(armies, province, defender)
		if side_regiments(defending) == 0:
			break
		var attacking: Array[ArmyState] = armies_of(armies, province, attacker)
		if side_regiments(attacking) == 0:
			continue
		var further: bool = index < attackers.size() - 1
		var report: Dictionary = _exchange(
			model, armies, province, defender, attacker, further, context
		)
		reports.append(report)
		if bool(report.get("captured", false)):
			break
		ArmyState.prune(armies)
	return reports


## One attacker-versus-defender exchange with ratio-band casualties.
static func _exchange(
	model: MapModel,
	armies: Array[ArmyState],
	province: int,
	defender: int,
	attacker: int,
	further: bool,
	context: Dictionary
) -> Dictionary:
	var defending: Array[ArmyState] = armies_of(armies, province, defender)
	var attacking: Array[ArmyState] = armies_of(armies, province, attacker)
	var def_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals(defending, context), true, model, province, defender
	)
	var atk_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals(attacking, context), false, model, province, attacker
	)
	var def_limit: int = int(def_mods["limit"])
	var atk_limit: int = int(atk_mods["limit"])
	var initial_defenders: int = mini(side_regiments(defending), def_limit)
	var atk_deployed: int = mini(side_regiments(attacking), atk_limit)
	var def_strength: float = ArmyModifiers.strength(
		defending, def_limit, float(def_mods["multiplier"])
	)
	var atk_strength: float = ArmyModifiers.strength(
		attacking, atk_limit, float(atk_mods["multiplier"])
	)
	var ratio: float = 0.0
	if def_strength > 0.0:
		ratio = atk_strength / def_strength
	var band: Dictionary = band_for(ratio)
	var attacker_lost: Array[String] = _apply_losses(
		armies, attacking, ceili(float(atk_deployed) * float(band["attacker"])), atk_limit
	)
	var defender_lost: Array[String] = _apply_losses(
		armies, defending, ceili(float(initial_defenders) * float(band["defender"])), def_limit
	)
	var atk_left: int = side_regiments(armies_of(armies, province, attacker))
	var def_left: int = side_regiments(armies_of(armies, province, defender))
	var report: Dictionary = {
		"province": province,
		"attacker": attacker,
		"defender": defender,
		"attacker_lost": attacker_lost,
		"defender_lost": defender_lost,
		"captured": false,
		"garrison": 0,
		"recovered_type": "",
		"attacker_medals": int(atk_mods["medals"]),
		"defender_medals": int(def_mods["medals"]),
		"medal_gain": "",
		"medal_owner": -1,
	}
	if def_left == 0 and atk_left > 0:
		_flip(model, province, attacker)
		report["outcome"] = Outcome.ATTACKER_VICTORY
		report["captured"] = true
		report["medal_gain"] = ArmyCommand.award(context, attacking, attacker)
		if not String(report["medal_gain"]).is_empty():
			report["medal_owner"] = attacker
		return report
	if def_left == 0:
		report["outcome"] = Outcome.MUTUAL_ANNIHILATION
		if further:
			var recovery: Dictionary = _recover_garrison(
				armies, province, defender, initial_defenders
			)
			report["garrison"] = int(recovery.get("count", 0))
			report["recovered_type"] = String(recovery.get("type", ""))
		return report
	if atk_left == 0:
		report["outcome"] = Outcome.DEFENDER_VICTORY
		report["medal_gain"] = ArmyCommand.award(context, defending, defender)
		if not String(report["medal_gain"]).is_empty():
			report["medal_owner"] = defender
		return report
	report["outcome"] = Outcome.STALEMATE
	return report


## Restores 20% (ceil, at least one, never above the initial count) of the
## defender's starting regiments as the era's most advanced infantry.
static func _recover_garrison(
	armies: Array[ArmyState], province: int, defender: int, initial: int
) -> Dictionary:
	if initial <= 0:
		return {"count": 0, "type": ""}
	var count: int = clampi(ceili(float(initial) * RECOVERY_SHARE), 1, initial)
	var type_id: String = RegimentCatalog.garrison_type_for(era_for(defender))
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	var army := ArmyState.muster(
		ArmyCommand.next_army_id(armies),
		defender,
		province,
		false,
		types,
		ArmyCommand.next_unit_number(armies)
	)
	armies.append(army)
	return {"count": count, "type": type_id}


## Weakest-first casualties among the deployed slice; reserves take no losses.
static func _apply_losses(
	armies: Array[ArmyState], side: Array[ArmyState], wanted: int, limit: int = 0
) -> Array[String]:
	var candidates: Array[Dictionary] = []
	for army: ArmyState in side:
		if army == null or not armies.has(army):
			continue
		for regiment_id: String in army.regiments:
			candidates.append({
				"army": army,
				"id": regiment_id,
				"rank": RegimentCatalog.strength(army.type_of(regiment_id)),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		return String(a["id"]) < String(b["id"])
	)
	var pool_start: int = 0
	if limit > 0 and candidates.size() > limit:
		pool_start = candidates.size() - limit
	var lost: Array[String] = []
	for offset in mini(maxi(wanted, 0), candidates.size() - pool_start):
		var entry: Dictionary = candidates[pool_start + offset]
		var army: ArmyState = entry["army"]
		var regiment_id: String = String(entry["id"])
		if army.remove_regiment(regiment_id):
			lost.append(regiment_id)
	return lost


static func side_strength(side: Array[ArmyState]) -> float:
	var total: float = 0.0
	for army: ArmyState in side:
		if army != null:
			total += army.strength()
	return total


static func side_regiments(side: Array[ArmyState]) -> int:
	var total: int = 0
	for army: ArmyState in side:
		if army != null:
			total += army.count()
	return total


static func initiative(side: Array[ArmyState], medals: int = 0) -> float:
	var riders: int = 0
	var total: int = 0
	for army: ArmyState in side:
		if army == null:
			continue
		total += army.count()
		for regiment_id: String in army.regiments:
			if RegimentCatalog.is_cavalry(army.type_of(regiment_id)):
				riders += 1
	if total == 0:
		return 0.0
	var share: float = float(riders) / float(total)
	return share * INITIATIVE_CAVALRY_WEIGHT + float(clampi(medals, 0, 4)) * ArmyModifiers.W_MEDAL


## Attacking factions in initiative order; ties fall to the lowest faction id.
## `context["hostile"]`, when set, is the court's war query so only factions at
## war are counted (wiki: diplomacy § War required for hostile actions).
static func ordered_attackers(
	armies: Array[ArmyState], province: int, defender: int, context: Dictionary = {}
) -> Array[int]:
	var groups: Dictionary = {}
	var hostile: Callable = context.get("hostile", Callable())
	for army: ArmyState in armies:
		if army == null or not army.moved or army.province != province:
			continue
		if army.owner == defender or army.is_empty():
			continue
		if not _hostile(hostile, army.owner, defender):
			continue
		if FactionCatalog.type_of(army.owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		var group: Array[ArmyState] = []
		group.assign(groups.get(army.owner, []))
		group.append(army)
		groups[army.owner] = group
	var owners: Array[int] = []
	for owner: int in groups.keys():
		owners.append(owner)
	owners.sort_custom(func(a: int, b: int) -> bool:
		var a_group: Array[ArmyState] = []
		a_group.assign(groups[a])
		var b_group: Array[ArmyState] = []
		b_group.assign(groups[b])
		var a_score: float = initiative(a_group, ArmyCommand.medals(a_group, context))
		var b_score: float = initiative(b_group, ArmyCommand.medals(b_group, context))
		if not is_equal_approx(a_score, b_score):
			return a_score > b_score
		return a < b
	)
	return owners


static func armies_of(
	armies: Array[ArmyState], province: int, owner: int
) -> Array[ArmyState]:
	var result: Array[ArmyState] = []
	for army: ArmyState in armies:
		if army != null and army.province == province and army.owner == owner:
			result.append(army)
	return result


## Any armed third faction blocks an unopposed capture (wiki: combat).
static func has_third_party(
	armies: Array[ArmyState], province: int, defender: int, attackers: Array[int]
) -> bool:
	for army: ArmyState in armies:
		if army == null or army.province != province or army.is_empty():
			continue
		if army.owner == defender or attackers.has(army.owner):
			continue
		return true
	return false


## Whether two factions may fight. An unset callable keeps the legacy
## every-faction-hostile fixture behaviour.
static func _hostile(hostile: Callable, attacker: int, defender: int) -> bool:
	if not hostile.is_valid():
		return true
	return bool(hostile.call(attacker, defender))


static func band_for(ratio: float) -> Dictionary:
	for band: Dictionary in BANDS:
		if ratio >= float(band["min"]):
			return band
	return BANDS[BANDS.size() - 1]


static func era_for(faction_id: int) -> int:
	if FactionCatalog.type_of(faction_id) == FactionCatalog.Type.GREAT_POWER:
		return GREAT_POWER_ERA
	return MINOR_ERA


static func outcome_label(outcome: int) -> String:
	match outcome:
		Outcome.ATTACKER_VICTORY:
			return "attacker victory"
		Outcome.DEFENDER_VICTORY:
			return "defender victory"
		Outcome.MUTUAL_ANNIHILATION:
			return "mutual annihilation"
		Outcome.CAPTURE:
			return "province captured"
	return "stalemate"


static func _capture_report(province: int, attacker: int, defender: int) -> Dictionary:
	return {
		"province": province,
		"attacker": attacker,
		"defender": defender,
		"outcome": Outcome.CAPTURE,
		"attacker_lost": [] as Array[String],
		"defender_lost": [] as Array[String],
		"captured": true,
		"garrison": 0,
		"recovered_type": "",
		"attacker_medals": 0,
		"defender_medals": 0,
		"medal_gain": "",
		"medal_owner": -1,
	}


static func _flip(model: MapModel, province: int, owner: int) -> void:
	var data: ProvinceState = model.get_province(province)
	if data != null:
		data.owner = owner


static func _lowest(owners: Array[int]) -> int:
	var best: int = owners[0]
	for owner: int in owners:
		if owner < best:
			best = owner
	return best
