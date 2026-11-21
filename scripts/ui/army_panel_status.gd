class_name ArmyPanelStatus
extends RefCounted
## Status and hint lines for the army dossier: what the standard is doing now
## and what the crown may press next. A reading only — nothing here marches or
## spends (REQ-P3-01, REQ-P3-03; wiki: military-armies § Movement and attacks).


## `Palermo — England's ground`, or the wilderness word when nobody holds it; a
## court's own land adds nothing, so the line is unchanged where it always was.
static func ground_note(model: MapModel, army: ArmyState) -> String:
	var holder: int = model.province_owner(army.province)
	if holder == army.owner:
		return ""
	if holder == MapModel.NO_ID:
		return " — unclaimed ground"
	var name: String = FactionCatalog.name_of(holder)
	# "United Provinces' ground", "Spain's ground": a name already ending in s
	# takes the bare mark.
	return " — %s%s ground" % [name, "'" if name.ends_with("s") else "'s"]


## One line for the gold status row: enemy, embarked, home, marched, or free.
static func status_text(army: ArmyState, is_player: bool) -> String:
	if not is_player:
		return "Enemy colours · no orders"
	if army.is_embarked():
		return "Aboard the fleet"
	if army.home:
		return "Home Army · never leaves the capital"
	if army.moved:
		return "Has marched this turn"
	return "1 march this turn"


## Hint under the status: a host standing off its own ground gets the walk-home
## word from #1218 — never own land the tap list does not hold — and one that does
## touch its own land still hears that only the provinces beside it are open
## (wiki: military-armies § Movement and attacks; DR-20261121-15).
static func hint_text(
	army: ArmyState, is_player: bool, stranded: bool, off_ground: bool = false
) -> String:
	if not is_player:
		return "Observe only. Orders require your own army."
	if army.is_embarked():
		return "The squadron carries the army; land on an owned coast."
	if army.home:
		return "Detach a regiment to form a field army, then march it."
	if army.moved:
		return "End the turn to march again."
	if stranded:
		return (
			"No own land touches here; walk through the provinces beside you, "
			+ "one march at a time, to reach home."
		)
	if off_ground:
		return (
			"Tap a highlighted province; off your own ground only the provinces "
			+ "beside you are open."
		)
	return (
		"Tap a highlighted province; your own land is open, enemy land must "
		+ "border you."
	)


## Writes both dossier lines from one opening.
static func apply(
	status: Label,
	hint: Label,
	army: ArmyState,
	is_player: bool,
	stranded: bool,
	off_ground: bool = false
) -> void:
	if status == null or hint == null:
		return
	status.text = status_text(army, is_player)
	hint.text = hint_text(army, is_player, stranded, off_ground)
