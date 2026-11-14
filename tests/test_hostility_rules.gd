extends GdToolsTest
## The shared war query: the naval rules and the rival planners read one
## hostility predicate and one at-war membership set (REQ-P3-03, REQ-P3-04).


func test_a_faction_is_never_hostile_to_itself() -> void:
	assert_false(Hostility.between(Callable(), 3, 3))
	assert_false(Hostility.between(func(_a: int, _b: int) -> bool: return true, 3, 3))


func test_an_unset_query_keeps_every_other_faction_hostile() -> void:
	assert_true(Hostility.between(Callable(), 1, 2))


func test_a_set_query_decides_the_pair() -> void:
	var at_war: Callable = func(a: int, b: int) -> bool: return a == 1 and b == 2
	assert_true(Hostility.between(at_war, 1, 2))
	assert_false(Hostility.between(at_war, 2, 1))


func test_no_court_reads_no_known_wars() -> void:
	assert_true(Hostility.owners(null, 1).is_empty())


func test_owners_lists_every_court_at_war() -> void:
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(1, 2).at_war = true
	state.ensure_relation(1, 3).at_war = false
	var hostile: Dictionary = Hostility.owners(state, 1)
	assert_true(hostile.has(2))
	assert_false(hostile.has(3))
	assert_false(hostile.has(1))
