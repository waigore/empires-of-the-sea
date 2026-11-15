extends SceneTree
## Headless free-playtest drive for the trade terms a crown's standing earns
## (wiki: world-market § Favoured trading partner, § Trade orders; diplomacy
## § GP–Tribe — Boycott, § Favoured trading partner). A colony is the gate: it
## makes its suzerain the Tribe's favoured partner and it is the only thing that
## lets a crown boycott a rival, so both payoffs sit behind the hardest
## diplomatic chain in the game.
##
## The drive opens the turn-100 advanced start (the New World is charted, so a
## Tribe is already in contact), walks the colony chain on the court sheet's own
## buttons, then reads the payoffs where a player meets them: the MARKET tab's
## terms banner, the Minor/Tribe offer rows, the LAST CLEARING lines, and the
## boycotted crown's own page. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_trade_terms.gd

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
	_say("seed %s — turn %d, treasury %s" % [
		SEED_TEXT, play.turn, DiplomacyCatalog.money(play.treasury()),
	])
	_read_market(play, "the market before any standing")
	var tribe: int = _trading_tribe(play)
	if tribe < 0:
		_say("no Tribe with goods on the table is in contact — the gate cannot open")
		_finish()
		return
	_say("the colony will be %s (%d provinces, %d goods on the table)" % [
		FactionCatalog.name_of(tribe), DiplomacyRules.provinces_owned(play.world, tribe),
		_offer_units(play, tribe),
	])
	MapPlayDiplomacy.open(play)
	var panel: DiplomacyPanel = play.hud.panels.diplomacy_panel
	panel.select_faction(tribe)
	_walk(play, panel, tribe)
	if play.diplomacy.colony_of(tribe) != play.player_faction:
		_say("no colony stands — the payoffs cannot be read")
		_finish()
		return
	_read_favoured_fill(play, tribe)
	_read_boycott(play, panel)
	_read_sale(play)
	_finish()


# --- the colony gate --------------------------------------------------------


func _walk(play: PlaySession, panel: DiplomacyPanel, tribe: int) -> void:
	var stage: String = play.diplomacy.overture(play.player_faction, tribe)
	_say("the chain stands at %s" % DiplomacyCatalog.stage_label(stage))
	for _step in 6:
		var next: String = DiplomacyCatalog.next_stage(stage)
		if next.is_empty():
			_say("the chain is complete")
			return
		var label: String = "Offer %s" % DiplomacyCatalog.stage_label(next)
		var press: Dictionary = _press(panel, label)
		if not bool(press["found"]):
			_say("the sheet offers no \"%s\" — the chain stops here" % label)
			return
		if bool(press["disabled"]):
			_say("the sheet shows \"%s\" disabled — %s" % [label, String(press["reason"])])
			if next != DiplomacyCatalog.STAGE_JOIN_EMPIRE:
				return
			var aid: Dictionary = _press(panel, "Grant Aid")
			if not bool(aid["found"]) or bool(aid["disabled"]):
				_say("the sheet offers no usable \"Grant Aid\" — %s" % String(aid["reason"]))
				return
			_say("pressed \"Grant Aid\" — %s" % _last_toast(play))
			press = _press(panel, label)
			if bool(press["disabled"]):
				_say("\"%s\" is still disabled — %s" % [label, String(press["reason"])])
				return
		_say("pressed \"%s\" — %s" % [label, _last_toast(play)])
		if next == DiplomacyCatalog.STAGE_JOIN_EMPIRE:
			break
		_end_turn(play)
		panel.select_faction(tribe)
		stage = play.diplomacy.overture(play.player_faction, tribe)
	_say("colony_of(%s) = %d" % [FactionCatalog.name_of(tribe), play.diplomacy.colony_of(tribe)])


# --- the favoured fill ------------------------------------------------------


## The suzerain is the colony Tribe's favoured partner, so its bid fills first
## inside the tier. The Deal Book is the only place the crown reads that.
func _read_favoured_fill(play: PlaySession, tribe: int) -> void:
	_end_turn(play)
	play.economy.open_panel()
	var offer: Dictionary = _colony_offer(play, tribe)
	if offer.is_empty():
		_say("the colony has nothing on the table this turn")
		return
	var commodity: String = String(offer.get("commodity", ""))
	var theirs: int = int(offer.get("quantity", 0))
	# Bid every unit on the table, so the colony's own offer is reached whatever
	# another seller's identical good clears first.
	var total: int = _table_units(play, commodity)
	_say("the colony offers %d %s at %d; the table holds %d" % [
		theirs, CommodityCatalog.label(commodity), int(offer.get("unit_price", 0)), total,
	])
	var pressed: int = _press_offer_bid(play, tribe, total)
	_say("pressed the offer row's Bid %d time(s) — %s" % [pressed, _last_toast(play)])
	if pressed <= 0:
		return
	_end_turn(play)
	play.economy.open_panel()
	_read_market(play, "the market after the favoured fill")
	_read_clearing(play)
	var page: LedgerMarket = _market_page(play)
	var lines: PackedStringArray = _labels(page) if page != null else PackedStringArray()
	var favoured: bool = false
	for line: String in lines:
		if line.contains("favoured"):
			favoured = true
	_say("the page names the favour: %s" % str(favoured))
	# What the clearing actually recorded, so a page that hides the claim is
	# told apart from a clearing that never made it.
	var report: Dictionary = play.market_report
	for raw: Variant in report.get("deals", []):
		var deal: Dictionary = raw
		if int(deal.get("seller", -2)) == tribe or int(deal.get("buyer", -2)) == play.player_faction:
			_say("deal: %s" % str(deal))
	for raw: Variant in report.get("notes", []):
		var note: Dictionary = raw
		if int(note.get("faction", -2)) == play.player_faction:
			_say("note: %s" % str(note))
	_say("staged now: %d" % play.economy.market.book.staged_count())


## The colony's richest row in the published book: the good the crown will bid
## for, so the fill can be the colony's own and the favour can be read.
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


## Every unit of one commodity on the whole Minor/Tribe table.
func _table_units(play: PlaySession, commodity: String) -> int:
	var total: int = 0
	for raw: Variant in play.economy.market.minor_offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if String(row.get("commodity", "")) == commodity:
			total += int(row.get("quantity", 0))
	return total


## Presses the Bid on the offer row whose seller is `tribe` — the page's own
## button, so the order goes through the controller the player uses. One press
## stages one unit, so a full row takes `times` presses.
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


## The button whose own label is `title` (a commodity row carries Offer and Bid).
func _button_titled(node: Node, title: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text.strip_edges() == title:
			return child as Button
	return null


# --- the boycott ------------------------------------------------------------


## A boycott is the colony's other privilege: it worsens the target's market
## terms 10%. The target reads that rate on its own page, so the drive reads the
## page the boycotted crown would see.
func _read_boycott(play: PlaySession, panel: DiplomacyPanel) -> void:
	var gp: int = -1
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		if play.diplomacy.has_relation(play.player_faction, faction):
			gp = faction
			break
	if gp < 0:
		_say("no rival court to boycott")
		return
	panel.select_faction(gp)
	var press: Dictionary = _press(panel, "Boycott Their Trade")
	if not bool(press["found"]):
		_say("the sheet offers no boycott")
		return
	if bool(press["disabled"]):
		_say("the boycott is disabled — %s" % String(press["reason"]))
		return
	_say("pressed \"Boycott Their Trade\" — %s" % _last_toast(play))
	_say("boycotting %s: %s" % [
		FactionCatalog.name_of(gp),
		str(DiplomacyTrade.is_boycotting(play.diplomacy, play.player_faction, gp)),
	])
	_read_sheet(panel, "the boycotted court's sheet")
	# The boycotted crown's own MARKET tab: the same page, read for that crown.
	var market: WorldMarket = play.economy.market
	var theirs: PlayerEconomy = play.ledger_for(gp)
	if theirs == null:
		_say("no ledger for %s" % FactionCatalog.name_of(gp))
		return
	var page := LedgerMarket.new()
	page.fill(theirs, market, {}, market.minor_offers, {}, gp)
	_say("--- %s's MARKET tab ---" % FactionCatalog.name_of(gp))
	for line: String in _labels(page):
		_say("  " + line)
	page.free()
	_say("%s pays %d for grain and earns %d (world price %d)" % [
		FactionCatalog.name_of(gp), market.buy_price("grain", gp),
		market.sell_price("grain", gp), market.price("grain"),
	])
	# The rate is on the boycotted crown's page; the receipt must add up too.
	_end_turn(play)
	_read_theirs(play, gp, "the boycotted crown's clearing after the boycott")


## One rival crown's MARKET tab and its LAST CLEARING, read where that crown
## would read them (the page is built for the viewer, like the ledger does).
func _read_theirs(play: PlaySession, faction: int, when: String) -> void:
	var market: WorldMarket = play.economy.market
	var theirs: PlayerEconomy = play.ledger_for(faction)
	if theirs == null:
		return
	var page := LedgerMarket.new()
	page.fill(theirs, market, {}, market.minor_offers, {}, faction)
	_say("--- %s: %s ---" % [FactionCatalog.name_of(faction), when])
	for line: String in _labels(page):
		if line == "SELLER" or line == "GOOD" or line == "SORT" or line.begins_with("20 offers"):
			break
		_say("  " + line)
	page.free()

# --- the sale receipt -------------------------------------------------------


## A sale is the one trade whose price the crown cannot see in the ledger, so
## the Deal Book line must add up: the unit it names times the tons it names.
func _read_sale(play: PlaySession) -> void:
	play.economy.open_panel()
	var page: LedgerMarket = _market_page(play)
	if page == null:
		return
	var pressed: bool = false
	for row: Node in page.get_children():
		var button: Button = _button_titled(row, "Offer")
		if button == null or button.disabled:
			continue
		button.pressed.emit()
		pressed = true
		break
	_say("pressed a commodity row's Offer — %s" % ("staged" if pressed else "nothing sellable"))
	if not pressed:
		return
	_end_turn(play)
	play.economy.open_panel()
	_read_clearing(play)


# --- reading ----------------------------------------------------------------


func _read_market(play: PlaySession, when: String) -> void:
	play.economy.open_panel()
	var page: LedgerMarket = _market_page(play)
	if page == null:
		_say("no MARKET tab")
		return
	_say("--- %s ---" % when)
	for line: String in _labels(page):
		_say("  " + line)


## The LAST CLEARING block: the deals the crown's own book settled.
func _read_clearing(play: PlaySession) -> void:
	var page: LedgerMarket = _market_page(play)
	if page == null:
		return
	var lines: PackedStringArray = _labels(page)
	var start: int = -1
	for index in lines.size():
		if lines[index] == "LAST CLEARING":
			start = index
			break
	if start < 0:
		_say("--- LAST CLEARING: no block (the crown traded nothing) ---")
		return
	_say("--- LAST CLEARING ---")
	for index in range(start, lines.size()):
		_say("  " + lines[index])


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


func _read_sheet(panel: DiplomacyPanel, when: String) -> void:
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
			var text: String = button.text.strip_edges()
			if not text.is_empty():
				lines.append("[%s] %s" % ["off" if button.disabled else "on", text])
		lines.append_array(_sheet_lines(child))
	return lines


func _press(panel: DiplomacyPanel, prefix: String) -> Dictionary:
	var detail: Node = panel.get("_detail") as Node
	if detail == null:
		return {"found": false, "disabled": false, "reason": ""}
	var button: Button = _find_button(detail, prefix)
	if button == null:
		return {"found": false, "disabled": false, "reason": ""}
	if button.disabled:
		return {"found": true, "disabled": true, "reason": _reason_under(button)}
	button.pressed.emit()
	return {"found": true, "disabled": false, "reason": ""}


func _reason_under(button: Button) -> String:
	var parent: Node = button.get_parent()
	if parent == null:
		return "no reason given"
	var index: int = button.get_index()
	for offset in range(index + 1, parent.get_child_count()):
		var sibling: Node = parent.get_child(offset)
		if sibling is Label:
			return (sibling as Label).text.strip_edges()
		if sibling is Button:
			break
	return "no reason given"


func _find_button(node: Node, prefix: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
			return child as Button
		var found: Button = _find_button(child, prefix)
		if found != null:
			return found
	return null


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


# --- helpers ----------------------------------------------------------------


## The Tribe the crown has met that has goods on the table: the colony's own
## offers are what the favoured fill is read from, so a Tribe that produces
## nothing tradeable cannot show the payoff. Fewest provinces breaks the tie
## (the Join Empire price is per province).
func _trading_tribe(play: PlaySession) -> int:
	var best: int = -1
	var best_units: int = 0
	var best_provinces: int = 1 << 30
	for tribe: int in FactionCatalog.tribe_ids():
		if not play.diplomacy.has_relation(play.player_faction, tribe):
			continue
		var units: int = _offer_units(play, tribe)
		if units <= 0:
			continue
		var provinces: int = DiplomacyRules.provinces_owned(play.world, tribe)
		if provinces < 1:
			continue
		if units > best_units or (units == best_units and provinces < best_provinces):
			best = tribe
			best_units = units
			best_provinces = provinces
	return best


## Units this faction has on the published Minor/Tribe book.
func _offer_units(play: PlaySession, faction: int) -> int:
	var total: int = 0
	for raw: Variant in play.economy.market.minor_offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if int(row.get("faction", -1)) == faction:
			total += int(row.get("quantity", 0))
	return total


func _end_turn(play: PlaySession) -> void:
	var start_turn: int = play.turn
	# Answering a pending decision finishes the *suspended* turn, so the closure
	# must be re-read before asking for another — a second press would close the
	# following turn and hand back its clearing instead.
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
	print("\n--- playtest_trade_terms: %d steps ---" % _steps.size())
	quit()
