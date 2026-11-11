extends GdToolsTest
## Rival courts work the whole court menu: overtures, alliances, trade pacts,
## boycotts, subsidies, foreign aid and alliance breaks, every one legal by the
## same rules the player calls (wiki: diplomacy § GP AI policy, § Diplomatic
## Order Types; DR-20261110-15).

const AiFixture = preload("res://tests/ai_fixture.gd")

var state: DiplomacyState
var config: AiConfig
var ai_state: AiState


func before_each() -> void:
	state = DiplomacyState.new()
	state.reset(1)
	state.human_faction = 0
	config = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	config.personality = AiPersonality.NEUTRAL
	config.agenda_traits = AiAgenda.NEUTRAL
	ai_state = AiState.new()


func test_every_court_menu_order_has_a_rival_policy() -> void:
	var menu: Array[String] = [
		DiplomacyOrders.KIND_WAR,
		DiplomacyOrders.KIND_PEACE,
		DiplomacyOrders.KIND_ALLIANCE,
		DiplomacyOrders.KIND_BREAK,
		DiplomacyOrders.KIND_OVERTURE,
		DiplomacyOrders.KIND_AID,
		DiplomacyOrders.KIND_SUBSIDY,
		DiplomacyOrders.KIND_CANCEL_SUBSIDY,
		DiplomacyOrders.KIND_FTP,
		DiplomacyOrders.KIND_REVOKE_FTP,
		DiplomacyOrders.KIND_BOYCOTT,
		DiplomacyOrders.KIND_REVOKE_BOYCOTT,
	]
	var planned: Array[String] = AiDiplomacyPlanner.kinds()
	assert_eq(planned.size(), menu.size(), "no order kind is left out of the rival menu")
	for kind: String in menu:
		assert_true(planned.has(kind), "%s has a rival policy" % kind)


func test_a_warm_rival_signs_a_trade_pact_with_a_fellow_court() -> void:
	# Turn one takes the free Non-Aggression Pact; Join Empire stays closed to a
	# Great Power still holding four provinces, so the next turn spends its one
	# order on the favoured trading pact (wiki: world-market § FTP).
	state.ensure_relation(2, 3, 1)
	state.relation(2, 3).score = 70.0
	_stage(2, 3, DiplomacyCatalog.STAGE_EMBASSY)
	var world: Array[int] = [0, 2, 3, 3, 3, 3]
	var first: Dictionary = _run(world, [[2, 3, 70.0]], 1)
	assert_eq(String(_action(first, 2)["kind"]), AiDiplomacyPlanner.KIND_OVERTURE)
	assert_eq(String(_action(first, 2)["stage"]), DiplomacyCatalog.STAGE_NAP)
	assert_eq(state.overture(2, 3), DiplomacyCatalog.STAGE_NAP, "a fellow court answers")
	# The warmer court, acting later in the same pass, spends its one order on
	# the trade pact the treaty just unlocked.
	assert_eq(String(_action(first, 3)["kind"]), AiDiplomacyOffers.KIND_FTP)
	assert_true(DiplomacyTrade.is_ftp(state, 2, 3), "the pact is signed at once")
	assert_true(String(_record(first, 3)["message"]).contains("favoured trading pact"))


func test_a_warm_rival_sends_aid_and_pays_from_its_own_purse() -> void:
	state.ensure_relation(2, 3, 1)
	state.relation(2, 3).score = 60.0
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_state.note_war(2, 3, 1)
	var result: Dictionary = _run([0, 2, 3, 3, 3, 3], [], 1)
	var action: Dictionary = _action(result, 2)
	assert_eq(String(action["kind"]), AiDiplomacyOffers.KIND_AID)
	assert_eq(int(action["amount"]), DiplomacyCatalog.GRANT_AID_STEP)
	assert_eq(int(action["target"]), 3)
	assert_true(state.relation(2, 3).score > 60.0, "the court remembers the gift")
	assert_true(_event("grantAid"), "the shared aid rules made the transfer")


func test_aid_stops_when_the_purse_cannot_cover_it() -> void:
	state.ensure_relation(2, 3, 1)
	state.relation(2, 3).score = 60.0
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state, AiFixture.world([0, 2, 3, 3, 3, 3]), 1,
		_context({2: 10, 3: 40})
	)
	assert_true((plan["action"] as Dictionary).is_empty())
	assert_eq(_offer_blocked(plan, AiDiplomacyOffers.KIND_AID), "The treasury cannot cover that aid.")


func test_a_rival_subsidises_a_minor_it_wants_close() -> void:
	state.ensure_relation(2, 6, 1)
	state.relation(2, 6).score = 70.0
	_stage(2, 6, DiplomacyCatalog.STAGE_NAP)
	var result: Dictionary = _run([0, 0, 0, 2, 6], [], 1)
	var action: Dictionary = _action(result, 2)
	assert_eq(String(action["kind"]), AiDiplomacyOffers.KIND_SUBSIDY)
	assert_eq(int(state.subsidy(2, 6)), int(action["amount"]))
	assert_eq(int(state.subsidy(2, 6)), DiplomacyCatalog.SUBSIDY_MIN)


func test_a_rival_ends_a_subsidy_once_the_friendship_cools() -> void:
	state.ensure_relation(2, 6, 1)
	state.relation(2, 6).score = 40.0
	_stage(2, 6, DiplomacyCatalog.STAGE_NAP)
	state.set_subsidy(2, 6, 10)
	ai_state.note_war(2, 6, 1)
	var result: Dictionary = _run([0, 0, 0, 2, 6], [], 2, {2: 3})
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_CANCEL_SUBSIDY)
	assert_eq(state.subsidy(2, 6), 0, "the shared rules end the subsidy")


func test_a_rival_too_weak_to_fight_boycotts_a_rival_it_has_fallen_out_with() -> void:
	state.ensure_relation(2, 3, 1)
	state.relation(2, 3).score = 30.0
	state.set_colony(9, 2)
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_state.economy_for(2).treasury = 0
	ai_state.note_war(2, 3, 1)
	var result: Dictionary = _run([0, 2, 3, 3, 3, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_BOYCOTT)
	assert_true(DiplomacyTrade.is_boycotting(state, 2, 3), "the colonies close at once")
	assert_true(String(_record(result, 2)["message"]).contains("closes its colonies"))


func test_a_recovered_standing_lifts_the_boycott() -> void:
	state.ensure_relation(2, 3, 1)
	state.relation(2, 3).score = 65.0
	state.set_colony(9, 2)
	state.boycotts["2>3"] = 1
	state.ftps[state.pair_key(2, 3)] = 1
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_state.economy_for(2).treasury = 0
	ai_state.note_war(2, 3, 1)
	var result: Dictionary = _run([0, 2, 3, 3, 3, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_REVOKE_BOYCOTT)
	assert_false(DiplomacyTrade.is_boycotting(state, 2, 3))


func test_a_pact_that_no_longer_matches_the_standing_is_revoked() -> void:
	state.ensure_relation(2, 3, 1)
	state.relation(2, 3).score = 30.0
	state.ftps[state.pair_key(2, 3)] = 1
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_state.economy_for(2).treasury = 0
	ai_state.note_war(2, 3, 1)
	var result: Dictionary = _run([0, 2, 3, 3, 3, 3], [], 2)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_REVOKE_FTP)
	assert_false(DiplomacyTrade.is_ftp(state, 2, 3))


func test_an_alliance_the_court_no_longer_means_is_broken() -> void:
	state.ensure_relation(2, 3, 1)
	state.relation(2, 3).score = 60.0
	state.relation(2, 3).formal_alliance = true
	ai_state.note_war(2, 3, 1)
	var result: Dictionary = _run([0, 2, 2, 2, 2, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_BREAK)
	assert_false(state.relation(2, 3).formal_alliance, "the treaty is dissolved")
	assert_true(String(_record(result, 2)["message"]).contains("breaks its alliance"))


func test_a_trade_pact_offer_to_the_human_court_waits_for_the_answer() -> void:
	state.ensure_relation(0, 2, 1)
	state.relation(0, 2).score = 70.0
	_stage(0, 2, DiplomacyCatalog.STAGE_NAP)
	var result: Dictionary = _run([0, 0, 0, 0, 2, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_FTP)
	assert_true(bool(_action(result, 2)["propose"]), "the human keeps consent")
	assert_false(DiplomacyTrade.is_ftp(state, 0, 2), "nothing is signed yet")
	assert_eq(state.pending_offers.size(), 1)
	assert_eq(String(state.pending_offers[0]["kind"]), DiplomacyProposals.KIND_FTP)
	assert_true(String(_record(result, 2)["message"]).contains("favoured trading pact"))
	var answer: Dictionary = DiplomacyProposals.resolve_human(state, null, true)
	assert_true(bool(answer.get("accepted", false)), answer.get("reason", ""))
	assert_true(DiplomacyTrade.is_ftp(state, 0, 2), "the court's answer signs the pact")


func test_one_sided_acts_and_consent_offers_are_told_apart() -> void:
	# A new order kind must reach the rival courts the turn it reaches the panel:
	# either through the court queue or as a one-sided act.
	var one_sided: Array[String] = [
		DiplomacyOrders.KIND_AID,
		DiplomacyOrders.KIND_BOYCOTT,
		DiplomacyOrders.KIND_REVOKE_BOYCOTT,
		DiplomacyOrders.KIND_SUBSIDY,
		DiplomacyOrders.KIND_CANCEL_SUBSIDY,
		DiplomacyOrders.KIND_REVOKE_FTP,
		DiplomacyOrders.KIND_BREAK,
	]
	for kind: String in AiDiplomacyOffers.KINDS:
		var queued: bool = DiplomacyProposals.knows(kind)
		assert_true(queued or one_sided.has(kind), "%s has a path to the human court" % kind)
	for kind: String in one_sided:
		assert_false(
			DiplomacyProposals.knows(kind),
			"%s needs no consent, so it never blocks the court" % kind
		)


## A court with a seat in the Old World and `faction`'s chart of a New World
## shore, so the envoy motive can be read off one court's own grid.
func _new_world_world() -> WorldMap:
	var old := MapModel.new()
	old.setup(4, 2)
	old.region_id = WorldMap.OLD_WORLD
	old.region_key = "old_world"
	var seat_tiles: Array[Vector2i] = [Vector2i(0, 0)]
	old.province[old.index_of(0, 0)] = 0
	old.provinces = [
		ProvinceState.create(0, "Seat", seat_tiles, Vector2.ZERO, 1, 2, true)
	]
	var shore := MapModel.new()
	shore.setup(4, 2)
	shore.region_id = WorldMap.NEW_WORLD
	shore.region_key = "new_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 2:
			tiles.append(Vector2i(x, y))
			shore.province[shore.index_of(x, y)] = 0
	shore.provinces = [
		ProvinceState.create(
			0, "Shore", tiles, Vector2.ZERO, tiles.size(),
			FactionCatalog.tribe_ids()[0], false
		)
	]
	var world := WorldMap.new()
	world.add_region(old)
	world.add_region(shore)
	return world


## A coast a rival has charted but cannot survey draws the envoy chain even with
## no deed priced and no merchant tech: the Consulate is what lets its Explorer
## read the shore (wiki: civilian-units § Overseas deployment; DR-20261111-05).
func test_a_charted_unsurveyed_shore_draws_the_envoy_chain() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var world: WorldMap = _new_world_world()
	state.ensure_relation(2, tribe, 1)
	var charts := CourtCharts.new()
	charts.setup(world, 0, {})
	var view: VisibilityModel = charts.model_for(2, WorldMap.NEW_WORLD)
	assert_eq(
		AiDiplomacyOffers._land_envoy_bonus(state, world, 2, tribe, 0, {}, charts), 0,
		"an uncharted coast asks for nothing"
	)
	view.reveal_landing(Vector2i(0, 0))
	assert_eq(
		AiDiplomacyOffers._land_envoy_bonus(state, world, 2, tribe, 0, {}, charts),
		AiDiplomacyOffers.LAND_ENVOY_BONUS, "a beachhead makes the Consulate worth paying for"
	)
	view.reveal_province(0)
	assert_eq(
		AiDiplomacyOffers._land_envoy_bonus(state, world, 2, tribe, 0, {}, charts), 0,
		"a surveyed coast needs no envoy for the survey"
	)


## Opens the turn pass with the given relation scores applied (default 50).
func _run(world: Array[int], scores: Array, turn: int, regiments: Dictionary = {}) -> Dictionary:
	for entry: Array in scores:
		state.ensure_relation(int(entry[0]), int(entry[1]), turn)
		state.relation(int(entry[0]), int(entry[1])).score = float(entry[2])
	return AiTurn.run(
		state, AiFixture.world(world), ai_state, turn, 0, 1500,
		{"regiments": regiments, "ships": {}}
	)


func _context(power: Dictionary) -> Dictionary:
	var context: Dictionary = AiFixture.context(power)
	context["treasury"] = {}
	context["tech"] = {}
	context["player"] = 0
	return context


## Both directions at one stage, as a signed overture lands.
func _stage(a: int, b: int, stage: String) -> void:
	state.set_overture(a, b, stage)
	state.set_overture(b, a, stage)


## The refusal the offers module recorded for one order kind.
func _offer_blocked(plan: Dictionary, kind: String) -> String:
	var offer: Dictionary = plan["candidates"][0].get("offer", {})
	for entry: Dictionary in offer.get("candidates", []):
		if String(entry.get("kind", "")) == kind:
			return String(entry.get("blocked", ""))
	return ""


func _action(run: Dictionary, faction: int) -> Dictionary:
	return _record(run, faction).get("action", {})


func _record(run: Dictionary, faction: int) -> Dictionary:
	for record: Dictionary in run["trace"]:
		if int(record["faction"]) == faction:
			return record
	return {}


func _event(kind: String) -> bool:
	for entry: Dictionary in state.events:
		if String(entry.get("kind", "")) == kind:
			return true
	return false
