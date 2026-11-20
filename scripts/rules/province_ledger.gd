class_name ProvinceLedger
extends RefCounted
## The crown's realm: every province it holds, in both charts, read three ways —
## what it yields (economy), how hard it is to hold (defence) and how far it
## sits from the seat (connectivity). Pure read-only projection: it reads the
## chart, the crown link the province dossier prints, the estates ledger's own
## rows, the army rosters and the market's current sell prices, and never orders
## a work, a march or a spend (REQ-P3-02, REQ-P3-03).
##
## No number here is recomputed: the garrison is `ArmyForce.side_strength`, the
## extraction is the estates ledger's own `output`, the defence multiplier is the
## battle's own [ArmyModifiers.TERRAIN_DEFENCE] and the fort's guns are
## [FortRules]', so a row can never print a figure the turn would not use
## (REQ-P2-03). Economic output is those extracted units valued at today's sell
## price, the same [WorldMarket.sell_price] the market ledger clears at.

## The three readings the realm offers. One name for the axis, so a chip press
## reads the same as a sort press.
const VIEW_ECONOMY: String = "economy"
const VIEW_DEFENCE: String = "defence"
const VIEW_CONNECTIVITY: String = "connectivity"
const VIEWS: Array[String] = [VIEW_ECONOMY, VIEW_DEFENCE, VIEW_CONNECTIVITY]

## Sort keys: one overall economic figure and one per resource kind, the
## defence figure, and the province-hop reading.
const SORT_VALUE: String = "value"
const SORT_DEFENCE: String = "defence"
const SORT_HOPS: String = "hops"
## The four published resource kinds, in the order every plate reads them.
const KIND_SORTS: Array[String] = ["tree", "ore", "coin", "wheat"]

const NO_ID: int = -1


## Whole-empire snapshot in reading order. `regions` is one entry per chart:
## {region, model, armies, estates, links, seat} — the armies the crown holds
## there, the estates ledger's snapshot for that chart, the crown link per
## province id (`LandConnectivity.province_link`) and the id of the province
## this crown seats there (-1 when it holds no seat). `market` prices the
## extraction; `tech` is the crown's unlocked studies, which decide the fort's
## emplaced battery.
static func snapshot(
	regions: Array[Dictionary],
	owner: int,
	market: WorldMarket = null,
	tech: Dictionary = {}
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var counts: Dictionary = {"cut_off": 0, "ungarrisoned": 0, "works": 0}
	var seat_region: int = NO_ID
	for entry: Dictionary in regions:
		var model := entry.get("model") as MapModel
		if model == null:
			continue
		var region: int = int(entry.get("region", model.region_id))
		var seat: int = int(entry.get("seat", NO_ID))
		if seat != NO_ID and seat_region == NO_ID:
			seat_region = region
		var hops: Dictionary = _hops(model, owner, seat)
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != owner:
				continue
			var row: Dictionary = _row(
				model, province, entry, region, seat, hops, seat_region, owner, market, tech
			)
			rows.append(row)
			for flag: String in row["flags"]:
				counts[flag] = int(counts.get(flag, 0)) + 1
	rows.sort_custom(_before)
	return {"rows": rows, "groups": LedgerRows.group(rows), "counts": counts, "total": rows.size()}


## Rows narrowed to one chart, ordered by the view's own key, grouped under
## their chart. Each chart is sorted inside its own group, so a heading never
## stands over another chart's rows.
static func groups(
	data: Dictionary, region_key: String, view_key: String, sort_key: String
) -> Array[Dictionary]:
	var kept: Array[Dictionary] = LedgerRows.groups(
		data, region_key, func(_row: Dictionary) -> bool: return true
	)
	for group: Dictionary in kept:
		var rows: Array[Dictionary] = []
		rows.assign(group["rows"] as Array)
		_sort_rows(rows, view_key, sort_key)
		group["rows"] = rows
	return kept


static func count(data: Dictionary, region_key: String) -> int:
	return LedgerRows.count(
		data, region_key, func(_row: Dictionary) -> bool: return true
	)


## One-word name of a view, for its chip and the sheet's count line.
static func view_label(key: String) -> String:
	match key:
		VIEW_DEFENCE:
			return "Defence"
		VIEW_CONNECTIVITY:
			return "Connectivity"
	return "Economy"


## The sort keys a view offers, in the order its chips print.
static func sort_keys(view_key: String) -> Array:
	match view_key:
		VIEW_DEFENCE:
			return [SORT_DEFENCE] as Array
		VIEW_CONNECTIVITY:
			return [SORT_HOPS] as Array
	var keys: Array = [SORT_VALUE]
	keys.append_array(KIND_SORTS)
	return keys


## The key a view opens on: the one figure a crown asks first.
static func sort_default(view_key: String) -> String:
	match view_key:
		VIEW_DEFENCE:
			return SORT_DEFENCE
		VIEW_CONNECTIVITY:
			return SORT_HOPS
	return SORT_VALUE


## The word a sort chip carries.
static func sort_label(key: String) -> String:
	match key:
		SORT_VALUE:
			return "Total"
		SORT_DEFENCE:
			return "Figure"
		SORT_HOPS:
			return "Hops"
	return String(ResourceTypes.NAMES.get(key, key)).capitalize()


# --- rows -------------------------------------------------------------------


static func _row(
	model: MapModel,
	province: ProvinceState,
	entry: Dictionary,
	region: int,
	seat: int,
	hops: Dictionary,
	seat_region: int,
	owner: int,
	market: WorldMarket,
	tech: Dictionary
) -> Dictionary:
	var garrison: Dictionary = _garrison(entry.get("armies", []), province.id, owner)
	var link: Dictionary = (entry.get("links", {}) as Dictionary).get(province.id, {}) as Dictionary
	var estate: Dictionary = _estates(entry.get("estates", {}) as Dictionary, province.id)
	var flags: Array[String] = []
	if link.has("linked") and not bool(link.get("linked", false)):
		flags.append("cut_off")
	if int(garrison["regiments"]) == 0:
		flags.append("ungarrisoned")
	if bool(estate["working"]):
		flags.append("works")
	return {
		"id": province.id,
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"name": String(province.name),
		"capital": province.capital,
		"town": province.town_level() if province.has_town() else 0,
		"place": _place(model, province),
		"line": _line(province, estate),
		"state": _state(garrison, link),
		"flags": flags,
		"regiments": int(garrison["regiments"]),
		"strength": float(garrison["strength"]),
		"estates": int(estate["estates"]),
		"yield": int(estate["output"]),
		"linked": bool(link.get("linked", false)),
		"economy": RealmReadings.economy(estate, owner, market),
		"defence": RealmReadings.defence(province, garrison, model, tech),
		"connectivity": RealmReadings.connectivity(link, hops, province.id, seat, region, seat_region),
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


## What the province is built to: its town, its wall and its ward.
static func _line(province: ProvinceState, estate: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append("Town %d" % province.town_level() if province.has_town() else "No town")
	if province.fort_level > 0:
		parts.append("Fort %d" % province.fort_level)
	if province.hospital_level > 0:
		parts.append("Hospital %d" % province.hospital_level)
	var estates: int = int(estate["estates"])
	parts.append("No estates" if estates == 0 else "%d estate%s" % [
		estates, "" if estates == 1 else "s"
	])
	return " · ".join(parts)


## What the province holds: the men who stand there and the road that pays it.
static func _state(garrison: Dictionary, link: Dictionary) -> String:
	var parts: PackedStringArray = []
	var regiments: int = int(garrison["regiments"])
	if regiments == 0:
		parts.append("Ungarrisoned")
	else:
		parts.append("%d regiment%s · %.1f strength" % [
			regiments, "" if regiments == 1 else "s", float(garrison["strength"])
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
		return "Cut off — %d road tile%s to lay" % [gap, "" if gap == 1 else "s"]
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


## One province's estates, read from the estates ledger's own groups: the rows
## themselves, so the economy view can price each resource at its own sell
## price without a second harvest walk.
static func _estates(estates: Dictionary, province_id: int) -> Dictionary:
	var reading: Dictionary = {
		"estates": 0, "output": 0, "working": false, "rows": [] as Array[Dictionary],
	}
	for raw: Variant in estates.get("groups", []):
		var group: Dictionary = raw
		if int(group.get("id", NO_ID)) != province_id:
			continue
		reading["estates"] = int(group.get("count", 0))
		var rows: Array[Dictionary] = reading["rows"]
		for entry: Variant in group.get("rows", []):
			var row: Dictionary = entry
			rows.append(row)
			reading["output"] = int(reading["output"]) + int(row.get("output", 0))
			if bool(row.get("working", false)):
				reading["working"] = true
		break
	return reading


## Owned-land hops from the seat, walked once per chart over the provinces this
## crown holds (wiki: map-topology). No seat on this chart reaches nothing.
static func _hops(model: MapModel, owner: int, seat: int) -> Dictionary:
	if seat == NO_ID:
		return {}
	var owned: Array = []
	for province: ProvinceState in model.provinces:
		if province != null and province.owner == owner:
			owned.append(province.id)
	return ProvinceGraph.hops(model, owned, seat)


# --- order ------------------------------------------------------------------


## The rows of one group in the view's own order. Economy and defence read
## highest first; connectivity reads near-first with the unreachable last.
static func _sort_rows(rows: Array[Dictionary], view_key: String, sort_key: String) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: float = _sort_value(a, view_key, sort_key)
		var right: float = _sort_value(b, view_key, sort_key)
		if left != right:
			return left > right if view_key != VIEW_CONNECTIVITY else left < right
		return _before(a, b)
	)


## One row's figure on the chosen sort key. An unreachable province scores
## below every reached one on connectivity, so it always prints last.
static func _sort_value(row: Dictionary, view_key: String, sort_key: String) -> float:
	match view_key:
		VIEW_DEFENCE:
			return float((row["defence"] as Dictionary)["figure"])
		VIEW_CONNECTIVITY:
			var hops: int = int((row["connectivity"] as Dictionary)["hops"])
			return 1e9 if hops < 0 else float(hops)
	if sort_key == SORT_VALUE:
		return float((row["economy"] as Dictionary)["value"])
	return float(((row["economy"] as Dictionary)["by_kind"] as Dictionary).get(sort_key, 0))


## Reading order: the seat first, then the chart's own order, so a crown's
## capital is never buried in the middle of its holdings.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["capital"]) != bool(b["capital"]):
		return bool(a["capital"])
	if int(a["region"]) != int(b["region"]):
		return int(a["region"]) < int(b["region"])
	return int(a["id"]) < int(b["id"])
