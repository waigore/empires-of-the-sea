class_name AiIncome
extends RefCounted
## The court's money goal (wiki: ai-architecture § Money first;
## treasury-planner § Priority; DR-20261113-19).
##
## Income outranks every want a court has except the victory itself, and the
## victory cannot be bought without it: a court that cannot pay for its next
## regiment cannot take a province, and a court that cannot take a province
## never reaches the bar. So before the planners run, each court reads whether
## its purse can already carry its next commitment — the muster it means to
## raise, or its own cash floor once it stands at target.
##
## A court short of that reads `earn`. Its income planners lead (voyages, sales,
## extraction works, prizes); purchases that can wait stand down — no imports
## above the works floor, no new war, no new bid the chest could not spare.
## Studies and hires lead from the purse above the chest (issue #1384): the
## investments the bank's own engines refill the chest with. A court that can
## pay reads `spend` and plays as published. The commitment can be the hull it means to
## lay as readily as the next regiment (issue #484) — but only once the court can
## already fill that chest: a yard price it is still short of waits behind the
## army, because a reserve no planner can pay out starves the regiment the court
## could have raised (issue #591). Pure and deterministic: the purse and the
## target are the only inputs (REQ-P2-03, REQ-P3-03).
##
## The commitment at war is also the storm host the thinnest wall ahead prices
## (issue #1381): while the wall read rides the config the reserve is the host
## its own target arms for, not one line regiment — the wall raises the muster
## target, and the chest is banked to pay for that host when the march opens.
## At peace the wall prices money alone (`storm_bank`): the chest stands when
## the court can already fund the line it would raise today, and the bank keeps
## it to the wall's own host while the purse fills — without the wall ever
## moving and without the stand-down the bank's other readers publish.

const GOAL_EARN: String = "earn"
const GOAL_SPEND: String = "spend"

const LABELS: Dictionary = {
	GOAL_EARN: "earning",
	GOAL_SPEND: "spending",
}


## True when any court holds a declared war on this one: the reserve a court
## must hold is read against it, and a war lifts the muster target by
## `army.war_extra` (wiki: ai-architecture § Land reinforcement).
static func at_war(state: DiplomacyState, faction: int) -> bool:
	if state == null:
		return false
	for record: DiplomacyRelation in state.relations_of(faction):
		if record.at_war:
			return true
	return false


## The purse this court must hold before it may spend on anything it can defer:
## At war: the muster it is saving for and the hull it means to lay (`AiNavy`,
## issue #484) once that chest is in reach — whichever is larger. The muster's
## own read is the storm host the thinnest wall ahead prices (issue #1381): the
## wall reading rides the config, so the chest is banked to pay the host the
## war must field — not one line regiment under a wall it cannot cross. At
## peace: its cash floor, or the hull chest when rebuilding with no fighting
## hull left so the yard is not gifted away before the next war (#484) — plus
## the muster chest once the purse holds the cheapest line's own price, so the
## regiment a peaceful court is one payment short of is banked, not auctioned
## away (#603). 0 when the caller has no ledger to read.
##
## `storm_bank` is the storm chest the wall prices at peace (issue #1381): the
## host its thinnest wall wants, read once by the map layer (`MapPlayArmyMusterAi`
## notes it on the shared config). It rides only while the purse can already
## fund the line it would raise today — the wall prices money alone at peace,
## and a bank no poorer court can reach would freeze its economy — and it keeps
## the peace-time chest sized to the storm host, not one line regiment, so a
## court that banks for conquest funds the march before it declares.
##
## `conquest_gap` is the win-bar reading (issue #995): a court that is short of
## the Old World bar with an army still under target banks for the regiment
## that takes the provinces it needs — at peace as at war. The conquest
## shortfall is the trigger, not the war: the buy-out (#975) and the prompt end
## of pointless wars (#999) often leave a court at peace precisely because it
## has no army, and a peace that never banks never arms. The bank also holds
## through the escalation stall: the gap is the standing reason to bank, so a
## wobble in the fill is not a stall.
##
## `muster_stall` is the deferred-aim escalation reading (#603): the turns the
## muster aim has been deferred without its shortfall shrinking. A war chest
## the court has stalled on re-routes — the reserve falls back to the cash
## floor and the reachable hull chest, so every planner that reads it leads
## again — and the shortfall shrinking resumes the chest as published. The
## shrinking is measured from the episode's own floor (issue #1484): the
## re-route is a damper, not a latch — the margin it frees is spent, the
## record's low resets to the spend-down, and the fill's recovery from that
## dip restarts the stall, which re-arms the chest.
static func reserve(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1, muster_stall: int = 0,
	conquest_gap: bool = false, storm_bank: int = 0
) -> int:
	if config == null or economy == null:
		return 0
	var floor: int = maxi(config.parameter("economy.min_treasury"), 0)
	# The storm host is priced off the war-time read when the wall raises the
	# muster target (the war chest pays the host the war fields); at peace the
	# wall prices money alone — the bank hands the storm host in (issue
	# #1381). The host is regiments; `muster_floor` prices the chest.
	var bank: int = storm_bank if not at_war else storm_want(config, regiments)
	var muster: int = AiArmyReinforce.muster_floor(
		config, economy, regiments, true, bank
	)
	if muster_stall >= maxi(config.parameter("ledger.escalate_turns"), 1):
		# The re-route: the reserve the court cannot reach stands down so the
		# court's own income planners lead again (issue #603). The bar reads
		# two turns, not one (issue #995): a bank that is progressing
		# restarts the stall at one on every new-low turn, and the bar at one
		# answered the fill's own progress — no chest ever closed, at war or
		# at peace. Two turns means a genuine standing-still re-routes and a
		# filling bank never does; the valve itself is untouched. The exit is
		# the record's own (issue #1484): under the re-route the court spends
		# its margin, the deferral record's low resets to that spend-down, and
		# the shortfall's recovery from the dip restarts the stall — the chest
		# re-arms on the fill's first true progress instead of latching shut
		# behind a low water a spend-down can never beat.
		muster = 0
	elif not at_war and not conquest_gap:
		# At peace the war chest is kept only once the purse already holds the
		# cheapest line's own price (wiki: ai-architecture § Land
		# reinforcement): a poorer court keeps its cash floor and grows — no
		# peace-time save phase (DR-20261113-22) — and a court in reach banks
		# the last of the chest instead of auctioning it away the turn peace
		# opens (issue #603). A court short of the bar keeps the whole chest
		# (issue #995): the gap is the trigger, not the war. The storm bank
		# rides the same reach test (issue #1381): the wall prices money
		# alone, so the chest stands only while the line is already funded.
		if economy.treasury < AiArmyReinforce.cheapest_line_price(economy):
			muster = 0
	var held: int = hull_held(
		config, economy, at_war, regiments, hull_chest, own_warships, conquest_gap
	)
	return maxi(floor, maxi(muster, held))


## Regiments the thinnest wall ahead prices at war, off the reading the map
## layer notes on the shared config (`MapPlayArmyMusterAi.storm_extra`): the
## host the wall wants less the host the court already fields, floored at zero
## (issue #1381). Zero with no reading — open ground, or no wall in front.
## The money chest the host needs is `AiArmyReinforce.muster_floor`'s own:
## the host regiments × the cheapest line, so the goal and the muster read
## one purse (`MapPlayArmyMusterAi.storm_chest` prices the same rule).
static func storm_want(config: AiConfig, regiments: int) -> int:
	if config == null:
		return 0
	return maxi(int(config.storm_read.get("want", 0.0)) - maxi(regiments, 0), 0)


## The yard's chest as this court holds it this turn. A chest the court can
## already fill is the fleet's — the purse waits for the hull and the yard leads.
## A chest it cannot afford yet stands behind the army, unless the court has no
## fighting hull left — then the rebuild chest is held even while the muster is
## due (#484, #591) — and never while the court banks for the army its conquest
## still needs (issue #995): a fleetless court at war that is short of the bar
## with a host under strength buys its line before its hull, because the army
## holds the land the yard stands on. 0 when there is no hull to save for.
static func hull_held(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int, own_warships: int = -1, conquest_gap: bool = false
) -> int:
	var chest: int = maxi(hull_chest, 0)
	if config == null or economy == null or chest <= 0:
		return chest
	if economy.treasury >= chest:
		return chest
	if own_warships == 0 and not conquest_gap:
		return chest
	if AiArmyReinforce.muster_floor(config, economy, regiments, at_war) > 0:
		return 0
	return chest


## One turn's goal plus the readings behind it, for the turn trace and the
## observer row. `hull_chest` is the yard price the court is saving for, 0 when
## it is not rebuilding its fleet. `muster_stall` is the deferred-aim
## escalation reading (issue #603; see `reserve`). `conquest_gap` is the
## win-bar reading (issue #995; see `reserve`). `storm_bank` is the storm chest
## the thinnest wall ahead prices (issue #1381; see `reserve`) — the row stamps
## it and the want the war-time target prices it by, so the trace can name the
## host the bank is filling for.
static func plan(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1, muster_stall: int = 0,
	conquest_gap: bool = false, storm_bank: int = 0
) -> Dictionary:
	var bank: int = storm_bank if not at_war else storm_want(config, regiments)
	var need: int = reserve(
		config, economy, at_war, regiments, hull_chest, own_warships, muster_stall,
		conquest_gap, bank
	)
	var held: int = economy.treasury if economy != null else 0
	return {
		"goal": GOAL_EARN if held < need else GOAL_SPEND,
		"reserve": need,
		"treasury": held,
		"regiments": regiments,
		"hull_chest": maxi(hull_chest, 0),
		# The win-bar reading the bank rides on (issue #995): the trace and
		# the treaty rungs read it beside the goal it moved.
		"conquest_gap": conquest_gap,
		# The storm host the bank prices (issue #1381): the chest the bank
		# fills for — the want regiments the thinnest wall ahead prices, at
		# the line's own price — and the want the war-time target prices it
		# by. Zero with no wall in front of the court.
		"storm_want": storm_want(config, regiments),
		"storm_bank": maxi(bank, 0) if bank > 0 else 0,
		# The chest the bank is holding the purse for (issue #995): the
		# canonical reserve with the escalation valve stood down. `reserve`
		# above is the money goal's own — the #603 valve may re-route it to
		# the cash floor while the fill stands still — and a bank that reads
		# the wobbled row releases at the peak of its own fill: the college
		# unpins, the ladder burns the margin, and the chest never closes
		# (measured: the purse parked at ~2,250 against a ~2,600 muster,
		# flickering spend every other turn). A caller with no chest keeps
		# the row it was given (the wobbled reserve stands in).
		"bank_chest": maxi(
			reserve(
				config, economy, at_war, regiments, hull_chest, own_warships, 0,
				conquest_gap, bank
			),
			0
		) if conquest_gap else need,
	}


## Goal name only, for callers that do not keep the readings. `storm_bank` is
## the storm chest the thinnest wall ahead prices at peace (issue #1381).
static func goal_for(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1, conquest_gap: bool = false,
	storm_bank: int = 0
) -> String:
	return String(
		plan(
			config, economy, at_war, regiments, hull_chest, own_warships, 0,
			conquest_gap, storm_bank
		)["goal"]
	)


## True while the court's money comes before anything it can defer. `storm_bank`
## is the storm chest the thinnest wall ahead prices at peace (issue #1381).
static func wants_income(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1, conquest_gap: bool = false,
	storm_bank: int = 0
) -> bool:
	return (
		goal_for(
			config, economy, at_war, regiments, hull_chest, own_warships,
			conquest_gap, storm_bank
		)
		== GOAL_EARN
	)


## The refusal a deferrable spender records while the court is still filling its
## purse, naming the reserve it keeps (wiki: treasury-planner § Priority; issue
## #580). `amount` is what the order would take out of the purse today (0 for an
## order that only promises future money, like a subsidy). Empty when the court
## may spend without dipping under the reserve it is saving for.
static func saving_reason(income: Dictionary, amount: int = 0) -> String:
	# No money goal read (a caller with no ledger) keeps the published behaviour.
	if income.is_empty():
		return ""
	var reserve: int = int(income.get("reserve", 0))
	var held: int = int(income.get("treasury", 0))
	if String(income.get("goal", GOAL_SPEND)) != GOAL_EARN and held - amount >= reserve:
		return ""
	return "the court is saving for its reserve (%d)" % reserve


## True while this court is banking for the army its conquest still needs
## (issue #995): the win-bar gap holds, the host stands under the war-time
## target, and the purse is short of the chest — so every deferrable purchase
## (a war, a pact break, an envoy rung) waits, and a purse that peaks inside a
## turn still belongs to the army that marches before anything else spends it.
## The read is the purse, the host and the bar — and the chest the income row
## stamps (`bank_chest`), never the wobbling money goal: the goal's own
## reserve re-routes on the #603 cycle, and a bank that released at the peak
## of its own fill unpinned the college and burned the margin it was holding
## for. A caller with no ledger or no income row keeps the published
## behaviour.
##
## The release is the host's own price (issue #1488): the purse covers the
## chest — the war's next line, its own levy and price — and the bank lets go.
## The chest the court once banked for was made unreachable by the second
## line's price the shortfall carried on top: the bank's provisioning works
## and the college's ladder spend ~1,000-1,450 a close while the bank holds
## (the trim's own list, by design), the market refills the purse after the
## ledger's read, and a bar a full-AI economy never presents held every court
## at peace for the last 170 turns of the age — no pact broken, no war
## declared, no muster past turn 4. The chest itself is floor-protected while
## it stands (the reserve every planner reads is the chest), so the spending
## the release frees cannot eat it; what the release hands over is the war.
##
## A purse the bank has already filled is not banking (issue #1135): once the
## chest stands in the purse, the army can be paid this turn and the court's
## other spending leads again — the trace names the army aim the bank waits
## for while it holds.
static func banking(
	config: AiConfig, ai_state: AiState, income: Dictionary
) -> bool:
	if config == null or not bool(income.get("conquest_gap", false)):
		return false
	if int(income.get("regiments", 0)) >= AiArmyReinforce.desired_regiments(config, true):
		return false
	var economy: PlayerEconomy = (
		ai_state.economy_for(config.faction) if ai_state != null else null
	)
	if economy == null:
		return false
	# The release is the host's own price (issue #1488): the chest — the war's
	# next line, its own levy and price — is what the bank was holding the
	# purse for. The line's price it carried on top priced a purse the full-AI
	# economy never presents (the provisioning works and the college's ladder
	# spend the close's own margin by design), so the pact break and the
	# declaration waited behind a bar no court could reach and no war opened
	# for the age's last 170 turns.
	var shortfall: int = maxi(
		int(income.get("bank_chest", income.get("reserve", 0))), 0
	)
	return int(income.get("treasury", 0)) < shortfall


## True while this court leads its income investments (issue #1384): the money
## goal reads `earn` — the purse stands under the chest it is saving for — and
## the readers that priced the whole stand-down off that goal held the college
## and the hire shut while the chest filled. The goal keeps naming the court's
## money first; this read is the split the investments follow: the chest keeps
## its claim on the deferrable purchases, and the studies and the region's own
## crews lead from the purse the same floors every other claim reads. A caller
## with no ledger keeps the published behaviour.
static func invests(config: AiConfig, ai_state: AiState, income: Dictionary) -> bool:
	if config == null:
		return false
	var economy: PlayerEconomy = (
		ai_state.economy_for(config.faction) if ai_state != null else null
	)
	if economy == null:
		return false
	return String(income.get("goal", GOAL_SPEND)) == GOAL_EARN


## The army aim the bank's purse is held for, in the trace's words (issue
## #1135): the host line the conquest marches behind — an aim that moves once
## the chest is paid, so a court that keeps its envoy shut names what its one
## order is waiting for instead of a bare refusal.
static func bank_refusal(config: AiConfig, ai_state: AiState, income: Dictionary) -> String:
	if not banking(config, ai_state, income):
		return ""
	return "the court is banking for its army (the host line %d of %d)" % [
		int(income.get("regiments", 0)),
		AiArmyReinforce.desired_regiments(config, true),
	]


## Reader-facing goal for the observer panel and the turn trace.
static func label(goal: String) -> String:
	return String(LABELS.get(goal, LABELS[GOAL_SPEND]))
