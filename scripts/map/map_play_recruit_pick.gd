class_name MapPlayRecruitPick
extends RefCounted
## The workers the court's own economy pass would recruit this phase — and, when
## it buys none, the gate that leaves the pool alone (wiki:
## workers-and-population § Recruiting, § Recruit vs. train; economy-planner
## § Playable slice; DR-20261122-01).
##
## The reading is not a second opinion: it is `recruitment_orders` — the call
## `MapPlayEconomyCourt.apply_turn` books every court's workers from, now read
## through the court's own `recruit_orders` — over a court opened by
## `MapPlayEconomyCourt.draft` and read through `rehearse`, the same figures the
## pass plans with, so the tab cannot name a hire the pass would not book
## (REQ-P2-03, REQ-P3-03).
##
## A reading only: nothing here enlists, pays, promotes or demotes a worker, and
## the crown still presses her own Recruit (REQ-P5-06).

## The plan buys workers: the phase would recruit these tiers.
const KIND_RECRUIT: String = "recruit"
## No hire is booked because the pool already stands at the target it keeps.
const KIND_TARGET: String = "target"
## No hire is booked because the larder cannot carry another mouth (issue #489).
const KIND_LARDER: String = "larder"
## No hire is booked because the court banks its purse for the army its bar
## still needs, and its provision already stands (issue #1059).
const KIND_BANK: String = "bank"
## No hire is booked and the sheet can read no gate of its own.
const KIND_QUIET: String = "quiet"

## The most tiers one line names before it counts the rest, so a handset's
## reading stays one line of chrome (REQ-P5-07).
const NAMED_LIMIT: int = 3

const LARDER_LINE: String = (
	"the court would recruit no worker this phase — its larder cannot feed "
	+ "another mouth"
)
const BANK_LINE: String = (
	"the court would recruit no worker this phase — it banks its purse for the "
	+ "army its bar still needs"
)
const QUIET_LINE: String = "the court would recruit no worker this phase"


## The sheet's sentence: the pick's own clause, capitalised and closed — the
## same one wording every pick surface prints (REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession) -> String:
	return MapPlayPickProse.sentence_of(pick(play))


## The ledger's pick as the WORKERS tab prints it: `{kind, tiers, line}`, where
## `tiers` maps a worker tier to the heads the plan buys. Empty when the session
## runs no planner for the crown, an observer session, a decided campaign, a
## crown with no ledger or a session with no civilian layer.
static func pick(play: PlaySession) -> Dictionary:
	if not MapPlayPickProse.crown_crew_ready(play):
		return {}
	if play.world == null or play.ai == null:
		return {}
	var faction: int = play.player_faction
	var court: MapPlayEconomyCourt = MapPlayEconomyCourt.draft(
		play, faction, MapPlayEconomyAi._market(play)
	)
	if court.economy == null:
		return {}
	court.rehearse()
	if not (court.config is AiConfig):
		return {}
	return of(
		court.economy, court.config, court.recruit_orders(court.harvest_slack()),
		court.fed_slack(), court.conquest_bank
	)


## The pick, worded off the plan and the court's own figures alone: the tiers the
## plan buys, or the gate that leaves the pool alone. `slack` is the larder's
## harvest slack the hire paces itself by, `bank` the court's conquest bank.
## Pure — a sheet and its suite drive it without a session.
static func of(
	economy: PlayerEconomy, config: Variant, orders: Array, slack: int,
	bank: bool
) -> Dictionary:
	if economy == null or not (config is AiConfig):
		return {}
	var tiers: Dictionary = {}
	for raw: Variant in orders:
		if not (raw is Dictionary):
			continue
		var tier: int = int((raw as Dictionary).get("tier", -1))
		if tier < 0 or tier >= WorkerPool.TIER_COUNT:
			continue
		tiers[tier] = int(tiers.get(tier, 0)) + 1
	if not tiers.is_empty():
		return {"kind": KIND_RECRUIT, "tiers": tiers, "line": recruit_line(tiers)}
	# The plan buys nothing: the gate its own figures show, in the order the
	# planner weighs them — the target the pool already holds, the larder, the
	# bank — else the flat line, because a refusal the sheet cannot read is the
	# tier rows' to name and never the counsel's to invent (REQ-P5-06).
	var target: int = int(config.parameter("economy.worker_target"))
	if economy.workers.total() >= target:
		return {
			"kind": KIND_TARGET, "tiers": {},
			"line": target_line(target), "target": target,
		}
	var tier: int = best_tier(economy)
	if tier >= 0 and slack >= 0 and slack < WorkerPool.FOOD_PER_WORKER[tier]:
		return {"kind": KIND_LARDER, "tiers": {}, "line": LARDER_LINE}
	if bank:
		return {"kind": KIND_BANK, "tiers": {}, "line": BANK_LINE}
	return {"kind": KIND_QUIET, "tiers": {}, "line": QUIET_LINE}


## "the court would recruit 3 Peasants and 1 Apprentice this phase". Tiers in the
## ladder's own order — the order the page prints its rows in — so the clause
## reads down the sheet it answers, and beyond three it counts the tiers it
## cannot name (`… and 1 more`).
static func recruit_line(tiers: Dictionary) -> String:
	var parts: Array[String] = []
	for tier in WorkerPool.TIER_COUNT:
		if not tiers.has(tier):
			continue
		var count: int = int(tiers[tier])
		var label: String = (
			WorkerPool.tier_name(tier) if count > 1 else WorkerPool.tier_one(tier)
		)
		parts.append("%d %s" % [count, label])
	var joined: String = MapPlayPickProse.capped(parts, NAMED_LIMIT)
	if joined.is_empty():
		return ""
	return "the court would recruit %s this phase" % joined


## "the court would recruit no worker this phase — its pool already stands at the
## 8 it keeps": the target the court plans its pool to, named rather than an
## empty page (wiki: workers-and-population § Phase placement).
static func target_line(target: int) -> String:
	return (
		"the court would recruit no worker this phase — its pool already stands "
		+ ("at the %d it keeps" % target)
	)


## The highest tier the rules would let this court recruit today, or -1 when
## every tier is refused: the ladder the published planner walks, read off the
## rules layer's own refusal (`PlayerEconomy.recruit_blocked_reason`).
static func best_tier(economy: PlayerEconomy) -> int:
	for tier in range(WorkerPool.TIER_COUNT - 1, -1, -1):
		if economy.recruit_blocked_reason(tier).is_empty():
			return tier
	return -1
