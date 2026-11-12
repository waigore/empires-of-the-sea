class_name QuickBattle
extends RefCounted
## One-province tactical combat (wiki: quick-battle): deterministic for a seed,
## three rounds, 3 CP a side. Action tables live in [QuickBattleActions]; fort
## guns in [QuickBattleBattery]. A side's strength aggregates its deployed
## slice's tactical stats (FPN + FPM, chevrons and health), never a bare unit
## count. Casualties feed the same ArmyCombat pipeline as auto-resolve
## (REQ-P2-03, REQ-P3-01, REQ-P3-03).

const MAX_ROUNDS: int = 3
const CP_PER_ROUND: int = 3


static func enabled(context: Dictionary, attacker: int, defender: int) -> bool:
	if not bool(context.get("quick_battle", false)):
		return false
	var player: int = int(context.get("player_faction", -1))
	return player == attacker or player == defender


## Resolves one attacker-versus-defender exchange as a three-round battle.
static func resolve_exchange(
	model: MapModel,
	armies: Array[ArmyState],
	province: int,
	defender: int,
	attacker: int,
	further: bool,
	context: Dictionary
) -> Dictionary:
	var def_side: Array[ArmyState] = ArmyForce.armies_of(armies, province, defender)
	var atk_side: Array[ArmyState] = ArmyForce.armies_of(armies, province, attacker)
	## The side's commander is the primary army read before the rounds
	## (wiki: military-armies § Battle grouping): its line and any medal agree.
	var def_lead: ArmyState = ArmyCommand.primary(def_side)
	var atk_lead: ArmyState = ArmyCommand.primary(atk_side)
	var def_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals_of(def_lead, context), true, model, province, defender
	)
	var atk_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals_of(atk_lead, context), false, model, province, attacker
	)
	var fort_level: int = int(def_mods["fort"])
	var guns: Array[Dictionary] = QuickBattleBattery.make(fort_level, context, defender)
	## The ground and the gates are read once, when the battle opens: the wall
	## lanes and the terrain do not change under the fighting (wiki: quick-battle
	## § Terrain; siege-mechanics § Gates and Sortie).
	var terrain: String = SiegeLanes.lane_terrain(
		model, province, fort_level, String(context.get("terrain_override", ""))
	)
	var gates: Dictionary = SiegeLanes.gates_for(fort_level)
	var state: Dictionary = {
		"attacker": _side_state(atk_side, attacker, int(atk_mods["limit"]), atk_mods),
		"defender": _side_state(def_side, defender, int(def_mods["limit"]), def_mods),
		"terrain": terrain,
		"gates": gates,
	}
	state["attacker"]["plan"] = plan_for(atk_side, attacker, context, false)
	state["defender"]["plan"] = plan_for(def_side, defender, context, true, fort_level > 0)
	## A hospital in the province triages the defender's survivors: the same
	## wear scale auto-resolve applies (DR-20261111-12).
	state["defender"]["triage"] = HospitalRules.triage_scale_at(model, province)
	var atk_start: int = ArmyForce.side_regiments(atk_side)
	var def_start: int = ArmyForce.side_regiments(def_side)
	## Lane split when the battle opened: casualties shrink the lanes as it runs.
	var wall_start: int = SiegeLanes.wall_ids(def_side).size()
	var behind_start: int = SiegeLanes.behind_ids(def_side).size()
	var atk_types: Dictionary = _type_counts(atk_side)
	var def_types: Dictionary = _type_counts(def_side)
	var rounds: Array[Dictionary] = []
	for round_index in MAX_ROUNDS:
		if ArmyForce.side_regiments(atk_side) == 0:
			break
		if ArmyForce.side_regiments(def_side) == 0:
			break
		rounds.append(_round(armies, state, guns, round_index, context))
	var atk_left: int = ArmyForce.side_regiments(atk_side)
	var def_left: int = ArmyForce.side_regiments(def_side)
	var guns_left: int = QuickBattleBattery.alive(guns)
	var fort_downgraded: bool = QuickBattleBattery.downgrade_fort(
		model, province, fort_level, guns
	)
	var fort_after: int = FortRules.level_at(model, province)
	var outcome: int = _outcome(
		atk_left, def_left, state, guns, atk_mods, def_mods
	)
	var atk_lost: Array[String] = state["attacker"]["lost"]
	var def_lost: Array[String] = state["defender"]["lost"]
	var report: Dictionary = BattleSettlement.report_skeleton(
		model, province, attacker, defender, outcome, atk_lost, def_lost,
		atk_mods, def_mods
	)
	report["quick"] = {
		"plan": String(state["attacker"]["plan"]),
		"defender_plan": String(state["defender"]["plan"]),
		"rounds": rounds,
		"attacker_start": atk_start,
		"defender_start": def_start,
		"attacker_left": atk_left,
		"defender_left": def_left,
		"guns_start": guns.size(),
		"guns_left": guns_left,
		"guns_lost": guns.size() - guns_left,
		"gun_type": _gun_type(context, defender),
		"fort_downgraded": fort_downgraded,
		"fort_after": fort_after,
		## The wall lanes the defender held when the battle opened, and how often
		## the garrison left them to sortie (wiki: siege-mechanics).
		"lanes": {
			"wall": wall_start,
			"behind": behind_start,
		},
		"sorties": _sortie_count(rounds),
		"terrain": terrain,
		"terrain_label": SiegeLanes.terrain_label(terrain),
		"gates": gates.duplicate(),
		"breaches": int(gates.get("broken", 0)),
		"limits": {
			"attacker": int(atk_mods["limit"]),
			"defender": int(def_mods["limit"]),
		},
		"attacker_cohesion": int(state["attacker"]["cohesion"]),
		"defender_cohesion": int(state["defender"]["cohesion"]),
	}
	report["attacker_detail"] = _losses(atk_types, _type_counts(atk_side))
	report["defender_detail"] = _losses(def_types, _type_counts(def_side))
	report.merge(ArmyModifiers.line_fields(
		atk_side, int(atk_mods["limit"]), def_side, int(def_mods["limit"])
	))
	BattleSettlement.settle(
		model, armies, report, atk_side, def_side, atk_lead, def_lead, context,
		further, def_start
	)
	return report


static func plan_for(
	side: Array[ArmyState], owner: int, context: Dictionary, is_defender: bool,
	siege: bool = false
) -> String:
	## An explicit defender script wins (the simulator and a scripted defence);
	## otherwise the player's chosen plan follows the side they command.
	if is_defender and QuickBattleActions.PLANS.has(String(context.get("defender_battle_plan", ""))):
		return String(context["defender_battle_plan"])
	if owner == int(context.get("player_faction", -1)):
		return QuickBattleActions.normalize_plan(String(context.get("battle_plan", "balanced")))
	## A garrison with no firearm on the wall can only hurt a siege by sallying.
	if is_defender and siege and SiegeLanes.return_fire_share(side) <= 0.0:
		return "aggressive"
	var riders: float = 0.0
	for army: ArmyState in side:
		if army != null:
			riders = maxf(riders, army.cavalry_share())
	if riders >= 0.3:
		return "aggressive"
	return "defensive" if is_defender else "balanced"


static func actions_for(
	plan: String, is_defender: bool = false, siege: bool = false
) -> Array:
	return QuickBattleActions.actions_for(plan, is_defender, siege)


static func _side_state(
	side: Array[ArmyState], owner: int, limit: int, mods: Dictionary
) -> Dictionary:
	return {
		"side": side,
		"owner": owner,
		"limit": limit,
		"mods": mods,
		"cohesion": 3,
		"guard": 0.0,
		"lost": [] as Array[String],
		"plan": "balanced",
		## A sortieing defender stands outside the wall for the round.
		"exposed": false,
	}


static func _round(
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
		var key: String = "attacker" if owner == int(state["attacker"]["owner"]) else "defender"
		var enemy_key: String = "defender" if key == "attacker" else "attacker"
		var cp: int = CP_PER_ROUND
		for action: String in QuickBattleActions.actions_for(
			String(state[key]["plan"]), key == "defender", siege
		):
			if cp < int(QuickBattleActions.ACTION_CP[action]):
				break
			cp -= int(QuickBattleActions.ACTION_CP[action])
			var entry: Dictionary = QuickBattleActions.resolve(
				armies, state, key, enemy_key, action, guns
			)
			log["actions"].append(entry)
		# The emplaced battery fires after the side's actions.
		if key == "defender" and QuickBattleBattery.alive(guns) > 0:
			var hit: int = QuickBattleBattery.fire(armies, state, guns)
			if hit > 0:
				var hits: Array[Dictionary] = RegimentCondition.damage_side(
					atk_side, float(hit) * RegimentCondition.HP_PER_SLOT,
					int(state["attacker"]["limit"])
				)
				log["actions"].append({
					"side": owner,
					"action": "battery",
					"label": "Emplaced battery",
					"attacker_lost": hit,
					"defender_lost": 0,
					"guns_destroyed": 0,
					"battery_hit": 0,
					"wall_lost": 0,
					"behind_lost": 0,
					"turned": 0,
					"gates_broken": 0,
					"sortie": false,
					"hits": hits,
					"mauled": hits.size(),
				})
	log["attacker_count"] = ArmyForce.side_regiments(atk_side)
	log["defender_count"] = ArmyForce.side_regiments(def_side)
	log["guns"] = QuickBattleBattery.alive(guns)
	log["gates"] = int((state.get("gates", {}) as Dictionary).get("broken", 0))
	## Condition after this round: the rail reads these, never a recomputation.
	log["attacker_health"] = RegimentCondition.entries(atk_side)
	log["defender_health"] = RegimentCondition.entries(def_side)
	log["attacker_strength"] = RegimentCondition.average(atk_side)
	log["defender_strength"] = RegimentCondition.average(def_side)
	log["attacker_cohesion"] = int(state["attacker"]["cohesion"])
	log["defender_cohesion"] = int(state["defender"]["cohesion"])
	return log


## Regiments held by type, so a battle can report what it cost by type.
static func _type_counts(side: Array[ArmyState]) -> Dictionary:
	var counts: Dictionary = {}
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			var type_id: String = army.type_of(regiment_id)
			counts[type_id] = int(counts.get(type_id, 0)) + 1
	return counts


## before minus after: the regiments a side actually lost, by type.
static func _losses(before: Dictionary, after: Dictionary) -> Dictionary:
	var lost: Dictionary = {}
	for type_id: Variant in before.keys():
		var gone: int = int(before[type_id]) - int(after.get(type_id, 0))
		if gone > 0:
			lost[String(type_id)] = gone
	return lost


## Emplaced gun quality the defending court's techs unlock (wiki: siege-mechanics).
static func _gun_type(context: Dictionary, defender: int) -> String:
	var tech: Dictionary = context.get("tech", {}) as Dictionary
	var unlocked: Dictionary = tech.get(defender, {}) as Dictionary
	return FortRules.emplaced_type(unlocked)


## Rounds in which the garrison left the wall to sortie.
static func _sortie_count(rounds: Array[Dictionary]) -> int:
	var count: int = 0
	for round: Dictionary in rounds:
		for entry: Dictionary in round.get("actions", []) as Array:
			if bool(entry.get("sortie", false)):
				count += 1
	return count


static func _order(state: Dictionary, context: Dictionary) -> Array[int]:
	var atk: Dictionary = state["attacker"]
	var def: Dictionary = state["defender"]
	var atk_side: Array[ArmyState] = atk["side"]
	var def_side: Array[ArmyState] = def["side"]
	var atk_score: float = ArmyCommand.initiative(
		atk_side, ArmyCommand.medals(atk_side, context)
	)
	var def_score: float = ArmyCommand.initiative(
		def_side, ArmyCommand.medals(def_side, context)
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


## One side's battle weight: the deployed slice's Σ (FPN + FPM) × chevrons ×
## health, scaled by cohesion and the side's combat modifiers. Emplaced guns
## add their own type's weight, already scaled by their remaining HP (wiki:
## quick-battle § Cohesion and effective strength).
static func effective_strength(
	side: Array[ArmyState],
	limit: int,
	cohesion: int,
	multiplier: float,
	gun_weight: float = 0.0
) -> float:
	return (
		ArmyModifiers.strength(side, limit, multiplier)
		* (float(clampi(cohesion, 0, CP_PER_ROUND)) / float(CP_PER_ROUND))
		+ gun_weight
	)


static func _outcome(
	atk_left: int,
	def_left: int,
	state: Dictionary,
	guns: Array[Dictionary],
	atk_mods: Dictionary,
	def_mods: Dictionary
) -> int:
	if def_left == 0 and atk_left > 0:
		return ArmyCombat.Outcome.ATTACKER_VICTORY
	if def_left == 0 and atk_left == 0:
		return ArmyCombat.Outcome.MUTUAL_ANNIHILATION
	if atk_left == 0:
		return ArmyCombat.Outcome.DEFENDER_VICTORY
	var atk_side: Array[ArmyState] = state["attacker"]["side"]
	var def_side: Array[ArmyState] = state["defender"]["side"]
	var atk: float = effective_strength(
		atk_side,
		int(state["attacker"]["limit"]),
		int(state["attacker"]["cohesion"]),
		float(atk_mods["multiplier"])
	)
	var def: float = effective_strength(
		def_side,
		int(state["defender"]["limit"]),
		int(state["defender"]["cohesion"]),
		float(def_mods["multiplier"]),
		QuickBattleBattery.strength(guns)
	)
	return ArmyCombat.Outcome.ATTACKER_ADVANTAGE if def <= 0.0 or atk / def >= 1.0 \
		else ArmyCombat.Outcome.DEFENDER_VICTORY
