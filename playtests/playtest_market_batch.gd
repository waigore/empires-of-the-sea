extends SceneTree
## Headless free-playtest drive for the market's whole-order (batch) presses
## (wiki: world-market § Trade orders — one order carries a positive integer
## quantity; § Treasury budget for bids. REQ-P5-04, REQ-P5-05).
##
## The batch press is the newest way a crown files market orders: `MarketBatch`
## reads the validator's own caps forward so one press is never an order the
## single press would have refused. This drive reads that promise where a player
## meets it — the MARKET tab's row presses, their labels, their captions and the
## toasts the controller answers with — and presses them past their own cap.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_market_batch.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
## The page's own row order: LedgerMarket draws one row per commodity, category
## by category, so the drive pairs its blocks by that order (REQ-P3-02).
const PAGE_CATEGORIES: Array = [
	CommodityCatalog.Category.FOOD,
	CommodityCatalog.Category.RAW,
	CommodityCatalog.Category.MANUFACTURED,
]

var _steps: PackedStringArray = PackedStringArray()
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
	_read_presses(play, "the presses the page offers before any order")
	_read_offer_repaint(play)
	_read_production_claim(play)
	_read_offer_cap(play)
	_read_minor_row(play)
	_read_bid_repaint(play)
	_finish()


# --- the batch presses ------------------------------------------------------


## Every batch press on the page, its label and every row's own reading: the
## figure the crown is asked to trust before one press spends the whole order.
func _read_presses(play: PlaySession, when: String) -> void:
	play.economy.open_panel()
	var page: LedgerMarket = _market_page(play)
	if page == null:
		_say("no MARKET tab")
		return
	_say("--- %s ---" % when)
	for key: String in _sorted_keys(page.batch_buttons()):
		if key.contains(":"):
			continue
		var minor: Button = page.batch_buttons()[key] as Button
		_say("  minor %s — [%s] %s" % [key, "off" if minor.disabled else "on", minor.text])
	for id: String in _page_ids():
		_say("  row %s: %s" % [id, _row_text(page, id)])


## One staged offer must move the row's own reading: the caption and the presses
## are the crown's only account of the cap (REQ-P2-03, REQ-P5-05).
func _read_offer_repaint(play: PlaySession) -> void:
	play.economy.open_panel()
	var page: LedgerMarket = _market_page(play)
	var ledger: PlayerEconomy = play.economy.economy
	if page == null:
		return
	var key: String = _first_key(page, "offer:")
	if key.is_empty():
		_say("no offer batch to press")
		return
	var commodity: String = key.split(":")[1]
	_say("--- one offer staged off the row: %s ---" % commodity)
	_say("  before: %s (held %d, claimed %d, promised %d)" % [
		_batch_text(page, key), ledger.quantity(commodity),
		int(_reserved(play).get(commodity, 0)),
		play.economy.market.book.pending_sell_units(play.player_faction, commodity),
	])
	var single: Button = _single_in(page, commodity, "Offer")
	if single == null or single.disabled:
		_say("  the single Offer is dead — nothing to stage")
		return
	single.pressed.emit()
	_say("  pressed the single Offer — %s" % _last_toast(play))
	play.economy.open_panel()
	page = _market_page(play)
	_say("  after: %s (promised %d)" % [
		_batch_text(page, key),
		play.economy.market.book.pending_sell_units(play.player_faction, commodity),
	])
	_say("  single Offer: %s" % _single_state(page, commodity, "Offer"))
	_say("  row now reads: %s" % _row_text(page, commodity))


## A production run claims its inputs before the auction, so the Offer press must
## leave them out — the row's own caption already says it does (wiki:
## world-market § Trade orders — the offer cap is the post-production stockpile
## minus industry reservations).
func _read_production_claim(play: PlaySession) -> void:
	play.economy.open_panel()
	var page: LedgerMarket = _market_page(play)
	var ledger: PlayerEconomy = play.economy.economy
	if page == null:
		return
	var recipe: String = ""
	var commodity: String = ""
	for candidate: String in ["lumber", "paper", "castIron", "fabric_from_wool", "bronze"]:
		var needed: Dictionary = ProductionRecipes.inputs(candidate)
		for id: Variant in needed.keys():
			var want: int = int(needed[id])
			if ledger.quantity(String(id)) >= want + 2:
				recipe = candidate
				commodity = String(id)
				break
		if not recipe.is_empty():
			break
	if recipe.is_empty():
		_say("no held input to claim by production")
		return
	_say("--- production claims the row: %s eats %s ---" % [recipe, commodity])
	ledger.production.set_assignment(recipe, 1)
	play.economy.refresh_panel()
	page = _market_page(play)
	var key: String = "offer:%s" % commodity
	_say("  held %d, claimed %d, promised %d" % [
		ledger.quantity(commodity),
		int(_reserved(play).get(commodity, 0)),
		play.economy.market.book.pending_sell_units(play.player_faction, commodity),
	])
	_say("  row reads: %s" % _row_text(page, commodity))
	_say("  batch reads: %s" % _batch_text(page, key))
	var press: Button = page.batch_buttons().get(key) as Button
	if press == null:
		_say("  no batch press — the single press is the whole order")
		return
	press.pressed.emit()
	_say("  pressed the batch — %s" % _last_toast(play))
	_say("  staged now: %d %s" % [
		play.economy.market.book.pending_sell_units(play.player_faction, commodity),
		commodity,
	])
	ledger.production.set_assignment(recipe, 0)
	play.economy.refresh_panel()


## The single press must stop where the batch stops: the sellable readout is the
## live cap (stock after reservations and the tons already offered), and a press
## past it is an order the validator refuses (wiki: world-market § Trade orders —
## per-commodity quantity cap; REQ-P2-03, REQ-P5-05).
func _read_offer_cap(play: PlaySession) -> void:
	play.economy.open_panel()
	var page: LedgerMarket = _market_page(play)
	var ledger: PlayerEconomy = play.economy.economy
	if page == null:
		return
	var recipe: String = ""
	var commodity: String = ""
	for candidate: String in ["lumber", "paper", "fabric_from_wool"]:
		var needed: Dictionary = ProductionRecipes.inputs(candidate)
		for id: Variant in needed.keys():
			var want: int = int(needed[id])
			if ledger.quantity(String(id)) >= want + 1:
				recipe = candidate
				commodity = String(id)
				break
		if not recipe.is_empty():
			break
	if recipe.is_empty():
		_say("no held input to read the offer cap")
		return
	_say("--- pressing the single Offer past its own cap: %s ---" % commodity)
	ledger.production.set_assignment(recipe, 1)
	play.economy.refresh_panel()
	for step in 5:
		page = _market_page(play)
		_say("  %d. row: %s" % [step + 1, _row_text(page, commodity)])
		var single: Button = _single_in(page, commodity, "Offer")
		if single == null or single.disabled:
			_say("     the single Offer is shut — the cap holds")
			break
		single.pressed.emit()
		_say("     pressed Offer — %s" % _last_toast(play))
	ledger.production.set_assignment(recipe, 0)
	play.economy.refresh_panel()


## A bid batch empties the holds it files; the row must re-read at once, or the
## next press files an order the rules refuse (REQ-P2-03, REQ-P5-04).
func _read_bid_repaint(play: PlaySession) -> void:
	play.economy.open_panel()
	var page: LedgerMarket = _market_page(play)
	if page == null:
		return
	var key: String = _first_key(page, "bid:")
	if key.is_empty():
		_say("no bid batch to press")
		return
	var commodity: String = key.split(":")[1]
	_say("--- the bid batch: %s ---" % commodity)
	_say("  before: %s" % _batch_text(page, key))
	var press: Button = page.batch_buttons()[key] as Button
	press.pressed.emit()
	_say("  pressed the batch — %s" % _last_toast(play))
	_say("  staged now: %d units" % play.economy.market.book.pending_buy_units(
		play.player_faction
	))
	play.economy.open_panel()
	page = _market_page(play)
	_say("  after: %s" % _batch_text(page, key))
	_say("  single Bid: %s" % _single_state(page, commodity, "Bid"))
	_say("  row now reads: %s" % _row_text(page, commodity))


## The Minor/Tribe row's batch: the seller's whole row in one press, at the ask
## the clearing charges that pair (wiki: world-market § Subsidy price adjustment;
## § Treasury budget for bids). A surcharge raises the ask above the world price,
## so the purse must be read at the ask the press prints.
func _read_minor_row(play: PlaySession) -> void:
	play.economy.open_panel()
	var page: LedgerMarket = _market_page(play)
	var ledger: PlayerEconomy = play.economy.economy
	if page == null:
		return
	var row_id: String = ""
	for key: String in _sorted_keys(page.batch_buttons()):
		if key.begins_with("bid:") or key.begins_with("offer:"):
			continue
		row_id = key
		break
	_say("--- the Minor/Tribe row ---")
	if row_id.is_empty():
		_say("  no Minor/Tribe row batches this turn")
		return
	var offer: Dictionary = {}
	for raw: Variant in play.economy.market.minor_offers:
		var row: Dictionary = raw
		if String(row.get("id", "")) == row_id:
			offer = row
			break
	var seller: int = int(offer.get("faction", -1))
	var commodity: String = String(offer.get("commodity", ""))
	var old_treasury: int = ledger.treasury
	var old_subsidy: int = play.diplomacy.subsidy(play.player_faction, seller)
	# A surcharge the crown pays on this pair, and a purse that binds at the ask
	# but not at the world price: the press must not promise more than it pays.
	play.diplomacy.set_subsidy(play.player_faction, seller, 20)
	DiplomacyTrade.apply_terms(play.diplomacy, play.world, play.economy.market)
	var ask: int = MinorMarket.ask_for_reader(play.economy.market, offer, play.player_faction)
	ledger.treasury = ask * 3 + ask / 2
	play.economy.refresh_panel()
	page = _market_page(play)
	var press: Button = page.batch_buttons().get(row_id) as Button
	_say("  %s sells %d %s; world price %d, ask %d, purse %d" % [
		FactionCatalog.name_of(seller), int(offer.get("quantity", 0)), commodity,
		play.economy.market.buy_price(commodity, play.player_faction), ask, ledger.treasury,
	])
	if press == null:
		_say("  no batch press at this purse")
	else:
		_say("  batch reads: %s" % press.text)
		press.pressed.emit()
		_say("  pressed the batch — %s" % _last_toast(play))
		_say("  staged now: %d units" % play.economy.market.book.pending_buy_units(
			play.player_faction
		))
		_end_turn(play)
		_read_pair_deals(play, seller, commodity)
	ledger.treasury = old_treasury
	if old_subsidy > 0:
		play.diplomacy.set_subsidy(play.player_faction, seller, old_subsidy)
	else:
		play.diplomacy.cancel_subsidy(play.player_faction, seller)
	DiplomacyTrade.apply_terms(play.diplomacy, play.world, play.economy.market)
	play.economy.refresh_panel()


## The deals the clearing settled with one seller for one commodity: the units
## and the ducats, so a press that promised more than it paid is read.
func _read_pair_deals(play: PlaySession, seller: int, commodity: String) -> void:
	var found: bool = false
	for raw: Variant in play.market_report.get("deals", []):
		var deal: Dictionary = raw
		if int(deal.get("seller", -2)) != seller:
			continue
		if int(deal.get("buyer", -2)) != play.player_faction:
			continue
		if String(deal.get("commodity", "")) != commodity:
			continue
		found = true
		_say("  deal: %d %s for %d ducats" % [
			int(deal.get("quantity", 0)), commodity, int(deal.get("cost", 0)),
		])
	if not found:
		_say("  no deal with %s for %s cleared" % [FactionCatalog.name_of(seller), commodity])


# --- reading helpers --------------------------------------------------------


func _market_page(play: PlaySession) -> LedgerMarket:
	var panel: EconomyPanel = play.hud.panels.economy_panel
	if panel == null:
		return null
	return panel.page_body(EconomyPanel.TAB_MARKET) as LedgerMarket


func _reserved(play: PlaySession) -> Dictionary:
	return ProductionPhase.reserved_inputs(play.economy.economy.production.assignments())


func _sorted_keys(book: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in book.keys():
		keys.append(String(key))
	keys.sort()
	return keys


## The first batch key with this prefix, in the page's own order.
func _first_key(page: LedgerMarket, prefix: String) -> String:
	for key: String in _sorted_keys(page.batch_buttons()):
		if key.begins_with(prefix):
			return key
	return ""


## The commodities the page draws, in its own row order.
func _page_ids() -> Array[String]:
	var ids: Array[String] = []
	for category: Variant in PAGE_CATEGORIES:
		ids.append_array(CommodityCatalog.ids_in(category))
	return ids


## The page child that draws one commodity: the row itself, or the block that
## wraps it when it carries a batch press. Paired by the page's row order, so a
## row whose batch press is gone still reads.
func _row_control(page: LedgerMarket, commodity: String) -> Node:
	var ids: Array[String] = _page_ids()
	var index: int = ids.find(commodity)
	if index < 0:
		return null
	var rows: Array[Node] = []
	for child: Node in page.get_children():
		if child is Label:
			continue
		if _find_button(child, "Offer") != null:
			rows.append(child)
	if index >= rows.size():
		return null
	return rows[index]


func _row_text(page: LedgerMarket, commodity: String) -> String:
	var row: Node = _row_control(page, commodity)
	if row == null:
		return "(no row)"
	var bits: PackedStringArray = PackedStringArray()
	for line: String in _labels(row):
		bits.append(line)
	for button: Button in _buttons(row):
		bits.append("[%s] %s" % ["off" if button.disabled else "on", button.text.strip_edges()])
	return " | ".join(bits)


func _batch_text(page: LedgerMarket, key: String) -> String:
	var press: Button = page.batch_buttons().get(key) as Button
	if press == null:
		return "(no batch press)"
	return "[%s] %s" % ["off" if press.disabled else "on", press.text]


func _single_state(page: LedgerMarket, commodity: String, title: String) -> String:
	var button: Button = _single_in(page, commodity, title)
	if button == null:
		return "(absent)"
	return "[%s] %s" % ["off" if button.disabled else "on", button.text]


## The single Bid/Offer press of one commodity's row, read by the page's own row
## order rather than by the batch press that may have gone.
func _single_in(page: LedgerMarket, commodity: String, title: String) -> Button:
	var row: Node = _row_control(page, commodity)
	if row == null:
		return null
	return _find_button(row, title)


func _find_button(node: Node, title: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text.strip_edges() == title:
			return child as Button
		var found: Button = _find_button(child, title)
		if found != null:
			return found
	return null


func _buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child: Node in node.get_children():
		if child is Button:
			out.append(child as Button)
		out.append_array(_buttons(child))
	return out


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


## Closes one real turn, answering any pending decision the way the other drives
## do: answering a pending decision finishes the *suspended* turn, so the
## calendar is re-read before asking for another.
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


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_market_batch: %d steps ---" % _steps.size())
	quit()
