class_name CivilianTurnPass
extends RefCounted
## Build/Work pass across every region: looking at another map must not pause
## the empire. Kept out of `CivilianLayer` so the layer stays a marker view
## (REQ-P3-01; wiki: map-topology, civilian-units § Merchant).


## Advances every region's crews and works. Returns the work reports for the
## caller. Every crown resolves against that crown's own chart, so a rival's
## finished `explore` reveals its fog and never the player's (DR-20261110-21).
## `purses` maps owner -> ledger, so a rival's deed is charged to that rival.
static func resolve(
	layer: CivilianLayer,
	world: WorldMap,
	charts: CourtCharts,
	purses: Dictionary = {}
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	if layer == null or world == null:
		return reports
	for index in world.region_count():
		var region_units: Array[CivilianState] = _roster_for(layer, index)
		CivilianMovement.begin_turn(region_units)
		var region_works: LandWorks = layer.works_regions.value(index, null)
		if region_works == null:
			continue
		# Owners in ascending order, so two runs of one state report alike.
		var owners: Array[int] = []
		for unit: CivilianState in region_units:
			if unit != null and not owners.has(unit.owner):
				owners.append(unit.owner)
		owners.sort()
		for owner: int in owners:
			var crew: Array[CivilianState] = []
			for unit: CivilianState in region_units:
				if unit != null and unit.owner == owner:
					crew.append(unit)
			var view: VisibilityModel = (
				charts.model_for(owner, index) if charts != null else null
			)
			var purse: PlayerEconomy = purses.get(owner, null) as PlayerEconomy
			for report: Dictionary in CivilianWork.resolve_turn(
				world.region(index), crew, region_works, view, purse
			):
				report["region"] = index
				reports.append(report)
	return reports


## The live array for a region: the on-screen roster is the same object the
## layer draws from, so edits must land in it rather than a copy.
static func _roster_for(layer: CivilianLayer, index: int) -> Array[CivilianState]:
	if layer.model != null and index == layer.model.region_id:
		return layer.units
	var roster: Array[CivilianState] = []
	roster.assign(layer.regions.value(index, []))
	return roster
