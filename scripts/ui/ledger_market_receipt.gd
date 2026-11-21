class_name LedgerMarketReceipt
extends RefCounted
## The MARKET tab's last-clearing receipt: the court's own fills, the overseas
## share rows behind the total, and the prices that moved. Pure composition —
## the page mounts it and never owns the reading (wiki: world-market § Trade
## orders, § First right of refusal, § Price discovery; REQ-P3-01, REQ-P5-05).

## Share fills named under the total before the page counts the rest.
const SHARE_ROWS: int = 4


## Mounts the receipt under `parent`. Quiet when the viewer traded nothing and
## took no overseas share, and when no price moved.
static func mount(
	parent: Control,
	market: WorldMarket,
	clearing: Dictionary,
	viewer: int
) -> void:
	if parent == null or market == null:
		return
	_add_deals(parent, market, clearing, viewer)
	_add_prices(parent, clearing)


static func _add_deals(
	parent: Control,
	market: WorldMarket,
	clearing: Dictionary,
	viewer: int
) -> void:
	var mine: Array[Dictionary] = []
	for raw: Variant in market.book.last_deals:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = raw
		var buyer: int = int(deal.get("buyer", -2))
		var seller: int = int(deal.get("seller", -2))
		if buyer == viewer or seller == viewer:
			mine.append(deal)
	var share: int = LedgerMarketText.share_credit(clearing, viewer)
	if mine.is_empty() and share <= 0:
		return
	UiRowBuilder.spacer(parent, 4.0)
	parent.add_child(UiRowBuilder.label("LAST CLEARING", 11, Palette.GOLD_DIM))
	for deal: Dictionary in mine.slice(0, 4):
		parent.add_child(UiRowBuilder.label(
			LedgerMarketText.deal_line(deal, viewer), 12, Palette.TEXT_DIM
		))
	if mine.size() > 4:
		parent.add_child(UiRowBuilder.label(
			"+%d more deals" % (mine.size() - 4), 11, Palette.TEXT_DIM
		))
	if share > 0:
		var shares := UiRowBuilder.label(
			"Overseas shares  +%d ducats" % share, 12, Palette.GOLD_PALE
		)
		shares.tooltip_text = (
			"The court's cut of the Minor and Tribe sales abroad — tile rights "
			+ "and embassy kickbacks (wiki: world-market § First right of refusal)."
		)
		parent.add_child(shares)
		_add_share_rows(parent, clearing, viewer)


## The fills behind the total, one dim row each: a rival's buy on the crown's sold
## ground pays the crown even in a turn it staged nothing, so the block names the
## buy instead of leaving one unexplained number (wiki: world-market § First right
## of refusal; REQ-P5-05).
static func _add_share_rows(
	parent: Control,
	clearing: Dictionary,
	viewer: int
) -> void:
	var rows: Array[Dictionary] = LedgerMarketText.share_rows(clearing, viewer)
	for row: Dictionary in rows.slice(0, SHARE_ROWS):
		var line := UiRowBuilder.label(LedgerMarketText.share_row_line(row), 11, Palette.TEXT_DIM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(240, 0)
		parent.add_child(line)
	if rows.size() > SHARE_ROWS:
		parent.add_child(UiRowBuilder.label(
			"+%d more fills" % (rows.size() - SHARE_ROWS), 11, Palette.TEXT_DIM
		))


## The clearing moved prices: the goods and the price they now stand at, so the
## turn's new market is read where the clearing is narrated and never arrives as
## a silent change (wiki: world-market § Price discovery; REQ-P5-05).
static func _add_prices(parent: Control, clearing: Dictionary) -> void:
	var line: String = LedgerMarketText.price_moves_line(clearing)
	if line.is_empty():
		return
	UiRowBuilder.spacer(parent, 4.0)
	var moved := UiRowBuilder.label(line, 11, Palette.TEXT_DIM)
	moved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	moved.custom_minimum_size = Vector2(240, 0)
	parent.add_child(moved)
