extends SceneTree
## Headless free-playtest drive for a deed's first right of refusal — the half a
## crown never presses (wiki: world-market § First right of refusal;
## world-market-first-right-of-refusal § Eligibility; civilian-units § Merchant —
## the deed row; DR-20261118-05). A Merchant's deed promises "a rival's buy pays
## you a share", but the crown only meets that promise in a clearing it did not
## bid in: a rival fills the sold tile's unit and the owner's cut arrives with the
## turn. The drive seats that state on the turn-100 advanced start (the tier's
## round-robin Minor deeds), bids as a rival court and lets a real turn close.
##
## It then reads every surface a player has: the crew's own Deed row, the MARKET
## tab's LAST CLEARING, the turn's despatch line, the treasury the credit moved,
## and the Deal Book rows. Scenario B reverses it — the crown bids on its own
## deed's units and must fill before a higher-priority rival (Priority override).
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_deed_share.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0

var _steps: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _failed: int = 0
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = await Launch.open_map(
		self, SEED_TEXT, SETUP_SIZE_INDEX, AdvancedStart.TURNS100
	)
	if screen == null:
		_finish()
		return
	_screen = screen
	var play: PlaySession = screen.play
	_say("seed %s — turn %d, treasury %s" % [
		SEED_TEXT, play.turn, DiplomacyCatalog.money(play.treasury()),
	])
	var deeds: Array[Dictionary] = _deeds(play)
	_say("the crown holds %d deeds that publish a unit" % deeds.size())
	for deed: Dictionary in deeds.slice(0, 6):
		var model: MapModel = deed["model"]
		var tile: Vector2i = deed["tile"]
		_say("  %s (%d, %d) in %s — %s" % [
			CommodityCatalog.label(String(deed["commodity"])), tile.x, tile.y,
			FactionCatalog.name_of((deed["province"] as ProvinceState).owner),
			DeedTerms.held_line(model, tile),
		])
	if deeds.is_empty():
		_say("no deed on the chart — the payoff cannot be read")
		_finish()
		return
	_read_deed_rows(play, deeds)
	_scenario_rival_fill(play, deeds)
	_scenario_own_bid(play, deeds)
	_finish()


# --- the crew's own Deed row ------------------------------------------------


## The row a Merchant's sheet prints under its price, and the row it prints once
## the ground is bought: what the deed promises the crown (DR-20261118-05).
func _read_deed_rows(play: PlaySession, deeds: Array[Dictionary]) -> void:
	var deed: Dictionary = deeds[0]
	var model: MapModel = deed["model"]
	var tile: Vector2i = deed["tile"]
	_say("--- the crew's Deed row on aim ---")
	_say("  held: %s" % DeedTerms.held_line(model, tile))
	var unsold: Vector2i = _unsold_tile(play, model, deed["province"])
	if unsold.x >= 0:
		_say("  a neighbouring deed's promise: %s" % DeedTerms.order_line(model, unsold))
	_check(DeedTerms.holder(model, tile) == play.player_faction, "the deed is the crown's")
	_check(not DeedTerms.commodity(model, tile).is_empty(), "the deed publishes a unit")


# --- scenario A: a rival's fill pays the crown ------------------------------


## The crown stages nothing; a rival buys the sold tile's harvest; the turn
## closes. R8.2 pays the owner the relation share of the rival's clear price
## (wiki: world-market-first-right-of-refusal § Profit formula, § Treasury
## transfer). Every read below is a surface the crown has.
func _scenario_rival_fill(play: PlaySession, deeds: Array[Dictionary]) -> void:
	var deed: Dictionary = deeds[0]
	var model: MapModel = deed["model"]
	var tile: Vector2i = deed["tile"]
	var commodity: String = String(deed["commodity"])
	var seller: int = (deed["province"] as ProvinceState).owner
	var rival: int = _rival(play, seller)
	_say("--- A: %s buys %s out of %s's sold ground ---" % [
		FactionCatalog.name_of(rival), CommodityCatalog.label(commodity),
		FactionCatalog.name_of(seller),
	])
	if rival < 0:
		_say("no rival court stands to bid")
		return
	var units: int = _table_units(play, commodity)
	var staged: Dictionary = MarketOrders.submit(
		play.economy.market, rival, commodity, MarketOrder.SIDE_BID, mini(units, 40),
		{
			"cargo_free": maxi(units, 1) + 8, "treasury": 20000,
			"buy_price": play.economy.market.buy_price(commodity, rival),
		},
		1
	)
	_say("staged the rival's bid — ok=%s %s" % [
		str(staged.get("ok", false)), String(staged.get("reason", "")),
	])
	if not bool(staged.get("ok", false)):
		return
	_check(_crown_staged(play) == 0, "the crown has staged no order of its own")
	var before: int = play.treasury()
	var relation: float = _relation(play, play.player_faction, seller)
	_say("the crown's relation with %s: %.0f" % [FactionCatalog.name_of(seller), relation])
	_end_turn(play)
	var report: Dictionary = play.market_report
	var paid: int = play.treasury() - before
	_say("the purse moved %+d ducats across the clearing" % paid)
	var mine: Array[Dictionary] = _deed_deals(report, model, tile)
	_say("deals attributed to the crown's deed tile: %d" % mine.size())
	for deal: Dictionary in mine:
		_say("  %s" % _deal_words(deal))
	var share: int = LedgerMarketText.share_credit(report, play.player_faction)
	_say("the clearing paid the crown %d ducats in shares" % share)
	var owner_credit: float = _owner_credit(report, play.player_faction)
	_say("its own deed's cut: %d ducats" % roundi(owner_credit))
	if not mine.is_empty():
		var first: Dictionary = mine[0]
		var expect: float = FirstRight.profit(
			relation, int(first.get("quantity", 0)), float(first.get("price", 0.0))
		)
		_say("the rival paid %d x %d at %.0f — the rule's share is %d" % [
			int(first.get("quantity", 0)), int(first.get("price", 0.0)),
			relation, roundi(expect),
		])
		_check(roundi(owner_credit) == roundi(expect), "the deed's cut is the rule's share")
	_check(share > 0, "a rival's fill paid the crown something")
	_check(paid >= share, "the purse carries at least the share the page prints")
	_read_market(play, "the MARKET tab after a rival's fill")
	var lines: PackedStringArray = _page_lines(play)
	var named: bool = false
	for line: String in lines:
		if line.begins_with("Our deed's share") and line.contains(
			FactionCatalog.name_of(rival)
		):
			named = true
	_check(named, "the clearing names the rival's buy the deed's share paid on")
	_say("the turn's despatch: %s" % _last_toast(play))
	_say("the clearing line: %s" % LedgerMarketText.market_summary(report, play.player_faction))


# --- scenario B: the crown bids on its own deed -----------------------------


## The crown's own bid fills the sold tile before any tier (wiki: world-market
## § First right of refusal — Priority override), even against a rival staged at
## a better priority. The row it reads must let it tell that fill apart.
func _scenario_own_bid(play: PlaySession, deeds: Array[Dictionary]) -> void:
	var deed: Dictionary = _pick_bid_deed(play, deeds)
	if deed.is_empty():
		_say("--- B: no deed left to bid on ---")
		return
	var commodity: String = String(deed["commodity"])
	var seller: int = (deed["province"] as ProvinceState).owner
	var rival: int = _rival(play, seller)
	_say("--- B: the crown bids first on its own deed's %s ---" % CommodityCatalog.label(commodity))
	play.economy.open_panel()
	var pressed: int = _press_offer_bid(play, seller, commodity)
	_say("pressed the offer row's Bid — %s" % _last_toast(play))
	_check(pressed > 0, "the offer row stages the crown's bid")
	if pressed <= 0:
		return
	var units: int = mini(_table_units(play, commodity), 40)
	var staged: Dictionary = MarketOrders.submit(
		play.economy.market, rival, commodity, MarketOrder.SIDE_BID, units,
		{
			"cargo_free": units + 8, "treasury": 20000,
			"buy_price": play.economy.market.buy_price(commodity, rival),
		},
		1
	)
	_say("staged the rival at priority 1 (%d units) — ok=%s" % [units, str(staged.get("ok", false))])
	_end_turn(play)
	var report: Dictionary = play.market_report
	var mine: Array[Dictionary] = _first_right_deals(report, play.player_faction)
	_say("the crown's own first-refusal fills: %d" % mine.size())
	for deal: Dictionary in mine:
		_say("  %s" % _deal_words(deal))
		_say("  the row the crown reads: %s" % LedgerMarketText.deal_line(
			deal, play.player_faction
		))
	_check(not mine.is_empty(), "the crown's bid took its deed's ground before the tier")
	var row_ok: bool = not mine.is_empty() and LedgerMarketText.deal_line(
		mine[0], play.player_faction
	).contains("as its deed's first refusal")
	_check(row_ok, "the purchase row names the deed's first refusal")
	_read_market(play, "the MARKET tab after the crown's own fill")
	_say("the turn's despatch: %s" % _last_toast(play))


# --- reading ---------------------------------------------------------------


func _read_market(play: PlaySession, when: String) -> void:
	play.economy.open_panel()
	_say("--- %s ---" % when)
	for line: String in _page_lines(play):
		if line == "SELLER" or line == "GOOD" or line == "SORT" or line.begins_with("20 offers"):
			break
		_say("  " + line)


func _page_lines(play: PlaySession) -> PackedStringArray:
	var panel: EconomyPanel = play.hud.panels.economy_panel
	if panel == null:
		return PackedStringArray()
	var page: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	if page == null:
		return PackedStringArray()
	return _labels(page)


func _labels(node: Node) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	_collect_labels(node, lines)
	return lines


func _collect_labels(node: Node, lines: PackedStringArray) -> void:
	for child: Node in node.get_children():
		if child is Label:
			var text: String = (child as Label).text.strip_edges()
			if not text.is_empty():
				lines.append(text)
		_collect_labels(child, lines)


func _deal_words(deal: Dictionary) -> String:
	return "%s %s from %s at %d x %d · is_frr=%s%s" % [
		FactionCatalog.name_of(int(deal.get("buyer", -2))),
		CommodityCatalog.label(String(deal.get("commodity", ""))),
		FactionCatalog.name_of(int(deal.get("seller", -2))),
		int(deal.get("quantity", 0)), int(deal.get("price", 0.0)),
		str(deal.get("is_frr", false)),
		" · origin %d/%d" % [
			int(deal.get("origin_region", -1)), int(deal.get("origin_index", -1)),
		],
	]


# --- state -----------------------------------------------------------------


## Every deed the crown holds whose tile still publishes a unit: what a rival
## can buy that pays the owner a share (DeedTerms.commodity).
func _deeds(play: PlaySession) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for model: MapModel in play.world.regions:
		for province: ProvinceState in model.provinces:
			for tile: Vector2i in province.tiles:
				if DeedTerms.holder(model, tile) != play.player_faction:
					continue
				var commodity: String = DeedTerms.commodity(model, tile)
				if commodity.is_empty():
					continue
				out.append({
					"model": model, "tile": tile, "province": province,
					"commodity": commodity,
				})
	return out


## The province's first resource tile no court has bought, for the promise a
## fresh deed prints (DeedTerms.order_line).
func _unsold_tile(play: PlaySession, model: MapModel, province: ProvinceState) -> Vector2i:
	for tile: Vector2i in province.tiles:
		if model.is_purchased_tile(tile):
			continue
		if DeedTerms.order_line(model, tile).is_empty():
			continue
		return tile
	return Vector2i(-1, -1)


## A deed whose good the crown can still bid on this turn: the seller's row is
## on the plate and the crown's purse covers one unit.
func _pick_bid_deed(play: PlaySession, deeds: Array[Dictionary]) -> Dictionary:
	for deed: Dictionary in deeds:
		var seller: int = (deed["province"] as ProvinceState).owner
		var commodity: String = String(deed["commodity"])
		if _offer_quantity(play, seller, commodity) <= 0:
			continue
		if play.economy.market.buy_price(commodity, play.player_faction) > play.treasury():
			continue
		return deed
	return {}


func _offer_quantity(play: PlaySession, seller: int, commodity: String) -> int:
	for raw: Variant in play.economy.market.minor_offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if int(row.get("faction", -1)) != seller:
			continue
		if String(row.get("commodity", "")) != commodity:
			continue
		return int(row.get("quantity", 0))
	return 0


## Every unit of one commodity on the whole Minor/Tribe table, so the rival's bid
## reaches the sold tile whatever clears first.
func _table_units(play: PlaySession, commodity: String) -> int:
	var total: int = 0
	for raw: Variant in play.economy.market.minor_offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if String(row.get("commodity", "")) == commodity:
			total += int(row.get("quantity", 0))
	return total


func _crown_staged(play: PlaySession) -> int:
	return play.economy.market.book.orders_for(play.player_faction).size()


func _rival(play: PlaySession, seller: int) -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction or faction == seller:
			continue
		if FactionCatalog.type_of(faction) != FactionCatalog.Type.GREAT_POWER:
			continue
		return faction
	return -1


func _relation(play: PlaySession, gp: int, minor: int) -> float:
	var record: DiplomacyRelation = play.diplomacy.relation(gp, minor) \
		if play.diplomacy != null else null
	return record.score if record != null else 0.0


func _deed_deals(report: Dictionary, model: MapModel, tile: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var region: int = model.region_id
	var index: int = model.index_of(tile.x, tile.y)
	for raw: Variant in report.get("deals", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = raw
		if int(deal.get("origin_region", -1)) != region:
			continue
		if int(deal.get("origin_index", -1)) != index:
			continue
		out.append(deal)
	return out


## The crown's own fills of a deed's ground: the pre-pass deals the matcher
## flagged, so a drive can tell the right apart from an ordinary tier win.
func _first_right_deals(report: Dictionary, faction: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in report.get("deals", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = raw
		if int(deal.get("buyer", -2)) != faction:
			continue
		if not bool(deal.get("is_frr", false)):
			continue
		out.append(deal)
	return out


func _owner_credit(report: Dictionary, faction: int) -> float:
	var credits: Dictionary = report.get("credits", {}) as Dictionary
	for raw: Variant in credits.get("rows", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if int(row.get("owner", -1)) != faction:
			continue
		return float(row.get("owner_credit", 0.0))
	return 0.0


## Presses the Bid on the offer row that names both the seller and the good — the
## plate's own button, so the order goes through the controller a player uses. The
## rows and their presses are drawn in one order, so the index picks the pair.
func _press_offer_bid(play: PlaySession, seller: int, commodity: String) -> int:
	var panel: EconomyPanel = play.hud.panels.economy_panel
	if panel == null:
		return 0
	var page: LedgerMarket = panel.page_body(EconomyPanel.TAB_MARKET) as LedgerMarket
	if page == null:
		return 0
	var rows: Array[Dictionary] = page.visible_offers()
	var buttons: Array[Button] = page.offer_buttons()
	for index in mini(rows.size(), buttons.size()):
		var row: Dictionary = rows[index]
		if int(row.get("faction", -1)) != seller:
			continue
		if String(row.get("commodity", "")) != commodity:
			continue
		var button: Button = buttons[index]
		if button.disabled:
			return 0
		button.pressed.emit()
		return 1
	return 0


func _end_turn(play: PlaySession) -> void:
	var start_turn: int = play.turn
	for _attempt in 12:
		MapPlayTurn.end_turn(play)
		if play.turn != start_turn:
			return
		var human: int = play.player_faction
		if CallToArms.has_pending(play.diplomacy, human):
			MapCourtOrders.apply(play, CallToArms.KIND_REFUSE, human, "")
		elif Intervention.has_pending(play.diplomacy, human):
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, human):
			MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, human, "")
		else:
			return
		if play.turn != start_turn:
			return
	_say("the turn would not close")


func _last_toast(play: PlaySession) -> String:
	var despatches: HudDespatches = play.hud.despatches
	if despatches == null:
		return "no despatch"
	var waiting: PackedStringArray = despatches.waiting()
	if not waiting.is_empty():
		return waiting[waiting.size() - 1]
	var newest: String = despatches.newest_live_text()
	return newest if not newest.is_empty() else "no despatch"


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	_say("%s %s" % ["ok  " if ok else "FAIL", what])


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_deed_share: %d steps, %d checks, %d failed ---" % [
		_steps.size(), _checks, _failed,
	])
	quit()
