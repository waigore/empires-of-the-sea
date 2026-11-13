class_name TribeContact
extends RefCounted
## First contact between a rival Great Power and a Tribe (wiki: diplomacy
## § GP–Tribe first contact).
##
## A court discovers a Tribe when its own chart holds a **non-`unknown`** tile in
## a province that Tribe owns. Sea-reachable colonial intel alone never counts:
## the reachability the Explorer and the invasion planner read connects Old World
## coasts to an unrevealed New World, and a court that has never charted a tribe
## province holds no diplomatic target there. Discovery persists `AT_PEACE`,
## score 50 (60 for a crown whose leader publishes the Tribe lean, wiki:
## leader-bonuses § Bonus Table — Isabella) and Neutral with `sinceTurn` = the
## resolved turn, and it is irreversible — the record survives a later fog decay.
##
## Rival courts make this contact during turn resolution, once the fog pass has
## settled every chart, and hear no herald. The human court's relation and its
## herald stay in the app layer (`MapPlayDiplomacy.sync_first_contact`), so this
## pass skips that court outright and never runs it twice.
## Pure rules: charts, relations and leaders in, relations out (REQ-P2-03,
## REQ-P3-03).


## Opens first contact for every AI crown that charts a Tribe province and holds
## no relation with that Tribe yet. `leaders` maps faction -> leaderKey, so a
## court whose leader publishes the first-contact lean opens on its score.
## Returns the pairs discovered, `{faction, tribe}`, in faction then tribe id
## order.
static func apply(
	charts: CourtCharts, state: DiplomacyState, human: int, turn: int,
	leaders: Dictionary = {}
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if charts == null or state == null:
		return found
	for faction: int in FactionCatalog.great_power_ids():
		if faction == human:
			continue
		var score: float = LeaderCatalog.first_contact_score(String(leaders.get(faction, "")))
		for tribe: int in charted_tribes(charts, faction):
			if state.has_relation(faction, tribe):
				continue
			var relation: DiplomacyRelation = state.ensure_relation(faction, tribe, turn)
			if relation != null:
				relation.set_score(score)
			_record(state, faction, tribe, turn, score)
			found.append({"faction": faction, "tribe": tribe})
	return found


## Tribes a court has charted a province of, in id order. A single fogged tile
## is enough: the court need not hold the ground or have seen the whole
## province.
static func charted_tribes(charts: CourtCharts, faction: int) -> Array[int]:
	var tribes: Array[int] = []
	if charts == null:
		return tribes
	var by_region: Dictionary = charts.regions_of(faction)
	for region: Variant in by_region.keys():
		var view: VisibilityModel = by_region[region]
		if view == null or view.model == null:
			continue
		for province: ProvinceState in view.model.provinces:
			if province.owner == MapModel.NO_ID or tribes.has(province.owner):
				continue
			if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.TRIBE:
				continue
			if view.is_province_known(province.id):
				tribes.append(province.owner)
	tribes.sort()
	return tribes


## The beat is stamped with the turn that resolved, not the state's clock: the
## diplomacy phase closed before movement, so `DiplomacyState.turn` has already
## stepped into the new turn by the time this pass runs, and the court's sheet
## narrates the turn just played. The record carries the opening score, and the
## pair already reads as Neutral, so no decay entry is needed on top of the
## record.
static func _record(
	state: DiplomacyState, faction: int, tribe: int, turn: int, score: float
) -> void:
	state.events.append(
		{
			"kind": "firstContact", "a": faction, "b": tribe, "turn": turn,
			"data": {"score": score},
		}
	)
