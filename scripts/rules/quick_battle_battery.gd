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


static func fire(
	armies: Array[ArmyState], state: Dictionary, guns: Array[Dictionary]
) -> int:
	var atk: Dictionary = state["attacker"]
	var atk_side: Array[ArmyState] = atk["side"]
	var count: int = ArmyCombat.side_regiments(atk_side)
	if count <= 0:
		return 0
	var wanted: int = ceili(float(alive(guns)) * GUN_FIRE * float(count))
	var lost: Array[String] = ArmyCombat.apply_losses(
		armies, atk_side, wanted, int(atk["limit"])
	)
	atk["lost"].append_array(lost)
	return lost.size()


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
