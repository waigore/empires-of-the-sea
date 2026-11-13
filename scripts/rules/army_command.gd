class_name ArmyCommand
extends RefCounted
## Command helpers for a battle side: which army is primary, which general
## medals apply, and stable id minting for recovered garrisons
## (wiki: military-armies § Combat and province loss, military-generals § Medals).
## Split from ArmyCombat so the battle chain stays inside the P3 size bar.


## Primary army for a side: most regiments, ties by lowest army id.
static func primary(side: Array[ArmyState]) -> ArmyState:
	var best: ArmyState = null
	for army: ArmyState in side:
		if army == null:
			continue
		if best == null or army.count() > best.count():
			best = army
		elif army.count() == best.count() and army.id < best.id:
			best = army
	return best


## Medals the side fights under: its primary army's bound general, else the
## leader-multiplier fallback (wiki: military-generals § Assignment). A general
## who wins an engagement earns a medal at once and fights the phase's later
## engagements with it (wiki: combat § Acceptance — "persists the updated medals
## into game state for subsequent engagements and turns"), so the live roster
## beats the phase snapshot the binding took. The snapshot stays as the fallback
## for a context that names medals without a roster (battle-sim scenarios).
static func medals(side: Array[ArmyState], context: Dictionary, defending: bool = false) -> int:
	return medals_of(primary(side), context, defending)


## Medals one army fights under: its bound general's live count, else the phase
## snapshot, else the leader fallback. Callers that also award the decoration
## read the primary army through this same entry, so the side's line and the
## general it credits always name one commander. `defending` picks the leader's
## published side (Gustavus attacks, Frederick defends — leader-bonuses).
static func medals_of(lead: ArmyState, context: Dictionary, defending: bool = false) -> int:
	if lead == null:
		return 0
	var bindings: Dictionary = context.get("army_general", {}) as Dictionary
	var general_id: String = String(bindings.get(lead.id, ""))
	if not general_id.is_empty():
		var roster: GeneralRoster = context.get("roster") as GeneralRoster
		if roster != null:
			return roster.medals(lead.owner, general_id)
	var snapshot: Dictionary = context.get("army_medals", {}) as Dictionary
	if snapshot.has(lead.id):
		return int(snapshot[lead.id])
	var leaders: Dictionary = context.get("leaders", {}) as Dictionary
	return ArmyModifiers.fallback_medals(String(leaders.get(lead.owner, "")), defending)


## Credits the winning side's primary general with one medal; returns its id
## only when a medal was actually gained (a four-medal general gains nothing).
## The caller passes the army it read BEFORE casualties for `medals_of`: the
## primary is the army with the most regiments before battle resolution
## (wiki: military-armies § Battle grouping), so a mauled line cannot hand the
## decoration to a general who was not the side's commander when it opened.
static func award(context: Dictionary, lead: ArmyState, owner: int) -> String:
	if lead == null:
		return ""
	var bindings: Dictionary = context.get("army_general", {}) as Dictionary
	var general_id: String = String(bindings.get(lead.id, ""))
	if general_id.is_empty():
		return ""
	var roster: GeneralRoster = context.get("roster") as GeneralRoster
	if roster == null:
		return ""
	var before: int = roster.medals(owner, general_id)
	if roster.award(owner, general_id) <= before:
		return ""
	return general_id


## Initiative for one attacking side: cavalry share plus general medals
## (wiki: combat § Initiative).
static func initiative(side: Array[ArmyState], medals: int = 0) -> float:
	var riders: int = 0
	var total: int = 0
	for army: ArmyState in side:
		if army == null:
			continue
		total += army.count()
		for regiment_id: String in army.regiments:
			if RegimentCatalog.is_cavalry(army.type_of(regiment_id)):
				riders += 1
	if total == 0:
		return 0.0
	var share: float = float(riders) / float(total)
	return share * ArmyModifiers.W_CAV + float(clampi(medals, 0, 4)) * ArmyModifiers.W_MEDAL


## Attacking factions in initiative order. Exact ties are broken by one
## deterministic seeded roll per battle context (wiki: combat § Initiative,
## § Multi-Attacker Chain — seeded by the combat seed and the context identity,
## never the lexical faction id). Rolls come in ascending faction order, so
## identical state always orders ties identically.
static func initiative_order(
	groups: Dictionary, province: int, context: Dictionary
) -> Array[int]:
	var owners: Array[int] = []
	for owner: int in groups.keys():
		owners.append(owner)
	owners.sort()
	var tie_keys: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%d" % [int(context.get("seed", 0)), province]).hash()
	for owner: int in owners:
		tie_keys[owner] = rng.randf()
	owners.sort_custom(func(a: int, b: int) -> bool:
		var a_group: Array[ArmyState] = []
		a_group.assign(groups[a])
		var b_group: Array[ArmyState] = []
		b_group.assign(groups[b])
		var a_score: float = initiative(a_group, medals(a_group, context))
		var b_score: float = initiative(b_group, medals(b_group, context))
		if not is_equal_approx(a_score, b_score):
			return a_score > b_score
		var a_key: float = float(tie_keys.get(a, 0.0))
		var b_key: float = float(tie_keys.get(b, 0.0))
		if not is_equal_approx(a_key, b_key):
			return a_key < b_key
		return a < b
	)
	return owners


## Whether two factions may fight. An unset callable keeps the legacy
## every-faction-hostile fixture behaviour.
static func is_hostile(hostile: Callable, attacker: int, defender: int) -> bool:
	if not hostile.is_valid():
		return true
	return bool(hostile.call(attacker, defender))


static func next_army_id(armies: Array[ArmyState]) -> int:
	var best: int = 0
	for army: ArmyState in armies:
		if army != null:
			best = maxi(best, army.id)
	return best + 1


static func next_unit_number(armies: Array[ArmyState]) -> int:
	var best: int = 0
	for army: ArmyState in armies:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			if regiment_id.begins_with("unit_"):
				best = maxi(best, int(regiment_id.trim_prefix("unit_")))
	return best + 1
