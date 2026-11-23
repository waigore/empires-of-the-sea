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
## once. Pure state reads and the one trace row an army order records: nothing
## here issues an order or changes a roster.

## `-1` reads as "any owner" for the roster lookups.
const NO_OWNER: int = -1


## The chart the crown's seat stands on, its province there and that chart's
## model: `{region, province, model}` (wiki: capital-and-connectivity § Capital;
## map-topology § two regions). Read off the world, never off the chart on
## screen: a chart can show a colony with no seat on it, and a province id means
## a different province on each chart (wiki: world-model-identity). A seat-scoped
## order — a hire, a muster, a launch — lands at `province` on `region`, or
## nowhere when `province` is NO_ID because the crown's capital is not in hand.
static func crown_seat(play: PlaySession) -> Dictionary:
	var empty: Dictionary = {
		"region": MapModel.NO_ID, "province": MapModel.NO_ID, "model": null,
	}
	if play == null or play.world == null:
		return empty
	var region: int = FactionCatalog.region_of(play.player_faction)
	var model: MapModel = play.world.region(region)
	if model == null:
		return empty
	return {
		"region": region,
		"province": play.world.capital_province_of(region, play.player_faction),
		"model": model,
	}


## The Great Powers that run a planner for this session, in catalog order. The
## human court is skipped unless the full-AI observer seats it like any rival
## (wiki: game-setup § Human/AI slot assignment; docs/ai-observer.md), and the
## `AiControl` gate keeps a noop or bench crown inert.
##
## Auto mode asks for the same seat one pass at a time: `ai_stage_faction` names
## the one court a pass may plan, so the paced driver can run the crown's own
## orders without the rival passes planning them a second time
## (wiki: auto-mode § Drawing on the same planners).
##
## A fallen crown plans nothing: a seat with no Old or New World province is out
## (wiki: capital-and-connectivity § Great Power fall; `CampaignDefeat`: an AI
## fall removes that crown and the campaign continues). The read is the
## observer's own `alive` row, so the shared gate and the observer cannot
## disagree — a court that lost its last province stops planning instead of
## burning a pass a turn and pricing coverage rows no living court ran
## (issue #1136).
static func planning_factions(play: PlaySession) -> Array[int]:
	var factions: Array[int] = []
	if play == null:
		return factions
	var staged: int = play.ai_stage_faction
	for faction: int in FactionCatalog.great_power_ids():
		if staged != MapModel.NO_ID and faction != staged:
			continue
		if faction == play.player_faction and not play.observer_mode:
			# The crown plans only when Auto hands it the seat for this pass.
			if not (play.auto_active and staged == play.player_faction):
				continue
		if not AiControl.plans(play, faction):
			continue
		if not holds_land(play, faction):
			continue
		factions.append(faction)
	return factions


## True while the crown still holds a province in either world: the observer's
## own `alive` read, shared here so the planner gate cannot drift from the row
## the standing prints (issue #1136).
static func holds_land(play: PlaySession, faction: int) -> bool:
	if play == null or play.world == null:
		return false
	return (
		play.world.owned_provinces(WorldMap.OLD_WORLD, faction)
		+ play.world.owned_provinces(WorldMap.NEW_WORLD, faction)
	) > 0


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


## The published order of battle every map read shares: each crown's land
## strength and its hull total. The court panel, the calendar's declared winner
## and the rival pass all read this one pass, so the published power score
## cannot drift between them (wiki: diplomacy § Great Power power score;
## REQ-P2-03, REQ-P3-02).
static func public_orders(play: PlaySession) -> Dictionary:
	return {"strength": public_strength(play), "ships": public_ships(play)}


## Land strength per faction over the whole roster: FPN + FPM over every army it
## holds in both regions, without the general medal multiplier (wiki: diplomacy
## § Great Power power score).
static func public_strength(play: PlaySession) -> Dictionary:
	var strength: Dictionary = {}
	if play == null or play.army_layer == null:
		return strength
	for raw: Variant in play.army_layer.regions.values():
		var stored: Array[ArmyState] = []
		stored.assign(raw)
		for army: ArmyState in stored:
			if army == null:
				continue
			strength[army.owner] = (
				float(strength.get(army.owner, 0.0)) + army.strength()
			)
	return strength


## Hull count of every Great Power, the term the power score multiplies.
static func public_ships(play: PlaySession) -> Dictionary:
	var ships: Dictionary = {}
	if play == null or play.ship_layer == null:
		return ships
	for faction: int in FactionCatalog.great_power_ids():
		ships[faction] = play.ship_layer.hull_count_all(faction)
	return ships


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
##
## The yield valve (issue #603, issue #1275): the yard stands down past the
## escalation bar while a line is due — the hull chest then pins the purse the
## muster's own material row needs — and the chest resumes as published once
## the line is no longer due (the fill the stand-down freed has closed the
## muster) or once the shortfall starts shrinking (the stall's own low water,
## so a fill the court is winning never counts as a stall). Without the
## line-due gate the valve is one-way: the chest releases, the freed purse
## funds no other chest, the yard is never reached and the court stays
## fleetless for the whole campaign.
static func navy_chest(play: PlaySession, faction: int) -> int:
	if play == null:
		return 0
	var ledger: PlayerEconomy = play.ledger_for(faction)
	if ledger == null:
		return 0
	var config: AiConfig = AiProfile.for_court(faction, play.map_seed, play.ensure_ai().profiles)
	var at_war_now: bool = at_war(play, faction)
	# The yard's chest re-routes like the war chest (issue #603): a court that
	# has stalled on `navy.build` past the escalation bar stops holding the
	# purse for a hull it cannot fill — the wiki's own re-route reading: the
	# cash floor and the reachable hull chest remain, so a chest the purse can
	# already fill is the fleet's (the yard lays it) and one it cannot fill
	# stands down while every other spender leads again (issue #878).
	var stalled: int = (
		AiDeferral.stall_for(play.ai.deferrals, faction, "navy.build")
		if play.ai != null else 0
	)
	var low: int = (
		AiDeferral.low_water_for(play.ai.deferrals, faction, "navy.build")
		if play.ai != null else 0
	)
	var price: int = AiNavy.price(ledger, hull_types(play, faction))
	var shortfall: int = maxi(price - ledger.treasury, 0)
	# The storm chest rides the muster's own read (issue #1381): a court
	# banking for the host its thinnest wall prices holds a war chest too.
	var storm: int = MapPlayArmyMusterAi.storm_chest(
		play, play.model, faction, regiments(play, faction)
	)
	# The host is regiments; the muster floor prices the chest (issue #1381).
	var muster_due: bool = AiArmyReinforce.muster_floor(
		config, ledger, regiments(play, faction), at_war_now, storm
	) > 0
	var yields: bool = (
		# A regiment is due: the hull chest is the purse the muster's row
		# needs, so a stalled fill stands down behind it (issue #603).
		muster_due
		and stalled >= maxi(config.parameter("ledger.escalate_turns"), 1)
		# The fill is not moving: the shortfall this turn is still the stall's
		# best gap. A fill the court is winning keeps its chest reachable.
		and shortfall >= low
		# The purse has reached the price: the valve releases and the chest
		# reads as published — the yard lays the hull it banked for.
		and ledger.treasury < price
	)
	return AiNavy.chest(
		at_war_now, warships(play, faction), hostile_warships(play, faction),
		ledger, hull_types(play, faction), yields
	)


## Hull types this court flies or has flown — craft its yard may rebuild
## without the unlocking tech, kept after the last of that type is lost
## (issue #484).
static func hull_types(play: PlaySession, faction: int) -> Array[String]:
	if play == null or play.ship_layer == null:
		return []
	var owned: Array[FleetState] = []
	for region: int in play.ship_layer.regions.region_ids():
		for raw: Variant in play.ship_layer.regions.value(region, []):
			var fleet: FleetState = raw
			if fleet != null and fleet.owner == faction:
				owned.append(fleet)
	var flown: Array[String] = ShipEconomy.types_flown(owned)
	var ledger: PlayerEconomy = play.ledger_for(faction)
	if ledger == null:
		return flown
	ledger.note_shipcraft(flown)
	for type_id: String in ledger.shipcraft:
		if not flown.has(type_id):
			flown.append(type_id)
	return flown

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


## The one row every rival land order records: the court, the kind, the standard
## and the ground it stands on, named for the trace's readers. The army pass, its
## muster and the invasion pass all spell it here, so a new key lands once
## (wiki: turn-trace-interpretation).
static func army_trace(
	model: MapModel, faction: int, kind: String, army: int, province: int
) -> Dictionary:
	return {
		"faction": faction,
		"kind": kind,
		"army": army,
		"province": province,
		"province_name": model.province_name(province),
		"region": model.region_id,
	}


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
