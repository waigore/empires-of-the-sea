class_name InvasionBar
extends RefCounted
## Why a march into another faction's land stands or falls, as one reading: `ok`
## and one cause. The march's refusal and the province sheet both ask it, so a
## surface can never name a bar the rules do not hold (wiki: diplomacy § War
## required for hostile actions; REQ-P2-03).
##
## Every foreign owner is read alike — Great Power, Minor Nation and Tribe — so a
## newly contacted Tribe at peace is no invasion, and no deed raises a bar the
## declaration does not already hold.
##
## [DiplomacyRules.invadable] is this read's `ok`, so order legality and the
## words that explain it come from one place.

## The three causes: that is already the crown's land, the declaration is held,
## or the declaration is the bar.
const OWN: String = "own"
const OPEN: String = "open"
const PEACE: String = "peace"


static func read(state: DiplomacyState, attacker: int, target: int) -> Dictionary:
	if attacker == target:
		return {"ok": false, "cause": OWN}
	if DiplomacyRules.at_war_with(state, attacker, target):
		return {"ok": true, "cause": OPEN}
	return {"ok": false, "cause": PEACE}
