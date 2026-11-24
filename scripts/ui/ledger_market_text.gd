class_name LedgerMarketText
extends RefCounted
## Plain-text (and pure) formatting for the MARKET tab and the turn's clearing:
## the next-turn preview, the Deal Book line, the cargo-holds and bid-budget
## banners and the clearing toast. No visual nodes, so it is cheap to unit test
## (REQ-P3-03).


## "Next turn:  Grain +3 · ducats -10" or the calm no-change line. A staged order
## settles at the auction after these phases, so the line names it rather than
## letting the promise read as the whole purse movement (wiki:
## stockpiles-and-production § Production flow, world-market § Trade orders).
static func preview(report: Dictionary) -> String:
	var parts: PackedStringArray = []
	var delta: Dictionary = report.get("stockpile_delta", {})
	for id: String in delta.keys():
		parts.append("%s %+d" % [CommodityCatalog.label(id), int(delta[id])])
	var treasury_delta: int = int(report.get("treasury_delta", 0))
	if treasury_delta != 0:
		parts.append("ducats %s" % MoneyText.signed(treasury_delta))
	var staged: int = int(report.get("staged_orders", 0))
	var auction: String = _auction_line(staged)
	if parts.is_empty():
		var calm: String = "Next turn: no stock changes."
		if auction.is_empty():
			return calm
		return calm + "  " + auction
	var line: String = "Next turn:  " + "   ".join(parts)
	if auction.is_empty():
		return line
	return line + "   ·  " + auction


## "1 order settles at the auction." / "" when nothing is staged.
static func _auction_line(staged: int) -> String:
	if staged <= 0:
		return ""
	if staged == 1:
		return "1 order settles at the auction"
	return "%d orders settle at the auction" % staged


## The crown's overseas share of Minor and Tribe sales this clearing (wiki:
## world-market § First right of refusal, § Subsidy price adjustment). The
## clearing report carries it as `credits.by_gp`; a bare map is accepted too.
static func share_credit(report: Dictionary, faction: int) -> int:
	var credits: Dictionary = report.get("credits", {}) as Dictionary
	var by_gp: Dictionary = credits.get("by_gp", credits) as Dictionary
	return roundi(float(by_gp.get(faction, by_gp.get(str(faction), 0.0))))


## Ducats one clearing moved for one crown: what its fills paid and earned, plus
## the share its deeds and embassies drew (wiki: world-market § Trade orders,
## § First right of refusal). 0 for a court the clearing did not serve, so a bar
## naming the last clearing never prints a rival's trade as the crown's own
## (REQ-P5-05). A report whose `fills` is not a per-court map (an old save, a
## fixture that never traded) reads as no fills rather than as a cast failure.
static func clearing_net(report: Dictionary, faction: int) -> int:
	var fills: Variant = report.get("fills", {})
	var mine: Dictionary = {}
	if typeof(fills) == TYPE_DICTIONARY:
		var row: Variant = (fills as Dictionary).get(
			faction, (fills as Dictionary).get(str(faction), {})
		)
		if typeof(row) == TYPE_DICTIONARY:
			mine = row
	return (
		int(mine.get("earned", 0)) - int(mine.get("spent", 0))
		+ share_credit(report, faction)
	)


## The fills that paid the crown's share, one row per deal: the owner's cut of a
## rival's buy on its sold ground first, then the embassy kickbacks (wiki:
## world-market-first-right-of-refusal § Profit formula, § Eligibility). The
## total above them is a bare number until these rows say who bought what (REQ-
## P5-05: a receipt names every line it spends). The ducats stay on the total and
## off the rows, because one deal's known price and quantity would publish the
## sealed relation score (DR-20261118-05).
static func share_rows(report: Dictionary, faction: int) -> Array[Dictionary]:
	var credits: Dictionary = report.get("credits", {}) as Dictionary
	var rows: Array[Dictionary] = []
	for raw: Variant in credits.get("rows", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = raw
		if int(deal.get("owner", -1)) == faction and float(deal.get("owner_credit", 0.0)) > 0.0:
			rows.append(_share_row(deal, "deed"))
	for raw: Variant in credits.get("rows", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = raw
		for raw_kick: Variant in deal.get("kickbacks", []):
			if typeof(raw_kick) != TYPE_DICTIONARY:
				continue
			var kick: Dictionary = raw_kick
			if int(kick.get("faction", -1)) != faction or float(kick.get("credit", 0.0)) <= 0.0:
				continue
			rows.append(_share_row(deal, "embassy"))
	return rows


static func _share_row(deal: Dictionary, kind: String) -> Dictionary:
	return {
		"kind": kind,
		"buyer": int(deal.get("buyer", -2)),
		"seller": int(deal.get("seller", -2)),
		"commodity": String(deal.get("commodity", "")),
		"quantity": int(deal.get("quantity", 0)),
	}


## One share row in words: which rule paid, and the buy that paid it. A court no
## longer in the catalogue (an absorbed Minor, an older save) reads as it was
## named when the clearing settled.
static func share_row_line(row: Dictionary) -> String:
	var quantity: int = int(row.get("quantity", 0))
	var commodity: String = CommodityCatalog.label(String(row.get("commodity", "")))
	var words: String = "%s bought %d %s from %s" % [
		FactionCatalog.name_of(int(row.get("buyer", -2))), quantity, commodity,
		FactionCatalog.name_of(int(row.get("seller", -2))),
	]
	if String(row.get("kind", "")) == "deed":
		return "Our deed's share — " + words
	return "Our embassy's kickback — " + words


## One line of the Deal Book. A purchase names the price the pair was charged —
## the crown's terms and the subsidy step included — and the ducats it cost; a
## sale names its receipt (wiki: world-market § Subsidy price adjustment;
## REQ-P5-05). `price` is the untaxed published price, so older saved rows that
## carry no `buy_unit` still read.
static func deal_line(deal: Dictionary, viewer: int = FactionCatalog.PLAYER_FACTION) -> String:
	var quantity: int = int(deal.get("quantity", 0))
	var commodity: String = CommodityCatalog.label(String(deal.get("commodity", "")))
	var price: int = int(deal.get("price", 0))
	var buyer: int = int(deal.get("buyer", -2))
	var seller: int = int(deal.get("seller", -2))
	var mine: bool = buyer == viewer
	var other_id: int = seller if mine else buyer
	var other: String = "the world market" if other_id < 0 else FactionCatalog.name_of(other_id)
	if mine:
		var claim: String = (
			" as its favoured partner" if bool(deal.get("is_favoured", false)) else ""
		)
		# The one thing a deed buys the crown is this fill: the owner's bid takes
		# its sold ground's unit before any tier, and the row must say so or the
		# right is invisible on the purchase it won (wiki: world-market § First
		# right of refusal — Priority override).
		if bool(deal.get("is_frr", false)):
			claim = " as its deed's first refusal"
		var unit: int = int(deal.get("buy_unit", price))
		# The debt is rounded once from the whole deal, so the per-unit ask need
		# not multiply to it: name the ducats the clearing charged, and say so
		# when the rounded rate is what moved them (wiki: world-market § Subsidy
		# price adjustment; REQ-P5-05).
		var paid: int = int(deal.get("cost", unit * quantity))
		if quantity > 0 and unit * quantity != paid:
			claim += " (rounded from the deal)"
		return "Bought %d %s from %s at %s — %s%s" % [
			quantity, commodity, other, MoneyText.thousands(unit),
			MoneyText.ducats(paid), claim,
		]
	var earned: int = int(deal.get("earned", price * quantity))
	# A sale's receipt is rounded from the whole deal, so the published price need
	# not multiply to it: name the rate that moved it (REQ-P5-05).
	var note: String = ""
	if quantity > 0 and price * quantity > 0 and earned != price * quantity:
		note = " (exports %d%%)" % roundi(100.0 * float(earned) / float(price * quantity))
	return "Sold %d %s to %s at %s — %s%s" % [
		quantity, commodity, other, MoneyText.thousands(price),
		MoneyText.ducats(earned), note,
	]


## The cargo-holds banner above the market rows (wiki: ships-and-naval).
## Extraction ships before trade, so the banner names the colonial tonnage the
## home fleet must carry first (DR-20261109-17).
static func cargo_line(cargo: Dictionary) -> String:
	var holds: int = int(cargo.get("holds", -1))
	if holds < 0:
		return "Cargo holds unknown."
	if holds <= 0:
		return "No cargo holds — launch a merchant hull or moor the home squadron."
	var free: int = int(cargo.get("free", holds))
	var reserved: int = int(cargo.get("reserved", 0))
	if reserved > 0:
		return "CARGO  %d holds  ·  %d for the colonies  ·  %d free this turn" % [
			holds, reserved, free
		]
	return "CARGO  %d holds  ·  %d free this turn" % [holds, free]


static func cargo_color(cargo: Dictionary) -> Color:
	var holds: int = int(cargo.get("holds", -1))
	if holds < 0:
		return Palette.TEXT_DIM
	if holds <= 0:
		return Palette.GOLD_PALE
	return Palette.TEXT


## The bid budget above the market rows: the purse the auction may spend after
## the turn's waiting Build/work orders are paid (wiki: world-market § Treasury
## budget for bids; DR-20261115-13). A promised purse is named, never hidden —
## the refusal a crown meets on a bid is this line's own figure (REQ-P5-05).
## A purse in debt is named as debt: the auction may spend nothing, and printing
## the clamped `max(0, treasury)` as "the whole purse" would name a sum the
## crown does not hold (the college's lending floor put it there).
static func bid_budget_line(budget: Dictionary) -> String:
	var purse: int = int(budget.get("purse", budget.get("treasury", 0)))
	var promised: int = int(budget.get("promised", 0))
	var left: int = int(budget.get("budget", 0))
	var orders: int = (budget.get("orders", []) as Array).size()
	var count: String = "%d waiting order%s" % [orders, "" if orders == 1 else "s"]
	if purse < 0:
		if promised <= 0:
			return "BIDS  nothing this turn — the purse is %s ducats in debt" % (
				TextFormat.thousands(-purse)
			)
		return "BIDS  nothing this turn — the purse is %s ducats in debt and %s more promised to %s" % [
			TextFormat.thousands(-purse), TextFormat.thousands(promised), count,
		]
	if promised <= 0:
		return "BIDS  the whole purse — %s ducats" % TextFormat.thousands(purse)
	if left <= 0:
		return "BIDS  nothing this turn — %s ducats promised to %s" % [
			TextFormat.thousands(promised), count
		]
	return "BIDS  %s of %s ducats — %s promised to %s" % [
		TextFormat.thousands(left), TextFormat.thousands(purse),
		TextFormat.thousands(promised), count,
	]


static func bid_budget_color(budget: Dictionary) -> Color:
	return Palette.GOLD_PALE if int(budget.get("budget", 0)) <= 0 else Palette.TEXT


## The clearing's price pass in one line: the goods that moved and the price they
## now stand at, so a turn's new market is read and never a silent change (wiki:
## world-market § Price discovery; REQ-P5-05). Empty when no price moved.
static func price_moves_line(report: Dictionary, limit: int = 4) -> String:
	var moved: Dictionary = report.get("prices", {}) as Dictionary
	if moved.is_empty():
		return ""
	var ids: Array[String] = []
	for raw: Variant in moved.keys():
		ids.append(String(raw))
	ids.sort()
	var parts: PackedStringArray = []
	for index in mini(ids.size(), limit):
		var id: String = ids[index]
		parts.append("%s %d" % [CommodityCatalog.label(id), int(moved[id])])
	var text: String = "Prices moved: " + "  ·  ".join(parts)
	if ids.size() > limit:
		text += "  ·  +%d more" % (ids.size() - limit)
	return text + "."


## One plain sentence for the court's trade diplomacy, so an adjusted price is
## never a mystery (wiki: world-market § FTP; REQ-P2-03). Empty when the market
## carries no terms for this viewer.
static func terms_line(market: WorldMarket, viewer: int) -> String:
	if market == null:
		return ""
	var terms: Dictionary = market.terms_for(viewer)
	if terms.is_empty():
		return ""
	var buy: Dictionary = terms.get("buy", {})
	var sell: Dictionary = terms.get("sell", {})
	var buy_rate: float = float(buy.get("*", 1.0))
	var sell_rate: float = float(sell.get("*", 1.0))
	var text: String = "Trade terms: imports at %d%% and exports at %d%% of the world price." % [
		roundi(buy_rate * 100.0), roundi(sell_rate * 100.0)
	]
	var subsidy: int = MarketRules.subsidy_rate_paid(market, viewer)
	if subsidy > 0:
		text += " Subsidy %d%%: a subsidised court's goods cost us more, ours earn less." % subsidy
	# A boycotted crown's rate is worse for a reason a price never states: name
	# the bar, and the closed rows the plate prints under each colony (wiki:
	# diplomacy § GP–Tribe — Boycott, R6).
	var issuers: PackedStringArray = []
	for raw: Variant in MinorMarket.sealed_for(market, viewer).values():
		var name: String = FactionCatalog.name_of(int(raw))
		if not issuers.has(name):
			issuers.append(name)
	if not issuers.is_empty():
		text += " Boycotted by %s: no deal of ours clears with its colonies." % (
			", ".join(issuers)
		)
	return text


## One-line market clearing report for the turn toast: the crown's fills and
## any carried or dropped orders (wiki: world-market § Trade orders). A sale
## names the ducats it paid, and the overseas share is named too: the auction
## is the one purse movement the per-turn figure cannot project.
static func market_summary(report: Dictionary, faction: int) -> String:
	var parts: PackedStringArray = []
	var fills: Dictionary = report.get("fills", {}) as Dictionary
	var mine: Dictionary = fills.get(faction, fills.get(str(faction), {})) as Dictionary
	var bought: int = int(mine.get("bought", 0))
	var sold: int = int(mine.get("sold", 0))
	if bought > 0:
		parts.append("bought %d for %s" % [bought, MoneyText.ducats(int(mine.get("spent", 0)))])
	if sold > 0:
		var earned: int = int(mine.get("earned", 0))
		parts.append(
			"sold %d for %s" % [sold, MoneyText.ducats(earned)]
			if earned > 0 else "sold %d" % sold
		)
	var share: int = share_credit(report, faction)
	if share > 0:
		parts.append("%s in shares" % MoneyText.ducats(share))
	var carry: int = (report.get("carry", []) as Array).size()
	if carry > 0:
		parts.append("%d order%s carried" % [carry, "" if carry == 1 else "s"])
	var dropped: int = 0
	for note: Variant in report.get("notes", []):
		if typeof(note) != TYPE_DICTIONARY:
			continue
		var code: String = String((note as Dictionary).get("code", ""))
		if code.begins_with("carry_forward_dropped") and int(
			(note as Dictionary).get("faction", -1)
		) == faction:
			dropped += 1
	if dropped > 0:
		parts.append("%d order%s lapsed" % [dropped, "" if dropped == 1 else "s"])
	if parts.is_empty():
		return ""
	return "The market cleared: " + "  ·  ".join(parts) + "."
