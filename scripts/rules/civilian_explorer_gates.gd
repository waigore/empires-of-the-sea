class_name CivilianExplorerGates
extends RefCounted
## Gates checked before an Explorer's field work (wiki: civilian-units
## § Work Order Summary, Refs #3753 R4; fog-and-exploration § Order Visibility).
## Pure rules: one refusal string ("" when the work may start) shared by the
## work-order validator and the dossier options (REQ-P3-03).


## Empty string when the work may start; otherwise the first refusal reason.
static func refusal(
	action: String,
	model: MapModel,
	owner: int,
	tile: Vector2i,
	province: int,
	visibility: VisibilityModel,
	context: Dictionary
) -> String:
	# Prospect is a deed, not a look: the tile must already be charted at fogged
	# or better (wiki: fog-and-exploration § Order Visibility Requirements).
	if action == "prospect" and visibility != null:
		if visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.UNKNOWN:
			return "Only charted land can be prospected."
	return _consulate_refusal(model, owner, province, context)


## Exploring or prospecting inside a Minor Nation or Tribe province needs a
## Consulate (or higher) with its owner. Without a court in `context` the gate
## is inert, so isolated rules fixtures can still exercise the work itself.
static func _consulate_refusal(
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