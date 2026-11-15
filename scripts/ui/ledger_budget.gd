class_name LedgerBudget
extends RefCounted
## The market tab's bid budget line: the purse the turn's auction may spend once
## the waiting Build/work orders are paid (wiki: world-market § Treasury budget
## for bids; DR-20261115-13). One builder, so the sheet keeps its own rows and
## the figure stays the validator's own (REQ-P3-01, REQ-P2-03).


## The banner for one crown's purse, or null when there is no ledger to read.
static func banner(economy: PlayerEconomy) -> Label:
	if economy == null:
		return null
	var reading: Dictionary = MarketBudget.budget(economy)
	var line := UiRowBuilder.label(
		LedgerText.bid_budget_line(reading), 12, LedgerText.bid_budget_color(reading)
	)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(240, 0)
	line.tooltip_text = (
		"The turn's waiting build orders are paid before the auction clears, so "
		+ "bids may spend only what they leave (wiki: world-market § Treasury "
		+ "budget for bids)."
	)
	return line
