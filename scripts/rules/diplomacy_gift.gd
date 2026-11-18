class_name DiplomacyGift
extends RefCounted
## The court's gift: the sum one Grant Aid order carries. The rules publish a
## step and a floor — "a positive multiple of £1000 (minimum £1000)" — and never
## a menu of legal amounts (wiki: diplomacy § Diplomatic Order Types — Grant Aid,
## § Amount parameters), while `DiplomacyAid.can_grant_aid` already validates any
## amount inside those rules and the purse. This reading turns that parameter
## into the £1,000 steps the court's sheet offers, so a crown sends one gift of
## the sum it chose instead of the same £1,000 every press (REQ-P2-02, REQ-P5-02).
##
## Pure: it steps a number against the treasury it is handed and prints the same
## sentence the gift's rules carry. Nothing here spends, stages or saves
## (REQ-P3-03).


## The step and the floor are the catalogue's own £1,000, so a step can never
## propose an amount the validator would refuse on its amount.
static func step() -> int:
	return maxi(DiplomacyCatalog.GRANT_AID_STEP, 1)


## The largest gift whole steps can carry out of `treasury` — 0 when the purse
## cannot cover the floor, so a ceiling the rules would refuse is never offered.
static func ceiling(treasury: int) -> int:
	var unit: int = step()
	return (maxi(treasury, 0) / unit) * unit


## The amount one step up (`direction` 1) or down (−1) from `amount`, kept inside
## the published floor and the purse's own ceiling. `direction` 0 only clamps,
## which is what a redraw does to a sum a spent treasury has left unaffordable.
static func stepped(amount: int, direction: int, treasury: int) -> int:
	var unit: int = step()
	var top: int = maxi(ceiling(treasury), unit)
	var next: int = amount + unit * direction
	if next < unit:
		next = unit
	if next > top:
		next = top
	return next


## One gift's face on the sheet: the sum the press will send.
static func face(amount: int) -> String:
	return "Grant Aid · %s" % DiplomacyCatalog.money(amount)


## What the sum does and does not buy. The relation a gift earns is fixed and
## does not grow with the £ amount, and the numeric modifier is never printed
## (wiki: diplomacy § GP–Minor Rules — Foreign aid), so a crown reads that a
## larger gift is generosity, not leverage (REQ-P5-05).
static func pledge() -> String:
	return (
		"The regard a gift earns is fixed, whatever the sum — a court that would "
		+ "be courted further must give again."
	)
