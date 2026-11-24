class_name MapPlayProvinceHarvest
extends RefCounted
## The province dossier's harvest line, read off the session: what the crown's own
## estates in this province clear at today's sell and how many still have room to
## raise — the realm's Economy reading on the sheet the crown raises from
## (wiki: extraction-and-improvements § The crown reads its own estates and towns
## in the realm; DR-20261123-25). The rows are the estates ledger's own
## ([ImprovementLedger]) and the price the market's own
## ([WorldMarket.sell_price]), so the dossier, the realm and the Extraction phase
## can never print three harvests (REQ-P2-03). The sheet reads this on every
## paint, so a raise, a road, a seal or a turn's clearing reaches the line without
## a second home (REQ-P3-02, REQ-P3-03).


## The line for one province of the chart on screen, or `""` when the session is
## gone, keeps no works table, or the id names no province of `model`.
static func line(play: PlaySession, model: MapModel, province_id: int) -> String:
	if play == null or not is_instance_valid(play) or model == null:
		return ""
	if play.civilian_layer == null:
		return ""
	if model.province_data(province_id) == null:
		return ""
	return DossierCopy.harvest(read(play, model, province_id))


## The realm's own economy read for this province: the estates ledger's rows for
## its ground, priced by [RealmReadings.economy] at the market's today's sell.
## `owner` is the crown reading the sheet, so a rival's ground names no estate of
## hers and prices nothing.
static func read(play: PlaySession, model: MapModel, province_id: int) -> Dictionary:
	var owner: int = play.player_faction
	var estate: Dictionary = ImprovementLedger.province_estates(
		model, play.land_works, _units(play), play.stockpile(), owner, province_id,
		play.capital_tile, play.tech_caps(), MapPlayBlockades.crown(play)
	)
	return RealmReadings.economy(estate, owner, MapPlayEconomyLarder.market(play))


## The seated chart's crews: the works table and the civilians the boot hands the
## dossier are the session's own, so the line counts the Builder already at work
## on this ground.
static func _units(play: PlaySession) -> Array[CivilianState]:
	if play.civilian_layer == null:
		return [] as Array[CivilianState]
	return play.civilian_layer.units
