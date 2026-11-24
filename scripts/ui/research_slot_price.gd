class_name ResearchSlotPrice
extends RefCounted
## One research slot's priced reading, and the words the college prints for it
## (REQ-P3-02, REQ-P3-03). `ResearchQueueDesk` walks `ResearchWalk`; this holds
## what the walk said about one slot — the study, its preset, the gold and points
## it buys, whether the purse pays and where it stands — so a playtest can read a
## slot without walking widgets (REQ-P5-05).
##
## `ResearchSlotRow` paints from this reading alone: a funding change rewrites the
## row from a new price, and the row owns no arithmetic of its own.

## The study in the slot; "" means the slot is idle.
var tech: String = ""
var funding: String = ResearchFunding.DEFAULT
## Ducats the slot spends next turn and the points it buys at that preset.
var gold: int = 0
var rp: int = 0
## The study's full cost and the points already banked toward it.
var cost: int = 0
var progress: int = 0
## Spy-network percent lifting this study (DR-20261110-03).
var boost: int = 0
## False when the Research phase cannot pay this slot at its preset next turn.
var paid: bool = true
## The borrowing floor the purse prices against, named in an unpaid slot's tip.
var floor: int = 0


## The reading of one row of `ResearchWalk` — the same priced rows the heading
## and the Research phase total (REQ-P2-03). `floor` is the walk's borrowing
## floor, which the row never computes for itself.
static func from_priced(priced: Dictionary, floor: int = 0) -> ResearchSlotPrice:
	var out := ResearchSlotPrice.new()
	out.tech = String(priced.get("tech", ""))
	out.funding = String(priced.get("funding", ResearchFunding.DEFAULT))
	out.gold = int(priced.get("gold", 0))
	out.rp = int(priced.get("rp", 0))
	out.cost = int(priced.get("cost", 0))
	out.progress = int(priced.get("progress", 0))
	out.boost = int(priced.get("boost", 0))
	out.paid = bool(priced.get("paid", true))
	out.floor = floor
	return out


func is_idle() -> bool:
	return tech.is_empty()


## True when the slot spends nothing next turn — idle, or paid at None.
func silent() -> bool:
	return gold <= 0


## What the next Research phase adds to the study, never past its cost.
func lands() -> int:
	return maxi(mini(progress + rp, cost), 0)


## Turns the study still needs at this slot's own preset: the points left over
## the points the next phase buys, rounded up, so a slot that meets its cost in
## the coming phase reads one. Zero when the slot cannot promise — idle, a phase
## that cannot pay it, a preset that buys nothing, or a cost no catalogue prices
## (wiki: tech-tree § Research Model — the catalogue prices 6–12 turns at
## Medium, and a preset only moves that pace).
func turns_left() -> int:
	if is_idle() or not paid or rp <= 0 or cost <= 0:
		return 0
	return maxi(int(ceil(float(maxi(cost - progress, 0)) / float(rp))), 1)


## "3 turns" / "1 turn" — the wait a study still owes, in the raise ledger's own
## words (wiki: technology, [DR-20261124-01]).
func turns_text() -> String:
	if turns_left() <= 1:
		return "1 turn"
	return "%d turns" % turns_left()


## The line under the slot: what the next phase adds, where it leaves the study
## and the turns it still owes at that pace. An unpaid slot says so rather than
## promising points the phase cannot pay (wiki: tech-tree § Research Model — no
## partial funding), and an idle or unfunded slot names the rule rather than a
## gain (REQ-P5-05).
func next_text() -> String:
	if is_idle():
		return ""
	if not paid:
		return "unpaid next turn"
	if rp <= 0:
		return "earns nothing"
	if cost <= 0:
		return "+%s" % TextFormat.thousands(rp)
	var text: String = "+%s → %s" % [TextFormat.thousands(rp), TextFormat.thousands(lands())]
	if turns_left() > 0:
		text += " · %s left" % turns_text()
	return text


## Whether `next_text` reads as a warning, so the row paints it crimson.
func next_warns() -> bool:
	return not is_idle() and (not paid or rp <= 0)


## The rule behind `next_text`, so a crown that reads a crimson line can learn
## why — a hover alone would leave touch crowns guessing (REQ-P1-05).
func next_tip() -> String:
	if is_idle():
		return ""
	if not paid:
		return "The treasury cannot cover this slot next turn — %s." % (
			LedgerReportText.research_floor_line(floor)
		)
	if rp <= 0:
		return "No funding buys no research points."
	if cost <= 0:
		return "%s research points next turn." % TextFormat.thousands(rp)
	var tip: String = "%s research points next turn, %s of %s met" % [
		TextFormat.thousands(rp), TextFormat.thousands(lands()),
		TextFormat.thousands(cost),
	]
	if turns_left() > 0:
		tip += " — it meets the cost in %s at this preset" % turns_text()
	return tip


## What the gold buys here, for the spend line's tooltip.
func spend_tip() -> String:
	if silent():
		return "This slot buys no research points this turn"
	return "%s buys %s research points each turn" % [
		MoneyText.ducats(gold), TextFormat.thousands(rp),
	]


## The spy line's tooltip, or "" when no network lifts the study.
func boost_tip() -> String:
	if boost <= 0:
		return ""
	return (
		"Spy network: +%d%% research points from the rival courts it shadows"
		% boost
	)