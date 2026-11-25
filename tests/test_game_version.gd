extends GdToolsTest
## Smoke tests for GameVersion helpers.


func test_as_string_matches_semver_parts() -> void:
	assert_eq(GameVersion.as_string(), "0.1.0")


func test_is_compatible_with_matching_major() -> void:
	assert_true(GameVersion.is_compatible_with(GameVersion.MAJOR))


func test_is_compatible_with_rejects_other_major() -> void:
	assert_false(GameVersion.is_compatible_with(GameVersion.MAJOR + 1))
