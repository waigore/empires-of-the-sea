class_name InvasionBar
extends RefCounted
## Why a march into another faction's land stands or falls, as one reading: `ok`
## and one cause. The march's refusal and the province sheet both ask it, so a
## surface can never name a bar the rules do not hold (wiki: factions § Tribe —
## "unless another GP has invested in the province"; diplomacy § GP–Minor Rules
## § Intervention; REQ-P2-03).
##
## [DiplomacyRules.invadable] is this read's `ok`, so order legality and the
## words that explain it come from one place.

## The four causes: that is already the crown's land, no declaration is needed,
## a declaration is the bar, or another crown's bought land is the stake.
const OWN: String = "own"
const OPEN: String = "open"
const PEACE: String = "peace"
const DEED: String = "deed"


## `deeds` carries the holders and their tiles on the `deed` row only, so the
## refusal can name what raised the bar instead of blaming peace.
static func read(
	state: DiplomacyState, attacker: int, target: int,
	model: MapModel = null, province: int = -1
) -> Dictionary:
	if attacker == target:
		return {"ok": false, "cause": OWN, "deeds": {}}
	var tribe: bool = FactionCatalog.type_of(target) == FactionCatalog.Type.TRIBE
	var at_war: bool = DiplomacyRules.at_war_with(state, attacker, target)
	if not tribe:
		if at_war:
			return {"ok": true, "cause": OPEN, "deeds": {}}
		return {"ok": false, "cause": PEACE, "deeds": {}}
	var deeds: Dictionary = DeedProtection.province_holders(model, province, attacker)
	if at_war:
		return {"ok": true, "cause": OPEN, "deeds": deeds}
	if not deeds.is_empty():
		return {"ok": false, "cause": DEED, "deeds": deeds}
	return {"ok": true, "cause": OPEN, "deeds": {}}