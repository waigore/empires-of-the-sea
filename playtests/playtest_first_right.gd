extends SceneTree
## Headless free-playtest drive for a deed's first refusal: a tile bought in a
## Minor or Tribe province keeps selling that province's harvest, and when a
## rival's bid fills it the tile-owning court is paid its relation share
## (wiki: world-market-first-right-of-refusal § Eligibility, § Profit formula,
## § Treasury transfer D4; world-market § First right of refusal).
##
## The drive opens the turn-100 advanced start as Spain, deeds a Minor/Tribe
## province's estate, keeps that seller's relation as the only warm one, has a
## rival Great Power bid the whole commodity's harvest, and runs the real
## clearing pass (the one the turn close runs, through MapPlayMarket). It then
## holds what the court is paid to what the market ledger prints, and closes a
## real turn to see the same share arrive through the turn itself.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_first_right.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
## The relation the crown holds with the seller: a share that lands between two
## ducats is what the receipt has to survive.
const RELATION: float = 75.0

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
	_say("seed %s — %s, turn %d, treasury %d" % [
		SEED_TEXT, FactionCatalog.name_of(play.player_faction), play.turn,
		play.treasury(),
	])
	var pick: Dictionary = _deed_pass(play)
	if pick.is_empty():
		_finish()
		return
	_share_pass(play, pick)
	_priority_pass(play, pick)
	_turn_pass(play)
	_finish()


# --- the deed ---------------------------------------------------------------


## Holds the deed on a Minor/Tribe province's estate, the way a Merchant's
## `purchase_land` completion writes it.
func _deed_pass(play: PlaySession) -> Dictionary:
	var pick: Dictionary = _deedable(play)
	if pick.is_empty():
		_say("no Minor or Tribe province sells land this crown may buy — nothing to play")
		return {}
	var model: MapModel = pick["model"] as MapModel
	var province: ProvinceState = pick["province"] as ProvinceState
	var commodity: String = String(pick["commodity"])
	var tiles: Array = pick["tiles"] as Array
	var tile: Vector2i = tiles[0] as Vector2i
	_say("--- the deed: %s (%s) sells %s on %d estate%s ---" % [
		province.name, FactionCatalog.name_of(int(pick["seller"])),
		CommodityCatalog.label(commodity),
		tiles.size(), "" if tiles.size() == 1 else "s",
	])
	_say("  tile %s: land %s · province %d · held %s · bought by %d · resource %d" % [
		str(tile), str(model.is_land(tile.x, tile.y)),
		model.province_at(tile.x, tile.y),
		str(model.is_purchased_tile(tile)),
		model.ownership.purchaser(model.index_of(tile.x, tile.y)),
		model.resource_at(tile.x, tile.y),
	])
	var bought: int = 0
	for raw: Variant in tiles:
		var held: Vector2i = raw as Vector2i
		if model.is_purchased_tile(held):
			continue
		if model.purchase_tile(held, play.player_faction):
			bought += 1
	_say("%d tile%s bought at %s each (the deed's published 15× price)" % [
		bought, "" if bought == 1 else "s", LandPurchase.cost_text(model, tile),
	])
	# The book must re-publish before the auction can hold the harvest the deed
	# keeps in the seller's hands (wiki: world-market § Minor and tribe auto-sell).
	MapPlayMarket.republish(play)
	return pick


## The first Minor/Tribe province with an estate this crown may hold: a
## tradeable raw, no war, and a tile no other court has already bought.
func _deedable(play: PlaySession) -> Dictionary:
	for model: MapModel in play.world.regions:
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			var seller: int = model.province_owner(province.id)
			var kind: int = FactionCatalog.type_of(seller)
			if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
				continue
			if DiplomacyRules.at_war_with(play.diplomacy, play.player_faction, seller):
				continue
			var by_commodity: Dictionary = {}
			for tile: Vector2i in province.tiles:
				var commodity: String = MinorMarket.estate_commodity(model, tile)
				if commodity.is_empty():
					continue
				var index: int = model.index_of(tile.x, tile.y)
				if model.is_purchased_tile(tile) \
					and model.ownership.purchaser(index) != play.player_faction:
					continue
				if not by_commodity.has(commodity):
					by_commodity[commodity] = [] as Array
				(by_commodity[commodity] as Array).append(tile)
			var ids: Array = by_commodity.keys()
			ids.sort()
			for raw: Variant in ids:
				var commodity: String = String(raw)
				return {
					"model": model, "province": province, "seller": seller,
					"commodity": commodity,
					"tiles": (by_commodity[commodity] as Array).duplicate(),
				}
	return {}


# --- the rival's fill and the crown's share ---------------------------------


## A rival Great Power bids the whole harvest; the real clearing pass pays the
## deed-holder its relation share and the ledger prints it.
func _share_pass(play: PlaySession, pick: Dictionary) -> void:
	var seller: int = int(pick["seller"])
	var commodity: String = String(pick["commodity"])
	var price: int = play.economy.market.price(commodity)
	# Only this seller's relation is warm, so every ducat the clearing credits
	# the crown is this one deed's share.
	for minor: int in FactionCatalog.minor_ids():
		play.diplomacy.ensure_relation(play.player_faction, minor, 0).set_score(0.0)
	for tribe: int in FactionCatalog.tribe_ids():
		play.diplomacy.ensure_relation(play.player_faction, tribe, 0).set_score(0.0)
	play.diplomacy.ensure_relation(play.player_faction, seller, 0).set_score(RELATION)
	play.diplomacy.set_overture(
		play.player_faction, seller, DiplomacyCatalog.STAGE_EMBASSY
	)
	var rival: int = _rival(play, seller)
	if rival < 0:
		_say("no rival court may buy from %s — the share cannot be read" % (
			FactionCatalog.name_of(seller)
		))
		return
	# The auction's whole supply of this commodity, so the rival's bid certainly
	# reaches the deed tile and not only the first offer the sort names.
	var units: int = 0
	for order: MarketOrder in MinorMarket.emit_orders(play.world):
		if order.commodity == commodity and not order.is_bid():
			units += order.remaining()
	if units <= 0:
		_say("the auction holds no %s to bid on" % CommodityCatalog.label(commodity))
		return
	var ledger: PlayerEconomy = play.ledger_for(rival)
	if ledger != null:
		ledger.treasury = maxi(ledger.treasury, price * units * 2)
	var staged: Dictionary = MarketOrders.submit(
		play.economy.market, rival, commodity, MarketOrder.SIDE_BID, units,
		{"cargo_free": units, "treasury": price * units * 2, "buy_price": price}
	)
	if not bool(staged.get("ok", false)):
		_say("the rival's bid was refused: %s" % String(staged.get("reason", "")))
		return
	_say("--- %s bids the whole %s harvest: %d at %d (relation %d%%) ---" % [
		FactionCatalog.name_of(rival), CommodityCatalog.label(commodity), units,
		price, roundi(RELATION),
	])
	var before: int = play.treasury()
	var report: Dictionary = MapPlayMarket.run(
		play, {"factions": {rival: {"trade": {"free_holds": units, "holds": units}}}}
	)
	var after: int = play.treasury()
	var credited: int = roundi(float(
		(report.get("credits", {}) as Dictionary).get("by_gp", {}).get(
			play.player_faction, 0.0
		)
	))
	var expected: int = roundi(float(_deed_units(pick)) * float(price) * RELATION / 100.0)
	_say("the crown's shares: the clearing credits %d, the deed's own sum is %d — %s" % [
		credited, expected, "they agree" if credited == expected else "THEY DISAGREE",
	])
	_say("the purse moves %d → %d (%+d)" % [before, after, after - before])
	_say("the clearing's credit rows:")
	var credits: Dictionary = report.get("credits", {}) as Dictionary
	for raw: Variant in credits.get("rows", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		_say("  seller %s · buyer %s · %d × %d · owner %d pays %d · kickbacks %d" % [
			FactionCatalog.name_of(int(row.get("seller", -2))),
			FactionCatalog.name_of(int(row.get("buyer", -2))),
			int(row.get("quantity", 0)), int(row.get("price", 0)),
			int(row.get("owner", -2)), roundi(float(row.get("owner_credit", 0.0))),
			(row.get("kickbacks", []) as Array).size(),
		])
	_say("gross %d · owner totals %d · kickbacks %d · sink %d" % [
		roundi(float(credits.get("gross", 0.0))),
		roundi(float(credits.get("owner_total", 0.0))),
		roundi(float(credits.get("kickback_total", 0.0))),
		roundi(float(credits.get("sink", 0.0))),
	])
	var filled: int = 0
	for raw: Variant in report.get("deals", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = raw
		if String(deal.get("commodity", "")) != commodity:
			continue
		if int(deal.get("buyer", -2)) != rival:
			continue
		if int(deal.get("seller", -2)) != seller:
			continue
		filled += int(deal.get("quantity", 0))
		_say("  %s · first right %s" % [
			LedgerMarketText.deal_line(deal, play.player_faction),
			"yes" if bool(deal.get("is_frr", false)) else "no",
		])
	_say("%d of the deed's %d %s were filled to %s" % [
		filled, _deed_units(pick), CommodityCatalog.label(commodity),
		FactionCatalog.name_of(rival),
	])
	_read_ledger(play, credited)


## The deed's own estate count: the units the seller offers from the bought
## tiles, and so the units a rival's fill can pay a share on.
func _deed_units(pick: Dictionary) -> int:
	return (pick["tiles"] as Array).size()


## The crown's own bid fills its deed tile before any tier: the owner bids at a
## worse integer priority than a rival and still takes the deed's unit first
## (wiki: world-market-first-right-of-refusal § Priority override; world-market
## § First right of refusal — "regardless of the bid's integer tier").
func _priority_pass(play: PlaySession, pick: Dictionary) -> void:
	var model: MapModel = pick["model"] as MapModel
	var seller: int = int(pick["seller"])
	var commodity: String = String(pick["commodity"])
	var units: int = _deed_units(pick)
	var price: int = play.economy.market.price(commodity)
	var owned: Array[int] = []
	for raw: Variant in pick["tiles"]:
		owned.append(model.index_of((raw as Vector2i).x, (raw as Vector2i).y))
	var rival: int = _rival(play, seller)
	if rival < 0 or units <= 0:
		return
	_say("--- the crown bids %d %s at priority 9, %s bids at 1 ---" % [
		units, CommodityCatalog.label(commodity), FactionCatalog.name_of(rival),
	])
	var ledger: PlayerEconomy = play.ledger_for(rival)
	if ledger != null:
		ledger.treasury = maxi(ledger.treasury, price * units * 2)
	var mine: Dictionary = MarketOrders.submit(
		play.economy.market, play.player_faction, commodity, MarketOrder.SIDE_BID, units,
		{"cargo_free": units, "treasury": price * units * 2, "buy_price": price}, 9
	)
	var theirs: Dictionary = MarketOrders.submit(
		play.economy.market, rival, commodity, MarketOrder.SIDE_BID, units,
		{"cargo_free": units, "treasury": price * units * 2, "buy_price": price}, 1
	)
	if not bool(mine.get("ok", false)) or not bool(theirs.get("ok", false)):
		_say("a bid was refused: %s / %s" % [
			String(mine.get("reason", "")), String(theirs.get("reason", "")),
		])
		return
	var report: Dictionary = MapPlayMarket.run(play, {
		"factions": {
			rival: {"trade": {"free_holds": units, "holds": units}},
			play.player_faction: {"trade": {"free_holds": units, "holds": units}},
		},
	})
	var winner: String = "nobody"
	var first_right: bool = false
	for raw: Variant in report.get("deals", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = raw
		if String(deal.get("commodity", "")) != commodity:
			continue
		if int(deal.get("seller", -2)) != seller:
			continue
		if not owned.has(int(deal.get("origin_index", -1))):
			continue
		winner = FactionCatalog.name_of(int(deal.get("buyer", -2)))
		first_right = bool(deal.get("is_frr", false))
		break
	_say("the deed tile filled to %s (first right %s) — %s" % [
		winner, "yes" if first_right else "no",
		"the crown took it whatever its tier"
			if winner == FactionCatalog.name_of(play.player_faction)
			else "THE RIVAL TOOK IT FIRST",
	])
	var credited: int = roundi(float(
		(report.get("credits", {}) as Dictionary).get("by_gp", {}).get(
			play.player_faction, 0.0
		)
	))
	_say("the crown bought its own harvest, so the deed pays no owner share: %d were credited" % credited)


## A Great Power that may buy from this seller: another court with no war and no
## boycott between it and the Minor/Tribe.
func _rival(play: PlaySession, seller: int) -> int:
	for gp: int in FactionCatalog.great_power_ids():
		if gp == play.player_faction:
			continue
		if DiplomacyRules.at_war_with(play.diplomacy, gp, seller):
			continue
		if DiplomacyTrade.blocked_by_boycott(play.diplomacy, gp, seller):
			continue
		return gp
	return -1


## The market ledger's own lines: the crown's deed share is printed where the
## court reads its clearing (REQ-P5-05).
func _read_ledger(play: PlaySession, credited: int) -> void:
	play.economy.open_panel()
	var panel: EconomyPanel = play.hud.panels.economy_panel
	if panel == null:
		_say("no economy panel — the ledger cannot be read")
		return
	var page: LedgerMarket = panel.page_body(EconomyPanel.TAB_MARKET) as LedgerMarket
	if page == null:
		_say("no MARKET tab — the ledger cannot be read")
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
	_say("--- LAST CLEARING at %d of %d ---" % [start, lines.size()])
	var printed: int = -1
	for index in range(start, mini(start + 10, lines.size())):
		_say("  " + lines[index])
		if lines[index].begins_with("Overseas shares"):
			printed = int(lines[index].replace("Overseas shares", "").replace(
				"ducats", ""
			).replace("+", "").strip_edges())
	_say("the ledger prints %s for a share of %d — %s" % [
		"%d ducats" % printed if printed >= 0 else "no share line", credited,
		"they agree" if printed == credited else "THEY DISAGREE",
	])


# --- the same share through a real turn -------------------------------------


## One real turn close, so the share arrives through the phase the crown plays
## and not only through a pass the drive called by hand.
func _turn_pass(play: PlaySession) -> void:
	_say("--- one real turn: what the phase pays the deed ---")
	var before: int = play.treasury()
	_end_turn(play)
	var report: Dictionary = play.market_report
	var credited: int = roundi(float(
		(report.get("credits", {}) as Dictionary).get("by_gp", {}).get(
			play.player_faction, 0.0
		)
	))
	_say("turn %d — the clearing credited %d in shares; the purse moves %d → %d" % [
		play.turn, credited, before, play.treasury(),
	])


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
	_say("the turn would not close")


# --- helpers ----------------------------------------------------------------


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


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_first_right: %d steps ---" % _steps.size())
	quit()
