class_name MarketRow
extends RefCounted
## One commodity row of the crown's market tab: the medallion, the holding, the
## price, the Offer and Bid presses, and the batch press the rules allow under
## it. Pure composition — every press emits the page's own trade intent and the
## controller decides (wiki: world-market § Trade orders; REQ-P2-03, REQ-P3-01).

const ROW_HEIGHT: float = 38.0


## Builds the row — wrapped when it carries a batch press — and returns
## `{row, batches}`. `batches` is keyed "bid"/"offer" for the presses the rules
## allow; a row whose whole order is one unit carries none. `on_trade` takes
## `(commodity, quantity, is_buy)`.
static func build(
	id: String,
	held: int,
	claimed: int,
	cargo: Dictionary,
	market: WorldMarket,
	viewer: int,
	ctx: Dictionary,
	compact: bool,
	on_trade: Callable
) -> Dictionary:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	row.add_child(CommodityIcons.cell(id, 132.0))

	var qty := UiRowBuilder.label("%d" % held, 14, Palette.GOLD_PALE)
	qty.custom_minimum_size = Vector2(44, 0)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(qty)

	var buy_unit: int = market.buy_price(id, viewer)
	var sell_unit: int = market.sell_price(id, viewer)
	var price := UiRowBuilder.label("%d" % buy_unit, 13, Palette.TEXT_DIM)
	price.custom_minimum_size = Vector2(44, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)

	# The court can only sell what its own production runs leave behind and what
	# it has not already offered this turn, and the cap is a readout on the page,
	# not a hover: a phone player must see why the Offer is dead (wiki:
	# world-market § Trade orders — the sellable readout, the offer cap is the
	# post-production stockpile minus industry reservations and staged offers;
	# REQ-P1-05, REQ-P5-05).
	var promised: int = market.book.pending_sell_units(viewer, id) if market != null else 0
	var sellable: int = maxi(held - claimed - promised, 0)
	var sell := UiRowBuilder.button("Offer", ROW_HEIGHT, 70.0)
	sell.disabled = sellable <= 0
	if claimed > 0 or promised > 0:
		sell.tooltip_text = "%s — %d sellable at %d ducats" % [
			_claim_line(id, claimed, promised), sellable, sell_unit,
		]
	else:
		sell.tooltip_text = "Offer 1 %s at %d ducats — it clears when the turn closes" % [
			CommodityCatalog.label(id), sell_unit,
		]
	sell.pressed.connect(func() -> void: on_trade.call(id, 1, false))
	row.add_child(sell)

	var buy := UiRowBuilder.button("Bid", ROW_HEIGHT, 70.0)
	buy.tooltip_text = "Bid 1 %s at %d ducats — it clears when the turn closes" % [
		CommodityCatalog.label(id), buy_unit
	]
	# Imports need a free hold in the home fleet (DR-20261109-03).
	if int(cargo.get("free", -1)) == 0:
		buy.disabled = true
		buy.tooltip_text = "No cargo holds free this turn"
	buy.pressed.connect(func() -> void: on_trade.call(id, 1, true))
	row.add_child(buy)

	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	block.add_child(row)
	if claimed > 0 or promised > 0:
		block.add_child(UiRowBuilder.caption(
			"%s — %d sellable" % [_claim_line(id, claimed, promised), sellable],
			10, Palette.TEXT_DIM, 0.0
		))
	# One press files the whole order the rules accept, so a court buying a
	# turn's ration never taps Bid ten times (REQ-P5-04). The single presses
	# above stay, so a batch is never forced.
	var batches: Dictionary = {}
	var bid_units: int = MarketBatch.bid_units(market, viewer, id, ctx)
	var press := MarketBatchPress.attach(
		block, "Bid", bid_units, id,
		MarketRules.deal_total(market, id, bid_units, viewer, 1.0, true),
		compact,
		func() -> void: on_trade.call(id, bid_units, true)
	)
	if press != null:
		batches["bid"] = press
	var offer_units: int = MarketBatch.offer_units(market, viewer, id, held, ctx)
	press = MarketBatchPress.attach(
		block, "Offer", offer_units, id,
		MarketRules.deal_total(market, id, offer_units, viewer, 1.0, false),
		compact,
		func() -> void: on_trade.call(id, offer_units, false)
	)
	if press != null:
		batches["offer"] = press
	if block.get_child_count() > 1:
		return {"row": block, "batches": batches}
	# A row with no batch press reads exactly as it did before: the wrapper is
	# only there to stack the press under the row.
	block.remove_child(row)
	block.free()
	return {"row": row, "batches": batches}


## What the crown cannot sell off this row, in words: the assigned runs' claim
## and the tons already offered. The readout names only what is there, so a row
## with neither reads no caption at all (REQ-P1-07).
static func _claim_line(id: String, claimed: int, promised: int) -> String:
	var label: String = CommodityCatalog.label(id)
	var parts: PackedStringArray = PackedStringArray()
	if claimed > 0:
		parts.append("%d %s claimed by production" % [claimed, label])
	if promised > 0:
		parts.append("%d offered" % promised)
	return ", ".join(parts)
