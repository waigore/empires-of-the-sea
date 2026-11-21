class_name MapPlayVoyagePickWords
extends RefCounted
## How one voyage pick is worded (wiki: civilian-units § Overseas deployment;
## DR-20261121-08): the step the court's own colonisation pass would take with a
## squadron, in the rule book's own names — the crew it boards, the harbour it
## musters at, the water it sails, the Passage it crosses, the ground it lands
## on. A reading, never an order; every figure is one the planner decided on.

## The step that takes a colonist aboard at the crown's harbour.
const KIND_EMBARK: String = "embark"
## The step that sails her one leg: toward the harbour, or toward the Passage.
const KIND_SAIL: String = "sail"
## The step that docks her at the harbour the voyage musters at.
const KIND_DOCK: String = "dock"
## The step that carries her and her passenger through a Passage.
const KIND_CROSS: String = "cross"
## The step that puts the colonist ashore on a charted coast.
const KIND_LAND: String = "land"

## One step, worded for the crown's block. Empty when the step names nothing this
## module can say (an unknown kind, or a chart with no such water or province).
static func line(model: MapModel, data: Dictionary) -> String:
	if model == null or data.is_empty():
		return ""
	match String(data.get("kind", "")):
		KIND_EMBARK:
			return _embark(model, data)
		KIND_SAIL:
			return _sail(model, data)
		KIND_DOCK:
			return _dock(model, data)
		KIND_CROSS:
			return _cross(data)
		KIND_LAND:
			return _land(data)
	return ""

## The boarding: the crew the plan names, at the harbour she musters at. The
## step names the crew and the squadron; the harbour is the one the plan boards
## at, so a step that carries no province reads the harbour's own.
static func _embark(model: MapModel, data: Dictionary) -> String:
	var crew: String = _crew(data)
	var port: int = _port(data)
	if crew.is_empty() or port == MapModel.NO_ID:
		return ""
	return "the court would take %s aboard at %s" % [crew, model.province_name(port)]

## The province a step stands at: its own when it names one (a dock), the
## harbour the voyage musters at when it does not (a boarding).
static func _port(data: Dictionary) -> int:
	var port: int = int(data.get("province", MapModel.NO_ID))
	if port != MapModel.NO_ID:
		return port
	return int(data.get("harbour", MapModel.NO_ID))

## One leg of the voyage: a squadron carrying a colonist sails for the Passage,
## a free one for the harbour where the voyage musters (wiki: civilian-units
## § Overseas deployment).
static func _sail(model: MapModel, data: Dictionary) -> String:
	var zone: int = int(data.get("zone", MapModel.NO_ID))
	if zone == MapModel.NO_ID:
		return ""
	if bool(data.get("carrying", false)):
		return "the court would sail her for the %s — the first leg to the Passage" % (
			model.sea_zone_name(zone)
		)
	var port: int = int(data.get("harbour", MapModel.NO_ID))
	if port == MapModel.NO_ID:
		return "the court would sail her for the %s — the first leg of the voyage" % (
			model.sea_zone_name(zone)
		)
	return "the court would sail her for the %s — the first leg to %s, where the voyage musters" % [
		model.sea_zone_name(zone), model.province_name(port)
	]

## The harbour leg: she docks where the colonist musters, so the boarding is one
## press away.
static func _dock(model: MapModel, data: Dictionary) -> String:
	var port: int = int(data.get("province", MapModel.NO_ID))
	if port == MapModel.NO_ID:
		return ""
	return "the court would dock her at %s — the harbour the voyage musters at" % (
		model.province_name(port)
	)

## The crossing: the Passage carries the squadron and her passenger together.
static func _cross(data: Dictionary) -> String:
	var crew: String = _crew(data)
	if crew.is_empty():
		return "the court would cross the Passage with her colonist aboard"
	return "the court would cross the Passage with %s aboard" % crew

## The landing: the ground the plan picked, with what the crown can read of it —
## the terrain and the commodity an estate there would work.
static func _land(data: Dictionary) -> String:
	var crew: String = _crew(data)
	var tile: Vector2i = data.get("tile", CivilianState.NO_TILE)
	if crew.is_empty() or tile.x < 0:
		return ""
	var ground: String = String(data.get("ground", ""))
	var where: String = "(%d, %d)" % [tile.x, tile.y]
	if ground.is_empty():
		return "the court would put %s ashore at %s" % [crew, where]
	return "the court would put %s ashore at %s — %s" % [crew, where, ground]

## The crew with its article: "an Explorer", "a Builder". A step that names no
## crew (a hull sailing before the boarding) prints nothing rather than a label.
static func _crew(data: Dictionary) -> String:
	var type_id: String = String(data.get("crew", ""))
	if type_id.is_empty() or not CivilianCatalog.known(type_id):
		return ""
	var name: String = CivilianCatalog.display_name(type_id)
	if name.is_empty():
		return ""
	return "%s %s" % ["an" if _vowel(name) else "a", name]

static func _vowel(word: String) -> bool:
	if word.is_empty():
		return false
	return "aeiouAEIOU".contains(word.substr(0, 1))
