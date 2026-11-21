class_name QuickBattleActions
extends RefCounted
## One action's resolution for Quick Battle. The law it is fought under — the
## plans, the command points, the damage and guard shares, the cohesion steps
## and the despatch words — lives in [QuickBattleActionLaw], so this module only
## walks a blow (REQ-P3-01, REQ-P3-03).
## A siege routes casualties through [SiegeLanes]: the wall shelters the
## garrison, only artillery reaches behind it, and a sortie trades that shelter
## for every regiment's fire. [SiegeGround] scales the ground a blow lands on:
## assaults and volleys are weaker into HILL/WOODS/TOWN, entrenching is surer
## there (wiki: quick-battle § Core actions). [QuickBattleLine] owns which men a
## side fights with: the line dealt when the battle opened, its wings and the
## weight a blow carries (wiki: combat § The line and the reserve).


## The one action-entry shape every blow writes: a scripted order and the
## battery's volley are read by the same plate, so they share one skeleton
## (REQ-P3-01). Fields a blow does not touch stay at their quiet value.
static func action_entry(side: int, action: String, label: String) -> Dictionary:
	return {
		"side": side,
		"action": action,
		"label": label,
		"attacker_lost": 0,
		"defender_lost": 0,
		"guns_destroyed": 0,
		"battery_hit": 0,
		"wall_lost": 0,
		"behind_lost": 0,
		"turned": 0,
		"gates_broken": 0,
		"sortie": false,
		"guard": 0.0,
		"cohesion_lost": 0,
		"cohesion_why": "",
		"hits": [] as Array[Dictionary],
		"mauled": 0,
		"own_hits": [] as Array[Dictionary],
		"own_mauled": 0,
	}


## Resolve one scripted action against the enemy side (and guns, when assaulting).
## The action walks five named steps: the stance it resolves as, the cohesion it
## pays, the wing it falls on, the weight the blow carries, and the men it
## breaks and mauls (REQ-P3-01).
static func resolve(
	armies: Array[ArmyState],
	state: Dictionary,
	key: String,
	enemy_key: String,
	action: String,
	guns: Array[Dictionary]
) -> Dictionary:
	var me: Dictionary = state[key]
	var enemy: Dictionary = state[enemy_key]
	var fort: int = int((state["defender"].get("mods", {}) as Dictionary).get("fort", 0))
	var siege: bool = fort > 0
	var acted: String = _stance(action, key, siege)
	var entry: Dictionary = action_entry(
		int(me["owner"]), acted, QuickBattleActionLaw.label_of(acted)
	)
	var terrain: String = String(state.get("terrain", "open"))
	## The wing this blow falls on: fire on the fullest part of the enemy line,
	## a charge on the thinnest. A garrison behind a wall holds no wings and the
	## wall's lanes take the blow instead (wiki: quick-battle § Wings and
	## collapse).
	var wing: String = QuickBattleLine.wing_for(enemy, acted)
	entry["wing"] = wing
	_charge_cohesion(me, acted, entry)
	if acted == "maneuver":
		return entry
	if acted == "entrench" or acted == "fall_back":
		_hold_ground(me, key, acted, terrain, entry)
		return entry
	var ratio: float = _blow_ratio(me, enemy, key, acted, terrain, wing, entry)
	var wanted: int = _carried_weight(me, enemy, key, siege, acted, ratio, entry, guns)
	var standing: int = QuickBattleLine.standing_of(enemy)
	if standing <= 0:
		## Nothing stands to be struck: the blow names no wing, because naming
		## one would point at men who have already fallen (wiki: quick-battle
		## § Wings and collapse).
		entry["wing"] = ""
		return entry
	var lost: Array[String] = _strike(
		armies, me, enemy, state, key, siege, fort, wanted, wing, entry
	)
	_maul(enemy, key, lost, entry)
	_break_cohesion(enemy, standing, lost)
	return _pay_own(armies, me, key, entry, acted)


## The stance an order resolves as: a sally with no wall to leave, or one an
## attacker names, is ordinary volley fire.
static func _stance(action: String, key: String, siege: bool) -> String:
	var acted: String = "volley" if action == "sortie" and not siege else action
	if acted == "sortie" and key != "defender":
		return "volley"
	return acted


## Every stance has a cohesion price, and none hands a step back: a manoeuvre
## pays for the press it crosses under, and a fall back trades a step for the
## space it gives (wiki: quick-battle § Turn structure and actions). The price
## is paid before the stance does its work, so the blow it lands is its line's
## own weakened one, and it is kept on the entry so the despatch can name it
## (REQ-P5-05).
static func _charge_cohesion(me: Dictionary, acted: String, entry: Dictionary) -> void:
	var paid: int = mini(QuickBattleActionLaw.cohesion_cost(acted, me), int(me["cohesion"]))
	if paid <= 0:
		return
	me["cohesion"] = int(me["cohesion"]) - paid
	entry["cohesion_lost"] = paid
	entry["cohesion_why"] = QuickBattleActionLaw.cohesion_why(acted)


## A stance that keeps its ground instead of striking: the guard it raises, the
## prepared ground of HILL/WOODS/TOWN making a defender surer.
static func _hold_ground(
	me: Dictionary, key: String, acted: String, terrain: String, entry: Dictionary
) -> void:
	var guard: float = QuickBattleActionLaw.guard_of(acted)
	if key == "defender":
		guard *= SiegeGround.entrench_scale(terrain)
	me["guard"] = maxf(float(me["guard"]), clampf(guard, 0.0, 0.8))
	entry["guard"] = float(me["guard"])


## The share of a line one blow carries: the action's published damage, scaled by
## the striker's cohesion, the enemy's guard, the ground and a flank. The
## defender shoots out into the approaches; the attacker shoots into the
## defender's cover. Ground never shields the side that sallies from it.
static func _blow_ratio(
	me: Dictionary,
	enemy: Dictionary,
	key: String,
	acted: String,
	terrain: String,
	wing: String,
	entry: Dictionary
) -> float:
	var ratio: float = QuickBattleActionLaw.damage_share(acted) \
		* (float(me["cohesion"]) / float(QuickBattleTerms.COHESION_MAX))
	ratio *= 1.0 - clampf(float(enemy["guard"]), 0.0, 0.8)
	var ground: String = terrain if key == "attacker" else "open"
	ratio *= SiegeGround.terrain_scale(acted, ground)
	## A wing taken in flank: a blow that lands beside a wing the enemy has
	## already lost is heavier, and heavier still from both sides (wiki:
	## quick-battle § Wings and collapse). The scale is kept on the blow so the
	## despatch can name why it fell heavier.
	var flank: float = QuickBattleWings.turned_scale(wing, enemy.get("broken", []) as Array)
	if flank > 1.0:
		entry["flank"] = flank
	return ratio * flank


## The men a blow actually reaches: the action's published share spent as
## tactical weight over the enemy line's average rank, with the battery drinking
## what it can and a walled defender's return fire thinning the rest (wiki:
## quick-battle § Cohesion and effective strength). Both terms are read over the
## men each side's line was dealt when the battle opened: a reserve waiting
## behind the limit adds no strength to a blow and never makes the enemy's line
## read tougher than the survivors of its own line (wiki: combat § The line and
## the reserve — "a reserve adds no strength"; quick-battle § Battlefield layout
## — "the reserve is dealt nowhere ... add no strength").
static func _carried_weight(
	me: Dictionary,
	enemy: Dictionary,
	key: String,
	siege: bool,
	acted: String,
	ratio: float,
	entry: Dictionary,
	guns: Array[Dictionary]
) -> int:
	var me_side: Array[ArmyState] = me["side"]
	var enemy_side: Array[ArmyState] = enemy["side"]
	var average: float = ArmyModifiers.average_rank(
		enemy_side, int(enemy["limit"]), QuickBattleLine.line_of(enemy)
	)
	var weight: float = QuickBattleLine.weight(me_side, me)
	## Only firearms, bows and guns can strike a parapet: a besieger's blow is the
	## weight of the regiments that reach it, so a pike's share breaks no wall,
	## silences no gun and opens no gate (wiki: siege-mechanics § Damage Reduction
	## — "melee-only units cannot attack walls"; § Quick Battle lanes — "only
	## regiments with RNG >= 2 can strike it").
	var striking: float = weight
	if siege and key == "attacker":
		striking = SiegeLanes.striking_weight(
			me_side, int(me["limit"]), QuickBattleLine.multiplier_of(me),
			QuickBattleLine.line_of(me)
		)
	var wanted: int = ceili(ratio * striking / average)
	# A line with no firearm or gun among it delivers nothing to the wall, and
	# the despatch says the wall turned the blow aside (the whole line's blow is
	# what it turned).
	if siege and key == "attacker" and striking <= 0.0:
		entry["turned"] = ceili(ratio * weight / average)
		wanted = 0
	# The battery is shot at before the men behind it; melee cannot reach it. A
	# standing gun spends the blow before the lanes, so the garrison is sheltered
	# until the battery is quiet (wiki: siege-mechanics § Quick Battle lanes).
	# A line with no fight left in it delivers no blow, and an empty blow buys
	# nothing: the guns take only what the blow actually carries.
	if wanted > 0 and key == "attacker" and QuickBattleBattery.alive(guns) > 0 \
		and SiegeLanes.can_reach_wall(me_side, QuickBattleLine.line_of(me)):
		var battery: Dictionary = QuickBattleBattery.absorb(guns, wanted)
		entry["guns_destroyed"] = int(battery["destroyed"])
		entry["battery_hit"] = int(battery["absorbed"])
		wanted = maxi(0, wanted - int(battery["absorbed"]))
	if siege and key == "defender":
		var sortie: bool = acted == "sortie"
		entry["sortie"] = sortie
		me["exposed"] = sortie
		if not sortie:
			# The wall answers with the men the battle dealt onto it: a musket
			# held in reserve neither shoots from the parapet nor thins the fire
			# of the line that stands there (wiki: combat § The line and the
			# reserve; siege-mechanics § Quick Battle lanes).
			wanted = ceili(
				float(wanted) * SiegeLanes.return_fire_share(me_side, QuickBattleLine.line_of(me))
			)
	return wanted


## The blow's casualties: a siege splits them across the wall and the men behind
## it, an open field breaks them out of the wing the blow fell on. A wing's
## casualties fall on that wing alone; a line with no wings (a hand-built state,
## a record before wings existed) bled as one deployed slice (wiki: quick-battle
## § Wings and collapse).
static func _strike(
	armies: Array[ArmyState],
	me: Dictionary,
	enemy: Dictionary,
	state: Dictionary,
	key: String,
	siege: bool,
	fort: int,
	wanted: int,
	wing: String,
	entry: Dictionary
) -> Array[String]:
	if wanted <= 0:
		return [] as Array[String]
	var me_side: Array[ArmyState] = me["side"]
	var enemy_side: Array[ArmyState] = enemy["side"]
	if not siege or key != "attacker":
		return QuickBattleLine.break_men(armies, enemy_side, wanted, enemy, wing)
	var split: Dictionary = SiegeLanes.strike(
		armies, me_side, enemy_side, wanted, int(enemy["limit"]), fort,
		bool(enemy.get("exposed", false)), state.get("gates", {}) as Dictionary,
		enemy.get("lanes", {}) as Dictionary, QuickBattleLine.line_of(me)
	)
	var wall_lost: Array[String] = split["wall"]
	var behind_lost: Array[String] = split["behind"]
	var lost: Array[String] = []
	lost.append_array(wall_lost)
	lost.append_array(behind_lost)
	entry["wall_lost"] = wall_lost.size()
	entry["behind_lost"] = behind_lost.size()
	entry["turned"] = int(entry["turned"]) + int(split["turned"])
	entry["gates_broken"] = int(split.get("gates_broken", 0))
	return lost


## The survivors the blow mauls, and the side's casualty count: the blow that
## broke a regiment also costs every standing man health, and the plate shows
## every survivor's drop (wiki: combat § Strength). The province's hospital
## triages the defender's survivors (DR-20261111-12).
static func _maul(enemy: Dictionary, key: String, lost: Array[String], entry: Dictionary) -> void:
	enemy["lost"].append_array(lost)
	var side: Array[ArmyState] = enemy["side"]
	var pool: float = float(lost.size()) * RegimentCondition.HP_PER_SLOT
	if key == "attacker":
		pool *= float(enemy.get("triage", 1.0))
	entry["hits"] = RegimentCondition.damage_side(
		side, pool, int(enemy["limit"]), QuickBattleLine.line_of(enemy)
	)
	entry["mauled"] = (entry["hits"] as Array).size()
	if key == "attacker":
		entry["defender_lost"] = lost.size()
	else:
		entry["attacker_lost"] = lost.size()


## A blow that broke a quarter of the enemy line takes a cohesion step
## (wiki: quick-battle § Cohesion and effective strength).
static func _break_cohesion(enemy: Dictionary, standing: int, lost: Array[String]) -> void:
	if lost.size() < ceili(float(standing) * 0.25):
		return
	enemy["cohesion"] = maxi(0, int(enemy["cohesion"]) - 1)


## An action's own price (an assault or a sortie costs the side that launches it).
## The share is spent over the line the side was dealt, not over every regiment it
## has: men waiting in reserve never take the field, so they neither pay for the
## charge nor make it dearer for the men who do (wiki: combat § The line and the
## reserve — "a reserve adds no strength, takes no casualties"; quick-battle
## § Battlefield layout — "the reserve is dealt nowhere").
static func _pay_own(
	armies: Array[ArmyState], me: Dictionary, key: String, entry: Dictionary, action: String
) -> Dictionary:
	var self_ratio: float = QuickBattleActionLaw.self_share(action) \
		* (float(me["cohesion"]) / float(QuickBattleTerms.COHESION_MAX))
	if self_ratio <= 0.0:
		return entry
	var own_side: Array[ArmyState] = me["side"]
	var wanted_own: int = ceili(self_ratio * float(QuickBattleLine.standing_of(me)))
	var own: Array[String] = QuickBattleLine.losses(armies, own_side, wanted_own, me)
	me["lost"].append_array(own)
	var pool: float = float(own.size()) * RegimentCondition.HP_PER_SLOT
	# A defender's own sally is triaged by its hospital too.
	if key == "defender":
		pool *= float(me.get("triage", 1.0))
	entry["own_hits"] = RegimentCondition.damage_side(
		own_side, pool, int(me["limit"]), QuickBattleLine.line_of(me)
	)
	entry["own_mauled"] = (entry["own_hits"] as Array).size()
	if key == "attacker":
		entry["attacker_lost"] = int(entry["attacker_lost"]) + own.size()
	else:
		entry["defender_lost"] = int(entry["defender_lost"]) + own.size()
	return entry
