class_name CivilianPanelStatus
extends RefCounted
## A civilian dossier's two lines above the orders: what the crew is doing now
## and, for a crew of the reading court that waits, the pick its own planner
## would give it next (REQ-P3-01, REQ-P3-03; REQ-P5-06, DR-20261117-06). A
## reading only — nothing here assigns, reserves or spends.

## How the sheet words the pick's own name: one capital to open the sentence and
## a full stop to close it, whatever ledger worded it.
static func sentence(text: String) -> String:
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


## The court's own pick for a crew that waits: the work the published planner
## would give it next, worded by the ledger that sells the work (REQ-P5-06;
## DR-20261117-06). Empty when the sheet carries no pick.
static func pick_line(context: Dictionary) -> String:
	var pick: Dictionary = context.get("pick", {}) as Dictionary
	return sentence(String(pick.get("line", "")))


## A rival's crew answers to its own crown: the sheet says so with the same
## words the fleet and army dossiers use, so no control is offered that the rules
## would refuse (REQ-P2-03, REQ-P5-06). `legal` is how many orders the sheet can
## press here; when every row is refused the status must say so, rather than
## pointing the crown at a list it cannot use (REQ-P5-06). Pass a negative value
## when the caller has not counted yet.
static func text(
	model: MapModel, unit: CivilianState, viewer: int, legal: int = -1
) -> String:
	if viewer != unit.owner:
		return "Enemy colours · no orders"
	if not unit.is_working():
		if unit.type_id == SpyNetworks.SPY_TYPE:
			return _spy(model, unit)
		# Every row below is refused: the sheet must not send the crown down a
		# list it cannot press (REQ-P5-06).
		if legal == 0:
			return "Idle — no order can be taken here."
		return "Idle — choose an order below."
	if unit.work_action() == SpyRules.WORK_COUNTER:
		return "Counter-espionage · ongoing."
	return "%s · %d turn%s left." % [
		CivilianWork.label(unit.work_action()),
		unit.remaining_turns(),
		MoneyText.plural(unit.remaining_turns()),
	]


## An idle spy is unseen and unscreened: the line says where its trade pays, so
## a court that shares nothing is never sent there twice.
static func _spy(model: MapModel, unit: CivilianState) -> String:
	var host: int = model.owner_at(unit.tile.x, unit.tile.y)
	if host == MapModel.NO_ID or host == unit.owner:
		return (
			"At large — post it on a rival Great Power's land, or keep it home as a screen."
		)
	var host_name: String = FactionCatalog.name_of(host)
	if FactionCatalog.type_of(host) == FactionCatalog.Type.GREAT_POWER:
		return "At large — shadowing %s: presence reveal and a research share." % host_name
	return "At large — shadowing %s: presence reveal only, no research share." % host_name