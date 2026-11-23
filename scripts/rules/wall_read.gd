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

## The wall's clause for a province sheet, in the ladder's own figures:
## `40 wall hp · 10% off a blow` at a Wood fort, rising a level at a time, and the
## storm the wall sets when the caller hands one in (`storm_line`). Empty on open
## ground, so a caller leaves the row out rather than printing a zero.
static func line(level: int, storm: String = "") -> String:
	var fort: int = FortRules.clamp_level(level)
	if not FortRules.is_siege(fort):
		return ""
	var text: String = "%d wall hp · %d%% off a blow" % [
		roundi(FortRules.wall_hp(fort)),
		roundi(damage_share(fort) * 100.0),
	]
	if storm.is_empty():
		return text
	return "%s · %s" % [text, storm]


## The strength an empty walled province's storm must beat — the wall and its
## standing battery, `FortRules.storm_threshold`'s own figure (wiki:
## siege-mechanics § Storming an empty walled province). The crown's own ground
## reads her own battery exactly (`battery_known`); another court's studies are
## not hers to read, so her wall prints the published envelope instead — a royal
## battery to the heaviest any court can mount (`FortRules.storm_ceiling`).
## Empty on open ground, where no storm is fought.
static func storm_line(
	level: int, tech: Dictionary = {}, battery_known: bool = false
) -> String:
	var fort: int = FortRules.clamp_level(level)
	if not FortRules.is_siege(fort):
		return ""
	if battery_known:
		return "storm needs %d strength" % roundi(FortRules.storm_threshold(tech, fort))
	var light: int = roundi(FortRules.storm_threshold({}, fort))
	var heavy: int = roundi(FortRules.storm_ceiling(fort))
	if light >= heavy:
		return "storm needs %d strength" % heavy
	return "storm needs %d–%d strength" % [light, heavy]


## The rule behind the storm clause, for the row's own tip: what the figure
## means, and why another court's wall prints a range.
static func storm_tip(level: int, battery_known: bool = false) -> String:
	if not FortRules.is_siege(FortRules.clamp_level(level)):
		return ""
	var text: String = (
		"A storm of an empty wall must beat this strength to take the province,"
		+ " and every whole %d strength past it costs one regiment." % int(FortRules.STORM_STEP)
	)
	if battery_known:
		return text
	return text + " Another court's guns are not yours to read, so the range runs from her lightest battery to her heaviest."


## The share of a blow a wall spares the garrison (ten points a level), read
## from the exchange's own loss scale so the words cannot drift from the
## casualty band.
static func damage_share(level: int) -> float:
	return 1.0 - FortRules.loss_scale(FortRules.clamp_level(level))


## The receipt a march into another court's walled province reads in place of the
## plain one: the wall that stands there, in the fort table's own numbers, and the
## storm it would take when the caller hands one in (`storm_line`). The caller
## asks it for another court's land only, and an empty answer keeps the plain
## line — open ground names no siege.
static func march_line(province_name: String, level: int, storm: String = "") -> String:
	if line(level).is_empty():
		return ""
	var fort: int = FortRules.clamp_level(level)
	var pieces: int = FortRules.guns(fort)
	var text: String = "The army marches on %s — a %s fort stands: %d wall hp, %d emplaced gun%s, %d%% off a blow" % [
		province_name,
		FortRules.level_name(fort).to_lower(),
		roundi(FortRules.wall_hp(fort)),
		pieces,
		"" if pieces == 1 else "s",
		roundi(damage_share(fort) * 100.0),
	]
	if storm.is_empty():
		return text + "."
	return "%s · %s." % [text, storm]
