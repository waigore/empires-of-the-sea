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
## This module orchestrates the turn chain only: side accounting lives in
## [ArmyForce], one exchange in [ArmyExchange], empty-wall storms in
## [ArmyStorm], and both resolvers settle through [BattleSettlement].

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
	ArmyRoster.prune(armies)
	for province: int in contested_provinces(model, armies):
		var defender: int = model.province_owner(province)
		var attackers: Array[int] = ordered_attackers(armies, province, defender, context)
		if attackers.is_empty():
			continue
		var defending: Array[ArmyState] = ArmyForce.armies_of(armies, province, defender)
		if ArmyForce.side_regiments(defending) == 0:
			if ArmyForce.has_third_party(armies, province, defender, attackers):
				continue
			## A wall blocks the walk-in (wiki: siege-mechanics; issue #1314):
			## fort level ≥ 1 is never an unopposed flip, even with zero
			## defending regiments — the march resolves as a storm against the
			## wall and its emplaced battery. Only open ground keeps the
			## unopposed rule. Every attacker storms in the chain's order, so a
			## thin host that marched first cannot void another court's march.
			if FortRules.level_at(model, province) >= 1:
				reports.append_array(
					ArmyStorm.resolve_walled(
						model, armies, province, defender, attackers, context
					)
				)
				continue
			var capturer: int = _lowest(attackers)
			BattleSettlement.flip(model, province, capturer)
			reports.append(_capture_report(model, province, capturer, defender))
			continue
		reports.append_array(
			resolve_chain(model, armies, province, defender, attackers, context)
		)
		ArmyRoster.prune(armies)
	return reports


## One holder versus attackers in initiative order, without healing between
## exchanges; the chain runs until no attacker is left to fight. The winner of
## each engagement holds the field against the next: a defender that holds stays
## where it stands, and an attacker that takes the province meets the next
## attacker as its holder, worn as the fight left it (wiki: combat
## § Multi-Attacker Chain — "the previous battle's winner (without healing or
## regenerating regiments) and the next attacker"; § Province Flip — the
## province flips "to the attacker faction that was last in the chain").
static func resolve_chain(
	model: MapModel,
	armies: Array[ArmyState],
	province: int,
	defender: int,
	attackers: Array[int],
	context: Dictionary
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	## The side that holds the province as this step opens: the seat's own
	## defender until an attacker takes the field from it.
	var holder: int = defender
	for index in attackers.size():
		var attacker: int = attackers[index]
		var holding: Array[ArmyState] = ArmyForce.armies_of(armies, province, holder)
		if ArmyForce.side_regiments(holding) == 0:
			break
		var attacking: Array[ArmyState] = ArmyForce.armies_of(armies, province, attacker)
		if ArmyForce.side_regiments(attacking) == 0:
			continue
		var further: bool = index < attackers.size() - 1
		var report: Dictionary = ArmyExchange.resolve(
			model, armies, province, holder, attacker, further, context
		)
		reports.append(report)
		## A winner that took the province meets the next attacker from the
		## walls it now holds.
		if bool(report.get("captured", false)):
			holder = attacker
		ArmyRoster.prune(armies)
	return reports


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


static func _capture_report(
	model: MapModel, province: int, attacker: int, defender: int
) -> Dictionary:
	var report: Dictionary = BattleSettlement.report_skeleton(
		model, province, attacker, defender, Outcome.CAPTURE,
		[] as Array[String], [] as Array[String], {}, {}
	)
	report["captured"] = true
	return report


static func _lowest(owners: Array[int]) -> int:
	var best: int = owners[0]
	for owner: int in owners:
		if owner < best:
			best = owner
	return best
