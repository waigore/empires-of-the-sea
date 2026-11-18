class_name RaiseLine
extends RefCounted
## What the crown's raise sheets' one press takes before it is pressed: how many
## of the ready rows the view prints the stores and the free crews carry, the
## materials the line spends and the reason the next one waits (wiki:
## civilian-units § One press files what the realm can raise;
## DR-20261118-12).
##
## The towns, the walls, the hospitals and the estates filed a whole line on a
## count alone, so a crown learned the stores' answer after it signed: five ready
## estates and one idle Builder spend one Builder's materials and refuse the
## rest. The walk here is the press's own — every ready row, in the sheet's
## order, each priced against the stores the orders before it leave, stopping at
## the first refusal the rules give — and it writes nothing:
## [RaiseLedger.file_batch] still files and [CivilianWork] still charges.
##
## Pure reads over stores, catalogues and the sheets' own cost tables: no nodes,
## no order of its own (REQ-P2-03, REQ-P3-03).

## The chart key a single-pool walk draws from, so one walk serves a one-chart
## view and a two-chart sheet alike (DR-20261118-13).
const POOLED: int = -1


## The plan a raise sheet's press would file. `targets` are the ready rows the
## sheet's view prints, in its order, each carrying its `cost` (a materials
## map) and, when the line is walked chart by chart, its `region`; `stores` is
## the crown's own stockpile, read and never written; `crews` is how many idle
## crews of the sheet's trade the realm holds, because one order ties one up.
## `free_by_region` is the same reading chart by chart ({region: how many stand
## idle}), and a crew works the chart it stands on — the filing walk sends a
## Builder aboard nothing, so a New World Builder can never raise an Old World
## town (DR-20261118-13). A sheet whose view is one chart may hand the one pool
## instead. `price` is the sheet's own reading when the price is
## not the row's (`(target, stores_left) -> cost`), so a sheet whose cost moves
## with the stores — the H8 bootstrap — is still priced by the walk that files
## it (REQ-P2-03). `crew_word` is the trade the sheets name in their own words
## ("Builder", "Engineer").
static func plan(
	targets: Array[Dictionary],
	stores: Dictionary,
	crews: int,
	crew_word: String,
	price: Callable = Callable(),
	free_by_region: Dictionary = {}
) -> Dictionary:
	var reading: Dictionary = {
		"count": targets.size(),
		"filed": 0,
		"materials": {},
		"crews": 0,
		"kept": {},
		"crew_word": crew_word,
		"refusal": "",
	}
	var left: Dictionary = stores.duplicate()
	# One pool for a single-chart view, one pool per chart when the sheet reads
	# both: either way a filed order spends the hand it will send.
	var pooled: bool = free_by_region.is_empty()
	var hands: Dictionary = {POOLED: maxi(crews, 0)} if pooled else free_by_region.duplicate()
	for raw: Variant in targets:
		var target: Dictionary = raw
		var chart: int = POOLED if pooled else int(target.get("region", POOLED))
		if int(hands.get(chart, 0)) <= 0:
			reading["refusal"] = RaiseLedger.no_crew_note(crew_word)
			break
		var cost: Dictionary = _cost_of(target, price, left)
		var short: String = CivilianWorkRefusals.stores(cost, left)
		if not short.is_empty():
			reading["refusal"] = short
			break
		_pay(left, cost)
		var materials: Dictionary = reading["materials"]
		for commodity: Variant in cost.keys():
			var id: String = String(commodity)
			materials[id] = int(materials.get(id, 0)) + int(cost[commodity])
		reading["crews"] = int(reading["crews"]) + 1
		reading["filed"] = int(reading["filed"]) + 1
		hands[chart] = int(hands.get(chart, 0)) - 1
	# The stores the line leaves, for the resources it spends: the row's own
	# labels and the sheet's own reading, never the whole stockpile.
	var kept: Dictionary = reading["kept"]
	for commodity: Variant in (reading["materials"] as Dictionary).keys():
		var id: String = String(commodity)
		kept[id] = int(left.get(id, 0))
	return reading


## The row's price: the sheet's own reading when it hands one, the row's `cost`
## otherwise.
static func _cost_of(target: Dictionary, price: Callable, left: Dictionary) -> Dictionary:
	if price.is_valid():
		var priced: Variant = price.call(target, left)
		if priced is Dictionary:
			return priced as Dictionary
		return {}
	var raw: Variant = target.get("cost", {})
	if raw is Dictionary:
		return raw as Dictionary
	return {}


## Materials are paid when the order is filed and are not refunded on cancel, so
## the walk draws the same stores the order will (wiki: civilian-units
## § Relations).
static func _pay(stores: Dictionary, cost: Dictionary) -> void:
	for commodity: Variant in cost.keys():
		var id: String = String(commodity)
		stores[id] = int(stores.get(id, 0)) - int(cost[commodity])


## "8 Lumber · 2 Cast Iron · 3 Builders": what the line spends, in the stores'
## own commodity labels and the crews it ties up. A crew word the sheet names in
## the singular reads its plural here, so one press never says "1 Builders".
static func paid(reading: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var materials: Dictionary = reading.get("materials", {})
	for commodity: Variant in materials.keys():
		parts.append("%d %s" % [
			int(materials[commodity]), CommodityCatalog.label(String(commodity))
		])
	var crews: int = int(reading.get("crews", 0))
	if crews > 0:
		parts.append("%d %s%s" % [
			crews,
			String(reading.get("crew_word", "crew")),
			"" if crews == 1 else "s",
		])
	return " · ".join(parts)


## The line under the press, before it is pressed: what the line spends and the
## stores it leaves — or, when the walk stops short, how many of the ready rows
## wait and why. `""` when the view holds nothing the press would file.
static func sheet_line(reading: Dictionary) -> String:
	var filed: int = int(reading.get("filed", 0))
	if filed <= 0:
		return ""
	var costs: String = paid(reading)
	var refusal: String = String(reading.get("refusal", ""))
	if refusal.is_empty():
		var kept: String = _kept_text(reading)
		if kept.is_empty():
			return "%s — every ready step in this view is ordered." % costs
		return "%s — the stores keep %s." % [costs, kept]
	# The rules' own refusal ends its own sentence ("Stores are short of 4
	# cast iron."), so the line adds a stop only when it is missing.
	var why: String = refusal if refusal.ends_with(".") else refusal + "."
	var waiting: int = int(reading.get("count", 0)) - filed
	return "%s — %d of %d wait%s: %s" % [
		costs,
		waiting,
		int(reading.get("count", 0)),
		"" if waiting != 1 else "s",
		why,
	]


## "12 Lumber, 30 Cast Iron": what the stores still hold of what the line spends.
static func _kept_text(reading: Dictionary) -> String:
	var kept: Dictionary = reading.get("kept", {})
	var parts: PackedStringArray = PackedStringArray()
	for commodity: Variant in kept.keys():
		parts.append("%d %s" % [
			int(kept[commodity]), CommodityCatalog.label(String(commodity))
		])
	return ", ".join(parts)