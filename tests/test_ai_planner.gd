extends GdToolsTest

const AiFixture = preload("res://tests/ai_fixture.gd")
## Full-AI diplomacy policy: war desire, relation gate, cooldowns, war goals and
## peace (wiki: diplomacy § GP AI policy for war vs. relations).

var state: DiplomacyState
var config: AiConfig
var ai_state: AiState


func before_each() -> void:
	state = DiplomacyState.new()
	state.reset(1)
	config = AiConfig.build(FactionCatalog.PLAYER_FACTION, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_state = AiState.new()


func test_desire_starts_at_the_base_and_adds_power_and_relation() -> void:
	state.ensure_relation(0, 1, 1)
	var desire: Dictionary = AiDiplomacyPlanner.war_desire(
		config, state, AiFixture.world([0, 1]), 0, 1,
		AiFixture.context({0: 100, 1: 100})
	)
	assert_eq(int(desire["score"]), 35, "50 base + 5 even power - 20 neutral relations")
	var factors: Dictionary = desire["factors"]
	assert_eq(int(factors["base"]), 50)
	assert_eq(int(factors["relative_power"]), 5)
	assert_eq(int(factors["relation"]), -20)
	assert_eq(int(factors["personality"]), 0)


func test_relative_power_dominates_the_score() -> void:
	state.ensure_relation(0, 1, 1)
	var world: WorldMap = AiFixture.world([0, 1])
	var strong: Dictionary = AiDiplomacyPlanner.war_desire(
		config, state, world, 0, 1, AiFixture.context({0: 135, 1: 100})
	)
	assert_eq(int(strong["score"]), 60, "50 + 30 strong - 20 neutral")
	var weak: Dictionary = AiDiplomacyPlanner.war_desire(
		config, state, world, 0, 1, AiFixture.context({0: 84, 1: 100})
	)
	assert_eq(int(weak["score"]), 5, "50 - 25 weak - 20 neutral")


func test_relation_pressure_bands() -> void:
	var world: WorldMap = AiFixture.world([0, 1])
	var context: Dictionary = AiFixture.context({0: 100, 1: 100})
	state.ensure_relation(0, 1, 1)
	state.relation(0, 1).score = 25.0
	assert_eq(int(AiDiplomacyPlanner.war_desire(config, state, world, 0, 1, context)["score"]), 65)
	state.relation(0, 1).score = 40.0
	assert_eq(int(AiDiplomacyPlanner.war_desire(config, state, world, 0, 1, context)["score"]), 55)
	state.relation(0, 1).score = 75.0
	assert_eq(int(AiDiplomacyPlanner.war_desire(config, state, world, 0, 1, context)["score"]), 15)


func test_minor_targets_pay_the_invasion_capacity_cost() -> void:
	state.ensure_relation(0, 6, 1)
	var world: WorldMap = AiFixture.world([0, 6])
	var weak: Dictionary = AiDiplomacyPlanner.war_desire(
		config, state, world, 0, 6, AiFixture.context({0: 100, 6: 100})
	)
	assert_eq(int(weak["score"]), 15, "no regiments is -20")
	var ready: Dictionary = AiDiplomacyPlanner.war_desire(
		config, state, world, 0, 6, AiFixture.context({0: 100, 6: 100}, {0: 3, 6: 0})
	)
	assert_eq(int(ready["score"]), 45, "superior regiments is +10")


func test_two_active_wars_add_the_multi_war_penalty() -> void:
	state.ensure_relation(0, 6, 1)
	state.ensure_relation(0, 7, 1)
	state.ensure_relation(0, 8, 1)
	DiplomacyRules.declare_war(state, 0, 7)
	DiplomacyRules.declare_war(state, 0, 8)
	var desire: Dictionary = AiDiplomacyPlanner.war_desire(
		config, state, AiFixture.world([0, 6]), 0, 6,
		AiFixture.context({0: 100, 6: 100}, {0: 3, 6: 0})
	)
	assert_eq(int(desire["factors"]["wars"]), -15)
	assert_eq(int(desire["score"]), 30)


func test_missing_stockpiles_are_scored_against_the_target() -> void:
	state.ensure_relation(0, 6, 1)
	var world: WorldMap = AiFixture.world([0, 6, 6, 6, 6], {1: 0, 2: 1, 3: 2, 4: 3})
	var context: Dictionary = AiFixture.context({0: 100, 6: 100})
	context["stockpiles"] = {0: {}}
	var need: Dictionary = AiDiplomacyPlanner.war_desire(config, state, world, 0, 6, context)
	assert_eq(int(need["factors"]["resource_need"]), 15, "four missing resources cap at +15")
	context["stockpiles"] = {0: {"timber": 4, "iron": 4, "coal": 4}}
	var partly: Dictionary = AiDiplomacyPlanner.war_desire(config, state, world, 0, 6, context)
	assert_eq(int(partly["factors"]["resource_need"]), 5)


func test_rival_embassies_add_the_intervention_risk_penalty() -> void:
	state.ensure_relation(0, 6, 1)
	state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_overture(2, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_overture(3, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var desire: Dictionary = AiDiplomacyPlanner.war_desire(
		config, state, AiFixture.world([0, 6]), 0, 6,
		AiFixture.context({0: 100, 6: 100})
	)
	assert_eq(int(desire["factors"]["intervention"]), -24, "three embassies cap at -24")
	state.set_overture(2, 6, DiplomacyCatalog.STAGE_NONE)
	state.set_overture(3, 6, DiplomacyCatalog.STAGE_NONE)
	var single: Dictionary = AiDiplomacyPlanner.war_desire(
		config, state, AiFixture.world([0, 6]), 0, 6,
		AiFixture.context({0: 100, 6: 100})
	)
	assert_eq(int(single["factors"]["intervention"]), -8)


## A deed is protection in the attacker's eyes too: a rival's purchased land in
## the minor's provinces is a Great Power the declaration would call to the
## victim's aid, so it costs the same -8 as an embassy (wiki: diplomacy
## § Intervention "investment protection"; DR-20261110-20).
func test_a_rival_deed_in_the_minors_land_adds_the_intervention_risk_penalty() -> void:
	state.ensure_relation(0, 6, 1)
	var world: WorldMap = AiFixture.world([0, 6])
	var context: Dictionary = AiFixture.context({0: 100, 6: 100}, {0: 3, 6: 0})
	var bare: Dictionary = AiDiplomacyPlanner.war_desire(config, state, world, 0, 6, context)
	assert_eq(int(bare["factors"]["intervention"]), 0, "no one would answer")
	var model: MapModel = world.region(0)
	assert_true(model.ownership.purchase(model.index_of(1, 0), 1), "a rival buys land")
	var bought: Dictionary = AiDiplomacyPlanner.war_desire(config, state, world, 0, 6, context)
	assert_eq(int(bought["factors"]["intervention"]), -8, "the deed holder answers")
	assert_true(
		int(bought["score"]) < int(bare["score"]),
		"the protected minor is the harder war"
	)


func test_declares_war_when_strong_and_relations_are_cool() -> void:
	state.ensure_relation(0, 1, 1)
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state, AiFixture.world([0, 1, 1]), 1,
		AiFixture.context({0: 200, 1: 100})
	)
	var action: Dictionary = plan["action"]
	assert_eq(String(action["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)
	assert_eq(int(action["target"]), 1)
	assert_eq(int(action["desired_territory"]), 2, "clamp(round(75/25), 1, 2)")


func test_friendly_relations_block_war_even_when_desire_is_high() -> void:
	state.ensure_relation(0, 1, 1)
	state.relation(0, 1).score = 80.0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state, AiFixture.world([0, 1]), 1,
		AiFixture.context({0: 400, 1: 100})
	)
	assert_eq(String(plan["candidates"][0]["blocked"]), "relations too warm")
	assert_eq(
		String((plan["action"] as Dictionary).get("kind", "")),
		AiDiplomacyOffers.KIND_ALLIANCE,
		"the court works for the treaty the standing already earns"
	)


func test_war_cooldown_blocks_the_pair_for_four_turns() -> void:
	state.ensure_relation(0, 1, 1)
	ai_state.note_war(0, 1, 1)
	var context: Dictionary = AiFixture.context({0: 200, 1: 100})
	var world: WorldMap = AiFixture.world([0, 1])
	var cooling: Dictionary = AiDiplomacyPlanner.decide(config, state, ai_state, world, 2, context)
	assert_true((cooling["action"] as Dictionary).is_empty())
	assert_eq(String(cooling["candidates"][0]["blocked"]), "war cooldown")
	var ready: Dictionary = AiDiplomacyPlanner.decide(config, state, ai_state, world, 5, context)
	assert_eq(String(ready["action"]["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)


func test_war_desire_below_the_minimum_blocks_war() -> void:
	state.ensure_relation(0, 1, 1)
	state.relation(0, 1).score = 45.0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state, AiFixture.world([0, 1]), 1,
		AiFixture.context({0: 84, 1: 100})
	)
	assert_true((plan["action"] as Dictionary).is_empty())
	assert_eq(String(plan["candidates"][0]["blocked"]), "war desire too low")


func test_peace_is_offered_when_the_war_stops_being_worth_it() -> void:
	state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(state, 0, 1)
	var context: Dictionary = AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state, AiFixture.world([0, 1]), 2, context
	)
	assert_eq(String(plan["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_eq(int(plan["action"]["target"]), 1)


func test_peace_with_the_human_is_proposed_and_waits_for_the_player() -> void:
	var france: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	state.ensure_relation(2, 0, 1)
	DiplomacyRules.declare_war(state, 2, 0)
	var context: Dictionary = AiFixture.context({2: 84, 0: 100})
	context["player"] = 0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		france, state, ai_state, AiFixture.world([0, 2]), 2, context
	)
	var action: Dictionary = plan["action"]
	assert_eq(String(action["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_eq(int(action["target"]), 0)
	assert_true(bool(action.get("propose", false)), "the human court answers the offer")
	assert_true(state.relation(0, 2).at_war, "nothing is signed before the answer")


func test_a_refused_peace_waits_the_peace_cooldown() -> void:
	var france: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	state.ensure_relation(2, 0, 1)
	DiplomacyRules.declare_war(state, 2, 0)
	ai_state.note_peace(2, 0, 2)
	var context: Dictionary = AiFixture.context({2: 84, 0: 100})
	context["player"] = 0
	var cooling: Dictionary = AiDiplomacyPlanner.decide(
		france, state, ai_state, AiFixture.world([0, 2]), 3, context
	)
	assert_true((cooling["action"] as Dictionary).is_empty())
	assert_eq(String(cooling["candidates"][0]["blocked"]), "peace cooldown")
	var ready: Dictionary = AiDiplomacyPlanner.decide(
		france, state, ai_state, AiFixture.world([0, 2]), 5, context
	)
	assert_eq(String(ready["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)


func test_a_recent_war_declaration_does_not_silence_a_peace_offer() -> void:
	# The 4-turn war cooldown gates another Declare War on that pair, never the
	# peace leg of the same pair (wiki: diplomacy § Configurable Values —
	# "Applies to AI-initiated Declare War re-attempts"; DR-20261108-01).
	state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(state, 0, 1)
	ai_state.note_war(0, 1, 1)
	var context: Dictionary = AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state, AiFixture.world([0, 1]), 2, context
	)
	assert_eq(
		String((plan["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"a war that stopped being worth waging still offers peace after declaring"
	)
	assert_eq(int((plan["action"] as Dictionary).get("target", -1)), 1)


func test_war_goal_clamps_to_the_target_province_count() -> void:
	assert_eq(AiDiplomacyPlanner.desired_territory(75, 5), 3)
	assert_eq(AiDiplomacyPlanner.desired_territory(75, 2), 2)
	assert_eq(AiDiplomacyPlanner.desired_territory(12, 3), 1)
	assert_eq(AiDiplomacyPlanner.desired_territory(100, 0), 1)


# --- the agenda's hand on the court (DR-20261111-27) --------------------------


func test_a_peacemaker_offers_peace_where_a_plain_court_fights_on() -> void:
	# Same war, same standing: the dove's peace bar sits 15 higher, so a war it
	# no longer means is put to its enemy a turn earlier (wiki: hidden-agendas —
	# peacemaker early peace).
	state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(state, 0, 1)
	state.relation(0, 1).score = 40.0
	var context: Dictionary = AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var world: WorldMap = AiFixture.world([0, 1])
	var plain: Dictionary = AiDiplomacyPlanner.decide(config, state, ai_state, world, 2, context)
	assert_eq(String(plain["candidates"][0]["blocked"]), "war still worth waging")
	var dove: AiConfig = AiConfig.build(0, 1500, AiProfile.NORMAL, AiAgenda.PEACEMAKER)
	var peace: Dictionary = AiDiplomacyPlanner.decide(dove, state, ai_state, world, 2, context)
	assert_eq(String(peace["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_eq(int(peace["action"]["target"]), 1)


func test_a_warmonger_keeps_a_war_a_plain_court_would_end() -> void:
	state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(state, 0, 1)
	state.relation(0, 1).score = 60.0
	var context: Dictionary = AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var world: WorldMap = AiFixture.world([0, 1])
	var plain: Dictionary = AiDiplomacyPlanner.decide(config, state, ai_state, world, 2, context)
	assert_eq(String(plain["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	var hawk: AiConfig = AiConfig.build(0, 1500, AiProfile.NORMAL, AiAgenda.WARMONGER)
	var keep: Dictionary = AiDiplomacyPlanner.decide(hawk, state, ai_state, world, 2, context)
	assert_true((keep["action"] as Dictionary).is_empty(), "the war is still worth waging")
	assert_eq(String(keep["candidates"][0]["blocked"]), "war still worth waging")


func test_a_backstabber_breaks_an_alliance_it_would_otherwise_keep() -> void:
	# A formal ally that is weaker than the court: the treaty still serves an
	# honest court, but the backstabber's desire against its own ally clears the
	# break bar (wiki: hidden-agendas — hits allies when weak).
	state.ensure_relation(0, 1, 1)
	state.relation(0, 1).score = 70.0
	state.relation(0, 1).formal_alliance = true
	var context: Dictionary = AiFixture.context({0: 135, 1: 100})
	context["player"] = 5
	var world: WorldMap = AiFixture.world([0, 1])
	var honest: Dictionary = AiDiplomacyPlanner.war_desire(config, state, world, 0, 1, context)
	assert_false((honest["factors"] as Dictionary).has("betrayal"))
	assert_eq(int(honest["score"]), 40, "50 + 30 strong - 40 allied")
	var snake: AiConfig = AiConfig.build(0, 1500, AiProfile.NORMAL, AiAgenda.BACKSTABBER)
	var snake_desire: Dictionary = AiDiplomacyPlanner.war_desire(snake, state, world, 0, 1, context)
	assert_eq(int(snake_desire["factors"]["betrayal"]), 25)
	var keep: Dictionary = AiDiplomacyPlanner.decide(config, state, ai_state, world, 1, context)
	assert_true(
		String((keep["action"] as Dictionary).get("kind", "")) != AiDiplomacyOffers.KIND_BREAK,
		"an honest court keeps the treaty its standing earned"
	)
	var betray: Dictionary = AiDiplomacyPlanner.decide(snake, state, ai_state, world, 1, context)
	assert_eq(String(betray["action"]["kind"]), AiDiplomacyOffers.KIND_BREAK)
	assert_true(state.relation(0, 1).formal_alliance, "the planner only plans the break")


func test_an_envious_court_resents_a_human_crown_that_pulled_ahead() -> void:
	state.ensure_relation(0, 2, 1)
	var context: Dictionary = AiFixture.context({0: 135, 2: 100})
	context["player"] = 0
	var world: WorldMap = AiFixture.world([0, 2, 2])
	var plain_config: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	var plain: Dictionary = AiDiplomacyPlanner.war_desire(plain_config, state, world, 2, 0, context)
	assert_false((plain["factors"] as Dictionary).has("rival"))
	var jealous: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.ENVY)
	var envy: Dictionary = AiDiplomacyPlanner.war_desire(jealous, state, world, 2, 0, context)
	assert_eq(int(envy["factors"]["rival"]), 20)
	assert_eq(
		int(envy["score"]) - int(plain["score"]), 25,
		"20 rival_bias + 5 war_bias"
	)
	assert_true(int(envy["score"]) > int(plain["score"]), "the lead is felt")


func test_an_envious_court_does_not_resent_a_crown_that_trails_it() -> void:
	state.ensure_relation(0, 2, 1)
	var context: Dictionary = AiFixture.context({0: 100, 2: 135})
	context["player"] = 0
	var jealous: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.ENVY)
	var desire: Dictionary = AiDiplomacyPlanner.war_desire(
		jealous, state, AiFixture.world([0, 2, 2]), 2, 0, context
	)
	assert_false((desire["factors"] as Dictionary).has("rival"), "envy is not a grudge")
	# Nor is it a grudge against another rival: the pull is for the human crown.
	var other: Dictionary = AiDiplomacyPlanner.war_desire(
		jealous, state, AiFixture.world([0, 1, 2]), 2, 1, context
	)
	assert_false((other["factors"] as Dictionary).has("rival"))
