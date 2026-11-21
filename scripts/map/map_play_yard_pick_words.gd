class_name MapPlayYardPickWords
extends RefCounted
## How the yard's pick is worded (wiki: ships-and-naval § Ship build economy,
## treasury-planner § Priority; DR-20261121-02): the hull the court would lay, in
## the catalogue's own name and the yard row's own price line; or the hull it is
## saving for, with the study that opens her, the purse that is filling, or the
## yard's own word for the stores and the hand she waits on. A reading, never an
## order (REQ-P2-03, REQ-P5-06).

## The hull the yard would lay down, priced exactly as her own row prints her: the
## catalog's treasury row, her materials and the peasant she takes
## (`ShipEconomy.cost_text`; DR-20261117-15).
static func lay_line(type_id: String) -> String:
	return "the court would lay a %s — %s" % [
		ShipStats.display_name(type_id), ShipEconomy.cost_text(type_id)
	]

## The hull the court means to lay while the purse fills: what the yard will take
## for her against the coin in hand, so the shortfall reads as a figure and never
## as a silence (REQ-P5-05).
static func saving_line(type_id: String, price: int, held: int) -> String:
	return "the court is saving for a %s — the purse holds %s of %s" % [
		ShipStats.display_name(type_id), MoneyText.ducats(maxi(held, 0)),
		MoneyText.ducats(maxi(price, 0)),
	]

## The hull the court means to lay, and the study the yard waits on: the same
## door the college's own pick names (wiki: tech-tree § Research model;
## DR-20261121-01), so a crown reads one chain on both sheets.
static func study_line(type_id: String, study_id: String) -> String:
	return "the court is saving for a %s — the study %s opens her" % [
		ShipStats.display_name(type_id), TechCatalog.display_name(study_id)
	]

## The hull the court means to lay while the purse already covers her row: the
## yard's own refusal is the gate, in the yard's own words (`Insufficient
## materials`, `Insufficient workers`), so the slip never tells a funded court it
## is saving (wiki: ships-and-naval § Ship build economy; DR-20261121-02).
static func gate_line(type_id: String, reason: String) -> String:
	if reason.is_empty():
		return ""
	return "the court would lay a %s — the yard cannot: %s" % [
		ShipStats.display_name(type_id), reason
	]
