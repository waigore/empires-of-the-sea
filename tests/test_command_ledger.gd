extends GdToolsTest
## The crown's command ledger: the pool of generals read as a ledger — who each
## commander is, what his medals buy in the field and which study raises the cap
## next (wiki: military-generals § Generals, § Count and tech-gated cap,
## § Medals; DR-20261115-11) — and the sheet that prints it. One Godot boot: the
## projection cases read a small roster, the drive mounts the shared map screen
## (docs/testing.md).

const Fixture = preload("res://tests/map_fixture.gd")

var screen: MapScreen = null


func before_all() -> void:
	screen = Fixture.attach_screen(self)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.hud.command_ledger.close()
		screen.free()
	screen = null


func before_each() -> void:
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	screen.hud.command_ledger.close()


# --- projection -------------------------------------------------------------


func test_the_pool_reads_every_commander_with_his_medals() -> void:
	var roster := GeneralRoster.new()
	roster.sync(0, {})
	roster.award(0, "general_1")
	var data: Dictionary = CommandLedger.snapshot(roster, 0, {}, "isabella")
	assert_eq(int(data["held"]), 1, "the opening cap is one commander")
	assert_eq(int(data["cap"]), 1)
	assert_false(bool(data["above_cap"]))
	var row: Dictionary = (data["rows"] as Array)[0]
	assert_eq(String(row["id"]), "general_1")
	assert_ne(String(row["name"]), "", "every commander is christened")
	assert_eq(int(row["medals"]), 1, "the medal he won is read")
	assert_false(bool(row["full"]), "one medal is not the ceiling")


func test_the_cap_follows_the_studied_rungs() -> void:
	var roster := GeneralRoster.new()
	assert_eq(roster.sync(0, {}), 1, "the opening cap")
	assert_eq(roster.sync(0, {"organised_regiments": true}), 2)
	assert_eq(
		roster.sync(0, {"organised_regiments": true, "national_bureaucracy": true}), 3
	)
	assert_eq(
		roster.sync(
			0,
			{
				"organised_regiments": true,
				"national_bureaucracy": true,
				"improved_infantry_tactics": true,
			},
		),
		3,
		"the two cap-3 rungs do not stack"
	)
	assert_eq(roster.sync(0, {"nationalism": true}), 4, "nationalism alone reaches four")
	var data: Dictionary = CommandLedger.snapshot(roster, 0, {"nationalism": true}, "")
	assert_eq(int(data["cap"]), 4)
	assert_eq(int(data["held"]), 4, "the pool always holds the cap")


func test_the_road_names_the_next_study() -> void:
	var opening: Dictionary = CommandLedger.snapshot(GeneralRoster.new(), 0, {}, "")
	var next: Dictionary = opening["next"]
	assert_eq(String(next["tech"]), "organised_regiments", "the first rung is named")
	assert_eq(int(next["cap"]), 2)
	assert_eq(String(next["name"]), TechCatalog.display_name("organised_regiments"))
	assert_true(
		CommandLedger.summary(opening).contains("next: "),
		"the count line names the road"
	)
	var studied: Dictionary = CommandLedger.snapshot(
		GeneralRoster.new(), 0, {"organised_regiments": true}, ""
	)
	assert_eq(String((studied["next"] as Dictionary)["tech"]), "national_bureaucracy")
	var ceiling: Dictionary = CommandLedger.snapshot(
		GeneralRoster.new(), 0, {"nationalism": true}, ""
	)
	assert_true((ceiling["next"] as Dictionary).is_empty(), "four is the ceiling")
	assert_true(CommandLedger.summary(ceiling).contains("ceiling is 4"))


func test_the_road_reads_every_rung_and_which_are_studied() -> void:
	var road: Array[Dictionary] = CommandLedger.road({"nationalism": true})
	assert_eq(road.size(), CommandLedger.ROAD.size(), "every published rung is read")
	var studied: int = 0
	for rung: Dictionary in road:
		if bool(rung["unlocked"]):
			studied += 1
	assert_eq(studied, 1, "only the rung the crown studied reads taken")
	assert_eq(CommandLedger.ceiling(), 4)


func test_an_above_cap_roster_is_read_not_trimmed() -> void:
	var roster := GeneralRoster.new()
	roster.sync(0, {"nationalism": true})
	var data: Dictionary = CommandLedger.snapshot(roster, 0, {}, "")
	assert_eq(int(data["held"]), 4, "the roster keeps every commander it spawned")
	assert_eq(int(data["cap"]), 1, "the cap is the studies' own")
	assert_true(bool(data["above_cap"]), "an above-cap roster is tolerated, not trimmed")
	assert_true(
		CommandLedger.summary(data).begins_with("4 commanders (cap 1)"),
		"the count line reads the roster against the studies' own cap"
	)


func test_a_medal_buys_the_combat_modules_own_figures() -> void:
	var one: Dictionary = CommandLedger.effects(1)
	assert_eq(int(one["line"]), 1, "one more regiment in the line")
	assert_eq(int(one["morale_pct"]), 5, "the aura's own step")
	assert_eq(int(one["initiative"]), 10, "the medal weight")
	var four: Dictionary = CommandLedger.effects(4)
	assert_eq(int(four["line"]), 4)
	assert_eq(int(four["morale_pct"]), 20, "the aura caps at a fifth")
	assert_eq(int(four["initiative"]), 40)
	var clamped: Dictionary = CommandLedger.effects(9)
	assert_eq(int(clamped["line"]), 4, "no commander earns a fifth medal")
	assert_true(CommandLedger.medal_line().contains("+1 regiment in the line"))


func test_the_fallback_reads_the_leaders_own_medals() -> void:
	var napoleon: Dictionary = CommandLedger.fallback("napoleon")
	assert_eq(int(napoleon["attack"]), 4, "a 1.25 leader fights as four medals")
	assert_eq(int(napoleon["defend"]), 4)
	var gustavus: Dictionary = CommandLedger.fallback("gustavus")
	assert_eq(int(gustavus["attack"]), 2, "his bonus is published attacking only")
	assert_eq(int(gustavus["defend"]), 0)
	var neutral: Dictionary = CommandLedger.fallback(LeaderCatalog.DEFAULT_KEY)
	assert_eq(int(neutral["attack"]), 0, "a crown with no leader falls back to none")
	var data: Dictionary = CommandLedger.snapshot(GeneralRoster.new(), 0, {}, "napoleon")
	assert_true(CommandLedger.fallback_line(data).contains("4 medals"))


# --- the row ----------------------------------------------------------------


func test_a_row_prints_the_medals_and_what_they_buy() -> void:
	var row := CommandLedgerRow.new()
	row.setup({
		"name": "Don Álvaro",
		"medals": 2,
		"effects": CommandLedger.effects(2),
		"full": false,
	})
	assert_eq(row._name.text, "Don Álvaro")
	assert_eq(row._medals.text, "×2")
	assert_true(row._effects.text.contains("Line +2"), "the line a medal adds")
	assert_true(row._effects.text.contains("morale +10%"))
	assert_true(row._effects.text.contains("initiative +20"))
	row.free()


func test_a_row_reads_a_commander_with_no_medals_and_one_at_the_ceiling() -> void:
	var bare := CommandLedgerRow.new()
	bare.compact = true
	bare.setup({"name": "A new commander", "medals": 0, "effects": CommandLedger.effects(0)})
	assert_eq(bare._medals.text, "—", "no decoration reads as none")
	assert_true(bare._effects.text.contains("No medals yet"))
	bare.free()
	var full := CommandLedgerRow.new()
	full.setup({
		"name": "A veteran",
		"medals": GeneralRoster.MAX_MEDALS,
		"effects": CommandLedger.effects(GeneralRoster.MAX_MEDALS),
		"full": true,
	})
	assert_eq(full._medals.text, "×4")
	assert_true(full._effects.text.contains("every medal he can earn"))
	full.free()


func test_a_session_with_no_army_layer_reads_an_empty_pool() -> void:
	var data: Dictionary = MapPlayCommand.snapshot(null)
	assert_eq(int(data["held"]), 0, "no layer, no commanders")
	assert_true((data["rows"] as Array).is_empty())
	assert_eq(int(data["cap"]), GeneralRoster.BASE_CAP, "the cap is still the rules'")


# --- the sheet --------------------------------------------------------------


func test_the_command_door_opens_the_ledger_and_lists_the_pool() -> void:
	var panel: CommandLedgerPanel = screen.hud.command_ledger
	assert_not_null(panel, "the HUD mounts the command ledger")
	var play: PlaySession = screen.play
	play.army_layer.sync_generals(play.player_faction, play.tech_unlocked())
	var door: Button = _command_door()
	assert_not_null(door, "the army dossier carries the command door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the dossier's command door opens it")
	assert_true(_row_widgets(panel) > 0, "the crown's commanders are listed")
	assert_true(
		panel._subtitle.text.contains("commander"),
		"the count line names the pool"
	)
	assert_true(panel._medal.text.contains("Each medal"), "the medal note is printed")


func test_back_and_the_key_close_the_ledger() -> void:
	var panel: CommandLedgerPanel = screen.hud.command_ledger
	screen.hud.command_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.COMMAND_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


# --- fixtures ---------------------------------------------------------------


## The army dossier's command door, found by its word so the suite reads the
## button the player presses.
func _command_door() -> Button:
	for node: Node in screen.hud._army_panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Commanders":
			return button
	return null


func _row_widgets(panel: CommandLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is CommandLedgerRow:
			total += 1
	return total
