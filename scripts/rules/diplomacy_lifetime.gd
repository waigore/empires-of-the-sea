class_name DiplomacyLifetime
extends RefCounted
## The two edges of a campaign's diplomatic ledger: the courts already in
## contact when the sea opens, and the erasure of a court absorbed by Join
## Empire (wiki: diplomacy § Alliances; § GP–Tribe Rules — Join Empire). Both
## walk every table a [DiplomacyState] keeps, so they live here rather than
## crowding the state past its method bar (REQ-P3-01): the state owns what it
## stores, this module owns how a court comes and goes. Pure data, no nodes
## (REQ-P3-03).


## Opens the ledger: a clean slate, the region peers in contact, and an embassy
## between every pair of Great Powers.
static func open(state: DiplomacyState, at_turn: int) -> void:
	state.reset(at_turn)
	_seed_group(state, _region_peers(FactionCatalog.OLD_WORLD))
	_seed_group(state, _region_peers(FactionCatalog.NEW_WORLD))
	for gp_a: int in FactionCatalog.great_power_ids():
		for gp_b: int in FactionCatalog.great_power_ids():
			if gp_a == gp_b:
				continue
			state.set_overture(gp_a, gp_b, DiplomacyCatalog.STAGE_EMBASSY)


## Removes every trace of a faction absorbed by Join Empire: its relations,
## pacts, trade ties, colonies and the decisions still waiting on its court.
static func absorb(state: DiplomacyState, faction: int) -> void:
	_purge(state.relations, faction)
	_drop_pending(state.pending_interventions, ["aggressor", "target"], faction)
	_drop_pending(state.pending_offers, ["from"], faction)
	# A call to arms is a decision waiting on a court, and a crown that left play
	# can neither answer one nor be answered for: the call goes with it, so the
	# court is never asked to honour a treaty with a court that no longer exists
	# (wiki: diplomacy § GP–Minor Rules — Join Empire; § Alliances).
	_drop_pending(state.pending_calls, ["aggressor", "defender", "ally"], faction)
	# The frozen mutual-defence map is a treaty record too, read from the
	# relations just dropped.
	_purge(state.alliance_snapshot, faction)
	_purge(state.overtures, faction)
	_purge(state.subsidies, faction)
	_purge(state.ftps, faction)
	_purge(state.boycotts, faction)
	for tribe: int in state.colonies.keys():
		if tribe != faction and int(state.colonies[tribe]) != faction:
			continue
		if int(state.colonies[tribe]) == faction:
			# The suzerain left play: the colony becomes independent again
			# (wiki: diplomacy § GP–Tribe Rules — Join Empire, R5.5).
			state.record_event("colonyReleased", tribe, faction)
		state.colonies.erase(tribe)


## Drops every pair or directed key that names `faction` on either side.
static func _purge(table: Dictionary, faction: int) -> void:
	for key: String in table.keys():
		if DiplomacyKeys.touches(key, faction):
			table.erase(key)


## Drops every subsidy row a court could not have set: a Great Power-to-Great
## Power row, a legacy £/turn row, a percent off the published 5–20 ladder, or a
## malformed key (wiki: diplomacy § Acceptance Criteria — a save carrying any of
## them loads with none of them; R3, "the legacy £ subsidies are dropped; the
## player re-establishes them under the percent model"). A subsidy is only ever
## Great Power → Minor/Tribe, so every other shape is refused before any rules
## pass reads it.
##
## The legacy shape stores an object where a percent belongs, and reading that
## object as an int throws, so a single un-migrated row took the whole pass that
## prices every subsidy down with it — the legal rows included. The load is the
## one place that can tell a legacy row from a live one, so the pruning is done
## here rather than guessed at by a reader. Returns how many rows went.
static func prune_subsidies(state: DiplomacyState) -> int:
	if state == null:
		return 0
	var dropped: int = 0
	for key: String in state.subsidies.keys():
		if _subsidy_allowed(key, state.subsidies[key]):
			continue
		state.subsidies.erase(key)
		dropped += 1
	return dropped


## True for a row the subsidy rules could still read: a Great Power payer, a
## Minor Nation or Tribe target, and a published percent.
static func _subsidy_allowed(key: String, value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var courts: Vector2i = DiplomacyKeys.directed_courts(key)
	if courts.x < 0 or courts.y < 0 or courts.x == courts.y:
		return false
	if FactionCatalog.type_of(courts.x) != FactionCatalog.Type.GREAT_POWER:
		return false
	var target: int = FactionCatalog.type_of(courts.y)
	if target != FactionCatalog.Type.MINOR_NATION and target != FactionCatalog.Type.TRIBE:
		return false
	return DiplomacyCatalog.is_valid_subsidy(int(value))


## Drops every pending decision whose named courts include `faction`.
static func _drop_pending(
	entries: Array[Dictionary], fields: Array[String], faction: int
) -> void:
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		for field: String in fields:
			if int(entry.get(field, -1)) == faction:
				entries.remove_at(index)
				break


static func _seed_group(state: DiplomacyState, ids: Array[int]) -> void:
	for first in ids.size():
		for second in range(first + 1, ids.size()):
			state.ensure_relation(ids[first], ids[second], state.turn)


static func _region_peers(region: int) -> Array[int]:
	var result: Array[int] = []
	for faction: Dictionary in FactionCatalog.all():
		var type: int = int(faction["type"])
		if int(faction["region"]) != region:
			continue
		if region == FactionCatalog.OLD_WORLD:
			if type == FactionCatalog.Type.GREAT_POWER or type == FactionCatalog.Type.MINOR_NATION:
				result.append(int(faction["id"]))
		elif type == FactionCatalog.Type.TRIBE:
			result.append(int(faction["id"]))
	return result
