extends SceneTree
## Headless free-playtest drive for the colonial boycott's blocked-deal half
## (wiki: diplomacy § GP–Tribe — Boycott, R6; DR-20261115-03). A boycott needs a
## colony, a Great Power target at peace and a rival that will bid on the
## colony's goods, so no ordinary turn reaches it. The drive seats the two
## states a session cannot wait for — a rival holding the colony, and that rival
## boycotting the crown — then reads what each court is told:
##
## 1. the boycotted crown (the player) bids on the colony's own offer row while
##    the bar stands: the press, the staged order, the turn close, the Deal Book,
##    the despatch and the notes the clearing wrote;
## 2. the issuer's page for the boycotted court, which is where a boycott is
##    announced in words.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_boycott_block.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0

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
	var player: int = play.player_faction
	_say("seed %s — %s, turn %d, treasury %s" % [
		SEED_TEXT, FactionCatalog.name_of(player), play.turn,
		DiplomacyCatalog.money(play.treasury()),
	])
	var tribe: int = _trading_tribe(play)
	if tribe < 0:
		_say("no Tribe with goods on the table is in contact — the gate cannot open")
		_finish()
		return
	var rival: int = _rival(play, player)
	if rival < 0:
		_say("no rival court to seat the boycott")
		_finish()
		return
	_say("the colony will be %s (%d goods on the table)" % [
		FactionCatalog.name_of(tribe), _offer_units(play, tribe),
	])
	# Seated: the rival holds the Tribe as a colony, then closes it to us. A
	# session reaches this through the whole overture chain plus the rival's own
	# diplomacy, so the drive puts the two records in place and reads onward.
	play.diplomacy.set_colony(tribe, rival)
	var seated: Dictionary = DiplomacyBoycott.boycott(play.diplomacy, rival, player)
	_say("seated: colony_of(%s) = %s; boycott %s>%s %s — %s" % [
		FactionCatalog.name_of(tribe), FactionCatalog.name_of(play.diplomacy.colony_of(tribe)),
		FactionCatalog.name_of(rival), FactionCatalog.name_of(player),
		str(bool(seated.get("ok", false))), String(seated.get("message", seated.get("reason", ""))),
	])
	_say("blocked_by_boycott(us, colony) = %s" % str(
		DiplomacyBoycott.blocked(play.diplomacy, player, tribe)
	))
	if not bool(seated.get("ok", false)):
		_finish()
		return
	MapPlayDiplomacy.resolve_turn(play)
	_read_sheet(play, rival, "the boycotted crown's page for %s" % FactionCatalog.name_of(rival))
	_read_sheet(play, tribe, "the colony's page as the boycotted crown")
	_read_market(play, "the market with the bar standing")
	_read_ask(play, tribe)
	_read_bid(play, tribe)
	_read_after_close(play, tribe, "the close after the barred bid")
	_read_after_close(play, tribe, "the next close, the order carried")
	_finish()


# --- the barred bid ---------------------------------------------------------


## The ask the page draws against the ask the clearing will charge right now:
## the row keeps the price it was published with, and a term that moves after
## the publish (a pact, a subsidy, a boycott) moves the deal.
func _read_ask(play: PlaySession, tribe: int) -> void:
	var offer: Dictionary = _colony_offer(play, tribe)
	if offer.is_empty():
		return
	var market: WorldMarket = play.economy.market
	var commodity: String = String(offer.get("commodity", ""))
	var stored: int = int(offer.get("unit_price", 0))
	var live: int = MinorMarket.unit_price(market, commodity, play.player_faction, tribe)
	var drawn: int = _drawn_ask(play, tribe)
	_say("the page asks %d for %s (published %d); the clearing charges %d" % [
		drawn, CommodityCatalog.label(commodity), stored, live,
	])


## The ask the offer row actually prints, read off the row's own Bid tooltip.
func _drawn_ask(play: PlaySession, tribe: int) -> int:
	var page: LedgerMarket = _market_page(play)
	if page == null:
		return -1
	var box: Node = page.get("_offers_box") as Node
	if box == null:
		return -1
	for row: Node in box.get_children():
		if not _row_names(row, FactionCatalog.name_of(tribe)):
			continue
		var button: Button = _last_button(row)
		if button == null:
			return -1
		var parts: PackedStringArray = button.tooltip_text.split("ask of ")
		if parts.size() < 2:
			return -1
		return int(parts[1].split(" ")[0])
	return -1


## The colony's own offer row, pressed the way a player presses it: the row's
## Bid stages a market bid for one unit, so a full row takes `times` presses.
func _read_bid(play: PlaySession, tribe: int) -> void:
	play.economy.open_panel()
	var offer: Dictionary = _colony_offer(play, tribe)
	if offer.is_empty():
		_say("the colony has nothing on the table this turn")
		return
	var commodity: String = String(offer.get("commodity", ""))
	var units: int = int(offer.get("quantity", 0))
	_say("the colony offers %d %s at %d" % [
		units, CommodityCatalog.label(commodity), int(offer.get("unit_price", 0)),
	])
	var pressed: int = _press_offer_bid(play, tribe, units)
	_say("pressed the colony row's Bid %d time(s) — %s" % [pressed, _last_toast(play)])
	_read_orders(play, "our staged orders after the press")


func _read_after_close(play: PlaySession, tribe: int, when: String) -> void:
	_end_turn(play)
	play.economy.open_panel()
	_say("--- %s (turn %d) ---" % [when, play.turn])
	_say("despatch: %s" % _last_toast(play))
	_read_orders(play, "our orders after the close")
	_read_clearing(play, tribe)
	var report: Dictionary = play.market_report
	for raw: Variant in report.get("notes", []):
		var note: Dictionary = raw
		if int(note.get("faction", -2)) == play.player_faction:
			_say("note about us: %s" % str(note))
	for raw: Variant in report.get("carry", []):
		var carried: MarketOrder = raw as MarketOrder
		if carried != null and carried.faction == play.player_faction:
			_say("carried for us: %s %d %s (id %s)" % [
				"BID" if carried.is_bid() else "OFFER", carried.remaining(),
				carried.commodity, carried.id,
			])
	_say("blocked_by_boycott(us, colony) = %s" % str(
		DiplomacyBoycott.blocked(play.diplomacy, play.player_faction, tribe)
	))


## The LAST CLEARING block, and whether the colony's goods sold to anyone at
## all: the bar's only other expression is who the goods went to instead.
func _read_clearing(play: PlaySession, tribe: int) -> void:
	var page: LedgerMarket = _market_page(play)
	if page != null:
		var lines: PackedStringArray = _labels(page)
		var start: int = -1
		for index in lines.size():
			if lines[index] == "LAST CLEARING":
				start = index
				break
		if start < 0:
			_say("LAST CLEARING: no block — the crown's book settled nothing")
		else:
			_say("LAST CLEARING:")
			for index in range(start, mini(lines.size(), start + 8)):
				_say("  " + lines[index])
	var report: Dictionary = play.market_report
	var ours: int = 0
	var at_colony: int = 0
	var buyers: Dictionary = {}
	for raw: Variant in report.get("deals", []):
		var deal: Dictionary = raw
		var buyer: int = int(deal.get("buyer", -2))
		var seller: int = int(deal.get("seller", -2))
		if seller == tribe or buyer == tribe:
			at_colony += 1
			buyers[buyer] = int(buyers.get(buyer, 0)) + int(deal.get("quantity", 0))
		if buyer == play.player_faction or seller == play.player_faction:
			ours += 1
	_say("deals at the colony: %d, by buyer %s" % [at_colony, str(buyers)])
	if ours == 0:
		_say("no deal of ours settled")


func _read_orders(play: PlaySession, when: String) -> void:
	var orders: Array[MarketOrder] = play.economy.market.book.orders_for(play.player_faction)
	_say("%s: %d staged — %s" % [when, orders.size(), _order_text(orders)])
	var page: LedgerMarket = _market_page(play)
	if page == null:
		return
	for line: String in _labels(page):
		if line.begins_with("BID") or line.begins_with("OFFER") or line.contains("carried"):
			_say("  page line: " + line)


func _order_text(orders: Array[MarketOrder]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for order: MarketOrder in orders:
		parts.append("%s %d %s" % [
			"BID" if order.is_bid() else "OFFER", order.remaining(), order.commodity,
		])
	return ", ".join(parts) if not parts.is_empty() else "none"


# --- reading ----------------------------------------------------------------


func _read_market(play: PlaySession, when: String) -> void:
	play.economy.open_panel()
	var page: LedgerMarket = _market_page(play)
	if page == null:
		_say("no MARKET tab")
		return
	_say("--- %s ---" % when)
	for line: String in _labels(page):
		if line == "SELLER":
			break
		_say("  " + line)
	var offer: Dictionary = _colony_offer(play, _tribe_of(play))
	if not offer.is_empty():
		_say("  the colony's row is still on the book: %s" % str(offer))


func _read_sheet(play: PlaySession, target: int, when: String) -> void:
	MapPlayDiplomacy.open(play)
	var panel: DiplomacyPanel = play.hud.panels.diplomacy_panel
	if panel == null:
		_say("no diplomacy panel")
		return
	panel.select_faction(target)
	_say("--- %s ---" % when)
	var detail: Node = panel.get("_detail") as Node
	if detail == null:
		return
	for line: String in _sheet_lines(detail):
		_say("  " + line)


func _sheet_lines(node: Node) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for child: Node in node.get_children():
		if child is Label:
			var text: String = (child as Label).text.strip_edges()
			if not text.is_empty():
				lines.append(text)
		elif child is Button:
			var button := child as Button
			var label: String = button.text.strip_edges()
			if not label.is_empty():
				lines.append("[%s] %s" % ["off" if button.disabled else "on", label])
		lines.append_array(_sheet_lines(child))
	return lines


# --- helpers ----------------------------------------------------------------


## Presses the Bid on the offer row whose seller is `tribe` — the page's own
## button, so the order goes through the controller a player uses.
func _press_offer_bid(play: PlaySession, tribe: int, times: int = 1) -> int:
	var page: LedgerMarket = _market_page(play)
	if page == null:
		return 0
	var box: Node = page.get("_offers_box") as Node
	if box == null:
		return 0
	for row: Node in box.get_children():
		if not _row_names(row, FactionCatalog.name_of(tribe)):
			continue
		var button: Button = _last_button(row)
		if button == null or button.disabled:
			return 0
		var pressed: int = 0
		for _unit in times:
			button.pressed.emit()
			pressed += 1
		return pressed
	return 0


func _colony_offer(play: PlaySession, tribe: int) -> Dictionary:
	var best: Dictionary = {}
	for raw: Variant in play.economy.market.minor_offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if int(row.get("faction", -1)) != tribe or int(row.get("quantity", 0)) <= 0:
			continue
		if best.is_empty() or int(row.get("quantity", 0)) > int(best.get("quantity", 0)):
			best = row
	return best


func _tribe_of(play: PlaySession) -> int:
	for tribe: int in FactionCatalog.tribe_ids():
		if play.diplomacy.colony_of(tribe) >= 0:
			return tribe
	return -1


func _offer_units(play: PlaySession, faction: int) -> int:
	var total: int = 0
	for raw: Variant in play.economy.market.minor_offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if int(row.get("faction", -1)) == faction:
			total += int(row.get("quantity", 0))
	return total


## A Tribe in contact with goods on the table: the bar needs a colony that
## actually sells something, or there is no deal to bar.
func _trading_tribe(play: PlaySession) -> int:
	var best: int = -1
	var best_units: int = 0
	for tribe: int in FactionCatalog.tribe_ids():
		if not play.diplomacy.has_relation(play.player_faction, tribe):
			continue
		var units: int = _offer_units(play, tribe)
		if units > best_units:
			best = tribe
			best_units = units
	return best


## The rival that will hold the colony: a Great Power the crown has met, at
## peace, and not the crown itself.
func _rival(play: PlaySession, player: int) -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction == player:
			continue
		if not play.diplomacy.has_relation(player, faction):
			continue
		var record: DiplomacyRelation = play.diplomacy.relation(player, faction)
		if record != null and record.at_war:
			continue
		return faction
	return -1


func _row_names(row: Node, name: String) -> bool:
	for child: Node in row.get_children():
		if child is Label and (child as Label).text.strip_edges() == name:
			return true
	return false


func _last_button(node: Node) -> Button:
	var found: Button = null
	for child: Node in node.get_children():
		if child is Button:
			found = child as Button
	return found


func _market_page(play: PlaySession) -> LedgerMarket:
	var panel: EconomyPanel = play.hud.panels.economy_panel
	if panel == null:
		return null
	return panel.page_body(EconomyPanel.TAB_MARKET) as LedgerMarket


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


func _last_toast(play: PlaySession) -> String:
	var despatches: HudDespatches = play.hud.despatches
	if despatches == null:
		return "no despatch"
	var waiting: PackedStringArray = despatches.waiting()
	if not waiting.is_empty():
		return waiting[waiting.size() - 1]
	var newest: String = ""
	for child: Node in despatches.box.get_children():
		var text: String = String(child.get_meta("toast_text", ""))
		if not text.is_empty():
			newest = text
	return newest if not newest.is_empty() else "no despatch"


func _end_turn(play: PlaySession) -> void:
	var start_turn: int = play.turn
	# Answering a pending decision finishes the *suspended* turn, so the calendar
	# is re-read before asking for another.
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


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_boycott_block: %d steps ---" % _steps.size())
	quit()
