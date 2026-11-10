class_name MapPlayPortLoss
extends RefCounted
## Port verdicts of the Combat phase: a squadron caught in a port that changed
## hands sorts out rather than being taken in harbour, and a reassigned crown's
## home squadron re-moors with its court (wiki: ships-and-naval § Ports that
## change hands; DR-20261109-11, DR-20261109-12). Presentation only — the rules
## stay in NavalPortLoss and FleetPortSettlement (REQ-P3-03).


static func settle(play: PlaySession, reassigned: Array) -> void:
	if play.ship_layer == null:
		return
	var reports: Array[Dictionary] = play.ship_layer.settle_port_losses(
		play.world, reassigned
	)
	for report: Dictionary in reports:
		if report.has("merged"):
			_report_merge(play, report)
			continue
		_report_move(play, report)


## The re-mooring is administrative, so the squadron keeps its passengers. One
## squadron carries one army: a surplus army goes ashore at the new seat rather
## than drowning in the merge (wiki: ships-and-naval § Naval transport).
static func _report_merge(play: PlaySession, report: Dictionary) -> void:
	var seat: int = int(report.get("to", MapModel.NO_ID))
	var owner: int = int(report.get("owner", MapModel.NO_ID))
	var owner_name: String = FactionCatalog.name_of(owner)
	var place: String = _place(play, report, seat)
	play.hud.toast("%s's home squadron re-moors at %s" % [owner_name, place])
	for raw: Variant in report.get("ashore", []):
		put_ashore(play, int(raw), seat, place)


## Lands an army a merge could not keep aboard and tells the player where.
static func put_ashore(
	play: PlaySession, army_id: int, province_id: int, place: String = ""
) -> void:
	if play.army_layer == null:
		return
	var landed: Dictionary = ArmyTransport.put_ashore(
		play.army_layer, army_id, province_id
	)
	if not bool(landed.get("ok", false)):
		return
	var where: String = place
	if where.is_empty():
		where = _place(play, {}, province_id)
	play.hud.toast("The troops go ashore at %s" % where)


## A re-moored squadron or a squadron that sorted out of a lost port.
static func _report_move(play: PlaySession, report: Dictionary) -> void:
	var owner: int = int(report.get("owner", MapModel.NO_ID))
	var owner_name: String = FactionCatalog.name_of(owner)
	if report.has("from"):
		var seat: int = int(report.get("to", MapModel.NO_ID))
		play.hud.toast(
			"%s's home squadron re-moors at %s"
			% [owner_name, _place(play, report, seat)]
		)
		return
	var province: int = int(report.get("province", MapModel.NO_ID))
	var place: String = _place(play, report, province)
	if bool(report.get("scuttled", false)):
		play.hud.toast(
			"%s's squadron is scuttled in %s — no water to sort out into"
			% [owner_name, place]
		)
		return
	var zone: int = int(report.get("zone", MapModel.NO_ID))
	play.hud.toast(
		"%s's squadron sorts out of %s into %s"
		% [owner_name, place, _zone_name(play, report, zone)]
	)


static func _model(play: PlaySession, report: Dictionary) -> MapModel:
	var region: int = int(report.get("region", play.region_index))
	if play.model != null and region == play.region_index:
		return play.model
	return play.world.region(region) if play.world != null else null


static func _place(play: PlaySession, report: Dictionary, province_id: int) -> String:
	var model: MapModel = _model(play, report)
	return model.province_name(province_id) if model != null else "—"


static func _zone_name(play: PlaySession, report: Dictionary, zone_id: int) -> String:
	var model: MapModel = _model(play, report)
	return model.sea_zone_name(zone_id) if model != null else "—"
