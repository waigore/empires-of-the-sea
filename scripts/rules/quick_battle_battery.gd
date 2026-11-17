class_name QuickBattleBattery
extends RefCounted
## Emplaced fort guns for Quick Battle sieges: spawn, silence, fire, and fort
## downgrade when the battery is gone. Node-free so the resolver stays testable
## (REQ-P3-01, REQ-P3-03).


const GUN_HP: float = 2.0
const GUN_FIRE: float = 0.03


static func make(level: int, context: Dictionary, defender: int) -> Array[Dictionary]:
	var guns: Array[Dictionary] = []
	var tech: Dictionary = context.get("tech", {}) as Dictionary
	var unlocked: Dictionary = tech.get(defender, {}) as Dictionary
	var type_id: String = FortRules.emplaced_type(unlocked)
	for _index in FortRules.guns(level):
		guns.append({"hp": GUN_HP, "alive": true, "type": type_id})
	return guns


static func alive(guns: Array[Dictionary]) -> int:
	var count: int = 0
	for gun: Dictionary in guns:
		if bool(gun["alive"]):
			count += 1
	return count


static func hit(guns: Array[Dictionary], damage: int) -> int:
	var destroyed: int = 0
	var left: float = float(damage)
	for gun: Dictionary in guns:
		if left <= 0.0:
			break
		if not bool(gun["alive"]):
			continue
		var take: float = minf(left, float(gun["hp"]))
		gun["hp"] = float(gun["hp"]) - take
		left -= take
		if float(gun["hp"]) <= 0.0:
			gun["alive"] = false
			destroyed += 1
	return destroyed


## Spends one blow on the battery: how much of it the guns soaked, and how many
## that silenced. A gun still standing drinks the blow before the lanes do
## (wiki: siege-mechanics § Quick Battle lanes — the battery is not sheltered).
static func absorb(guns: Array[Dictionary], damage: int) -> Dictionary:
	var before: float = total_hp(guns)
	var destroyed: int = hit(guns, damage)
	var soaked: float = maxf(0.0, before - total_hp(guns))
	return {"absorbed": int(round(soaked)), "destroyed": destroyed}


## Remaining hit points across the battery, silenced guns included at zero.
static func total_hp(guns: Array[Dictionary]) -> float:
	var total: float = 0.0
	for gun: Dictionary in guns:
		if bool(gun["alive"]):
			total += maxf(0.0, float(gun["hp"]))
	return total


## One round of the garrison's emplaced guns. A gun's fire is a blow like any
## other: it falls into **one wing** of the besieging line — the fullest, the
## mass the guns are laid on — takes the flank heavier when that wing's
## neighbour has broken, and never bleeds past the wing it strikes (wiki:
## quick-battle § Wings and collapse). A line with no wings (a hand-built state
## or a record made before wings existed) is bled as one deployed slice, as it
## was before. Returns the wing it fired into and how many it broke.
static func fire(
	armies: Array[ArmyState], state: Dictionary, guns: Array[Dictionary]
) -> Dictionary:
	var atk: Dictionary = state["attacker"]
	var atk_side: Array[ArmyState] = atk["side"]
	var count: int = ArmyForce.side_regiments(atk_side)
	if count <= 0:
		return {"lost": 0, "wing": ""}
	var wings: Dictionary = atk.get("wings", {}) as Dictionary
	var wing: String = QuickBattleWings.target(QuickBattleWings.counts(wings), "volley")
	var blow: float = float(alive(guns)) * GUN_FIRE * float(count)
	blow *= QuickBattleWings.turned_scale(wing, atk.get("broken", []) as Array)
	var lost: Array[String] = []
	if wing.is_empty():
		lost = ArmyForce.apply_losses(armies, atk_side, ceili(blow), int(atk["limit"]))
	else:
		lost = ArmyForce.apply_losses(
			armies, atk_side, ceili(blow), 0, Callable(),
			QuickBattleWings.ids(wings, wing)
		)
	atk["lost"].append_array(lost)
	return {"lost": lost.size(), "wing": wing}


## The battery's volley as one action entry, or `{}` when it hit nobody: the
## guns fire after the garrison's orders, into one wing of the besieging line,
## and the plate reads the blow like any other (wiki: quick-battle § Wings and
## collapse). The entry is [QuickBattleActions]' shape, so the despatch needs no
## special case for the fort's own fire.
static func volley_entry(
	armies: Array[ArmyState], state: Dictionary, guns: Array[Dictionary], owner: int
) -> Dictionary:
	var shot: Dictionary = fire(armies, state, guns)
	var hit: int = int(shot["lost"])
	if hit <= 0:
		return {}
	var atk_side: Array[ArmyState] = state["attacker"]["side"]
	var hits: Array[Dictionary] = RegimentCondition.damage_side(
		atk_side, float(hit) * RegimentCondition.HP_PER_SLOT,
		int(state["attacker"]["limit"])
	)
	var entry: Dictionary = QuickBattleActions.action_entry(owner, "battery", "Emplaced battery")
	entry["attacker_lost"] = hit
	entry["wing"] = String(shot["wing"])
	entry["hits"] = hits
	entry["mauled"] = hits.size()
	var broken_now: Array[String] = QuickBattleWings.fell(state, "attacker")
	if not broken_now.is_empty():
		entry["wing_broken"] = broken_now
	return entry


## Battle weight of the virtual battery: each living piece's type stats scaled by
## the share of its HP still standing (wiki: combat § Strength). The guns' own
## weight replaces the aggregate emplaced bonus on the Quick Battle path, so the
## same pieces are never counted twice.
static func strength(guns: Array[Dictionary]) -> float:
	var total: float = 0.0
	for gun: Dictionary in guns:
		if not bool(gun["alive"]):
			continue
		var share: float = clampf(float(gun["hp"]) / GUN_HP, 0.0, 1.0)
		total += float(RegimentCatalog.strength(String(gun["type"]))) * share
	return total


static func downgrade_fort(
	model: MapModel, province: int, level: int, guns: Array[Dictionary]
) -> bool:
	if level <= 0 or guns.is_empty() or alive(guns) > 0:
		return false
	var data: ProvinceState = model.get_province(province)
	if data == null:
		return false
	data.fort_level = maxi(0, level - 1)
	return true
