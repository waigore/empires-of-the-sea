class_name WallRead
extends RefCounted
## The wall's own numbers in one home (wiki: siege-mechanics § Wall Protection;
## DR-20261120-06). A crown that reads a province, or marches on one, is told
## what the wall soaks and what it spares — the two figures the exchange itself
## reads (`FortRules.wall_soak`, `FortRules.loss_scale`) — so a plan is made
## against the same wall the battle will fight (REQ-P2-03, REQ-P5-05).
##
## A reading only: no level, gun, gate or battle outcome lives here. The fort
## table owns every number; this module owns the words a surface prints.

## The wall's clause for a province sheet: `10 wall hp · 25% off a blow`. Empty
## on open ground, so a caller leaves the row out rather than printing a zero.
static func line(level: int) -> String:
	var fort: int = FortRules.clamp_level(level)
	if not FortRules.is_siege(fort):
		return ""
	return "%d wall hp · %d%% off a blow" % [
		roundi(FortRules.wall_hp(fort)),
		roundi(damage_share(fort) * 100.0),
	]


## The share of a blow a wall spares the garrison (25/45/60%), read from the
## exchange's own loss scale so the words cannot drift from the casualty band.
static func damage_share(level: int) -> float:
	return 1.0 - FortRules.loss_scale(FortRules.clamp_level(level))


## The receipt a march into another court's walled province reads in place of the
## plain one: the wall that stands there, in the fort table's own numbers. Empty
## on open ground, and for a wall the crown already holds — a march into its own
## land names no siege.
static func march_line(province_name: String, level: int) -> String:
	if line(level).is_empty():
		return ""
	var fort: int = FortRules.clamp_level(level)
	var pieces: int = FortRules.guns(fort)
	return "The army marches on %s — a %s fort stands: %d wall hp, %d emplaced gun%s, %d%% off a blow." % [
		province_name,
		FortRules.level_name(fort).to_lower(),
		roundi(FortRules.wall_hp(fort)),
		pieces,
		"" if pieces == 1 else "s",
		roundi(damage_share(fort) * 100.0),
	]
