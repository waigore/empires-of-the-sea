class_name MapPlayColonies
extends RefCounted
## The colony ledger's one map hook: both charts assembled with the crown's
## diplomacy record into the reading [ColonyLedger] projects (wiki: diplomacy
## § GP–Tribe Rules; DR-20261117-02). Presentation only — the record is the
## session's own and the land is the chart's, so the sheet reads the colonies the
## rule already holds (REQ-P3-02).


## The world's colonies as the player's crown may know them. A session with no
## chart reads an empty roll rather than inventing a colony.
static func snapshot(play: PlaySession) -> Dictionary:
	if play == null or play.world == null:
		return ColonyLedger.snapshot([] as Array[Dictionary], null, MapModel.NO_ID)
	var regions: Array[Dictionary] = []
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		regions.append({"region": region, "model": model})
	return ColonyLedger.snapshot(regions, play.diplomacy, play.player_faction)
