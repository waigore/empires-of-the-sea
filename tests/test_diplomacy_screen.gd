extends GdToolsTest
## Integration: the map screen's court panel, orders and diplomacy phase.

const Fixture = preload("res://tests/map_fixture.gd")
const CourtFixture = preload("res://tests/civilian_fixture.gd")

## One mounted screen for the whole suite: under coverage a mount costs ~0.5 s
## and a re-seat from the pristine save ~0.15 s, so court cases share the chart
## and reset the session instead of remounting (`Fixture.suite_reset`). Folded
## tribe-contact pocket cases never touch `_screen`, so they skip the re-seat
## (docs/testing.md § Speed rules).
var mounted: MapScreen = null
var pristine: Dictionary = {}
var pristine_map: Array = []
## Set when this case has paid for a pristine re-seat; cleared in `before_each`.
var _chart_bound: bool = false


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)


func before_each() -> void:
	_chart_bound = false
	_tribe_before_each()


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	pristine = {}


## Court cases reach the chart through `_screen`; pocket tribe-contact cases
## that never ask never pay `suite_reset`.
func _attach() -> MapScreen:
	if _chart_bound and is_instance_valid(mounted):
		return mounted
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(mounted, pristine)
	_chart_bound = true
	return mounted


var _screen: MapScreen:
	get:
		return _attach()


func test_map_screen_starts_with_a_relation_web() -> void:
	assert_not_null(_screen.play.diplomacy)
	assert_eq(_screen.play.diplomacy.relations.size(), 111)
	assert_eq(
		_screen.play.diplomacy.overture(0, 1), DiplomacyCatalog.STAGE_EMBASSY
	)


func test_court_panel_opens_and_closes() -> void:
	var toasts_before: int = _screen.hud._toast_box.get_child_count()
	MapPlayDiplomacy.open(_screen.play)
	assert_true(_screen.hud.panels.is_diplomacy_open())
	assert_false(_screen.hud.panels.is_panel_open())
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before)
	DiplomacyHud.hide(_screen.hud.panels)
	assert_false(_screen.hud.panels.is_diplomacy_open())


## The court reads every crown's public power: the session's order of battle
## feeds the published score, and each Great Power row carries its band while a
## Minor Nation carries none (wiki: diplomacy § Great Power power score).
func test_the_court_reads_each_crowns_public_power() -> void:
	MapPlayDiplomacy.open(_screen.play)
	var panel: DiplomacyPanel = _screen.hud.panels.diplomacy_panel
	var orders: Dictionary = MapPlayCourt.public_orders(_screen.play)
	assert_eq(panel._power.size(), FactionCatalog.great_power_ids().size())
	assert_eq(
		int(panel._power[0]),
		AiPower.score(
			_screen.play.world,
			0,
			int(roundf(float((orders["strength"] as Dictionary).get(0, 0.0)))),
			int((orders["ships"] as Dictionary).get(0, 0))
		),
		"the panel reads the published score, not its own arithmetic"
	)
	assert_false(CourtRows.line(panel._power, 0, 1).is_empty(), "a rival Great Power carries a band")
	assert_true(CourtRows.line(panel._power, 0, 6).is_empty(), "a Minor Nation carries none")


## The rival pass weighs relative power by that same public order of battle, not
## by a head count: the planner's score for a crown is the published one the
## court panel prints (wiki: diplomacy § Great Power power score).
func test_the_rival_pass_weighs_power_the_published_way() -> void:
	var context: Dictionary = MapPlayDiplomacyAi._context(_screen.play)
	assert_false(
		(context.get("strengths", {}) as Dictionary).is_empty(),
		"the pass hands the planner the order of battle"
	)
	var shared: Dictionary = AiTurnRead.context(
		_screen.play.world, context, _screen.play.player_faction
	)
	var published: Dictionary = MapPlayDiplomacy.public_power(_screen.play)
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(
			int(shared["power"][faction]),
			int(published[faction]),
			"the planner and the panel read one score for %s"
			% FactionCatalog.name_of(faction)
		)


## The rival pass stamps the frontier crowns of every conquest-gap court
## (issue #1082): the crowns whose Old World land touches its own — the fronts
## its field army can walk to — so the buy-out and the white-peace answer can
## keep the war that sits on one.
func test_the_rival_pass_stamps_the_conquest_gap_frontier() -> void:
	var context: Dictionary = MapPlayDiplomacyAi._context(_screen.play)
	var frontier: Dictionary = context.get(AiFrontier.KEY, {})

	assert_false(frontier.is_empty(), "the shared pass hands the planners a frontier")
	for faction: int in FactionCatalog.great_power_ids():
		var expected: Array[int] = AiFrontier.crowns(_screen.play.world, faction)
		assert_eq(
			frontier.get(faction, []), expected,
			"%s's frontier is the crowns whose land touches its own"
			% FactionCatalog.name_of(faction)
		)
		for other: int in expected:
			assert_eq(
				FactionCatalog.type_of(other), FactionCatalog.Type.GREAT_POWER,
				"only a Great Power is a frontier crown"
			)


func test_orders_from_the_court_change_relations_and_toast() -> void:
	MapPlayDiplomacy.open(_screen.play)
	var toasts_before: int = _screen.hud._toast_box.get_child_count()
	MapPlayDiplomacy.on_order(_screen.play, DiplomacyOrders.KIND_WAR, 1, "")
	assert_true(_screen.play.diplomacy.relation(0, 1).at_war)
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)
	assert_true(_screen.hud.panels.is_diplomacy_open())
	MapPlayDiplomacy.on_order(_screen.play, DiplomacyOrders.KIND_PEACE, 1, "")
	assert_false(_screen.play.diplomacy.relation(0, 1).at_war)


func test_grant_aid_spends_treasury_and_refreshes_the_chip() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var before: int = economy.treasury
	MapPlayDiplomacy.open(_screen.play)
	MapPlayDiplomacy.on_order(_screen.play, DiplomacyOrders.KIND_AID, 1, "1000")
	assert_eq(economy.treasury, before - 1000)
	assert_eq(_screen.hud._treasury_value, economy.treasury)
	assert_eq(_screen.play.diplomacy.relation(0, 1).score, 55.0)


func test_end_turn_runs_relation_decay_and_keeps_turn_in_sync() -> void:
	_screen.play.diplomacy.relation(0, 1).score = 40.0
	# Keep rival declarations off this pair so the decay itself is under test;
	# rival proposals still wait for the court and are refused here.
	_screen.play.ai = AiState.new()
	for faction: int in FactionCatalog.great_power_ids():
		if faction != 0:
			_screen.play.ai.note_war(faction, 0, _screen.play.turn)
	MapPlayTurn.end_turn(_screen.play)
	while DiplomacyProposals.has_pending(_screen.play.diplomacy, 0):
		MapCourtOrders.apply(_screen.play, DiplomacyProposals.KIND_REFUSE, 0, "")
	assert_eq(_screen.play.diplomacy.relation(0, 1).score, 44.0)
	assert_eq(_screen.play.diplomacy.turn, _screen.play.turn)


func test_first_contact_requires_tile_visibility_in_a_tribe_province() -> void:
	assert_eq(_screen.play.diplomacy.relations_of(0).size(), 11)
	assert_true(MapPlayDiplomacy.sync_first_contact(_screen.play).is_empty())
	_screen._cycle_region()
	var province: ProvinceState = _tribe_province()
	assert_not_null(province)
	_screen.play.diplomacy.relations.erase(
		_screen.play.diplomacy.pair_key(0, province.owner)
	)
	assert_false(_screen.play.diplomacy.has_relation(0, province.owner))
	var visibility: VisibilityModel = _screen.play.visibility_by_region[1]
	var tile: Vector2i = province.tiles[0]
	visibility.raise_to(
		visibility.model.index_of(tile.x, tile.y), VisibilityModel.Level.FOGGED
	)
	var contacted: Array[int] = MapPlayDiplomacy.sync_first_contact(_screen.play)
	assert_true(contacted.has(province.owner))
	assert_true(_screen.play.diplomacy.has_relation(0, province.owner))


func test_a_march_into_foreign_land_needs_a_declared_war() -> void:
	var army: ArmyState = _field_army()
	assert_not_null(army, "a field army can be detached from the Home Army")
	var origin: int = army.province
	var target: int = _stage_on_foreign_border(army)
	assert_gt(target, -1, "the crown holds land on a foreign border")
	origin = army.province
	var owner: int = _screen.play.model.province_owner(target)
	_screen.play.diplomacy.ensure_relation(0, owner)

	_screen.play.army_layer.select(army)
	MapPlayArmies.select(_screen.play, army)
	var toasts_before: int = _screen.hud._toast_box.get_child_count()
	var tile: Vector2i = _screen.play.model.province_data(target).tiles[0]
	assert_true(MapPlayArmies.try_order(_screen.play, tile))
	assert_eq(army.province, origin, "peace refuses the invasion")
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)

	DiplomacyRules.declare_war(_screen.play.diplomacy, 0, owner)
	_screen.play.army_layer.select(army)
	MapPlayArmies.select(_screen.play, army)
	assert_true(MapPlayArmies.try_order(_screen.play, tile))
	assert_eq(army.province, target, "war lets the same march through")


## A Tribe's shore another crown has bought land in is barred by that deed, so
## the refusal names the crown instead of blaming a peace the crown may not be
## under (wiki: factions § Tribe — "unless another GP has invested in the
## province"; DR-20261120-05; REQ-P5-05).
func test_the_march_into_a_tribes_bought_land_names_the_deed() -> void:
	var model: MapModel = _screen.play.model
	var tribe: int = 9
	var bought: ProvinceState = model.provinces[0]
	bought.owner = tribe
	_screen.play.diplomacy.ensure_relation(0, tribe)
	assert_true(model.purchase_tile(bought.tiles[0], 1), "a rival's deed")
	var fallback: String = "Peace holds with the Aztec; declare war before invading."
	assert_eq(
		MapPlayArmies.refusal(_screen.play, bought.id, fallback),
		"Deeds in %s bar an undeclared march — %s has bought land there; declare war before invading."
		% [model.province_name(bought.id), FactionCatalog.name_of(1)]
	)
	var bare: ProvinceState = model.provinces[1]
	bare.owner = tribe
	assert_eq(
		MapPlayArmies.refusal(_screen.play, bare.id, fallback),
		fallback,
		"no deed, the order's own words"
	)


func test_join_empire_takes_the_absorbed_crowns_regiments() -> void:
	var play: PlaySession = _screen.play
	var state: DiplomacyState = play.diplomacy
	var minor: int = 6
	state.set_overture(0, minor, DiplomacyCatalog.STAGE_NAP)
	state.relation(0, minor).score = 80.0
	play.economy.economy.treasury = 200000
	var player_before: int = play.army_layer.regiment_count_all(0)
	var minor_before: int = play.army_layer.regiment_count_all(minor)
	assert_gt(minor_before, 0, "the Minor holds a garrison")
	var absorbed_ids: Array[int] = []
	for army: ArmyState in play.army_layer.armies:
		if army.owner == minor:
			absorbed_ids.append(army.id)

	MapCourtOrders.apply(
		play, DiplomacyOrders.KIND_OVERTURE, minor, DiplomacyCatalog.STAGE_JOIN_EMPIRE
	)

	assert_eq(play.army_layer.regiment_count_all(minor), 0, "no stranded regiments")
	assert_eq(
		play.army_layer.regiment_count_all(0),
		player_before + minor_before,
		"the winner takes every regiment"
	)
	var home_armies: int = 0
	for army: ArmyState in play.army_layer.armies:
		if army.owner != 0:
			continue
		if army.home:
			home_armies += 1
		if absorbed_ids.has(army.id):
			assert_false(army.home, "an absorbed Home Army becomes a field army")
			var marker: ArmyMarker = play.army_layer.marker_for(army)
			assert_not_null(marker, "the standard follows the regiments")
			assert_eq(marker.faction, 0, "the standard changes colours")
	assert_eq(home_armies, 1, "the winner still keeps exactly one Home Army")


func test_call_to_arms_suspends_the_turn_until_answered() -> void:
	var state: DiplomacyState = _screen.play.diplomacy
	var pact: DiplomacyRelation = state.relation(0, 2)
	pact.formal_alliance = true
	pact.score = 80.0
	CallToArms.freeze_alliances(state)
	DiplomacyRules.declare_war(state, 3, 2)
	assert_true(CallToArms.has_pending(state, 0))
	MapPlayDiplomacy.open(_screen.play)
	assert_true(_screen.hud.panels.diplomacy_panel._call_box.visible, "the court asks")
	var turn_before: int = _screen.play.turn
	MapPlayTurn.end_turn(_screen.play)
	assert_eq(_screen.play.turn, turn_before, "the calendar waits for the answer")
	assert_true(_screen.play.turn_suspended)
	MapPlayTurn.answer_call(_screen.play, true)
	assert_true(state.relation(0, 3).at_war, "joining means war on the aggressor")
	assert_eq(_screen.play.turn, turn_before + 1)
	assert_false(CallToArms.has_pending(state, 0))


func test_intervention_suspends_the_turn_until_answered() -> void:
	var state: DiplomacyState = _screen.play.diplomacy
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	assert_true(Intervention.has_pending(state, 0))
	MapPlayDiplomacy.open(_screen.play)
	assert_true(_screen.hud.panels.diplomacy_panel._call_box.visible, "the court asks")
	var turn_before: int = _screen.play.turn
	MapPlayTurn.end_turn(_screen.play)
	assert_eq(_screen.play.turn, turn_before, "the calendar waits for the answer")
	assert_true(_screen.play.turn_suspended)
	MapPlayTurn.answer_intervention(_screen.play, Intervention.KIND_PROTEST)
	assert_false(state.relation(0, 3).at_war)
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(_screen.play.turn, turn_before + 1)
	assert_false(Intervention.has_pending(state, 0))


## Wiki: diplomacy § Intervention — the choice is presented **once**, at war
## declaration time. Pressing Next Turn again re-opens the court but must not
## repeat the same war news, which reads as a fresh declaration every time.
func test_a_waiting_intervention_is_announced_once() -> void:
	var play: PlaySession = _screen.play
	play.diplomacy.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(play.diplomacy, 3, 6)
	MapPlayTurn.end_turn(play)
	assert_eq(_news_about("Genoa"), 1, "the court is told once")
	MapPlayTurn.end_turn(play)
	assert_eq(_news_about("Genoa"), 1, "a second press repeats nothing")
	assert_true(play.turn_suspended, "the turn still waits for the answer")


## The AI pass raises a new decision in its own words, so the resolver opening
## the panel on the same press adds no second despatch.
func test_the_resolver_does_not_repeat_the_passes_news() -> void:
	var play: PlaySession = _screen.play
	play.diplomacy.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(play.diplomacy, 3, 6)
	MapPlayDiplomacyConsent.mark_announced(play)
	MapPlayDiplomacyConsent.show_intervention(play)
	assert_eq(_news_about("Genoa"), 0, "the panel adds no second despatch")


## Consent and AI extracts keep their own doors: null guards, a waiting call and
## proposal, blocked court business, and a rival absorb that recolours units
## (REQ-P3-01 — soft pressure after the charted-land AI split).
func test_consent_and_ai_extracts_keep_their_own_doors() -> void:
	var play: PlaySession = _screen.play
	var state: DiplomacyState = play.diplomacy
	play.diplomacy = null
	MapPlayDiplomacyConsent.mark_announced(play)
	MapPlayDiplomacyConsent.show_call(play)
	MapPlayDiplomacyConsent.show_intervention(play)
	MapPlayDiplomacyConsent.show_offer(play)
	play.diplomacy = state
	# Nothing waits yet: each show returns after the empty pending check.
	MapPlayDiplomacyConsent.show_call(play)
	MapPlayDiplomacyConsent.show_intervention(play)
	MapPlayDiplomacyConsent.show_offer(play)

	var pact: DiplomacyRelation = state.relation(0, 2)
	pact.formal_alliance = true
	pact.score = 80.0
	CallToArms.freeze_alliances(state)
	DiplomacyRules.declare_war(state, 3, 2)
	assert_true(CallToArms.has_pending(state, 0))
	MapPlayDiplomacyConsent.mark_announced(play)
	assert_true(play.announced_decisions.has("call:3:2"))
	MapPlayDiplomacyConsent.show_call(play)
	MapPlayDiplomacy.on_order(play, DiplomacyOrders.KIND_WAR, 1, "")
	assert_true(CallToArms.has_pending(state, 0), "a waiting call blocks other business")
	assert_false(state.relation(0, 1).at_war)

	state.relation(0, 4).score = 80.0
	state.set_overture(0, 4, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(4, 0, DiplomacyCatalog.STAGE_NAP)
	assert_true(
		DiplomacyProposals.queue(
			state, play.world, 4, DiplomacyProposals.KIND_ALLIANCE
		)["ok"]
	)
	# Answer the call while a proposal still waits: the ladder re-opens on it.
	play.turn_suspended = true
	MapPlayTurn.answer_call(play, false)
	assert_true(DiplomacyProposals.has_pending(state, 0))
	MapPlayDiplomacyConsent.show_offer(play)
	MapPlayDiplomacy.on_order(play, DiplomacyOrders.KIND_WAR, 1, "")
	assert_true(DiplomacyProposals.has_pending(state, 0), "a proposal blocks other business")
	MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, 4, "")

	# Intervention blocks the same way once a deed invites the court.
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	assert_true(Intervention.has_pending(state, 0))
	MapPlayDiplomacy.on_order(play, DiplomacyOrders.KIND_WAR, 1, "")
	assert_true(Intervention.has_pending(state, 0))
	assert_false(state.relation(0, 1).at_war)
	MapPlayTurn.answer_intervention(play, Intervention.KIND_PROTEST)

	# Rival absorb: units change colour and the chart rebuilds.
	var minor: int = 7
	var minor_before: int = play.army_layer.regiment_count_all(minor)
	var player_before: int = play.army_layer.regiment_count_all(0)
	assert_gt(minor_before, 0, "the Minor holds a garrison")
	MapPlayDiplomacyAi._apply_map_changes(
		play, [{"faction": 0, "result": {"absorbed": minor, "map_changed": true}}]
	)
	assert_eq(play.army_layer.regiment_count_all(minor), 0, "no stranded regiments")
	assert_eq(
		play.army_layer.regiment_count_all(0),
		player_before + minor_before,
		"the winner takes every regiment"
	)


## Toasts that name `needle`.
func _news_about(needle: String) -> int:
	var total: int = 0
	for child: Node in _screen.hud._toast_box.get_children():
		for node: Node in child.get_children():
			if node is Label and (node as Label).text.contains(needle):
				total += 1
	return total


## Wiki: tech-tree-diplomacy-civilian — a protest against an aggressor holding
## Propaganda costs 5, not 10. The court must read the aggressor's ledger.
func test_propaganda_softens_the_protest_the_court_plays() -> void:
	var play: PlaySession = _screen.play
	play.diplomacy.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	if play.ai == null:
		play.ai = AiState.new()
	play.ai.economy_for(3).tech_unlocked["propaganda"] = true
	DiplomacyRules.declare_war(play.diplomacy, 3, 6)
	assert_true(Intervention.has_pending(play.diplomacy, 0))
	MapCourtOrders.apply(play, Intervention.KIND_PROTEST, 0, "")
	assert_eq(play.diplomacy.relation(0, 3).score, 45.0, "−5 against Propaganda")


func test_a_plain_protest_still_costs_ten() -> void:
	var play: PlaySession = _screen.play
	play.diplomacy.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	if play.ai == null:
		play.ai = AiState.new()
	DiplomacyRules.declare_war(play.diplomacy, 3, 6)
	assert_true(Intervention.has_pending(play.diplomacy, 0))
	MapCourtOrders.apply(play, Intervention.KIND_PROTEST, 0, "")
	assert_eq(play.diplomacy.relation(0, 3).score, 40.0, "−10 without Propaganda")


## Wiki: diplomacy § GP–Minor Rules § Intervention — a deed in the victim's
## provinces invites the offer without an embassy, and the court order path
## must hand the rules its world (REQ-P2-03).
func test_a_court_order_war_reaches_the_deed_holder() -> void:
	var play: PlaySession = _screen.play
	play.world = _deed_world(1)
	MapCourtOrders.apply(play, DiplomacyOrders.KIND_WAR, 6, "")
	assert_true(play.diplomacy.relation(0, 6).at_war, "the war is declared")
	assert_true(_intervention_answers(play.diplomacy) > 0, "the deed holder answers")


func test_a_war_without_a_deed_holder_invites_nobody() -> void:
	var play: PlaySession = _screen.play
	play.world = _deed_world(-1)
	MapCourtOrders.apply(play, DiplomacyOrders.KIND_WAR, 6, "")
	assert_true(play.diplomacy.relation(0, 6).at_war, "the war is declared")
	assert_eq(_intervention_answers(play.diplomacy), 0, "no court held a deed")


## Tiny world whose second province answers to Minor Nation 6, with a deed sold
## to `buyer` (-1 for none).
func _deed_world(buyer: int) -> WorldMap:
	var model: MapModel = CourtFixture.build()
	var province: ProvinceState = model.provinces[1]
	province.owner = 6
	if buyer >= 0:
		assert_true(model.purchase_tile(province.tiles[0], buyer), "a deed is signed")
	var world := WorldMap.new()
	world.add_region(model)
	return world


## Every way an AI court can answer a declaration: join, stand aside or protest.
static func _intervention_answers(state: DiplomacyState) -> int:
	var total: int = 0
	for event: Dictionary in state.events:
		var kind: String = String(event.get("kind", ""))
		if kind in [
			"interventionIntervened", "interventionDoNothing", "interventionProtest",
		]:
			total += 1
	return total


func test_court_intent_router_sends_orders_and_call_answers() -> void:
	MapCourtOrders.apply(_screen.play, DiplomacyOrders.KIND_WAR, 1, "")
	assert_true(_screen.play.diplomacy.relation(0, 1).at_war, "orders reach the court")
	var state: DiplomacyState = _screen.play.diplomacy
	var pact: DiplomacyRelation = state.relation(0, 4)
	pact.formal_alliance = true
	pact.score = 80.0
	CallToArms.freeze_alliances(state)
	DiplomacyRules.declare_war(state, 5, 4)
	MapCourtOrders.apply(_screen.play, CallToArms.KIND_JOIN, 5, "")
	assert_true(state.relation(0, 5).at_war, "a call answer reaches the turn resolver")


func test_a_rival_proposal_suspends_the_turn_until_the_court_answers() -> void:
	var state: DiplomacyState = _screen.play.diplomacy
	state.relation(0, 2).score = 80.0
	# The alliance rides on the pact (wiki: diplomacy § Alliances; issue #750).
	state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
	assert_true(
		DiplomacyProposals.queue(
			state, _screen.play.world, 2, DiplomacyProposals.KIND_ALLIANCE
		)["ok"]
	)
	var turn_before: int = _screen.play.turn
	MapPlayTurn.end_turn(_screen.play)
	assert_true(_screen.play.turn_suspended, "the calendar waits for the answer")
	assert_eq(_screen.play.turn, turn_before)
	assert_true(
		_screen.hud.panels.diplomacy_panel._call_box.visible, "the court asks"
	)
	MapCourtOrders.apply(_screen.play, DiplomacyProposals.KIND_ACCEPT, 2, "")
	assert_true(state.relation(0, 2).formal_alliance, "the answer signs the treaty")
	assert_false(_screen.play.turn_suspended)
	assert_eq(_screen.play.turn, turn_before + 1)
	assert_false(DiplomacyProposals.has_pending(state, 0))


func test_refusing_a_rival_proposal_starts_the_improve_relations_cooldown() -> void:
	var play: PlaySession = _screen.play
	var state: DiplomacyState = play.diplomacy
	play.ai = AiState.new()
	state.set_overture(2, 0, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyProposals.queue(
		state, play.world, 2, DiplomacyProposals.KIND_OVERTURE,
		DiplomacyCatalog.STAGE_NAP
	)
	var turn_before: int = play.turn
	MapPlayTurn.end_turn(play)
	MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, 2, "")
	assert_eq(state.overture(0, 2), DiplomacyCatalog.STAGE_EMBASSY, "nothing is signed")
	assert_true(play.ai.overture_on_cooldown(2, 0, turn_before, 2))


func test_a_rival_peace_offer_suspends_the_turn_and_the_answer_ends_the_war() -> void:
	var play: PlaySession = _screen.play
	var state: DiplomacyState = play.diplomacy
	play.ai = AiState.new()
	DiplomacyRules.declare_war(state, 2, 0)
	DiplomacyProposals.queue(state, play.world, 2, DiplomacyProposals.KIND_PEACE)
	var turn_before: int = play.turn
	MapPlayTurn.end_turn(play)
	assert_true(play.turn_suspended, "the calendar waits for the answer")
	assert_eq(play.turn, turn_before)
	assert_true(state.relation(0, 2).at_war, "the war holds until the answer")
	MapCourtOrders.apply(play, DiplomacyProposals.KIND_ACCEPT, 2, "")
	assert_false(state.relation(0, 2).at_war, "the answer concludes the peace")
	assert_false(play.turn_suspended)
	assert_eq(play.turn, turn_before + 1)
	assert_true(
		play.ai.peace_on_cooldown(2, 0, turn_before, 3),
		"the answer starts the peace-offer cooldown (DR-20261109-07)"
	)


func test_accepting_a_peace_offer_calls_off_that_turns_battle() -> void:
	# wiki: diplomacy § Court proposals — accepting ends the war for that same
	# turn's movement and combat, so the province is not stormed after the
	# answer (DR-20261109-07).
	var play: PlaySession = _screen.play
	var state: DiplomacyState = play.diplomacy
	play.ai = AiState.new()
	for faction: int in FactionCatalog.great_power_ids():
		if faction != 0:
			play.ai.note_overture(faction, 0, play.turn)
	var army: ArmyState = _field_army()
	assert_not_null(army, "a field army is on the map")
	var province: int = _stage_on_great_power_border(army)
	assert_true(province >= 0, "the army has a Great Power neighbour")
	var owner: int = play.model.province_owner(province)
	DiplomacyRules.declare_war(state, owner, 0)
	assert_true(bool(play.army_layer.order(army, province, true).get("ok", false)))
	assert_eq(army.province, province, "the army has stormed the province")
	assert_true(
		DiplomacyProposals.queue(
			state, play.world, owner, DiplomacyProposals.KIND_PEACE
		)["ok"]
	)
	MapPlayTurn.end_turn(play)
	assert_true(play.turn_suspended, "the calendar waits for the answer")
	MapCourtOrders.apply(play, DiplomacyProposals.KIND_ACCEPT, owner, "")
	assert_false(state.relation(0, owner).at_war, "the answer concludes the peace")
	assert_eq(
		play.model.province_owner(province), owner,
		"no battle runs after the peace is accepted"
	)
	assert_true(play.army_layer.armies.has(army), "the storming army survives the peace")


func test_a_trade_pact_reaches_the_ledger_prices() -> void:
	_screen.play.diplomacy.relation(0, 1).score = 80.0
	MapPlayDiplomacy.open(_screen.play)
	MapPlayDiplomacy.on_order(_screen.play, DiplomacyOrders.KIND_FTP, 1, "")
	assert_true(DiplomacyTrade.is_ftp(_screen.play.diplomacy, 0, 1))
	var market: WorldMarket = _screen.economy.market
	assert_true(market != null)
	assert_almost_eq(market.term_multiplier(0, "timber", true), 0.95, 0.001)


func _field_army() -> ArmyState:
	for army: ArmyState in _screen.play.army_layer.armies.duplicate():
		if army.owner == 0 and army.home and army.count() > 1:
			var ids: Array[String] = []
			for regiment: String in army.regiments:
				ids.append(regiment)
			_screen.play.army_layer.split(army, ids.slice(0, 1))
	for army: ArmyState in _screen.play.army_layer.armies:
		if army.owner == 0 and not army.home:
			return army
	return null


## Moves the field army onto a crown province that borders foreign land (the
## generated map no longer guarantees the capital province itself does) and
## returns the foreign neighbour.
func _stage_on_foreign_border(army: ArmyState) -> int:
	return _stage_on_border(army, false)


func _stage_on_great_power_border(army: ArmyState) -> int:
	return _stage_on_border(army, true)


func _stage_on_border(army: ArmyState, great_power_only: bool) -> int:
	var model: MapModel = _screen.play.model
	for province: ProvinceState in model.provinces:
		if province.owner != 0:
			continue
		var target: int = _adjacent_foreign_province(
			army, great_power_only, province.id
		)
		if target >= 0:
			army.province = province.id
			return target
	return -1


func _adjacent_foreign_province(
	army: ArmyState, great_power_only: bool = false, from_province: int = -1
) -> int:
	var model: MapModel = _screen.play.model
	var origin: int = army.province if from_province < 0 else from_province
	for neighbor: int in MapGeo.province_neighbors(model, origin):
		var owner: int = model.province_owner(neighbor)
		if owner == 0 or owner == MapModel.NO_ID:
			continue
		if not great_power_only:
			return neighbor
		if FactionCatalog.type_of(owner) == FactionCatalog.Type.GREAT_POWER:
			return neighbor
	return -1


func _tribe_province() -> ProvinceState:
	for province: ProvinceState in _screen.play.world.region(1).provinces:
		if FactionCatalog.type_of(province.owner) == FactionCatalog.Type.TRIBE:
			return province
	return null


# --- folded: GP-Tribe first contact ---
## First contact for rival crowns (wiki: diplomacy § GP–Tribe first contact;
## map pass: MapPlayTribeContact), merged from test_tribe_contact: the same
## mounted court boot pays the discovery rules and the turn close.

const HUMAN: int = 0
const TURN: int = 4
const NEW_WORLD: int = 1

var _rival: int = 0
var _tribe: int = 0
var _other_tribe: int = 0
var _state: DiplomacyState = null


func _tribe_before_each() -> void:
	_rival = FactionCatalog.great_power_ids()[1]
	_tribe = FactionCatalog.tribe_ids()[0]
	_other_tribe = FactionCatalog.tribe_ids()[1]
	_state = DiplomacyState.new()
	_state.initialize(TURN)


## One New World region, one province per entry. Its baseline is unknown, so a
## court discovers a tribe province only by charting it.
func _world(owners: Array[int]) -> WorldMap:
	var model := MapModel.new()
	model.setup(maxi(owners.size(), 1), 1)
	model.region_id = FactionCatalog.NEW_WORLD
	model.region_key = FactionCatalog.REGION_KEYS[FactionCatalog.NEW_WORLD]
	for index in owners.size():
		var tiles: Array[Vector2i] = [Vector2i(index, 0)]
		var province := ProvinceState.create(
			index,
			"P%d" % index,
			tiles,
			Vector2(float(index), 0.0),
			1,
			owners[index],
			false
		)
		model.provinces.append(province)
	var world := WorldMap.new()
	world.add_region(model)
	return world


func _charts(owners: Array[int], human_views: Dictionary = {}) -> CourtCharts:
	return _charts_over(_world(owners), human_views)


func _charts_over(world: WorldMap, human_views: Dictionary = {}) -> CourtCharts:
	var charts := CourtCharts.new()
	charts.setup(world, HUMAN, human_views)
	return charts


func _reveal(charts: CourtCharts, faction: int, province: int) -> void:
	charts.reveal_province(faction, 0, province)


# --- discovery ---------------------------------------------------------------


## A court that has charted nothing of the New World holds no Tribal court, even
## though the Tribe's provinces exist in the world.
func test_an_uncharted_tribe_is_never_contacted() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	assert_eq(TribeContact.charted_tribes(charts, _rival), [] as Array[int])
	assert_eq(TribeContact.apply(charts, _state, HUMAN, TURN), [] as Array[Dictionary])
	assert_false(_state.has_relation(_rival, _tribe))


## One charted province opens the relation once, `AT_PEACE` / 50 / Neutral, with
## `sinceTurn` the turn that resolved and no war flag.
func test_a_charted_province_opens_first_contact() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	var found: Array[Dictionary] = TribeContact.apply(charts, _state, HUMAN, TURN)
	assert_eq(found.size(), 1)
	assert_eq(int(found[0]["faction"]), _rival)
	assert_eq(int(found[0]["tribe"]), _tribe)
	var record: DiplomacyRelation = _state.relation(_rival, _tribe)
	assert_not_null(record)
	assert_false(record.at_war, "first contact is peace, not war")
	assert_eq(record.score, 50.0)
	assert_eq(record.level(), "Neutral")
	assert_eq(record.since_turn, TURN)
	assert_false(record.formal_alliance)


## A crown whose leader publishes the Tribe lean opens on score 60, while a crown
## with no diplomacy row still opens at the Neutral equilibrium (wiki:
## leader-bonuses § Bonus Table — Isabella).
func test_a_leader_with_the_tribe_lean_opens_first_contact_at_sixty() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	var found: Array[Dictionary] = TribeContact.apply(
		charts, _state, HUMAN, TURN, {_rival: "isabella"}
	)
	assert_eq(found.size(), 1)
	var record: DiplomacyRelation = _state.relation(_rival, _tribe)
	assert_eq(record.score, 60.0, "Spain opens friendlier than the equilibrium")
	assert_false(record.at_war)


func test_a_crown_without_the_tribe_lean_opens_at_the_equilibrium() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	TribeContact.apply(charts, _state, HUMAN, TURN, {_rival: "victoria"})
	var record: DiplomacyRelation = _state.relation(_rival, _tribe)
	assert_eq(record.score, 50.0, "research funding buys no Tribal welcome")


## The discovery is a chronicle beat of the turn that resolved, so the court's
## sheet narrates it beside the turn's other acts.
func test_the_beat_is_stamped_with_the_resolved_turn() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	TribeContact.apply(charts, _state, HUMAN, TURN)
	var beats: Array[Dictionary] = []
	for event: Dictionary in _state.events:
		if String(event.get("kind", "")) == "firstContact":
			beats.append(event)
	assert_eq(beats.size(), 1)
	assert_eq(int(beats[0]["a"]), _rival)
	assert_eq(int(beats[0]["b"]), _tribe)
	assert_eq(int(beats[0]["turn"]), TURN, "the resolved turn, not the state's clock")


## Irreversible and once only: a second pass neither re-records the beat nor
## touches a score the courts have since moved.
func test_first_contact_is_once_and_irreversible() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	TribeContact.apply(charts, _state, HUMAN, TURN)
	_state.relation(_rival, _tribe).set_score(28.0)
	var charts_after: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts_after, _rival, 2)
	assert_eq(
		TribeContact.apply(charts_after, _state, HUMAN, TURN + 1), [] as Array[Dictionary]
	)
	assert_eq(_state.relation(_rival, _tribe).score, 28.0, "the record keeps its score")
	assert_eq(_state.relation(_rival, _tribe).since_turn, TURN)
	assert_eq(_events("firstContact"), 1)


## A court with no chart at all — a fixture, or a session that never loaded a
## region — discovers nothing and writes nothing.
func test_a_court_without_a_chart_is_a_stranger() -> void:
	assert_eq(TribeContact.apply(null, _state, HUMAN, TURN), [] as Array[Dictionary])
	assert_eq(TribeContact.charted_tribes(null, _rival), [] as Array[int])
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	charts.courts[_rival][0] = null
	assert_eq(TribeContact.charted_tribes(charts, _rival), [] as Array[int])
	assert_eq(TribeContact.apply(charts, _state, HUMAN, TURN), [] as Array[Dictionary])


## Two provinces of one Tribe are one court, and a province no faction owns is
## nobody's: neither opens a second relation nor a phantom one.
func test_a_repeated_or_unowned_province_is_not_a_second_court() -> void:
	var before: int = _state.relations_of(_rival).size()
	var charts: CourtCharts = _charts(
		[HUMAN, _rival, _tribe, _tribe, MapModel.NO_ID]
	)
	_reveal(charts, _rival, 2)
	_reveal(charts, _rival, 3)
	_reveal(charts, _rival, 4)
	assert_eq(TribeContact.charted_tribes(charts, _rival), [_tribe] as Array[int])
	assert_eq(TribeContact.apply(charts, _state, HUMAN, TURN).size(), 1)
	assert_eq(_state.relations_of(_rival).size(), before + 1, "one court, one relation")


## The turn pass guards a session that is not a playthrough at all.
func test_the_turn_pass_waits_for_diplomacy_and_a_chart() -> void:
	assert_eq(MapPlayTribeContact.resolve(null), [] as Array[Dictionary])
	var bare := PlaySession.new()
	assert_eq(MapPlayTribeContact.resolve(bare), [] as Array[Dictionary])
	bare.diplomacy = DiplomacyState.new()
	bare.diplomacy.initialize(TURN)
	assert_eq(MapPlayTribeContact.resolve(bare), [] as Array[Dictionary])


## Several charted tribes in one pass come back in id order, one relation each.
func test_each_charted_tribe_is_contacted_once() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe, _other_tribe])
	_reveal(charts, _rival, 2)
	_reveal(charts, _rival, 3)
	var found: Array[Dictionary] = TribeContact.apply(charts, _state, HUMAN, TURN)
	assert_eq(TribeContact.charted_tribes(charts, _rival), [_tribe, _other_tribe] as Array[int])
	assert_eq(found.size(), 2)
	assert_eq(int(found[0]["tribe"]), _tribe)
	assert_eq(int(found[1]["tribe"]), _other_tribe)


## A Minor Nation's province is not a Tribal court: only tribes are discovered.
func test_a_charted_minor_is_not_a_tribe() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, FactionCatalog.minor_ids()[0]])
	_reveal(charts, _rival, 2)
	assert_eq(TribeContact.apply(charts, _state, HUMAN, TURN), [] as Array[Dictionary])


# --- the human court ---------------------------------------------------------


## The crown's own discovery keeps its app-layer pass and herald, so this pass
## never writes the human relation — even when the crown's grid knows the tribe.
func test_the_human_court_is_skipped() -> void:
	var world: WorldMap = _world([HUMAN, _rival, _tribe])
	var human := VisibilityModel.new()
	human.setup(world.region(0), HUMAN)
	human.reveal_province(2)
	var charts: CourtCharts = _charts_over(world, {0: human})
	assert_true(TribeContact.charted_tribes(charts, HUMAN).has(_tribe))
	assert_eq(TribeContact.apply(charts, _state, HUMAN, TURN), [] as Array[Dictionary])
	assert_false(_state.has_relation(HUMAN, _tribe))


## The full-AI observer has no human court, so every crown — the slot one
## included, whose grid is the session's own table — opens its own first contact.
func test_an_observer_contacts_every_crown() -> void:
	var world: WorldMap = _world([HUMAN, _rival, _tribe])
	var slot := VisibilityModel.new()
	slot.setup(world.region(0), HUMAN)
	slot.reveal_province(2)
	var charts: CourtCharts = _charts_over(world, {0: slot})
	for faction: int in FactionCatalog.great_power_ids():
		charts.reveal_province(faction, 0, 2)
	var found: Array[Dictionary] = TribeContact.apply(charts, _state, MapModel.NO_ID, TURN)
	assert_eq(found.size(), FactionCatalog.great_power_ids().size())
	assert_true(_state.has_relation(HUMAN, _tribe), "the observer's slot court contacts too")
	assert_eq(_events("firstContact"), FactionCatalog.great_power_ids().size())


# --- the turn pass -----------------------------------------------------------


## Closing a turn lets a rival that charted a tribe province open contact, and a
## rival that has not stays a stranger (wiki: end-of-turn pass). Rides the suite
## mount — a second chart used to pay ~2 s under coverage for the same reading.
func test_a_turn_close_opens_contact_from_the_rivals_own_chart() -> void:
	assert_not_null(_screen.play.court_charts, "the screen charts its world")
	# The crown's region 1 is the New World; the load charts every rival too.
	_screen._cycle_region()
	var province: ProvinceState = _tribe_contact_province(_screen.play.world)
	assert_not_null(province, "the New World holds a Tribe province")
	var rival: int = FactionCatalog.great_power_ids()[1]
	assert_false(_screen.play.diplomacy.has_relation(rival, province.owner))
	var charts: CourtCharts = _screen.play.court_charts
	charts.reveal_province(rival, NEW_WORLD, province.id)
	_close_turn(_screen.play)
	assert_true(
		_screen.play.diplomacy.has_relation(rival, province.owner),
		"the rival charted the province before the turn closed"
	)
	assert_eq(_screen.play.diplomacy.relation(rival, province.owner).score, 50.0)


func _tribe_contact_province(world: WorldMap) -> ProvinceState:
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if FactionCatalog.type_of(province.owner) == FactionCatalog.Type.TRIBE:
				return province
	return null


## Ends the turn past every consent decision the rivals raise on the way.
func _close_turn(play: PlaySession) -> void:
	var before: int = play.turn
	MapPlayTurn.end_turn(play)
	var guard: int = 0
	while play.turn == before and guard < 12:
		guard += 1
		if CallToArms.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_call(play, false)
		elif Intervention.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_offer(play, false)
		else:
			break
	assert_gt(play.turn, before, "the turn closed")


func _events(kind: String) -> int:
	var total: int = 0
	for event: Dictionary in _state.events:
		if String(event.get("kind", "")) == kind:
			total += 1
	return total
