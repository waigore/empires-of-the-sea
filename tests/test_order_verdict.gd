extends GdToolsTest
## One home for an order verdict: the accept/refuse shape every army, navy,
## market and court order check returns (REQ-P3-01, REQ-P3-03).


func test_an_allowed_order_is_ok_with_no_reason() -> void:
	assert_eq(OrderVerdict.allow(), {"ok": true, "reason": ""})


func test_a_refused_order_carries_its_reason() -> void:
	assert_eq(
		OrderVerdict.deny("A fleet may only dock in a province it owns."),
		{"ok": false, "reason": "A fleet may only dock in a province it owns."}
	)


func test_an_allowed_order_keeps_the_rules_own_fields() -> void:
	var verdict: Dictionary = OrderVerdict.allow({"unit": "frigate", "cost": 40})
	assert_true(bool(verdict["ok"]), "an accept stays an accept")
	assert_eq(String(verdict["reason"]), "", "an accept has no reason")
	assert_eq(String(verdict["unit"]), "frigate", "the rule's unit rides along")
	assert_eq(int(verdict["cost"]), 40, "the rule's cost rides along")


func test_a_refused_order_keeps_the_rules_denied_fields() -> void:
	var verdict: Dictionary = OrderVerdict.deny("There is no army to split.", {"army": null})
	assert_false(bool(verdict["ok"]), "a refusal stays a refusal")
	assert_eq(String(verdict["reason"]), "There is no army to split.")
	assert_true(verdict.has("army"), "the denied field is present")
	assert_eq(verdict["army"], null, "the denied field reads its empty value")


func test_a_real_order_check_builds_its_verdict_here() -> void:
	var split: Dictionary = ArmyRoster.split([] as Array[ArmyState], null, [] as Array[String], 0)
	assert_false(bool(split.get("ok", true)), "a null army is refused")
	assert_true(split.has("army"), "the refusal carries the army field")
	assert_eq(split["army"], null, "and that field is null")
