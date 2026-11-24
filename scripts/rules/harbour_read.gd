class_name HarbourRead
extends RefCounted
## The province sheet's **Port** row: whether a harbour is actually built on the
## water the quay faces, what it carries, and what the port order would bring a
## bare coast (wiki: extraction-and-improvements § Transport Level, § Overseas
## delivery; civilian-units § Work Order Summary; capital-and-connectivity
## § Blockade).
##
## The row used to name the water a province opens on and nothing else, so a
## coast with no port work standing on it read `Harbour · Mar Caribe` — the same
## words a finished harbour reads — while the ground carried none of the
## Transport 4 a harbour grants and an overseas network had no port to root it.
## One read for the
## sheet, the observatory and the tests, priced off the port order's own table
## and the transport constant the extraction formula uses, so no figure is a
## second copy (REQ-P2-03, REQ-P3-03).
##
## A reading only: no port is laid, no order filed and no save key moves.

const PORT_ACTION: String = "build_port"
const LANDLOCKED: String = "Landlocked"
## What a port leaves on the ground: the same level the extraction formula reads
## as `Transport 4` (wiki: extraction-and-improvements § Transport Level;
## `LandWorks.TRANSPORT_RAIL`).
const TRANSPORT: int = LandWorks.TRANSPORT_RAIL


## True when a harbour is built anywhere in the province — the work the docking,
## the colony crossing and the transport grant all read (`LandWorks.has_port`).
static func stands(model: MapModel, works: LandWorks, province: ProvinceState) -> bool:
	if model == null or works == null or province == null:
		return false
	return works.province_has_port(model, province.id)


## The row's one line. `works` and `blockade` may be null: a sheet with no seated
## session cannot say whether a harbour stands, so it names only the water the
## quay faces (the words the row printed before this reading) and claims nothing
## else. A sealed harbour is no landfall, so the seal takes the transport grant
## with it rather than pricing a yield the Extraction phase withholds.
static func line(
	model: MapModel,
	works: LandWorks,
	province: ProvinceState,
	blockade: Blockades = null
) -> String:
	if model == null or province == null:
		return ""
	var water: String = ProvinceLedger.harbour_name(model, province)
	if works == null:
		if province.port_tile.x < 0:
			return LANDLOCKED
		return ("Harbour · %s" % water) if not water.is_empty() else "Harbour"
	if not stands(model, works, province):
		if province.port_tile.x < 0:
			return LANDLOCKED
		return "No harbour%s · a port brings Transport %d — %s" % [
			(" on the %s" % water) if not water.is_empty() else "",
			TRANSPORT,
			CivilianWorkPlan.cost_text(CivilianWorkPlan.cost_for(PORT_ACTION)),
		]
	var head: String = "Harbour" + ((" · %s" % water) if not water.is_empty() else "")
	if sealed(model, province, blockade):
		return head + " · sealed — no landfall, and its estates gather by road"
	return head + " · Transport %d — the quay and the estates beside it" % TRANSPORT


## The rule behind the row, printed in the tip: what a harbour opens, or what the
## port order would lay and the crew it needs.
static func tip(
	model: MapModel,
	works: LandWorks,
	province: ProvinceState,
	blockade: Blockades = null
) -> String:
	if model == null or province == null:
		return ""
	if works == null:
		return ""
	if not stands(model, works, province):
		if province.port_tile.x < 0:
			return ""
		var wait: int = turns_left(model, province)
		return (
			"No port stands here yet: an idle Engineer lays one in %d turn%s for %s."
			+ " A harbour carries Transport %d on its quay and on the crown's estates"
			+ " beside it, and roots the ground abroad so its estates pay (wiki:"
			+ " civilian-units § Work Order Summary; extraction-and-improvements"
			+ " § Transport Level, § Overseas delivery)."
		) % [
			wait,
			"" if wait == 1 else "s",
			CivilianWorkPlan.cost_text(CivilianWorkPlan.cost_for(PORT_ACTION)),
			TRANSPORT,
		]
	if sealed(model, province, blockade):
		return (
			"A hostile station holds this coast's port: nothing here reaches the"
			+ " crown by sea this turn and its estates gather only what the roads"
			+ " give them (wiki: capital-and-connectivity § Blockade)."
		)
	return (
		"A harbour carries Transport %d on its quay and on the crown's estates"
		+ " beside it, and is the port an overseas network ships through (wiki:"
		+ " extraction-and-improvements § Transport Level, § Overseas delivery;"
		+ " capital-and-connectivity § Blockade)."
	) % TRANSPORT


## Whether the province's own harbour is held shut this turn — the reading the
## estate rows and the crown link already take (`Blockades.cuts` names the
## capital's sea cut too). A court with no reading seals nothing.
static func sealed(
	model: MapModel, province: ProvinceState, blockade: Blockades
) -> bool:
	if model == null or province == null or blockade == null:
		return false
	return blockade.cuts(model.region_id, province.id)


## The port order's wait in turns, so the tip's plural and the figure it prints
## come off one read.
static func turns_left(model: MapModel, province: ProvinceState) -> int:
	if model == null or province == null:
		return 1
	return CivilianWorkPlan.duration_for(model, PORT_ACTION, province.port_tile, null)
