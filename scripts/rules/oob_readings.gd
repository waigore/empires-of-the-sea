class_name OobReadings
extends RefCounted
## What each court can see of every court's order of battle (wiki:
## fog-and-exploration § Explorer vs Spy, § Order Visibility Requirements;
## military-armies § Docket; DR-20261110-21, DR-20261112-09).
##
## A court reads another court's garrison and hulls only across ground and water
## its own chart holds: its own forces everywhere, a foreign army standing in a
## charted province, a foreign squadron in a charted sea zone or a charted port,
## and a regiment aboard a squadron wherever that squadron is seen. Province
## counts are published and never obfuscated (fog § Province ownership intel), so
## only the two unit terms are read here.
##
## Pure maths over the charts and the rosters — no nodes, so the diplomacy phase,
## a save-free suite and the tests share one implementation (REQ-P2-03,
## REQ-P3-03).


## Per court: `{"regiments": {faction: count}, "ships": {faction: count}}`, the
## docket that court has charted. Every court is present, even with no forces
## seen, so a caller never has to guess a missing reading.
static func by_court(
	charts: CourtCharts,
	armies: MapRegionTable,
	fleets: MapRegionTable,
	courts: Array[int]
) -> Dictionary:
	var out: Dictionary = {}
	for reader: int in courts:
		out[reader] = {"regiments": {}, "ships": {}}
	if out.is_empty():
		return out
	var carriers: Dictionary = _fleets_by_id(fleets)
	for region: int in armies.region_ids():
		var roster: Array[ArmyState] = []
		roster.assign(armies.value(region, []))
		for army: ArmyState in roster:
			if army == null:
				continue
			for reader: int in courts:
				if _sees_army(charts, reader, region, army, carriers):
					_credit(out[reader], "regiments", army.owner, army.count())
	for region: int in fleets.region_ids():
		var roster: Array[FleetState] = []
		roster.assign(fleets.value(region, []))
		for fleet: FleetState in roster:
			if fleet == null:
				continue
			for reader: int in courts:
				if _sees_fleet(charts, reader, region, fleet):
					_credit(out[reader], "ships", fleet.owner, fleet.ship_count())
	return out


## Hulls index their instance id, so a regiment aboard one rides with it.
static func _fleets_by_id(fleets: MapRegionTable) -> Dictionary:
	var by_id: Dictionary = {}
	for raw: Variant in fleets.values():
		var roster: Array[FleetState] = []
		roster.assign(raw)
		for fleet: FleetState in roster:
			if fleet != null:
				by_id[fleet.id] = fleet
	return by_id


## A court always knows its own standard; a foreign one only on charted ground.
static func _sees_army(
	charts: CourtCharts, reader: int, region: int, army: ArmyState, carriers: Dictionary
) -> bool:
	if army.owner == reader:
		return true
	if army.is_embarked():
		var carrier: FleetState = carriers.get(army.embarked_fleet, null)
		if carrier == null:
			return false
		return _sees_fleet(charts, reader, region, carrier)
	return _knows_province(charts, reader, region, army.province)


## A squadron is seen in charted water at sea and in a charted port ashore.
## Its own court sees it everywhere.
static func _sees_fleet(
	charts: CourtCharts, reader: int, region: int, fleet: FleetState
) -> bool:
	if fleet.owner == reader:
		return true
	if fleet.is_at_sea():
		return _knows_zone(charts, reader, region, fleet.sea_zone)
	return _knows_province(charts, reader, region, fleet.province)


## Charted ground: one tile at `fogged` or better. A court with no chart for the
## region (a fixture, or a world never charted) reads the published docket.
static func _knows_province(
	charts: CourtCharts, reader: int, region: int, province: int
) -> bool:
	if charts == null:
		return true
	var view: VisibilityModel = charts.model_for(reader, region)
	return view == null or view.is_province_known(province)


## Charted water: one tile of the zone at `fogged` or better, as a voyage needs.
static func _knows_zone(
	charts: CourtCharts, reader: int, region: int, zone: int
) -> bool:
	if charts == null:
		return true
	if charts.model_for(reader, region) == null:
		return true
	return charts.knows_zone(reader, region, zone)


static func _credit(docket: Dictionary, term: String, faction: int, count: int) -> void:
	var counts: Dictionary = docket[term]
	counts[faction] = int(counts.get(faction, 0)) + count
