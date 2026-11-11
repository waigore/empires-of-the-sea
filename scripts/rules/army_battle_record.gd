class_name ArmyBattleRecord
extends RefCounted
## The land-battle report both resolvers hand back. Auto-resolve and Quick
## Battle open the same record, recover the same garrison and credit the same
## general, so the plate, the gazette and the army layer read one shape
## (REQ-P2-03, REQ-P3-01). Split from [ArmyCombat] so neither resolver carries
## the report skeleton twice.


## The fields every land-battle report carries before its resolver adds the
## battle-specific ones (`quick`, `siege`, `attack_cost`, line strengths).
static func open(
	province: int, attacker: int, defender: int, outcome: int
) -> Dictionary:
	return {
		"province": province,
		"attacker": attacker,
		"defender": defender,
		"outcome": outcome,
		"attacker_lost": [] as Array[String],
		"defender_lost": [] as Array[String],
		"captured": false,
		"garrison": 0,
		"recovered_type": "",
		"attacker_medals": 0,
		"defender_medals": 0,
		"medal_gain": "",
		"medal_owner": -1,
	}


## Credits the winning side's commander and records the decoration on the
## report. `lead` is the army read BEFORE casualties, so a mauled line cannot
## hand the medal to a general who was not the side's commander when it opened.
static func credit(
	report: Dictionary, context: Dictionary, lead: ArmyState, owner: int
) -> void:
	var medal: String = ArmyCommand.award(context, lead, owner)
	report["medal_gain"] = medal
	if not medal.is_empty():
		report["medal_owner"] = owner


## A mutual annihilation on a later exchange leaves the defender's province a
## recovered garrison (wiki: combat § Garrison recovery type).
static func recover_garrison(
	report: Dictionary,
	armies: Array[ArmyState],
	province: int,
	defender: int,
	initial: int,
	context: Dictionary
) -> void:
	var recovery: Dictionary = ArmyGarrison.recover(
		armies, province, defender, initial, context
	)
	report["garrison"] = int(recovery.get("count", 0))
	report["recovered_type"] = String(recovery.get("type", ""))
