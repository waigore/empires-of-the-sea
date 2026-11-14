class_name MapPlayCourt
extends RefCounted
## One reader for the court's standing and its order of battle, so every rival
## pass asks the same question once instead of carrying its own copy
## (REQ-P2-03, REQ-P3-01, REQ-P3-02).
##
## A pass needs three kinds of answer before it plans: which courts run a
## planner this session, what each already holds (regiments, hulls, hulls that
## can fight, the enemy's hulls), and where a named army or squadron stands.
## Those reads lived six times over in the `MapPlay*Ai` passes; they live here
## once. Pure state reads: nothing here issues an order or changes a roster.

## `-1` reads as "any owner" for the roster lookups.
const NO_OWNER: int = -1


## The Great Powers that run a planner for this session, in catalog order. The
## human court is skipped unless the full-AI observer seats it like any rival
## (wiki: game-setup § Human/AI slot assignment; docs/ai-observer.md), and the
## `AiControl` gate keeps a noop or bench crown inert.
static func planning_factions(play: PlaySession) -> Array[int]:
	var factions: Array[int] = []
	if play == null:
		return factions
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction and not play.observer_mode:
			continue
		if not AiControl.plans(play, faction):
			continue
		factions.append(faction)
	return factions


## True when any court holds a declared war on this one. Delegates to the pure
## `AiIncome.at_war`, which the money goal already reads, so the reserve and the
## planner's footing cannot disagree about what a war is.
static func at_war(play: PlaySession, faction: int) -> bool:
	if play == null:
		return false
	return AiIncome.at_war(play.diplomacy, faction)


## Land regiments this court holds in every region: the muster target and the
## invasion capacity read the whole order of battle, not the visible region.
## A session with no army layer reads none.
static func regiments(play: PlaySession, faction: int) -> int:
	if play == null or play.army_layer == null:
		return 0
	return play.army_layer.regiment_count_all(faction)


## Hulls of every kind this court holds, the head count the power score and the
## build objective count.
static func ships(play: PlaySession, faction: int) -> int:
	if play == null or play.ship_layer == null:
		return 0
	return play.ship_layer.hull_count_all(faction)


## Hulls of a court that can fight: the build objective's own reading, so a
## court with only merchant hulls still wants a warship (issue #491 T5, #484).
static func warships(play: PlaySession, owner: int) -> int:
	if play == null or play.ship_layer == null:
		return 0
	var total: int = 0
	for region: int in play.ship_layer.regions.region_ids():
		for raw: Variant in play.ship_layer.regions.value(region, []):
			var fleet: FleetState = raw
			if fleet == null or fleet.owner != owner:
				continue
			for hull_id: String in fleet.hulls:
				if ShipStats.is_warship(fleet.type_of(hull_id)):
					total += 1
	return total


## Hulls of every court at war with this one: the threat the navy objective
## prices.
static func hostile_ships(play: PlaySession, faction: int) -> int:
	if play == null or play.ship_layer == null:
		return 0
	var total: int = 0
	for other: int in at_war_with(play, faction):
		total += ships(play, other)
	return total


## Fighting hulls of every court at war with this one: the reading the build
## objective weighs against its own `warships`.
static func hostile_warships(play: PlaySession, faction: int) -> int:
	if play == null or play.ship_layer == null:
		return 0
	var total: int = 0
	for other: int in at_war_with(play, faction):
		total += warships(play, other)
	return total


## The purse this court must hold before it may lay the hull it means to build:
## the fleet claim every other spender defers to (issue #484). 0 when it is not
## rebuilding — no war, a fleet that already matches its enemies, or techs that
## open no warship at all.
static func navy_chest(play: PlaySession, faction: int) -> int:
	if play == null:
		return 0
	var ledger: PlayerEconomy = play.ledger_for(faction)
	if ledger == null:
		return 0
	return AiNavy.chest(
		at_war(play, faction), warships(play, faction), hostile_warships(play, faction),
		ledger
	)


## The courts at war with this one, in relation order. Empty when the session
## carries no diplomacy.
static func at_war_with(play: PlaySession, faction: int) -> Array[int]:
	var rivals: Array[int] = []
	if play == null or play.diplomacy == null:
		return rivals
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record != null and record.at_war:
			rivals.append(record.other(faction))
	return rivals


## Squadrons stored in one region, as the passes copy them before planning.
static func region_fleets(play: PlaySession, region: int) -> Array[FleetState]:
	var roster: Array[FleetState] = []
	if play == null or play.ship_layer == null:
		return roster
	roster.assign(play.ship_layer.regions.value(region, []))
	return roster


## Armies stored in one region, as the land pass copies them before planning.
static func region_armies(play: PlaySession, region: int) -> Array[ArmyState]:
	var roster: Array[ArmyState] = []
	if play == null or play.army_layer == null:
		return roster
	roster.assign(play.army_layer.regions.value(region, []))
	return roster


## Armies in one region as the view holds them: the region on screen answers
## from the live marker roster, so a march the court is watching is not planned
## from a stale copy; every other region answers from its stored roster.
static func visible_armies(play: PlaySession, region: int) -> Array[ArmyState]:
	if play == null or play.army_layer == null:
		return []
	if play.army_layer.model != null and play.army_layer.model.region_id == region:
		return play.army_layer.armies
	return region_armies(play, region)


## The squadron with this id in a roster, optionally narrowed to one owner.
static func fleet_by_id(roster: Array, fleet_id: int, owner: int = NO_OWNER) -> FleetState:
	for raw: Variant in roster:
		var fleet: FleetState = raw
		if fleet == null or fleet.id != fleet_id:
			continue
		if owner != NO_OWNER and fleet.owner != owner:
			continue
		return fleet
	return null


## The army with this id in a roster, optionally narrowed to one owner.
static func army_by_id(armies: Array, army_id: int, owner: int = NO_OWNER) -> ArmyState:
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army == null or army.id != army_id:
			continue
		if owner != NO_OWNER and army.owner != owner:
			continue
		return army
	return null


## The squadron with this id stored in `region`, at any owner: a voyage or a
## crossing may be planned across a court's charted water.
static func fleet_in(
	play: PlaySession, region: int, fleet_id: int, owner: int = NO_OWNER
) -> FleetState:
	return fleet_by_id(region_fleets(play, region), fleet_id, owner)


## Rebuilds the on-screen hull markers after a rival moved a squadron, keeping
## the player's selected marker when it still stands. The view never follows a
## rival's sail.
static func refresh_hulls(play: PlaySession) -> void:
	if play == null or play.ship_layer == null or play.ship_layer.model == null:
		return
	var selected: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	play.ship_layer.spawn(
		play.ship_layer.model, 0, 0, -1, false, play.player_faction
	)
	if selected != null:
		play.ship_layer.select(play.ship_layer.ship_for(selected))
