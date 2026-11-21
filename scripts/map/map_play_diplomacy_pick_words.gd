class_name MapPlayDiplomacyPickWords
extends RefCounted
## How the court's own envoy pick is worded (wiki: diplomacy § GP AI policy for
## war vs. relations, diplomacy-planner; DR-20261121-05): the one order the
## court's planner would spend this turn, said to one crown; the crown the order
## goes to instead; or the gate that holds the envoy when it goes nowhere. Every
## order kind the planner can emit has a sentence here, so a new kind fails the
## wording test instead of printing silence (REQ-P5-05). A reading, never an
## order (REQ-P2-03, REQ-P5-06).

## The pick's own sentence, opened like one: one capital and a full stop.
static func sentence(text: String) -> String:
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


## The order the envoy would spend on this crown, in the order catalogue's own
## kinds; "" for a kind the planner never emits.
static func order_line(kind: String, target: int, action: Dictionary) -> String:
	var name: String = FactionCatalog.name_of(target)
	match kind:
		DiplomacyOrders.KIND_WAR:
			return "the court's envoy would declare war on %s" % name
		DiplomacyOrders.KIND_PEACE:
			return "the court's envoy would offer peace to %s" % name
		DiplomacyOrders.KIND_ALLIANCE:
			return "the court's envoy would offer %s an alliance" % name
		DiplomacyOrders.KIND_OVERTURE:
			return _overture_line(name, String(action.get("stage", "")))
		DiplomacyOrders.KIND_FTP:
			return "the court's envoy would propose a trade pact to %s" % name
		DiplomacyOrders.KIND_REVOKE_FTP:
			return "the court's envoy would revoke the trade pact with %s" % name
		DiplomacyOrders.KIND_BOYCOTT:
			return "the court's envoy would boycott %s's trade" % name
		DiplomacyOrders.KIND_REVOKE_BOYCOTT:
			return "the court's envoy would lift the boycott on %s" % name
		DiplomacyOrders.KIND_AID:
			return _aid_line(name, int(action.get("amount", 0)))
		DiplomacyOrders.KIND_SUBSIDY:
			return "the court's envoy would set %s a subsidy" % name
		DiplomacyOrders.KIND_CANCEL_SUBSIDY:
			return "the court's envoy would cancel %s's subsidy" % name
		DiplomacyOrders.KIND_BREAK:
			return "the court's envoy would break the alliance with %s" % name
		DiplomacyOrders.KIND_BREAK_NAP:
			return "the court's envoy would break the pact with %s" % name
	return ""


## The envoy's one order is spoken for: this crown hears nothing this turn, and
## the sheet says where the order went instead (the crown's own staff, so no
## rival's business is named) (REQ-P5-05).
static func elsewhere_line(target: int, other: int) -> String:
	if other < 0:
		return ""
	return "the court's one order goes to %s this turn — nothing for %s" % [
		FactionCatalog.name_of(other), FactionCatalog.name_of(target)
	]


## The envoy goes nowhere, and the gate the planner itself named is why; with no
## gate to name the line still says the envoy was weighed (REQ-P5-05).
static func hold_line(target: int, why: String) -> String:
	var name: String = FactionCatalog.name_of(target)
	var gate: String = gate_words(why)
	if gate.is_empty():
		return "the court's envoy would say nothing to %s this turn" % name
	return "the court's envoy would say nothing to %s — %s" % [name, gate]


## The planner's own gate words in the court's plain voice. An unknown reading
## passes through as it stands: the advice never invents a reason the planner
## did not give (REQ-P2-03).
static func gate_words(why: String) -> String:
	match why:
		"war still worth waging":
			return "the war is still worth waging"
		"war desire too low":
			return "the court has no quarrel to press"
		"relations too warm":
			return "the standing is too warm for war"
		"overstretched: no third front":
			return "the court is overstretched"
		"the pair's truce holds: no new war yet":
			return "the pair's truce holds"
		"war cooldown":
			return "the court is on its war cooldown"
		"an envoy chain has a claim on that court":
			return "an envoy chain has a claim on this court"
		"the court is already considering a proposal":
			return "the court is already weighing a proposal"
	if why.begins_with("peace cooldown"):
		return "the pair's peace offer is still cooling"
	return why


## The envoy chain's next rung, in the chain's own stage words
## (`DiplomacyCatalog.stage_label`): the rungs the planner can buy, each said
## the way the court says it (wiki: diplomacy § Overtures).
static func _overture_line(name: String, stage: String) -> String:
	match stage:
		DiplomacyCatalog.STAGE_CONSULATE:
			return "the court's envoy would open a Trade Consulate with %s" % name
		DiplomacyCatalog.STAGE_EMBASSY:
			return "the court's envoy would open an Embassy with %s" % name
		DiplomacyCatalog.STAGE_NAP:
			return "the court's envoy would offer %s a Non-Aggression Pact" % name
		DiplomacyCatalog.STAGE_JOIN_EMPIRE:
			return "the court's envoy would bring %s into the empire" % name
	return ""


## The gift the envoy would carry, in the published step the order catalogue
## prints beside it (wiki: diplomacy § Grant Aid).
static func _aid_line(name: String, amount: int) -> String:
	if amount <= 0:
		return ""
	return "the court's envoy would send %s %s" % [name, MoneyText.ducats(amount)]
