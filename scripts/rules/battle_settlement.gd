class_name BattleSettlement
extends RefCounted
## The one place a resolved land exchange settles: the report fields every
## battle carries, who holds the province, the medal a commander wins, the
## garrison a mutual annihilation leaves, and the aftermath the despatch and
## the plate read (wiki: combat, quick-battle; DR-20261111-18).
## Auto-resolve ([ArmyCombat]) and Quick Battle ([QuickBattle]) both settle here,
## so one exchange never grows two copies of the same outcome branches
## (REQ-P2-03, REQ-P3-01, REQ-P3-03).


## Fields every land battle carries before its mode-specific block. `atk_mods`
## and `def_mods` are the side modifier bundles: the defender's fort sets the
## battle mode and the walls the report names.
static func report_skeleton(
	model: MapModel,
	province: int,
	attacker: int,
	defender: int,
	outcome: int,
	attacker_lost: Array[String],
	defender_lost: Array[String],
	atk_mods: Dictionary,
	def_mods: Dictionary
) -> Dictionary:
	var fort_level: int = int(def_mods.get("fort", 0))
	return {
		"province": province,
		"attacker": attacker,
		"defender": defender,
		"outcome": outcome,
		"attacker_lost": attacker_lost,
		"defender_lost": defender_lost,
		"captured": false,
		"garrison": 0,
		"recovered_type": "",
		"attacker_medals": int(atk_mods.get("medals", 0)),
		"defender_medals": int(def_mods.get("medals", 0)),
		"battle_mode": FortRules.battle_mode(fort_level),
		"fort_level": fort_level,
		"hospital_level": HospitalRules.level_at(model, province),
		"medal_gain": "",
		"medal_owner": -1,
	}


## Settles the outcome onto a report: a victor takes the province, the winning
## side's commander may win a medal, a mutual annihilation that still has a
## fresh attacker leaves a garrison behind, and every survivor's condition is
## attached. `garrison_start` is the defender's strength when the exchange
## opened, and `further` says another attacker is still waiting behind this one.
static func settle(
	model: MapModel,
	armies: Array[ArmyState],
	report: Dictionary,
	attacking: Array[ArmyState],
	defending: Array[ArmyState],
	atk_lead: ArmyState,
	def_lead: ArmyState,
	context: Dictionary,
	further: bool,
	garrison_start: int
) -> void:
	var outcome: int = int(report.get("outcome", ArmyCombat.Outcome.STALEMATE))
	var atk_up: int = 0
	var def_up: int = 0
	match outcome:
		ArmyCombat.Outcome.ATTACKER_VICTORY, ArmyCombat.Outcome.ATTACKER_ADVANTAGE:
			# Only a victory takes the province; an advantage holds the field.
			if outcome == ArmyCombat.Outcome.ATTACKER_VICTORY:
				flip(model, int(report["province"]), int(report["attacker"]))
				report["captured"] = true
			atk_up = RegimentCondition.award_side(attacking)
			_medal(report, context, atk_lead, int(report["attacker"]))
		ArmyCombat.Outcome.DEFENDER_VICTORY:
			def_up = RegimentCondition.award_side(defending)
			_medal(report, context, def_lead, int(report["defender"]))
		ArmyCombat.Outcome.MUTUAL_ANNIHILATION:
			if further:
				var recovery: Dictionary = ArmyGarrison.recover(
					armies, int(report["province"]), int(report["defender"]),
					garrison_start, context
				)
				report["garrison"] = int(recovery.get("count", 0))
				report["recovered_type"] = String(recovery.get("type", ""))
	RegimentCondition.attach(report, attacking, defending, atk_up, def_up)


## Writes the medal a side's commander won, and whose name it goes under.
static func _medal(
	report: Dictionary, context: Dictionary, lead: ArmyState, owner: int
) -> void:
	report["medal_gain"] = ArmyCommand.award(context, lead, owner)
	if not String(report["medal_gain"]).is_empty():
		report["medal_owner"] = owner


## Hands one province to a new holder; a report never flips a missing province.
static func flip(model: MapModel, province: int, owner: int) -> void:
	var data: ProvinceState = model.get_province(province)
	if data != null:
		data.owner = owner
