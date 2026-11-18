extends SceneTree
## Headless free-playtest drive for the Battle Simulator (wiki: quick-battle;
## docs/testing.md § Local). The sandbox is the instrument a playtester reasons
## about Quick Battle with, and it has no drive of its own: this one mounts the
## real scene, presses its own rail (ground, fort, battery line, men, plans,
## medals, Fight, Next round, Reset) and reads what it prints back — the header,
## the number line, the despatch and the plate — against the record the live
## resolver returned, and against the aftermath the game's own plate shows.
##
##   godot --headless --path . --script res://playtests/playtest_battle_sim.gd
##
## Not a CI gate. A failure prints "FAIL: …" and the run exits non-zero.

const DESKTOP: Vector2i = Vector2i(1440, 720)
const HANDSET: Vector2 = Vector2(720, 360)
## The aftermath lines the game's plate prints, in the order it prints them
## (`quick_battle_overlay.gd`). The sandbox must read the same sheet.
const AFTERMATH_LINES: Array[String] = [
	"Ground — ", "Wings — ", "Line — ", "Losses — ", "Mauled — ", "Chevrons — ",
	"Honours — ", "Citations — ",
]

var _steps: PackedStringArray = PackedStringArray()
var _failures: PackedStringArray = PackedStringArray()
var _screen: BattleSimScreen = null
var _holder: Control = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = DESKTOP
	_screen = (load("res://scenes/battle_sim.tscn") as PackedScene).instantiate()
	root.add_child(_screen)
	await _idle(3)
	_opening_read()
	await _empty_side_pass()
	await _walk_pass()
	await _despatch_pass()
	await _levers_pass()
	await _ground_matrix()
	await _handset_pass()
	_finish()


# --- passes -----------------------------------------------------------------


## The sandbox as it opens: a header that says nothing has been fought, a rail
## holding the published defaults, and a plate at rest.
func _opening_read() -> void:
	_say("")
	_say("--- the sandbox as it opens ---")
	_check(_screen._header.text == "No battle yet", "the opening header names no battle, not a blank line")
	_check(_screen._status.text.contains("set the ground"), "the opening status says what to set")
	_check(_screen._result.is_empty(), "no record is resolved before Fight")
	var spec: Dictionary = _screen._setup.spec()
	_say("rail: Attack %d men, Garrison %d men, %s, %s" % [
		(spec["attacker"] as Array).size(), (spec["defender"] as Array).size(),
		BattleSimSetup.FORT_LABELS[int(spec["fort"])], String(spec["terrain"]),
	])
	_check((spec["attacker"] as Array).size() > 0, "the opening rail seats an attack")
	_check((spec["defender"] as Array).size() > 0, "the opening rail seats a garrison")


## An emptied rail: the sandbox must refuse by name rather than field a default
## army the playtester never set (wiki: quick-battle § The crown's plan — a
## scenario's men are its own).
func _empty_side_pass() -> void:
	_say("")
	_say("--- a rail with no men ---")
	_seat(_screen._setup, "attacker", [])
	_screen._fight()
	await _idle(1)
	_check(_screen._result.is_empty(), "an emptied attacker resolves no battle")
	_check(_screen._status.text.begins_with("The Attack fields no men"), "the refusal names the empty side")
	_check(_screen._log.text.is_empty(), "a refused Fight writes no despatch")
	_screen._step()
	await _idle(1)
	_check(_screen._result.is_empty(), "Next round cannot resolve a refused setup")
	_seat(_screen._setup, "defender", [])
	_seat(_screen._setup, "attacker", [["musketeers", 4]])
	_screen._fight()
	await _idle(1)
	_check(_screen._status.text.begins_with("The Garrison fields no men"), "the garrison's emptiness is named too")
	_say("refusals: \"%s\"" % _screen._status.text)
	_seat(_screen._setup, "defender", [["pikemen", 4], ["musketeers", 2]])
	_seat(_screen._setup, "attacker", [["musketeers", 6], ["culverin", 1]])
	_screen._setup._fort.selected = 2


## The step walk: Fight then Next round must reach every round the record holds
## and then the aftermath, and only then start the plate over — the outcome is
## the walk's own end, not a second button's secret.
func _walk_pass() -> void:
	_say("")
	_say("--- the step walk ---")
	_screen._fight()
	var rounds: Array = _screen._rounds()
	_check(rounds.size() > 0, "Fight resolves at least one round")
	_check(int(_screen._field.outcome) >= 0, "Fight stamps the outcome")
	var seen: Array[int] = [int(_screen._field.round_index)]
	for index in rounds.size():
		_screen._step()
		await _idle(1)
		seen.append(int(_screen._field.round_index))
		_say("step -> round %d, status \"%s\"" % [
			int(_screen._field.round_index) + 1, _screen._status.text,
		])
		_check(_screen._field.round_index == index, "step %d shows round %d" % [index, index + 1])
	_screen._step()
	await _idle(1)
	_check(
		_screen._field.round_index == rounds.size() - 1,
		"the walk's next step is the aftermath, where the last round left the lines"
	)
	_check(_screen._status.text == _screen._status.text.strip_edges(), "the aftermath prints a status")
	_check(not _screen._status.text.begins_with("Round "), "the aftermath is not a round")
	_say("after the last round: \"%s\"" % _screen._status.text)
	_screen._step()
	await _idle(1)
	_check(_screen._field.round_index == 0, "stepping past the aftermath starts the plate over")
	var doors: PackedStringArray = PackedStringArray()
	for index in _screen._round_buttons.get_child_count():
		var button: Button = _screen._round_buttons.get_child(index) as Button
		if not button.disabled:
			doors.append(button.text)
	_say("doors a %d-round record opens: %s" % [rounds.size(), str(doors)])
	for index in QuickBattleTerms.MAX_ROUNDS:
		var button: Button = _screen._round_buttons.get_child(index) as Button
		_check(
			button.disabled == (index >= rounds.size()),
			"round %d's door is %s" % [index + 1, "shut" if index >= rounds.size() else "open"]
		)


## The despatch against the game's own plate: the same aftermath lines, in the
## same order, with the line's numbers taken from the record — a sandbox that
## reads fewer lines than the game hides its subject.
func _despatch_pass() -> void:
	_say("")
	_say("--- the despatch against the game's plate ---")
	for slot: Dictionary in _screen._setup._attacker_slots:
		(slot["count"] as SpinBox).value = 20
	_screen._setup._attacker_plan.selected = 1
	## Broken ground, so the ground's own line is on the sheet too (open ground
	## has no penalty to name and prints none).
	_screen._setup._terrain.selected = _terrain_row("hill")
	_screen._fight()
	var report: Dictionary = _screen._result["report"]
	var text: String = _screen._log.text
	_say("rail seats %d men; the plate opens with %d" % [
		(_screen._setup.spec()["attacker"] as Array).size(), int(_screen._field.attacker_start),
	])
	var deployed: int = int(report.get("attacker_deployed", 0))
	var reserve: int = int(report.get("attacker_reserve", 0))
	_check(reserve > 0, "the rail seats an army larger than the line, or the line is untested")
	_check(
		text.contains("Line — The Attack: %d of %d in the line" % [deployed, deployed + reserve]),
		"the despatch names the men who waited behind the line"
	)
	for line: String in AFTERMATH_LINES:
		if line in ["Honours — ", "Citations — "]:
			continue
		_check(text.contains(line), "the despatch prints the game's \"%s\" line" % line.strip_edges())
	_say("the line the game prints, as the sandbox prints it:")
	for row: String in text.split("\n"):
		if row.begins_with("Line — ") or row.begins_with("Chevrons — "):
			_say("  " + row)
	var missing: int = 0
	for round: Dictionary in _screen._rounds():
		for action: Dictionary in round.get("actions", []) as Array:
			if not text.contains(QuickBattleCopy.action_line(action, report, BattleSimScreen.NAMES)):
				missing += 1
	_check(missing == 0, "every resolved action reaches the despatch (%d missing)" % missing)


## The rail's own levers: the garrison's battery line and each side's chevrons
## are the rules' numbers, so the record must read them back — and a rail with no
## seed, because a lone attacker's quick battle is deterministic for its plan
## (wiki: siege-mechanics § Emplaced Artillery; combat § Initiative).
func _levers_pass() -> void:
	_say("")
	_say("--- the rail's levers ---")
	_seat(_screen._setup, "attacker", [["musketeers", 6], ["culverin", 1]])
	_seat(_screen._setup, "defender", [["pikemen", 4], ["musketeers", 2]])
	_screen._setup._fort.selected = 2
	_check(not _screen._setup.spec().has("seed"), "the rail carries no seed a lone attacker cannot feel")
	for line in BattleSimSetup.GUN_ROWS.size():
		_screen._setup._guns.selected = line
		_screen._setup._attacker_medals.value = 2
		_screen._setup._defender_medals.value = 1
		_screen._fight()
		await _idle(1)
		var spec: Dictionary = _screen._setup.spec()
		var quick: Dictionary = _screen._result["report"]["quick"]
		var want: String = FortRules.emplaced_type(spec["tech"] as Dictionary)
		_say("  %s -> %s, limits %d/%d, guns %d" % [
			String(BattleSimSetup.GUN_ROWS[line][1]), String(quick["gun_type"]),
			int(quick["limits"]["attacker"]), int(quick["limits"]["defender"]),
			int(quick["guns_start"]),
		])
		_check(
			String(quick["gun_type"]) == want,
			"the %s line is the battery the resolver spawns" % String(BattleSimSetup.GUN_ROWS[line][1])
		)
		_check(
			int(quick["limits"]["attacker"]) == ArmyModifiers.BASE_DEPLOYMENT + 2
			and int(quick["limits"]["defender"]) == ArmyModifiers.BASE_DEPLOYMENT + 1,
			"each side's chevrons move its own deployment limit"
		)
		_check(
			_screen._readout.text.contains("defender medals 1"),
			"the readout reads the levers back"
		)


## Every ground and every fort a playtester can set: each must resolve, name the
## ground it fought on, and keep its gates and battery on the record.
func _ground_matrix() -> void:
	_say("")
	_say("--- every ground, every fort ---")
	_seat(_screen._setup, "attacker", [["musketeers", 6], ["knights", 2], ["culverin", 1]])
	_seat(_screen._setup, "defender", [["pikemen", 4], ["musketeers", 3], ["culverin", 1]])
	for terrain in BattleSimSetup.TERRAIN_ROWS.size():
		for fort in BattleSimSetup.FORT_LABELS.size():
			_screen._setup._terrain.selected = terrain
			_screen._setup._fort.selected = fort
			_screen._fight()
			await _idle(1)
			if _screen._result.is_empty():
				_check(false, "ground %d, fort %d resolves" % [terrain, fort])
				continue
			var report: Dictionary = _screen._result["report"]
			var quick: Dictionary = report["quick"] as Dictionary
			var want: String = String(BattleSimSetup.TERRAIN_ROWS[terrain][0])
			_check(
				String(quick.get("terrain", "")) == want,
				"fort %d fights on the ground the rail names (%s)" % [fort, want]
			)
			_check(
				int(quick.get("guns_start", 0)) == fort,
				"a %s seats %d emplaced guns" % [BattleSimSetup.FORT_LABELS[fort], fort]
			)
			_check(
				_screen._log.text.contains("— OUTCOME —"),
				"ground %d, fort %d prints an outcome" % [terrain, fort]
			)
	_say("20 setups resolved, each naming its own ground and battery")


## The sandbox on a handset: one column, scrolling, with the rail and the
## despatches reachable instead of clipped (REQ-P1-05, REQ-P5-07).
func _handset_pass() -> void:
	_say("")
	_say("--- a handset's window ---")
	_holder = Control.new()
	_holder.size = HANDSET
	root.add_child(_holder)
	root.remove_child(_screen)
	_holder.add_child(_screen)
	await _idle(4)
	_check(_screen._stacked, "a 720x360 window stacks the sandbox into one column")
	_check(_screen._row is ScrollContainer, "a stacked sandbox scrolls")
	var scroll := _screen._row as ScrollContainer
	var content: float = scroll.get_v_scroll_bar().max_value
	var page: float = scroll.get_v_scroll_bar().page
	_say("stacked: %.0f points of content in a %.0f-point window" % [content, page])
	_check(content > page, "the stack runs longer than its window, so it must scroll")
	_check(_screen._field.size.y >= BattleSimScreen.FIELD_MIN, "the plate keeps its floor")
	_check(_screen._setup.size.y >= BattleSimScreen.RAIL_MIN, "the rail keeps its window")


# --- seating ----------------------------------------------------------------


## Fills the sandbox's rail: one [type, count] per slot, the rest at zero.
func _seat(setup: BattleSimSetup, side: String, rows: Array) -> void:
	var slots: Array = setup._attacker_slots if side == "attacker" else setup._defender_slots
	for index in slots.size():
		var row: Array = rows[index] if index < rows.size() else []
		var slot: Dictionary = slots[index]
		if row.is_empty():
			(slot["count"] as SpinBox).value = 0
			continue
		(slot["picker"] as OptionButton).selected = maxi(setup._types.find(String(row[0])), 0)
		(slot["count"] as SpinBox).value = int(row[1])


## The rail's row for a ground, so a reordered list cannot silently seat another.
func _terrain_row(terrain: String) -> int:
	for index in BattleSimSetup.TERRAIN_ROWS.size():
		if String(BattleSimSetup.TERRAIN_ROWS[index][0]) == terrain:
			return index
	return 0


func _idle(count: int) -> void:
	for index in count:
		await process_frame


func _check(ok: bool, text: String) -> void:
	if ok:
		return
	_failures.append(text)
	print("playtest: FAIL: ", text)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	_say("")
	if _failures.is_empty():
		_say("%d checks passed — the sandbox fights the army it shows, walks into its aftermath, and prints the game's sheet" % _steps.size())
	else:
		_say("%d checks FAILED: %s" % [_failures.size(), "; ".join(_failures)])
	print("\n--- playtest_battle_sim: %d steps, %d failures ---" % [_steps.size(), _failures.size()])
	quit(1 if not _failures.is_empty() else 0)
