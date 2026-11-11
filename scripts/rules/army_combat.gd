class_name ArmyCombat
extends RefCounted
## Field battles and unopposed captures (wiki: combat, military-armies).
## Auto-resolve: side strength is Σ (FPN + FPM) over the deployed slice, scaled
## by general medals, feeding, leader and terrain modifiers; casualties follow
## the documented ratio bands; army elimination is applied before a province
## flips. Pre-combat general binding arrives in `context` from the caller.
## Sieges read the fort level: walls soak attack, the emplaced battery adds
## defence and shrinks defender losses, and the besieging train silences guns
## before the clash (wiki: siege-mechanics; DR-20261110-22). Human land battles
## route through QuickBattle; every report names the line and the reserve.

enum Outcome {
	ATTACKER_VICTORY,
	DEFENDER_VICTORY,
	STALEMATE,
	MUTUAL_ANNIHILATION,
	CAPTURE,
	## Quick Battle only: the attacker holds the field but the defender keeps
	## the province (wiki: quick-battle § Outcome and integration).
	ATTACKER_ADVANTAGE,
}

## Garrison recovery eras: a Great Power reforms at 4, a Minor Nation at the
## parity level the caller passes, a Tribe at 1 (wiki: combat § Garrison
## recovery type; factions § Minor military parity).
const GREAT_POWER_ERA: int = 4
const MINOR_ERA: int = 1


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
			flip(model, province, capturer)
			reports.append(_capture_report(province, capturer, defender))
			continue
		reports.append_array(_resolve_chain(model, armies, province, defender, attackers, context))
		ArmyState.prune(armies)
	return reports


## One defender versus attackers in initiative order, without healing between
## exchanges; the chain stops when the defender dies or all attackers have fought.
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
	var fee: Dictionary = ArmyAttackCost.charge(context, attacker)
	if QuickBattle.enabled(context, attacker, defender):
		return ArmyAttackCost.stamp(fee, QuickBattle.resolve_exchange(
			model, armies, province, defender, attacker, further, context
		))
	var defending: Array[ArmyState] = armies_of(armies, province, defender)
	var attacking: Array[ArmyState] = armies_of(armies, province, attacker)
	## The primary army read before any casualties commands the side, and wins
	## its medal (wiki: military-armies § Battle grouping).
	var def_lead: ArmyState = ArmyCommand.primary(defending)
	var atk_lead: ArmyState = ArmyCommand.primary(attacking)
	var def_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals_of(def_lead, context), true, model, province, defender
	)
	var atk_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals_of(atk_lead, context), false, model, province, attacker
	)
	var def_limit: int = int(def_mods["limit"])
	var atk_limit: int = int(atk_mods["limit"])
	var initial_defenders: int = mini(side_regiments(defending), def_limit)
	var atk_deployed: int = mini(side_regiments(attacking), atk_limit)
	## The besieging train's opening fire: silenced guns fall before the clash
	## (wiki: siege-mechanics § Emplaced Artillery; DR-20261110-22).
	var siege: Dictionary = AutoSiege.resolve(
		model, province, int(def_mods["fort"]), defender, attacking, atk_limit, context
	)
	## A silenced gun stops answering: only the standing pieces add their weight.
	var emplaced: float = float(def_mods["emplaced"])
	if not siege.is_empty():
		emplaced *= float(int(siege["guns_left"])) / float(maxi(int(siege["guns_start"]), 1))
	var def_strength: float = ArmyModifiers.strength(
		defending, def_limit, float(def_mods["multiplier"])
	) + emplaced
	var atk_strength: float = FortRules.wall_soak(
		ArmyModifiers.strength(attacking, atk_limit, float(atk_mods["multiplier"])),
		int(atk_mods["fort"]))
	var ratio: float = atk_strength / def_strength if def_strength > 0.0 else 0.0
	var band: Dictionary = ArmyBands.for_ratio(
		ratio, ArmyModifiers.morale(context, attacker),
		ArmyModifiers.morale(context, defender)
	)
	var attacker_lost: Array[String] = apply_losses(
		armies, attacking, ceili(float(atk_deployed) * float(band["attacker"])), atk_limit
	)
	var defender_lost: Array[String] = apply_losses(
		armies, defending, ceili(float(initial_defenders) * float(band["defender"])
		* float(def_mods["loss_scale"])), def_limit
	)
	RegimentCondition.wear(
		attacking,
		RegimentCondition.WOUND_SHARE
		* float(attacker_lost.size()) / float(maxi(atk_deployed, 1)),
		atk_limit
	)
	RegimentCondition.wear(
		defending,
		RegimentCondition.WOUND_SHARE
		* float(defender_lost.size()) / float(maxi(initial_defenders, 1))
		* HospitalRules.triage_scale_at(model, province),
		def_limit
	)
	var atk_left: int = side_regiments(armies_of(armies, province, attacker))
	var def_left: int = side_regiments(armies_of(armies, province, defender))
	var atk_up: int = 0
	var def_up: int = 0
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
		"attack_cost": int(fee["due"]),
		"attack_paid": int(fee["paid"]),
		"battle_mode": FortRules.battle_mode(int(def_mods["fort"])),
		"fort_level": int(def_mods["fort"]),
		"hospital_level": HospitalRules.level_at(model, province),
		"medal_gain": "",
		"medal_owner": -1,
	}
	report.merge(ArmyModifiers.line_fields(attacking, atk_limit, defending, def_limit))
	if not siege.is_empty(): report["siege"] = siege
	if def_left == 0 and atk_left > 0 and not bool(band.get("blunted", false)):
		flip(model, province, attacker)
		report["outcome"] = Outcome.ATTACKER_VICTORY
		report["captured"] = true
		atk_up = RegimentCondition.award_side(attacking)
		report["medal_gain"] = ArmyCommand.award(context, atk_lead, attacker)
		if not String(report["medal_gain"]).is_empty():
			report["medal_owner"] = attacker
		RegimentCondition.attach(report, attacking, defending, atk_up, def_up)
		return report
	if def_left == 0 and atk_left == 0:
		report["outcome"] = Outcome.MUTUAL_ANNIHILATION
		if further:
			var recovery: Dictionary = ArmyGarrison.recover(
				armies, province, defender, initial_defenders, context
			)
			report["garrison"] = int(recovery.get("count", 0))
			report["recovered_type"] = String(recovery.get("type", ""))
		RegimentCondition.attach(report, attacking, defending, atk_up, def_up)
		return report
	if atk_left == 0:
		report["outcome"] = Outcome.DEFENDER_VICTORY
		def_up = RegimentCondition.award_side(defending)
		report["medal_gain"] = ArmyCommand.award(context, def_lead, defender)
		if not String(report["medal_gain"]).is_empty():
			report["medal_owner"] = defender
		RegimentCondition.attach(report, attacking, defending, atk_up, def_up)
		return report
	# The hungrier attacker's gutted garrison keeps its owner (wiki: combat).
	report["blunted"] = def_left == 0 and atk_left > 0
	report["outcome"] = Outcome.STALEMATE
	RegimentCondition.attach(report, attacking, defending, atk_up, def_up)
	return report


## Weakest-first casualties among the deployed slice; reserves take no losses.
## `accept` filters the pool by type, so one siege lane can bleed alone.
static func apply_losses(
	armies: Array[ArmyState], side: Array[ArmyState], wanted: int,
	limit: int = 0, accept: Callable = Callable()
) -> Array[String]:
	var candidates: Array[Dictionary] = []
	for army: ArmyState in side:
		if army == null or not armies.has(army):
			continue
		for regiment_id: String in army.regiments:
			var data: Dictionary = army.condition_of(regiment_id)
			if accept.is_valid() and not bool(accept.call(String(data["type"]))):
				continue
			candidates.append({
				"army": army,
				"id": regiment_id,
				"rank": ArmyModifiers.rank_of(
					String(data["type"]), int(data["medals"]), float(data["fraction"])
				),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["rank"]), float(b["rank"])):
			return float(a["rank"]) < float(b["rank"])
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


## Initiative for one side (wiki: combat § Initiative).
static func initiative(side: Array[ArmyState], medals: int = 0) -> float:
	return ArmyCommand.initiative(side, medals)


## Attacking factions in initiative order; exact ties use one deterministic
## seeded roll per battle context, never lexical faction id. `context["hostile"]`
## is the court's war query, so only factions at war are counted
## (wiki: combat § Initiative, § Multi-Attacker Chain; diplomacy § War).
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
		if not ArmyCommand.is_hostile(hostile, army.owner, defender):
			continue
		if FactionCatalog.type_of(army.owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		var group: Array[ArmyState] = []
		group.assign(groups.get(army.owner, []))
		group.append(army)
		groups[army.owner] = group
	return ArmyCommand.initiative_order(groups, province, context)


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


static func band_for(ratio: float) -> Dictionary:
	return ArmyBands.for_ratio(ratio)


## Effective military era for garrison recovery (wiki: combat § Garrison
## recovery type; factions § Minor military parity).
static func era_for(faction_id: int, context: Dictionary = {}) -> int:
	return ArmyGarrison.era_for(faction_id, context)


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
		Outcome.ATTACKER_ADVANTAGE:
			return "attacker holds the field"
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


static func flip(model: MapModel, province: int, owner: int) -> void:
	var data: ProvinceState = model.get_province(province)
	if data != null:
		data.owner = owner


static func _lowest(owners: Array[int]) -> int:
	var best: int = owners[0]
	for owner: int in owners:
		if owner < best:
			best = owner
	return best
