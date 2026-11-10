class_name MapPlayEspionage
extends RefCounted
## Session glue for the spy network: folds every region's roster into the
## Research-phase share (wiki: civilian-units § Spy; DR-20261110-03). The rules
## live in SpyNetworks; this only reads the live rosters and the rival ledgers.

const SPY_TYPE: String = "spy"


## Rival Great Powers (ascending, unique) whose land shelters at least one of
## the crown's spies, across every region. Court reports read the same list, so
## a despatch is only written for a court the crown actually watches.
static func shadowed_rivals(play: PlaySession) -> Array[int]:
	var rivals: Array[int] = []
	if play == null or play.civilian_layer == null:
		return rivals
	for index in play.world.region_count():
		var model: MapModel = play.world.region(index)
		for rival: int in SpyNetworks.qualifying_rivals(
			model, _roster(play, index), play.player_faction
		):
			if not rivals.has(rival):
				rivals.append(rival)
	rivals.sort()
	return rivals


## Tech id -> percent the human crown's spies add this turn. Empty when no spy
## stands on a rival Great Power's land, or before the rival ledgers exist.
## Every region counts: a spy posted overseas reads the same.
static func research_boost(play: PlaySession) -> Dictionary:
	if play == null or play.civilian_layer == null or play.ai == null:
		return {}
	var rivals: Array[int] = shadowed_rivals(play)
	if rivals.is_empty():
		return {}
	var tech: Dictionary = {}
	for faction: int in rivals:
		tech[faction] = play.ai.economy_for(faction).tech_unlocked
	return SpyNetworks.research_boost(rivals, tech)


## Live roster for the shown region, stored table for the other.
static func _roster(play: PlaySession, index: int) -> Array[CivilianState]:
	var units: Array[CivilianState] = []
	if index == play.region_index:
		return play.civilian_layer.units
	units.assign(play.civilian_layer.regions.value(index, []))
	return units


## Rival research tables before the economy pass, so the despatch can name the
## technologies each court finished this turn (wiki: civilian-units § Spy).
static func tech_snapshot(play: PlaySession) -> Dictionary:
	var snapshot: Dictionary = {}
	if play == null or play.ai == null:
		return snapshot
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction and not play.observer_mode:
			continue
		var unlocked: Dictionary = play.ai.economy_for(faction).tech_unlocked
		snapshot[faction] = unlocked.duplicate()
	return snapshot


## Writes the resolved turn's despatch for every shadowed court and leaves the
## chronicle mark for the next turn (wiki: civilian-units § Spy — court reports;
## DR-20261110-07). Derived state: a save reloads without it.
static func record_court_reports(
	play: PlaySession,
	land_battles: Array,
	naval_battles: Array,
	tech_before: Dictionary
) -> void:
	if play == null or play.observer_mode:
		return
	var shadowed: Array[int] = shadowed_rivals(play)
	var after: Dictionary = tech_snapshot(play)
	play.court_reports = {
		"turn": play.turn,
		"shadowed": shadowed,
		"facts": CourtReports.collect(
			play.diplomacy, play.court_report_mark,
			land_battles, naval_battles,
			CourtReports.techs_gained(tech_before, after), shadowed
		),
	}
	play.court_report_mark = play.diplomacy.events.size() if play.diplomacy != null else 0
