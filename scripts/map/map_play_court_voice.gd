class_name MapPlayCourtVoice
extends RefCounted
## The court answers the crown's own turn (wiki: dialogue-and-mood § Design
## intent — `event`: tech discovered, capital threatened; DR-20261111-08).
##
## Presentation only: it reads the turn that just resolved — the studies the
## Research phase finished, the hosts standing at the crown's seat and the
## rivals due to speak about their own motives — and records the beat the court
## panel then speaks. Nothing here changes a rule outcome (REQ-P2-03,
## REQ-P3-03).


## Both beats of one resolved turn. A rival's turn and the observer speak
## nothing: the court panel only ever answers the human crown.
static func record_turn(play: PlaySession, crown_report: Dictionary) -> void:
	if play == null or play.observer_mode or play.diplomacy == null:
		return
	# The weakest beat goes in first: a study, a host at the seat or any act of
	# the same turn is recorded after it and stays the court's newest word
	# (DR-20261111-19).
	_record_agendas(play)
	_record_study(play, crown_report)
	_record_seat(play)


## A rival's veiled word about its own hidden motive, on its own seven-turn
## cadence and only once the crown's dossier already suspects it (wiki:
## dialogue-and-mood § Seeding / cadence; hidden-agendas § Playable slice).
static func _record_agendas(play: PlaySession) -> void:
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		DialogueAgenda.record(
			play.diplomacy,
			play.world,
			play.player_faction,
			faction,
			play.map_seed,
			play.turn
		)


## The costliest study the turn finished, ties by ascending id: a court speaks
## once about the age's work, not once per finished study.
static func _record_study(play: PlaySession, crown_report: Dictionary) -> void:
	var research: Variant = crown_report.get("research", {})
	if typeof(research) != TYPE_DICTIONARY:
		return
	var done: Variant = (research as Dictionary).get("researched", [])
	if typeof(done) != TYPE_ARRAY:
		return
	var tech_id: String = _deepest(done as Array)
	if tech_id.is_empty():
		return
	DialogueHome.record_tech_studied(play.diplomacy, play.player_faction, tech_id)


static func _deepest(done: Array) -> String:
	var best: String = ""
	var best_cost: int = -1
	for raw: Variant in done:
		var tech_id: String = String(raw)
		if tech_id.is_empty():
			continue
		var cost: int = TechCatalog.cost(tech_id)
		if best.is_empty() or cost > best_cost or (cost == best_cost and tech_id < best):
			best = tech_id
			best_cost = cost
	return best


## The seat still held, with a hostile host standing in its province: the host
## speaks. A seat that fell this turn is capital loss, which has its own news.
static func _record_seat(play: PlaySession) -> void:
	var seat: Dictionary = _seat(play)
	if seat.is_empty():
		return
	var region: int = int(seat["region"])
	var province: int = int(seat["province"])
	var model: MapModel = play.world.region(region) if play.world != null else null
	if model == null or model.province_owner(province) != play.player_faction:
		return
	DialogueHome.record_capital_threat(
		play.diplomacy, play.player_faction, province, _hosts(play, region, province)
	)


## The crown's capital province and the region it lives in, or {} when the
## campaign has no seat yet.
static func _seat(play: PlaySession) -> Dictionary:
	if play.world == null:
		return {}
	for region in play.world.region_count():
		var province: int = play.world.capital_province_of(region, play.player_faction)
		if province != MapModel.NO_ID:
			return {"region": region, "province": province}
	return {}


## Every army standing in the province this turn, trimmed to what the beat
## reads. The shown region's roster is live; the others keep their stored table
## (a seat is usually off-screen while the crown is abroad).
static func _hosts(play: PlaySession, region: int, province: int) -> Array:
	var hosts: Array = []
	if play.army_layer == null:
		return hosts
	for army: ArmyState in _armies(play, region):
		if army == null or army.province != province or army.is_embarked():
			continue
		hosts.append({"owner": army.owner, "strength": army.strength()})
	return hosts


static func _armies(play: PlaySession, region: int) -> Array[ArmyState]:
	var armies: Array[ArmyState] = []
	if play.model != null and play.model.region_id == region:
		return play.army_layer.armies
	armies.assign(play.army_layer.regions.value(region, []))
	return armies
