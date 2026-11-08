class_name GeneralBinding
extends RefCounted
## Pre-Combat general–army binding (wiki: military-generals § Assignment).
## One general per attacking army and one per defending army, drawn from that
## faction's pool without repeating a general already bound this phase. Binding
## lasts the Combat phase only; anything left unbound uses fallback medals.
##
## Selection is random from the eligible pool but seeded by the caller, so the
## same turn and state reproduce the same commanders (REQ-P2-03).


## Bindings for the whole phase across every region. Returns
## {"army_general": {army_id: general_id}, "army_medals": {army_id: int}};
## unbound armies are absent. The medal snapshot is taken at binding time so a
## general who wins early does not fight the next engagement with the new medal.
static func bind_phase(
	world: WorldMap,
	armies_by_region: Dictionary,
	roster: GeneralRoster,
	seed: int = 0
) -> Dictionary:
	var bindings: Dictionary = {}
	var medals: Dictionary = {}
	if world == null or roster == null:
		return {"army_general": bindings, "army_medals": medals}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var taken: Dictionary = {}
	var battles: Array[Dictionary] = _battles(world, armies_by_region)
	# Attackers first so an offensive commitment always finds a commander while
	# defenders take what remains (wiki: attack cap).
	for battle: Dictionary in battles:
		var armies: Array[ArmyState] = _armies_of(battle, armies_by_region)
		var defender: int = int(battle["defender"])
		for army: ArmyState in _sorted(armies):
			if army.moved and army.owner != defender:
				_bind(army, roster, taken, rng, bindings, medals)
	for battle: Dictionary in battles:
		var armies: Array[ArmyState] = _armies_of(battle, armies_by_region)
		var defending: Array[ArmyState] = ArmyCombat.armies_of(
			armies, int(battle["province"]), int(battle["defender"])
		)
		for army: ArmyState in _sorted(defending):
			_bind(army, roster, taken, rng, bindings, medals)
	return {"army_general": bindings, "army_medals": medals}


## Provinces where a land battle will actually resolve: a Great Power army
## moved in and the owner still has regiments standing.
static func _battles(world: WorldMap, armies_by_region: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		var armies: Array[ArmyState] = []
		armies.assign(armies_by_region.get(index, []))
		for province: int in ArmyCombat.contested_provinces(model, armies):
			var defender: int = model.province_owner(province)
			if ArmyCombat.armies_of(armies, province, defender).is_empty():
				continue
			result.append({"region": index, "province": province, "defender": defender})
	return result


static func _armies_of(battle: Dictionary, armies_by_region: Dictionary) -> Array[ArmyState]:
	var armies: Array[ArmyState] = []
	armies.assign(armies_by_region.get(int(battle["region"]), []))
	return armies


static func _sorted(armies: Array[ArmyState]) -> Array[ArmyState]:
	var result: Array[ArmyState] = armies.duplicate()
	result.sort_custom(func(a: ArmyState, b: ArmyState) -> bool: return a.id < b.id)
	return result


## Binds one eligible general to the army; a full pool leaves it unbound.
static func _bind(
	army: ArmyState,
	roster: GeneralRoster,
	taken: Dictionary,
	rng: RandomNumberGenerator,
	bindings: Dictionary,
	medals: Dictionary
) -> void:
	if army == null or army.is_empty():
		return
	if FactionCatalog.type_of(army.owner) != FactionCatalog.Type.GREAT_POWER:
		return
	var bound: Array[String] = []
	bound.assign(taken.get(army.owner, []))
	var free: Array[String] = []
	for general_id: String in roster.ids(army.owner):
		if not bound.has(general_id):
			free.append(general_id)
	if free.is_empty():
		return
	var chosen: String = free[rng.randi_range(0, free.size() - 1)]
	bound.append(chosen)
	taken[army.owner] = bound
	bindings[army.id] = chosen
	medals[army.id] = roster.medals(army.owner, chosen)
