class_name MapPlayObserver
extends RefCounted
## Live full-AI observer scoreboard (wiki: game-setup § Human/AI slot assignment
## — an empty human slot set is the full-AI observer; turn-trace-interpretation).
##
## One row per Great Power: lands, public power, forces, ledger, wars and last
## turn's orders. The observatory panel and the headless exporter render these;
## this module only reads PlaySession state (REQ-P2-03, REQ-P3-03).

const NO_ID: int = MapModel.NO_ID


## Live scoreboard ranked by Old World provinces then public power, with the
## campaign result when one is decided.
static func snapshot(play: PlaySession) -> Dictionary:
	var rows: Array[Dictionary] = []
	for faction: int in FactionCatalog.great_power_ids():
		rows.append(row(play, faction))
	rows.sort_custom(_better_row)
	for index in rows.size():
		rows[index]["rank"] = index + 1
	var winner: int = _winner(play)
	var leader: int = winner
	if leader == NO_ID and not rows.is_empty():
		leader = int(rows[0]["faction"])
	var live: int = AiControl.live_faction(play)
	return {
		"turn": play.turn,
		"year": TurnTime.year_for_turn(play.turn),
		"seed": play.map_seed,
		"ai_mode": play.ai_mode,
		"ai_live": live,
		"ai_baselines": AiControl.baseline_factions(play) if play.ai_mode == AiControl.BENCH else [],
		"campaign_over": play.campaign_over(),
		"winner": winner,
		"leader": leader,
		"result": _result_text(play, winner),
		"market": market_reading(play, rows),
		"rows": rows,
	}


## The shared world market as this turn left it: the prices a run's courts paid
## and the Minor/Tribe rows on the book. A run that starves has to show what it
## paid for grain (wiki: world-market § Price discovery; issues #676, #730).
##
## The food half is the famine's own reading (issue #766 clause 3): `minor_food`
## is the ration tonnage the book offers this turn, `ration_demand` is what every
## court in play wants to eat, and `food_gap` is the difference. A deficit there
## is the world's supply, not a court's bid, so the issue's own acceptance can be
## checked on the turn trace instead of a throwaway probe.
static func market_reading(
	play: PlaySession, rows: Array[Dictionary] = []
) -> Dictionary:
	if play == null or play.economy == null or play.economy.market == null:
		return {}
	var book: WorldMarket = play.economy.market
	var prices: Dictionary = {}
	for id: String in ["grain", "meat", "timber", "wool", "iron"]:
		prices[id] = book.price(id)
	prices["minor_offers"] = book.minor_offers.size()
	prices["minor_food"] = _book_food(book)
	prices["ration_demand"] = _ration_demand(rows)
	prices["food_gap"] = maxi(int(prices["ration_demand"]) - int(prices["minor_food"]), 0)
	# The deed's own privilege, read off the same clearing the Deal Book prints:
	# a deed owner's bid fills at absolute top priority, so a run that never
	# shows an `is_frr` deal never exercised the path the deed is bought for
	# (issue #841; wiki: world-market § First right of refusal).
	prices["frr_fills"] = _frr_fills(book)
	return prices


## The deals the last clearing settled through first right of refusal: the
## reading the deed gate is measured on (issue #841).
static func _frr_fills(book: WorldMarket) -> int:
	var fills: int = 0
	if book == null or book.book == null:
		return fills
	for deal: Dictionary in book.book.last_deals:
		if bool(deal.get("is_frr", false)):
			fills += 1
	return fills


## The food tonnage the Minor Nation and Tribe estates offer on this turn's book:
## one unit per level-1 estate, the published yield (wiki: world-market
## § Minor and tribe auto-sell; DR-20261110-32).
static func _book_food(book: WorldMarket) -> int:
	var units: int = 0
	for offer: Dictionary in book.minor_offers:
		if CommodityCatalog.is_food(String(offer.get("commodity", ""))):
			units += maxi(int(offer.get("quantity", 0)), 0)
	return units


## What every court in play wants to eat at its next Consumption phase, read from
## the same larder row the scoreboard prints (wiki: workers-and-population
## § Consumption).
static func _ration_demand(rows: Array[Dictionary]) -> int:
	var demand: int = 0
	for row: Dictionary in rows:
		var larder: Dictionary = row.get("larder", {}) as Dictionary
		demand += maxi(int(larder.get("wanted", 0)), 0)
	return demand


## What the next Consumption phase does to one court's larder, as the strike
## reading: the store, every mouth the phase feeds in its own order, and the
## shortfall that puts the workforce on strike (wiki: workers-and-population
## § Consumption). `mouths` is the army, navy and ward ration the phase feeds
## before the pool (`_mouths`); without it only the pool is fed, so a caller
## that has the session should pass it. The destitute-court signature is
## measured on exactly this — a store that collapses to strike levels while the
## purse pins (issue #676 clause 4, #766) — so the turn trace names the famine
## instead of a throwaway probe reading one run at a time.
static func larder_reading(
	economy: PlayerEconomy, mouths: Dictionary = {}
) -> Dictionary:
	if economy == null:
		return {}
	var reading: Dictionary = LarderRead.forecast(economy, mouths)
	var appetites: Dictionary = reading["appetites"] as Dictionary
	var store: int = int(reading["store_food"])
	# Every mouth the phase feeds, in its own order, so the store can be read
	# against the whole demand instead of the worker pool alone.
	var wanted: int = (
		int(appetites["army"]) + int(appetites["navy"])
		+ int(appetites["pool"]) + int(appetites["wards"])
	)
	return {
		"store": store,
		"wanted": wanted,
		"army": int(appetites["army"]),
		"navy": int(appetites["navy"]),
		"pool": int(appetites["pool"]),
		"wards": int(appetites["wards"]),
		"strikers": int(reading["strikers"]),
		# The reading's own whole-larder shortfall, so the trace and the WORKERS
		# tab can never disagree about what the store is short (REQ-P2-03).
		"short": int(reading["store_short"]),
	}


## The mouths the next Consumption phase feeds before the worker pool: the army's
## rations, the navy's upkeep and the hospital wards, each read the way the
## phase itself reads it (wiki: workers-and-population § Consumption). A session
## with no army or hospital yet reads zeros, so a fixture needs neither. The wards
## ride **one per staff**, because the phase feeds them in order and whole.
static func _mouths(play: PlaySession, faction: int) -> Dictionary:
	var army: int = 0
	if play.army_layer != null:
		army = play.army_layer.food_upkeep_all(faction)
	var wards: Array[int] = []
	var wards_food: int = 0
	if play.world != null:
		wards = HospitalRules.demand_list(play.world, faction)
		for ration: int in wards:
			wards_food += ration
	return {
		"army": army,
		"ships": MapPlayCourt.ships(play, faction),
		"hospital": wards_food,
		"wards": wards,
	}


## One court's observable state. `economy` is that court's ledger whichever
## side (human path in a live game, AiState ledger in the observer).
static func row(play: PlaySession, faction: int) -> Dictionary:
	var config: AiConfig = AiProfile.for_court(faction, play.map_seed, play.ensure_ai().profiles)
	var agenda: String = play.ai.agenda_for(config) if play.ai != null else config.agenda
	var economy: PlayerEconomy = _economy(play, faction)
	# The footing the court plans with this turn (DR-20261113-15): a war, an
	# overstretched court with two fronts, or the published peace. The money goal
	# rides beside it (DR-20261113-19).
	var phase: String = AiPhasePlanner.phase_for(config, play.diplomacy)
	# How close the court stands to the bar it must clear, and whether it is
	# pressing for it (DR-20261114-04). A submission court short of the bar
	# banks for the army that takes the provinces it still needs (issue #995),
	# so the goal the panel reads is the goal the economy pass plans with; a
	# baseline court keeps its published read.
	var pressure: Dictionary = AiVictoryPressure.read(
		play.world, faction, play.human_faction_id(), play.difficulty, config
	)
	var income: Dictionary = AiIncome.plan(
		config, economy, MapPlayCourt.at_war(play, faction),
		play.army_layer.regiment_count_all(faction),
		MapPlayCourt.navy_chest(play, faction),
		MapPlayCourt.warships(play, faction),
		0,
		AiControl.court_kind(play, faction) != AiControl.KIND_BASELINE
		and int(pressure["need"]) > 0
	)
	var strength: float = float(
		MapPlayCourt.public_strength(play).get(faction, 0.0)
	)
	var ships: int = MapPlayCourt.ships(play, faction)
	# Fighting hulls alone: a merchant hull is cargo, not a predator, so the
	# yard's claim and every naval aim are priced on these (issue #484).
	var warships: int = MapPlayCourt.warships(play, faction)
	var old_world: int = play.world.owned_provinces(WorldMap.OLD_WORLD, faction)
	var new_world: int = play.world.owned_provinces(WorldMap.NEW_WORLD, faction)
	var last: Dictionary = _last_turn(play, faction)
	return {
		"faction": faction,
		"name": FactionCatalog.name_of(faction),
		"leader": LeaderCatalog.label(String(play.leaders.get(faction, ""))),
		"agenda": agenda.capitalize().replace("_", " "),
		"profile": config.profile,
		"phase": phase,
		"posture": AiPhasePlanner.label(phase),
		"goal": String(income["goal"]),
		"intent": AiIncome.label(String(income["goal"])),
		"reserve": int(income["reserve"]),
		"plans": AiControl.plans(play, faction),
		"court_kind": AiControl.court_kind(play, faction),
		"provinces_old": old_world,
		"provinces_new": new_world,
		"provinces_total": old_world + new_world,
		"power": AiPower.score(play.world, faction, int(roundf(strength)), ships),
		"strength": int(roundf(strength)),
		"regiments": play.army_layer.regiment_count_all(faction),
		"ships": ships,
		"warships": warships,
		# Holds the crown keeps in port at its seat: the import gate every build
		# input and overseas voyage passes (wiki: ships-and-naval § Cargo holds
		# and capacity; issue #530).
		"holds": TradeCargo.capacity(play.world, play.ship_layer.regions.snapshot(), faction),
		"civilians": play.civilian_layer.unit_count_all(faction),
		# The deeds this court holds: purchased Minor/Tribe land, the tile the
		# Merchant signs and the first-right-of-refusal privilege rides on
		# (issue #841; wiki: civilian-units § Merchant).
		"deeds": deeds_held(play, faction),
		"treasury": economy.treasury if economy != null else 0,
		"stock": economy.total_units() if economy != null else 0,
		# The larder the next Consumption phase will eat: the famine reading the
		# destitute-court signature is measured on (issue #766).
		"larder": larder_reading(economy, _mouths(play, faction)),
		"workers": economy.workers.total() if economy != null else 0,
		"techs": economy.tech_unlocked.size() if economy != null else 0,
		"wars": _war_names(play, faction),
		"alliances": _alliance_count(play, faction),
		"progress": float(old_world) / float(VictoryRules.MILITARY_THRESHOLD),
		"pressure_stage": String(pressure["stage"]),
		"pressure": AiVictoryPressure.label(String(pressure["stage"])),
		"pressure_need": int(pressure["need"]),
		"pressure_regiments": int(pressure["extra_regiments"]),
		"alive": old_world + new_world > 0,
		"last": last,
		"headline": AiTurnLog.headline(last),
	}


## The purchased tiles one court holds across every region: the deeds its
## Merchants signed. A deed keeps its buyer when the province changes hands, so
## the count reads the tile's owner, not the province's (issue #841; wiki:
## civilian-units § Merchant).
static func deeds_held(play: PlaySession, faction: int) -> int:
	if play == null or play.world == null:
		return 0
	var count: int = 0
	for index in play.world.region_count():
		var model: MapModel = play.world.region(index)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			for tile: Vector2i in province.tiles:
				if model.is_purchased_tile(tile) and model.owner_at(tile.x, tile.y) == faction:
					count += 1
	return count


## Turn record of one court, empty before its first resolved turn.
static func _last_turn(play: PlaySession, faction: int) -> Dictionary:
	if play.ai_turns.is_empty():
		return {}
	var merged: Dictionary = play.ai_turns[play.ai_turns.size() - 1]
	var factions: Dictionary = merged.get("factions", {})
	return factions.get(faction, {})


static func _economy(play: PlaySession, faction: int) -> PlayerEconomy:
	return play.ledger_for(faction)


static func _war_names(play: PlaySession, faction: int) -> Array[String]:
	var names: Array[String] = []
	for other: int in MapPlayCourt.at_war_with(play, faction):
		names.append(FactionCatalog.name_of(other))
	names.sort()
	return names


static func _alliance_count(play: PlaySession, faction: int) -> int:
	var total: int = 0
	if play.diplomacy == null:
		return total
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record.formal_alliance:
			total += 1
	return total


static func _winner(play: PlaySession) -> int:
	if play.victory != null:
		return play.victory.winner_player_id
	if play.campaign_halted:
		return MapPlayCampaign.declared_leader(play)
	return NO_ID


static func _result_text(play: PlaySession, winner: int) -> String:
	if play.victory != null:
		return "%s wins a military victory on turn %d." % [
			FactionCatalog.name_of(winner), play.victory.turn_number,
		]
	if play.campaign_halted:
		if winner == NO_ID:
			return "The age is divided — no crown is declared."
		return "%s holds the age at the calendar cap." % FactionCatalog.name_of(winner)
	if winner != NO_ID:
		return "%s leads the campaign." % FactionCatalog.name_of(winner)
	return "Campaign in progress."


## Provinces first (the victory currency), then power, then faction id so the
## same state always ranks the same way.
static func _better_row(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("provinces_old", 0)) != int(b.get("provinces_old", 0)):
		return int(a.get("provinces_old", 0)) > int(b.get("provinces_old", 0))
	if int(a.get("power", 0)) != int(b.get("power", 0)):
		return int(a.get("power", 0)) > int(b.get("power", 0))
	return int(a.get("faction", 0)) < int(b.get("faction", 0))
