class_name GazetteBattle
extends RefCounted
## Land and sea fight pages for one turn's Gazette (wiki: the-gazette § Item
## catalog). It selects which resolved battles the crown may print and shapes
## each structured record; [Gazette] files the line. Outcomes arrive already
## decided — this narrates, it never re-fights (REQ-P2-03, REQ-P3-01).


## Land battles: the crown's own page, or a watched court's — never a World item,
## because a fight between two strangers is not world news. A watched court's
## fight prints only where the crown's own chart reaches the province
## (wiki: the-gazette § What the crown can know; DR-20261110-28).
static func land(
	pages: Array[Array],
	viewer: int,
	world: WorldMap,
	state: DiplomacyState,
	battles: Array,
	watched: Array[int],
	charts: CourtCharts
) -> void:
	for raw: Variant in battles:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var battle: Dictionary = raw
		var attacker: int = int(battle.get("attacker", -1))
		var defender: int = int(battle.get("defender", -1))
		if attacker < 0 or defender < 0:
			continue
		var ours: bool = attacker == viewer or defender == viewer
		if not ours:
			if not _any_watched([attacker, defender], watched, viewer):
				continue
			if not _charted(charts, viewer, battle, false):
				continue
		var rec: Dictionary = _land_record(battle, viewer, world, state, ours)
		if rec.is_empty():
			continue
		Gazette.push(
			pages,
			Gazette.Class.COURT if ours else Gazette.Class.INTEREST,
			String(rec["kind"]),
			rec
		)


## Sea battles: same class and chart rules as land, with the zone in place of
## the province (wiki: the-gazette § What the crown can know; DR-20261110-28).
static func naval(
	pages: Array[Array],
	viewer: int,
	world: WorldMap,
	state: DiplomacyState,
	battles: Array,
	watched: Array[int],
	charts: CourtCharts
) -> void:
	for raw: Variant in battles:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var battle: Dictionary = raw
		var attacker: int = int(battle.get("attacker", -1))
		var defender: int = int(battle.get("defender", -1))
		if attacker < 0 or defender < 0:
			continue
		var ours: bool = attacker == viewer or defender == viewer
		if not ours:
			if not _any_watched([attacker, defender], watched, viewer):
				continue
			if not _charted(charts, viewer, battle, true):
				continue
		var rec: Dictionary = _naval_record(battle, viewer, world, state, ours)
		if rec.is_empty():
			continue
		Gazette.push(
			pages,
			Gazette.Class.COURT if ours else Gazette.Class.INTEREST,
			String(rec["kind"]),
			rec
		)


static func _land_record(
	battle: Dictionary, viewer: int, world: WorldMap, state: DiplomacyState, ours: bool
) -> Dictionary:
	var attacker: int = int(battle.get("attacker", -1))
	var defender: int = int(battle.get("defender", -1))
	var outcome: int = int(battle.get("outcome", ArmyCombat.Outcome.STALEMATE))
	var rec: Dictionary = {"place": _province(world, battle)}
	match outcome:
		ArmyCombat.Outcome.MUTUAL_ANNIHILATION:
			rec["kind"] = "battleAnnihilated"
			var recovered: String = String(battle.get("recovered_type", ""))
			# Another court's garrison and its type are its own affair: only the
			# crown's page names the regiment that re-forms (DR-20261110-28).
			if ours and int(battle.get("garrison", 0)) > 0 and not recovered.is_empty():
				rec["bonus"] = RegimentCatalog.display_name(recovered)
			return rec
		ArmyCombat.Outcome.STALEMATE:
			rec["kind"] = "battleStandoff"
			rec["who"] = _side_name(state, viewer, attacker, ours)
			rec["whom"] = _side_name(state, viewer, defender, ours)
			rec["self_act"] = attacker == viewer
			# A standoff still costs the crown men; its own dead are counted
			# (wiki: the-gazette § What the crown can know).
			if ours:
				rec["own_lost"] = _own_losses(battle, viewer)
			return rec
		ArmyCombat.Outcome.CAPTURE:
			# An unopposed occupation is a province changing hands, not a
			# battle: no shot was fired and no regiment fell, so the sheet
			# prints the flag coming down and no casualty count
			# (wiki: the-gazette § Item catalog — "Provinces the crown took or
			# lost"; § Prose — a line never invents an outcome).
			rec["kind"] = "provinceOccupied"
			rec["who"] = _side_name(state, viewer, attacker, ours)
			rec["whom"] = _side_name(state, viewer, defender, ours)
			rec["self_act"] = attacker == viewer
			return rec
		ArmyCombat.Outcome.ATTACKER_VICTORY:
			# A fought win that takes the province is a capture: the crown's page
			# must print the province lost or taken, not only the field held
			# (wiki: the-gazette § Item catalog — "Provinces the crown took or
			# lost"). An advantage holds the field and leaves the province be
			# (wiki: quick-battle § Outcome and integration).
			var kind: String = (
				"battleCapture" if bool(battle.get("captured", false)) else "battleHeld"
			)
			return _victor(rec, kind, battle, state, viewer, attacker, defender, ours, false)
		ArmyCombat.Outcome.ATTACKER_ADVANTAGE:
			return _victor(rec, "battleHeld", battle, state, viewer, attacker, defender, ours, false)
		ArmyCombat.Outcome.DEFENDER_VICTORY:
			return _victor(rec, "battleHeld", battle, state, viewer, defender, attacker, ours, true)
	return {}


static func _naval_record(
	battle: Dictionary, viewer: int, world: WorldMap, state: DiplomacyState, ours: bool
) -> Dictionary:
	var attacker: int = int(battle.get("attacker", -1))
	var defender: int = int(battle.get("defender", -1))
	var outcome: int = int(battle.get("outcome", NavalCombat.Outcome.STALEMATE))
	var rec: Dictionary = {"place": _zone(world, battle)}
	var raw_retreat: Variant = battle.get("retreat", {})
	var retreat: Dictionary = raw_retreat if typeof(raw_retreat) == TYPE_DICTIONARY else {}
	if bool(retreat.get("success", false)):
		var beaten: int = int(retreat.get("beaten", defender))
		var holder: int = attacker if beaten == defender else defender
		rec["kind"] = "seaWithdrew"
		rec["who"] = _side_name(state, viewer, beaten, ours)
		rec["whom"] = _side_name(state, viewer, holder, ours)
		rec["self_act"] = beaten == viewer
		# The side that holds the water still spends hulls doing it; the crown's
		# own loss is counted (wiki: the-gazette § What the crown can know).
		if ours:
			rec["own_lost"] = _own_losses(battle, viewer)
		return rec
	match outcome:
		NavalCombat.Outcome.SIDE1_VICTORY:
			return _victor(rec, "seaHeld", battle, state, viewer, attacker, defender, ours, false)
		NavalCombat.Outcome.SIDE2_VICTORY:
			return _victor(rec, "seaHeld", battle, state, viewer, defender, attacker, ours, false)
		NavalCombat.Outcome.STALEMATE:
			rec["kind"] = "seaDraw"
			rec["who"] = _side_name(state, viewer, attacker, ours)
			rec["whom"] = _side_name(state, viewer, defender, ours)
			rec["self_act"] = attacker == viewer
			return rec
	return {}


## The winner's record: `count` is what the beaten side lost, in hulls or
## regiments, exactly as the Combat phase recorded it — and only on the crown's
## own page. Another court's losses are never counted (DR-20261110-28).
static func _victor(
	rec: Dictionary,
	kind: String,
	battle: Dictionary,
	state: DiplomacyState,
	viewer: int,
	victor: int,
	beaten: int,
	ours: bool,
	defended: bool
) -> Dictionary:
	var lost: Array = []
	if victor == int(battle.get("attacker", -1)):
		lost = battle.get("defender_lost", []) as Array
	else:
		lost = battle.get("attacker_lost", []) as Array
	rec["kind"] = kind
	rec["who"] = _side_name(state, viewer, victor, ours)
	rec["whom"] = _side_name(state, viewer, beaten, ours)
	rec["self_act"] = victor == viewer
	if ours:
		rec["count"] = lost.size()
		rec["own_lost"] = _own_losses(battle, viewer)
	if defended:
		rec["defended"] = true
	return rec


## The crown's own dead in a battle it fought, read from the side it held. Only
## the crown's own page carries it: another court's losses are never counted
## (wiki: the-gazette § What the crown can know; DR-20261110-28).
static func _own_losses(battle: Dictionary, viewer: int) -> int:
	var side: String = "attacker" if int(battle.get("attacker", -1)) == viewer else "defender"
	return (battle.get(side + "_lost", []) as Array).size()


## A battle's combatants: the crown speaks of itself as "our crown"; a watched
## court of a battle the crown is not in is named as the chronicle names it.
static func _side_name(state: DiplomacyState, viewer: int, faction: int, ours: bool) -> String:
	if ours and faction == viewer:
		return GazetteCopy.CROWN
	return DiplomacyHistory.name_for(state, viewer, faction)


static func _any_watched(parties: Array, watched: Array[int], viewer: int) -> bool:
	for raw: Variant in parties:
		var faction: int = int(raw)
		if faction != viewer and watched.has(faction):
			return true
	return false


## Is the place of another court's fight on the crown's chart? A caller with no
## chart is a headless fixture, and every place counts as charted
## (wiki: the-gazette § What the crown can know; DR-20261110-28).
static func _charted(
	charts: CourtCharts, viewer: int, battle: Dictionary, at_sea: bool
) -> bool:
	if charts == null:
		return true
	var region: int = int(battle.get("region", -1))
	if region < 0:
		return false
	if at_sea:
		return charts.knows_zone(viewer, region, int(battle.get("zone", -1)))
	return charts.knows_province(viewer, region, int(battle.get("province", -1)))


static func _province(world: WorldMap, battle: Dictionary) -> String:
	if world == null:
		return "the field"
	var model: MapModel = world.region(int(battle.get("region", 0)))
	if model == null:
		return "the field"
	return model.province_name(int(battle.get("province", -1)))


static func _zone(world: WorldMap, battle: Dictionary) -> String:
	if world == null:
		return "open water"
	var model: MapModel = world.region(int(battle.get("region", 0)))
	if model == null:
		return "open water"
	return model.sea_zone_name(int(battle.get("zone", -1)))
