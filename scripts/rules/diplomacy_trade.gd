class_name DiplomacyTrade
extends RefCounted
## Trade diplomacy: favoured-trading-partner pacts, colonial boycotts and the
## world-market price terms a crown's standing earns (wiki: diplomacy § GP–Tribe
## — Boycott; world-market § FTP, § Subsidy price adjustment). Pure rules:
## callers supply DiplomacyState and WorldMap; nothing here touches a node
## (REQ-P3-03).
##
## The product clears every crown against one global order book, so a pact's
## priority and a boycott's exclusion cannot be matched deal by deal. They are
## published as per-crown price terms the market applies, and a subsidy's
## discount/surcharge lands on the commodities that court's provinces produce
## (docs/diplomacy.md § Trade terms).

const KIND_FTP: String = "establish_ftp"
const KIND_REVOKE_FTP: String = "revoke_ftp"
const KIND_BOYCOTT: String = "boycott"
const KIND_REVOKE_BOYCOTT: String = "revoke_boycott"


static func is_ftp(state: DiplomacyState, a: int, b: int) -> bool:
	if state == null or a == b:
		return false
	return state.ftps.has(state.pair_key(a, b))


static func ftps_of(state: DiplomacyState, faction: int) -> Array[int]:
	var partners: Array[int] = []
	if state == null:
		return partners
	for key: String in state.ftps.keys():
		var parts: PackedStringArray = key.split(":")
		if parts.size() != 2:
			continue
		var low: int = int(parts[0])
		var high: int = int(parts[1])
		if low == faction:
			partners.append(high)
		elif high == faction:
			partners.append(low)
	partners.sort()
	return partners


static func can_establish_ftp(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	if player == target:
		return _deny("A crown cannot trade with itself.")
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return _deny("Only Great Powers exchange favoured trading pacts.")
	if not state.has_relation(player, target):
		return _deny("No envoy has reached that court.")
	if state.relation(player, target).at_war:
		return _deny("No trade pact can be signed with an enemy.")
	if not DiplomacyRules.has_embassy(state, player, target):
		return _deny("An embassy is required before a trade pact.")
	if is_ftp(state, player, target):
		return _deny("A favoured trading pact already binds us.")
	if state.claimed(player, target, "ftp"):
		return _deny("A trade pact was already offered to this court this turn.")
	return _allow()


## The target answers: an AI court accepts at Friendly standing or better
## (wiki: world-market § FTP — relation ≥ 65).
static func establish_ftp(
	state: DiplomacyState, player: int, target: int, decision: String = ""
) -> Dictionary:
	var check: Dictionary = can_establish_ftp(state, player, target)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "ftp")
	var record: DiplomacyRelation = state.relation(player, target)
	var accepts: bool = _accepts_ftp(record)
	if decision == DiplomacyRules.DECISION_ACCEPT:
		accepts = true
	elif decision == DiplomacyRules.DECISION_REFUSE:
		accepts = false
	if not accepts:
		state.record_event("ftpRefused", player, target)
		return {
			"ok": true,
			"accepted": false,
			"message": "%s declines a favoured trading pact." % (
				FactionCatalog.name_of(target)
			),
		}
	state.ftps[state.pair_key(player, target)] = state.turn
	state.record_event("ftpSigned", player, target)
	return {
		"ok": true,
		"accepted": true,
		"message": "%s signs a favoured trading pact: our merchants clear first." % (
			FactionCatalog.name_of(target)
		),
	}


static func can_revoke_ftp(state: DiplomacyState, player: int, target: int) -> Dictionary:
	if not is_ftp(state, player, target):
		return _deny("No favoured trading pact is in force.")
	if state.claimed(player, target, "ftp"):
		return _deny("A trade pact was already offered to this court this turn.")
	return _allow()


static func revoke_ftp(state: DiplomacyState, player: int, target: int) -> Dictionary:
	var check: Dictionary = can_revoke_ftp(state, player, target)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "ftp")
	state.ftps.erase(state.pair_key(player, target))
	state.record_event("ftpRevoked", player, target)
	return {
		"ok": true,
		"reason": "",
		"message": "The favoured trading pact with %s is ended." % (
			FactionCatalog.name_of(target)
		),
	}


static func is_boycotting(state: DiplomacyState, issuer: int, target: int) -> bool:
	if state == null:
		return false
	return state.boycotts.has("%d>%d" % [issuer, target])


static func boycotts_against(state: DiplomacyState, target: int) -> Array[int]:
	var issuers: Array[int] = []
	if state == null:
		return issuers
	for key: String in state.boycotts.keys():
		var parts: PackedStringArray = key.split(">")
		if parts.size() == 2 and int(parts[1]) == target and int(parts[0]) != target:
			issuers.append(int(parts[0]))
	issuers.sort()
	return issuers


static func can_boycott(state: DiplomacyState, player: int, target: int) -> Dictionary:
	if player == target:
		return _deny("A crown cannot boycott itself.")
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return _deny("Only a Great Power can be boycotted.")
	if not state.has_relation(player, target):
		return _deny("No envoy has reached that court.")
	if state.relation(player, target).at_war:
		return _deny("We are already at war with that crown; no boycott is needed.")
	if _colony_tribes(state, player).is_empty():
		return _deny("A colony is required before a boycott can be declared.")
	if is_boycotting(state, player, target):
		return _deny("A boycott of that crown is already in force.")
	if state.claimed(player, target, "boycott"):
		return _deny("A boycott order was already given this turn.")
	return _allow()


## Applying a boycott also voids the target's subsidies to every colony of the
## issuer, because those courts no longer trade with it (wiki: diplomacy
## § GP–Tribe — Boycott, R6.2).
static func boycott(state: DiplomacyState, player: int, target: int) -> Dictionary:
	var check: Dictionary = can_boycott(state, player, target)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "boycott")
	state.boycotts["%d>%d" % [player, target]] = state.turn
	state.record_event("boycottSet", player, target)
	for tribe: int in _colony_tribes(state, player):
		state.cancel_subsidy(target, tribe)
	return {
		"ok": true,
		"reason": "",
		"message": "Our colonies are closed to %s; its trade with them ends." % (
			FactionCatalog.name_of(target)
		),
	}


static func can_revoke_boycott(
	state: DiplomacyState, player: int, target: int
) -> Dictionary:
	if not is_boycotting(state, player, target):
		return _deny("No boycott of that crown is in force.")
	if state.claimed(player, target, "boycott"):
		return _deny("A boycott order was already given this turn.")
	return _allow()


static func revoke_boycott(state: DiplomacyState, player: int, target: int) -> Dictionary:
	var check: Dictionary = can_revoke_boycott(state, player, target)
	if not bool(check["ok"]):
		return check
	state.claim(player, target, "boycott")
	state.boycotts.erase("%d>%d" % [player, target])
	state.record_event("boycottRevoked", player, target)
	return {
		"ok": true,
		"reason": "",
		"message": "The boycott of %s is lifted." % FactionCatalog.name_of(target),
	}


## War severs every commercial tie between the two crowns: subsidies both ways,
## the favoured-trading pact and any boycott in either direction (wiki:
## diplomacy § GP–Tribe — Boycott, R6.4; world-market § FTP — breaks on war).
static func sever(state: DiplomacyState, a: int, b: int) -> void:
	if state == null:
		return
	state.cancel_subsidy(a, b)
	state.cancel_subsidy(b, a)
	if state.ftps.erase(state.pair_key(a, b)):
		state.record_event("ftpRevoked", a, b, {"cause": "war"})
	for pair: Vector2i in [Vector2i(a, b), Vector2i(b, a)]:
		if state.boycotts.erase("%d>%d" % [pair.x, pair.y]):
			state.record_event("boycottRevoked", pair.x, pair.y, {"cause": "war"})


## Installs every crown's trade terms on the shared market. The market is pure
## data; the caller supplies the world so a subsidy can find its court's goods.
static func apply_terms(
	state: DiplomacyState, world: WorldMap, market: WorldMarket
) -> void:
	if market == null:
		return
	if state == null:
		market.clear_terms()
		return
	var terms: Dictionary = market_terms(state, world)
	for faction: int in terms.keys():
		market.set_terms(faction, terms[faction])


## Faction -> {"buy": {commodity|"*": multiplier}, "sell": {...}} for every
## Great Power. Includes every crown so a rival's trade obeys the same rules.
static func market_terms(state: DiplomacyState, world: WorldMap = null) -> Dictionary:
	var terms: Dictionary = {}
	if state == null:
		return terms
	var produce: Dictionary = _produce_by_faction(world)
	for faction: int in FactionCatalog.great_power_ids():
		terms[faction] = faction_terms(state, produce, faction)
	return terms


## One crown's terms. "*" carries pacts and boycotts across every commodity; a
## subsidy writes its own commodity rates for the goods that court produces.
static func faction_terms(
	state: DiplomacyState, produce: Dictionary, faction: int
) -> Dictionary:
	var buy: Dictionary = {"*": 1.0}
	var sell: Dictionary = {"*": 1.0}
	if state == null:
		return {"buy": buy, "sell": sell}
	var partners: Array[int] = ftps_of(state, faction)
	buy["*"] = 1.0 - DiplomacyCatalog.FTP_TERMS * float(partners.size())
	sell["*"] = 1.0 + DiplomacyCatalog.FTP_TERMS * float(partners.size())
	for key: String in state.subsidies.keys():
		var parts: PackedStringArray = key.split(">")
		if parts.size() != 2 or int(parts[0]) != faction:
			continue
		var percent: int = int(state.subsidies[key])
		var surcharge: float = 1.0 + float(percent) / 100.0
		var discount: float = 1.0 - float(percent) / 100.0
		for id: String in _produce_of(produce, int(parts[1])):
			buy[id] = maxf(float(buy.get(id, 1.0)), surcharge)
			sell[id] = minf(float(sell.get(id, 1.0)), discount)
	var boycotts: int = boycotts_against(state, faction).size()
	buy["*"] = float(buy["*"]) + DiplomacyCatalog.BOYCOTT_TERMS * float(boycotts)
	sell["*"] = float(sell["*"]) - DiplomacyCatalog.BOYCOTT_TERMS * float(boycotts)
	buy["*"] = clampf(float(buy["*"]), DiplomacyCatalog.TERMS_BUY_MIN, DiplomacyCatalog.TERMS_BUY_MAX)
	sell["*"] = clampf(float(sell["*"]), DiplomacyCatalog.TERMS_SELL_MIN, DiplomacyCatalog.TERMS_SELL_MAX)
	return {"buy": buy, "sell": sell}


## One crown's terms with the map's commodity detail (UI and tests).
static func terms_for_court(
	state: DiplomacyState, world: WorldMap, faction: int
) -> Dictionary:
	return faction_terms(state, _produce_by_faction(world), faction)


## Commodities the faction's provinces can produce, keyed by faction, from the
## map's resource table. No world (a rules fixture) means no commodity rates.
static func _produce_by_faction(world: WorldMap) -> Dictionary:
	var produce: Dictionary = {}
	if world == null:
		return produce
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province.owner < 0:
				continue
			var ids: Dictionary = produce.get(province.owner, {})
			for tile: Vector2i in province.tiles:
				var id: String = Extraction.commodity_for_resource(model.resource_at(tile.x, tile.y))
				if not id.is_empty():
					ids[id] = true
			produce[province.owner] = ids
	return produce


static func _produce_of(produce: Dictionary, faction: int) -> Array[String]:
	var ids: Array[String] = []
	var raw: Variant = produce.get(faction, {})
	if typeof(raw) != TYPE_DICTIONARY:
		return ids
	for id: Variant in (raw as Dictionary).keys():
		ids.append(String(id))
	ids.sort()
	return ids


static func _colony_tribes(state: DiplomacyState, gp: int) -> Array[int]:
	var tribes: Array[int] = []
	if state == null:
		return tribes
	for tribe: int in state.colonies.keys():
		if int(state.colonies[tribe]) == gp:
			tribes.append(tribe)
	tribes.sort()
	return tribes


static func _accepts_ftp(record: DiplomacyRelation) -> bool:
	if record == null:
		return false
	return record.score >= DiplomacyCatalog.FTP_MIN_SCORE


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
