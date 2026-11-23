class_name MapPlayProvinceHosts
extends RefCounted
## The province dossier's Hosts row, read off the session: the chart's armies,
## the province's owner and the crown's own fog (wiki: fog-and-exploration
## § Order-of-battle readings; DR-20261123-13). The boot seats the session on
## the sheet once and the sheet reads its own method on every paint, so a march,
## a muster or a fog change reaches the row without a second home (REQ-P3-02,
## REQ-P3-03).


## Seats the session on the province sheet, so the sheet's own method can count
## the chart's hosts on every paint. One field, reassigned by the boot and by
## every dossier refresh — never a closure, which cannot outlive the session it
## reads (DR-20261121-14).
static func seat(play: PlaySession) -> void:
	if play == null or play.hud == null or play.hud.panels.panel == null:
		return
	play.hud.panels.panel.play = play


## The row for one province of the chart on screen, or `""` when the session
## keeps no army layer or the id names no province of `model`.
static func line(play: PlaySession, model: MapModel, province_id: int) -> String:
	if play == null or model == null or play.army_layer == null:
		return ""
	var province: ProvinceState = model.province_data(province_id)
	if province == null:
		return ""
	var armies: Array = []
	var table: MapRegionTable = play.army_layer.regions
	if table != null and table.has_region(model.region_id):
		armies = table.value(model.region_id, []) as Array
	# The rule's own gate: another court's hosts are read where this crown's grid
	# holds the province at `fogged` or better; a session with no fog reads all.
	var known: bool = play.visibility == null or play.visibility.is_province_known(province_id)
	return ProvinceHosts.line(armies, province_id, province.owner, play.player_faction, known)
