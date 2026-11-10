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
	raids: Array
) -> Dictionary:
	var pages: Array[Array] = [[], [], []]
	_diplomacy(pages, viewer, turn, state, watched)
	_land(pages, viewer, world, state, land_battles, watched)
	_naval(pages, viewer, world, state, naval_battles, watched)
	_falls(pages, viewer, state, falls)
	_studies(pages, viewer, state, watched, research)
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
## because a fight between two strangers is not world news (wiki: the-gazette
## § PlayerView and masking).
static func _land(
	pages: Array[Array],
	viewer: int,
	world: WorldMap,
	state: DiplomacyState,
	battles: Array,
	watched: Array[int]
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
		if not ours and not _any_watched([attacker, defender], watched, viewer):
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
			if int(battle.get("garrison", 0)) > 0 and not recovered.is_empty():
				rec["bonus"] = RegimentCatalog.display_name(recovered)
			return rec
		ArmyCombat.Outcome.STALEMATE:
			rec["kind"] = "battleStandoff"
			rec["who"] = _side_name(state, viewer, attacker, ours)
			rec["whom"] = _side_name(state, viewer, defender, ours)
			rec["self_act"] = attacker == viewer
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
	watched: Array[int]
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
		if not ours and not _any_watched([attacker, defender], watched, viewer):
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
## regiments, exactly as the Combat phase recorded it.
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
	rec["count"] = lost.size()
	if defended:
		rec["defended"] = true
	return rec


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


static func _studies(
	pages: Array[Array],
	viewer: int,
	state: DiplomacyState,
	watched: Array[int],
	research: Dictionary
) -> void:
	var factions: Array = research.keys()
	factions.sort()
	for raw: Variant in factions:
		var faction: int = int(raw)
		if faction != viewer and not watched.has(faction):
			continue
		if not _met(state, viewer, faction):
			continue
		var cls: Class = Class.COURT if faction == viewer else Class.INTEREST
		for tech: Variant in research[raw]:
			_push(
				pages,
				cls,
				"techFinished",
				{
					"who": GazetteDiplomacy.name_for(state, viewer, faction),
					"label": TechCatalog.display_name(String(tech)),
					"self_act": faction == viewer,
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
		var kind: String = "raidPrize" if String(raid.get("kind", "")) == "prize" else "raidSuffered"
		_push(pages, Class.COURT, kind, {"place": place, "prize": prize})


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
