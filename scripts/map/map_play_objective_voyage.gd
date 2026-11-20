class_name MapPlayObjectiveVoyage
extends RefCounted
## The expedition reading the objective ledger prices (docs/ai.md; issue #491 T2,
## #497, #602): idle hulls, a ready Explorer, and a voyage already afloat,
## abroad, or stranded. `MapPlayObjectiveReadings` owns the ledger; this owner
## answers every voyage question, so the allocate pass and the turn trace never
## drift from one hull reading (REQ-P2-03, REQ-P3-01, REQ-P3-03).


## The expedition: the hulls and the Explorer that could still sail, and the
## voyage already under way or stranded.
static func reading(play: PlaySession, faction: int) -> Dictionary:
	return {
		"idle_hulls": _idle_hulls(play, faction),
		"explorer_ready": _explorer_ready(play, faction),
		"voyage_afloat": _voyage_afloat(play, faction),
		"voyage_abroad": _voyage_abroad(play, faction),
		"voyage_stranded": _voyage_stranded(play, faction),
	}


## Squadrons that could take an expedition: afloat, un-moved, no troops and no
## colonists aboard. The same hull reading the colonisation planner sails.
static func _idle_hulls(play: PlaySession, faction: int) -> int:
	if play.ship_layer == null:
		return 0
	var total: int = 0
	for region: int in play.ship_layer.regions.region_ids():
		total += VoyageRead.free_count(
			MapPlayCourt.region_fleets(play, region), faction
		)
	return total


## An idle Explorer of this court at home: the colonist the next train slot
## musters (issue #491 T2).
static func _explorer_ready(play: PlaySession, faction: int) -> bool:
	if play.civilian_layer == null:
		return false
	var home: int = FactionCatalog.region_of(faction)
	if home < 0:
		return false
	return VoyageRead.idle_colonist(
		play.civilian_layer.regions.value(home, []), faction, "explorer"
	) != null


## True while an expedition of this court is already at sea (a protected claim
## in T2, #497).
static func _voyage_afloat(play: PlaySession, faction: int) -> bool:
	if play.ship_layer == null:
		return false
	for region: int in play.ship_layer.regions.region_ids():
		if VoyageRead.carrying(
			MapPlayCourt.region_fleets(play, region), faction
		) != null:
			return true
	return false


## True while a colonist of this court already stands on the far shore (its
## landing is the voyage's own progress, not a missing Explorer): the child that
## musters a new one is not blocked, and the parent prices the voyage instead
## (#497). A court with a civilian in the other region has nothing left to
## muster either — `CivilianMuster.muster_port` holds the gate shut until
## that colonist leaves or works.
static func _voyage_abroad(play: PlaySession, faction: int) -> bool:
	if play.civilian_layer == null:
		return false
	var home: int = FactionCatalog.region_of(faction)
	if home < 0:
		return false
	for region: int in play.civilian_layer.regions.region_ids():
		if region == home:
			continue
		for raw: Variant in play.civilian_layer.regions.value(region, []):
			var unit: CivilianState = raw
			if unit != null and unit.owner == faction:
				return true
	return false


## True while an Explorer of this court stands ashore in a region its crown holds
## no ground in — no province and no purchased deed. It founds nothing (a Builder
## needs crown land) and cannot board again — boarding needs a squadron in port
## and docking needs a crown port — so the expedition can never sail on: the
## ledger reads the aim blocked with that reason instead of funding a voyage the
## planner will not order (issue #602).
##
## The expedition the court paid for is ashore with no crown land: the reading
## the objective ledger prints (`voyage_stranded`) and the claim-crew carve-out
## in the hire ladder both share, so the aim and the hire cannot disagree
## (issue #1139; #602).
static func claim_stranded(play: PlaySession, faction: int) -> bool:
	return _voyage_stranded(play, faction)


## The claim is what keeps it alive (#1127): a Merchant still waiting at home
## sails next, and the deeds it signs are crown land a Builder lands on, so the
## aim is not stranded while that crew stands ready. A Merchant or Builder ashore
## is left to #497's reading — its work is the voyage's progress.
static func _voyage_stranded(play: PlaySession, faction: int) -> bool:
	if play.civilian_layer == null or play.world == null:
		return false
	var home: int = FactionCatalog.region_of(faction)
	if home < 0:
		return false
	for region: int in play.civilian_layer.regions.region_ids():
		if region == home:
			continue
		var model: MapModel = play.world.region(region)
		if model == null or VoyageRead.holds_ground(model, faction):
			continue
		if not _explorer_ashore(play, region, faction):
			continue
		if _claim_crew_ready(play, home, region, faction):
			# The claim has a voyage left to sail.
			return false
		return true
	return false


## True when the claim the voyage would carry next still has a step: no Merchant
## of this court is ashore there yet, and one stands idle at home (the crew the
## muster holds at the harbour). A claim already sailed, and a court with no
## Merchant to send, leave the expedition where #602 reads it.
static func _claim_crew_ready(
	play: PlaySession, home: int, region: int, faction: int
) -> bool:
	if int(CivilianMuster.abroad_counts(play, region, faction).get("merchant", 0)) > 0:
		return false
	return CivilianMuster.muster_colonist(
		CivilianMuster.roster(play, home), faction, "merchant"
	) >= 0


## True when an Explorer of this court stands ashore (not embarked) in a region.
static func _explorer_ashore(play: PlaySession, region: int, faction: int) -> bool:
	for raw: Variant in CivilianMuster.roster(play, region):
		var unit: CivilianState = raw
		if unit == null or unit.owner != faction:
			continue
		if unit.type_id == "explorer" and not unit.is_embarked():
			return true
	return false
