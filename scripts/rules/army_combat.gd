class_name ArmyCombat
extends RefCounted
## Field battles and unopposed captures (wiki: combat, military-armies).
## Auto-resolve only: side strength is Σ (FPN + FPM), casualties follow the
## documented ratio bands, and army elimination is applied before a province
## flips. Generals, terrain, feeding and siege walls are deferred (REQ-P2-02).

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
## `hostile(a, b)` says whether faction a may fight faction b; an invalid callable
## treats every faction as hostile (fixtures), while the map passes the court's
## war state so peace never spills blood (wiki: diplomacy § War required).
static func resolve_turn(
	model: MapModel, armies: Array[ArmyState], hostile: Callable = Callable()
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	if model == null:
		return reports
	ArmyState.prune(armies)
	for province: int in contested_provinces(model, armies):
		var defender: int = model.province_owner(province)
		var attackers: Array[int] = []
		for attacker: int in ordered_attackers(armies, province, defender):
			if _hostile(hostile, attacker, defender):
				attackers.append(attacker)
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
		reports.append_array(_resolve_chain(model, armies, province, defender, attackers))
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
	attackers: Array[int]
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
			model, armies, province, defender, attacker, further
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
	further: bool
) -> Dictionary:
	var defending: Array[ArmyState] = armies_of(armies, province, defender)
	var attacking: Array[ArmyState] = armies_of(armies, province, attacker)
	var initial_defenders: int = side_regiments(defending)
	var ratio: float = 0.0
	if side_strength(defending) > 0.0:
		ratio = side_strength(attacking) / side_strength(defending)
	var band: Dictionary = band_for(ratio)
	var attacker_lost: Array[String] = _apply_losses(
		armies, attacking, ceili(float(side_regiments(attacking)) * float(band["attacker"]))
	)
	var defender_lost: Array[String] = _apply_losses(
		armies, defending, ceili(float(initial_defenders) * float(band["defender"]))
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
	}
	if def_left == 0 and atk_left > 0:
		_flip(model, province, attacker)
		report["outcome"] = Outcome.ATTACKER_VICTORY
		report["captured"] = true
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
		_next_army_id(armies), defender, province, false, types, _next_unit_number(armies)
	)
	armies.append(army)
	return {"count": count, "type": type_id}


static func _apply_losses(
	armies: Array[ArmyState], side: Array[ArmyState], wanted: int
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
	var lost: Array[String] = []
	for index in mini(maxi(wanted, 0), candidates.size()):
		var entry: Dictionary = candidates[index]
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


static func initiative(side: Array[ArmyState]) -> float:
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
	return (float(riders) / float(total)) * INITIATIVE_CAVALRY_WEIGHT


## Attacking factions in initiative order; ties fall to the lowest faction id.
static func ordered_attackers(
	armies: Array[ArmyState], province: int, defender: int
) -> Array[int]:
	var groups: Dictionary = {}
	for army: ArmyState in armies:
		if army == null or not army.moved or army.province != province:
			continue
		if army.owner == defender or army.is_empty():
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
		var a_score: float = initiative(_as_armies(groups[a]))
		var b_score: float = initiative(_as_armies(groups[b]))
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


static func _next_army_id(armies: Array[ArmyState]) -> int:
	var best: int = 0
	for army: ArmyState in armies:
		if army != null:
			best = maxi(best, army.id)
	return best + 1


static func _next_unit_number(armies: Array[ArmyState]) -> int:
	var best: int = 0
	for army: ArmyState in armies:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			if regiment_id.begins_with("unit_"):
				best = maxi(best, int(regiment_id.trim_prefix("unit_")))
	return best + 1


static func _as_armies(raw: Variant) -> Array[ArmyState]:
	var result: Array[ArmyState] = []
	result.assign(raw)
	return result
