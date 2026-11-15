# gdlint: disable=max-public-methods
extends GdToolsTest
## Campaign rules: intervention, deeds as a defended stake, mutual-defence calls,
## the capital-choice phase and the age's race readings (wiki: diplomacy,
## capital-choice-phase, victory).
## Consolidated rulebook: test_intervention, test_deed_protection,
## test_call_to_arms, test_capital_choice, test_victory_standings, test_gazette
## (one Godot boot per domain).

const _Fixture = preload("res://tests/civilian_fixture.gd")

var state: DiplomacyState
var call_state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)
	call_state = DiplomacyState.new()
	call_state.initialize(1)


# --- from test_intervention.gd ---
## Third-party intervention on a war against a Minor Nation or Tribe
## (wiki: diplomacy § Intervention). Embassy courts choose to join, stand aside
## or protest; AI courts roll the relation bands deterministically.


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
		assert_eq(
			state.overture(1, 6),
			DiplomacyCatalog.STAGE_EMBASSY,
			"a caring court protests instead of standing aside"
		)
		assert_eq(state.relation(1, 3).score, 40.0, "and charges the aggressor for it")


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
	# A court that does not care about the victim stands aside, so the cleared
	# embassy proves the declaration reached it without a world to scan.
	state.relation(1, 6).score = 10.0
	var war: Dictionary = DiplomacyRules.declare_war(state, 3, 6)
	assert_true(bool(war.get("ok", false)), war.get("reason", ""))
	assert_eq(state.overture(1, 6), DiplomacyCatalog.STAGE_NONE, "the war clears it")


## A court that cares about the victim (26+) but loses the intervention roll
## protests rather than standing aside: it keeps its embassy and puts a relation
## price on the aggression (DR-20261110-16).
func test_an_ai_that_does_not_intervene_protests_while_it_cares() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.relation(1, 6).score = 30.0
	assert_false(
		Intervention.roll(state.turn, 3, 6, 1) < 0.25,
		"this turn's roll leaves the court at peace"
	)
	DiplomacyRules.declare_war(state, 3, 6)
	assert_false(state.relation(1, 3).at_war, "the court keeps the peace")
	assert_eq(state.relation(1, 3).score, 40.0, "−10 protest penalty")
	assert_eq(
		state.overture(1, 6), DiplomacyCatalog.STAGE_EMBASSY, "a protest keeps the embassy"
	)
	assert_true(_event("interventionProtest"), "the act is on the record")


## The first intervention band is the line: 0–25 is indifference, and the court
## stands aside as it always has (DR-20261110-16).
func test_an_ai_below_the_band_stands_aside() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.relation(1, 6).score = 25.0
	DiplomacyRules.declare_war(state, 3, 6)
	assert_eq(state.overture(1, 6), DiplomacyCatalog.STAGE_NONE, "no care, no embassy")
	assert_true(_event("interventionDoNothing"))
	assert_eq(state.relation(1, 3).score, 50.0, "standing aside is not a diplomatic act")


func test_ai_protest_policy_follows_the_intervention_band() -> void:
	state.relation(1, 6).score = 25.0
	assert_false(Intervention.ai_protests(state, 1, 6), "0% band stands aside")
	state.relation(1, 6).score = 26.0
	assert_true(Intervention.ai_protests(state, 1, 6), "the first band protests")


func test_ai_choice_prefers_the_roll_then_the_protest() -> void:
	state.relation(1, 6).score = 90.0
	assert_eq(
		Intervention.ai_choice(state, 1, 3, 6),
		Intervention.KIND_INTERVENE,
		"the roll passed"
	)
	state.relation(1, 6).score = 30.0
	assert_eq(
		Intervention.ai_choice(state, 1, 3, 6),
		Intervention.KIND_PROTEST,
		"the roll failed, but the court still cares"
	)
	state.relation(1, 6).score = 10.0
	assert_eq(Intervention.ai_choice(state, 1, 3, 6), Intervention.KIND_NOTHING)


## The protest penalty is read off the declarer's own ledger (Propaganda), which
## an AI declarer now hands to the rules too (DR-20261110-16).
func test_the_protest_reads_the_declarers_propaganda() -> void:
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.relation(1, 6).score = 30.0
	DiplomacyRules.declare_war(state, 3, 6, true, null, {"propaganda": true})
	assert_eq(state.relation(1, 3).score, 45.0, "−5 against a propaganda aggressor")
	assert_eq(state.overture(1, 6), DiplomacyCatalog.STAGE_EMBASSY)


## A deed is a stake, not a courtesy: a court that has bought land inside the
## victim's provinces never shrugs the aggression off, even on cold relations
## (wiki: diplomacy § Intervention "investment protection"; DR-20261110-20).
func test_one_deed_keeps_a_cold_court_from_standing_aside() -> void:
	var world: WorldMap = _deed_world(1)
	state.relation(1, 6).score = 10.0
	assert_false(Intervention.ai_protests(state, 1, 6), "goodwill alone stands aside")
	assert_true(Intervention.ai_protests(state, 1, 6, world), "the deed is the stake")
	assert_eq(Intervention.protection_chance(state, 1, 3, 6, world), 0.25)


func test_two_deeds_raise_the_trial_to_the_second_band() -> void:
	var world: WorldMap = _deed_world(1)
	var model: MapModel = world.region(0)
	assert_true(model.ownership.purchase(model.index_of(4, 0), 1), "a second deed")
	state.relation(1, 6).score = 10.0
	assert_eq(DeedProtection.deed_count(world, 1, 6), 2)
	assert_eq(Intervention.protection_chance(state, 1, 3, 6, world), 0.5)


## Losing the roll still leaves the deed holder protesting against the war: it
## keeps its seat at the victim's court and puts a relation price on the
## aggression.
func test_a_deed_holder_that_loses_the_roll_protests() -> void:
	var world: WorldMap = _deed_world(1)
	state.relation(1, 6).score = 10.0
	state.turn = _turn_above_the_first_band(3, 6, 1)
	assert_eq(
		Intervention.ai_choice(state, 1, 3, 6, world),
		Intervention.KIND_PROTEST,
		"below 26 relations a court without a deed would stand aside"
	)


## The offer records what earned the court its seat, so the prompt never claims
## an embassy the court does not hold (REQ-P2-05, REQ-P5-05).
func test_a_deed_only_offer_names_the_deed_not_the_embassy() -> void:
	var world: WorldMap = _deed_world(0)
	DiplomacyRules.declare_war(state, 3, 6, true, world)
	var offer: Dictionary = Intervention.pending_for(state, 0)
	assert_eq(String(offer.get("basis", "")), "deed")
	assert_eq(int(offer.get("deeds", 0)), 1)
	var text: String = Intervention.offer_text(offer)
	assert_true(text.contains("deed"), text)
	assert_false(text.contains("embassy"), "no embassy is claimed: " + text)


func test_standing_aside_without_an_embassy_leaves_the_deed_alone() -> void:
	var world: WorldMap = _deed_world(0)
	DiplomacyRules.declare_war(state, 3, 6, true, world)
	var answer: Dictionary = Intervention.resolve_human(state, Intervention.KIND_NOTHING)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(String(answer["message"]).contains("deeds"), String(answer["message"]))
	assert_eq(DeedProtection.deed_count(world, 0, 6), 1, "the land stays bought")


## The first turn whose trial roll clears the 25% band, so a protest test reads
## the band rather than the sample.
func _turn_above_the_first_band(aggressor: int, target: int, court: int) -> int:
	for turn in range(1, 200):
		if Intervention.roll(turn, aggressor, target, court) >= 0.25:
			return turn
	return 1


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


# --- from test_deed_protection.gd ---
## Deeds as a defended stake (wiki: diplomacy § Intervention — "Embassy with that
## Minor/Tribe **or** purchased land recorded in its provinces"; DR-20261110-20).


const MINOR: int = 6
const BUYER: int = 1


func test_a_deed_inside_the_victims_provinces_counts_for_its_buyer() -> void:
	var world: WorldMap = _minor_world()
	assert_eq(DeedProtection.deed_count(world, BUYER, MINOR), 1)
	assert_eq(DeedProtection.deed_count(world, 2, MINOR), 0, "another crown holds nothing")
	assert_true(DeedProtection.holds_deed(world, BUYER, MINOR))
	assert_eq(DeedProtection.holders(world, MINOR), [BUYER] as Array[int])


func test_the_stake_is_what_the_deed_would_cost_to_buy_again() -> void:
	var world: WorldMap = _minor_world()
	var model: MapModel = world.region(0)
	var tile: Vector2i = _first_deed(model, BUYER, MINOR)
	assert_eq(
		DeedProtection.stake_value(world, BUYER, MINOR),
		LandPurchase.cost(model, tile),
		"15 x the resource's base price, the merchant's own price"
	)


func test_a_province_the_victim_lost_takes_the_stake_with_it() -> void:
	var world: WorldMap = _minor_world()
	world.region(0).provinces[1].owner = 7
	assert_eq(DeedProtection.deed_count(world, BUYER, MINOR), 0)
	assert_false(DeedProtection.holds_deed(world, BUYER, MINOR))


func test_one_deed_is_worth_protecting_and_two_are_serious() -> void:
	var world: WorldMap = _minor_world()
	assert_true(DeedProtection.worth_protecting(world, BUYER, MINOR))
	assert_false(DeedProtection.serious_stake(world, BUYER, MINOR))
	var model: MapModel = world.region(0)
	assert_true(model.purchase_tile(Vector2i(2, 1), BUYER), "a second deed is signed")
	assert_eq(DeedProtection.deed_count(world, BUYER, MINOR), 2)
	assert_true(DeedProtection.serious_stake(world, BUYER, MINOR))
	assert_eq(DeedProtection.holding_text(world, BUYER, MINOR), "2 deeds")


func test_a_crown_with_no_deed_has_no_stake() -> void:
	var world: WorldMap = _minor_world()
	assert_false(DeedProtection.worth_protecting(world, 3, MINOR))
	assert_eq(DeedProtection.stake_value(world, 3, MINOR), 0)
	assert_eq(DeedProtection.holding_text(world, 3, MINOR), "")


## A declaration of war does not tear a deed up: the province owner changes
## relations, never the tile's buyer (wiki: diplomacy § Intervention § Do Nothing
## — "purchased land remains recorded until normal province conquest rules
## apply").
func test_a_war_with_the_seller_leaves_the_deed_standing() -> void:
	var world: WorldMap = _minor_world()
	var model: MapModel = world.region(0)
	var tile: Vector2i = _first_deed(model, BUYER, MINOR)
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(BUYER, MINOR, 1)
	assert_true(
		bool(DiplomacyRules.declare_war(state, BUYER, MINOR, true, world).get("ok", false))
	)
	assert_true(model.is_purchased_tile(tile), "the deed survives the declaration")
	assert_eq(model.owner_at(tile.x, tile.y), BUYER)
	assert_eq(DeedProtection.deed_count(world, BUYER, MINOR), 1)


## A crown deciding to attack a protected Minor is told who would answer before
## it commits (REQ-P5-03, REQ-P5-05; DR-20261110-20).
func test_the_court_names_who_would_answer_a_war_on_the_minor() -> void:
	var world: WorldMap = _minor_world()
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(0, MINOR, 1)
	state.ensure_relation(3, MINOR, 1)
	state.set_overture(3, MINOR, DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(
		InterventionCopy.warden_hint(state, world, 0, MINOR),
		"England and Portugal may intervene."
	)
	state.set_overture(3, MINOR, DiplomacyCatalog.STAGE_NONE)
	assert_eq(InterventionCopy.warden_hint(state, world, 0, MINOR), "England may intervene.")


func test_three_wardens_read_as_a_list() -> void:
	var world: WorldMap = _minor_world()
	var model: MapModel = world.region(0)
	assert_true(model.ownership.purchase(model.index_of(2, 1), 2), "a second holder")
	assert_true(model.ownership.purchase(model.index_of(2, 2), 4), "a third holder")
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(0, MINOR, 1)
	assert_eq(
		InterventionCopy.warden_hint(state, world, 0, MINOR),
		"England, France and United Provinces may intervene."
	)


func test_an_unprotected_minor_names_no_warden() -> void:
	var world: WorldMap = _minor_world()
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(0, MINOR, 1)
	world.region(0).ownership.clear()
	assert_eq(InterventionCopy.warden_hint(state, world, 0, MINOR), "")


## Small map where Minor Nation 6 owns province 1 and `BUYER` holds one deed in
## it (the fixture's grain tile).
func _minor_world() -> WorldMap:
	var model: MapModel = _Fixture.build_minor()
	assert_true(model.purchase_tile(Vector2i(3, 1), BUYER), "a deed is signed")
	var world := WorldMap.new()
	world.add_region(model)
	return world


func _first_deed(model: MapModel, buyer: int, target: int) -> Vector2i:
	for province: ProvinceState in model.provinces:
		if province.owner != target:
			continue
		for tile: Vector2i in province.tiles:
			if model.ownership.purchaser(model.index_of(tile.x, tile.y)) == buyer:
				return tile
	return Vector2i(-1, -1)


# --- from test_call_to_arms.gd ---
## Mutual defence: a formal ally of a declared-upon Great Power is called to
## arms once, joins by relation or refuses with the unified penalty
## (wiki: diplomacy § Alliances § Mutual defence).


func test_formal_ally_is_called_and_joins_at_fifty_or_better() -> void:
	_ally(1, 2, 80.0)
	var war: Dictionary = DiplomacyRules.declare_war(call_state, 3, 2)
	assert_true(war["ok"], war.get("reason", ""))
	assert_true(call_state.relation(1, 3).at_war, "England joins the war on Portugal")
	assert_true(_call_event("callToArmsAccepted"), "the answer is recorded in history")
	assert_eq(call_state.pending_calls.size(), 0, "AI allies need no consent prompt")


func test_informal_allied_band_alone_never_calls() -> void:
	call_state.relation(1, 2).score = 90.0
	assert_false(call_state.relation(1, 2).formal_alliance)
	CallToArms.freeze_alliances(call_state)
	DiplomacyRules.declare_war(call_state, 3, 2)
	assert_false(call_state.relation(1, 3).at_war, "no treaty, no obligation")
	assert_false(_call_event("callToArmsAccepted"))


func test_alliance_signed_this_turn_never_calls() -> void:
	call_state.relation(1, 2).formal_alliance = true
	call_state.relation(1, 2).score = 80.0
	# No snapshot: the treaty was signed after the preceding turn closed.
	DiplomacyRules.declare_war(call_state, 3, 2)
	assert_false(call_state.relation(1, 3).at_war)


func test_end_turn_freezes_alliances_for_the_next_turn() -> void:
	call_state.relation(1, 2).formal_alliance = true
	call_state.relation(1, 2).score = 80.0
	call_state.end_turn()
	DiplomacyRules.declare_war(call_state, 3, 2)
	assert_true(call_state.relation(1, 3).at_war)


func test_ai_ally_refuses_below_fifty_and_breaks_the_treaty() -> void:
	_ally(1, 2, 40.0)
	DiplomacyRules.declare_war(call_state, 3, 2)
	assert_false(call_state.relation(1, 3).at_war)
	assert_false(call_state.relation(1, 2).formal_alliance)
	assert_eq(call_state.relation(1, 2).score, 0.0, "−50 clamps at zero")
	assert_eq(call_state.relation(1, 0).score, 40.0, "−10 cascade to another GP")
	assert_eq(call_state.relation(1, 4).score, 40.0)
	assert_eq(call_state.relation(1, 5).score, 40.0)
	assert_eq(call_state.relation(1, 3).score, 50.0, "the aggressor is exempt")
	assert_true(_call_event("allianceBroken"))
	assert_true(_call_event("callToArmsRefused"))


func test_human_call_waits_for_consent() -> void:
	_ally(0, 2, 80.0)
	DiplomacyRules.declare_war(call_state, 3, 2)
	var call: Dictionary = CallToArms.pending_call_for(call_state, 0)
	assert_false(call.is_empty(), "the human court is asked")
	assert_eq(int(call["aggressor"]), 3)
	assert_eq(int(call["defender"]), 2)
	assert_false(call_state.relation(0, 3).at_war, "no war until the player answers")
	assert_true(CallToArms.has_pending(call_state, 0))
	var answer: Dictionary = CallToArms.resolve_human(call_state, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(call_state.relation(0, 3).at_war, "joining means war on the aggressor")
	assert_true(call_state.relation(0, 2).formal_alliance, "the alliance stands")
	assert_false(CallToArms.has_pending(call_state, 0))
	assert_true(_call_event("callToArmsAccepted"))


## The stakes line the court reads: the war it joins and the unified penalty a
## refusal costs (wiki: diplomacy § Alliances § Mutual defence, § Breaking an
## alliance).
func test_the_offer_names_what_each_answer_costs() -> void:
	_ally(0, 2, 80.0)
	DiplomacyRules.declare_war(call_state, 3, 2)
	var call: Dictionary = CallToArms.pending_call_for(call_state, 0)
	assert_false(call.is_empty(), "the court is asked")
	var text: String = CallToArms.offer_text(call)
	assert_true(text.contains("war against Portugal"), text)
	assert_true(text.contains("−50 with France"), text)
	assert_true(text.contains("−10 with every other Great Power"), text)


func test_human_join_cancels_subsidies_with_the_aggressor() -> void:
	_ally(0, 2, 80.0)
	call_state.set_subsidy(0, 3, 10)
	call_state.set_subsidy(3, 0, 5)
	DiplomacyRules.declare_war(call_state, 3, 2)
	CallToArms.resolve_human(call_state, true)
	assert_eq(call_state.subsidy(0, 3), 0)
	assert_eq(call_state.subsidy(3, 0), 0)


func test_human_refusal_applies_the_unified_penalty() -> void:
	_ally(0, 2, 90.0)
	DiplomacyRules.declare_war(call_state, 3, 2)
	var answer: Dictionary = CallToArms.resolve_human(call_state, false)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_false(call_state.relation(0, 2).formal_alliance)
	assert_eq(call_state.relation(0, 2).score, 40.0, "−50 with the abandoned ally")
	assert_eq(call_state.relation(0, 1).score, 40.0, "−10 cascade")
	assert_eq(call_state.relation(0, 4).score, 40.0)
	assert_eq(call_state.relation(0, 5).score, 40.0)
	assert_eq(call_state.relation(0, 3).score, 50.0, "the aggressor is exempt")
	assert_false(call_state.relation(0, 3).at_war)
	assert_true(_call_event("allianceBroken"))
	assert_true(_call_event("callToArmsRefused"))


func test_ally_already_at_war_with_the_aggressor_is_not_called() -> void:
	call_state.relation(1, 3).at_war = true
	_ally(1, 2, 80.0)
	DiplomacyRules.declare_war(call_state, 3, 2)
	assert_eq(CallToArms.candidates(call_state, 3, 2), [] as Array[int])
	assert_false(_call_event("callToArmsAccepted"))


func test_declaring_on_a_minor_never_calls_allies() -> void:
	_ally(1, 2, 80.0)
	DiplomacyRules.declare_war(call_state, 0, 6)
	assert_eq(CallToArms.candidates(call_state, 0, 6), [] as Array[int])
	assert_false(CallToArms.has_pending(call_state, 0))


func test_one_call_per_aggressor_and_defender_pair() -> void:
	assert_true(CallToArms.queue_human_call(call_state, 3, 2, 0))
	assert_false(CallToArms.queue_human_call(call_state, 3, 2, 0), "the same pair never asks twice")
	assert_eq(call_state.pending_calls.size(), 1)


func test_answering_without_a_waiting_call_is_refused() -> void:
	var answer: Dictionary = CallToArms.resolve_human(call_state, true)
	assert_false(answer["ok"])
	assert_false(call_state.relation(0, 3).at_war)


func _ally(a: int, b: int, score: float) -> void:
	var record: DiplomacyRelation = call_state.relation(a, b)
	record.formal_alliance = true
	record.score = score
	CallToArms.freeze_alliances(call_state)


func _call_event(kind: String) -> bool:
	for event: Dictionary in call_state.events:
		if String(event.get("kind", "")) == kind:
			return true
	return false


# --- from test_capital_choice.gd ---
## Capital-choice phase rules (wiki: capital-choice-phase, capital-and-connectivity
## § Capital Setup). Synthetic maps keep each acceptance case readable.

const WIDTH: int = 12
const HEIGHT: int = 9


func _blank() -> MapModel:
	var model := MapModel.new()
	model.setup(WIDTH, HEIGHT)
	return model


## Claims tiles for a province, starting from ocean, and registers the province.
func _add_province(
	model: MapModel, id: int, owner: int, tiles: Array, terrain: int = MapModel.Terrain.PLAINS
) -> void:
	var sum := Vector2.ZERO
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = terrain
		model.province[model.index_of(tile.x, tile.y)] = id
		sum += Vector2(tile)
	var typed_tiles: Array[Vector2i] = []
	for tile: Vector2i in tiles:
		typed_tiles.append(tile)
	model.provinces.append(
		ProvinceState.create(
			id, "P%d" % id, typed_tiles, sum / float(tiles.size()), tiles.size(), owner
		)
	)


func _block(x0: int, x1: int, y0: int, y1: int) -> Array:
	var tiles: Array = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			tiles.append(Vector2i(x, y))
	return tiles


## Paints every sea tile with a zone id chosen by position.
func _paint_sea(model: MapModel, zones: Callable) -> void:
	for y in model.height:
		for x in model.width:
			if model.is_sea(x, y):
				model.sea_zone[model.index_of(x, y)] = zones.call(x, y)


## 5x3 island at (3,3)-(7,5) with one sea zone on each side.
func _island_with_four_seaboards() -> MapModel:
	var model := _blank()
	_add_province(model, 0, 0, _block(3, 7, 3, 5))
	_paint_sea(model, func(x: int, y: int) -> int:
		if y <= 2:
			return 0
		if y >= 6:
			return 2
		if x <= 2:
			return 1
		return 3
	)
	return model


## Two separate islands, every sea tile in one zone.
func _two_islands() -> MapModel:
	var model := _blank()
	_add_province(model, 0, 0, _block(2, 4, 2, 4))
	_add_province(model, 1, 1, _block(7, 8, 6, 7))
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	return model


# --- province choice --------------------------------------------------------


func test_sea_bound_lookup_and_sorted_seaboards() -> void:
	var model := _island_with_four_seaboards()
	assert_true(CapitalChoice.is_sea_bound(model, 0))
	assert_eq(CapitalChoice.sea_bound_sea_zones(model, 0), [0, 1, 2, 3])


func test_great_power_skips_lower_id_inland_province() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 0, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_add_province(model, 2, 1, [Vector2i(6, 6), Vector2i(7, 6)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	assert_false(CapitalChoice.is_sea_bound(model, 0))
	assert_true(CapitalChoice.is_sea_bound(model, 1))

	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(result["ok"])
	assert_eq(int(result["province_id"]), 1)


func test_great_power_without_sea_bound_province_fails_setup() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)

	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_false(result["ok"])
	assert_eq(String(result["error"]), CapitalChoice.ERROR_NO_SEA_BOUND_PROVINCE)
	assert_false(model.provinces[0].capital)


func test_faction_without_provinces_fails_setup() -> void:
	var model := _island_with_four_seaboards()
	var result: Dictionary = CapitalChoice.place_capital(model, 7)
	assert_false(result["ok"])
	assert_eq(String(result["error"]), CapitalChoice.ERROR_NO_OWNED_PROVINCE)


func test_minor_prefers_sea_bound_then_falls_back_to_inland() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 0, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_add_province(model, 2, 1, [Vector2i(7, 7)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)

	var pick: Dictionary = CapitalChoice.pick_province(model, 0, CapitalChoice.KIND_MINOR)
	assert_eq(int(pick["province_id"]), 1)

	var inland := _blank()
	_add_province(inland, 0, 0, [Vector2i(2, 2)])
	_add_province(inland, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(inland, func(_x: int, _y: int) -> int: return 0)
	var fallback: Dictionary = CapitalChoice.pick_province(
		inland, 0, CapitalChoice.KIND_MINOR
	)
	assert_eq(int(fallback["province_id"]), 0)


# --- tile choice ------------------------------------------------------------


func test_great_power_takes_first_plains_class_a_tile() -> void:
	var model := _two_islands()
	model.terrain[model.index_of(2, 2)] = MapModel.Terrain.HARDWOOD_FOREST
	assert_eq(CapitalChoice.tile_class(model, 0, Vector2i(2, 2)), CapitalChoice.CLASS_A)
	assert_eq(CapitalChoice.tile_class(model, 0, Vector2i(3, 3)), CapitalChoice.CLASS_B)
	assert_eq(CapitalChoice.choose_tile(model, 0), Vector2i(3, 2))


func test_class_rank_beats_plains() -> void:
	var model := _two_islands()
	for tile: Vector2i in model.province_tiles(0):
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.HARDWOOD_FOREST
	model.terrain[model.index_of(3, 3)] = MapModel.Terrain.PLAINS
	assert_eq(CapitalChoice.choose_tile(model, 0), Vector2i(2, 2))


func test_great_power_falls_back_to_coastal_class_c() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 1, [Vector2i(1, 2), Vector2i(2, 1)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	assert_eq(CapitalChoice.tile_class(model, 0, Vector2i(2, 2)), CapitalChoice.CLASS_C)
	assert_eq(CapitalChoice.choose_tile(model, 0), Vector2i(2, 2))


func test_minor_takes_class_a_before_class_b() -> void:
	var model := _two_islands()
	for tile: Vector2i in model.province_tiles(0):
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.HARDWOOD_FOREST
	model.terrain[model.index_of(3, 3)] = MapModel.Terrain.PLAINS
	assert_eq(
		CapitalChoice.choose_tile(model, 0, CapitalChoice.KIND_MINOR), Vector2i(2, 2)
	)


func test_capital_tile_becomes_plains_and_loses_its_resource() -> void:
	var model := _two_islands()
	var seat := Vector2i(2, 2)
	for tile: Vector2i in model.province_tiles(0):
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.HARDWOOD_FOREST
	model.resource[model.index_of(seat.x, seat.y)] = 3
	model.provinces[0].resource = 3
	model.provinces[0].resource_tile = seat

	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(result["ok"])
	assert_true(bool(result["converted"]))
	assert_eq(model.terrain_at(seat.x, seat.y), MapModel.Terrain.PLAINS)
	assert_eq(model.resource_at(seat.x, seat.y), MapModel.NO_ID)
	assert_eq(model.provinces[0].resource, MapModel.NO_ID)
	assert_false(model.provinces[0].has_resource_tile())


# --- capital setup: ports, roads, town development -------------------------


func test_one_port_per_seaboard_with_roads_to_the_capital() -> void:
	var model := _island_with_four_seaboards()
	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(result["ok"])
	var seat := Vector2i(3, 3)
	assert_eq(Vector2i(result["tile"]), seat)

	var ports: Dictionary = result["ports"]
	assert_eq(ports.size(), 4)
	assert_eq(ports[0], seat)
	assert_eq(ports[1], seat)
	assert_eq(ports[2], Vector2i(3, 5))
	assert_eq(ports[3], Vector2i(7, 3))

	var roads: Array = result["road_paths"]
	assert_eq(roads.size(), 2)
	var port_tiles: Array = ports.values()
	for path: Array in roads:
		assert_true(port_tiles.has(path[0]))
		assert_eq(path[path.size() - 1], seat)
		assert_true(_is_contiguous(path))
	assert_eq(model.provinces[0].town_development, 4)


func test_inland_minor_gets_no_ports_or_roads() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)

	var result: Dictionary = CapitalChoice.place_capital(
		model, 0, CapitalChoice.KIND_MINOR
	)
	assert_true(result["ok"])
	assert_eq(int(result["province_id"]), 0)
	assert_true((result["ports"] as Dictionary).is_empty())
	assert_true((result["road_paths"] as Array).is_empty())
	assert_eq(model.provinces[0].town_development, 0)


func test_capital_choice_is_deterministic() -> void:
	var first := _island_with_four_seaboards()
	var second := _island_with_four_seaboards()
	var a: Dictionary = CapitalChoice.place_capital(first, 0)
	var b: Dictionary = CapitalChoice.place_capital(second, 0)
	assert_eq(a["tile"], b["tile"])
	assert_eq(a["ports"], b["ports"])
	assert_eq(a["road_paths"], b["road_paths"])


func test_place_all_reports_one_result_per_faction() -> void:
	var model := _two_islands()
	var results: Array[Dictionary] = CapitalChoice.place_all(model, [0, 1])
	assert_eq(results.size(), 2)
	assert_eq(int(results[0]["province_id"]), 0)
	assert_eq(int(results[1]["province_id"]), 1)
	assert_true(model.provinces[1].capital)


# --- player seating ---------------------------------------------------------


## Two owned provinces on one island, each with its own seaboard.
func _two_owned_coasts() -> MapModel:
	var model := _blank()
	_add_province(model, 0, 0, _block(2, 4, 2, 5))
	_add_province(model, 1, 0, _block(5, 7, 2, 5))
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	return model


## The interactive phase only accepts a crown province that reaches the sea.
func test_can_seat_accepts_only_owned_sea_bound_provinces() -> void:
	var model := _two_islands()
	assert_true(CapitalChoice.can_seat(model, 0, 0), "own sea-bound province")
	assert_false(CapitalChoice.can_seat(model, 0, 1), "another crown's province")
	assert_false(CapitalChoice.can_seat(model, 0, 99), "no such province")

	var inland := _blank()
	_add_province(inland, 0, 0, [Vector2i(2, 2)])
	_add_province(inland, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(inland, func(_x: int, _y: int) -> int: return 0)
	assert_false(
		CapitalChoice.can_seat(inland, 0, 0), "an inland province cannot hold the court"
	)


## The chart glows exactly the provinces the court may sit in: the crown's
## sea-bound holdings, in province order — never a rival's shore or an inland
## holding that would only earn a refusal.
func test_seatable_provinces_lists_only_the_crowns_seaboards() -> void:
	var model := _two_islands()
	_add_province(model, 2, 0, _block(2, 4, 6, 7))
	assert_true(CapitalChoice.is_sea_bound(model, 2), "the third holding reaches the sea")
	var expected: Array[int] = [0, 2]
	assert_eq(CapitalChoice.seatable_provinces(model, 0), expected)
	var auto_seat: int = int(CapitalChoice.pick_province(model, 0)["province_id"])
	assert_true(expected.has(auto_seat), "the auto-choice is one of the glowing provinces")

	var inland := _blank()
	_add_province(inland, 0, 0, [Vector2i(2, 2)])
	_add_province(inland, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(inland, func(_x: int, _y: int) -> int: return 0)
	var none: Array[int] = []
	assert_eq(CapitalChoice.seatable_provinces(inland, 0), none, "inland only: nothing glows")
	assert_eq(CapitalChoice.seatable_provinces(inland, 9), none, "no provinces: nothing glows")


## Seating by hand moves the capital works: the old province keeps its town but
## loses the harbour, the new one gains the court, its roads and town level 4.
func test_seat_capital_moves_the_court_and_its_harbour() -> void:
	var model := _two_owned_coasts()
	var first: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(first["ok"])
	assert_eq(int(first["province_id"]), 0)
	var seat := Vector2i(6, 3)

	var moved: Dictionary = CapitalChoice.seat_capital(model, 0, 1, seat)
	assert_true(moved["ok"])
	assert_eq(int(moved["province_id"]), 1)
	assert_eq(Vector2i(moved["tile"]), seat)
	assert_false(model.provinces[0].capital, "the old seat stands down")
	assert_eq(model.provinces[0].capital_tile, CapitalChoice.NO_TILE)
	assert_true((model.provinces[0].ports as Dictionary).is_empty(), "no stale harbour")
	assert_true((model.provinces[0].road_paths as Array).is_empty(), "no stale roads")
	assert_eq(model.provinces[0].town_development, 1, "the old capital keeps its town")
	assert_true(model.provinces[1].capital)
	assert_eq(model.provinces[1].capital_tile, seat)
	assert_eq(model.provinces[1].town_tile, seat, "the seat is the province town")
	assert_eq(model.provinces[1].town_development, 4)
	assert_true((model.provinces[1].ports as Dictionary).has(0), "the new seat has a port")
	assert_eq(CapitalChoice.seat_province(model, 0), 1)


## Select-then-convert applies to a hand-picked tile too.
func test_seat_capital_converts_the_chosen_tile_to_plains() -> void:
	var model := _two_owned_coasts()
	CapitalChoice.place_capital(model, 0)
	var seat := Vector2i(6, 4)
	var index: int = model.index_of(seat.x, seat.y)
	model.terrain[index] = MapModel.Terrain.HILLS
	model.resource[index] = 3
	model.provinces[1].resource_tile = seat

	var moved: Dictionary = CapitalChoice.seat_capital(model, 0, 1, seat)
	assert_true(moved["ok"])
	assert_true(bool(moved["converted"]))
	assert_eq(model.terrain_at(seat.x, seat.y), MapModel.Terrain.PLAINS)
	assert_eq(model.resource_at(seat.x, seat.y), MapModel.NO_ID)
	assert_false(model.provinces[1].has_resource_tile(), "the resource is cleared")


## A foreign province, an inland one and a tile outside the province are all
## refused, and the court stays where it was.
func test_seat_capital_refuses_foreign_inland_and_outside_tiles() -> void:
	var model := _two_islands()
	CapitalChoice.place_capital(model, 0)
	var before: Vector2i = model.provinces[0].capital_tile

	var foreign: Dictionary = CapitalChoice.seat_capital(model, 0, 1, Vector2i(7, 6))
	assert_false(foreign["ok"])
	assert_eq(String(foreign["error"]), CapitalChoice.ERROR_NOT_OWNED)

	var outside: Dictionary = CapitalChoice.seat_capital(model, 0, 0, Vector2i(7, 6))
	assert_false(outside["ok"])
	assert_eq(String(outside["error"]), CapitalChoice.ERROR_TILE_OUTSIDE)

	var sea: Dictionary = CapitalChoice.seat_capital(model, 0, 0, Vector2i(0, 0))
	assert_false(sea["ok"])
	assert_eq(String(sea["error"]), CapitalChoice.ERROR_TILE_OUTSIDE)

	var inland := _blank()
	_add_province(inland, 0, 0, [Vector2i(2, 2)])
	_add_province(inland, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(inland, func(_x: int, _y: int) -> int: return 0)
	var dry: Dictionary = CapitalChoice.seat_capital(inland, 0, 0, Vector2i(2, 2))
	assert_false(dry["ok"])
	assert_eq(String(dry["error"]), CapitalChoice.ERROR_NOT_SEA_BOUND)

	assert_true(model.provinces[0].capital, "a refused move changes nothing")
	assert_eq(model.provinces[0].capital_tile, before)


func _is_contiguous(path: Array) -> bool:
	for i in range(1, path.size()):
		var step: Vector2i = path[i] - path[i - 1]
		if absi(step.x) + absi(step.y) != 1:
			return false
	return true

# --- test_victory_standings ---
const victory_standings_Fixture = preload("res://tests/map_fixture.gd")
const SPAIN: int = FactionCatalog.PLAYER_FACTION
const ENGLAND: int = 1
const FRANCE: int = 2
const HARD: String = "hard"

var victory_standings_saved_world: Array = []
var victory_standings_saved_region: Array = []

func _setup_victory_standings() -> void:
	if victory_standings_saved_world.is_empty():
		victory_standings_saved_world = victory_standings_Fixture.snapshot(victory_standings_Fixture.world())
		victory_standings_saved_region = victory_standings_Fixture.snapshot(
			_victory_standings_wrap(victory_standings_Fixture.region())
		)
	victory_standings_Fixture.restore(victory_standings_Fixture.world(), victory_standings_saved_world)
	victory_standings_Fixture.restore(
		_victory_standings_wrap(victory_standings_Fixture.region()), victory_standings_saved_region
	)

# --- the rows ----------------------------------------------------------------


func test_every_great_power_is_ranked_by_old_world_holdings() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 4, ENGLAND: 9, FRANCE: 2})
	var standings: Array[Dictionary] = VictoryStandings.rows(world, SPAIN)
	assert_eq(standings.size(), FactionCatalog.great_power_ids().size())
	assert_eq(String(standings[0]["name"]), "England", "equal bars: the most provinces leads")
	assert_eq(int(standings[0]["holdings"]), 9)
	assert_eq(int(standings[0]["need"]), 22, "a rival clears the published 31")
	assert_eq(String(standings[1]["name"]), "Spain")
	assert_true(bool(standings[1]["human"]), "the reader's row is marked")


func test_the_crown_bar_carries_the_level_and_rivals_keep_the_published_one() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 30, ENGLAND: 30})
	var crown: Dictionary = VictoryStandings.crown_row(
		VictoryStandings.rows(world, SPAIN, HARD), SPAIN
	)
	var rival: Dictionary = VictoryStandings.next_rival(
		VictoryStandings.rows(world, SPAIN, HARD)
	)
	assert_eq(int(crown["bar"]), 36, "hard scales the crown's own bar")
	assert_eq(int(rival["bar"]), 31, "every rival keeps the published bar")
	assert_eq(int(crown["need"]), 6)
	assert_eq(int(rival["need"]), 1)


func test_only_old_world_provinces_count() -> void:
	_setup_victory_standings()
	var world: WorldMap = victory_standings_Fixture.world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 5})
	var before: int = int(VictoryStandings.crown_row(VictoryStandings.rows(world, SPAIN), SPAIN)["holdings"])
	_victory_standings_seat(world.region(WorldMap.NEW_WORLD), {SPAIN: 20})
	var after: int = int(VictoryStandings.crown_row(VictoryStandings.rows(world, SPAIN), SPAIN)["holdings"])
	assert_eq(after, before, "a New World empire is not the age")
	assert_eq(after, 5)


func test_a_shared_holdings_count_keeps_the_smaller_id_first() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 7, ENGLAND: 7, FRANCE: 7})
	var standings: Array[Dictionary] = VictoryStandings.rows(world, SPAIN)
	assert_eq(int(standings[0]["id"]), SPAIN)
	assert_eq(int(standings[1]["id"]), ENGLAND)
	assert_eq(int(standings[2]["id"]), FRANCE)


# --- the court's line --------------------------------------------------------


## The race ranks each crown against **its own** bar: on a harder level the crown
## carries a 36 bar, so a rival holding fewer provinces can stand nearer the age
## (wiki: victory § Military victory; DR-20261112-05 — `England leads with 9 of
## 31` beside `you hold 12 of 36`).
func test_the_race_ranks_by_distance_to_each_crown_bar() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 12, ENGLAND: 9})
	var standings: Array[Dictionary] = VictoryStandings.rows(world, SPAIN, HARD)
	assert_eq(String(standings[0]["name"]), "England", "the nearer crown leads")
	assert_eq(int(standings[0]["need"]), 22)
	assert_eq(int(standings[1]["need"]), 24, "twelve of thirty-six is the longer road")
	var line: String = VictoryStandings.line(world, 3, SPAIN, HARD)
	assert_true(line.contains("England leads with 9 of 31"), line)
	assert_false(line.contains("you lead"), "more provinces is not the same as nearer the age")


## The crown can hold the most provinces in the world and still be told it is
## behind: at hard, 30 of 36 is six away while a rival's 29 of 31 is two.
func test_the_crown_is_named_behind_though_it_holds_the_most() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 30, ENGLAND: 29})
	var line: String = VictoryStandings.line(world, 3, SPAIN, HARD)
	assert_true(line.contains("England leads with 29 of 31"), line)
	assert_false(line.contains("you lead"), "the crown's own bar sets its road, not the rival's")


func test_the_line_names_the_crown_the_leader_and_the_calendar() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 9, ENGLAND: 12})
	var line: String = VictoryStandings.line(world, 5, SPAIN)
	assert_true(line.contains("you hold 9 of 31 Old World provinces"), line)
	assert_true(line.contains("England leads with 12 of 31"), line)
	assert_true(line.contains("the calendar closes in %d turns" % (TurnTime.cap_turn() - 5)), line)


func test_the_line_says_when_the_crown_leads() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 14, ENGLAND: 9})
	var line: String = VictoryStandings.line(world, 3, SPAIN)
	assert_true(line.contains("you lead"), line)
	assert_true(line.contains("England follows with 9 of 31"), line)


func test_the_line_reads_the_advanced_bar_at_a_harder_level() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 9, ENGLAND: 12})
	var line: String = VictoryStandings.line(world, 3, SPAIN, HARD)
	assert_true(line.contains("you hold 9 of 36"), line)
	assert_true(line.contains("England leads with 12 of 31"), line)


func test_an_endless_campaign_names_no_calendar() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 12, ENGLAND: 9})
	var line: String = VictoryStandings.line(world, 3, SPAIN, Difficulty.DEFAULT, true)
	assert_true(line.contains("no calendar closes this age"), line)
	assert_false(line.contains("calendar closes in"), line)


func test_the_line_is_empty_without_a_crown_to_read() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {ENGLAND: 9})
	assert_eq(VictoryStandings.line(world, 3), "", "the full-AI observer has no crown")


# --- the turn's warning ------------------------------------------------------


func test_the_warning_is_silent_while_the_age_is_distant() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 10, ENGLAND: 12})
	assert_eq(VictoryStandings.warning(world, SPAIN), "")


func test_the_warning_names_a_rival_within_three_provinces() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 10, ENGLAND: 28})
	var warning: String = VictoryStandings.warning(world, SPAIN)
	assert_eq(warning, "England stands 3 provinces from the age (28 of 31 Old World).")


func test_the_warning_counts_one_province_in_the_singular() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 10, ENGLAND: 30})
	var warning: String = VictoryStandings.warning(world, SPAIN)
	assert_eq(warning, "England stands 1 province from the age (30 of 31 Old World).")


func test_the_warning_names_the_crown_too() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 34, ENGLAND: 10})
	var warning: String = VictoryStandings.warning(world, SPAIN, HARD)
	assert_eq(warning, "Your crown stands 2 provinces from the age (34 of 36 Old World).")


func test_the_warning_names_both_when_both_are_close() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 29, ENGLAND: 28})
	var warning: String = VictoryStandings.warning(world, SPAIN)
	assert_eq(
		warning,
		"Your crown stands 2 provinces from the age (29 of 31 Old World). "
		+ "England stands 3 provinces from the age (28 of 31 Old World)."
	)


func test_a_crown_on_its_bar_is_not_merely_warned() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 10, ENGLAND: 31})
	# The victory check closes the campaign before a warning could print; the
	# reading stays silent so the two never disagree.
	assert_eq(VictoryStandings.warning(world, SPAIN), "")


# --- fixtures ----------------------------------------------------------------


## A single-region world over the shared small map, with every province
## unclaimed until a case seats it.
func _victory_standings_old_world() -> WorldMap:
	var world: WorldMap = _victory_standings_wrap(victory_standings_Fixture.region())
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {})
	return world


## The shared small map wrapped as a one-region world, so the fixture's
## snapshot/restore pair can read it.
static func _victory_standings_wrap(model: MapModel) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(model)
	return world


## Hands the province list to the crowns in the order given, the rest unclaimed.
func _victory_standings_seat(model: MapModel, counts: Dictionary) -> void:
	var owners: Array[int] = []
	for faction_id: int in counts:
		for _index in int(counts[faction_id]):
			owners.append(faction_id)
	for index in model.provinces.size():
		model.provinces[index].owner = owners[index] if index < owners.size() else MapModel.NO_ID

# --- from test_gazette.gd ---
## The Gazette: one sheet per resolved turn and its watchlist.
# gdlint: disable=max-public-methods
## The Gazette's rules: the watchlist and its archive, the three classes and
## Also includes gazette plate (one Godot boot).
## their order, the imperial prose, and the PlayerView masking (wiki:
## the-gazette; DR-20261110-14). Pure rules — no map screen, no HUD.

const Fixture = preload("res://tests/map_fixture.gd")

const VIEWER: int = 0
const GAZ_ENGLAND: int = 1
const GAZ_FRANCE: int = 2
const AZTEC: int = 9
const TLAXCALA: int = 10
const GENOA: int = 6

## Cached two-region world; only province and zone names are read from it.
var world: WorldMap = null


func before_all() -> void:
	world = Fixture.world()
	loss_pristine_map = Fixture.snapshot(Fixture.world())
	loss_mounted = Fixture.attach_screen(self)
	loss_pristine = Fixture.suite_capture(loss_mounted)


func after_all() -> void:
	world = null
	if is_instance_valid(loss_mounted):
		loss_mounted.free()
	loss_mounted = null
	loss_pristine = {}
	loss_pristine_map = []


func after_each() -> void:
	_teardown_gazette_plate()


# --- watchlist ---------------------------------------------------------------


func test_the_watchlist_seeds_from_the_bonds_the_campaign_opens_with() -> void:
	var state: DiplomacyState = _state(2)
	var gazette := GazetteState.new()
	GazetteState.seed(gazette, state, VIEWER)
	assert_true(gazette.is_watched(GAZ_ENGLAND), "an embassy puts a court on the list")
	assert_true(gazette.is_watched(GAZ_FRANCE))
	assert_false(gazette.is_watched(AZTEC), "a people the crown has not met is not")


func test_a_removal_sticks_even_when_the_bond_remains() -> void:
	var state: DiplomacyState = _state(2)
	var gazette := GazetteState.new()
	GazetteState.seed(gazette, state, VIEWER)
	gazette.set_watched(GAZ_ENGLAND, false)
	GazetteState.seed(gazette, state, VIEWER)
	assert_false(gazette.is_watched(GAZ_ENGLAND), "seed never undoes a player's removal")


func test_a_bond_formed_later_reseeds_the_court() -> void:
	var state: DiplomacyState = _state(2)
	var gazette := GazetteState.new()
	GazetteState.seed(gazette, state, VIEWER)
	gazette.set_watched(GAZ_FRANCE, false)
	state.set_overture(VIEWER, AZTEC, DiplomacyCatalog.STAGE_NAP)
	GazetteState.seed(gazette, state, VIEWER)
	assert_true(gazette.is_watched(AZTEC), "a new pact puts the court on the list")
	assert_false(gazette.is_watched(GAZ_FRANCE), "the struck-off court stays off")


func test_the_watchlist_and_the_archive_round_trip_through_a_save() -> void:
	var gazette := GazetteState.new()
	gazette.set_watched(GAZ_ENGLAND, true)
	gazette.set_watched(GAZ_FRANCE, false)
	gazette.append(_sheet(2, "one"))
	gazette.append(_sheet(3, "two"))
	var restored: GazetteState = GazetteState.from_dict(gazette.to_dict())
	assert_true(restored.is_watched(GAZ_ENGLAND))
	assert_false(restored.is_watched(GAZ_FRANCE), "a removal survives the round trip")
	assert_eq(restored.sheets.size(), 2)
	assert_eq(restored.newest_turn(), 3)
	assert_eq(restored.history()[0]["turn"], 3, "history reads newest first")


# --- classification ----------------------------------------------------------


func test_a_war_between_other_great_powers_is_world_news() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", GAZ_ENGLAND, GAZ_FRANCE)
	var items: Array = _items(state, [])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.WORLD)
	assert_true(String(items[0]["text"]).contains("gauntlet"), "thick imperial voice")


func test_the_crowns_own_war_is_our_court_news() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", VIEWER, GAZ_FRANCE)
	var items: Array = _items(state, [])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	assert_true(String(items[0]["text"]).contains("Our crown"))


## A watched court's war is still a public epoch fact, and the classes are
## exclusive in order: World outranks Courts of interest (wiki: the-gazette
## § Classes).
func test_a_watched_courts_war_is_still_world_news() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", GAZ_ENGLAND, GAZ_FRANCE)
	var items: Array = _items(state, [GAZ_ENGLAND])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.WORLD)


## A watched court's quieter act — a league, a finished study — is what the
## interest page is for.
func test_a_watched_courts_league_is_news_of_interest() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("allianceFormed", GAZ_ENGLAND, GAZ_FRANCE)
	var items: Array = _items(state, [GAZ_ENGLAND])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.INTEREST)


func test_a_strangers_private_war_stays_out_of_the_sheet() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", AZTEC, TLAXCALA)
	var items: Array = _items(state, [])
	assert_eq(items.size(), 0, "an unmet court cannot be named, so it is not printed")


func test_display_order_is_world_then_our_court_then_interest() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", GAZ_ENGLAND, GAZ_FRANCE)  # World
	state.record_event("peaceMade", VIEWER, GAZ_FRANCE)  # Our court
	state.record_event("allianceFormed", GAZ_ENGLAND, GAZ_FRANCE)  # Interest, when watched
	var classes: Array[int] = []
	for item: Variant in _items(state, [GAZ_ENGLAND]):
		classes.append(int((item as Dictionary)["class"]))
	assert_eq(classes, [Gazette.Class.WORLD, Gazette.Class.COURT, Gazette.Class.INTEREST])


func test_an_empty_turn_is_still_archived_so_the_history_has_no_gaps() -> void:
	var sheet: Dictionary = Gazette.collect(
		VIEWER, 4, world, _state(4), [], [], [], [], {}, 0, []
	)
	assert_true(Gazette.is_empty(sheet), "nothing to print")
	var gazette := GazetteState.new()
	gazette.append(sheet)
	assert_eq(gazette.sheets.size(), 1, "the archive still takes the turn")
	assert_true(gazette.has_sheet(4))


# --- battles, studies, treasury, raids ---------------------------------------


func test_a_capture_prints_the_province_and_the_regiments_lost() -> void:
	var province: int = _province()
	var battle: Dictionary = {
		"attacker": VIEWER,
		"defender": GAZ_FRANCE,
		"region": 0,
		"province": province,
		"outcome": ArmyCombat.Outcome.CAPTURE,
		"captured": true,
		"defender_lost": [1, 2],
	}
	var items: Array = _items(_state(3), [], [battle])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	var text: String = String(items[0]["text"])
	assert_true(text.contains(_province_name(province)))
	assert_true(text.contains("2 regiments"))


func test_a_battle_between_unwatched_courts_is_never_reported() -> void:
	var battle: Dictionary = {
		"attacker": GAZ_ENGLAND,
		"defender": GAZ_FRANCE,
		"region": 0,
		"province": _province(),
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"defender_lost": [1],
	}
	assert_eq(_items(_state(3), [], [battle]).size(), 0)


func test_a_watched_courts_sea_battle_reports_both_courts() -> void:
	var battle: Dictionary = {
		"attacker": GAZ_ENGLAND,
		"defender": GAZ_FRANCE,
		"region": 0,
		"zone": 0,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"defender_lost": [1, 2, 3],
	}
	var items: Array = _items(_state(3), [GAZ_ENGLAND], [], [battle])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.INTEREST)
	var text: String = String(items[0]["text"])
	assert_true(text.contains("England"))
	assert_false(text.contains("3 hulls"), "another court's losses are never counted")


## Charted is the gate for a watched court's fight, and the crown's own chart is
## what counts (wiki: the-gazette § What the crown can know; DR-20261110-28).
func test_a_watched_courts_battle_in_uncharted_land_is_not_printed() -> void:
	var province: int = _new_world_province()
	var battle: Dictionary = {
		"attacker": GAZ_ENGLAND,
		"defender": GAZ_FRANCE,
		"region": 1,
		"province": province,
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"defender_lost": [1],
	}
	assert_eq(
		_items(_state(3), [GAZ_ENGLAND], [battle], [], {}, 0, [], [], _charts()).size(),
		0,
		"uncharted ground prints nothing"
	)
	var charted: Array = _items(
		_state(3), [GAZ_ENGLAND], [battle], [], {}, 0, [], [], _charts(province)
	)
	assert_eq(charted.size(), 1, "the crown's own chart opens the place")
	assert_eq(int(charted[0]["class"]), Gazette.Class.INTEREST)
	assert_false(
		String(charted[0]["text"]).contains("1 regiments"),
		"a charted fight still prints no casualty count"
	)


func test_a_watched_courts_battle_in_uncharted_water_is_not_printed() -> void:
	var zone: int = _new_world_zone()
	var battle: Dictionary = {
		"attacker": GAZ_ENGLAND,
		"defender": GAZ_FRANCE,
		"region": 1,
		"zone": zone,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"defender_lost": [1, 2],
	}
	assert_eq(_items(_state(3), [GAZ_ENGLAND], [], [battle], {}, 0, [], [], _charts()).size(), 0)
	assert_eq(
		_items(_state(3), [GAZ_ENGLAND], [], [battle], {}, 0, [], [], _charts(-1, zone)).size(),
		1,
		"charted water carries the line"
	)


## A watched court's study is a spy's finding, never the sheet's
## (wiki: civilian-units § Spy; DR-20261110-28).
func test_a_watched_courts_finished_study_is_never_printed() -> void:
	var research: Dictionary = {VIEWER: ["crop_rotation"], GAZ_ENGLAND: ["crop_rotation"]}
	var items: Array = _items(_state(3), [GAZ_ENGLAND], [], [], research)
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	assert_true(String(items[0]["text"]).contains(TechCatalog.display_name("crop_rotation")))


## A watched court's capture and hold read as fact without a body count: the
## place, the winner and the beaten side only (DR-20261110-28).
func test_a_watched_courts_capture_and_hold_print_no_numbers() -> void:
	var province: int = _new_world_province()
	var charts: CourtCharts = _charts(province)
	var capture: Dictionary = {
		"attacker": GAZ_ENGLAND,
		"defender": GAZ_FRANCE,
		"region": 1,
		"province": province,
		"outcome": ArmyCombat.Outcome.CAPTURE,
		"captured": true,
		"defender_lost": [1, 2, 3],
	}
	var held: Dictionary = {
		"attacker": GAZ_ENGLAND,
		"defender": GAZ_FRANCE,
		"region": 1,
		"province": province,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"attacker_lost": [1, 2],
	}
	var items: Array = _items(_state(3), [GAZ_ENGLAND], [capture, held], [], {}, 0, [], [], charts)
	assert_eq(items.size(), 2)
	for item: Variant in items:
		var text: String = String((item as Dictionary)["text"])
		assert_false(text.contains("regiment"), "no casualties for another court: %s" % text)
		assert_true(text.contains("England") and text.contains("France"))


## The crown's own fight prints with numbers wherever it happens: its own report
## is not gated by its chart.
func test_the_crowns_own_battle_ignores_the_chart() -> void:
	var battle: Dictionary = {
		"attacker": VIEWER,
		"defender": GAZ_FRANCE,
		"region": 1,
		"province": _new_world_province(),
		"outcome": ArmyCombat.Outcome.CAPTURE,
		"captured": true,
		"defender_lost": [1, 2],
	}
	var items: Array = _items(_state(3), [], [battle], [], {}, 0, [], [], _charts())
	assert_eq(items.size(), 1)
	assert_true(String(items[0]["text"]).contains("2 regiments"))


## The crown's own losses always print their numbers, even when it did not win
## (wiki: the-gazette § What the crown can know).
func test_a_field_battle_the_crown_loses_prints_its_dead() -> void:
	var battle: Dictionary = {
		"attacker": GAZ_FRANCE,
		"defender": VIEWER,
		"region": 0,
		"province": _province(),
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"attacker_lost": [1],
		"defender_lost": [1, 2, 3],
	}
	var items: Array = _items(_state(3), [], [battle])
	assert_eq(items.size(), 1)
	var text: String = String(items[0]["text"])
	assert_true(text.contains("3 of our regiments are lost"), text)


## A fought win that takes the province is a capture on the crown's page: the
## sheet must say the province changed hands, not only that the field was held
## (wiki: the-gazette § Item catalog — "Provinces the crown took or lost").
func test_a_fought_capture_prints_the_province_lost() -> void:
	var battle: Dictionary = {
		"attacker": GAZ_FRANCE,
		"defender": VIEWER,
		"region": 0,
		"province": _province(),
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"captured": true,
		"attacker_lost": [1],
		"defender_lost": [1],
	}
	var items: Array = _items(_state(3), [], [battle])
	assert_eq(items.size(), 1)
	var text: String = String(items[0]["text"])
	assert_true(text.contains("has carried"), text)
	assert_true(text.contains("1 of our regiments is lost"), text)


## An advantage holds the field and leaves the province with its owner, so the
## sheet keeps the held-field line (wiki: quick-battle § Outcome and integration).
func test_an_advantage_still_reads_as_a_held_field() -> void:
	var battle: Dictionary = {
		"attacker": GAZ_FRANCE,
		"defender": VIEWER,
		"region": 0,
		"province": _province(),
		"outcome": ArmyCombat.Outcome.ATTACKER_ADVANTAGE,
		"attacker_lost": [1],
		"defender_lost": [1],
	}
	var items: Array = _items(_state(3), [], [battle])
	assert_eq(items.size(), 1)
	assert_true(String(items[0]["text"]).contains("holds the field"), String(items[0]["text"]))


func test_a_standoff_prints_the_crowns_own_dead() -> void:
	var battle: Dictionary = {
		"attacker": VIEWER,
		"defender": GAZ_FRANCE,
		"region": 0,
		"province": _province(),
		"outcome": ArmyCombat.Outcome.STALEMATE,
		"attacker_lost": [1, 2],
		"defender_lost": [1],
	}
	var items: Array = _items(_state(3), [], [battle])
	assert_eq(items.size(), 1)
	var text: String = String(items[0]["text"])
	assert_true(text.contains("2 of our regiments lost"), text)


## A beaten squadron that slips away still costs the crown that held the water
## hulls (wiki: the-gazette § What the crown can know; ships-and-naval § Naval
## Combat Resolution).
func test_a_withdrawal_that_costs_the_crown_hulls_prints_them() -> void:
	var battle: Dictionary = {
		"attacker": GAZ_FRANCE,
		"defender": VIEWER,
		"region": 0,
		"zone": 0,
		"outcome": NavalCombat.Outcome.SIDE2_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["h1"],
		"retreat": {"ok": true, "success": true, "beaten": GAZ_FRANCE},
	}
	var items: Array = _items(_state(3), [], [], [battle])
	assert_eq(items.size(), 1)
	var text: String = String(items[0]["text"])
	assert_true(text.contains("1 of our hulls lost"), text)


## Another court's standoff and withdrawal still print no numbers
## (wiki: the-gazette § What the crown can know; DR-20261110-28).
func test_a_watched_courts_standoff_and_withdrawal_print_no_numbers() -> void:
	var province: int = _new_world_province()
	var zone: int = _new_world_zone()
	var standoff: Dictionary = {
		"attacker": GAZ_ENGLAND,
		"defender": GAZ_FRANCE,
		"region": 1,
		"province": province,
		"outcome": ArmyCombat.Outcome.STALEMATE,
		"attacker_lost": [1, 2],
		"defender_lost": [1],
	}
	var withdrawal: Dictionary = {
		"attacker": GAZ_ENGLAND,
		"defender": GAZ_FRANCE,
		"region": 1,
		"zone": zone,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": ["h1"],
		"defender_lost": [],
		"retreat": {"ok": true, "success": true, "beaten": GAZ_FRANCE},
	}
	var items: Array = _items(
		_state(3), [GAZ_ENGLAND], [standoff], [withdrawal], {}, 0, [], [],
		_charts(province, zone)
	)
	assert_eq(items.size(), 2)
	for item: Variant in items:
		var text: String = String((item as Dictionary)["text"])
		assert_false(text.contains("regiment"), "no casualties for another court: %s" % text)
		assert_false(text.contains("hull"), "no hulls for another court: %s" % text)


func test_deed_income_is_our_court_news() -> void:
	var items: Array = _items(_state(3), [], [], [], {}, 1250)
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	assert_true(String(items[0]["text"]).contains("estates"))


func test_a_prize_taken_off_rival_trade_prints_as_a_prize() -> void:
	var raids: Array = [
		{
			"kind": "prize",
			"zone_name": "the Windward Passage",
			"losses": {"grain": 3},
		}
	]
	var items: Array = _items(_state(3), [], [], [], {}, 0, raids)
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	assert_true(String(items[0]["text"]).contains("3 grain"))


## A raid that sends a merchant down says so in the record (DR-20261111-17).
func test_a_raid_that_sinks_a_merchant_names_her_in_the_gazette() -> void:
	var raids: Array = [
		{
			"kind": "prize",
			"zone_name": "the Windward Passage",
			"losses": {"grain": 3},
			"hulls_lost": [{"type_id": "fluyte", "name": "Vrouw Maria"}],
		},
		{
			"kind": "incoming",
			"zone_name": "Mar Caribe",
			"losses": {"timber": 2},
			"hulls_lost": [{"type_id": "carrack", "name": "Santa Ana"}],
		},
	]
	var items: Array = _items(_state(3), [], [], [], {}, 0, raids)
	assert_eq(items.size(), 2)
	assert_true(String(items[0]["text"]).contains("sends the Fluyte Vrouw Maria down"))
	assert_true(String(items[1]["text"]).contains("sent the Carrack Santa Ana to the bottom"))


func test_a_great_powers_fall_is_world_news() -> void:
	var falls: Array = [{"faction": GAZ_FRANCE, "conqueror": GAZ_ENGLAND}]
	var items: Array = _items(_state(3), [], [], [], {}, 0, [], falls)
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.WORLD)
	assert_true(String(items[0]["text"]).contains("France"))


## A Minor Nation falling is map cleanup, not a struck name on the roll of
## powers (wiki: the-gazette § Item catalog — World).
func test_a_minor_nations_fall_is_not_world_news() -> void:
	var falls: Array = [{"faction": GENOA, "conqueror": GAZ_ENGLAND}]
	assert_eq(_items(_state(3), [], [], [], {}, 0, [], falls).size(), 0)


## A crown leaves play with its dealings: the fall clears the fallen court's
## relations, so the sheet must read the knowledge the crown held when the court
## fell, not the relations left afterwards (wiki: the-gazette § Item catalog —
## World, "Great Power terminal fall").
func test_a_great_powers_fall_prints_after_its_relations_are_cleared() -> void:
	var state: DiplomacyState = _state(3)
	var falls: Array = [{"faction": GAZ_FRANCE, "conqueror": GAZ_ENGLAND, "known": true}]
	state.clear_relations_of(GAZ_FRANCE)
	var items: Array = _items(state, [], [], [], {}, 0, [], falls)
	assert_eq(items.size(), 1, "a met crown's fall is still world news")
	assert_eq(int(items[0]["class"]), Gazette.Class.WORLD)
	assert_true(String(items[0]["text"]).contains("France"))


## The World page is the epoch's own news: a Great Power's war or peace with a
## Minor Nation is that court's doing, not the world's (wiki: the-gazette
## § Item catalog — World, "GP–GP declaration of war or peace").
func test_a_great_powers_war_on_a_minor_is_not_world_news() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", GAZ_ENGLAND, GENOA)
	var items: Array = _items(state, [GAZ_ENGLAND])
	assert_eq(items.size(), 1)
	assert_eq(
		int(items[0]["class"]), Gazette.Class.INTEREST,
		"a watched court's war on a Minor is news of interest"
	)
	assert_eq(_items(state, []).size(), 0, "an unwatched court's war on a Minor is no news")


func test_a_great_powers_peace_with_a_minor_is_not_world_news() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("peaceMade", GAZ_ENGLAND, GENOA)
	var items: Array = _items(state, [GAZ_ENGLAND])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.INTEREST)


## One act, one line: a proposal answer is the treaty it answered, so the sheet
## prints the act once (wiki: the-gazette § Item catalog — the catalogue lists
## the acts, not the offers that led to them).
func test_a_refused_overture_proposal_prints_once() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event(
		"overtureRejected", GAZ_FRANCE, VIEWER, {"stage": DiplomacyCatalog.STAGE_NAP}
	)
	state.record_event(
		"proposalRefused", GAZ_FRANCE, VIEWER,
		{"kind": DiplomacyProposals.KIND_OVERTURE, "stage": DiplomacyCatalog.STAGE_NAP}
	)
	assert_eq(_items(state, []).size(), 1, "the refusal prints once")


func test_an_accepted_overture_proposal_prints_once() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event(
		"overtureEstablished", GAZ_FRANCE, VIEWER, {"stage": DiplomacyCatalog.STAGE_NAP}
	)
	state.record_event(
		"proposalAccepted", GAZ_FRANCE, VIEWER,
		{"kind": DiplomacyProposals.KIND_OVERTURE, "stage": DiplomacyCatalog.STAGE_NAP}
	)
	assert_eq(_items(state, []).size(), 1, "the establishment prints once")


## A refused alliance or peace offer has no act of its own, so the answer is the
## news and must still print.
func test_a_refused_alliance_proposal_still_prints() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event(
		"proposalRefused", GAZ_FRANCE, VIEWER,
		{"kind": DiplomacyProposals.KIND_ALLIANCE, "stage": ""}
	)
	assert_eq(_items(state, []).size(), 1)


# --- prose -------------------------------------------------------------------


## Every catalogue kind this sheet can print must produce a filled line: no
## template may leave a field or print nothing (REQ-P2-03, REQ-P1-07).
func test_every_catalogue_kind_prints_a_filled_line() -> void:
	var base: Dictionary = {
		"who": "England",
		"whom": "France",
		"aggressor": "Spain",
		"target": "France",
		"place": "Coro",
		"label": "Embassy",
		"count": 3,
		"prize": "3 grain",
		"bonus": "Tercio",
		"amount": 1250,
		"percent": 10,
		"cause": "war",
	}
	var kinds: Array[String] = [
		"warDeclared",
		"peaceMade",
		"allianceFormed",
		"allianceBroken",
		"joinEmpire",
		"colonyFormed",
		"colonyReleased",
		"overtureEstablished",
		"overtureRejected",
		"callToArmsAccepted",
		"callToArmsRefused",
		"interventionProtest",
		"interventionIntervened",
		"interventionDoNothing",
		"proposalAccepted",
		"proposalRefused",
		"subsidySet",
		"subsidyCancelled",
		"ftpSigned",
		"ftpRefused",
		"ftpRevoked",
		"boycottSet",
		"boycottRevoked",
		"grantAid",
		"firstContact",
		"greatPowerFell",
		"battleCapture",
		"battleHeld",
		"battleAnnihilated",
		"battleStandoff",
		"seaHeld",
		"seaWithdrew",
		"seaDraw",
		"techFinished",
		"richesRendered",
		"raidSuffered",
		"raidPrize",
	]
	for kind: String in kinds:
		for self_act: bool in [true, false]:
			var rec: Dictionary = base.duplicate()
			rec["kind"] = kind
			rec["self_act"] = self_act
			var text: String = GazetteCopy.line(rec)
			assert_false(text.is_empty(), "%s prints a line" % kind)
			assert_false(
				text.contains("%s") or text.contains("%d"),
				"%s leaves no unfilled field" % kind
			)


## Every narrated diplomacy kind builds a record, and the record prints.
func test_every_narrated_diplomacy_kind_builds_and_prints() -> void:
	var state: DiplomacyState = _state(3)
	for kind: String in GazetteDiplomacy.COURT_KINDS:
		var event: Dictionary = {
			"kind": kind,
			"a": VIEWER,
			"b": GAZ_FRANCE,
			"turn": 3,
			"data": {
				"aggressor": GAZ_ENGLAND,
				"target": GAZ_FRANCE,
				"stage": DiplomacyCatalog.STAGE_EMBASSY,
				"kind": DiplomacyProposals.KIND_PEACE,
				"percent": 10,
				"amount": 1000,
				"cause": "war",
			},
		}
		var rec: Dictionary = GazetteDiplomacy.record(kind, event, state, VIEWER)
		assert_false(rec.is_empty(), "%s builds a record" % kind)
		assert_false(GazetteCopy.line(rec).is_empty(), "%s prints" % kind)


## Every Combat outcome the rules can return reaches the sheet with a line.
func test_every_combat_outcome_reaches_the_sheet() -> void:
	var land: Array[int] = [
		ArmyCombat.Outcome.ATTACKER_VICTORY,
		ArmyCombat.Outcome.DEFENDER_VICTORY,
		ArmyCombat.Outcome.STALEMATE,
		ArmyCombat.Outcome.MUTUAL_ANNIHILATION,
		ArmyCombat.Outcome.CAPTURE,
		ArmyCombat.Outcome.ATTACKER_ADVANTAGE,
	]
	for outcome: int in land:
		var battle: Dictionary = _battle(outcome)
		var items: Array = _items(_state(3), [], [battle])
		assert_eq(items.size(), 1, "land outcome %d prints" % outcome)
	var sea: Array[int] = [
		NavalCombat.Outcome.SIDE1_VICTORY, NavalCombat.Outcome.SIDE2_VICTORY,
		NavalCombat.Outcome.STALEMATE,
	]
	for outcome: int in sea:
		var battle: Dictionary = _sea_battle(outcome)
		var items: Array = _items(_state(3), [], [], [battle])
		assert_eq(items.size(), 1, "sea outcome %d prints" % outcome)
	var retreat: Dictionary = _sea_battle(NavalCombat.Outcome.STALEMATE)
	retreat["retreat"] = {"success": true, "beaten": VIEWER}
	assert_eq(_items(_state(3), [], [], [retreat]).size(), 1, "a withdrawal prints")


func test_the_prose_never_invents_an_outcome_for_an_unknown_kind() -> void:
	assert_eq(GazetteCopy.line({"kind": "noSuchThing"}), "")


## The copy desk's table is the sheet's one list of kinds, so a kind the
## diplomacy catalogue narrates cannot fall off the desk (REQ-P2-03, RUB-P3-01).
func test_every_narrated_kind_has_a_copy_desk() -> void:
	var narrated: Array[String] = []
	narrated.append_array(GazetteDiplomacy.COURT_KINDS)
	narrated.append_array(GazetteDiplomacy.WORLD_KINDS)
	for kind: String in narrated:
		assert_true(GazetteCopy.kinds().has(kind), "%s has a copy desk" % kind)


func test_an_unmet_party_reads_as_an_unknown_faction() -> void:
	var state: DiplomacyState = _state(3)
	var line: String = GazetteCopy.line(
		GazetteDiplomacy.record(
			"warDeclared",
			{"kind": "warDeclared", "a": AZTEC, "b": GAZ_FRANCE, "turn": 3, "data": {}},
			state,
			VIEWER
		)
	)
	assert_true(line.contains("Unknown faction"), "a stranger is never named")


# --- helpers -----------------------------------------------------------------


## A diplomacy ledger at `turn` with the opening embassies in place.
func _state(turn: int) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.initialize(1)
	state.turn = turn
	return state


func _sheet(turn: int, text: String) -> Dictionary:
	return {
		"turn": turn,
		"items": [{"class": Gazette.Class.COURT, "kind": "techFinished", "text": text}],
	}


# --- build/work: what the crown's orders delivered ---------------------------


## A completed recruit prints on Our court page, in the same sheet as the rest of
## the turn (wiki: the-gazette § Item catalog; workers-and-population
## § Phase placement).
func test_a_completed_recruit_prints_on_our_court_page() -> void:
	var musters: Array = [
		{"kind": "workerRecruited", "label": "Apprentice"},
		{"kind": "civilianMustered", "label": "Builder", "place": "London"},
		{"kind": "regimentMustered", "label": "Peasant Levies"},
		{"kind": "shipLaunched", "label": "Carrack", "place": "London"},
	]
	var items: Array = _muster_items(musters)
	assert_eq(items.size(), 4)
	for item: Dictionary in items:
		assert_eq(int(item["class"]), Gazette.Class.COURT, "the crown's own news")
	assert_true(String(items[0]["text"]).contains("apprentice"))
	assert_true(String(items[1]["text"]).contains("London"))
	assert_true(String(items[3]["text"]).contains("Carrack"))
	assert_true(String(items[3]["text"]).contains("London"))


## A christened regiment prints the title it mustered under
## (DR-20261111-18); a crown with no name for it keeps the plain line.
func test_a_regiment_line_carries_its_title_when_it_has_one() -> void:
	var titled: String = GazetteCopyMuster.regiment_mustered(
		{"label": "Peasant Levies", "title": "The Dorsetshire Foot"}
	)
	assert_true(titled.contains("The Dorsetshire Foot"))
	assert_true(titled.contains("Peasant Levies"))
	var plain: String = GazetteCopyMuster.regiment_mustered({"label": "Peasant Levies"})
	assert_true(plain.contains("new regiment of Peasant Levies"))


## A launched hull prints the name it was christened with beside its type and
## the capital it slid from (wiki: the-gazette § Item catalog — "a hull keeps
## the name it was christened with"; naming § Ship names).
func test_a_launched_hull_line_carries_its_christened_name() -> void:
	var named: String = GazetteCopyMuster.ship_launched(
		{"label": "Carrack", "name": "Trinidad", "place": "Madrid"}
	)
	assert_true(named.contains("Trinidad"), "the christened name prints")
	assert_true(named.contains("Carrack"), "the hull's type prints")
	assert_true(named.contains("Madrid"), "the capital she slid from prints")
	## A record that carries no name keeps the plain launch line.
	var plain: String = GazetteCopyMuster.ship_launched(
		{"label": "Carrack", "place": "Madrid"}
	)
	assert_true(plain.contains("A Carrack slides from the slips at Madrid"))


## A record whose kind has no copy prints nothing, so a sheet never carries an
## empty rule (REQ-P2-03).
func test_an_unknown_muster_kind_prints_nothing() -> void:
	assert_eq(_muster_items([{"kind": "noSuchMuster", "label": "Hulk"}]).size(), 0)
	assert_eq(_muster_items(["not a record"]).size(), 0)


## The sheet's items for one resolved turn.
func _items(
	state: DiplomacyState,
	watched: Array[int],
	land: Array = [],
	naval: Array = [],
	research: Dictionary = {},
	richness: int = 0,
	raids: Array = [],
	falls: Array = [],
	charts: CourtCharts = null
) -> Array:
	var sheet: Dictionary = Gazette.collect(
		VIEWER, 3, world, state, watched, land, naval, falls, research, richness, raids, charts
	)
	return sheet["items"]


## The sheet's items for one resolved turn that also delivered some orders.
func _muster_items(musters: Array) -> Array:
	var sheet: Dictionary = Gazette.collect(
		VIEWER, 3, world, _state(3), [], [], [], [], {}, 0, [], null, musters
	)
	return sheet["items"]


## The crown's chart for a headless sheet: the Old World baseline, plus a New
## World province and/or sea zone the crown has charted when asked.
func _charts(province: int = -1, zone: int = -1) -> CourtCharts:
	var views: Dictionary = {}
	for index in world.region_count():
		var view := VisibilityModel.new()
		view.setup(world.region(index), VIEWER)
		if index == FactionCatalog.NEW_WORLD:
			if province >= 0:
				view.reveal_province(province)
			if zone >= 0:
				view.reveal_sea_zone(zone)
		views[index] = view
	var charts := CourtCharts.new()
	charts.setup(world, VIEWER, views)
	return charts


## An uncharted New World province: the fogged Old World cannot refuse a fight.
func _new_world_province() -> int:
	return int(world.region(FactionCatalog.NEW_WORLD).provinces[0].id)


func _new_world_zone() -> int:
	return int(world.region(FactionCatalog.NEW_WORLD).sea_zones[0].id)


func _province() -> int:
	var model: MapModel = world.region(0)
	return int(model.provinces[0].id)


func _province_name(province: int) -> String:
	return world.region(0).province_name(province)


## A land-battle record of `outcome` between our crown and France.
func _battle(outcome: int) -> Dictionary:
	return {
		"attacker": VIEWER,
		"defender": GAZ_FRANCE,
		"region": 0,
		"province": _province(),
		"outcome": outcome,
		"captured": outcome == ArmyCombat.Outcome.CAPTURE,
		"attacker_lost": [1],
		"defender_lost": [1, 2],
		"garrison": 1,
		"recovered_type": "peasant_levies",
	}


## A sea-battle record of `outcome` in the Old World's first zone.
func _sea_battle(outcome: int) -> Dictionary:
	return {
		"attacker": VIEWER,
		"defender": GAZ_FRANCE,
		"region": 0,
		"zone": 0,
		"outcome": outcome,
		"attacker_lost": [1],
		"defender_lost": [1, 2, 3],
	}

# --- gazette_plate ---
## The soft Gazette plate: the turn-start sheet, the archive and the watchlist
## editor on one surface, dismissible with one press (wiki: the-gazette § When
## it appears, § History screen; DR-20261110-14). Presentation only — the lines
## are what [Gazette] built (REQ-P2-03, REQ-P5-06).

const gazette_plate_VIEWER: int = 0
const gazette_plate_ENGLAND: int = 1

var plate: GazettePlate = null


func _setup_gazette_plate() -> void:
	plate = GazettePlate.new()
	add_child(plate)


func _teardown_gazette_plate() -> void:
	if is_instance_valid(plate):
		plate.free()
	plate = null


func test_the_sheet_prints_its_stamp_and_each_class_heading() -> void:
	_setup_gazette_plate()
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	assert_true(plate.is_shown())
	assert_true(_has_text(plate, "THE GAZETTE"))
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(3)))
	assert_true(_has_text(plate, "THE WORLD"))
	assert_true(_has_text(plate, "OUR COURT"))
	assert_true(_has_text(plate, "The gauntlet passes between them."))


func test_one_press_sets_the_sheet_aside() -> void:
	_setup_gazette_plate()
	var dismissed: Array[bool] = []
	plate.dismissed.connect(func() -> void: dismissed.append(true))
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	plate.dismiss()
	assert_false(plate.is_shown())
	assert_false(plate.visible)
	assert_eq(dismissed.size(), 1)


## The plate is soft: the map under and around it keeps its pointer.
func test_only_the_plate_takes_the_pointer() -> void:
	_setup_gazette_plate()
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	assert_eq(plate.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the map stays usable")
	assert_eq(plate._panel.mouse_filter, Control.MOUSE_FILTER_STOP, "the sheet is readable")


func test_a_turn_that_printed_nothing_says_so() -> void:
	_setup_gazette_plate()
	plate.open_sheet({"turn": 4, "items": []}, GazetteState.new(), null, gazette_plate_VIEWER)
	assert_true(_has_text(plate, GazettePlate.EMPTY_LINE))


## The plate stands as tall as its news and only the news scrolls, so a quiet
## sheet never leaves a reef of blank paper under it.
func test_the_plate_takes_the_height_of_its_news() -> void:
	_setup_gazette_plate()
	plate.size = Vector2(1280, 800)
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	plate._fit()
	assert_eq(plate._panel.offset_bottom, plate._panel.offset_top, "height follows content")
	assert_true(plate._scroll.custom_minimum_size.y >= 120.0, "the sheet keeps a readable body")
	assert_true(plate._scroll.custom_minimum_size.y <= 600.0, "a long sheet scrolls")


## The sheet's foot states the race for the age; the archive, a past sheet, does
## not (wiki: victory § Victory Check; DR-20261112-05).
func test_the_live_sheet_states_the_race_for_the_age() -> void:
	_setup_gazette_plate()
	var age: String = "The age: you hold 12 of 31 Old World provinces; England leads with 9 of 31."
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER, age)
	assert_true(_has_text(plate, "THE STATE OF THE AGE"), "the standing column is printed")
	assert_true(_has_text(plate, "you hold 12 of 31"), age)
	var state := GazetteState.new()
	state.append(gazette_plate_sheet(3))
	plate.open_archive(state, null, gazette_plate_VIEWER)
	assert_false(_has_text(plate, "THE STATE OF THE AGE"), "a past sheet carries no standing")


func test_a_sheet_without_a_reading_prints_no_standing_column() -> void:
	_setup_gazette_plate()
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	assert_false(_has_text(plate, "THE STATE OF THE AGE"))


## The seal opens the history screen; its sheet tab is the live sheet, so the
## race stays readable on a turn that printed no news, and it is the newest
## sheet rather than whatever was on screen last (wiki: the-gazette § History
## screen — the Gazette and every prior turn's sheet are readable there).
func test_the_history_screen_keeps_the_live_sheet_and_its_standing() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	state.append(gazette_plate_sheet(2))
	state.append(gazette_plate_sheet(3))
	var age: String = "The age: you hold 12 of 31 Old World provinces; England leads with 9 of 31."
	plate.open_archive(state, null, gazette_plate_VIEWER, age)
	plate._go(GazettePlate.Mode.SHEET)
	assert_true(_has_text(plate, "THE STATE OF THE AGE"), "the live sheet keeps its standing")
	assert_true(_has_text(plate, age), age)
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(3)), "the newest sheet is read")
	assert_false(_has_text(plate, GazettePlate.EMPTY_LINE), "a filed sheet is not empty news")


func test_the_archive_opens_on_the_newest_sheet_and_walks_back() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	state.append(gazette_plate_sheet(2))
	state.append(gazette_plate_sheet(3))
	plate.open_archive(state, null, gazette_plate_VIEWER)
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(3)))
	plate._step(1)
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(2)))
	assert_true(plate._older.disabled, "the oldest sheet has no older neighbour")
	plate._step(-1)
	assert_true(plate._newer.disabled, "the newest sheet leads")


func test_an_archive_without_sheets_says_the_presses_have_not_run() -> void:
	_setup_gazette_plate()
	plate.open_archive(GazetteState.new(), null, gazette_plate_VIEWER)
	assert_true(_has_text(plate, GazettePlate.NO_HISTORY))


# --- the archive's reading filter (DR-20261115-06) ---------------------------
## A campaign files one sheet a turn and keeps every one, so a long age's
## archive is a hundred pages of three classes mixed together. The chips read
## one class across the whole campaign; the filter never re-orders, re-words or
## invents a line (wiki: the-gazette § History screen; REQ-P2-03, REQ-P5-03).


func test_the_filter_keeps_the_sheets_order_and_prose() -> void:
	var sheet: Dictionary = gazette_plate_sheet(3)
	var court: Dictionary = GazetteArchive.sheet(sheet, Gazette.Class.COURT)
	assert_eq(int(court["turn"]), 3, "the page keeps its turn")
	assert_eq((court["items"] as Array).size(), 1, "only the chosen class prints")
	assert_eq(
		String((court["items"] as Array)[0]["text"]),
		"Our scholars have finished the Crop Rotation.",
		"the line is the one the turn wrote"
	)
	assert_eq(
		GazetteArchive.sheet(sheet, GazetteArchive.ALL), sheet,
		"the unfiltered page is the filed one, untouched"
	)
	assert_true(GazetteArchive.holds(sheet, Gazette.Class.WORLD))
	assert_false(GazetteArchive.holds(sheet, Gazette.Class.INTEREST))
	assert_eq(GazetteArchive.tally([sheet], GazetteArchive.ALL), 2)
	assert_eq(GazetteArchive.tally([sheet], Gazette.Class.WORLD), 1)
	assert_true(GazetteArchive.walk([sheet], Gazette.Class.INTEREST).is_empty())
	assert_eq(GazetteArchive.label(Gazette.Class.COURT), "Our court", "a chip keeps the sheet's heading")
	assert_false(GazetteArchive.hint(Gazette.Class.INTEREST).is_empty(), "a chip says what it buys")


func test_the_archive_reads_one_class_across_the_campaign() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	state.append(_court_only_sheet(2))
	state.append(gazette_plate_sheet(3))
	plate.open_archive(state, null, gazette_plate_VIEWER)
	assert_true(_has_text(plate, "The gauntlet passes between them."), "every class prints")
	(_chip(plate, Gazette.Class.COURT) as Button).pressed.emit()
	assert_false(
		_has_text(plate, "The gauntlet passes between them."), "the world's news is set aside"
	)
	assert_true(_has_text(plate, "Our scholars have finished the Crop Rotation."))
	assert_eq(plate._nav_label.text, "1 of 2", "the walk counts the pages that hold the class")
	plate._step(1)
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(2)))
	assert_true(plate._older.disabled, "the oldest page that holds the class ends the walk")


func test_a_class_filter_skips_the_quiet_turns_the_archive_still_keeps() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	state.append({"turn": 2, "items": []})
	state.append(gazette_plate_sheet(3))
	plate.open_archive(state, null, gazette_plate_VIEWER)
	assert_eq(plate._nav_label.text, "1 of 2", "the unfiltered archive keeps the quiet turn")
	plate._step(1)
	assert_true(_has_text(plate, GazettePlate.EMPTY_LINE), "a quiet turn still reads as quiet")
	(_chip(plate, Gazette.Class.COURT) as Button).pressed.emit()
	assert_eq(plate._nav_label.text, "1 of 1", "a class filter walks only the pages that hold it")


func test_a_filter_that_matches_nothing_says_so() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	state.append(gazette_plate_sheet(2))
	plate.open_archive(state, null, gazette_plate_VIEWER)
	(_chip(plate, Gazette.Class.INTEREST) as Button).pressed.emit()
	assert_true(_has_text(plate, GazetteArchive.NONE_LINE))
	assert_eq(plate._nav_label.text, "", "there is no page to count")
	assert_true(plate._newer.disabled and plate._older.disabled, "there is nowhere to walk")


func test_the_filter_chips_carry_the_archive_tally() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	state.append(gazette_plate_sheet(2))
	state.append(gazette_plate_sheet(3))
	plate.open_archive(state, null, gazette_plate_VIEWER)
	assert_eq((_chip(plate, GazetteArchive.ALL) as Button).text, "All news 4")
	assert_eq((_chip(plate, Gazette.Class.WORLD) as Button).text, "The world 2")
	assert_eq((_chip(plate, Gazette.Class.COURT) as Button).text, "Our court 2")
	assert_true(
		(_chip(plate, GazetteArchive.ALL) as Button).button_pressed, "the archive opens unfiltered"
	)
	(_chip(plate, Gazette.Class.WORLD) as Button).pressed.emit()
	assert_true(
		(_chip(plate, Gazette.Class.WORLD) as Button).button_pressed, "the chip shows the reading"
	)
	assert_false((_chip(plate, GazetteArchive.ALL) as Button).button_pressed)


## The filter is the reader's, not the page's: reopening the archive keeps it
## and starts again at the newest page that holds the class.
func test_reopening_the_archive_keeps_the_filter() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	state.append(_court_only_sheet(2))
	state.append(gazette_plate_sheet(3))
	plate.open_archive(state, null, gazette_plate_VIEWER)
	(_chip(plate, Gazette.Class.COURT) as Button).pressed.emit()
	plate._step(1)
	plate.open_archive(state, null, gazette_plate_VIEWER)
	assert_eq(plate._nav_label.text, "1 of 2", "the walk restarts at the newest page")
	assert_false(
		_has_text(plate, "The gauntlet passes between them."), "the reading is still the crown's own"
	)


func _chip(node: Node, cls: int) -> Button:
	var chips: Dictionary = (node as GazettePlate)._archive_room.filter_buttons()
	return chips.get(cls, null) as Button


func _court_only_sheet(turn: int) -> Dictionary:
	return {
		"turn": turn,
		"items": [
			{
				"class": Gazette.Class.COURT,
				"kind": "techFinished",
				"text": "Our scholars have finished the Crop Rotation.",
			},
		],
	}


func test_the_watchlist_lists_met_courts_and_toggles_the_list() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	var diplomacy := DiplomacyState.new()
	diplomacy.initialize(1)
	plate.open_watchlist(state, diplomacy, gazette_plate_VIEWER)
	var box: CheckBox = _check_for(plate, "England")
	assert_not_null(box, "a met court is offered")
	assert_false(box.button_pressed)
	box.button_pressed = true
	assert_true(state.is_watched(gazette_plate_ENGLAND), "ticking follows the court")
	box.button_pressed = false
	assert_false(state.is_watched(gazette_plate_ENGLAND))
	assert_true(state.removed.has(gazette_plate_ENGLAND), "and the removal is remembered")


func test_the_plate_narrows_to_a_phone_viewport() -> void:
	_setup_gazette_plate()
	plate.size = Vector2(480, 800)
	plate._fit()
	var width: float = plate._panel.offset_right - plate._panel.offset_left
	assert_true(width <= 480.0, "the sheet never outgrows the screen")
	assert_true(width >= GazettePlate.MIN_WIDTH)


## The archive's filter chips ride a strip that scrolls sideways, so a phone's
## plate never widens for them (REQ-P1-05, REQ-P5-07).
func test_the_archive_filter_strip_never_widens_a_phone_plate() -> void:
	_setup_gazette_plate()
	plate.size = Vector2(320, 640)
	var state := GazetteState.new()
	state.append(gazette_plate_sheet(2))
	plate.open_archive(state, null, gazette_plate_VIEWER)
	plate._fit()
	var width: float = plate._panel.offset_right - plate._panel.offset_left
	assert_true(width <= 320.0, "the sheet never outgrows the screen")
	var chips: Dictionary = plate._archive_room.filter_buttons()
	var chips_width: float = 0.0
	for key: Variant in chips.keys():
		chips_width += (chips[key] as Button).get_combined_minimum_size().x
	assert_true(chips_width > width, "the chips are wider than a phone's plate")
	assert_true(
		plate._archive_room.get_combined_minimum_size().x <= width,
		"the strip scrolls instead of widening the sheet"
	)


## Toasts stay readable: while the sheet is up they are pushed to the lane under
## it, and the moment it goes they return to the top (REQ-P5-05). A phone's
## resting lane is not the atlas 84, so the plate gives back the lane's own top.
func test_the_sheet_moves_the_toast_lane_below_itself() -> void:
	_setup_gazette_plate()
	var host := ToastHost.new()
	host.size = Vector2(1280, 800)
	add_child(host)
	var lane := HudDespatches.new()
	host.add_child(lane)
	# A compact bar (56) + 6 is well above the atlas 84 the old plate assumed.
	lane.fit(true, 56.0, 382.0)
	var resting: float = lane.resting_top()
	assert_eq(resting, 62.0)

	var sheet_plate := GazettePlate.new()
	sheet_plate.despatches = lane
	host.add_child(sheet_plate)
	sheet_plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	# The lane follows the laid-out sheet, so let one layout pass settle.
	await get_tree().process_frame
	sheet_plate._fit()
	assert_true(lane.lane_top() > resting, "the lane drops below the sheet")
	sheet_plate.dismiss()
	assert_eq(lane.lane_top(), resting, "the lane comes back to its own top")
	host.free()


## A stand-in for the HUD: the plate only needs the despatch lane.
class ToastHost:
	extends Control


# --- helpers -----------------------------------------------------------------


func gazette_plate_sheet(turn: int) -> Dictionary:
	return {
		"turn": turn,
		"items": [
			{
				"class": Gazette.Class.WORLD,
				"kind": "warDeclared",
				"text": "The gauntlet passes between them.",
			},
			{
				"class": Gazette.Class.COURT,
				"kind": "techFinished",
				"text": "Our scholars have finished the Crop Rotation.",
			},
		],
	}


func _check_for(node: Node, needle: String) -> CheckBox:
	if node is CheckBox and String((node as CheckBox).text).contains(needle):
		return node as CheckBox
	for child: Node in node.get_children():
		var found: CheckBox = _check_for(child, needle)
		if found != null:
			return found
	return null


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false


# --- the age's room (DR-20261115-05) -----------------------------------------
## The whole race on the Gazette's own tab: one row per Great Power, read from
## the same standings the end-of-turn check acts on (wiki: victory § Victory
## Check; REQ-P2-03, REQ-P5-03). Presentation only — the room counts nothing.

var age_room_room: AgeRoom = null


func _setup_age_room() -> void:
	age_room_room = AgeRoom.new()
	add_child(age_room_room)


func _teardown_age_room() -> void:
	if is_instance_valid(age_room_room):
		age_room_room.free()
	age_room_room = null


func _age_row(id: int, name: String, holdings: int, bar: int, human: bool) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"holdings": holdings,
		"bar": bar,
		"need": maxi(bar - holdings, 0),
		"human": human,
		"leader": false,
	}


func test_the_age_room_prints_every_crown_against_its_own_bar() -> void:
	_setup_age_room()
	var rows: Array[Dictionary] = [
		_age_row(ENGLAND, "England", 28, 31, false),
		_age_row(SPAIN, "Spain", 12, 36, true),
	]
	rows[0]["leader"] = true
	age_room_room.fill(
		{
			"rows": rows,
			"human": SPAIN,
			"calendar": "the calendar closes in 140 turns",
			"note": VictoryStandings.bar_note(SPAIN, HARD),
		}
	)
	assert_true(_has_text(age_room_room, "England · leads"), "the race's leader is named")
	assert_true(_has_text(age_room_room, "28 of 31 · 3 to go"), "holdings against its own bar")
	assert_true(_has_text(age_room_room, "Spain · your crown"), "the reader's row is marked")
	assert_true(_has_text(age_room_room, "12 of 36 · 24 to go"), "the crown's bar is the level's")
	assert_true(
		_has_text(age_room_room, "The calendar closes in 140 turns"),
		"the calendar opens the sentence"
	)
	assert_true(_has_text(age_room_room, "every rival keeps 31"), "the bar rule is printed")
	_teardown_age_room()


## A crown already on its bar is never told it has "0 to go": the check would
## have closed the campaign first (wiki: victory § Victory Check).
func test_a_crown_on_its_bar_reads_on_the_bar() -> void:
	assert_eq(
		AgeRoom.standing_text(_age_row(SPAIN, "Spain", 31, 31, true)), "31 of 31 · on the bar"
	)
	assert_eq(
		AgeRoom.standing_text(_age_row(ENGLAND, "England", 30, 31, false)), "30 of 31 · 1 to go"
	)


func test_the_age_room_names_no_crown_when_the_session_has_none() -> void:
	_setup_age_room()
	age_room_room.fill({})
	assert_true(_has_text(age_room_room, AgeRoom.EMPTY_LINE))
	_teardown_age_room()


## The room is a table, not two strips (issue #672): the standing column and its
## heading read on one line at a desktop and a phone plate width, and each row
## keeps its two columns side by side. A wrapped cell reports no minimum width,
## so the row's HBox used to hand the standing a single glyph and stack it.
func test_the_age_room_reads_across_at_both_plate_widths() -> void:
	for width: float in [GazettePlate.MAX_WIDTH, GazettePlate.MIN_WIDTH]:
		_setup_age_room()
		age_room_room.size = Vector2(width, 0.0)
		var rows: Array[Dictionary] = [
			_age_row(ENGLAND, "England", 28, 31, false),
			_age_row(SPAIN, "Spain", 12, 36, true),
		]
		rows[0]["leader"] = true
		age_room_room.fill({"rows": rows, "human": SPAIN, "calendar": "", "note": ""})
		await get_tree().process_frame
		await get_tree().process_frame
		var names: Array[Label] = []
		var standing: Array[Label] = []
		for row: Node in age_room_room.get_children():
			if not row is HBoxContainer:
				continue
			var cells: Array[Node] = row.get_children()
			if cells.size() != 2:
				continue
			names.append(cells[0] as Label)
			standing.append(cells[1] as Label)
		assert_eq(standing.size(), 3, "the heading and both crowns print a standing cell")
		assert_eq(standing[0].text, AgeRoom.HEADINGS[1], "the standing heading leads the column")
		for label: Label in standing:
			assert_eq(label.get_line_count(), 1, "%s at %s" % [label.text, width])
			assert_true(
				label.size.x + 0.5 >= _one_line_width(label),
				"%s reads across, not down: %s of %s" % [
					label.text, label.size.x, _one_line_width(label)
				]
			)
		for i: int in names.size():
			assert_true(
				standing[i].get_rect().position.x + 0.5 >= names[i].get_rect().end.x,
				"the standing sits beside %s, not on it" % names[i].text
			)
			assert_true(
				names[i].size.x + 0.5 >= _longest_word_width(names[i]),
				"%s keeps its words whole: %s" % [names[i].text, names[i].size.x]
			)
		_teardown_age_room()


## The width a label's text needs on one line, in its own face and size.
func _one_line_width(label: Label) -> float:
	return label.get_theme_font("font").get_string_size(
		label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")
	).x


## The width of the label's longest word: below it the text breaks mid-word.
func _longest_word_width(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	var size: int = label.get_theme_font_size("font_size")
	var widest: float = 0.0
	for word: String in label.text.split(" ", false):
		widest = maxf(
			widest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		)
	return widest


func test_the_plate_prints_the_whole_race_on_its_age_tab() -> void:
	_setup_gazette_plate()
	var rows: Array[Dictionary] = [
		_age_row(ENGLAND, "England", 28, 31, false),
		_age_row(SPAIN, "Spain", 12, 31, true),
	]
	rows[0]["leader"] = true
	plate.open_sheet(
		gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER,
		"",
		{"rows": rows, "human": SPAIN, "calendar": "", "note": VictoryStandings.bar_note()}
	)
	plate._go(GazettePlate.Mode.AGE)
	assert_true(_has_text(plate, "THE GAZETTE  ·  THE AGE"))
	assert_true(_has_text(plate, "28 of 31 · 3 to go"))
	assert_true(_has_text(plate, "12 of 31 · 19 to go"))
	assert_true(plate._age_room.visible, "the room takes the body on its tab")
	plate._go(GazettePlate.Mode.SHEET)
	assert_false(plate._age_room.visible, "and gives it back on any other tab")
	assert_true(_has_text(plate, "The gauntlet passes between them."), "the sheet still prints")
	_teardown_gazette_plate()


## The payload is the check's own read: same rows, same order, the leader
## stamped from that order, and the calendar and bar in the sheet's words.
func test_the_age_payload_carries_the_checks_own_rows() -> void:
	_setup_victory_standings()
	var world := _victory_standings_old_world()
	_victory_standings_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 12, ENGLAND: 9})
	var play := PlaySession.new()
	play.world = world
	play.turn = 5
	play.player_faction = SPAIN
	play.difficulty = HARD
	var payload: Dictionary = MapPlayGazette.age_payload(play)
	assert_eq(int(payload["human"]), SPAIN)
	var rows: Array = payload["rows"] as Array
	assert_eq(rows.size(), FactionCatalog.great_power_ids().size())
	assert_eq(String(rows[0]["name"]), "England", "the nearer crown leads")
	assert_true(bool(rows[0]["leader"]), "the leader is the race's first row")
	assert_false(bool(rows[1]["leader"]), "only one crown leads")
	assert_eq(
		String(payload["note"]), VictoryStandings.bar_note(SPAIN, HARD), "the bar's own words"
	)
	assert_eq(
		String(payload["calendar"]), VictoryStandings.calendar_text(5), "the sheet's calendar"
	)
	victory_standings_Fixture.restore(
		victory_standings_Fixture.world(), victory_standings_saved_world
	)


func test_the_age_payload_is_empty_without_a_world() -> void:
	assert_eq(MapPlayGazette.age_payload(null), {})


func test_an_endless_age_closes_no_calendar_in_the_table() -> void:
	assert_eq(VictoryStandings.calendar_text(5, true), "no calendar closes this age")
	assert_eq(VictoryStandings.calendar_text(5), VictoryStandings.calendar_text(5, false))


# --- capital loss (wiki: capital-and-connectivity § Capital loss and reassignment;
# DR-20261109-02) -------------------------------------------------------------
## Merged from test_capital_loss. The rules cases build a hand-made 6x4 chart:
## Seat/Harbour/Uplands belong to one crown and Rival Seat to another, so a
## captured seat has a deterministic seaboard successor, an inland-only crown has
## a fallback, and a crown with a single province has nothing to fall back on.
## The wiring cases drive the one mounted chart instead of mounting per case.

const SEAT: int = 0
const HARBOUR: int = 1
const UPLANDS: int = 2
const RIVAL: int = 3

var loss_mounted: MapScreen = null
var loss_pristine: Dictionary = {}
var loss_pristine_map: Array = []


## A wiring case starts on the pristine chart, as a mount did.
func _loss_screen() -> MapScreen:
	Fixture.restore(Fixture.world(), loss_pristine_map)
	Fixture.suite_reset(loss_mounted, loss_pristine)
	return loss_mounted


func test_snapshot_records_the_capital_of_each_crown() -> void:
	var model: MapModel = _chart()
	var seats: Dictionary = CapitalLoss.snapshot(model)
	assert_eq(int(seats[0]), SEAT)
	assert_eq(int(seats[1]), RIVAL)


func test_a_captured_seat_moves_to_the_lowest_seaboard_province() -> void:
	var model: MapModel = _chart()
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 1

	var result: Dictionary = CapitalLoss.resolve(model, before)

	assert_eq(result["reassigned"].size(), 1)
	var row: Dictionary = result["reassigned"][0]
	assert_eq(int(row["faction"]), 0)
	assert_eq(int(row["province"]), HARBOUR, "seaboard first, ascending id")
	assert_eq(int(row["lost"]), SEAT)
	assert_true(model.province_data(HARBOUR).capital)
	assert_false(model.province_data(SEAT).capital, "the captured seat stops being a capital")
	assert_false(model.province_data(UPLANDS).capital)


func test_a_crown_with_only_inland_provinces_falls_back_to_them() -> void:
	var model: MapModel = _chart()
	model.province_data(HARBOUR).owner = 1
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 1

	var result: Dictionary = CapitalLoss.resolve(model, before)

	assert_eq(int(result["reassigned"][0]["province"]), UPLANDS)
	assert_true(model.province_data(UPLANDS).capital)


func test_a_great_power_seat_reaches_town_development_four() -> void:
	var model: MapModel = _chart()
	model.province_data(HARBOUR).town_development = 1
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 1

	CapitalLoss.resolve(model, before)

	assert_eq(model.province_data(HARBOUR).town_development, 4)


func test_a_minor_nation_keeps_its_new_seats_town_development() -> void:
	var model: MapModel = _chart()
	_hand_over(model, 0, [SEAT, HARBOUR, UPLANDS])
	_hand_over(model, 6, [SEAT, HARBOUR, UPLANDS])
	model.province_data(SEAT).capital = true
	model.province_data(HARBOUR).town_development = 2
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 1

	CapitalLoss.resolve(model, before)

	assert_eq(model.province_data(HARBOUR).town_development, 2)
	assert_true(model.province_data(HARBOUR).capital)
	assert_eq(CapitalLoss.seat_of(model, 6), HARBOUR)


func test_the_new_seat_gets_a_tile_near_the_province_centre() -> void:
	var model: MapModel = _chart()
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 1

	CapitalLoss.resolve(model, before)

	var seat: ProvinceState = model.province_data(HARBOUR)
	assert_in(seat.capital_tile, seat.tiles)
	assert_eq(seat.capital_tile, CapitalLoss.town_tile(seat), "deterministic on a re-read")


func test_an_intact_capital_is_left_alone() -> void:
	var model: MapModel = _chart()
	var before: Dictionary = CapitalLoss.snapshot(model)

	var result: Dictionary = CapitalLoss.resolve(model, before)

	assert_eq(result["reassigned"].size(), 0)
	assert_eq(result["fallen"].size(), 0)
	assert_eq(CapitalLoss.seat_of(model, 0), SEAT)
	assert_eq(CapitalLoss.seat_of(model, 1), RIVAL)


func test_a_crown_with_no_province_left_falls_to_the_conqueror() -> void:
	var model: MapModel = _chart()
	_hand_over(model, 0, [SEAT, HARBOUR, UPLANDS])
	_hand_over(model, 6, [SEAT])
	_hand_over(model, 1, [HARBOUR, UPLANDS])
	model.province_data(SEAT).capital = true
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 0

	var result: Dictionary = CapitalLoss.resolve(model, before)

	assert_eq(result["fallen"].size(), 1)
	var row: Dictionary = result["fallen"][0]
	assert_eq(int(row["faction"]), 6)
	assert_eq(int(row["conqueror"]), 0)
	assert_eq(int(row["lost"]), SEAT)
	assert_false(model.province_data(SEAT).capital)


func test_a_crown_that_already_fell_is_not_reported_again() -> void:
	var model: MapModel = _chart()
	_hand_over(model, 0, [SEAT, HARBOUR, UPLANDS])
	_hand_over(model, 6, [SEAT])
	_hand_over(model, 1, [HARBOUR, UPLANDS])
	model.province_data(SEAT).capital = true
	var before: Dictionary = CapitalLoss.snapshot(model)
	model.province_data(SEAT).owner = 0
	var first: Dictionary = CapitalLoss.resolve(model, before)
	assert_eq(first["fallen"].size(), 1)

	# The next Combat phase snapshots a crown that no longer holds a seat.
	var after: Dictionary = CapitalLoss.snapshot(model)
	var again: Dictionary = CapitalLoss.resolve(model, after)

	assert_eq(again["fallen"].size(), 0, "a fallen crown does not fall twice")
	assert_eq(again["reassigned"].size(), 0, "and is not given a new seat")


func test_a_crown_without_a_snapshot_seat_is_not_given_one() -> void:
	var model: MapModel = _chart()
	_hand_over(model, 6, [HARBOUR, UPLANDS])
	var before: Dictionary = CapitalLoss.snapshot(model)
	assert_eq(int(before[6]), CapitalLoss.NO_ID)

	var result: Dictionary = CapitalLoss.resolve(model, before)

	assert_eq(result["reassigned"].size(), 0, "no seat was lost, so none is reassigned")
	assert_eq(result["fallen"].size(), 0)
	assert_eq(CapitalLoss.seat_of(model, 6), CapitalLoss.NO_ID)


func test_a_fall_hands_every_province_in_every_region_to_the_conqueror() -> void:
	var old_world: MapModel = _chart()
	var new_world: MapModel = _chart()
	new_world.region_id = FactionCatalog.NEW_WORLD
	new_world.region_key = FactionCatalog.region_key(FactionCatalog.NEW_WORLD)
	var world := WorldMap.new()
	world.add_region(old_world)
	world.add_region(new_world)
	_hand_over(old_world, 6, [SEAT])
	_hand_over(old_world, 1, [HARBOUR, UPLANDS])
	_hand_over(new_world, 6, [RIVAL])
	_hand_over(new_world, 0, [SEAT, HARBOUR, UPLANDS])
	var before: Array = CapitalLoss.snapshot_world(world)
	old_world.province_data(SEAT).owner = 0

	var result: Dictionary = CapitalLoss.resolve_world(world, before)

	assert_eq(result["fallen"].size(), 1)
	assert_eq(result["reassigned"].size(), 0, "no seat is invented in the overseas region")
	assert_eq(int(result["fallen"][0]["conqueror"]), 0)
	assert_eq(new_world.province_data(RIVAL).owner, 0, "the overseas holding follows")
	assert_eq(world.owned_provinces(WorldMap.NEW_WORLD, 6), 0)


func test_the_pick_is_stable_across_calls() -> void:
	var model: MapModel = _chart()
	var owned: Array[int] = [HARBOUR, UPLANDS]

	var first: int = CapitalLoss.pick_capital_province(model, owned)
	var second: int = CapitalLoss.pick_capital_province(model, owned)

	assert_eq(first, HARBOUR)
	assert_eq(second, first)


# --- screen wiring -----------------------------------------------------------

func test_a_captured_capital_reseats_its_owner_on_the_map() -> void:
	var screen: MapScreen = _loss_screen()
	var model: MapModel = screen.model
	var saved: Array[Dictionary] = _save_seats(model)
	var pair: Dictionary = _enemy_capital_next_door(screen)
	assert_false(pair.is_empty(), "an enemy seat borders crown land")
	var target: int = int(pair["target"])
	var enemy: int = model.province_owner(target)
	assert_eq(_capital_count(model, enemy), 1, "the crown has exactly one seat to lose")
	# Rival land AI can split and march into a declared seat on the same
	# end-turn pass; strip that crown's armies so the capture stays unopposed.
	screen.army_layer.transfer_owner(enemy, MapModel.NO_ID)
	_declare_war(screen, enemy)
	var army: ArmyState = _detach_one(screen)
	army.province = int(pair["start"])
	var tile: Vector2i = model.province_data(target).tiles[0]
	assert_true(MapPlayArmies.try_order(screen.play, tile))

	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	assert_eq(model.province_owner(target), MapScreen.PLAYER_FACTION)
	assert_false(model.province_data(target).capital, "the captured seat stops being a capital")
	assert_eq(_capital_count(model, enemy), 1, "the crown keeps exactly one seat")
	_restore_seats(model, saved)


## The Home Army always stands on its court's seat: a reassignment takes the
## guard to the new capital, so a court that lost its seat can muster again
## (wiki: military-armies § Home Army; issue #474). Without the recall the
## capital guard in `MapPlayArmyAi._reinforce` blocks every muster for the rest
## of the campaign.
func test_a_reassignment_takes_the_home_army_to_the_new_seat() -> void:
	var screen: MapScreen = _loss_screen()
	var model: MapModel = screen.model
	var home: ArmyState = _home_of(screen, MapScreen.PLAYER_FACTION)
	assert_not_null(home, "the crown musters a Home Army")
	var seat: int = _successor(model, home.province)
	assert_gt(seat, -1, "the court holds another province to move to")
	var original: int = home.province

	# The row `CapitalLoss.resolve` emits when the seat falls.
	var changed: bool = MapPlayLandTurn.apply_capital_loss(
		screen.play,
		{
			"fallen": [],
			"reassigned": [
				{
					"faction": MapScreen.PLAYER_FACTION,
					"province": seat,
					"lost": original,
					"region": model.region_id,
				},
			],
		}
	)

	assert_true(changed)
	assert_eq(home.province, seat, "the guard follows the court")

	home.province = original


func test_the_player_capital_framing_follows_a_reassignment() -> void:
	var screen: MapScreen = _loss_screen()
	var model: MapModel = screen.model
	var home: int = screen.capital_province
	var home_tile: Vector2i = model.capital_tile_of(home)
	var successor: int = _successor(model, home)
	assert_gt(successor, -1)
	model.province_data(successor).capital = true
	model.province_data(successor).capital_tile = CapitalLoss.town_tile(
		model.province_data(successor)
	)
	model.province_data(home).capital = false

	MapPlayLandTurn.sync_player_capital(screen.play)

	assert_eq(screen.capital_province, successor)
	assert_eq(screen.capital_tile, model.capital_tile_of(successor))
	model.province_data(home).capital = true
	model.province_data(home).capital_tile = home_tile
	model.province_data(successor).capital = false
	model.province_data(successor).capital_tile = CapitalLoss.NO_TILE


func test_a_fallen_crown_leaves_the_roster_and_the_court() -> void:
	var screen: MapScreen = _loss_screen()
	var minor: int = FactionCatalog.minor_ids()[0]
	screen.play.diplomacy.ensure_relation(minor, 0, screen.play.diplomacy.turn)
	assert_not_null(screen.play.diplomacy.relation(minor, 0))
	var armies_before: int = _army_count(screen, minor)
	assert_gt(armies_before, 0)
	var toasts_before: int = screen.hud._toast_box.get_child_count()

	var changed: bool = MapPlayLandTurn.apply_capital_loss(
		screen.play, {"fallen": [{"faction": minor, "conqueror": 0}], "reassigned": []}
	)

	assert_true(changed)
	assert_eq(_army_count(screen, minor), 0)
	assert_null(screen.play.diplomacy.relation(minor, 0))
	assert_eq(screen.hud._toast_box.get_child_count(), toasts_before + 1)
	# The fall record keeps the knowledge the crown held when the court left
	# play: the relations are gone by the time the Gazette reads the turn
	# (wiki: the-gazette § Item catalog — World, "Great Power terminal fall").
	assert_eq(screen.play.last_falls.size(), 1)
	assert_true(bool(screen.play.last_falls[0].get("known", false)), "the crown had met the court")


# --- transfer and retirement (wiki: diplomacy § GP–Minor Rules) --------------


func test_a_retired_crown_leaves_the_regions_it_was_stored_in() -> void:
	var screen: MapScreen = _loss_screen()
	var minor: int = FactionCatalog.minor_ids()[0]
	var roster: Array = []
	roster.assign(screen.army_layer.regions.value(screen.model.region_id, []))
	var doomed: ArmyState = null
	for raw: Variant in roster:
		var army: ArmyState = raw
		if army != null and army.owner == minor:
			doomed = army
			break
	assert_not_null(doomed, "the minor musters a Home Army")

	# Handing a crown to nobody retires its armies, not just the on-screen list.
	screen.army_layer.transfer_owner(minor, MapModel.NO_ID)

	roster = []
	roster.assign(screen.army_layer.regions.value(screen.model.region_id, []))
	assert_false(roster.has(doomed), "a fallen crown's army leaves the stored roster")
	assert_eq(_army_count(screen, minor), 0)
	assert_null(screen.army_layer.marker_for(doomed), "and its standard leaves the map")
	# A roster on another map is not on screen at all; a fall rewrites it too.
	var elsewhere: Array[ArmyState] = [ArmyState.muster(77, minor, 0, true, ["pikemen"], 1)]
	screen.army_layer.regions.set_region(FactionCatalog.NEW_WORLD, elsewhere)
	screen.army_layer.transfer_owner(minor, MapModel.NO_ID)
	var stored: Array = []
	stored.assign(screen.army_layer.regions.value(FactionCatalog.NEW_WORLD, []))
	assert_eq(stored.size(), 0, "an off-screen roster is retired, not merely the shown one")


func test_a_join_empire_keeps_every_army_in_play() -> void:
	var screen: MapScreen = _loss_screen()
	var minor: int = FactionCatalog.minor_ids()[0]
	var won: Array[ArmyState] = _armies_of(screen, minor)
	assert_gt(won.size(), 0)

	screen.army_layer.transfer_owner(minor, MapScreen.PLAYER_FACTION)

	assert_eq(_army_count(screen, minor), 0)
	for army: ArmyState in won:
		assert_true(
			_armies_of(screen, MapScreen.PLAYER_FACTION).has(army),
			"an absorbed army stays in play under the winner's colours"
		)
		assert_false(army.home, "and becomes a field army so the winner keeps one Home Army")


# --- fixtures ----------------------------------------------------------------

## Lands and waters of the test chart, in tile coordinates.
func _chart() -> MapModel:
	var model := MapModel.new()
	model.setup(6, 4)
	model.region_id = FactionCatalog.OLD_WORLD
	model.region_key = FactionCatalog.region_key(FactionCatalog.OLD_WORLD)
	model.faction_ids = [0, 1, 2, 6]
	var land: Dictionary = {
		SEAT: [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],
		HARBOUR: [Vector2i(3, 0), Vector2i(3, 1), Vector2i(2, 0), Vector2i(2, 2), Vector2i(3, 2)],
		UPLANDS: [Vector2i(1, 1), Vector2i(2, 1)],
	}
	# The rival seat sits apart on the eastern seaboard.
	var rival_tiles: Array[Vector2i] = [Vector2i(5, 0), Vector2i(5, 1)]
	for province_id: int in land.keys():
		_fill(model, land[province_id], province_id)
	_fill(model, rival_tiles, RIVAL)
	model.provinces = [
		_loss_province(SEAT, "Seat", land[SEAT], 0, true),
		_loss_province(HARBOUR, "Harbour", land[HARBOUR], 0, false),
		_loss_province(UPLANDS, "Uplands", land[UPLANDS], 0, false),
		_loss_province(RIVAL, "Rival Seat", rival_tiles, 1, true),
	]
	var water: Array[Vector2i] = []
	for y in model.height:
		for x in model.width:
			if model.province_at(x, y) == MapModel.NO_ID:
				water.append(Vector2i(x, y))
	for tile: Vector2i in water:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 0
	model.sea_zones = [SeaZoneState.create(0, "Open Water", water, Vector2(4.0, 3.0), water.size())]
	return model


func _fill(model: MapModel, tiles: Array, province_id: int) -> void:
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = province_id


func _loss_province(
	id: int, title: String, tiles: Array, owner: int, capital: bool
) -> ProvinceState:
	var typed: Array[Vector2i] = []
	typed.assign(tiles)
	var sum := Vector2.ZERO
	for tile: Vector2i in typed:
		sum += Vector2(tile)
	var center: Vector2 = sum / maxf(float(typed.size()), 1.0)
	var data := ProvinceState.create(id, title, typed, center, typed.size(), owner, capital)
	if capital:
		data.capital_tile = CapitalLoss.town_tile(data)
	return data


## Hands provinces to a faction without touching anything else on the chart.
func _hand_over(model: MapModel, faction: int, provinces: Array) -> void:
	for province_id: int in provinces:
		model.province_data(province_id).owner = faction


func _successor(model: MapModel, capital: int) -> int:
	var owned: Array[int] = []
	for province: ProvinceState in model.provinces:
		if province.owner == MapScreen.PLAYER_FACTION and province.id != capital:
			owned.append(province.id)
	return CapitalLoss.pick_capital_province(model, owned)


func _army_count(screen: MapScreen, faction: int) -> int:
	return _armies_of(screen, faction).size()


## The faction's Home Army among every stored roster, or null.
func _home_of(screen: MapScreen, faction: int) -> ArmyState:
	for army: ArmyState in _armies_of(screen, faction):
		if army.is_home_army():
			return army
	return null


## Every army in the regions the layer has visited (the screen's own included).
func _armies_of(screen: MapScreen, faction: int) -> Array[ArmyState]:
	var found: Array[ArmyState] = []
	for raw: Variant in screen.army_layer.regions.values():
		var roster: Array = raw
		for army: ArmyState in roster:
			if army != null and army.owner == faction:
				found.append(army)
	return found


## Marks a province next to the player's capital as a rival crown's only seat,
## so one march captures a capital without disturbing the rest of the map.
## A crown province bordering a rival one; the rival province is made that
## crown's seat so the capture has a capital to lose. Returns {start, target}.
func _enemy_capital_next_door(screen: MapScreen) -> Dictionary:
	var model: MapModel = screen.model
	for province: ProvinceState in model.provinces:
		if province.owner != MapScreen.PLAYER_FACTION:
			continue
		for province_id: int in MapGeo.province_neighbors(model, province.id):
			var data: ProvinceState = model.province_data(province_id)
			if data == null or data.owner == MapScreen.PLAYER_FACTION:
				continue
			if data.owner == MapModel.NO_ID:
				continue
			if not data.capital:
				for other: ProvinceState in model.provinces:
					if other.owner == data.owner and other.capital:
						other.capital = false
				data.capital = true
				data.capital_tile = CapitalLoss.town_tile(data)
			return {"start": province.id, "target": province_id}
	return {}


func _capital_count(model: MapModel, faction: int) -> int:
	var total: int = 0
	for province: ProvinceState in model.provinces:
		if province.owner == faction and province.capital:
			total += 1
	return total


func _save_seats(model: MapModel) -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	for province: ProvinceState in model.provinces:
		saved.append({
			"id": province.id,
			"owner": province.owner,
			"capital": province.capital,
			"tile": province.capital_tile,
			"town": province.town_development,
		})
	return saved


func _restore_seats(model: MapModel, saved: Array[Dictionary]) -> void:
	for row: Dictionary in saved:
		var province: ProvinceState = model.province_data(int(row["id"]))
		if province == null:
			continue
		province.owner = int(row["owner"])
		province.capital = bool(row["capital"])
		province.capital_tile = row["tile"]
		province.town_development = int(row["town"])


func _declare_war(screen: MapScreen, faction: int) -> void:
	screen.play.diplomacy.ensure_relation(
		screen.play.player_faction, faction, screen.play.diplomacy.turn
	)
	DiplomacyRules.declare_war(screen.play.diplomacy, screen.play.player_faction, faction)


func _detach_one(screen: MapScreen) -> ArmyState:
	for army: ArmyState in screen.army_layer.armies:
		if army.owner == screen.play.player_faction and army.is_home_army():
			screen.army_layer.select(army)
			MapPlayArmies.on_action(screen.play, "detach:%s" % army.regiments[0])
			return screen.army_layer.selected_army
	return null
