class_name CivilianExplorerGates
extends RefCounted
## Gates checked before an Explorer's field work (wiki: civilian-units
## § Work Order Summary, Refs #3753 R4; fog-and-exploration § Order Visibility,
## § Prospecting; DR-20261111-26). Pure rules: one refusal string ("" when the
## work may start) shared by the work-order validator, the dossier and the AI
## planners (REQ-P3-03).


## Empty string when the province survey may start; otherwise the first refusal.
## The "already charted" test stays with the work order, which knows the target.
static func explore_refusal(
	model: MapModel, owner: int, province: int, context: Dictionary
) -> String:
	return consulate_refusal(model, owner, province, context)


## Empty string when the Explorer may survey this tile now. Prospect is the
## Explorer's one-turn uncover of charted, prospectable ground in the province it
## stands in — an empty survey is legal, and a tile whose resource already shows
## is never a survey target (wiki: fog-and-exploration § Prospecting).
static func prospect_refusal(
	model: MapModel,
	owner: int,
	unit_tile: Vector2i,
	tile: Vector2i,
	works: LandWorks,
	visibility: VisibilityModel,
	context: Dictionary
) -> String:
	var ground: String = MineralSurvey.refusal(model, works, owner, tile, visibility)
	if not ground.is_empty():
		return ground
	var province: int = model.province_at(tile.x, tile.y)
	if model.province_at(unit_tile.x, unit_tile.y) != province:
		return "An Explorer surveys the province it stands in — march closer first."
	return consulate_refusal(model, owner, province, context)


## Exploring or prospecting inside a Minor Nation or Tribe province needs a
## Consulate (or higher) with its owner. Without a court in `context` the gate
## is inert, so isolated rules fixtures can still exercise the work itself.
## Public because the map's survey marks and the Explorer's dossier must offer
## only the ground this court may actually read (REQ-P2-03).
static func consulate_refusal(
	model: MapModel, owner: int, province: int, context: Dictionary
) -> String:
	var owner_id: int = model.province_owner(province)
	if owner_id == MapModel.NO_ID or owner_id == owner:
		return ""
	var kind: int = FactionCatalog.type_of(owner_id)
	if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
		return ""
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	if diplomacy == null or DiplomacyRules.has_consulate(diplomacy, owner, owner_id):
		return ""
	return "Establish a consulate before exploring or prospecting"
