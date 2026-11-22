class_name MarketRow
extends RefCounted
## One commodity row of the crown's market tab: the medallion, the holding, the
## price, the Offer and Bid presses, and the batch press the rules allow under
## it. Pure composition — every press emits the page's own trade intent and the
## controller decides (wiki: world-market § Trade orders; REQ-P2-03, REQ-P3-01).

const ROW_HEIGHT: float = 38.0
## The mark a row wears when the court's own trade plan names its good.
const COURT_MARK: String = "▸"


## The tons a row cannot sell, named: production's claim and the tons already
## offered this turn (wiki: world-market § Trade orders — the offer cap is the
## post-production stockpile, and a staged offer spends it).
static func _claim_phrase(id: String, claimed: int, promised: int) -> String:
	var label: String = CommodityCatalog.label(id)
	var parts: PackedStringArray = []
	if claimed > 0:
		parts.append("%d %s claimed by production" % [claimed, label])
	if promised > 0:
		parts.append("%d %s already offered" % [promised, label])
	return ", ".join(parts)


## "The court would bid 3 this phase." — the side and the units the court's own
## market pass books on one good, in the tab's own voice, so a marked row says
## what the reading means without the crown re-reading the gold line
## (wiki: world-market § Trade orders; DR-20261122-08).
static func court_line(court: Dictionary) -> String:
	var offer: int = int(court.get("offer", 0))
	var bid: int = int(court.get("bid", 0))
	if offer > 0 and bid > 0:
		return "The court would offer %d and bid %d this phase." % [offer, bid]
	if offer > 0:
		return "The court would offer %d this phase." % offer
	if bid > 0:
		return "The court would bid %d this phase." % bid
	return ""


## Builds the row — wrapped when it carries a batch press or a refusal — and
## returns `{row, batches}`. `batches` is keyed "bid"/"offer" for the presses the
## rules allow; a row whose whole order is one unit carries none. `on_trade`
## takes `(commodity, quantity, is_buy)`. `court` is the court's own plan for this
## good, `{offer: n}` and/or `{bid: n}`: the row leads with the counsel's mark
## and prints the side and the units it books (DR-20261122-08).
static func build(
	id: String,
	held: int,
	claimed: int,
	_cargo: Dictionary,
	market: WorldMarket,
	viewer: int,
	ctx: Dictionary,
	compact: bool,
	on_trade: Callable,
	court: Dictionary = {}
) -> Dictionary:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	row.add_child(CommodityIcons.cell(
		id, 132.0, 14, Palette.TEXT, COURT_MARK if not court.is_empty() else ""
	))

	var qty := UiRowBuilder.label("%d" % held, 14, Palette.GOLD_PALE)
	qty.custom_minimum_size = Vector2(44, 0)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(qty)

	var buy_unit: int = market.buy_price(id, viewer)
	var sell_unit: int = market.sell_price(id, viewer)
	var price := UiRowBuilder.label(TextFormat.thousands(buy_unit), 13, Palette.TEXT_DIM)
	price.custom_minimum_size = Vector2(44, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)

	# The court can only sell what its own production runs leave behind and what
	# it has not already offered, and the cap is a readout on the page, not a
	# hover: a phone player must see why the Offer is dead (wiki: world-market
	# § Trade orders — the sellable readout; REQ-P1-05, REQ-P5-05).
	var promised: int = market.book.pending_sell_units(viewer, id)
	var sellable: int = maxi(held - claimed - promised, 0)
	var sell := UiRowBuilder.button("Offer", ROW_HEIGHT, 70.0)
	sell.disabled = sellable <= 0
	if claimed > 0 or promised > 0:
		sell.tooltip_text = "%s — %d sellable at %s" % [
			_claim_phrase(id, claimed, promised), sellable, MoneyText.ducats(sell_unit),
		]
	else:
		sell.tooltip_text = "Offer 1 %s at %s — it clears when the turn closes" % [
			CommodityCatalog.label(id), MoneyText.ducats(sell_unit),
		]
	sell.pressed.connect(func() -> void: on_trade.call(id, 1, false))
	row.add_child(sell)

	# The bid is the holds and the purse the rules leave, so a chip the auction
	# would refuse is dead before the press (wiki: world-market § Trade orders —
	# the bid-side clamp; § Treasury budget for bids).
	var bid_units: int = MarketBatch.bid_units(market, viewer, id, ctx)
	var buy := UiRowBuilder.button("Bid", ROW_HEIGHT, 70.0)
	buy.tooltip_text = "Bid 1 %s at %s — it clears when the turn closes" % [
		CommodityCatalog.label(id), MoneyText.ducats(buy_unit)
	]
	# Why a dead Bid is dead, in the rules' own words: the gates the validator
	# walks, read forward (wiki: world-market § Trade orders — validation rules,
	# § Treasury budget for bids; REQ-P2-03, REQ-P5-05). Printed under the row
	# below, never only in the hover.
	var shut: String = ""
	if bid_units <= 0:
		buy.disabled = true
		shut = String(MarketRules.bid_block(market, viewer, id, ctx).get("reason", ""))
		if shut.is_empty():
			shut = "The rules leave no room for a bid this turn."
		buy.tooltip_text = "Bid 1 %s at %s — %s" % [
			CommodityCatalog.label(id), MoneyText.ducats(buy_unit), shut,
		]
	buy.pressed.connect(func() -> void: on_trade.call(id, 1, true))
	row.add_child(buy)

	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	block.add_child(row)
	# The side and the units the court's own plan books on this good, printed
	# under the press it would use: a mark points at the row, this says what the
	# reading means (wiki: world-market § Trade orders; DR-20261122-08).
	var court_words: String = court_line(court)
	if not court_words.is_empty():
		block.add_child(UiRowBuilder.caption(court_words, 10, Palette.GOLD_PALE, 0.0))
	if claimed > 0 or promised > 0:
		block.add_child(UiRowBuilder.caption(
			"%s — %d sellable" % [_claim_phrase(id, claimed, promised), sellable],
			10, Palette.TEXT_DIM, 0.0
		))
	# A phone player has no hover: the reason the Bid is shut is printed under
	# the row it shuts (REQ-P1-05, REQ-P5-05).
	if not shut.is_empty():
		block.add_child(UiRowBuilder.wrapped_line(shut, 10, Palette.CRIMSON, 0.0))
	# One press files the whole order the rules accept, so a court buying a
	# turn's ration never taps Bid ten times (REQ-P5-04). The single presses
	# above stay, so a batch is never forced.
	var batches: Dictionary = {}
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

