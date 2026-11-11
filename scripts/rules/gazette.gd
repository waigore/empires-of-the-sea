class_name Gazette
extends RefCounted
## Builds one turn's Gazette sheet from the resolved turn's public record
## (wiki: the-gazette; DR-20261110-14). It selects and narrates: every rule
## outcome has already been decided elsewhere and arrives here as a structured
## record, so prose can never contradict combat, diplomacy or research
## (REQ-P2-03).
##
## Classification is exclusive and ordered — Our court (the crown is a party),
## then World (a public epoch-scale fact), then Courts of interest (a watched
## court is a party). Display order is World, Our court, Courts of interest,
## with resolution order kept inside each class.

enum Class { WORLD, COURT, INTEREST }


## One turn's sheet, ready to file and print: `{turn, items}` with the items in
## display order. A turn with nothing worth printing yields an empty item list,
## which the caller still archives so the history has no gaps.
##
## `research` maps a faction to the technologies it finished; `richness` is the
## crown's deed income the turn summary named; `raids` are MapPlayRaids reports.
## `charts` is the crown's own chart: a watched court's battle prints only where
## the crown has the place at fogged or better (wiki: the-gazette § What the
## crown can know; DR-20261110-28). A caller with no chart is a headless fixture.
static func collect(
	viewer: int,
	turn: int,
	world: WorldMap,
	state: DiplomacyState,
	watched: Array[int],
	land_battles: Array,
	naval_battles: Array,
	falls: Array,
	research: Dictionary,
	richness: int,
	raids: Array,
	charts: CourtCharts = null
) -> Dictionary:
	var pages: Array[Array] = [[], [], []]
	_diplomacy(pages, viewer, turn, state, watched)
	_land(pages, viewer, world, state, land_battles, watched, charts)
	_naval(pages, viewer, world, state, naval_battles, watched, charts)
	_falls(pages, viewer, state, falls)
	_studies(pages, viewer, research)
	_treasury(pages, richness)
	_raids(pages, raids)
	var items: Array[Dictionary] = []
	for cls: int in [Class.WORLD, Class.COURT, Class.INTEREST]:
		for entry: Variant in pages[cls]:
			items.append(entry)
	return {"turn": turn, "items": items}


## True when a sheet prints nothing: the overlay is skipped, the archive entry
## is not (wiki: the-gazette § When it appears).
static func is_empty(sheet: Dictionary) -> bool:
	return (sheet.get("items", []) as Array).is_empty()


## Heading the plate prints above a class's run of lines.
static func heading(cls: int) -> String:
	match cls:
		Class.WORLD:
			return "THE WORLD"
		Class.COURT:
			return "OUR COURT"
	return "COURTS OF INTEREST"


# --- sources -----------------------------------------------------------------


static func _diplomacy(
	pages: Array[Array], viewer: int, turn: int, state: DiplomacyState, watched: Array[int]
) -> void:
	var sorted: Dictionary = GazetteDiplomacy.classify(viewer, turn, state, watched)
	for entry: Array in [[Class.WORLD, "world"], [Class.COURT, "court"], [Class.INTEREST, "interest"]]:
		for item: Variant in sorted[String(entry[1])]:
			var row: Dictionary = item
			_push(pages, int(entry[0]), String(row["kind"]), row["rec"] as Dictionary)


## Land battles: the crown's own page, or a watched court's — never a World item,
## because a fight between two strangers is not world news. A watched court's
## fight prints only where the crown's own chart reaches the province
## (wiki: the-gazette § What the crown can know; DR-20261110-28).
static func _land(
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
		_push(pages, Class.COURT if ours else Class.INTEREST, String(rec["kind"]), rec)


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
			return _victor(rec, "battleCapture", battle, state, viewer, attacker, defender, ours, false)
		ArmyCombat.Outcome.ATTACKER_VICTORY, ArmyCombat.Outcome.ATTACKER_ADVANTAGE:
			return _victor(rec, "battleHeld", battle, state, viewer, attacker, defender, ours, false)
		ArmyCombat.Outcome.DEFENDER_VICTORY:
			return _victor(rec, "battleHeld", battle, state, viewer, defender, attacker, ours, true)
	return {}


static func _naval(
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
		_push(pages, Class.COURT if ours else Class.INTEREST, String(rec["kind"]), rec)


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


static func _falls(
	pages: Array[Array], viewer: int, state: DiplomacyState, falls: Array
) -> void:
	for raw: Variant in falls:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var fallen: Dictionary = raw
		var faction: int = int(fallen.get("faction", -1))
		# Only a Great Power's fall is world news; a Minor or Tribe falling is
		# map cleanup, not a struck name (wiki: the-gazette § Item catalog).
		if faction < 0 or faction == viewer or not FactionCatalog.can_win(faction):
			continue
		if not _met(state, viewer, faction):
			continue
		_push(
			pages,
			Class.WORLD,
			"greatPowerFell",
			{
				"who": GazetteDiplomacy.name_for(state, viewer, faction),
				"whom": GazetteDiplomacy.name_for(state, viewer, int(fallen.get("conqueror", -1))),
			}
		)


## Only the crown's own studies print. Another court's finished technology is
## not public news: it stays the spy's court report and the dossier's evidence
## (wiki: the-gazette § What the crown can know; civilian-units § Spy;
## DR-20261110-28).
static func _studies(pages: Array[Array], viewer: int, research: Dictionary) -> void:
	var raw: Variant = research.get(viewer, [])
	if typeof(raw) != TYPE_ARRAY:
		return
	for tech: Variant in raw as Array:
		_push(
			pages,
			Class.COURT,
			"techFinished",
			{
				"who": GazetteCopy.CROWN,
				"label": TechCatalog.display_name(String(tech)),
				"self_act": true,
			}
		)


static func _treasury(pages: Array[Array], richness: int) -> void:
	if richness <= 0:
		return
	_push(pages, Class.COURT, "richesRendered", {"amount": richness})


## Raids are the crown's own until the rules say otherwise, so both directions
## print on Our court page (wiki: the-gazette § Item catalog — Our court).
static func _raids(pages: Array[Array], raids: Array) -> void:
	for raw: Variant in raids:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var raid: Dictionary = raw
		var place: String = String(raid.get("zone_name", "")).strip_edges()
		if place.is_empty():
			place = "open water"
		var prize: String = BattleReport.cargo_of(raid.get("losses", {}) as Dictionary)
		var sunk: String = BattleReport.sunk_of(raid.get("hulls_lost", []))
		var kind: String = "raidPrize" if String(raid.get("kind", "")) == "prize" else "raidSuffered"
		_push(pages, Class.COURT, kind, {"place": place, "prize": prize, "sunk": sunk})


# --- internals ---------------------------------------------------------------


static func _push(pages: Array[Array], cls: Class, kind: String, rec: Dictionary) -> void:
	rec["kind"] = kind
	var text: String = GazetteCopy.line(rec)
	if text.is_empty():
		return
	pages[cls].append({"class": cls, "kind": kind, "text": text})


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


static func _met(state: DiplomacyState, viewer: int, faction: int) -> bool:
	if faction == viewer:
		return true
	if faction < 0 or state == null:
		return false
	return state.has_relation(viewer, faction)


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
