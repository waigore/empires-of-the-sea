class_name MapPlayProvinceHarbour
extends RefCounted
## The province dossier's Squadrons row, read off the session: the chart's
## squadrons in port, the province's owner and the crown's own fog (wiki:
## fog-and-exploration § Order-of-battle readings; DR-20261123-14). The boot
## seats the session on the sheet once (`MapPlayProvinceHosts.seat`) and the
## sheet reads its own method on every paint, so a sail, a dock, a launch or a
## fog change reaches the row without a second home (REQ-P3-02, REQ-P3-03).


## The row for one province of the chart on screen, or `""` when the session
## keeps no ship layer or the id names no province of `model`.
static func line(play: PlaySession, model: MapModel, province_id: int) -> String:
	if play == null or model == null or play.ship_layer == null:
		return ""
	var province: ProvinceState = model.province_data(province_id)
	if province == null:
		return ""
	var fleets: Array = []
	var table: MapRegionTable = play.ship_layer.regions
	if table != null and table.has_region(model.region_id):
		fleets = table.value(model.region_id, []) as Array
	# The rule's own gate: another court's hulls are read where this crown's grid
	# holds the province at `fogged` or better; a session with no fog reads all.
	var known: bool = play.visibility == null or play.visibility.is_province_known(province_id)
	return ProvinceHarbour.line(
		fleets, province_id, province.owner, play.player_faction, known
	)
