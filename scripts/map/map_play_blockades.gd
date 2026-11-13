class_name MapPlayBlockades
extends RefCounted
## The court's sealed ports, read from the map's own fleets and wars (wiki:
## capital-and-connectivity § Blockade). Rules stay in Blockades; this only hands
## it the station rosters, the seat and the war query (REQ-P3-02, REQ-P3-03).


## The coast sealed against `faction` this turn. The human court's seat follows
## its capital (which moves when the old one falls); a rival's is the seat the
## setup pipeline gave it.
static func of(play: PlaySession, faction: int) -> Blockades:
	if play == null or play.world == null or play.ship_layer == null:
		return Blockades.new()
	if faction < 0 or play.diplomacy == null:
		return Blockades.new()
	var region: int = FactionCatalog.region_of(faction)
	var model: MapModel = play.world.region(region)
	if model == null:
		return Blockades.new()
	var seat: int = play.capital_province
	if faction != play.player_faction:
		seat = int(WorldBootstrap.capital_seat(model, faction)["province"])
	return Blockades.read(
		play.world, play.ship_layer.regions.snapshot(), faction, region, seat,
		MapPlayRaids.hostile(play)
	)


## The court's own seals (the human crown's ports).
static func crown(play: PlaySession) -> Blockades:
	return of(play, play.player_faction if play != null else MapModel.NO_ID)
