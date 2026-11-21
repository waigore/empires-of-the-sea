extends GdToolsTest
## PlayScreen: the one way a MapPlay* helper speaks to the screen (REQ-P3-02).
##
## The bridge keeps the host in one place, so a helper never grows a node path
## to the chart. These cases prove the airings reach the host that owns them,
## that a host missing a signal or a method stays silent instead of failing, and
## that a headless session (no host bound) runs the same paths inert.

## A screen double with every signal and door MapScreen offers.
class FakeScreen extends Node:
	signal province_selected(province_id: int)
	signal selection_cleared
	signal coast_charted(province_id: int)
	signal battle_resolved(battles: Array[Dictionary])
	signal raid_resolved(raids: Array[Dictionary])
	signal turn_ended(turn: int)
	signal victory_declared(victory: VictoryState)
	signal defeat_declared(defeat: DefeatState)

	var repaints: int = 0
	var regions: Array[int] = []


	func refresh_political_map() -> void:
		repaints += 1


	func load_region(index: int) -> void:
		regions.append(index)


## A bare Node: none of the screen's signals or doors.
class PlainScreen extends Node:
	pass


func _bridge(host: Node) -> PlayScreen:
	var screen := PlayScreen.new()
	screen.host = host
	return screen


## A headless run binds no host: every airing is inert and the viewport unknown.
func test_an_unbound_screen_stays_silent() -> void:
	var screen := PlayScreen.new()

	assert_eq(screen.viewport(), null, "no host reads no viewport")
	screen.emit_province_selected(3)
	screen.emit_selection_cleared()
	screen.emit_coast_charted(4)
	screen.emit_battle_resolved([] as Array[Dictionary])
	screen.emit_raid_resolved([] as Array[Dictionary])
	screen.emit_turn_ended(9)
	screen.emit_campaign_end(VictoryState.new())
	screen.emit_campaign_end(VictoryState.new(), DefeatState.new())
	screen.refresh_map_views()
	screen.switch_region(1)

	assert_eq(screen.host, null, "an inert bridge stays unbound")


func test_a_bound_screen_hears_the_courts_airings() -> void:
	var host := FakeScreen.new()
	add_child(host)
	var screen := _bridge(host)
	var heard: Array = []
	host.province_selected.connect(
		func(province_id: int) -> void: heard.append(["province", province_id])
	)
	host.selection_cleared.connect(func() -> void: heard.append("cleared"))
	host.coast_charted.connect(
		func(province_id: int) -> void: heard.append(["coast", province_id])
	)
	host.turn_ended.connect(func(turn: int) -> void: heard.append(["turn", turn]))
	host.battle_resolved.connect(
		func(battles: Array[Dictionary]) -> void: heard.append(["battle", battles.size()])
	)
	host.raid_resolved.connect(
		func(raids: Array[Dictionary]) -> void: heard.append(["raid", raids.size()])
	)

	screen.emit_province_selected(3)
	screen.emit_selection_cleared()
	screen.emit_coast_charted(4)
	screen.emit_turn_ended(9)
	screen.emit_battle_resolved([] as Array[Dictionary])
	screen.emit_raid_resolved([] as Array[Dictionary])

	assert_eq(
		heard,
		[["province", 3], "cleared", ["coast", 4], ["turn", 9], ["battle", 0], ["raid", 0]],
		"each airing reaches the screen's own signal"
	)
	assert_true(screen.viewport() != null, "a mounted host reads its viewport")
	host.free()


## A land fight and a sea fight both air on the same signal: the host answers
## the plate, not the kind (wiki: dialogue-and-mood § Design intent).
func test_battle_airings_keep_every_record() -> void:
	var host := FakeScreen.new()
	add_child(host)
	var screen := _bridge(host)
	var landed: Array = []
	host.battle_resolved.connect(
		func(battles: Array[Dictionary]) -> void: landed.append(battles)
	)
	var battles: Array[Dictionary] = [
		{"province": 2, "attacker": 0, "defender": 1},
		{"zone": 5, "attacker": 0, "defender": 1},
	] as Array[Dictionary]

	screen.emit_battle_resolved(battles)

	assert_eq(landed.size(), 1, "one resolved turn airs once")
	assert_eq((landed[0] as Array).size(), 2, "both fights ride the airing")
	host.free()


## The crown's fall outranks a victory in the same moment, so the screen hears
## one closing, never two (wiki: victory § Great Power defeat).
func test_a_fall_closes_the_screen_before_the_victory() -> void:
	var host := FakeScreen.new()
	add_child(host)
	var screen := _bridge(host)
	var heard: Array = []
	host.victory_declared.connect(
		func(victory: VictoryState) -> void: heard.append(["victory", victory])
	)
	host.defeat_declared.connect(
		func(defeat: DefeatState) -> void: heard.append(["defeat", defeat])
	)
	var victory := VictoryState.new()
	var defeat := DefeatState.new()

	screen.emit_campaign_end(victory, defeat)
	assert_eq(heard.size(), 1, "one closing airs")
	assert_eq(heard[0][0], "defeat", "the crown's fall is the closing")

	heard.clear()
	screen.emit_campaign_end(victory)
	assert_eq(heard, [["victory", victory]], "a victory alone airs as a victory")

	heard.clear()
	screen.emit_campaign_end()
	assert_eq(heard, [], "no closing airs nothing")
	host.free()


## A host that never declared the raid signal, or the redraw and region doors,
## stays silent instead of raising: the harness screens are partial.
func test_a_partial_screen_stays_silent() -> void:
	var host := PlainScreen.new()
	add_child(host)
	var screen := _bridge(host)

	screen.emit_raid_resolved([] as Array[Dictionary])
	screen.refresh_map_views()
	screen.switch_region(2)

	assert_true(screen.viewport() != null, "the viewport still answers")
	host.free()


func test_the_map_asks_the_screen_to_redraw_or_swap() -> void:
	var host := FakeScreen.new()
	add_child(host)
	var screen := _bridge(host)

	screen.refresh_map_views()
	screen.switch_region(0)
	screen.switch_region(2)

	assert_eq(host.repaints, 1, "a political change asks one repaint")
	assert_eq(host.regions, [0, 2], "a crossing swaps to the named region")
	host.free()


## The session owns the bridge: binding a host wires it, and a resolved battle
## books the courts then airs on that screen (PlaySession keeps the booking).
func test_the_session_airs_a_battle_through_its_bridge() -> void:
	var play := PlaySession.new()
	assert_true(play.screen != null, "a fresh session carries its screen bridge")
	if play.screen == null:
		return
	var host := FakeScreen.new()
	add_child(host)
	var aired: Array = []
	host.battle_resolved.connect(
		func(battles: Array[Dictionary]) -> void: aired.append(battles.size())
	)

	play.bind_host(host)
	play.emit_battle_resolved([{"province": 1, "attacker": 0, "defender": 1}] as Array[Dictionary])

	assert_eq(play.screen.host, host, "the bound host is the bridge's own")
	assert_eq(aired, [1], "the bridge airs the fight the session booked")
	host.free()
