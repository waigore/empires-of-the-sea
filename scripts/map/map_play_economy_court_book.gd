class_name MapPlayEconomyCourtBook
extends RefCounted
## One rival court's research and trade book for the economy turn (docs/ai.md):
## what it studies and what it stages on the shared market. `MapPlayEconomyCourt`
## owns the turn; this owner plans the book against the footing the court already
## read, so the ledger and the book cannot drift apart (REQ-P2-03, REQ-P3-01,
## REQ-P3-03).


## What the court studies this turn: surplus above the money-first reserve,
## the navy unlock door first and the Tribe chain after it (issue #484, #490).
static func research(court: MapPlayEconomyCourt) -> Dictionary:
	var revealed: Dictionary = MapPlayCourtFog.research_revealed(court.play, court.faction)
	# Surplus research still leaves the money-first reserve alone; the standing
	# study alone may dip to the cash floor so a war-time court parked at 500
	# while saving 2,400 still learns (issue #490).
	var research_floor: int = AiBindEconomy.research_floor(court.kind, court.config)
	# Navy unlock door first, else Tribe chain (issue #484; DR-20261114-05).
	var door: String = ""
	if AiNavy.due(
		court.at_war, court.warships,
		MapPlayCourt.hostile_warships(court.play, court.faction)
	):
		door = AiNavy.unlock_tech(
			court.economy, MapPlayCourt.hull_types(court.play, court.faction)
		)
	if door.is_empty():
		door = AiTribeColony.door(
			court.play.diplomacy, court.play.world, court.play.court_charts,
			court.faction, court.economy.tech_unlocked, court.phase
		)
	# The deed door, buyer-gated: a court that has a priced deed on its chart and
	# no Merchant Companies studies the tech that hires the buyer. The study is
	# the closed link — the hire, the envoy chain and the purchase all wait on it
	# (issue #841; wiki: civilian-units § Merchant).
	if door.is_empty():
		door = AiMerchantWork.deed_door(
			court.play.world, court.faction, court.play.court_charts,
			court.play.diplomacy, court.economy.tech_unlocked
		)
	return AiBindEconomy.research_plan(
		court.kind, court.config, court.economy,
		{
			"at_war": court.at_war,
			"revealed": revealed,
			"treasury_floor": court.floor,
			"cash_floor": research_floor,
			"door": door,
			"defer_standing": court.hull_chest > 0,  # yard fills before standing (#484)
			# The bank the doors honor while the court arms (issue #995).
			"conquest_reserve": court.floor if court.conquest_bank else 0,
		}
	)


## The crew the hire order would take this turn, at the catalogue's price: the
## market keeps that cash back from its bids, so a court at its cash floor that
## has lost a Builder can still buy one (issue #894). Read from the home region's
## plan, which is where the court musters its crews.
static func hire_margin(court: MapPlayEconomyCourt) -> int:
	# The baseline planners keep their published market: the margin is the
	# submission surface's own reading (AiBind).
	if court.kind == AiControl.KIND_BASELINE:
		return 0
	var home: int = FactionCatalog.region_of(court.faction)
	for entry: Dictionary in court.plans:
		if int(entry.get("region", -1)) != home:
			continue
		var plan: Dictionary = entry.get("plan", {})
		var next: String = String(plan.get("next_crew", ""))
		if next.is_empty():
			return 0
		return CivilianCatalog.treasury_cost(next)
	return 0


## Sells above the reserve and this turn's inputs, then bids short build inputs
## with the holds the colonies left (wiki: world-market § Cargo). The cloth the
## next regiment must have is kept back and bid for first (wiki:
## growth-stage-planner § Recruitment modulation), and so is every material a
## crew's planned work will spend (wiki: economy-planner § Reservations).
static func trade(court: MapPlayEconomyCourt) -> Dictionary:
	var holds: int = (
		TradeCargo.capacity(
			court.play.world, court.play.ship_layer.regions.snapshot(), court.faction
		)
		if court.play.ship_layer != null else 0
	)
	var free_holds: int = maxi(
		holds - EconomyOverseas.shipped_total(court.overseas)
		- TradeCargo.used(court.market, court.faction),
		0
	)
	# The muster's material row and the hull's: read once in `plan_turn`, so
	# production, the market and the claims read one row apiece (issue #484).
	var need: Dictionary = court.muster_row
	# The hull the court is saving for holds its own material row beside the
	# muster's: a court that sells the last cloth it needs can save the whole
	# 5,500-ducat chest and still never lay the hull (issue #484). A chest that
	# has stood down (the yard re-routed to the muster, issue #603) holds no row
	# either, so the cloth it would have kept back is the regiment's.
	var navy: Dictionary = court.navy_row
	# The ration the larder cannot cover: a court that cannot feed its own people
	# is in the wiki's lock-recovery mode, so the market liquidates its hoard and
	# buys the missing food before any build input (wiki: treasury-planner
	# § Lock-recovery; issue #489). The reading is forward-looking — the larder
	# must cover this turn's ration and leave the next one in hand, because a
	# court that eats its last grain this turn strikes tomorrow.
	var food: int = MapPlayEconomyAi._food_demand(
		court.play, court.faction, court.economy
	)
	var food_short: int = maxi(
		food * 2 - EconomyConsumption.food_available(court.economy.stockpile), 0
	)
	# One primitive for every reservation: the rations, the muster's row, the
	# works and this turn's production are ranked claims, and the market reads
	# what the allocator funded (issue #491 T3, #498).
	var claims: Dictionary = AiClaims.reserve(MapPlayEconomyAi._claim_rows(
		court.production, food, court.economy, need, court.works_reserved, navy
	))
	var reserved: Dictionary = claims["reserved"]
	var saving: bool = String(court.income["goal"]) == AiIncome.GOAL_EARN
	# Market feedstock bids sit behind the war chest while the court is saving:
	# the civilian pass still draws extraction on the cash floor (#878), but the
	# bid book must not auction away the muster the earn goal is holding for —
	# otherwise a timber court spends every spare ducat on lumber/iron and the
	# chest never closes (#910 stall on seed 1500).
	var works_floor: int = court.floor if saving else -1
	# A court at war opens no speculative top-up: the slot is the footing's
	# (DR-20261117-01), and the published market fills the rest.
	var speculate: bool = AiPhasePlanner.opens(
		court.phase, AiPhasePlanner.SLOT_MARKET
	)
	var plan: Dictionary = AiBindEconomy.market_plan(
		court.kind, court.config, court.economy, court.market, free_holds,
		court.economy.tech_unlocked, reserved,
		MapPlayEconomyAi._merge_rows(need, navy), court.floor, food_short, saving,
		speculate, works_floor, court.hire_margin
	)
	plan["free_holds"] = free_holds
	var result: Dictionary = AiBindEconomy.market_stage(
		court.kind, court.economy, court.market, plan, court.faction,
		court.economy.tech_unlocked
	)
	result["plan"] = plan
	result["free_holds"] = free_holds
	result["claims"] = claims["lines"]
	# The bidding the footing held shut prints with its reason rather than going
	# quiet (REQ-P5-05; DR-20261117-01).
	if not speculate and int(plan.get("held", 0)) > 0:
		result["bids_blocked"] = AiMarketPlanner.REASON_SPECULATE
	return result
