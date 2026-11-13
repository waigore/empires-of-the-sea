extends GdToolsTest
## The pause door: one MENU seal, parked by every full-screen ledger and sealed
## for good by the full-AI observer (REQ-P3-02, REQ-P5-02). The three ledgers now
## ask GameMenu for the seal instead of walking the tree for a node path, so the
## parking rule itself needs its own suite (REQ-P3-04).

const SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")


func _seal() -> Button:
	var seal := Button.new()
	add_child(seal)
	return seal


func test_a_parked_door_hides_the_seal_and_a_release_shows_it() -> void:
	var door := GameMenuDoor.new()
	var seal := _seal()
	door.mount(seal)
	assert_true(seal.visible, "a fresh menu shows its seal")

	door.park()
	assert_false(seal.visible, "a ledger parks the seal")
	assert_true(door.is_parked(), "the door knows a ledger holds it")

	door.release()
	assert_true(seal.visible, "closing the ledger gives the seal back")
	assert_false(door.is_parked())


## The estates card, the civilian roster and the muster roll all use this rule:
## the first to open parks, the second leaves it alone, and the second to close
## does not hand the seal back while the first still holds it.
func test_two_ledgers_keep_the_door_parked_until_the_last_closes() -> void:
	var door := GameMenuDoor.new()
	var seal := _seal()
	door.mount(seal)

	var first: bool = GameMenuDoor.set_held(door, false, false)
	assert_true(first, "the first ledger parks the door")
	var second: bool = GameMenuDoor.set_held(door, false, false)
	assert_false(second, "a second ledger finds it already parked and claims nothing")
	assert_false(seal.visible)

	# The second ledger closes: it claimed no hold, so the door stays parked.
	assert_false(GameMenuDoor.set_held(door, true, second), "the second close releases nothing")
	assert_false(seal.visible, "the first ledger's frame keeps the seal parked")
	# The first ledger closes: the last close hands the seal back.
	assert_false(GameMenuDoor.set_held(door, true, first), "the last close is not its own either")
	assert_true(seal.visible, "the seal returns once the last ledger closes")


## A ledger that closes without opening (the estates card lives on the map all
## turn) must not hand the seal to the observer's hidden chrome.
func test_a_close_without_an_open_never_releases_the_seal() -> void:
	var door := GameMenuDoor.new()
	var seal := _seal()
	door.mount(seal)
	door.seal()

	assert_false(
		GameMenuDoor.set_held(door, true, false),
		"a stray close claims no hold"
	)
	assert_false(seal.visible, "the observer keeps its chrome sealed")


func test_a_standalone_menu_without_a_page_keeps_its_seal() -> void:
	var door := GameMenuDoor.new()
	var seal := _seal()
	door.mount(seal)
	assert_false(GameMenuDoor.set_held(null, true, false), "no menu, no hold")
	assert_true(GameMenuDoor.set_held(null, false, true), "no menu, nothing parked")
	assert_true(seal.visible)


## The observer's seal outlives every ledger: a panel that parks and releases
## while the observatory runs still leaves the human chrome hidden.
func test_a_release_never_lifts_the_observers_seal() -> void:
	var door := GameMenuDoor.new()
	var seal := _seal()
	door.mount(seal)
	door.seal()
	door.park()
	door.release()
	assert_false(seal.visible, "the observer keeps its seal")


## A door that never got its crest (a menu built without a page) still tracks
## parking instead of crashing on the missing button.
func test_a_door_without_a_crest_still_tracks_its_hold() -> void:
	var door := GameMenuDoor.new()
	door.park()
	assert_true(door.is_parked(), "no crest, the state still moves")
	door.release()
	assert_false(door.is_parked())


## The map screen hands its menu to the session, so the ledgers reach the seal
## through the narrow session surface, and the observer seals it for the run.
func test_the_screen_binds_the_door_and_the_observer_seals_it() -> void:
	var screen: MapScreen = SCREEN.instantiate()
	screen.map_width = 32
	screen.map_height = 24
	screen.observer_mode = true
	add_child(screen)
	assert_not_null(screen.play, "the session is live")
	if screen.play == null:
		return
	assert_true(screen.play.pause_menu == screen.game_menu, "the session names its pause menu")
	var seal: Button = screen.hud.top_row.find_child("MenuSeal", true, false) as Button
	assert_not_null(seal, "the MENU seal is mounted on the bar")
	if seal == null:
		return
	assert_false(seal.visible, "the observer owns no pause door")
	assert_true(screen.game_menu.door.is_sealed(), "the door stays sealed for the run")
	# The card is built on this screen all turn and closes on every back press:
	# that close must never hand the observer's chrome back.
	screen.improvements.close()
	assert_false(seal.visible, "a stray close leaves the observer's door sealed")
