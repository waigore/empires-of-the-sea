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
