class_name MapPlayYardPickWords
extends RefCounted
## How the yard's pick is worded (wiki: ships-and-naval § Ship build economy,
## treasury-planner § Priority; DR-20261121-02): the hull the court would lay, in
## the catalogue's own name and the yard row's own price line; or the hull it is
## saving for, with the study that opens her or the purse that is filling. A
## reading, never an order (REQ-P2-03, REQ-P5-06).


## The pick's own sentence, opened like one: one capital and a full stop.
static func sentence(text: String) -> String:
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


## The hull the yard would lay down, priced exactly as her own row prints her: the
## catalog's treasury row, her materials and the peasant she takes. Empty when the
## catalogue has no name for her, so the sheet can never print an id.
static func lay_line(type_id: String) -> String:
	var name: String = ShipStats.display_name(type_id)
	if name.strip_edges().is_empty():
		return ""
	return "the court would lay a %s — %s" % [name, ShipEconomy.cost_text(type_id)]


## The hull the court means to lay while the purse fills: what the yard will take
## for her against the coin in hand, so the shortfall reads as a figure and never
## as a silence (REQ-P5-05).
static func saving_line(type_id: String, price: int, held: int) -> String:
	var name: String = ShipStats.display_name(type_id)
	if name.strip_edges().is_empty():
		return ""
	return "the court is saving for a %s — the purse holds %s of %s" % [
		name, MoneyText.ducats(maxi(held, 0)), MoneyText.ducats(maxi(price, 0))
	]


## The hull the court means to lay, and the study the yard waits on: the same
## door the college's own pick names (wiki: tech-tree § Research model;
## DR-20261121-01), so a crown reads one chain on both sheets.
static func study_line(type_id: String, study_id: String) -> String:
	var name: String = ShipStats.display_name(type_id)
	var study: String = TechCatalog.display_name(study_id)
	if name.strip_edges().is_empty() or study.strip_edges().is_empty():
		return ""
	return "the court is saving for a %s — the study %s opens her" % [name, study]
