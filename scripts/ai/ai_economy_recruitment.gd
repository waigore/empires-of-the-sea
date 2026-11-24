class_name AiEconomyRecruitment
extends RefCounted
## Rival worker hire and train orders (wiki: workers-and-population § Rival
## training throttle; growth-stage-planner § Recruitment modulation).
##
## Highest affordable tier first, capped per turn and at the worker target. A
## copy is spent first, so the live ledger sees only the rows the rules already
## accepted. Two throttles keep the court growing rather than spent out:
## training never consumes the court's last peasant, and it never leaves the
## purse under its cash floor while the court could still train again next turn.
## Pure rules: config and ledger in, hire rows out (REQ-P2-03, REQ-P3-03).
## [AiEconomyPlanner] keeps the public door; the workshop plan and ground
## appetite live on [AiEconomyProduction] and [AiEconomyAppetite].


## Recruit orders for one turn. `floor` is the muster cash veto a caller hands
## in (issue #474). `fed_slack` is the grain the larder leaves after the army,
## the navy and the workers eat: a court hires no mouth it cannot feed (issue
## #489). A negative reading means the caller has no larder to read, and the
## gate does not apply. `hands` is the peasant count the muster reservation
## keeps (`AiArmyReinforce.muster_hands`): a court whose muster is
## legal-and-funded this turn trains no hand the levy itself would consume
## (issue #807). 0 keeps the published last-peasant throttle. `conquest_bank`
## is the win-bar reading (issue #995): a court short of the bar banking for
## its next line hires its farmhands against the cash floor. `harvest_slack`
## paces that bank against the land's own rations (issue #1059).
static func recruitment_orders(
	config: AiConfig, economy: PlayerEconomy, floor: int = 0, fed_slack: int = -1,
	hands: int = 0, conquest_bank: bool = false,
	harvest_slack: int = -2
) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	if config == null or economy == null:
		return orders
	var target: int = config.parameter("economy.worker_target")
	if economy.workers.total() >= target:
		return orders
	var min_treasury: int = maxi(config.parameter("economy.min_treasury"), 0)
	# The muster floor a caller hands in is a hard veto: a court saving for its
	# next regiment buys no workers with that purse (issue #474). The court's own
	# cash floor keeps its soft throttle, so peace-time growth still takes the
	# one training a thin purse can pay. The published last-peasant throttle
	# stands whenever no muster reservation is read (issue #807). A slack the
	# caller did read blocks below the tier's own ration — a court already
	# striking for food trains no mouth it cannot feed (#489); the −1 sentinel
	# keeps the no-reading behaviour.
	var muster_floor: int = maxi(floor, 0)
	var hand_floor: int = maxi(hands, 1)
	# The levy's own floor (issue #995): the pool the conquest bank needs to
	# even have a chest — `army.min_peasants` plus the levy's own hand spare.
	var levy_floor: int = maxi(config.parameter("army.min_peasants"), 0) \
		+ RegimentEconomy.WORKER_COST
	# The bar the harvest carries (issue #1059): while the court banks for the
	# army its conquest needs, the pool it hires is the levy's own provision —
	# the levy floor, not `economy.worker_target`. Every mouth past the levy's
	# hand eats one of the rations the muster's own gate plans with, and the
	# measured probe watched the farms' growth (+7 rations a turn by t80) fall
	# whole into six new mouths — the slack sat at 0 for a hundred turns and
	# the muster's ration gate with it. The pace reads the harvest slack: a
	# court whose land cannot carry one more ration hires no mouth this turn.
	# A caller with no reading keeps the published target.
	var pool_target: int = (
		maxi(levy_floor, economy.workers.count(WorkerPool.Tier.PEASANT))
		if conquest_bank and harvest_slack >= -1
		else target
	)
	var sim: PlayerEconomy = economy.copy()
	for _turn in maxi(config.parameter("economy.max_recruits"), 0):
		if sim.workers.total() >= pool_target:
			break
		var tier: int = -1
		if conquest_bank and sim.available_peasants() < levy_floor:
			# The conquest bank's own provision (issue #995): when the pool
			# cannot carry the levy's hand, the farmhand comes first — the
			# chest the restored pool re-opens is the army's, not an optional
			# build. The measured bench froze a short-of-bar court at three
			# peasants for a hundred and ninety turns: no hands, no chest, no
			# line, and every worker it could afford consumed one.
			tier = WorkerPool.Tier.PEASANT
		elif conquest_bank and harvest_slack >= -1 \
				and sim.available_peasants() >= levy_floor:
			# The pool carries the levy: while the bank holds with a harvest
			# to pace by, the trained tiers wait — a hire the muster cannot
			# afford to feed is not the army's provision (issue #1059). A
			# caller with no reading keeps the published ladder.
			break
		else:
			tier = _best_tier(sim)
		if tier < 0:
			break
		if fed_slack != -1 and fed_slack < WorkerPool.FOOD_PER_WORKER[tier]:
			break
		# The harvest carries the mouth (issue #1059): the reading the muster's
		# own gate plans with — one hire eats one of the rations that gate
		# wants for the levy. The bank's own pace; a court not banking keeps
		# the published gate alone. The −2 sentinel keeps the no-reading.
		if conquest_bank and harvest_slack >= -1 \
				and harvest_slack < WorkerPool.FOOD_PER_WORKER[tier]:
			break
		if WorkerPool.RECRUIT_CONSUMES_PEASANTS[tier] \
				and sim.workers.count(WorkerPool.Tier.PEASANT) <= hand_floor:
			break
		if muster_floor > min_treasury and sim.treasury - _trains(sim, tier) < muster_floor:
			# A farmhand the bank hires for its levy is the army's provision
			# (issue #995): it reads the cash floor like the food it eats.
			if not (conquest_bank and tier == WorkerPool.Tier.PEASANT):
				break
		if sim.treasury - _trains(sim, tier) < min_treasury \
				and _next_training_affordable(sim, min_treasury):
			break
		var result: Dictionary = sim.recruit(tier)
		if not bool(result.get("ok", false)):
			break
		fed_slack -= WorkerPool.FOOD_PER_WORKER[tier]
		if conquest_bank and harvest_slack >= -1:
			harvest_slack -= WorkerPool.FOOD_PER_WORKER[tier]
		orders.append({"tier": tier})
	return orders


## True when the purse could already pay a trained-tier row today, i.e. the
## court has slack outside `economy.min_treasury` and could train again next
## turn once its materials land. Peasant count is checked by the caller.
static func _next_training_affordable(economy: PlayerEconomy, reserve: int) -> bool:
	for tier in range(1, WorkerPool.TIER_COUNT):
		if not _techs_open(economy, tier):
			continue
		if economy.treasury - reserve >= _trains(economy, tier):
			return true
	return false


## True when this court's own techs already open `tier`, whatever its materials
## or peasant count say today.
static func _techs_open(economy: PlayerEconomy, tier: int) -> bool:
	return economy != null and WorkerPool.techs_unlocked(tier, economy.tech_unlocked)


## Treasury a training of `tier` would cost this court, or -1 for a bad tier.
static func _trains(economy: PlayerEconomy, tier: int) -> int:
	if economy == null or tier < 0 or tier >= WorkerPool.TIER_COUNT:
		return -1
	return int(WorkerPool.recruit_cost(tier).get("treasury", 0))


## Highest tier this court can legally train right now, or -1. Peasants are the
## fallback: a court with no worker tech still buys one peasant a turn, which is
## how the pool ever reaches `economy.worker_target` (wiki: workers-and-population
## § Recruit vs. train).
static func _best_tier(economy: PlayerEconomy) -> int:
	for tier in range(WorkerPool.TIER_COUNT - 1, -1, -1):
		if economy.recruit_blocked_reason(tier).is_empty():
			return tier
	return -1
