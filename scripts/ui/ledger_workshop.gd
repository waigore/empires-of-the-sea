class_name LedgerWorkshop
extends RefCounted
## Plain-text (and pure) copy for a production row's workshop: what the kiln is
## doing now and what its tag promises. No visual nodes, so it is cheap to unit
## test and the ledger, the market and the tooltips read the same words
## (REQ-P3-01, REQ-P3-03).


## The workshop tag on a production row: empty for one-turn work, "2t" when the
## row waits, "3→1t" while three units serve and the next lands in one phase. The
## row's stepper stays what the player set; this is only what the kiln is doing,
## and one unit leaves it each Production phase (DR-20261113-02).
static func note(economy: PlayerEconomy, recipe_id: String) -> String:
	if economy == null:
		return ""
	var serving: int = economy.production.wip_units(recipe_id)
	if serving > 0:
		return "%d→%dt" % [serving, maxi(economy.production.wip_turns(recipe_id), 1)]
	var turns: int = ProductionRecipes.turns(recipe_id)
	return "" if turns <= 1 else "%dt" % turns


## What the tag promises, spelled out for a long press or a hover. A multi-turn
## batch lands one unit a Production phase, so the note says how many are still
## on the anvil and when the next one lands (wiki: production-recipes § Turns per
## unit; DR-20261113-02).
##
## A court that leaves the row set starts a fresh batch every phase, and those
## batches each give up a unit — so the note names the cadence the phase will
## actually pay (two batches, two a phase) rather than promising the single
## batch's trickle (REQ-P2-03, REQ-P5-05).
static func tooltip(economy: PlayerEconomy, recipe_id: String) -> String:
	var turns: int = ProductionRecipes.turns(recipe_id)
	var serving: int = 0 if economy == null else economy.production.wip_units(recipe_id)
	if serving <= 0:
		if turns <= 1:
			return ""
		return "Ready next turn: a run pays its inputs and labour, then lands one unit a turn."
	var wait: int = maxi(economy.production.wip_turns(recipe_id), 1)
	# One unit leaves the workshop per batch on its landing phase, so the note
	# counts batches, not units in flight (`ledger_market` reads its rules helper
	# from here too).
	var landings: int = 0 if economy == null else ProductionWorkshop.ready_units(
		economy.production_wip, recipe_id, turns
	)
	var cadence: String = "still serving their turns"
	if landings == 1:
		cadence = "landing one a turn"
	elif landings > 1:
		cadence = "%d landing a turn" % landings
	return (
		"%d unit%s already in the workshop, %s — the next in %d turn%s. "
		+ "Runs started now wait %d turn%s."
	) % [
		serving,
		"" if serving == 1 else "s",
		cadence,
		wait,
		"" if wait == 1 else "s",
		turns,
		"" if turns == 1 else "s",
	]


## What one manufacture row's "+" can still buy this turn: the phase's own
## labour-and-inputs ceiling, so a court is never offered runs the Production
## phase would refuse (wiki: stockpiles-and-production § Production flow).
static func allowance_note(recipe_id: String, units: int) -> String:
	var good: String = CommodityCatalog.label(ProductionRecipes.output(recipe_id))
	if units <= 0:
		return "No labour or inputs spare a %s this turn." % good
	if units == 1:
		return "Labour and inputs allow 1 %s this turn." % good
	return "Labour and inputs allow %d %s this turn." % [units, good]
