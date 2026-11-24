class_name HudTreasuryTooltip
extends RefCounted
## The treasury plaque's spoken tip: phases alone on the label, then what
## settles after them, and a wider purse move when the closed turn beat the
## figure the bar promised (wiki: world-market § Trade orders; REQ-P3-01,
## REQ-P5-05). Pure copy — the binder owns the chip and calls this to paint it.

## Full tip for the plaque: balance, per-turn phases figure, after-phases clause,
## optional last-turn move, and the ledger door.
static func text(
	treasury: int,
	income: int,
	staged_orders: int,
	clearing: int,
	moved_known: bool,
	moved_wider: bool,
	purse_moved: int,
) -> String:
	var tip: String = "Treasury %s ducats%s · %s per turn from the phases" % [
		TextFormat.thousands(treasury),
		" (in debt)" if treasury < 0 else "",
		TextFormat.delta(income),
	]
	tip += after_phases_clause(staged_orders, clearing)
	if moved_known and moved_wider:
		tip += " · last turn the purse moved %s" % MoneyText.signed(purse_moved)
	return tip + " — open the ledger"


## The one clause naming what the label leaves out: the staged orders and the
## last clearing, in the ledger's own voice.
static func after_phases_clause(staged_orders: int, clearing_value: int) -> String:
	var orders: String = ""
	if staged_orders > 0:
		orders = "%d staged order%s" % [
			staged_orders, "" if staged_orders == 1 else "s",
		]
	var clearing: String = ""
	if clearing_value != 0:
		clearing = "the last clearing (%s)" % MoneyText.signed(clearing_value)
	if orders.is_empty() and clearing.is_empty():
		return "; nothing is staged for the auction after them"
	var subject: String = orders if clearing.is_empty() else clearing
	var settling: int = (1 if not clearing.is_empty() else 0)
	if not orders.is_empty():
		settling += staged_orders
		if not clearing.is_empty():
			subject = orders + " and " + clearing
	# "1 staged order moves", "3 staged orders move", "a and b move".
	return "; %s %s the purse after the phases" % [subject, "move" if settling > 1 else "moves"]
