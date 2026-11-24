class_name AttackPriceRead
extends RefCounted
## The crown's land-battle price in the rules' own figures (wiki:
## tech-tree-military § Economy modifiers; DR-20261124-11).
##
## Every land battle a Great Power attacks charges a treasury price before its
## outcome — 100 ducats per attacker per battle context, cut by Industrial
## Machinery (×0.75) and Modern Military Funding (×0.85) — and the dossier the
## crown orders her standards from named none of it: she learned what three
## storms cost from the turn's despatches, after the ducats had gone.
##
## A reading only: `ArmyAttackCost` owns the price and the factors, and nothing
## here charges, discounts or fights (REQ-P2-03, REQ-P3-03).

## The two studies that cut the price, for the tip's own worked figure.
const BOTH_FACTORS: Dictionary = {
	"industrial_machinery": true,
	"modern_military_funding": true,
}


## The ducats one land battle charges, off the court's own studies.
static func price(unlocked: Dictionary) -> int:
	return ArmyAttackCost.cost(unlocked)


## One dossier line: what the next land battle costs, and the studies that have
## cut the published base. Empty of studies, the line names the base alone.
static func line(unlocked: Dictionary) -> String:
	var due: int = price(unlocked)
	var cut: Array[String] = _cutting(unlocked)
	if cut.is_empty():
		return "Battles · each land battle costs %d ducats" % due
	var verb: String = "cuts" if cut.size() == 1 else "cut"
	return "Battles · each land battle costs %d ducats — %s %s the %d" % [
		due, _joined(cut), verb, ArmyAttackCost.BASE
	]


## The rule behind the row, for the row's own tip: the base, both factors, the
## floor and the walk-in that pays nothing (REQ-P5-03 — a phone keeps no hover,
## so the line stands on its own words above).
static func tip(unlocked: Dictionary) -> String:
	return (
		"Every land battle the crown attacks charges this price once, before "
		+ "its outcome, from her own treasury: %d ducats per attacker, cut by "
		+ "Industrial Machinery ×0.75 and Modern Military Funding ×0.85 (both "
		+ "together %d) and floored at zero, so a thin purse still fights. An "
		+ "unopposed walk-in over open ground fights no battle and pays nothing "
		+ "(wiki: tech-tree-military § Economy modifiers)."
	) % [price(unlocked), price(BOTH_FACTORS)]


## The studies the court holds that cut the price, by their catalogue names.
static func _cutting(unlocked: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for tech_id: Variant in ArmyAttackCost.TECH_FACTORS.keys():
		if bool(unlocked.get(String(tech_id), false)):
			names.append(TechCatalog.display_name(String(tech_id)))
	return names


## `<a> and <b>` — one name alone keeps no conjunction.
static func _joined(names: Array[String]) -> String:
	if names.is_empty():
		return ""
	if names.size() == 1:
		return names[0]
	var head: PackedStringArray = PackedStringArray(names.slice(0, names.size() - 1))
	return "%s and %s" % [", ".join(head), names[names.size() - 1]]
