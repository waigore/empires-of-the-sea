extends GdToolsTest
## AI parameter registry and blessed profiles (wiki: ai-parameter-registry,
## ai-profile-overrides).


func test_registry_exposes_the_documented_defaults() -> void:
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_desire_base"), 50)
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_declare_min_desire"), 51)
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_relation_ceiling"), 50)
	assert_eq(AiParameterRegistry.default_of("diplomacy.war_cooldown_turns"), 4)
	assert_eq(AiParameterRegistry.default_of("diplomacy.overture_cooldown_turns"), 2)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_province_weight"), 10)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_regiment_weight"), 1)
	assert_eq(AiParameterRegistry.default_of("diplomacy.power_ship_weight"), 5)
	assert_eq(AiParameterRegistry.keys().size(), AiParameterRegistry.PARAMETERS.size())


func test_unknown_keys_fall_back_instead_of_crashing() -> void:
	assert_false(AiParameterRegistry.has("diplomacy.made_up"))
	assert_eq(AiParameterRegistry.default_of("diplomacy.made_up", -1), -1)
	assert_eq(AiParameterRegistry.resolve("diplomacy.made_up"), 0)
	assert_eq(AiParameterRegistry.in_bounds("diplomacy.made_up", 1), false)


func test_resolve_prefers_an_in_bounds_override() -> void:
	var overrides: Dictionary = {"diplomacy.war_relation_ceiling": 70}
	assert_eq(AiParameterRegistry.resolve("diplomacy.war_relation_ceiling", overrides), 70)
	assert_eq(
		AiParameterRegistry.resolve("diplomacy.war_declare_min_desire", overrides), 51,
		"missing keys inherit the registry default"
	)


func test_resolve_ignores_out_of_bounds_and_non_integer_overrides() -> void:
	assert_eq(
		AiParameterRegistry.resolve(
			"diplomacy.war_relation_ceiling", {"diplomacy.war_relation_ceiling": 200}
		),
		50
	)
	assert_eq(
		AiParameterRegistry.resolve(
			"diplomacy.war_relation_ceiling", {"diplomacy.war_relation_ceiling": "high"}
		),
		50
	)
	assert_eq(
		AiParameterRegistry.resolve(
			"diplomacy.war_relation_ceiling", {"diplomacy.war_relation_ceiling": 62.5}
		),
		50
	)


func test_validate_rejects_unknown_and_invalid_values() -> void:
	var good: Dictionary = AiParameterRegistry.validate(
		{"diplomacy.war_declare_min_desire": 45}
	)
	assert_true(bool(good["ok"]))
	var bad: Dictionary = AiParameterRegistry.validate(
		{"diplomacy.nope": 1, "diplomacy.war_cooldown_turns": 99}
	)
	assert_false(bool(bad["ok"]))
	assert_eq(bad["rejected"], ["diplomacy.nope", "diplomacy.war_cooldown_turns"])


func test_blessed_profiles_override_the_registry() -> void:
	assert_true(AiProfile.has(AiProfile.AGGRESSIVE))
	assert_false(AiProfile.has("bogus"))
	assert_eq(
		AiProfile.resolve("diplomacy.war_relation_ceiling", AiProfile.AGGRESSIVE), 70
	)
	assert_eq(
		AiProfile.resolve("diplomacy.war_declare_min_desire", AiProfile.ECONOMIC), 65
	)
	assert_eq(
		AiProfile.resolve("diplomacy.war_relation_ceiling", "bogus"), 50,
		"an unknown profile falls back to neutral defaults"
	)
	assert_true(bool(AiProfile.validate(AiProfile.AGGRESSIVE)["ok"]))
	assert_false(bool(AiProfile.validate("bogus")["ok"]))
	assert_eq(AiProfile.ids().size(), 3)
