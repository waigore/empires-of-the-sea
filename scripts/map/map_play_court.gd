class_name MapPlayCourt
extends RefCounted
## One reader for which courts run a planner this session, where the crown's
## seat stands, and whether a court is at war — so every rival pass asks the
## same question once instead of carrying its own copy (REQ-P2-03, REQ-P3-01,
## REQ-P3-02).
##
## A pass needs three kinds of answer before it plans: which courts run a
## planner this session (this home), what each already holds ([MapPlayCourtHoldings]),
## and where a named army or squadron stands ([MapPlayCourtRoster]). Pure state
## reads: nothing here issues an order or changes a roster.


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
