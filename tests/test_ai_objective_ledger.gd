extends GdToolsTest
## The rival objective ledger (T1, trace-only): the shared utility currency, the
## rank and allocate passes, the claims a court carries into the next turn, and
## the trace lines that explain a deferred objective (wiki: ai-architecture;
## DR-20261113-15). Nothing here spends or moves, so the suite also proves the
## ledger is a read model (REQ-P2-03, REQ-P4-03).


func _objective(
	objective_id: String, utility: int, cost: Dictionary, blocked: String = ""
) -> AiObjective:
	return AiObjective.make(objective_id, "military", utility, cost, blocked)


# --- rank --------------------------------------------------------------------


func test_rank_orders_by_utility_then_id() -> void:
	var ranked: Array[AiObjective] = AiObjectiveLedger.rank([
		_objective("b", 40, {"orders": 1}),
		_objective("a", 40, {"orders": 1}),
		_objective("c", 90, {"orders": 1}),
	])

	assert_eq(ranked[0].id, "c")
	assert_eq(ranked[1].id, "a")
	assert_eq(ranked[2].id, "b")
	assert_eq(ranked[0].rank, 1)
	assert_eq(ranked[2].rank, 3)


# --- allocate ----------------------------------------------------------------


func test_claims_follow_rank_order_with_mixed_pools() -> void:
	var ranked: Array[AiObjective] = AiObjectiveLedger.rank([
		_objective("low", 20, {"treasury": 5}),
		_objective("high", 90, {"treasury": 8}),
	])
	var allocated: Array[AiObjective] = AiObjectiveLedger.allocate(
		ranked, {"treasury": 10}
	)

	assert_eq(allocated[0].id, "high")
	assert_eq(allocated[0].status, AiObjective.STATUS_FUNDED)
	assert_eq(allocated[0].claim_of("treasury"), 8)
	assert_eq(allocated[1].status, AiObjective.STATUS_DEFERRED)
	assert_eq(allocated[1].shortfall_of("treasury"), 3)


func test_a_pool_empties_and_later_objectives_defer() -> void:
	var ranked: Array[AiObjective] = AiObjectiveLedger.rank([
		_objective("first", 80, {"hull": 1}),
		_objective("second", 70, {"hull": 1}),
	])
	var allocated: Array[AiObjective] = AiObjectiveLedger.allocate(ranked, {"hull": 1})

	assert_eq(allocated[0].status, AiObjective.STATUS_FUNDED)
	assert_eq(allocated[1].status, AiObjective.STATUS_DEFERRED)
	assert_eq(allocated[1].shortfall_of("hull"), 1)


func test_blocked_objective_is_skipped_and_keeps_its_reason() -> void:
	var ranked: Array[AiObjective] = AiObjectiveLedger.rank([
		_objective("war", 90, {"orders": 1}, "war cooldown"),
		_objective("march", 50, {"orders": 1}),
	])
	var allocated: Array[AiObjective] = AiObjectiveLedger.allocate(
		ranked, {"orders": 1}
	)

	assert_eq(allocated[0].status, AiObjective.STATUS_BLOCKED)
	assert_eq(allocated[0].blocked, "war cooldown")
	assert_eq(allocated[0].claim, {})
	assert_eq(allocated[1].status, AiObjective.STATUS_FUNDED)


func test_claims_of_keeps_only_funded_rows() -> void:
	var ranked: Array[AiObjective] = AiObjectiveLedger.rank([
		_objective("funded", 80, {"orders": 1}),
		_objective("deferred", 70, {"orders": 1}),
	])
	var allocated: Array[AiObjective] = AiObjectiveLedger.allocate(
		ranked, {"orders": 1}
	)
	var claims: Array[Dictionary] = AiObjectiveLedger.claims_of(allocated)

	assert_eq(claims.size(), 1)
	assert_eq(String(claims[0]["id"]), "funded")


# --- persistence -------------------------------------------------------------


func test_ai_objective_round_trips_through_a_dict() -> void:
	var parent: AiObjective = AiObjective.make(
		"colonisation.voyage", "colonisation", 72,
		{"orders": 1, "hull": 1, "civilian": 1}
	)
	var child: AiObjective = AiObjective.make(
		"colonisation.hull", "colonisation", 60, {"hull": 1}, "no idle hull"
	)
	parent.children.append(child)
	var restored: AiObjective = AiObjective.from_dict(parent.to_dict())

	assert_eq(restored.id, "colonisation.voyage")
	assert_eq(restored.utility, 72)
	assert_eq(restored.total_cost(), 3)
	assert_eq(restored.cost_of("hull"), 1)
	assert_eq(restored.children.size(), 1)
	assert_eq(restored.children[0].id, "colonisation.hull")
	assert_true(restored.children[0].is_blocked())
	assert_eq(restored.children[0].blocked, "no idle hull")


func test_ai_objective_drops_unknown_and_empty_pools() -> void:
	var objective: AiObjective = AiObjective.make(
		"x", "market", 40, {"treasury": 0, "cannon": 4, "hull": 2}
	)

	assert_eq(objective.cost, {"hull": 2})


func test_ai_state_round_trips_the_ledger_claims() -> void:
	var ai := AiState.new()
	ai.claims[1] = [{
		"id": "military.march.3",
		"domain": "military",
		"claim": {"orders": 1},
	}]
	var restored: AiState = AiState.from_dict(ai.to_dict())
	var rows: Array = restored.claims[1]

	assert_eq(rows.size(), 1)
	assert_eq(String(rows[0]["id"]), "military.march.3")
	assert_eq(int((rows[0]["claim"] as Dictionary)["orders"]), 1)


# --- utility -----------------------------------------------------------------


func test_utility_normalizes_each_planner_scale() -> void:
	assert_eq(AiUtility.normalize(50, 100), 50)
	assert_eq(AiUtility.normalize(42, 84), 50)
	assert_eq(AiUtility.normalize(0, 0, "diplomacy"), 0)
	assert_eq(AiUtility.normalize(100, 0, "diplomacy"), 100)


func test_posture_is_a_modifier_not_a_kill_switch() -> void:
	var peace: int = AiUtility.adjust(50, "colonisation", AiUtility.POSTURE_PEACE, "")
	var war: int = AiUtility.adjust(50, "colonisation", AiUtility.POSTURE_WAR, "")

	assert_true(war < peace, "a war footing lowers colonisation")
	assert_true(war > 0, "but never zeroes it")
	assert_true(
		AiUtility.adjust(50, "military", AiUtility.POSTURE_WAR, "")
		> AiUtility.adjust(50, "military", AiUtility.POSTURE_PEACE, "")
	)


# --- trace -------------------------------------------------------------------


func test_trace_lines_name_utility_cost_claim_and_reason() -> void:
	var ranked: Array[AiObjective] = AiObjectiveLedger.rank([
		_objective("military.march.1", 80, {"orders": 1, "regiment": 1}),
		_objective("naval.sortie.2", 60, {"hull": 1}),
	])
	var allocated: Array[AiObjective] = AiObjectiveLedger.allocate(
		ranked, {"orders": 1, "regiment": 1}
	)
	var lines: Array[String] = AiObjectiveLedger.trace_lines(allocated)

	assert_eq(lines.size(), 2)
	assert_true(lines[0].contains("u80"))
	assert_true(lines[0].contains("cost regiment 1, orders 1"))
	assert_true(lines[0].contains("funded"))
	assert_true(lines[1].contains("deferred"))
	assert_true(lines[1].contains("short hull 1"))


func test_turn_log_exposes_the_ledger_lines_for_a_court() -> void:
	var merged: Dictionary = {
		"objectives": {
			1: {"lines": ["#1 military.march.4 u60 funded regiment 1, orders 1"]},
		},
	}
	var lines: Array[String] = AiTurnLog.ledger_lines(merged, 1)

	assert_eq(lines.size(), 1)
	assert_true(lines[0].contains("military.march.4"))
	assert_eq(AiTurnLog.ledger_lines(merged, 5).size(), 0)


# --- emitters ----------------------------------------------------------------


func test_diplomacy_emitter_reads_the_turn_trace() -> void:
	var context: Dictionary = {
		"owner": 1,
		"phase": AiUtility.POSTURE_PEACE,
		"agenda": "",
		"ai_trace": [{
			"faction": 1,
			"candidates": [
				{"target": 2, "desire": 80, "at_war": false, "blocked": ""},
				{"target": 3, "desire": 20, "at_war": true, "blocked": "peace cooldown"},
			],
		}],
	}
	var objectives: Array[AiObjective] = AiObjectives.diplomacy(context)

	assert_eq(objectives.size(), 2)
	assert_eq(objectives[0].id, "diplomacy.war.2")
	assert_eq(objectives[0].utility, 80)
	assert_eq(objectives[0].status, AiObjective.STATUS_RANKED)
	assert_eq(objectives[1].id, "diplomacy.peace.3")
	assert_eq(objectives[1].status, AiObjective.STATUS_BLOCKED)
	assert_eq(objectives[1].blocked, "peace cooldown")


func test_economy_emitter_prices_the_scored_candidates() -> void:
	var context: Dictionary = {
		"owner": 1,
		"phase": AiUtility.POSTURE_PEACE,
		"agenda": "",
		"report": {
			"production": {
				"candidates": [{"recipe": "lumber", "score": 42, "assigned": 2}],
			},
		},
	}
	var objectives: Array[AiObjective] = AiObjectives.economy(context)

	assert_eq(objectives.size(), 1)
	assert_eq(objectives[0].id, "economy.production.lumber")
	assert_eq(
		objectives[0].utility,
		AiUtility.adjust(50, "economy", AiUtility.POSTURE_PEACE, "")
	)
	assert_eq(objectives[0].cost_of("labour"), 2)


func test_collect_emits_every_domain_that_acted() -> void:
	var context: Dictionary = {
		"owner": 1,
		"phase": AiUtility.POSTURE_WAR,
		"agenda": "warmonger",
		"ai_trace": [{
			"faction": 1,
			"candidates": [{"target": 2, "desire": 60, "at_war": false}],
		}],
		"army_trace": [{"faction": 1, "kind": "march", "army": 4}],
		"fleet_trace": [{"faction": 1, "kind": "sortie", "fleet": 2}],
		"invasion_trace": [{"faction": 1, "kind": "cross"}],
		"report": {
			"production": {
				"candidates": [{"recipe": "lumber", "score": 20, "assigned": 1}],
			},
			"research": {"candidates": [{"tech": "gunnery", "score": 60}]},
			"cargo": {"candidates": [{"kind": "route", "fleet_id": 3, "holds": 4}]},
			"trade": {
				"candidates": [{
					"kind": "bid", "commodity": "timber", "quantity": 2,
					"unit_price": 3, "deficit": 2,
				}],
			},
			"civilians": {
				"orders": [{"action": "build", "unit_id": 7, "score": 30}],
			},
			"recruits": [{"tier": 1}],
		},
		"units": [],
		"world": null,
	}
	var objectives: Array[AiObjective] = AiObjectives.collect(context)
	var domains: Dictionary = {}
	for objective: AiObjective in objectives:
		domains[objective.domain] = true

	for domain: String in [
		"diplomacy", "military", "naval", "invasion", "economy", "research",
		"cargo", "market", "civilian", "muster",
	]:
		assert_true(domains.has(domain), "missing %s objective" % domain)
