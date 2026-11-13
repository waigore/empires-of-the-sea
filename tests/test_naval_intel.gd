extends GdToolsTest
## The crown's watch over rival squadrons (wiki: ships-and-naval
## § Sighted strength; DR-20261113-20, `NavalIntel`).
## The rule is plain state: a rival sighted this turn is unread until she is
## still in view at a later turn's opening, and leaving the crown's chart starts
## the watch over.

const FLEET: int = 41
const OTHER: int = 42


func test_a_first_sighting_is_unread() -> void:
	var intel := NavalIntel.new()

	assert_eq(intel.observe([FLEET], 5), [])
	assert_false(intel.is_revealed(FLEET), "a first sighting gives up no weight")


func test_the_same_turn_refreshes_do_not_read_her() -> void:
	var intel := NavalIntel.new()

	intel.observe([FLEET], 5)
	intel.observe([FLEET, OTHER], 5)
	intel.observe([FLEET], 5)

	assert_false(intel.is_revealed(FLEET), "the watch needs a turn boundary")
	assert_false(intel.is_revealed(OTHER))


func test_a_rival_still_in_view_next_turn_is_read_once() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5)

	assert_eq(intel.observe([FLEET], 6), [FLEET])
	assert_true(intel.is_revealed(FLEET), "a squadron watched across a turn is read")
	assert_eq(intel.observe([FLEET], 7), [], "the news is told once")
	assert_true(intel.is_revealed(FLEET))


func test_a_rival_not_seen_at_the_boundary_is_read_at_the_next_one() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5)
	intel.observe([], 6)

	assert_false(intel.is_revealed(FLEET), "slipping out of view starts the watch over")
	intel.observe([FLEET], 7)

	assert_false(intel.is_revealed(FLEET), "a fresh sighting is unread again")
	assert_eq(intel.observe([FLEET], 8), [FLEET])


func test_leaving_view_forgets_the_read() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5)
	intel.observe([FLEET], 6)
	assert_true(intel.is_revealed(FLEET))

	intel.observe([], 7)

	assert_false(intel.is_revealed(FLEET), "out of sight is out of knowledge")
	assert_eq(intel.watched(), [], "no squadrons under the eye")


func test_a_gap_in_the_watch_does_not_read_her() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5)
	intel.observe([], 6)
	intel.observe([FLEET], 6)

	assert_false(intel.is_revealed(FLEET), "the second sighting is still this turn")


func test_the_watch_survives_a_save() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5)
	intel.observe([FLEET, OTHER], 6)
	var restored: NavalIntel = NavalIntel.from_dict(intel.to_dict())

	assert_true(restored.is_revealed(FLEET), "a read squadron stays read")
	assert_false(restored.is_revealed(OTHER), "an unread squadron stays unread")
	assert_eq(restored.watched(), [FLEET, OTHER], "both stay under the eye")
	assert_eq(restored.observe([OTHER], 7), [OTHER], "the clock resumes")


func test_a_save_without_a_watch_resumes_empty() -> void:
	assert_eq(NavalIntel.from_dict({}).watched(), [])
	assert_eq(NavalIntel.from_dict(null).watched(), [])
	assert_false(NavalIntel.from_dict({"seen": "stale"}).is_revealed(FLEET))


func test_a_dossier_reads_a_rival_only_once_her_watch_closes() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5)
	var my_fleet := FleetState.at_sea(1, 0, 7, ["hull_1"], {"hull_1": "carrack"})
	var rival := FleetState.at_sea(FLEET, 1, 7, ["hull_2"], {"hull_2": "carrack"})
	var known := func(other: FleetState) -> bool: return intel.is_revealed(other.id)

	var unread: Dictionary = NavalStrength.dossier(
		[my_fleet, rival], my_fleet, Callable(), {}, {}, known
	)
	assert_true(bool((unread["zone"] as Dictionary).get("unread", false)),
		"an unread rival weighs nothing in the odds")

	intel.observe([FLEET], 6)
	var read: Dictionary = NavalStrength.dossier(
		[my_fleet, rival], my_fleet, Callable(), {}, {}, known
	)
	assert_false(bool((read["zone"] as Dictionary).get("unread", false)))
	assert_gt(float(read["zone"]["foe"]), 0.0, "a read rival counts in the zone")


func test_a_sighted_rival_dossier_is_fogged() -> void:
	var fogged: Dictionary = NavalStrength.fogged()

	assert_eq(int(fogged["count"]), 1, "the block still shows")
	assert_false(bool(fogged["known"]))
	assert_almost_eq(float(fogged["strength"]), 0.0, 0.0001, "no weight leaks")
