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
## unbound armies are absent. The medal snapshot is the phase's opening read —
## used where a caller has no roster (battle-sim scenarios) and as the
## engagement's starting point; a general who wins an engagement then fights the
## rest of the phase with the medal he just earned (wiki: combat § Acceptance —
## medals persist "for subsequent engagements and turns").
## `hostile` is the court's war query: a march into land its owner is at peace
## with triggers no engagement, so it must not spend a commander
## (wiki: military-generals § Assignment — "every faction that will participate
## in land combat this phase").
static func bind_phase(
	world: WorldMap,
	armies_by_region: Dictionary,
	roster: GeneralRoster,
	seed: int = 0,
	hostile: Callable = Callable()
) -> Dictionary:
	var bindings: Dictionary = {}
	var medals: Dictionary = {}
	if world == null or roster == null:
		return {"army_general": bindings, "army_medals": medals}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var taken: Dictionary = {}
	var battles: Array[Dictionary] = _battles(world, armies_by_region, hostile)
	# Attackers first so an offensive commitment always finds a commander while
	# defenders take what remains (wiki: attack cap). Each role draws from its own
	# pool: an offensive commitment does not spend a crown's defender generals
	# (wiki: military-generals § Assignment).
	for battle: Dictionary in battles:
		var armies: Array[ArmyState] = _armies_of(battle, armies_by_region)
		var defender: int = int(battle["defender"])
		var province: int = int(battle["province"])
		for army: ArmyState in _sorted(armies):
			# Only the armies standing in this province fight here: a moved army
			# elsewhere in the region must not spend a commander on this battle
			# (wiki: military-generals § Assignment — one general per attacking
			# army, not per marching army in the region).
			if army.province != province:
				continue
			if army.moved and army.owner != defender \
					and ArmyCommand.is_hostile(hostile, army.owner, defender):
				_bind(army, roster, taken, rng, bindings, medals, "attack")
	for battle: Dictionary in battles:
		var armies: Array[ArmyState] = _armies_of(battle, armies_by_region)
		var defending: Array[ArmyState] = ArmyForce.armies_of(
			armies, int(battle["province"]), int(battle["defender"])
		)
		for army: ArmyState in _sorted(defending):
			_bind(army, roster, taken, rng, bindings, medals, "defend")
	return {"army_general": bindings, "army_medals": medals}


## Provinces where a land battle will actually resolve: a Great Power army
## moved in, the owner still has regiments standing, and at least one of those
## movers is at war with the owner. A march into land its crown is at peace with
## is no engagement, so it neither binds a commander nor spends the phase's
## offensive cap (wiki: military-generals § Assignment).
static func _battles(
	world: WorldMap, armies_by_region: Dictionary, hostile: Callable = Callable()
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		var armies: Array[ArmyState] = []
		armies.assign(armies_by_region.get(index, []))
		for province: int in ArmyCombat.contested_provinces(model, armies):
			var defender: int = model.province_owner(province)
			if ArmyForce.armies_of(armies, province, defender).is_empty():
				continue
			if not _has_hostile_attacker(armies, province, defender, hostile):
				continue
			result.append({"region": index, "province": province, "defender": defender})
	return result


## True when a Great Power army that moved into `province` is at war with its
## owner. Mirrors the war query [ArmyCombat.ordered_attackers] uses, so binding
## and resolution agree on which provinces fight.
static func _has_hostile_attacker(
	armies: Array[ArmyState], province: int, defender: int, hostile: Callable
) -> bool:
	for army: ArmyState in armies:
		if army == null or not army.moved or army.province != province:
			continue
		if army.owner == defender or army.is_empty():
			continue
		if FactionCatalog.type_of(army.owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		if ArmyCommand.is_hostile(hostile, army.owner, defender):
			return true
	return false


static func _armies_of(battle: Dictionary, armies_by_region: Dictionary) -> Array[ArmyState]:
	var armies: Array[ArmyState] = []
	armies.assign(armies_by_region.get(int(battle["region"]), []))
	return armies


static func _sorted(armies: Array[ArmyState]) -> Array[ArmyState]:
	var result: Array[ArmyState] = armies.duplicate()
	result.sort_custom(func(a: ArmyState, b: ArmyState) -> bool: return a.id < b.id)
	return result


## Binds one eligible general to the army; a full pool leaves it unbound. The
## `taken` ledger is scoped by role and owner so the offensive cap never starves
## defender binding (wiki: military-generals § Assignment).
static func _bind(
	army: ArmyState,
	roster: GeneralRoster,
	taken: Dictionary,
	rng: RandomNumberGenerator,
	bindings: Dictionary,
	medals: Dictionary,
	role: String
) -> void:
	if army == null or army.is_empty():
		return
	if FactionCatalog.type_of(army.owner) != FactionCatalog.Type.GREAT_POWER:
		return
	var ledger: String = "%s:%d" % [role, army.owner]
	var bound: Array[String] = []
	bound.assign(taken.get(ledger, []))
	var free: Array[String] = []
	for general_id: String in roster.ids(army.owner):
		if not bound.has(general_id):
			free.append(general_id)
	if free.is_empty():
		return
	var chosen: String = free[rng.randi_range(0, free.size() - 1)]
	bound.append(chosen)
	taken[ledger] = bound
	bindings[army.id] = chosen
	medals[army.id] = roster.medals(army.owner, chosen)
