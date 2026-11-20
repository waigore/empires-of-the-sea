class_name MapPlayMusterPickWords
extends RefCounted
## How the drill yard's pick is worded (wiki: military-armies § Home Army,
## ai-architecture § Land reinforcement; DR-20261121-03): the line the court would
## muster, in the catalogue's own name and the muster row's own price; the line it
## is saving for and the gate that holds it; the target it already stands at; or
## the recall a moved seat waits on. A reading, never an order (REQ-P2-03,
## REQ-P5-06).


## The pick's own sentence, opened like one: one capital and a full stop.
static func sentence(text: String) -> String:
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


## The line the yard would raise, priced exactly as her own row prints her: the
## catalogue's treasury row, her materials and the hand she takes
## (`RegimentEconomy.cost_text`; DR-20261117-15).
static func muster_line(type_id: String) -> String:
	return "the court would muster %s — %s" % [
		RegimentCatalog.display_name(type_id), RegimentEconomy.cost_text(type_id)
	]


## The court already stands at its target strength: no regiment is due, so the
## yard reads the line it holds against the line it is arming for.
static func target_line(own: int, target: int) -> String:
	if target <= 0:
		return ""
	return "the court stands at its muster target — %d of %d regiments" % [
		clampi(own, 0, target), target
	]


## A seat that moved musters nowhere until the Home Army is recalled there: the
## order the muster pass takes first (issue #474;
## `AiArmyReinforce.recall_target`).
static func recall_line(model: MapModel, capital: int) -> String:
	if model == null or capital < 0:
		return ""
	return "the court must recall its Home Army to %s before it musters" % (
		model.province_name(capital)
	)


## The pattern the yard is saving for, against the coin in hand, so the shortfall
## reads as a figure and never as a silence (REQ-P5-05).
static func purse_line(type_id: String, price: int, held: int) -> String:
	return "the court is saving for %s — the purse holds %s of %s" % [
		RegimentCatalog.display_name(type_id), MoneyText.ducats(maxi(held, 0)),
		MoneyText.ducats(maxi(price, 0)),
	]


## The materials the pattern is short of, in the catalogue's own commodity names,
## read off the same `RegimentEconomy.missing_inputs` the muster row's gate reads.
static func stores_line(type_id: String, missing: Dictionary) -> String:
	if missing.is_empty():
		return ""
	var ids: Array[String] = []
	for raw: Variant in missing.keys():
		ids.append(String(raw))
	ids.sort()
	var parts: PackedStringArray = []
	for id: String in ids:
		parts.append("%d %s" % [int(missing[id]), CommodityCatalog.label(id)])
	return "the court is saving for %s — it lacks %s" % [
		RegimentCatalog.display_name(type_id), ", ".join(parts)
	]


## A gate the planner itself names — the larder, the harvest, the hull's bank —
## so the yard never goes quiet on a court that can arm nobody (REQ-P5-05).
static func gate_line(why: String) -> String:
	match why:
		AiArmyReinforce.REASON_LABOUR:
			return "the court would muster nothing — its fields cannot spare another hand"
		AiArmyReinforce.REASON_STARVING:
			return "the court would muster nothing — its people strike for food"
		AiArmyReinforce.REASON_HARVEST:
			return "the court would muster nothing — its harvest cannot carry one more ration"
		AiArmyReinforce.REASON_HULL:
			return "the court would muster nothing — its purse is banked for a hull"
	return ""
