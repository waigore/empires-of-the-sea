class_name MapPlayMarket
extends RefCounted
## One shared world-market clearing pass per turn (wiki: world-market § Trade
## orders, § Price discovery). Every court stages orders during its own turn;
## this helper gathers the ledgers, free holds and diplomacy and calls the pure
## matcher once, then refreshes the ledger and HUD (REQ-P2-03, REQ-P3-03).


## `economy_report` is MapPlayEconomyAi.run's report: rival free holds come from
## its trade pass, the human's from the live ledger.
static func run(play: PlaySession, economy_report: Dictionary = {}) -> Dictionary:
	if play == null or play.economy == null or play.economy.market == null:
		return {}
	var market: WorldMarket = play.economy.market
	var economies: Dictionary = {}
	var free_holds: Dictionary = {}
	var factions: Array[int] = FactionCatalog.great_power_ids()
	for faction: int in factions:
		var ledger: PlayerEconomy = play.ledger_for(faction)
		if ledger != null:
			economies[faction] = ledger
		if faction == play.player_faction and not play.observer_mode:
			var cargo: Dictionary = play.economy.trade_cargo()
			free_holds[faction] = int(cargo.get("clear_free", cargo.get("free", 0)))
		else:
			var entry: Dictionary = _faction_report(economy_report, faction)
			var trade: Dictionary = entry.get("trade", {}) as Dictionary
			free_holds[faction] = int(trade.get("free_holds", 0))
	var report: Dictionary = MarketClearing.clear(
		market, play.world, economies, free_holds, {"diplomacy": play.diplomacy}
	)
	play.market_report = report
	# The ledger reads this receipt: a sale's ducats and the overseas share are
	# otherwise invisible on every surface the player has (REQ-P5-05).
	play.economy.last_clearing = report
	play.economy.refresh_panel()
	return report


static func _faction_report(economy_report: Dictionary, faction: int) -> Dictionary:
	var rows: Dictionary = economy_report.get("factions", {}) as Dictionary
	var found: Variant = rows.get(faction, null)
	if found == null:
		found = rows.get(str(faction), null)
	return found as Dictionary if found is Dictionary else {}
