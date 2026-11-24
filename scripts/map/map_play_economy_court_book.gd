class_name MapPlayEconomyCourtBook
extends RefCounted
## One rival court's research and trade book for the economy turn (docs/ai.md):
## what it studies and what it stages on the shared market. `MapPlayEconomyCourt`
## owns the turn; this owner plans the book against the footing the court already
## read, so the ledger and the book cannot drift apart (REQ-P2-03, REQ-P3-01,
## REQ-P3-03).

## Which link of the door chain a court stands in, for the words that name it
## (wiki: tech-tree § Research model; DR-20261121-01).
const DOOR_HULL: String = "hull"
const DOOR_CHAIN: String = "chain"
const DOOR_DEED: String = "deed"


## The study a court's open door needs this turn, with the link that gave it:
## the yard's next hull while the court is at war short of hulls (issue #484),
## else the envoy chain's next stage (DR-20261114-05), else the study a charted
## deed waits on — the tech that hires the buyer, because the hire, the chain and
## the purchase all wait on it (issue #841; wiki: civilian-units § Merchant).
## Pure reads: one home for the chain, so this book's plan and the crown's
## college pick cannot walk two different chains (`MapPlayResearchPick`).
static func door(
	play: PlaySession,
	faction: int,
	economy: PlayerEconomy,
	phase: String,
	at_war: bool,
	warships: int
) -> Dictionary:
	if play == null or economy == null:
		return {}
	if AiNavy.due(at_war, warships, MapPlayCourt.hostile_warships(play, faction)):
		var hull: String = AiNavy.unlock_tech(
			economy, MapPlayCourt.hull_types(play, faction)
		)
		if not hull.is_empty():
			return {"tech": hull, "why": DOOR_HULL}
	var chain: String = AiTribeColony.door(
		play.diplomacy, play.world, play.court_charts, faction,
		economy.tech_unlocked, phase
	)
	if not chain.is_empty():
		return {"tech": chain, "why": DOOR_CHAIN}
	var deed: String = AiMerchantWork.deed_door(
		play.world, faction, play.court_charts, play.diplomacy, economy.tech_unlocked
	)
	if not deed.is_empty():
		return {"tech": deed, "why": DOOR_DEED}
	return {}


## The door's study alone: what the research plan hands the ranking.
static func door_tech(
	play: PlaySession,
	faction: int,
	economy: PlayerEconomy,
	phase: String,
	at_war: bool,
	warships: int
) -> String:
	return String(door(play, faction, economy, phase, at_war, warships).get("tech", ""))


## What the court studies this turn: surplus above the money-first reserve,
## the navy unlock door first and the Tribe chain after it (issue #484, #490).
## While the court banks (issue #995) the bank's own chest holds the purse —
## and the bank's income investments lead from the purse above it (issue
## #1384): the college's ladder and doors read the invest floor — the court's
## own cash floor — so the bank's fill is paid for by the studies it opens,
## and the chest itself stays the reserve the bank holds.
static func research(court: MapPlayEconomyCourt) -> Dictionary:
	var revealed: Dictionary = MapPlayCourtFog.research_revealed(court.play, court.faction)
	# Surplus research still leaves the money-first reserve alone; the standing
	# study alone may dip to the cash floor so a war-time court parked at 500
	# while saving 2,400 still learns (issue #490).
	var research_floor: int = AiBindEconomy.research_floor(court.kind, court.config)
	# The banked split (issue #1384): the invest floor — the same cash floor
	# every other claim reads — is what the ladder and the doors lead from,
	# while the chest itself stays the reserve the bank holds. A court not
	# banking keeps the published goal reserve; the standing study keeps the
	# #490 cash-floor gate either way, so a court parked at the floor still
	# learns.
	var invest_floor: int = (
		maxi(int(court.config.parameter("economy.min_treasury")), 0)
		if court.invest_bank else 0
	)
	# The court's open door: the yard's next hull, else the Tribe chain, else the
	# deed's buyer (issue #484, #841; DR-20261114-05). One home for the chain, so
	# the crown's college reads the same door this plan walks
	# (`MapPlayResearchPick`; DR-20261121-01).
	var door: String = String(door_tech(
		court.play, court.faction, court.economy, court.phase, court.at_war,
		court.warships
	))
	# The chest the conquest bank is holding the purse for (issue #995): the
	# canonical reserve the income row stamps beside the wobbling goal. The
	# money goal's own reserve wobbles when the #603 valve re-routes it to the
	# cash floor, and a floor that falls with the wobble lets the college's
	# ladder burn the very fill the bank is holding for — measured 450 ducats
	# on the one turn a big sale landed.
	var bank_chest: int = (
		int(court.income.get("bank_chest", 0)) if court.conquest_bank else 0
	)
	# The floors the college reads: the banked split hands the ladder and the
	# doors the invest floor (issue #1384); every other court keeps the
	# published chest — the bank chest on the conquest bank, the money goal's
	# own reserve otherwise.
	var ladder_floor: int = (
		invest_floor
		if court.invest_bank
		else bank_chest if court.conquest_bank else court.floor
	)
	var door_floor: int = (
		invest_floor if court.invest_bank
		else bank_chest if court.conquest_bank else 0
	)
	return AiBindEconomy.research_plan(
		court.kind, court.config, court.economy,
		{
			"at_war": court.at_war,
			"revealed": revealed,
			"treasury_floor": ladder_floor,
			"cash_floor": research_floor,
			"door": door,
			"defer_standing": court.hull_chest > 0,  # yard fills before standing (#484)
			# The bank the doors honor while the court arms (issue #995), and
			# the chest the yard is banking for (issue #1126): a door study
			# priced over the cash floor alone spent 150 ducats the turn the
			# hull's chest closed, so the yard never laid the hull it had
			# saved for.
			"conquest_reserve": door_floor,
			"navy_reserve": court.hull_chest,
			# The standing slot carries the ration ladder while the court
			# banks (issue #1059): the farms the host eats from lift their
			# caps on the one preset that may dip into the chest.
			"conquest_bank": court.conquest_bank,
		}
	)


## The rival's leaderKey, whose published funding multiplier lifts its research
## points (wiki: leader-bonuses § Bonus Table — Victoria). The study plan reads
## it from here, beside the door it funds.
static func leader(play: PlaySession, faction: int) -> String:
	return String(play.leaders.get(faction, ""))


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
##
## The plan only: `trade` stages it. A sheet that names the trade without booking
## it (`MapPlayMarketPick`) reads here, so the two cannot name different books
## (REQ-P2-03; DR-20261121-09).
static func trade_plan(court: MapPlayEconomyCourt) -> Dictionary:
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
	var food: int = MapPlayEconomyLarder.food_demand(
		court.play, court.faction, court.economy
	)
	var food_short: int = maxi(
		food * 2 - EconomyConsumption.food_available(court.economy.stockpile), 0
	)
	# One primitive for every reservation: the rations, the muster's row, the
	# works and this turn's production are ranked claims, and the market reads
	# what the allocator funded (issue #491 T3, #498).
	var claims: Dictionary = AiClaims.reserve(MapPlayEconomyLarder.claim_rows(
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
	# (DR-20261117-01), and the published market fills the rest. A phoney war
	# holds no front (issue #995): the #999 read already erodes a war that has
	# taken no attack to its peace, and the coin a silent front kept shut
	# belongs to the bank's chest — so a submission court whose every crown war
	# is phoney opens the top-up while the peace leg ends them. A frozen
	# baseline keeps the published footing: its planners hold no bank (issue
	# #995's subject-scoped surface).
	var speculate: bool = AiPhasePlanner.opens(
		court.phase, AiPhasePlanner.SLOT_MARKET
	)
	if not speculate and court.kind != AiControl.KIND_BASELINE and not AiWarMemory.holds_front(
		court.config, court.play.ai, court.play.diplomacy, court.play.turn,
		court.faction
	):
		speculate = true
	var plan: Dictionary = AiBindEconomy.market_plan(
		court.kind, court.config, court.economy, court.market, free_holds,
		court.economy.tech_unlocked, reserved,
		MapPlayEconomyLarder.merge_rows(need, navy), court.floor, food_short, saving,
		speculate, works_floor, court.hire_margin
	)
	plan["free_holds"] = free_holds
	var drafted: Dictionary = {
		"plan": plan,
		"free_holds": free_holds,
		# The crown's holds and the tonnage its colonies ship, so the clearing can
		# judge a carried bid against the trade cargo capacity the wiki names rather
		# than the holds this turn's imports used (wiki: world-market § Order
		# persistence, § Cargo).
		"holds": holds,
		"reserved": EconomyOverseas.shipped_total(court.overseas),
		"claims": claims["lines"],
	}
	# The bidding the footing held shut prints with its reason rather than going
	# quiet (REQ-P5-05; DR-20261117-01).
	if not speculate and int(plan.get("held", 0)) > 0:
		drafted["bids_blocked"] = AiMarketPlanner.REASON_SPECULATE
	return drafted


## The court's trade, staged in the world-market book for the turn's close.
static func trade(court: MapPlayEconomyCourt) -> Dictionary:
	var drafted: Dictionary = trade_plan(court)
	var plan: Dictionary = drafted["plan"] as Dictionary
	var result: Dictionary = AiBindEconomy.market_stage(
		court.kind, court.economy, court.market, plan, court.faction,
		court.economy.tech_unlocked
	)
	result["plan"] = plan
	result["free_holds"] = drafted["free_holds"]
	result["holds"] = drafted["holds"]
	result["reserved"] = drafted["reserved"]
	result["claims"] = drafted["claims"]
	if drafted.has("bids_blocked"):
		result["bids_blocked"] = drafted["bids_blocked"]
	return result
