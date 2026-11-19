class_name QuickBattleRounds
extends RefCounted
## The three rounds of a quick battle: who strikes first, what each side's
## scripted orders do, the garrison's answering battery, and what a round
## leaves behind for the plate (wiki: quick-battle § Core actions;
## § Wings and collapse; § Outcome and integration).
##
## [QuickBattle] opens the battle and settles it; every round is fought and
## recorded here, so the orchestrator reads the fight and this module fights it
## (REQ-P3-01, REQ-P3-03). Pure data and maths: no nodes, no state beyond the
## dictionaries it is handed.

## How many rounds the battle is fought, at most (see [QuickBattleTerms]).
const MAX_ROUNDS: int = QuickBattleTerms.MAX_ROUNDS
## Each side spends this many command points a round (see [QuickBattleTerms]).
const CP_PER_ROUND: int = QuickBattleTerms.CP_PER_ROUND


## Fights every round of the battle. A side that has lost its line has lost the
## field — the reserve behind it was never committed, so there is nothing left
## to strike and no blow left to deliver (wiki: combat § The line and the
## reserve; quick-battle § Wings and collapse).
static func fight(
	armies: Array[ArmyState],
	state: Dictionary,
	guns: Array[Dictionary],
	context: Dictionary
) -> Array[Dictionary]:
	var rounds: Array[Dictionary] = []
	for round_index in MAX_ROUNDS:
		if QuickBattleActions.line_standing(state, "attacker") == 0 \
			or QuickBattleActions.line_standing(state, "defender") == 0:
			break
		rounds.append(one(armies, state, guns, round_index, context))
	return rounds


static func one(
	armies: Array[ArmyState],
	state: Dictionary,
	guns: Array[Dictionary],
	round_index: int,
	context: Dictionary
) -> Dictionary:
	var order: Array[int] = _order(state, context)
	state["attacker"]["guard"] = 0.0
	state["defender"]["guard"] = 0.0
	state["attacker"]["exposed"] = false
	state["defender"]["exposed"] = false
	var atk_side: Array[ArmyState] = state["attacker"]["side"]
	var def_side: Array[ArmyState] = state["defender"]["side"]
	var siege: bool = int((state["defender"]["mods"] as Dictionary).get("fort", 0)) > 0
	var log: Dictionary = {
		"round": round_index + 1,
		"actions": [] as Array[Dictionary],
		"attacker_count": ArmyForce.side_regiments(atk_side),
		"defender_count": ArmyForce.side_regiments(def_side),
		"guns": QuickBattleBattery.alive(guns),
		"terrain": String(state.get("terrain", "open")),
	}
	for owner: int in order:
		_orders(armies, state, guns, owner, siege, log)
	log["attacker_count"] = ArmyForce.side_regiments(atk_side)
	log["defender_count"] = ArmyForce.side_regiments(def_side)
	log["guns"] = QuickBattleBattery.alive(guns)
	log["gates"] = int((state.get("gates", {}) as Dictionary).get("broken", 0))
	_close(log, state, atk_side, def_side)
	return log


## One side's turn within a round: its scripted orders, then the garrison's
## emplaced battery, which answers after the orders it shelters.
static func _orders(
	armies: Array[ArmyState],
	state: Dictionary,
	guns: Array[Dictionary],
	owner: int,
	siege: bool,
	log: Dictionary
) -> void:
	var key: String = "attacker" if owner == int(state["attacker"]["owner"]) else "defender"
	var enemy_key: String = "defender" if key == "attacker" else "attacker"
	var cp: int = CP_PER_ROUND
	for action: String in QuickBattleActions.actions_for(
		String(state[key]["plan"]), key == "defender", siege
	):
		## A line that has lost its last regiment spends no point and delivers no
		## blow, and nothing is left to strike when the enemy's line is gone
		## (wiki: quick-battle § Outcome and integration; § Wings and collapse).
		if cp < int(QuickBattleActions.ACTION_CP[action]) \
			or QuickBattleActions.line_standing(state, key) == 0 \
			or QuickBattleActions.line_standing(state, enemy_key) == 0:
			break
		cp -= int(QuickBattleActions.ACTION_CP[action])
		var entry: Dictionary = QuickBattleActions.resolve(
			armies, state, key, enemy_key, action, guns
		)
		log["actions"].append(entry)
		## A wing that lost its last regiment to this blow has broken: named
		## once, on the action that did it, on the line it stood in.
		entry.merge(QuickBattleWings.marks(state, key, enemy_key))
	# The emplaced battery fires after the side's actions, into one wing of
	# the besieging line; the guns are the fort's own units
	# (wiki: quick-battle § Wings and collapse).
	if key == "defender" and QuickBattleBattery.alive(guns) > 0 \
		and QuickBattleActions.line_standing(state, "attacker") > 0:
		var volley: Dictionary = QuickBattleBattery.volley_entry(armies, state, guns, owner)
		if not volley.is_empty():
			log["actions"].append(volley)


## What a round leaves behind, read by the plate: the wings as they stand and
## the ones the line has lost, then the condition the rail prints — never a
## recomputation.
static func _close(
	log: Dictionary, state: Dictionary, atk_side: Array[ArmyState], def_side: Array[ArmyState]
) -> void:
	log.merge(QuickBattleWings.record(state))
	log["attacker_health"] = RegimentCondition.entries(atk_side)
	log["defender_health"] = RegimentCondition.entries(def_side)
	log["attacker_strength"] = RegimentCondition.average(atk_side)
	log["defender_strength"] = RegimentCondition.average(def_side)
	log["attacker_cohesion"] = int(state["attacker"]["cohesion"])
	log["defender_cohesion"] = int(state["defender"]["cohesion"])


## The order the two sides strike in: the higher initiative first, the lower
## faction id first on a tie.
static func _order(state: Dictionary, context: Dictionary) -> Array[int]:
	var atk: Dictionary = state["attacker"]
	var def: Dictionary = state["defender"]
	var atk_side: Array[ArmyState] = atk["side"]
	var def_side: Array[ArmyState] = def["side"]
	var atk_score: float = ArmyCommand.initiative(
		atk_side, ArmyCommand.medals(atk_side, context, false)
	)
	var def_score: float = ArmyCommand.initiative(
		def_side, ArmyCommand.medals(def_side, context, true)
	)
	var atk_owner: int = int(atk["owner"])
	var def_owner: int = int(def["owner"])
	if is_equal_approx(atk_score, def_score):
		if atk_owner < def_owner:
			return [atk_owner, def_owner]
		return [def_owner, atk_owner]
	if atk_score > def_score:
		return [atk_owner, def_owner]
	return [def_owner, atk_owner]