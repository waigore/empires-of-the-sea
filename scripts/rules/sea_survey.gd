class_name SeaSurvey
extends RefCounted
## The sea reading: every sea zone the crown has a sail under its eye in, what
## stands there and whether the turn resolves a battle in that water
## (wiki: ships-and-naval § Missions and Movement, § Naval Combat Resolution).
## Pure read — the fight test is `NavalCombat.contested_zones` and every weight
## is `NavalStrength`/`NavalCombat.side_strength`, so the chart can never name a
## fight or a figure the resolver would not strike (REQ-P2-03, REQ-P3-03).
## `crown_view` is the chart's own answer (`drawn`, `read`) — the same callable
## the markers carry — so a rival the fog withholds, or one the crown has not
## watched across a turn, contributes neither a plaque nor a number
## (wiki: ships-and-naval § Sighted strength).

## Nothing but the crown's own sails here (a rival in the peace may be named).
const BAND_QUIET: String = "quiet"
## A rival's sails under the peace; no battle resolves between us.
const BAND_WATCHED: String = "watched"
## A hostile sail in water the crown does not hold: the battle, if any, is not
## ours to fight.
const BAND_STANDOFF: String = "standoff"
## A hostile sail shares the water with ours and the turn resolves a battle
## here; every hostile weight is read, so the odds are the court's to weigh.
const BAND_CONTESTED: String = "contested"
## The same fight, with a hostile weight the crown has not read: a battle
## resolves and her strength cannot be counted yet.
const BAND_BLIND: String = "blind"

const BANDS: Array[String] = [
	BAND_QUIET, BAND_WATCHED, BAND_STANDOFF, BAND_CONTESTED, BAND_BLIND
]

const BAND_LABELS: Dictionary = {
	BAND_QUIET: "Our water — no hostile sail",
	BAND_WATCHED: "A rival's sails, no war",
	BAND_STANDOFF: "Hostile water we do not hold",
	BAND_CONTESTED: "A battle resolves at turn end",
	BAND_BLIND: "A battle resolves — her weight unread",
}


## One pass over the region's roster. `fleets` is the roster of the chart on
## screen; a squadron in port fights nothing, so ports contribute no row.
static func snapshot(
	model: MapModel,
	fleets: Array,
	visibility: VisibilityModel = null,
	player: int = MapModel.NO_ID,
	hostile: Callable = Callable(),
	crown_view: Callable = Callable()
) -> Dictionary:
	var result: Dictionary = {
		"zones": [] as Array[Dictionary],
		"counts": _empty_counts(),
		"totals": {"zones": 0, "hulls": 0, "strength": 0.0, "contested": 0, "blind": 0},
	}
	if model == null:
		return result
	var rows: Dictionary = {}
	var drawn: Array[FleetState] = []
	for fleet: FleetState in fleets:
		if fleet == null or not fleet.is_at_sea() or not fleet.is_afloat():
			continue
		var own: bool = fleet.owner == player
		var read: bool = true
		if not own:
			if not _drawn(crown_view, fleet):
				continue
			read = _read(crown_view, fleet)
		drawn.append(fleet)
		var row: Dictionary = rows.get(fleet.sea_zone, _empty_row())
		if own:
			(row["own"] as Array).append(fleet)
		else:
			(row["foe"] as Array).append(fleet)
			if not read:
				row["unread"] = int(row["unread"]) + 1
			if not (row["courts"] as Array).has(fleet.owner):
				(row["courts"] as Array).append(fleet.owner)
			if _hostile(hostile, player, fleet.owner):
				row["hostile"] = true
		rows[fleet.sea_zone] = row
	var fights: Array[int] = NavalCombat.contested_zones(drawn, hostile)
	var zones: Array[int] = []
	for raw_zone: Variant in rows.keys():
		zones.append(int(raw_zone))
	zones.sort()
	for zone_id: int in zones:
		var entry: Dictionary = _entry(
			model, zone_id, rows[zone_id], fights.has(zone_id), visibility
		)
		_add_totals(result, entry)
		(result["zones"] as Array).append(entry)
	return result


## Band of one zone, from the facts a battle reads (who stands here, whether
## they are at war) plus what the crown may know of the weight of the sail she
## would fight. A fight between two rivals in water the crown does not hold
## reads as hostile water too: the crown is not in it, whatever it costs them.
## A crown squadron standing in that water is a spectator, not a belligerent —
## the resolver excludes a court hostile to nobody there — so `engaged` is what
## the close strikes, never merely "a sail of ours is in the zone".
static func band_for(
	own: bool, foe: bool, hostile_here: bool, unread: int, fight: bool,
	engaged: bool = true
) -> String:
	if fight:
		if not own:
			return BAND_STANDOFF
		if not engaged:
			return BAND_WATCHED
		return BAND_BLIND if unread > 0 else BAND_CONTESTED
	if foe and hostile_here:
		return BAND_STANDOFF
	if foe:
		return BAND_WATCHED
	return BAND_QUIET


static func band_label(band: String) -> String:
	return String(BAND_LABELS.get(band, BAND_LABELS[BAND_QUIET]))


## The hover line — the reading in the words the dossier and the store use, so a
## player who reads this one line knows the water, the station and the fight.
static func summary_text(entry: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append(_our_line(entry))
	var station: String = String(entry.get("station_text", ""))
	if not station.is_empty():
		parts.append(station)
	var foe: String = _foe_line(entry)
	if not foe.is_empty():
		parts.append(foe)
	if bool(entry.get("fight", false)):
		parts.append(
			"a battle resolves here at turn end"
			if bool(entry.get("own_engaged", false))
			else "two rivals fight here at turn end"
		)
	return " · ".join(parts)


# --- rows --------------------------------------------------------------------


static func _empty_row() -> Dictionary:
	return {"own": [], "foe": [], "unread": 0, "courts": [], "hostile": false}


static func _entry(
	model: MapModel,
	zone_id: int,
	row: Dictionary,
	fights: bool,
	visibility: VisibilityModel
) -> Dictionary:
	var own: Array = row["own"]
	var foe: Array = row["foe"]
	var unread: int = int(row["unread"])
	var hostile_here: bool = bool(row["hostile"])
	# The close fights a court only against someone it is at war with. A crown
	# squadron beside two rivals fighting each other is a spectator: the
	# resolver names no belligerent of ours, so the reading must not either.
	var engaged: bool = fights and not own.is_empty() and hostile_here
	var entry: Dictionary = {
		"id": zone_id,
		"name": model.sea_zone_name(zone_id),
		# The crown knows the water its own hulls float in, even on a chart whose
		# reveal pass has not yet run over it: a fleet never sails blind.
		"charted": (
			VisibilityModel.Level.FULLY_VISIBLE
			if not own.is_empty()
			else _charted(model, zone_id, visibility)
		),
		"anchor": _anchor(model, zone_id, visibility),
		"own_squadrons": own.size(),
		"own_hulls": NavalCombat.side_hull_count(own),
		"own_strength": NavalCombat.side_strength(own),
		"stations": _stations(own),
		"foe_squadrons": foe.size(),
		"foe_hulls": NavalCombat.side_hull_count(foe),
		# A rival the crown has not read weighs in with nothing, and a partial
		# sum would read as her whole strength: print no figure at all.
		"foe_strength": 0.0 if unread > 0 else NavalCombat.side_strength(foe),
		"foe_unread": unread,
		"foe_courts": _court_names(row["courts"]),
		"fight": fights,
		"own_engaged": engaged,
		"band": band_for(
			not own.is_empty(), not foe.is_empty(), hostile_here, unread, fights, engaged
		),
	}
	entry["station_text"] = _station_text(entry)
	entry["summary"] = summary_text(entry)
	return entry


static func _add_totals(result: Dictionary, entry: Dictionary) -> void:
	var counts: Dictionary = result["counts"]
	var band: String = String(entry["band"])
	counts[band] = int(counts[band]) + 1
	var totals: Dictionary = result["totals"]
	totals["zones"] = int(totals["zones"]) + 1
	totals["hulls"] = int(totals["hulls"]) + int(entry["own_hulls"])
	totals["strength"] = float(totals["strength"]) + float(entry["own_strength"])
	if bool(entry["fight"]):
		totals["contested"] = int(totals["contested"]) + 1
	if String(entry["band"]) == BAND_BLIND:
		totals["blind"] = int(totals["blind"]) + 1


## Distinct stations the crown's squadrons hold here, in roster order: the
## muster roll the player already reads, read again on the water.
static func _stations(own: Array) -> Array[String]:
	var labels: Array[String] = []
	for fleet: FleetState in own:
		if fleet.mission == FleetState.Mission.NONE:
			continue
		var label: String = FleetMissions.label(fleet.mission)
		if not labels.has(label):
			labels.append(label)
	return labels


## Two stations fit a slip's second line; a third reads `+N`, never hidden.
static func _station_text(entry: Dictionary) -> String:
	var stations: Array = entry.get("stations", [])
	if stations.is_empty():
		return "No station" if int(entry["own_squadrons"]) > 0 else ""
	var shown: PackedStringArray = []
	for i in mini(stations.size(), 2):
		shown.append(String(stations[i]))
	if stations.size() > 2:
		shown.append("+%d" % (stations.size() - 2))
	return " · ".join(shown)


static func _our_line(entry: Dictionary) -> String:
	var squadrons: int = int(entry["own_squadrons"])
	if squadrons <= 0:
		return "No sail of ours"
	return "Ours %d squadron%s · %d hull%s · %s" % [
		squadrons, _s(squadrons), int(entry["own_hulls"]), _s(int(entry["own_hulls"])),
		_one(entry["own_strength"]),
	]


static func _foe_line(entry: Dictionary) -> String:
	var squadrons: int = int(entry["foe_squadrons"])
	if squadrons <= 0:
		return ""
	var courts: Array = entry.get("foe_courts", [])
	var who: String = "A rival"
	if courts.size() == 1:
		who = String(courts[0])
	elif courts.size() > 1:
		who = "Rivals"
	var weight: String = (
		"weight unread" if int(entry["foe_unread"]) > 0 else _one(entry["foe_strength"])
	)
	return "%s %d squadron%s · %d hull%s · %s" % [
		who, squadrons, _s(squadrons), int(entry["foe_hulls"]), _s(int(entry["foe_hulls"])),
		weight,
	]


static func _court_names(owners: Array) -> Array[String]:
	var names: Array[String] = []
	for raw: Variant in owners:
		var owner_id: int = int(raw)
		if FactionCatalog.has_faction(owner_id):
			names.append(FactionCatalog.name_of(owner_id))
	return names


# --- chart -------------------------------------------------------------------


## Best knowledge the crown holds of a zone's water: a zone charted at all is
## remembered, so its plate draws at the charted alpha like a province slip.
static func _charted(
	model: MapModel, zone_id: int, visibility: VisibilityModel
) -> int:
	if visibility == null:
		return VisibilityModel.Level.FULLY_VISIBLE
	var data: SeaZoneState = model.sea_zone_data(zone_id)
	if data == null:
		return VisibilityModel.Level.UNKNOWN
	var best: int = VisibilityModel.Level.UNKNOWN
	for tile: Vector2i in data.tiles:
		var level: int = visibility.level_at(tile.x, tile.y)
		if level == VisibilityModel.Level.FULLY_VISIBLE:
			return level
		best = maxi(best, level)
	return best


## Plate anchor: the zone's water tile nearest its centre that the crown charts
## brightest — a centre is an average of water and can fall on a shoal or an
## island, and a plaque must never print over ground it does not describe.
static func _anchor(
	model: MapModel, zone_id: int, visibility: VisibilityModel
) -> Vector2i:
	var data: SeaZoneState = model.sea_zone_data(zone_id)
	if data == null or data.tiles.is_empty():
		return Vector2i.ZERO
	var center: Vector2 = data.center
	var best: Vector2i = data.tiles[0]
	var best_score: float = -INF
	for tile: Vector2i in data.tiles:
		var level: int = VisibilityModel.Level.FULLY_VISIBLE
		if visibility != null:
			level = visibility.level_at(tile.x, tile.y)
		# Known water first, then the tile nearest the centre: the score is the
		# level less the distance, so a charted tile always outranks a fogged one.
		var score: float = float(level) * 1000.0 - Vector2(tile).distance_squared_to(center)
		if score > best_score:
			best_score = score
			best = tile
	return best


# --- knowledge ---------------------------------------------------------------


## Whether the crown's chart carries a rival at all. A hand-built lens with no
## filter draws every squadron, exactly as a marker with no `crown_view` does.
static func _drawn(crown_view: Callable, fleet: FleetState) -> bool:
	if not crown_view.is_valid():
		return true
	var view: Dictionary = crown_view.call(fleet)
	return bool(view.get("drawn", true))


static func _read(crown_view: Callable, fleet: FleetState) -> bool:
	if not crown_view.is_valid():
		return true
	var view: Dictionary = crown_view.call(fleet)
	return bool(view.get("read", true))


## Without a hostile test the resolver treats every pair as hostile, so the
## reading does too (never a quieter answer than the battle it forecasts).
static func _hostile(hostile: Callable, a: int, b: int) -> bool:
	if not hostile.is_valid():
		return true
	if a == MapModel.NO_ID or b == MapModel.NO_ID:
		return false
	return bool(hostile.call(a, b))


static func _empty_counts() -> Dictionary:
	var counts: Dictionary = {}
	for band: String in BANDS:
		counts[band] = 0
	return counts


static func _one(value: Variant) -> String:
	return "%.1f" % float(value)


static func _s(count: int) -> String:
	return "" if count == 1 else "s"
