class_name CivilianWorkRows
extends RefCounted
## Work-order list rows and the transport preview they print (wiki:
## civilian-units § Work Order Summary; capital-and-connectivity § Path
## transport cap). Pure projection: [CivilianWork] builds the option list and
## the pick words name the same transport reading, so a row never prices a
## harbour's estate as a one-turn road (REQ-P3-01, REQ-P2-03; DR-20261117-05).
## Cost and duration maths stay on [CivilianWorkPlan].


## The order as the court reads it. A fort is the one order that lands at one of
## three levels, each with its own price, wait and tech gate, so the order names
## the level it would raise — "Build fort" alone cannot be told from "Build
## fort" for a higher wall (wiki: siege-mechanics § Fort Levels).
static func order_label(
	action: String, model: MapModel, tile: Vector2i, plain: String
) -> String:
	if action != "build_fort":
		return plain
	return "Build %s fort" % FortRules.level_name(
		CivilianWorkPlan.fort_target(model, tile)
	).to_lower()


## One row of the work-order list: the label the court reads, the price beside
## it and the materials the rules charge. A fort's price also names the turns it
## takes, because its wall is the one order that arrives over several of them.
## The row also says what the work lands, for the works no ledger prices: the
## transport a road, a harbour or a railroad brings to the tile (DR-20261117-05).
static func option_row(
	action: String, model: MapModel, tile: Vector2i, works: LandWorks,
	check: Dictionary, plain: String, blockade: Blockades = null
) -> Dictionary:
	var cost: Dictionary = CivilianWorkPlan.cost_for(
		action, CivilianWorkPlan.cost_level(action, model, tile, works)
	)
	var price: String = CivilianWorkPlan.cost_text(cost)
	if action == LandPurchase.ACTION:
		price = String(check.get("cost_text", LandPurchase.cost_text(model, tile)))
	var row: Dictionary = {
		"label": order_label(action, model, tile, plain),
		"cost": cost,
		"cost_text": price,
		"preview_text": _preview(action, model, tile, works, blockade),
	}
	if action != "build_fort":
		return row
	var turns: int = CivilianWorkPlan.duration_for(model, action, tile, works)
	row["cost_text"] = "%s · %d turn%s" % [price, turns, "" if turns == 1 else "s"]
	return row


## What the order lands, in the words of whichever rule prices it: the transport a
## road, a harbour or a railroad brings, the manufacture bonus and works a town
## level opens, or — for a Merchant's deed — the first refusal and town level the
## price buys ([DeedTerms]). Empty for every other order: those are priced where
## their own ledger prints the payoff.
static func _preview(
	action: String, model: MapModel, tile: Vector2i, works: LandWorks,
	blockade: Blockades = null
) -> String:
	var transport: String = transport_preview(action, model, tile, works, blockade)
	if not transport.is_empty():
		return transport
	if action == "upgrade_town":
		return TownTerms.order_line(model, tile)
	if action != LandPurchase.ACTION:
		return ""
	return DeedTerms.order_line(model, tile)


## What a transport work lands on this tile, in the order's own words: the
## transport level the path will carry, which is the ceiling the Extraction
## formula puts on an estate here (wiki: extraction-and-improvements §
## Extraction; capital-and-connectivity § Path transport cap). A port is read as
## the landfall it is — a harbour tile carries the rail's transport and anchors
## the sea road. Empty for every other order: those are priced where their own
## ledger prints the payoff (REQ-P5-06, REQ-P2-03; DR-20261117-05).
static func transport_preview(
	action: String, model: MapModel, tile: Vector2i, works: LandWorks,
	blockade: Blockades = null
) -> String:
	if not CivilianTransport.knows(action):
		return ""
	var level: int = transport_after(
		action, current_transport(model, tile, works, blockade)
	)
	var text: String = "Transport %d — an estate here gathers up to %d a turn" % [
		level, level
	]
	if action == "build_port":
		return "Landfall · " + text
	return text


## The transport the tile carries today, read the way the connectivity resolver
## reads it: its own road, rail or harbour, and — for a tile beside a crown
## harbour — the harbour's level 4 (wiki: extraction-and-improvements
## § Transport Level, "Adjacent port tile grants level 4 to that tile"). The
## preview reads it so the road row never prices a harbour's estate as a
## one-turn road, nor promises less than the land already gathers. A sealed
## harbour is no landfall, so the blockade takes its grant with it and the tile
## keeps only the grade its own road carries (wiki: capital-and-connectivity
## § Blockade).
static func current_transport(
	model: MapModel, tile: Vector2i, works: LandWorks,
	blockade: Blockades = null
) -> int:
	if model == null or works == null:
		return 0
	var level: int = works.transport_at(model, tile)
	if works.has_port(model, tile) and not Blockades.seals_harbour(blockade, model, tile):
		return LandWorks.TRANSPORT_RAIL
	var owner: int = model.owner_at(tile.x, tile.y)
	for offset: Vector2i in [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
	]:
		var next: Vector2i = tile + offset
		if not model.in_bounds(next.x, next.y):
			continue
		if model.owner_at(next.x, next.y) != owner:
			continue
		if works.has_port(model, next) and not Blockades.seals_harbour(blockade, model, next):
			return LandWorks.TRANSPORT_RAIL
	return level


## The transport level a finished work leaves on the tile: a road raises the
## path one step (level 2 at most) but never lowers a tile a harbour or a
## railroad already carries, a railroad lands 4, and a harbour carries the rail's
## transport in the network's own reading (`LandConnectivity`).
static func transport_after(action: String, current: int) -> int:
	match action:
		"build_road":
			return maxi(current, mini(current + 1, LandWorks.TRANSPORT_IMPROVED_ROAD))
		"build_port", "build_rail":
			return LandWorks.TRANSPORT_RAIL
	return current
