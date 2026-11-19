class_name ProvinceLedger
extends RefCounted
## The crown's provinces: every province it holds, in both charts, with what
## each one is worth and what it lacks (wiki: world-model § Provinces and Tiles;
## DR-20261115-09). Pure read-only projection — it reads the chart, the crown
## link the province dossier prints, the estates ledger's own rows and the
## army rosters, and never orders a work, a march or a spend (REQ-P3-02,
## REQ-P3-03).
##
## No number here is recomputed: the garrison is `ArmyForce.side_strength` and
## the yield is the estates ledger's own `output`, so a row can never print a
## figure the turn would not use (REQ-P2-03).

## The reading's own filters: what a crown asks of its holdings every turn.
const FILTER_ALL: String = "all"
const FILTER_CUT: String = "cut_off"
const FILTER_UNGARRISONED: String = "ungarrisoned"
const FILTER_WORKS: String = "works"
const FILTERS: Array[String] = [
	FILTER_ALL, FILTER_CUT, FILTER_UNGARRISONED, FILTER_WORKS
]

const NO_ID: int = -1


## Whole-empire snapshot in reading order. `regions` is one entry per chart:
## {region, model, armies, estates, links} — the armies the crown holds there,
## the estates ledger's snapshot for that chart, and the crown link per
## province id (`LandConnectivity.province_link`). A chart with no model is
## skipped, so a one-region world reads as one heading.
static func snapshot(regions: Array[Dictionary], owner: int) -> Dictionary:
	var rows: Array[Dictionary] = []
	var counts: Dictionary = {FILTER_CUT: 0, FILTER_UNGARRISONED: 0, FILTER_WORKS: 0}
	for entry: Dictionary in regions:
		var model := entry.get("model") as MapModel
		if model == null:
			continue
		var region: int = int(entry.get("region", model.region_id))
		var armies: Array = entry.get("armies", [])
		var estates: Dictionary = entry.get("estates", {})
		var links: Dictionary = entry.get("links", {})
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != owner:
				continue
			var row: Dictionary = _row(model, province, region, armies, estates, links)
			rows.append(row)
			for flag: String in row["flags"]:
				counts[flag] = int(counts.get(flag, 0)) + 1
	rows.sort_custom(_before)
	return {
		"rows": rows,
		"groups": LedgerRows.group(rows),
		"counts": counts,
		"total": rows.size(),
	}


## Rows narrowed to one chart and one filter, grouped under their chart.
static func groups(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> Array[Dictionary]:
	return LedgerRows.groups(data, region_key, matches.bind(filter_key))


static func count(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> int:
	return LedgerRows.count(data, region_key, matches.bind(filter_key))


## How many provinces each filter would show inside one chart, so a chip can
## carry its own tally and a zero stays legible rather than hidden.
static func filter_counts(data: Dictionary, region_key: String) -> Dictionary:
	return LedgerRows.counts(data, region_key, FILTERS, matches)


static func matches(row: Dictionary, filter_key: String) -> bool:
	return LedgerRows.flags_match(row, filter_key)


## One-word name of a filter, for its chip and the sheet's count line.
static func filter_label(key: String) -> String:
	match key:
		FILTER_CUT:
			return "Cut off"
		FILTER_UNGARRISONED:
			return "Ungarrisoned"
		FILTER_WORKS:
			return "Works"
	return "All provinces"


# --- rows -------------------------------------------------------------------


static func _row(
	model: MapModel,
	province: ProvinceState,
	region: int,
	armies: Array,
	estates: Dictionary,
	links: Dictionary
) -> Dictionary:
	var garrison: Dictionary = _garrison(armies, province.id, province.owner)
	var estate: Dictionary = _estates(estates, province.id)
	var link: Dictionary = links.get(province.id, {}) as Dictionary
	var flags: Array[String] = []
	if link.has("linked") and not bool(link.get("linked", false)):
		flags.append(FILTER_CUT)
	if int(garrison["regiments"]) == 0:
		flags.append(FILTER_UNGARRISONED)
	if bool(estate["working"]):
		flags.append(FILTER_WORKS)
	return {
		"id": province.id,
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"name": String(province.name),
		"capital": province.capital,
		"place": _place(model, province),
		"line": _line(province, estate),
		"state": _state(garrison, link),
		"flags": flags,
		"regiments": int(garrison["regiments"]),
		"strength": float(garrison["strength"]),
		"estates": int(estate["estates"]),
		"yield": int(estate["yield"]),
		"linked": bool(link.get("linked", false)),
	}


## Where the province stands: its harbour's water, or that it has none.
static func _place(model: MapModel, province: ProvinceState) -> String:
	var port: Vector2i = province.port_tile
	if port.x < 0:
		return "Inland"
	var water: String = model.sea_zone_name(_water(model, port))
	return ("Harbour — %s" % water) if not water.is_empty() else "Harbour"


## The water a harbour opens on: the port tile's own zone, or the first zone
## beside it when the chart keeps the zone on the water rather than the quay.
static func _water(model: MapModel, port: Vector2i) -> int:
	var zone: int = model.sea_zone_at(port.x, port.y)
	if zone != MapModel.NO_ID:
		return zone
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var next: Vector2i = port + offset
		if not model.in_bounds(next.x, next.y):
			continue
		var beside: int = model.sea_zone_at(next.x, next.y)
		if beside != MapModel.NO_ID:
			return beside
	return MapModel.NO_ID


## What the province is built to: its town, its wall, its ward and its estates.
static func _line(province: ProvinceState, estate: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append("Town %d" % province.town_level() if province.has_town() else "No town")
	if province.fort_level > 0:
		parts.append("Fort %d" % province.fort_level)
	if province.hospital_level > 0:
		parts.append("Hospital %d" % province.hospital_level)
	var estates: int = int(estate["estates"])
	if estates == 0:
		parts.append("No estates")
	else:
		parts.append("%d estate%s · %d a turn" % [
			estates, MoneyText.plural(estates), int(estate["yield"])
		])
	return " · ".join(parts)


## What the province lacks: the men who hold it and the road that pays it.
static func _state(garrison: Dictionary, link: Dictionary) -> String:
	var parts: PackedStringArray = []
	var regiments: int = int(garrison["regiments"])
	if regiments == 0:
		parts.append("Ungarrisoned")
	else:
		parts.append("%d regiment%s · %.1f strength" % [
			regiments, MoneyText.plural(regiments), float(garrison["strength"])
		])
	parts.append(_link_text(link))
	return " · ".join(parts)


## The crown link in the ledger's own words: the dossier's row says the same
## thing at more length, and both read the one `province_link` result.
static func _link_text(link: Dictionary) -> String:
	if not link.has("linked"):
		return "No crown link read"
	if bool(link.get("linked", false)):
		return "Roads to the seat"
	if bool(link.get("blockaded", false)):
		return "Harbour blockaded"
	var gap: int = int(link.get("distance", -1))
	if gap > 0:
		return "Cut off — %d road tile%s to lay" % [gap, MoneyText.plural(gap)]
	return "Cut off — no road route"


## The crown's men standing in one province, read through the resolver's own
## aggregation so the ledger and the battle agree.
static func _garrison(armies: Array, province_id: int, owner: int) -> Dictionary:
	var standing: Array[ArmyState] = []
	for raw: Variant in armies:
		var army := raw as ArmyState
		if army == null or army.province != province_id or army.owner != owner:
			continue
		standing.append(army)
	var regiments: int = 0
	for army: ArmyState in standing:
		regiments += army.regiments.size()
	return {
		"regiments": regiments,
		"strength": ArmyForce.side_strength(standing) if not standing.is_empty() else 0.0,
	}


## One province's estates, read from the estates ledger's own groups: how many
## it holds, what they yield and whether a crew is at work there.
static func _estates(estates: Dictionary, province_id: int) -> Dictionary:
	var reading: Dictionary = {"estates": 0, "yield": 0, "working": false}
	for raw: Variant in estates.get("groups", []):
		var group: Dictionary = raw
		if int(group.get("id", NO_ID)) != province_id:
			continue
		reading["estates"] = int(group.get("count", 0))
		for entry: Variant in group.get("rows", []):
			var row: Dictionary = entry
			reading["yield"] = int(reading["yield"]) + int(row.get("output", 0))
			if bool(row.get("working", false)):
				reading["working"] = true
		break
	return reading


# --- assembly ---------------------------------------------------------------


## Reading order: the seat first, then the chart's own order, so a crown's
## capital is never buried in the middle of its holdings.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["capital"]) != bool(b["capital"]):
		return bool(a["capital"])
	if int(a["region"]) != int(b["region"]):
		return int(a["region"]) < int(b["region"])
	return int(a["id"]) < int(b["id"])
