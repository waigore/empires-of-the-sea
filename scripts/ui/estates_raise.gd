class_name EstatesRaise
extends RefCounted
## The estates door's one press: the ready walk the current view prints, the
## H8 bootstrap price of each step, and the line under the press that names what
## the stores and free Builders carry (wiki: extraction-and-improvements
## § H8 feedstock bootstrap; DR-20261118-12, DR-20261118-21). Kept out of
## [ImprovementPanel] so the door stays under the P3 size bar (REQ-P3-01). Pure
## reads over the ledger and [RaiseLine] — the panel still emits the order; the
## screen still files it (REQ-P3-03).


## Holds the chart for RaiseLine's price Callable without a lambda capture
## (coverage and teardown must not free a bound Object mid-walk).
class PriceWalk extends RefCounted:
	var model: MapModel = null

	func price(row: Dictionary, left: Dictionary) -> Dictionary:
		return EstatesRaise.price_row(model, row, left)


## Ready estates and their tiles for the province and chip reading the door
## holds, in the order it prints them (REQ-P5-04; DR-20261116-06).
static func ready_view(
	snapshot: Dictionary, province_id: int, filter_key: String
) -> Dictionary:
	var groups: Array[Dictionary] = EstateLedger.in_province(
		EstateLedger.grouped(snapshot), province_id
	)
	return {
		"rows": EstateLedger.ready_rows(groups, filter_key),
		"tiles": EstateLedger.ready_tiles(groups, filter_key),
	}


## One estate's price inside the line, read against the stores the orders before
## it leave: the H8 bootstrap waives a level-1 raise's feedstock while the court
## holds none, so the fifth estate is not the first's price (#878, REQ-P2-03).
static func price_row(model: MapModel, row: Dictionary, left: Dictionary) -> Dictionary:
	var tile: Variant = row.get("tile", CivilianState.NO_TILE)
	if model == null or not (tile is Vector2i):
		var raw: Variant = row.get("cost", {})
		return raw as Dictionary if raw is Dictionary else {}
	return CivilianWorkPlan.bootstrap_cost(
		model, tile as Vector2i, left, int(row.get("next_level", 1))
	)


## Names how many estates the view would order and what the walk would take —
## or what waits and why — so the armed face confirms the line's own count
## (REQ-P5-03; DR-20261118-21).
static func sync(
	batch: RaiseBatchPress,
	line: Label,
	snapshot: Dictionary,
	province_id: int,
	filter_key: String,
	model: MapModel,
	stockpile: Dictionary,
	units: Array[CivilianState],
	faction: int
) -> void:
	if batch == null:
		return
	var view: Dictionary = ready_view(snapshot, province_id, filter_key)
	var tiles: Array = view["tiles"]
	if line == null:
		batch.set_ready(tiles.size(), "estates")
		return
	var rows: Array[Dictionary] = view["rows"]
	var walk := PriceWalk.new()
	walk.model = model
	var reading: Dictionary = RaiseLine.plan(
		rows,
		stockpile,
		ImprovementOrders.idle_builders(units, faction).size(),
		CivilianCatalog.display_name("builder"),
		walk.price
	)
	line.text = RaiseLine.sheet_line(reading)
	line.visible = not line.text.is_empty()
	batch.set_ready(tiles.size(), "estates", int(reading["filed"]))
