extends GdToolsTest
## Third-party intervention on a war against a Minor Nation or Tribe
## (wiki: diplomacy § Intervention). Embassy courts choose to join, stand aside
## or protest; AI courts roll the relation bands deterministically.

const _Fixture = preload("res://tests/civilian_fixture.gd")

var state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


func test_a_war_between_great_powers_never_invites_intervention() -> void:
	state.set_overture(1, 2, DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(Intervention.candidates(state, 3, 2), [] as Array[int])
	var war: Dictionary = DiplomacyRules.declare_war(state, 3, 2)
	assert_eq(war.get("interventions", []), [] as Array[String])


func test_an_embassy_in_the_victim_court_makes_a_candidate() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(Intervention.has_embassy(state, 1, 6))
	assert_eq(Intervention.candidates(state, 3, 6), [1] as Array[int])


func test_a_consulate_alone_does_not_qualify() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(Intervention.candidates(state, 3, 6), [] as Array[int])


func test_nap_and_join_empire_keep_the_embassy() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(4, 6, DiplomacyCatalog.STAGE_JOIN_EMPIRE)
	assert_eq(Intervention.candidates(state, 3, 6), [1, 4] as Array[int])


func test_the_human_court_is_asked_once_per_declaration() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var war: Dictionary = DiplomacyRules.declare_war(state, 3, 6)
	var offer: Dictionary = Intervention.pending_for(state, 0)
	assert_false(offer.is_empty(), "the embassy court is asked")
	assert_eq(int(offer["aggressor"]), 3)
	assert_eq(int(offer["target"]), 6)
	assert_true(Intervention.has_pending(state, 0))
	assert_false(Intervention.queue_human(state, 3, 6, 0), "the same pair never asks twice")
	assert_eq(state.pending_interventions.size(), 1)
	assert_false(bool(war.get("interventions", []).is_empty()), "the court is told")


func test_intervening_joins_the_war_and_keeps_the_embassy() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	var answer: Dictionary = Intervention.resolve_human(state, Intervention.KIND_INTERVENE)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(state.relation(0, 3).at_war, "war on the aggressor starts immediately")
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_EMBASSY)
	assert_false(Intervention.has_pending(state, 0))
	assert_true(_event("interventionIntervened"))


func test_standing_aside_costs_the_embassy_and_subsidy() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_subsidy(0, 6, 10)
	DiplomacyRules.declare_war(state, 3, 6)
	var answer: Dictionary = Intervention.resolve_human(state, Intervention.KIND_NOTHING)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(state.subsidy(0, 6), 0)
	assert_false(state.relation(0, 3).at_war)
	assert_eq(state.relation(0, 3).score, 50.0, "standing aside is not a diplomatic act")
	assert_true(_event("interventionDoNothing"))


## Overtures are two-way: `establish_overture` writes both directions, so
## standing aside must clear both or the reverse record keeps the embassy alive
## for aid and subsidy (wiki: diplomacy § Intervention § Do Nothing).
func test_standing_aside_clears_the_embassy_in_both_directions() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_overture(6, 0, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	Intervention.resolve_human(state, Intervention.KIND_NOTHING)
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(state.overture(6, 0), DiplomacyCatalog.STAGE_NONE, "the reverse record goes too")
	assert_false(DiplomacyRules.has_embassy(state, 0, 6), "no embassy survives standing aside")
	assert_false(
		bool(DiplomacyAid.can_grant_aid(state, 0, 6, 1000, 5000)["ok"]),
		"aid needs a live embassy"
	)


func test_an_ai_standing_aside_also_clears_both_directions() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_overture(6, 1, DiplomacyCatalog.STAGE_EMBASSY)
	state.relation(1, 6).score = 10.0
	DiplomacyRules.declare_war(state, 3, 6)
	assert_false(state.relation(1, 3).at_war, "0% never intervenes")
	assert_eq(state.overture(1, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(state.overture(6, 1), DiplomacyCatalog.STAGE_NONE, "the reverse record goes too")


func test_protest_penalises_the_aggressor_and_keeps_the_embassy() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	var answer: Dictionary = Intervention.resolve_human(state, Intervention.KIND_PROTEST)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_false(state.relation(0, 3).at_war)
	assert_eq(state.relation(0, 3).score, 40.0, "−10 protest penalty")
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(_event("interventionProtest"))


func test_propaganda_softens_the_protest() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	Intervention.resolve_human(state, Intervention.KIND_PROTEST, {"propaganda": true})
	assert_eq(state.relation(0, 3).score, 45.0, "−5 against a propaganda aggressor")


func test_answering_without_an_offer_is_refused() -> void:
	var answer: Dictionary = Intervention.resolve_human(
		state, Intervention.KIND_INTERVENE
	)
	assert_false(answer["ok"])
	assert_false(state.relation(0, 3).at_war)


func test_ai_chance_follows_the_documented_bands() -> void:
	assert_eq(Intervention.chance_for(0.0), 0.0)
	assert_eq(Intervention.chance_for(25.0), 0.0)
	assert_eq(Intervention.chance_for(26.0), 0.25)
	assert_eq(Intervention.chance_for(50.0), 0.25)
	assert_eq(Intervention.chance_for(51.0), 0.5)
	assert_eq(Intervention.chance_for(75.0), 0.5)
	assert_eq(Intervention.chance_for(76.0), 0.8)
	assert_eq(Intervention.chance_for(100.0), 0.8)


func test_the_ai_roll_is_a_stable_unit_sample() -> void:
	var first: float = Intervention.roll(7, 3, 6, 1)
	assert_eq(first, Intervention.roll(7, 3, 6, 1), "replays decide the same way")
	assert_true(first >= 0.0 and first < 1.0)


func test_ai_intervention_follows_the_band() -> void:
	state.relation(1, 6).score = 90.0
	var expected: bool = Intervention.roll(state.turn, 3, 6, 1) < 0.8
	assert_eq(Intervention.ai_intervenes(state, 1, 3, 6), expected)
	state.relation(1, 6).score = 10.0
	assert_false(Intervention.ai_intervenes(state, 1, 3, 6), "0% never intervenes")


func test_a_court_already_at_war_with_the_aggressor_is_not_asked() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.relation(1, 3).at_war = true
	assert_eq(Intervention.candidates(state, 3, 6), [] as Array[int])


func test_a_tribe_war_can_invite_intervention() -> void:
	state.set_overture(1, 9, DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(Intervention.candidates(state, 3, 9), [1] as Array[int])


func test_ai_answers_are_applied_at_the_declaration() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.relation(1, 6).score = 90.0
	var intervenes: bool = Intervention.roll(state.turn, 3, 6, 1) < 0.8
	DiplomacyRules.declare_war(state, 3, 6)
	assert_eq(state.relation(1, 3).at_war, intervenes, "the roll is the documented band")
	if not intervenes:
		assert_eq(state.overture(1, 6), DiplomacyCatalog.STAGE_NONE, "standing aside loses it")


func test_an_absorbed_faction_drops_its_waiting_offer() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(state, 3, 6)
	assert_true(Intervention.has_pending(state, 0))
	state.clear_relations_of(6)
	assert_false(Intervention.has_pending(state, 0))


## Wiki: diplomacy § GP–Minor Rules § Intervention — the trigger is an Embassy
## with the victim **or** purchased land recorded in its provinces, so a deed
## holder is offered the choice without an embassy.
func test_purchased_land_alone_makes_a_candidate() -> void:
	var world: WorldMap = _deed_world(1)
	assert_eq(state.overture(1, 6), DiplomacyCatalog.STAGE_NONE, "a deed is not an embassy")
	assert_false(DiplomacyRules.has_embassy(state, 1, 6))
	assert_eq(Intervention.candidates(state, 3, 6, world), [1] as Array[int])


func test_purchased_land_and_an_embassy_both_invite_the_same_court_once() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var world: WorldMap = _deed_world(1)
	assert_eq(Intervention.candidates(state, 3, 6, world), [1] as Array[int])


func test_a_deed_in_a_province_the_victim_lost_does_not_count() -> void:
	var world: WorldMap = _deed_world(1)
	world.region(0).provinces[1].owner = 7
	assert_eq(
		Intervention.candidates(state, 3, 6, world), [] as Array[int],
		"deeds follow the province, not the old owner"
	)


## The declaration path must carry the world, or the deed holder never hears of
## a war declared from the court or by a rival planner (REQ-P2-03).
func test_a_declaration_offers_the_human_deed_holder() -> void:
	var world: WorldMap = _deed_world(0)
	var war: Dictionary = DiplomacyRules.declare_war(state, 3, 6, true, world)
	assert_true(bool(war.get("ok", false)), war.get("reason", ""))
	assert_true(Intervention.has_pending(state, 0), "the deed holder is asked")
	assert_eq(int(Intervention.pending_for(state, 0)["aggressor"]), 3)


func test_a_declaration_without_a_world_keeps_the_embassy_trigger() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var war: Dictionary = DiplomacyRules.declare_war(state, 3, 6)
	assert_true(bool(war.get("ok", false)), war.get("reason", ""))
	assert_eq(state.overture(1, 6), DiplomacyCatalog.STAGE_NONE, "the war clears it")


## Tiny world whose second province answers to Minor Nation `victim`, with one
## land tile sold to `buyer`.
func _deed_world(buyer: int) -> WorldMap:
	var model: MapModel = _Fixture.build()
	var province: ProvinceState = model.provinces[1]
	province.owner = 6
	assert_true(model.purchase_tile(province.tiles[0], buyer), "a deed is signed")
	var world := WorldMap.new()
	world.add_region(model)
	return world


func _event(kind: String) -> bool:
	for event: Dictionary in state.events:
		if String(event.get("kind", "")) == kind:
			return true
	return false
