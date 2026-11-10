class_name DossierCopy
extends RefCounted
## Plain-text (and pure) lines for the province dossier: what the roads buy, the
## town's development and the town order's own wording. No visual nodes, so the
## copy is cheap to unit test beside the panel that prints it (REQ-P3-03).

## The town order is a Builder's work, and its two benefits are not obvious.
const TOWN_TIP: String = (
	"A Builder raises the town. Estates that reach the crown only through the"
	+ " town are capped by its level; level 2 or 4 adds town manufacturing."
)


## What the roads actually buy: developed estates that reach the crown. A count
## of tiles tells the player nothing on its own (wiki: capital-and-connectivity).
static func roads(rows: Array[Dictionary]) -> String:
	var developed: int = 0
	var linked: int = 0
	for row: Dictionary in rows:
		if not bool(row["ours"]) or int(row["level"]) <= 0:
			continue
		developed += 1
		if bool(row["connected"]):
			linked += 1
	if developed == 0:
		return "No developed estate yet"
	if linked == 0:
		return "No developed estate reaches the capital"
	return "%d of %d developed estates linked" % [linked, developed]


## The roads row's tooltip: the rule, then what this province holds.
static func roads_tip(province: ProvinceState, rows: Array[Dictionary]) -> String:
	var tiles: int = 0
	for path: Array in province.road_paths:
		tiles += path.size()
	return (
		"An estate on or beside a road, rail or port path to the capital yields"
		+ " its full output and escapes the town cap; one with no such path yields"
		+ " nothing. %d road tiles laid here. %d estates surveyed."
	) % [tiles, rows.size()]


## Live crown link from `LandConnectivity.province_link`. Falls back to the
## setup road plan when the session has not pushed a link yet.
static func crown_roads(province: ProvinceState, crown: Dictionary) -> String:
	if crown.has("linked"):
		var roads: int = int(crown.get("roads", 0))
		var text: String = "%d road tile%s" % [roads, "" if roads == 1 else "s"]
		if bool(crown.get("linked", false)):
			return "%s · linked to the crown" % text
		var gap: int = int(crown.get("distance", -1))
		if gap > 0:
			return "%s · no road to the crown (%d tile%s away)" % [
				text, gap, "" if gap == 1 else "s"
			]
		return "%s · no road to the crown" % text
	var planned: int = 0
	for path: Array in province.road_paths:
		planned += path.size()
	return "%d tiles" % planned if planned > 0 else "—"


## Town development, which caps the estates that reach the crown through it.
static func town(province: ProvinceState) -> String:
	if province == null or not province.has_town():
		return "—"
	var level: int = province.town_level()
	if level >= CivilianWorkPlan.MAX_TOWN:
		return "Level %d · full" % level
	return "Level %d" % level
