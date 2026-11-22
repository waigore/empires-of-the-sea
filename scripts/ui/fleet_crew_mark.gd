class_name FleetCrewMark
extends RefCounted
## The passengers block's court mark (DR-20261122-21): the press the voyage pick
## names, as the block prints it. A boarding names the crew it would take aboard,
## a landing the coast and the ground it would put her ashore on. Every other
## step — a sail, a dock, a crossing — names no press here, so it marks none
## (REQ-P2-03).
##
## Pure reads over the pick and the block's rows: the block reads one mark per
## render and asks these helpers, so a new step that names a press lands once.


## The press the pick names, as the block prints it: `{kind, unit}` for a
## boarding, `{kind, province, crew, tile}` for a landing, and `{}` when the pick
## names no press this block prints.
static func read(pick: Dictionary) -> Dictionary:
	var kind: String = String(pick.get("kind", ""))
	if kind == MapPlayVoyagePick.KIND_EMBARK:
		var unit: int = int(pick.get("unit", -1))
		return {"kind": kind, "unit": unit} if unit >= 0 else {}
	if kind != MapPlayVoyagePick.KIND_LAND:
		return {}
	var crew: String = String(pick.get("crew", ""))
	if crew.is_empty():
		return {}
	return {
		"kind": kind,
		"province": int(pick.get("province", -1)),
		"crew": crew,
		"tile": pick.get("tile", CivilianState.NO_TILE),
	}


## Whether this embark row is the crew the line would take aboard.
static func marks_embark(mark: Dictionary, row: Dictionary) -> bool:
	return String(mark.get("kind", "")) == MapPlayVoyagePick.KIND_EMBARK \
		and int(mark.get("unit", -1)) == int(row.get("id", -2))


## Whether this coast is the one the line would put the crew ashore on.
static func marks_coast(mark: Dictionary, province: int, crew: String) -> bool:
	return String(mark.get("kind", "")) == MapPlayVoyagePick.KIND_LAND \
		and int(mark.get("province", -1)) == province \
		and String(mark.get("crew", "")) == crew


## Whether this ground is the tile the line would land on.
static func marks_ground(mark: Dictionary, x: int, y: int) -> bool:
	return String(mark.get("kind", "")) == MapPlayVoyagePick.KIND_LAND \
		and mark.get("tile", CivilianState.NO_TILE) == Vector2i(x, y)
