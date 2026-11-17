extends SceneTree
## Headless free-playtest drive for the MARKET tab's own arithmetic (wiki:
## world-market § Trade orders, § Subsidy price adjustment, § FTP; REQ-P5-05).
## A crown reads two surfaces for one deal — the LAST CLEARING line and the
## turn's market toast — and a third for what it may sell: the commodity row's
## Offer button. This drive signs a favoured trading pact, buys at the pact's
## rate, closes a real turn, and prints the ducats the lines name against the
## ducats the clearing charged; then it claims a commodity's stock with its own
## production runs and reads the row whose Offer is dead.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_market_receipt.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
## The recipe whose inputs claim a commodity the crown already holds.

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
	_read_sellable(play)
	_read_purchase(play)
	_finish()


# --- the sellable readout ---------------------------------------------------


## A row whose own production runs claim its stock: the Offer button is dead and
## the only thing that says why is a tooltip, which a touch player never sees.
func _read_sellable(play: PlaySession) -> void:
	play.economy.open_panel()
	var page: LedgerMarket = _market_page(play)
	if page == null:
		_say("no MARKET tab")
		return
	var economy: PlayerEconomy = play.economy.economy
	# A run this court can actually pay for: an input it already holds.
	var recipe: String = ""
	var input: String = ""
	for id: String in ProductionRecipes.ids():
		var needs: Dictionary = ProductionRecipes.inputs(id)
		if needs.size() != 1:
			continue
		var commodity: String = String(needs.keys()[0])
		if economy.quantity(commodity) < 2:
			continue
		recipe = id
		input = commodity
		break
	if recipe.is_empty():
		_say("no run can claim a held commodity — the readout cannot be read")
		return
	var units: int = int(ceil(float(economy.quantity(input)) / float(
		int((ProductionRecipes.inputs(recipe) as Dictionary)[input])
	)))
	_say("--- claiming all %d %s with %d %s runs ---" % [
		economy.quantity(input), CommodityCatalog.label(input), units, recipe,
	])
	play.economy.orders.set_production(recipe, units)
	play.economy.open_panel()
	page = _market_page(play)
	if page == null:
		return
	var claimed: int = LedgerMarket.claimed_by_production(economy, input)
	_say("%d %s held, %d claimed by production" % [
		economy.quantity(input), CommodityCatalog.label(input), claimed,
	])
	var row: Control = _row_for(page, input)
	if row == null:
		_say("the row is not on the page")
		return
	var offer: Button = _button_titled(row, "Offer")
	_say("the row reads: %s" % " | ".join(_labels(row)))
	if offer != null:
		_say("Offer is %s; its tooltip says \"%s\"" % [
			"disabled" if offer.disabled else "enabled", offer.tooltip_text,
		])
	_say("a touch player sees a sellable count: %s" % (
		"yes" if _has_line(row, "sellable") else "no"
	))


# --- the purchase receipt ---------------------------------------------------


## Signs a favoured trading pact, buys at its rate, and reads the two surfaces
## that price the same deal: the LAST CLEARING lines and the toast's summary.
func _read_purchase(play: PlaySession) -> void:
	var target: int = _pact_target(play)
	if target < 0:
		_say("no court will sign a pact — the receipt cannot be read")
		return
	var signed: Dictionary = DiplomacyFtp.establish(
		play.diplomacy, play.player_faction, target, DiplomacyRules.DECISION_ACCEPT
	)
	_say("--- the pact with %s: %s ---" % [
		FactionCatalog.name_of(target), str(signed),
	])
	_end_turn(play)
	var market: WorldMarket = play.economy.market
	var rate: float = market.term_multiplier(play.player_faction, "grain", true)
	_say("the crown now buys at %d%%" % roundi(rate * 100.0))
	var commodity: String = _buyable(play)
	if commodity.is_empty():
		_say("nothing is buyable this turn — the receipt cannot be read")
		return
	var unit: int = market.buy_price(commodity, play.player_faction)
	_say("--- buying 5 %s at %d (ask %d) ---" % [
		CommodityCatalog.label(commodity), market.price(commodity), unit,
	])
	var staged: Dictionary = play.economy.orders.trade(commodity, 5, true)
	if not bool(staged.get("ok", false)):
		_say("the ledger refused the bid: %s" % String(staged.get("reason", "")))
		return
	_end_turn(play)
	var report: Dictionary = play.market_report
	var lines: PackedStringArray = PackedStringArray()
	var named: int = 0
	for raw: Variant in report.get("deals", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = raw
		if int(deal.get("buyer", -2)) != play.player_faction:
			continue
		lines.append(LedgerMarketText.deal_line(deal, play.player_faction))
		named += int(deal.get("cost", 0))
	var fills: Dictionary = report.get("fills", {}) as Dictionary
	var mine: Dictionary = fills.get(play.player_faction, {}) as Dictionary
	var charged: int = int(mine.get("spent", 0))
	_say("the Deal Book lines:")
	for line: String in lines:
		_say("  " + line)
	_say("the lines name %d ducats; the clearing charged %d — %s" % [
		named, charged, "they agree" if named == charged else "THEY DISAGREE",
	])
	_say("the turn's toast: %s" % LedgerMarketText.market_summary(report, play.player_faction))
	play.economy.open_panel()
	_read_clearing(play)


# --- helpers ----------------------------------------------------------------


## A court that will sign a pact: an embassy and a warm relation, both of which
## the wiki's FTP gate asks for (world-market § FTP).
func _pact_target(play: PlaySession) -> int:
	for gp: int in FactionCatalog.great_power_ids():
		if gp == play.player_faction:
			continue
		if not play.diplomacy.has_relation(play.player_faction, gp):
			continue
		play.diplomacy.set_overture(
			play.player_faction, gp, DiplomacyCatalog.STAGE_EMBASSY
		)
		play.diplomacy.ensure_relation(play.player_faction, gp, 0).set_score(80.0)
		return gp
	return -1


## A tradeable commodity the crown can bid on with no Minor/Tribe supply, so the
## standing world counterparty fills the whole bid as one deal.
func _buyable(play: PlaySession) -> String:
	var market: WorldMarket = play.economy.market
	var cargo: Dictionary = play.economy.trade_cargo()
	if int(cargo.get("clear_free", cargo.get("free", 0))) < 5:
		return ""
	var offered: Dictionary = {}
	for raw: Variant in market.minor_offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		offered[String(row.get("commodity", ""))] = true
	for id: String in CommodityCatalog.all_ids():
		if not CommodityCatalog.is_tradeable(id) or offered.has(id):
			continue
		var price: int = market.price(id)
		if price <= 0:
			continue
		# A rate that lands between two integers is what the line must survive.
		if is_equal_approx(float(price) * 0.95, roundf(float(price) * 0.95)):
			continue
		return id
	return ""


func _row_for(page: LedgerMarket, id: String) -> Control:
	for child: Node in page.get_children():
		if not child is Control:
			continue
		var row := child as Control
		if not _has_line(row, CommodityCatalog.label(id)):
			continue
		if _button_titled(row, "Offer") != null:
			return row
	return null


func _has_line(node: Node, needle: String) -> bool:
	for line: String in _labels(node):
		if line.contains(needle):
			return true
	return false


func _button_titled(node: Node, prefix: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
			return child as Button
		var found: Button = _button_titled(child, prefix)
		if found != null:
			return found
	return null


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
		_say("--- LAST CLEARING: no block ---")
		return
	_say("--- LAST CLEARING at %d of %d (book %d deals) ---" % [
		start, lines.size(), play.economy.market.book.last_deals.size(),
	])
	for index in range(start, mini(start + 8, lines.size())):
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


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_market_receipt: %d steps ---" % _steps.size())
	quit()
