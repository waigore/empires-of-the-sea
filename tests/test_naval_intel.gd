extends GdToolsTest
## The crown's watch over rival squadrons (wiki: ships-and-naval
## § Sighted strength; DR-20261113-20, `NavalIntel`).
## The rule is plain state: a rival sighted this turn is unread until she is
## still in view at a later turn's opening, and leaving the crown's chart starts
## the watch over. The watch is kept per chart, because fleet ids are minted per
## roster and id 5 stands for a different squadron on each map.

const FLEET: int = 41
const OTHER: int = 42
const OLD_WORLD: int = FactionCatalog.OLD_WORLD
const NEW_WORLD: int = FactionCatalog.NEW_WORLD


func test_a_first_sighting_is_unread() -> void:
	var intel := NavalIntel.new()

	assert_eq(intel.observe([FLEET], 5, OLD_WORLD), [])
	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "a first sighting gives up no weight")


func test_the_same_turn_refreshes_do_not_read_her() -> void:
	var intel := NavalIntel.new()

	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET, OTHER], 5, OLD_WORLD)
	intel.observe([FLEET], 5, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "the watch needs a turn boundary")
	assert_false(intel.is_revealed(OTHER, OLD_WORLD))


func test_a_rival_still_in_view_next_turn_is_read_once() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)

	assert_eq(intel.observe([FLEET], 6, OLD_WORLD), [FLEET])
	assert_true(intel.is_revealed(FLEET, OLD_WORLD), "a squadron watched across a turn is read")
	assert_eq(intel.observe([FLEET], 7, OLD_WORLD), [], "the news is told once")
	assert_true(intel.is_revealed(FLEET, OLD_WORLD))


func test_a_rival_not_seen_at_the_boundary_is_read_at_the_next_one() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([], 6, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD),
		"slipping out of view starts the watch over")
	intel.observe([FLEET], 7, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "a fresh sighting is unread again")
	assert_eq(intel.observe([FLEET], 8, OLD_WORLD), [FLEET])


func test_leaving_view_forgets_the_read() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET], 6, OLD_WORLD)
	assert_true(intel.is_revealed(FLEET, OLD_WORLD))

	intel.observe([], 7, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "out of sight is out of knowledge")
	assert_eq(intel.watched(OLD_WORLD), [], "no squadrons under the eye")


func test_a_gap_in_the_watch_does_not_read_her() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([], 6, OLD_WORLD)
	intel.observe([FLEET], 6, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "the second sighting is still this turn")


func test_the_watch_survives_a_save() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET, OTHER], 6, OLD_WORLD)
	var restored: NavalIntel = NavalIntel.from_dict(intel.to_dict())

	assert_true(restored.is_revealed(FLEET, OLD_WORLD), "a read squadron stays read")
	assert_false(restored.is_revealed(OTHER, OLD_WORLD), "an unread squadron stays unread")
	assert_eq(restored.watched(OLD_WORLD), [FLEET, OTHER], "both stay under the eye")
	assert_eq(restored.observe([OTHER], 7, OLD_WORLD), [OTHER], "the clock resumes")


## Fleet ids are minted per roster, so the same id stands for another squadron on
## the other chart: a read earned on one map must never hand over the other's
## weight, and looking away must not clear the watch behind it.
func test_each_chart_keeps_its_own_watch() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET], 6, OLD_WORLD)
	assert_true(intel.is_revealed(FLEET, OLD_WORLD))

	assert_false(intel.is_revealed(FLEET, NEW_WORLD),
		"a New World squadron of the same id is not the Old World one")

	intel.observe([FLEET], 7, NEW_WORLD)

	assert_true(intel.is_revealed(FLEET, OLD_WORLD),
		"another chart is not another water")
	assert_false(intel.is_revealed(FLEET, NEW_WORLD),
		"the New World watch starts from her own sighting")
	assert_eq(intel.watched(NEW_WORLD), [FLEET])

	var restored: NavalIntel = NavalIntel.from_dict(intel.to_dict())
	assert_true(restored.is_revealed(FLEET, OLD_WORLD), "both watches ride the save")
	assert_false(restored.is_revealed(FLEET, NEW_WORLD))


## A save written before the watch was kept per chart carries one flat watch; it
## belonged to the chart the court stood on.
func test_a_flat_watch_from_an_older_save_lands_on_its_own_chart() -> void:
	var legacy: Dictionary = {"seen": {FLEET: 5}, "revealed": [FLEET]}
	var restored: NavalIntel = NavalIntel.from_dict(legacy, NEW_WORLD)

	assert_true(restored.is_revealed(FLEET, NEW_WORLD))
	assert_false(restored.is_revealed(FLEET, OLD_WORLD))
	assert_eq(NavalIntel.from_dict(legacy).watched(NEW_WORLD), [],
		"a flat watch with no chart to sit on is dropped, not guessed")


func test_a_save_without_a_watch_resumes_empty() -> void:
	assert_eq(NavalIntel.from_dict({}).watched(OLD_WORLD), [])
	assert_eq(NavalIntel.from_dict(null).watched(OLD_WORLD), [])
	assert_false(NavalIntel.from_dict({"seen": "stale"}, OLD_WORLD).is_revealed(FLEET, OLD_WORLD))
	assert_false(
		NavalIntel.from_dict({"regions": "stale"}, OLD_WORLD).is_revealed(FLEET, OLD_WORLD)
	)


func test_a_dossier_reads_a_rival_only_once_her_watch_closes() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	var my_fleet := FleetState.at_sea(1, 0, 7, ["hull_1"], {"hull_1": "carrack"})
	var rival := FleetState.at_sea(FLEET, 1, 7, ["hull_2"], {"hull_2": "carrack"})
	var known := func(other: FleetState) -> bool: return intel.is_revealed(other.id, OLD_WORLD)

	var unread: Dictionary = NavalStrength.dossier(
		[my_fleet, rival], my_fleet, Callable(), {}, {}, known
	)
	assert_true(bool((unread["zone"] as Dictionary).get("unread", false)),
		"an unread rival weighs nothing in the odds")

	intel.observe([FLEET], 6, OLD_WORLD)
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
