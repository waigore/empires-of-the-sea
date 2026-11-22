extends GdToolsTest
## Land armies end-to-end through the real map screen (wiki: military-armies,
## combat): muster, dossier, detach, march, merge and capture.

const Fixture = preload("res://tests/map_fixture.gd")

## One mounted screen for the whole suite: under coverage a mount costs ~0.5 s
## and a re-seat from the pristine save ~0.15 s, so live cases share the chart
## and reset the session instead of remounting (`Fixture.suite_reset`). Pure
## ArmyFixture dossier / drill-yard cases never touch `_screen`, so they skip
## the re-seat (docs/testing.md § Speed rules).
var mounted: MapScreen = null
var pristine: Dictionary = {}
## The shared world as generated: combat tests shift ownership, so every live
## case starts from the same map instead of the previous case's aftermath.
## Non-underscore so before_all copies it onto each test instance.
var pristine_map: Array = []
## Set when this case has paid for a pristine re-seat; cleared in `before_each`.
var _chart_bound: bool = false


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)


func before_each() -> void:
	_chart_bound = false


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	pristine = {}


## Live cases reach the chart through `_screen` / `_attach()`; pure ArmyFixture
## dossier cases that never ask never pay `suite_reset`.
func _attach() -> MapScreen:
	if _chart_bound and is_instance_valid(mounted):
		return mounted
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(mounted, pristine, Fixture.world())
	_chart_bound = true
	return mounted


var _screen: MapScreen:
	get:
		return _attach()


func test_home_armies_muster_at_each_capital() -> void:
	var home: ArmyState = _player_home()
	assert_not_null(home)
	assert_true(home.is_home_army())
	assert_eq(home.province, _screen.capital_province)
	assert_eq(home.owner, MapScreen.PLAYER_FACTION)
	assert_eq(home.count(), ArmyMuster.GREAT_POWER_ROSTER.size())
	for army: ArmyState in _screen.army_layer.armies:
		if army.is_home_army():
			var province: ProvinceState = _screen.model.province_data(army.province)
			assert_true(province != null and province.capital)


func test_selecting_an_army_opens_its_dossier() -> void:
	var home: ArmyState = _player_home()
	var marker: ArmyMarker = _screen.army_layer.marker_for(home)
	assert_not_null(marker)
	# Settle the opening camera first: it zooms into the capital over several
	# frames, and a tap is resolved against the live zoom. Waiting for the
	# camera to come to rest (not a fixed frame count) keeps the suite stable
	# when workers are loaded by parallel suites.
	await _settle_camera()

	MapPlayInput.on_tapped(_screen.play, marker.position)

	assert_eq(_screen.army_layer.selected_army, home)
	assert_true(_screen.hud.panels.is_army_panel_open())
	assert_false(_screen.hud.panels.is_panel_open())


## Waits until the camera's position and zoom hold for two frames (bounded).
func _settle_camera() -> void:
	var last: Vector2 = _screen.camera.zoom
	var last_position: Vector2 = _screen.camera.position
	var stable: int = 0
	for _frame in 90:
		await get_tree().process_frame
		var still: bool = (
			_screen.camera.zoom.is_equal_approx(last)
			and _screen.camera.position.is_equal_approx(last_position)
		)
		stable = stable + 1 if still else 0
		last = _screen.camera.zoom
		last_position = _screen.camera.position
		if stable >= 2:
			return


func test_the_home_army_has_no_march_options() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var none: Array[int] = []
	assert_eq(ArmyMovement.destinations(_screen.model, home), none)
	assert_eq(_screen.overlay.move_provinces.size(), 0)


func test_detaching_a_regiment_forms_a_field_army() -> void:
	var home: ArmyState = _player_home()
	var before: int = home.count()
	_screen.army_layer.select(home)

	MapPlayArmies.on_action(_screen.play, "detach:%s" % home.regiments[0])

	var field: ArmyState = _screen.army_layer.selected_army
	assert_not_null(field)
	assert_ne(field, home)
	assert_false(field.is_home_army())
	assert_eq(field.count(), 1)
	assert_eq(home.count(), before - 1)
	assert_eq(field.province, home.province)
	assert_true(_screen.hud.panels.is_army_panel_open())


func test_a_field_army_marches_once_and_resets_next_turn() -> void:
	var field: ArmyState = _detach_one()
	var destination: int = ArmyMovement.destinations(_screen.model, field)[0]
	var tile: Vector2i = _screen.model.province_data(destination).tiles[0]

	assert_true(MapPlayArmies.try_order(_screen.play, tile))
	assert_eq(field.province, destination)
	assert_true(field.moved)

	# The moved flag clears on the army begin-turn pass; a full end_turn would
	# also run every rival court under coverage (~10 s) for the same assert
	# (docs/testing.md § Speed rules: one resolved turn / pure path first).
	ArmyMovement.begin_turn(_screen.army_layer.armies, _screen.model)

	assert_false(field.moved)


## The rival diplomacy pass mutes the HUD for its own turn, so no rival despatch
## takes the lane (`MapPlayDiplomacy.resolve_turn` sets `hud` to null and puts it
## back). The army layer re-emits its own selection when a rival absorbs a Minor,
## and that lands here — so a muted HUD must be a no-op: the crown's own pick
## stays where it was instead of being cleared by a pass it never made
## (wiki: hud-toasts § Off the lane — "a rival-only event never takes the lane").
func test_a_muted_hud_leaves_the_crown_view_alone() -> void:
	var play: PlaySession = _screen.play
	var home: ArmyState = _player_home()
	assert_not_null(home)
	var hud: GameHud = play.hud
	assert_not_null(hud)
	play.hud = null
	play.selected_province = 42
	MapPlayArmies.select(play, home)
	MapPlayArmies.show_panel(play, home)
	MapPlayArmies.hide_dossier(play)
	var picked: int = play.selected_province
	play.hud = hud
	assert_eq(picked, 42, "a muted HUD does not clear the crown's province pick")
	assert_false(hud.panels.is_army_panel_open(), "the muted pass painted no dossier")


func test_detach_all_moves_the_whole_army_in_one_order() -> void:
	var home: ArmyState = _player_home()
	var total: int = home.count()
	_screen.army_layer.select(home)

	MapPlayArmies.on_action(_screen.play, "detach_all")

	var field: ArmyState = _screen.army_layer.selected_army
	assert_not_null(field)
	assert_ne(field, home)
	assert_eq(field.count(), total)
	assert_eq(home.count(), 0)
	assert_true(_screen.army_layer.armies.has(home))
	assert_true(_screen.hud.panels.is_army_panel_open())


## A dismissal sheds force instead of feeding it forever: exactly one peasant
## returns, nothing else is refunded, and the report names the colours
## (wiki: military-armies § Dismissing regiments; DR-20261109-01).
func test_dismissing_a_regiment_returns_its_peasant_and_no_refund() -> void:
	var home: ArmyState = _player_home()
	var ledger: PlayerEconomy = _screen.play.economy.economy
	var before: int = home.count()
	var peasants: int = ledger.workers.count(WorkerPool.Tier.PEASANT)
	var purse: int = ledger.treasury
	var stock: Dictionary = ledger.stockpile.duplicate()
	var regiment: String = home.regiments[0]
	var borne: String = RegimentNames.of(home, regiment)
	_screen.army_layer.select(home)
	var plaque: int = _screen.army_layer.regiment_count_all(MapScreen.PLAYER_FACTION)

	MapPlayArmies.on_action(_screen.play, "dismiss:%s" % regiment)

	assert_eq(home.count(), before - 1, "the colours leave the standard")
	assert_false(home.regiments.has(regiment), "the instance is gone")
	assert_eq(
		ledger.workers.count(WorkerPool.Tier.PEASANT),
		peasants + 1,
		"one peasant returns to the pool"
	)
	assert_eq(ledger.treasury, purse, "no treasury is refunded")
	assert_eq(ledger.stockpile, stock, "no material is refunded")
	assert_eq(
		_screen.army_layer.regiment_count_all(MapScreen.PLAYER_FACTION),
		plaque - 1,
		"the plaque counts what is left"
	)
	assert_true(_last_toast().contains(borne), _last_toast())
	assert_true(_last_toast().contains("one peasant"), _last_toast())


## Dismiss all is one batched order, and the Home Army keeps its standard when
## it is emptied (wiki: military-armies § Dismissing regiments).
func test_dismiss_all_sheds_the_whole_army_in_one_order() -> void:
	var home: ArmyState = _player_home()
	var ledger: PlayerEconomy = _screen.play.economy.economy
	var total: int = home.count()
	var peasants: int = ledger.workers.count(WorkerPool.Tier.PEASANT)
	_screen.army_layer.select(home)

	MapPlayArmies.on_action(_screen.play, "dismiss_all")

	assert_eq(home.count(), 0, "every regiment leaves in one order")
	assert_eq(
		ledger.workers.count(WorkerPool.Tier.PEASANT),
		peasants + total,
		"one peasant per dismissed regiment"
	)
	assert_true(_screen.army_layer.armies.has(home), "the Home Army's standard stays")
	assert_true(_last_toast().contains("%d peasants" % total), _last_toast())


## An emptied field army retires at once: the state and the standard both go
## (wiki: military-armies § Dismissing regiments).
func test_dismissing_the_last_field_regiment_retires_its_standard() -> void:
	var field: ArmyState = _detach_one()
	_screen.army_layer.select(field)

	MapPlayArmies.on_action(_screen.play, "dismiss:%s" % field.regiments[0])

	assert_false(_screen.army_layer.armies.has(field), "the standard retires")
	assert_null(_screen.army_layer.marker_for(field), "its marker leaves the chart")
	assert_null(_screen.army_layer.selected_army, "nothing is selected on a retired standard")
	assert_false(_screen.hud.panels.is_army_panel_open(), "the dossier closes with it")
	assert_true(_last_toast().contains("standard retires"), _last_toast())


## An order naming colours the army does not hold is refused with the reason and
## changes nothing (REQ-P2-03, REQ-P5-05).
func test_a_dismissal_refuses_a_regiment_the_army_does_not_hold() -> void:
	var home: ArmyState = _player_home()
	var before: int = home.count()
	var ledger: PlayerEconomy = _screen.play.economy.economy
	var peasants: int = ledger.workers.count(WorkerPool.Tier.PEASANT)

	MapPlayArmyMuster.dismiss(_screen.play, home, ["no_such_regiment"])

	assert_eq(home.count(), before, "no colours leave")
	assert_eq(ledger.workers.count(WorkerPool.Tier.PEASANT), peasants, "no peasant returns")
	assert_true(_last_toast().contains("does not stand"), _last_toast())


## A batch that names one instance twice still sheds it once: each dismissed
## regiment returns exactly one peasant (wiki: military-armies § Dismissing
## regiments).
func test_a_batch_naming_one_instance_twice_returns_one_peasant() -> void:
	var home: ArmyState = _player_home()
	var ledger: PlayerEconomy = _screen.play.economy.economy
	var before: int = home.count()
	var peasants: int = ledger.workers.count(WorkerPool.Tier.PEASANT)
	var regiment: String = home.regiments[0]

	var result: Dictionary = ArmyDismiss.dismiss(ledger, home, [regiment, regiment])

	assert_eq(int(result["count"]), 1, "one instance leaves once")
	assert_eq(int(result["peasants"]), 1, "one peasant, not two")
	assert_eq(home.count(), before - 1, "only one regiment leaves the standard")
	assert_eq(ledger.workers.count(WorkerPool.Tier.PEASANT), peasants + 1, "one peasant returns")


## An embarked army that sheds its last regiment retires with its deck freed:
## no squadron carries an army nobody can land (wiki: military-armies
## § Dismissing regiments; ships-and-naval § Naval transport).
func test_dismissing_an_embarked_army_frees_its_squadron() -> void:
	var field: ArmyState = _detach_one()
	_screen.army_layer.select(field)
	MapPlayArmies.on_action(_screen.play, "embark")
	var fleet_id: int = field.embarked_fleet
	assert_true(fleet_id >= 0, "the squadron carries it")

	MapPlayArmies.on_action(_screen.play, "dismiss_all")

	assert_false(_screen.army_layer.armies.has(field), "the standard retires")
	var carrier: FleetState = _fleet_by_id(fleet_id)
	assert_not_null(carrier, "the squadron is still afloat")
	assert_eq(carrier.embarked_army, -1, "the empty deck is free again")
	assert_true(VoyageRead.is_free(carrier), "she can take a new charge")


func test_combining_armies_uses_the_home_army_as_target() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	MapPlayArmies.on_action(_screen.play, "detach:%s" % home.regiments[0])
	var first: ArmyState = _screen.army_layer.selected_army
	_screen.army_layer.select(home)
	MapPlayArmies.on_action(_screen.play, "detach:%s" % home.regiments[0])
	var second: ArmyState = _screen.army_layer.selected_army
	var total: int = home.count() + first.count() + second.count()

	_screen.army_layer.select(second)
	MapPlayArmies.on_action(_screen.play, "merge")

	assert_eq(_screen.army_layer.selected_army, home)
	assert_eq(home.count(), total)
	assert_eq(_screen.army_layer.armies_in(home.province, home.owner).size(), 1)


## Away from the seat the Home Army is not in the group, so the panel's own order
## decides: the standard the crown sees first absorbs the one it tapped, because
## the province's standards stack by army id (wiki: military-armies
## § Split and combine).
func test_a_combine_keeps_the_standard_the_panel_prints_first() -> void:
	var play: PlaySession = _screen.play
	var earlier: ArmyState = ArmyState.muster(
		4, play.player_faction, 1, false, ["pikemen"], 401
	)
	var later: ArmyState = ArmyState.muster(
		9, play.player_faction, 1, false, ["squires"], 901
	)
	_screen.army_layer.armies.clear()
	_screen.army_layer.armies.append(later)
	_screen.army_layer.armies.append(earlier)
	_screen.army_layer._rebuild_markers()

	_screen.army_layer.select(later)
	MapPlayArmies.on_action(play, "merge")

	assert_eq(
		_screen.army_layer.selected_army, earlier, "the earlier standard keeps the field"
	)
	assert_eq(earlier.count(), 2)
	assert_false(_screen.army_layer.armies.has(later))


## The train (DR-20261112-07): the dossier names the offer or its refusal, the
## register spends the materials, and a second pitch is refused in the rules'
## own words.
func test_the_dossier_pitches_a_field_hospital_train() -> void:
	var home: ArmyState = _player_home()
	var play: PlaySession = _screen.play
	var economy: PlayerEconomy = _screen.economy.economy
	_screen.army_layer.select(home)
	MapPlayArmies.on_action(play, "detach:%s" % home.regiments[0])
	var army: ArmyState = _screen.army_layer.selected_army
	assert_not_null(army)
	assert_false(army.field_hospital)

	# Without the tech the order still shows, disabled, with the reason.
	economy.tech_unlocked.erase("organised_regiments")
	var blocked: Dictionary = MapPlayArmies.hospital_order(play, army)
	assert_false(bool(blocked.get("ok", true)))
	assert_true(String(blocked.get("caption", "")).contains("Organised Regiments"))

	economy.tech_unlocked["organised_regiments"] = true
	economy.stockpile["lumber"] = 6
	economy.stockpile["fabric"] = 6
	MapPlayArmies.show_panel(play, army)
	var panel: ArmyPanel = _screen.hud.panels.army_panel
	assert_true(panel._hospital.visible)
	assert_false(panel._hospital.disabled)
	assert_true(String(panel._hospital.text).contains("2 Lumber"), panel._hospital.text)

	var lumber: int = economy.quantity("lumber")
	var fabric: int = economy.quantity("fabric")
	MapPlayArmies.on_action(play, "hospital")
	assert_true(army.field_hospital)
	assert_eq(economy.quantity("lumber"), lumber - 2)
	assert_eq(economy.quantity("fabric"), fabric - 1)
	assert_true(String(panel._strength.text).contains("field hospital"), panel._strength.text)
	# The receipt names what the stores paid, not just that the tents arrived.
	assert_true(_last_toast().contains("2 Lumber"), _last_toast())
	assert_true(_last_toast().contains("1 Fabric"), _last_toast())
	# The strength line's food is the army's own upkeep line, so it agrees with
	# the ledger's army ration, nurses included (DR-20261112-07).
	var upkeep: int = ArmyRoster.food_upkeep_of([army], army.owner)
	assert_true(String(panel._strength.text).contains("%d food" % upkeep), panel._strength.text)
	assert_false(panel._hospital.visible, "a served order is gone")

	# A second pitch is refused, and the train stays one.
	MapPlayArmyMuster.pitch_hospital(play, army)
	assert_true(army.field_hospital)
	assert_eq(economy.quantity("lumber"), lumber - 2)


## A muster is a BuildUnitOrder: the drill yard queues it and Build/work pays the
## ledger, takes the peasant and adds the regiment (wiki: military-armies
## § Recruitment; workers-and-population § Phase placement).
func test_mustering_a_regiment_is_queued_then_joins_the_home_army() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	assert_true(_screen.hud.panels.army_panel._muster_button.visible)
	var before: int = home.count()
	var treasury: int = _screen.economy.economy.treasury
	var fabric: int = _screen.economy.economy.quantity("fabric")

	MapPlayArmies.on_action(_screen.play, "recruit:peasant_levies")

	assert_eq(home.count(), before, "nothing joins at the press")
	assert_eq(_screen.economy.economy.treasury, treasury, "nothing is paid at the press")
	assert_eq(
		_screen.economy.economy.recruits.pending(RecruitQueue.KIND_REGIMENT, "peasant_levies"),
		1
	)

	MapPlayRecruits.complete(_screen.play)

	assert_eq(home.count(), before + 1)
	assert_eq(home.type_of(home.regiments[home.regiments.size() - 1]), "peasant_levies")
	assert_eq(
		_screen.economy.economy.treasury,
		treasury - RegimentCatalog.treasury_cost("peasant_levies")
	)
	assert_eq(_screen.economy.economy.quantity("fabric"), fabric - 1)


## The drill yard's one press files every ready standard, and the Build/work pass
## musters them all (REQ-P5-04; DR-20261118-07). The press stands down while its
## orders wait, so a second tap cannot double the line.
func test_the_drill_yard_files_every_ready_standard_in_one_press() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var economy: PlayerEconomy = _screen.economy.economy
	economy.treasury = 500000
	for commodity: String in ["fabric", "castIron", "bronze", "lumber", "horses"]:
		economy.stockpile[commodity] = 400
	economy.workers.add(WorkerPool.Tier.PEASANT, 12)
	var before: int = home.count()
	var ready: Array[String] = ArmyTraining.batch_types(economy)
	assert_true(ready.size() >= 2, "the yard offers more than one payable row")

	MapPlayArmies.show_panel(_screen.play, home)
	var panel: ArmyPanel = _screen.hud.panels.army_panel
	panel.set_muster_open(true)
	var press: RaiseBatchPress = panel._muster_box._batch
	assert_eq(press.text, "Muster all ready (%d)" % ready.size())

	press.pressed.emit()
	press.pressed.emit()

	assert_eq(
		economy.recruits.pending_kind(RecruitQueue.KIND_REGIMENT),
		ready.size(),
		"one order per ready row"
	)
	assert_true(_last_toast().contains("%d regiments are under orders" % ready.size()), _last_toast())
	assert_false(press.visible, "every row waits on its order, so the press stands down")

	MapPlayRecruits.complete(_screen.play)

	assert_eq(home.count(), before + ready.size(), "the whole line joins the Home Army")
	MapPlayArmies.show_panel(_screen.play, home)
	assert_true(press.visible, "a paid-off yard offers the next line")


## The drill yard names what its whole line costs before it is pressed: the walk's
## own sum and the purse it leaves, and the same sum on the confirm face and the
## receipt — a crown used to read the price of a whole line after it signed
## (REQ-P5-06, REQ-P1-07; DR-20261118-11).
func test_the_drill_yard_names_the_whole_line_before_it_is_pressed() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var economy: PlayerEconomy = _screen.economy.economy
	economy.treasury = 100000
	for commodity: String in ["fabric", "castIron", "bronze", "lumber", "horses"]:
		economy.stockpile[commodity] = 400
	economy.workers.add(WorkerPool.Tier.PEASANT, 12)
	var ready: Array[String] = ArmyTraining.batch_types(economy)
	assert_true(ready.size() >= 2, "the yard offers more than one payable row")

	MapPlayArmies.show_panel(_screen.play, home)
	var panel: ArmyPanel = _screen.hud.panels.army_panel
	panel.set_muster_open(true)
	var press: RaiseBatchPress = panel._muster_box._batch
	var plan: Dictionary = ArmyTraining.batch_plan(economy)
	assert_eq(int(plan["count"]), ready.size(), "the plan reads every ready row")

	var line: String = _sum_label(panel._muster_box)
	assert_eq(line, RaiseBatchSum.sheet_line(plan), "the sheet prints the plan")
	assert_true(line.contains(MoneyText.ducats(int(plan["ducats"]))), line)
	assert_true(line.contains("the purse keeps"), line)

	press.pressed.emit()
	press.pressed.emit()
	assert_true(
		_last_toast().contains(MoneyText.ducats(int(plan["ducats"]))),
		"the receipt names what it paid: %s" % _last_toast()
	)


## The one sum line the yard prints under its rows, "" when it prints none.
func _sum_label(box: VBoxContainer) -> String:
	for child: Node in box.get_children():
		var label := child as Label
		if label == null or not label.visible:
			continue
		if label.text.contains("the purse keeps") or label.text.contains(" wait"):
			return label.text
	return ""


## The province panel's Recruit order opens the drill yard door on the Home Army
## and musters straight from it, so both entry points share one path.
func test_the_drill_yard_door_musters_into_the_home_army() -> void:
	var home: ArmyState = _player_home()
	var before: int = home.count()
	_screen.army_layer.deselect()

	MapPlayArmies.open_muster(_screen.play)

	assert_eq(_screen.army_layer.selected_army, home)
	assert_true(_screen.hud.panels.army_panel._muster_box.visible)

	MapPlayArmyMuster.recruit(_screen.play, "peasant_levies")
	MapPlayRecruits.complete(_screen.play)

	assert_eq(home.count(), before + 1)


## The register's gate names the same refusal the Build/work pass would, so a
## crown with no Home Army or no ledger is told why its muster cannot stand
## (wiki: military-armies § Recruitment; REQ-P2-03).
func test_the_muster_gate_names_a_crown_without_a_home_army() -> void:
	var play: PlaySession = _screen.play
	var economy: PlayerEconomy = _screen.economy.economy
	var none: Array[ArmyState] = []
	assert_eq(
		ArmyTraining.muster_blocked_reason(economy, none, play.player_faction, "peasant_levies"),
		"Regiments muster only in the Home Army."
	)
	assert_eq(
		ArmyTraining.muster_blocked_reason(null, play.army_layer.armies, play.player_faction, "x"),
		"Regiments muster only in the Home Army."
	)
	assert_eq(
		ArmyTraining.muster_blocked_reason(
			economy, play.army_layer.armies, play.player_faction, "no_such_regiment"
		),
		"Unknown regiment"
	)


## A refusal leaves the register untouched and says why, for every register order.
func test_refused_register_orders_keep_the_armies() -> void:
	var home: ArmyState = _player_home()
	var before: int = home.count()
	_screen.army_layer.select(home)

	MapPlayArmyMuster.recruit(_screen.play, "no_such_regiment")
	MapPlayArmyMuster.detach(_screen.play, home, ["no_such_regiment"])
	MapPlayArmyMuster.merge(_screen.play, home)

	assert_eq(home.count(), before)
	assert_eq(_screen.army_layer.armies_in(home.province, home.owner).size(), 1)


## A blooded regiment prints its service record under its condition; a green one
## adds no line (wiki: naming § Regiment records; DR-20261111-18).
func test_roster_rows_carry_a_service_record_once_blooded() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(3, 0, 1, ["guards"], false)
	army.regiment_engagements["unit_301"] = 3
	army.regiment_wins["unit_301"] = 2

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	var entry: VBoxContainer = panel._roster.get_child(0)
	var record: Label = entry.get_child(entry.get_child_count() - 1)
	assert_eq(String(record.text), "3 engagements · 2 won")
	panel.free()


## A blooded regiment prints its service record under its condition, and its
## despatch under that once it has stood in a field; a green one adds no line
## (wiki: naming § Regiment records; DR-20261111-18, DR-20261112-10/-13-04).
func test_a_roster_row_carries_the_despatch_a_regiment_holds() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(3, 0, 1, ["guards", "guards"], false)
	army.regiment_engagements["unit_301"] = 1
	army.regiment_wins["unit_301"] = 1
	army.regiment_health["unit_301"] = int(army.condition_of("unit_301")["max"]) / 2
	RegimentDecorations.note([army] as Array[ArmyState], 1, true)

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	var cited: VBoxContainer = panel._roster.get_child(0)
	var despatch: Label = cited.get_child(cited.get_child_count() - 1)
	assert_eq(
		String(despatch.text), "Cited +5% — Province 1 won",
		"the citation leads, and names the rank it buys"
	)
	var whole: VBoxContainer = panel._roster.get_child(1)
	var bare: Label = whole.get_child(whole.get_child_count() - 1)
	assert_eq(
		String(bare.text), "History — Province 1 won",
		"a colour that did not bleed carries no decoration"
	)
	panel.free()

	var green_panel := ArmyPanel.new()
	add_child(green_panel)
	green_panel.refresh(
		model, ArmyDossierOpening.of(ArmyFixture.army(4, 0, 1, ["guards"], false), true)
	)
	var green: VBoxContainer = green_panel._roster.get_child(0)
	for child: Node in green.get_children():
		if child is Label:
			assert_false(
				String((child as Label).text).begins_with("History —"),
				"a regiment that never marched gains no despatch line"
			)
	green_panel.free()


## The dossier's one battle-plan tap is a crown-wide standing order, named so it
## is not mistaken for this army's (wiki: quick-battle § The crown's plan;
## DR-20261110-33; REQ-P5-03).
func test_the_dossier_cycles_the_crowns_battle_plan() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var panel: ArmyPanel = _screen.hud.panels.army_panel
	assert_eq(_screen.play.battle_plan, "balanced")
	assert_eq(panel._plan.text, "Crown battle plan: Balanced")

	panel._plan.pressed.emit()
	assert_eq(_screen.play.battle_plan, "aggressive")
	assert_eq(panel._plan.text, "Crown battle plan: Aggressive")

	panel._plan.pressed.emit()
	assert_eq(_screen.play.battle_plan, "defensive")
	panel._plan.pressed.emit()
	assert_eq(_screen.play.battle_plan, "balanced", "the cycle closes")


func test_the_drill_yard_stacks_below_the_roster() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var panel: ArmyPanel = _screen.hud.panels.army_panel
	assert_eq(panel._muster_box.get_parent(), panel._roster.get_parent())
	assert_true(panel._muster_box.get_parent() is VBoxContainer)


func test_the_drill_yard_is_closed_on_a_field_army() -> void:
	var field: ArmyState = _detach_one()
	assert_false(_screen.hud.panels.army_panel._muster_button.visible)
	assert_eq(field.owner, MapScreen.PLAYER_FACTION)


func test_army_rations_enter_the_consumption_projection() -> void:
	var home: ArmyState = _player_home()
	var expected: int = _screen.army_layer.food_upkeep_all(MapScreen.PLAYER_FACTION)
	assert_gt(expected, 0)
	assert_eq(_screen.economy.readings.army_food(), expected)
	var consumption: Dictionary = _screen.economy.readings.projected()["consumption"]
	assert_eq(int(consumption["army_demand"]), expected)
	assert_eq(_screen.hud.stats.army_label.text, str(_screen.army_layer.regiment_count_all(0)))


## The dossier's strength is the resolver's own aggregation, not the paper sum:
## a standard whose colours were all cited (a laurel each, +10%) reads the
## weight the battle pays, the figure the muster roll prints too (wiki: combat
## § Strength, military-armies § The muster roll; DR-20261113-04).
func test_the_dossier_strength_is_the_resolvers_own_aggregation() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var panel: ArmyPanel = _screen.hud.panels.army_panel
	var one: Array[ArmyState] = [home]
	var paper: float = home.strength()
	assert_true(String(panel._strength.text).contains("%d strength" % roundi(paper)))
	for regiment_id: String in home.regiments:
		home.regiment_history[regiment_id] = {"cited": 3, "fields": []}
	_screen.army_layer.select(home)
	var paid: float = ArmyModifiers.strength(one, 0, 1.0)
	assert_almost_eq(paid, paper * 1.10, 0.001, "a laurel on every colours")
	assert_almost_eq(ArmyForce.side_strength(one), paid, 0.001)
	assert_true(
		String(panel._strength.text).contains("%d strength" % roundi(paid)),
		panel._strength.text
	)
	assert_ne(roundi(paid), roundi(paper), "the citation names a higher figure")


func test_marching_into_an_enemy_province_captures_it_unopposed() -> void:
	var field: ArmyState = _detach_one()
	var home: ArmyState = _player_home()
	var target: int = _adjacent_enemy_province(home.province)
	assert_gt(target, -1)
	var tile: Vector2i = _screen.model.province_data(target).tiles[0]
	var owner: int = _screen.model.province_owner(target)
	# Open ground only: a wall would turn the march into a storm (#1314).
	_screen.model.province_data(target).fort_level = 0
	_screen.play.diplomacy.ensure_relation(0, owner, _screen.play.diplomacy.turn)
	DiplomacyRules.declare_war(_screen.play.diplomacy, 0, owner)

	assert_true(MapPlayArmies.try_order(_screen.play, tile))
	assert_eq(field.province, target)

	# Capture lands in the land-combat pass; skip the full end_turn rival walk
	# under coverage (docs/testing.md § Speed rules).
	MapPlayLandTurn.resolve(_screen.play)

	assert_eq(_screen.model.province_owner(target), MapScreen.PLAYER_FACTION)


## A march into another court's walled province names the wall that stands there,
## in the fort table's own figures, instead of the plain march line — and open
## ground keeps the plain line (wiki: siege-mechanics § Wall Protection;
## DR-20261120-06, REQ-P5-05).
func test_a_march_into_a_walled_province_names_the_wall() -> void:
	var field: ArmyState = _detach_one()
	var home: ArmyState = _player_home()
	var target: int = _adjacent_enemy_province(home.province)
	assert_gt(target, -1)
	var data: ProvinceState = _screen.model.province_data(target)
	data.fort_level = 2
	var owner: int = _screen.model.province_owner(target)
	_screen.play.diplomacy.ensure_relation(0, owner, _screen.play.diplomacy.turn)
	DiplomacyRules.declare_war(_screen.play.diplomacy, 0, owner)

	assert_true(MapPlayArmies.try_order(_screen.play, data.tiles[0]))
	assert_eq(field.province, target)
	assert_eq(
		_last_toast(),
		WallRead.march_line(_screen.model.province_name(target), 2),
		"the receipt names the wall it must break"
	)
	assert_true(_last_toast().contains("80 wall hp"), _last_toast())
	assert_true(_last_toast().contains("2 emplaced guns"), _last_toast())


func test_enemy_armies_are_observed_not_ordered() -> void:
	var enemy: ArmyState = _enemy_army()
	assert_not_null(enemy)
	_screen.army_layer.select(enemy)
	assert_true(_screen.hud.panels.is_army_panel_open())
	var tile: Vector2i = _screen.model.province_data(enemy.province).tiles[0]
	assert_false(MapPlayArmies.try_order(_screen.play, tile))


func test_detaching_the_last_field_regiment_retires_its_standard() -> void:
	var field: ArmyState = _detach_one()
	_screen.army_layer.select(field)
	MapPlayArmies.on_action(_screen.play, "detach:%s" % field.regiments[0])
	var created: ArmyState = _screen.army_layer.selected_army
	assert_false(_screen.army_layer.armies.has(field))
	assert_null(_screen.army_layer.marker_for(field))
	assert_not_null(created)
	assert_eq(created.count(), 1)


func test_army_dossier_can_dock_left_or_right() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.RIGHT)
	_screen.hud.panels.toggle_dock_side()
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.LEFT)
	assert_eq(_screen.hud._army_wrap.anchor_left, 0.0)
	assert_true(_screen.hud.panels.is_army_panel_open())
	# Restore the shared user://ui.cfg so parallel suites still see RIGHT.
	_screen.hud.panels.toggle_dock_side()
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.RIGHT)


## A garrison the rules reform after mutual annihilation arrives without a
## standard: the combat pass must draw one, or the court cannot see, tap or
## order the army that is holding its province (wiki: combat § Garrison
## recovery; § Multi-Attacker Chain).
func test_a_reformed_garrison_gets_a_standard_the_court_can_tap() -> void:
	var capital: int = _screen.capital_province
	var armies: Array[ArmyState] = _screen.army_layer.armies
	var recovery: Dictionary = ArmyGarrison.recover(
		armies, capital, MapScreen.PLAYER_FACTION, 5, {}
	)
	var reformed: ArmyState = armies[armies.size() - 1]
	assert_eq(int(recovery["count"]), 1)
	assert_null(
		_screen.army_layer.marker_for(reformed),
		"the rules minted it; no standard exists until the layer reconciles"
	)

	_screen.army_layer.resolve_battles(_screen.world, {"quick_battle": false})

	var marker: ArmyMarker = _screen.army_layer.marker_for(reformed)
	assert_not_null(marker, "the combat pass draws the reformed garrison's standard")
	assert_true(marker.visible, "a province the court holds keeps its garrison on the map")


## The crown's id cursors travel with the combat pass and never fall behind a
## live instance: a standard the rules minted outside them still cannot have its
## number handed out again, so the next split or muster never creates a second
## army or regiment wearing it (wiki: military-armies § Split and combine,
## § Home Army — every instance keeps its stable id).
func test_the_id_cursors_clear_every_live_instance() -> void:
	var capital: int = _screen.capital_province
	var armies: Array[ArmyState] = _screen.army_layer.armies
	ArmyGarrison.recover(armies, capital, MapScreen.PLAYER_FACTION, 5, {})
	var reformed: ArmyState = armies[armies.size() - 1]

	_screen.army_layer.resolve_battles(_screen.world, {"quick_battle": false})

	assert_true(
		_screen.army_layer.next_army > reformed.id,
		"the next split cannot mint the reformed standard's army id"
	)
	for regiment_id: String in reformed.regiments:
		assert_true(
			_screen.army_layer.next_regiment > ArmyCommand.unit_number(regiment_id),
			"the next muster cannot mint a man the garrison already fields"
		)


## A standard whose army left the field goes with it, so a wiped garrison leaves
## no ghost marker behind (wiki: combat § Outcomes).
func test_a_standard_leaves_with_the_army_it_belongs_to() -> void:
	var home: ArmyState = _player_home()
	var marker: ArmyMarker = _screen.army_layer.marker_for(home)
	assert_not_null(marker)

	_screen.army_layer.armies.erase(home)
	_screen.army_layer.resolve_battles(_screen.world, {"quick_battle": false})

	assert_null(_screen.army_layer.marker_for(home), "the fallen army's standard is retired")


## A battle the crown fights leaves a word at the rival's court: the event beat
## (wiki: dialogue-and-mood § Design intent — event: battle results;
## DR-20261111-01). Books through the same `record_land_battle` path the combat
## pass uses; seating a chart fight under coverage paid the observer step-plate
## (~5–12 s) for a beat diplomacy_rules already covers (docs/testing.md § Speed
## rules; fleet sea-fight twin).
func test_a_battle_leaves_a_word_at_the_rivals_court() -> void:
	var player: int = MapScreen.PLAYER_FACTION
	var rival: int = 2
	var state := DiplomacyState.new()
	state.ensure_relation(player, rival, 1)
	DiplomacyRules.declare_war(state, player, rival)
	assert_true(
		DialogueEvents.record_land_battle(
			state,
			{
				"province": 1,
				"attacker": player,
				"defender": rival,
				"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
			},
			player
		),
		"a verdict the crown fought is kept"
	)

	var spoken: Dictionary = DialogueEvents.for_pair(state, player, rival)
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_EVENT, "the field answers")
	assert_true(String(spoken["point"]).begins_with("event/"), "a battle beat")
	assert_eq(int(spoken["speaker"]), rival, "the rival speaks, never the crown")


func _player_home() -> ArmyState:
	for army: ArmyState in _screen.army_layer.armies:
		if army.owner == MapScreen.PLAYER_FACTION and army.is_home_army():
			return army
	return null


func _detach_one() -> ArmyState:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	MapPlayArmies.on_action(_screen.play, "detach:%s" % home.regiments[0])
	return _screen.army_layer.selected_army


## A squadron by id, in the shown region or in any stored region roster.
func _fleet_by_id(fleet_id: int) -> FleetState:
	var ships: ShipLayer = _screen.play.ship_layer
	for region: int in ships.regions.region_ids():
		var stored: Array = ships.regions.value(region, [])
		for fleet: FleetState in stored:
			if fleet != null and fleet.id == fleet_id:
				return fleet
	return null


func _enemy_army() -> ArmyState:
	for army: ArmyState in _screen.army_layer.armies:
		if army.owner != MapScreen.PLAYER_FACTION and army.count() > 0:
			return army
	return null


## Turns an adjacent province over to a rival so the capture path has no
## defender; the map's own ownership layout stays untouched otherwise.
func _adjacent_enemy_province(capital: int) -> int:
	for province_id: int in MapGeo.province_neighbors(_screen.model, capital):
		var data: ProvinceState = _screen.model.province_data(province_id)
		if data == null or data.capital:
			continue
		data.owner = 1
		return province_id
	return -1


## The line the court last raised, as the player reads it.
func _last_toast() -> String:
	var box: VBoxContainer = _screen.hud.despatches.box
	assert_gt(box.get_child_count(), 0, "a report was raised")
	var plate: Control = box.get_child(box.get_child_count() - 1) as Control
	for child: Node in plate.get_children():
		if child is Label:
			return (child as Label).text
	return ""

# --- Regiment detail in the army dossier (REQ-P1-07, REQ-P5-05) ---
const ArmyFixture = preload("res://tests/army_fixture.gd")


func test_roster_rows_carry_regiment_detail() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(3, 0, 1, ["guards", "pikemen"], false)

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	var roster: VBoxContainer = panel._roster
	assert_eq(roster.get_child_count(), 2, "one row per regiment")
	var first: VBoxContainer = roster.get_child(0)
	var name_row: HBoxContainer = first.get_child(0)
	assert_true(name_row.get_child(0) is UnitMedallion, "the type's medallion leads the row")
	assert_eq(
		(name_row.get_child(1) as Label).text,
		"%s — Guards" % RegimentNames.of(army, "unit_301"),
		"the row names the regiment, then its type (DR-20261111-18)"
	)
	var detail_row: HBoxContainer = first.get_child(1)
	var detail: Label = detail_row.get_child(0)
	assert_eq(detail.text, RegimentCatalog.detail_line("guards"))
	assert_true(detail.text.contains("FPN 12"), detail.text)
	assert_true(detail.text.contains("food"), detail.text)
	assert_eq(detail_row.get_child_count(), 2, "the dismissal sits beside the detail")
	assert_eq((detail_row.get_child(1) as Button).text, "Dismiss")
	panel.free()


func test_the_drill_yard_names_the_regiment_it_raises() -> void:
	var economy := PlayerEconomy.starting()
	var rows: Array[Dictionary] = ArmyTraining.rows(economy)
	assert_false(rows.is_empty(), "the yard offers the catalogue")
	for row: Dictionary in rows:
		var type_id: String = String(row["type_id"])
		assert_eq(
			String(row["line"]),
			RegimentCatalog.muster_line(type_id),
			"every row carries the catalogue's own line"
		)
		assert_true(
			String(row["line"]).contains(
				"%d strength" % RegimentCatalog.strength(type_id)
			),
			String(row["line"])
		)
	# The roster's line is unchanged; the yard adds the strength and nothing else.
	assert_eq(
		RegimentCatalog.detail_line("guards"),
		"Heavy infantry · FPN 12 · FPM 10 · RNG 6 · DEF 6 · MVR 4 · 3 food"
	)
	assert_eq(
		RegimentCatalog.muster_line("guards"),
		"Heavy infantry · FPN 12 · FPM 10 · RNG 6 · DEF 6 · MVR 4 · 22 strength · 3 food"
	)
	## The two published examples are pinned as literals, not composed from the
	## live catalogue: military-units § Paying the muster prints the levy's line
	## in full beside the guard's, so a changed ration ladder (`1 food` for a
	## levy, `3` for a guard) or stat has to surface here — and in the page —
	## rather than drift apart silently.
	assert_eq(
		RegimentCatalog.muster_line("peasant_levies"),
		(
			"Light infantry · FPN 0 · FPM 3 · RNG 1 · DEF 3 · MVR 3"
			+ " · 3 strength · 1 food"
		),
		"the levy's published line, figure for figure"
	)


## The drill yard's batch walks the yard's order and reserves what each order
## spends, so one press never files a standard the Build/work pass would refuse
## (REQ-P2-03, REQ-P5-04; DR-20261118-07).
func test_the_drill_yard_batch_reserves_the_ledger_each_order_spends() -> void:
	var home := ArmyFixture.army(30, 0, 0, [], true)
	var armies: Array[ArmyState] = [home]
	var types: Array[String] = ["peasant_levies", "pikemen", "arquebusiers"]

	var economy := PlayerEconomy.starting()
	var result: Dictionary = ArmyTraining.queue_all(economy, armies, 0, types)
	assert_eq(int(result["filed"]), 3, "every payable row files")
	assert_eq(String(result["refusal"]), "", "nothing is refused")
	assert_eq(
		economy.recruits.pending_kind(RecruitQueue.KIND_REGIMENT),
		3,
		"one order per row"
	)
	assert_eq(
		economy.available_peasants(),
		PlayerEconomy.START_PEASANTS - 3,
		"each standard reserves its peasant"
	)

	# Cash: the levy's price leaves the pikemen short.
	economy = PlayerEconomy.starting()
	economy.treasury = RegimentCatalog.treasury_cost("peasant_levies")
	result = ArmyTraining.queue_all(
		economy, armies, 0, ["peasant_levies", "pikemen"]
	)
	assert_eq(int(result["filed"]), 1, "only what the purse covers")
	assert_eq(String(result["refusal"]), "Insufficient treasury")
	assert_eq(economy.recruits.pending_kind(RecruitQueue.KIND_REGIMENT), 1)

	# Materials: the levy takes the last bolt of cloth.
	economy = PlayerEconomy.starting()
	economy.stockpile["fabric"] = 1
	result = ArmyTraining.queue_all(
		economy, armies, 0, ["peasant_levies", "pikemen"]
	)
	assert_eq(int(result["filed"]), 1, "only what the stores cover")
	assert_eq(String(result["refusal"]), "Insufficient materials")

	# Hands: the queue reserves the peasant, so the second standard finds none.
	economy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(1)
	result = ArmyTraining.queue_all(
		economy, armies, 0, ["peasant_levies", "pikemen"]
	)
	assert_eq(int(result["filed"]), 1, "only what the pool covers")
	assert_eq(String(result["refusal"]), "Insufficient workers")


## The yard's one press reads only rows no waiting order claims, so a second
## press never doubles a standard already under orders (DR-20261118-07).
func test_the_drill_yard_batch_skips_a_standard_already_under_orders() -> void:
	var home := ArmyFixture.army(31, 0, 0, [], true)
	var armies: Array[ArmyState] = [home]
	var economy := PlayerEconomy.starting()
	economy.queue_build(RecruitQueue.KIND_REGIMENT, "peasant_levies")

	var ready: Array[String] = ArmyTraining.batch_types(economy)

	assert_false(ready.has("peasant_levies"), "a standard under orders is not re-filed")
	assert_true(ready.has("pikemen"), "a row nothing claims still stands ready")


func test_an_enemy_dossier_keeps_the_detail_but_no_orders() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(4, 1, 2, ["knights"], false)

	panel.refresh(model, ArmyDossierOpening.of(army, false))

	var row: VBoxContainer = panel._roster.get_child(0)
	assert_eq(
		(row.get_child(0) as HBoxContainer).get_child_count(),
		2,
		"medallion and name, no detach order"
	)
	assert_true((row.get_child(1) as HBoxContainer).get_child(0).text.contains("Spear cavalry"))
	assert_eq(
		(row.get_child(1) as HBoxContainer).get_child_count(),
		1,
		"a rival's colours are never dismissed by the crown"
	)
	assert_true(String(panel._status.text).contains("Enemy colours"))
	panel.free()


## A beaten host left where it fought stands on ground it does not hold. The
## dossier must name whose ground that is, and the hint must not promise own land
## the tap list does not hold — the road home is a walk through the provinces
## beside it (wiki: military-armies § Movement and attacks).
func test_a_routed_host_reads_its_ground_and_the_walk_home() -> void:
	var model := ArmyFixture.build()
	# The far colony goes over to the rival, so province 4 — the rival province
	# at the map's edge — has no crown land beside it at all.
	model.province_data(1).owner = 1
	var bordered := ArmyFixture.army(9, 0, 2, ["guards"], false)
	var stranded := ArmyFixture.army(10, 0, 4, ["guards"], false)
	var rival_name: String = FactionCatalog.name_of(1)
	var mark: String = "'" if rival_name.ends_with("s") else "'s"

	var panel := ArmyPanel.new()
	add_child(panel)
	panel.refresh(model, ArmyDossierOpening.of(bordered, true))
	assert_eq(
		String(panel._location.text), "At Province 2 — %s%s ground" % [rival_name, mark],
		"the place line names whose ground the host stands on"
	)
	assert_eq(
		String(panel._hint.text),
		"Tap a highlighted province; off your own ground only the provinces "
		+ "beside you are open.",
		"a host off its own ground is not promised own land it cannot reach"
	)
	assert_false(ArmyMovement.stranded(model, bordered), "own land is one march away")

	panel.refresh(model, ArmyDossierOpening.of(stranded, true))
	assert_eq(
		String(panel._location.text), "At Province 4 — %s%s ground" % [rival_name, mark],
		"the place line names the ground even where no road home is open"
	)
	assert_eq(
		String(panel._hint.text),
		"No own land touches here — march through the provinces beside you, "
		+ "one march at a time, to reach home.",
		"the hint reads the page's own sentence for the walk"
	)
	assert_true(ArmyMovement.stranded(model, stranded), "no own province is one march away")
	var home: Dictionary = ArmyMovement.can_move(model, stranded, 0)
	assert_false(bool(home.get("ok", true)), "a home march is refused from here")
	assert_eq(
		String(home.get("reason", "")),
		String(panel._hint.text),
		"the refusal and the dossier's hint are the one published sentence"
	)
	assert_false(
		String(home.get("reason", "")).contains("naval transport"),
		"a land army is not told to buy a hull: %s" % home.get("reason", "")
	)
	panel.free()


## A stranded host on a chart that holds no seat of its court reads the water's
## own words: no land march from that shore reaches home, so the rule names the
## one road that does — a squadron in port — and then the harbour that squadron
## must dock at, or says the crown keeps none within a march (wiki:
## military-armies § Movement and attacks; ships-and-naval § Naval transport
## (armies); DR-20261122-07, DR-20261122-09).
func test_a_stranded_host_across_the_sea_reads_the_water() -> void:
	var model := ArmyFixture.build()
	# The crown's seat stands on the Old World chart; this chart is the New
	# World's, and the far colony goes over to the rival, so nothing of the
	# crown's touches the host's ground.
	model.region_id = FactionCatalog.NEW_WORLD
	model.province_data(0).capital = false
	model.province_data(1).owner = 1
	var host := ArmyFixture.army(11, 0, 4, ["guards"], false)
	var no_harbour: String = (
		ArmyMovement.NO_OWN_LAND_REACH_OVERSEAS + ArmyMovement.SEA_HOME_NO_HARBOUR
	)
	assert_true(ArmyMovement.seat_elsewhere(model, host), "the seat lies on another chart")
	assert_true(ArmyMovement.stranded(model, host), "no own province is one march away")
	assert_eq(
		ArmyMovement.nearest_harbour(model, host),
		ArmyMovement.NO_PROVINCE,
		"no harbour of the crown's is within a march of this ground"
	)
	assert_eq(
		ArmyMovement.walk_home_words(model, host),
		no_harbour,
		"the walk across the sea names the water, and that no quay of the crown's is near"
	)
	var refused: Dictionary = ArmyMovement.can_move(model, host, 0)
	assert_false(bool(refused.get("ok", true)), "a home march is refused from here")
	assert_eq(
		String(refused.get("reason", "")),
		no_harbour,
		"the refusal names the sea and the missing harbour, not a land road home"
	)
	var panel := ArmyPanel.new()
	add_child(panel)
	panel.refresh(model, ArmyDossierOpening.of(host, true))
	assert_eq(
		String(panel._hint.text),
		no_harbour,
		"the hint and the refusal are the one published sentence"
	)
	panel.free()
	# The same host on the seat's own chart keeps the page's land words.
	model.province_data(0).capital = true
	assert_false(ArmyMovement.seat_elsewhere(model, host), "the seat is on this chart")
	assert_eq(
		ArmyMovement.walk_home_words(model, host),
		ArmyMovement.NO_OWN_LAND_REACH,
		"the seat's own chart keeps the land road home"
	)


## A cut-off host across the sea hears the shore to march for: the nearest own
## harbour by land hops is named, a harbour under the host's own feet is pressed
## instead of marched to, and the water's words ride with the harbour counsel so
## the dossier and the refusal never speak two sentences (wiki: military-armies
## § Movement and attacks; ships-and-naval § Naval transport (armies);
## DR-20261122-09).
func test_a_stranded_host_across_the_sea_names_the_harbour_that_takes_it_home() -> void:
	var model := ArmyFixture.build()
	model.region_id = FactionCatalog.NEW_WORLD
	model.province_data(0).capital = false
	model.province_data(1).owner = 1
	var host := ArmyFixture.army(12, 0, 4, ["guards"], false)
	# The crown's own coast beside the host's ground opens the sea road home.
	model.province_data(1).owner = 0
	model.province_data(1).port_tile = Vector2i(4, 0)
	assert_eq(
		ArmyMovement.nearest_harbour(model, host),
		1,
		"the nearest own harbour is the one a land march reaches first"
	)
	assert_eq(
		ArmyMovement.walk_home_words(model, host),
		ArmyMovement.NO_OWN_LAND_REACH_OVERSEAS
		+ ArmyMovement.SEA_HOME_HARBOUR % model.province_name(1),
		"the water's words name the harbour the squadron must dock at"
	)
	# A harbour under the host's own feet is docked at, never marched to.
	var at_quay := ArmyFixture.army(13, 0, 1, ["guards"], false)
	assert_eq(ArmyMovement.nearest_harbour(model, at_quay), 1, "the host stands in it")
	assert_eq(
		ArmyMovement.walk_home_words(model, at_quay),
		ArmyMovement.NO_OWN_LAND_REACH_OVERSEAS + ArmyMovement.SEA_HOME_HARBOUR_HERE,
		"a host standing in its own harbour hears the dock, not a march"
	)
	# Without a deck room the counsel names the quay, not a promise that a hull
	# waits there: the embark gate is the squadron's own (ships-and-naval).
	assert_true(NavalMovement.has_harbour(model, 1), "the province keeps a harbour")
	# A quay across open water is never named: the sea column at x = 7 shuts the
	# far colony off from the host's ground.
	model.province_data(5).owner = 0
	model.province_data(5).port_tile = Vector2i(8, 0)
	assert_eq(
		ArmyMovement.nearest_harbour(model, host),
		1,
		"a harbour beyond open water is no march from here"
	)
	var cut_off := ArmyFixture.army(14, 0, 5, ["guards"], false)
	model.province_data(5).owner = 1
	assert_eq(
		ArmyMovement.nearest_harbour(model, cut_off),
		ArmyMovement.NO_PROVINCE,
		"an island harbour of the crown's is no march from the far shore either"
	)
	# Two own quays one march away: the lower id is the one named, so one chart
	# always reads one sentence.
	model.province_data(2).owner = 0
	model.province_data(2).port_tile = Vector2i(2, 0)
	var between := ArmyFixture.army(15, 0, 3, ["guards"], false)
	assert_eq(ArmyMovement.nearest_harbour(model, between), 1, "the tie takes the lower id")
	# A reading with no chart, no host or no ground says nothing rather than
	# guessing.
	assert_eq(ArmyMovement.nearest_harbour(null, host), ArmyMovement.NO_PROVINCE, "no chart")
	assert_eq(ArmyMovement.nearest_harbour(model, null), ArmyMovement.NO_PROVINCE, "no host")
	assert_eq(ArmyMovement.sea_home_words(model, null), "", "a host that is not there names no quay")


## A host camped on ground it does not hold keeps no interior lines: only the
## provinces beside it are open, so own land two marches away is no march while
## the own province that borders it is one. Back on its own ground the same court
## marches on interior lines again (wiki: military-armies § Movement and attacks;
## DR-20261121-15).
func test_a_host_off_its_ground_keeps_no_interior_lines() -> void:
	var model := ArmyFixture.build()
	# Province 2 is the rival's; the crown holds 0 and 6 beside it, and 1 beyond
	# them on the same landmass.
	var host := ArmyFixture.army(11, 0, 2, ["guards"], false)

	var listed: Array[int] = ArmyMovement.destinations(model, host)
	assert_true(listed.has(0), "the own province beside the host is open")
	assert_true(listed.has(6), "the own corridor beside the host is open")
	assert_true(listed.has(3), "the neutral province beside the host is open")
	assert_false(listed.has(1), "own land two marches away is not a one-march destination")

	var far: Dictionary = ArmyMovement.can_move(model, host, 1)
	assert_false(bool(far.get("ok", true)), "own land beyond the border is refused")
	assert_eq(
		String(far.get("reason", "")),
		"No interior lines run from this ground — march through the provinces "
		+ "beside you, one march at a time, to reach home.",
		"the refusal reads the page's own sentence"
	)
	var beside: Dictionary = ArmyMovement.can_move(model, host, 0)
	assert_true(bool(beside.get("ok", false)), "the own province beside it is one march")

	host.province = 0
	assert_true(
		ArmyMovement.destinations(model, host).has(1),
		"interior lines fork again once the host is home"
	)


## The hint never promises own land the tap list does not hold: a host touching
## its own land hears the walk's word too, and a host on its own ground keeps the
## ordinary sentence (wiki: military-armies § Movement and attacks).
func test_the_hint_keeps_the_tap_list_within_its_word() -> void:
	var model := ArmyFixture.build()
	var host := ArmyFixture.army(12, 0, 2, ["guards"], false)
	var panel := ArmyPanel.new()
	add_child(panel)

	panel.refresh(model, ArmyDossierOpening.of(host, true))
	assert_eq(
		String(panel._hint.text),
		"Tap a highlighted province; off your own ground only the provinces "
		+ "beside you are open."
	)

	host.province = 0
	panel.refresh(model, ArmyDossierOpening.of(host, true))
	assert_eq(
		String(panel._hint.text),
		"Tap a highlighted province; your own land is open, enemy land must border you."
	)
	panel.free()


## The dossier names the province's hospital tempo before the player commits
## (wiki: combat § Regiment condition; DR-20261111-12).
func test_roster_names_the_hospital_rest_tempo() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	model.province_data(1).hospital_level = 1
	var army := ArmyFixture.army(6, 0, 1, ["guards"], false)

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	assert_true(String(panel._strength.text).contains("rest 40%"), panel._strength.text)
	panel.free()


## A host with tents keeps the field's own 40% in its line, and a fed ward that
## out-heals them is named beside it rather than passing as the tents' tempo
## (wiki: combat § Regiment condition; DR-20261112-07).
func test_a_fed_ward_is_named_beside_the_tents() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	model.province_data(1).hospital_level = 2
	model.province_data(1).hospital_staffed = true
	var army := ArmyFixture.army(7, 0, 1, ["guards"], false)
	army.field_hospital = true

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	var line: String = String(panel._strength.text)
	assert_true(line.contains("field hospital · rest 40%"), line)
	assert_true(line.contains("ward 55%"), line)
	assert_true(
		line.contains(
			"%d food" % (
				RegimentCatalog.food_upkeep("guards") + HospitalTrain.food()
			)
		),
		"the train's staff rides in the dossier's own larder line: " + line
	)

	model.province_data(1).hospital_staffed = false

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	line = String(panel._strength.text)
	assert_true(line.contains("field hospital · rest 40%"), line)
	assert_false(line.contains("ward"), "an unfed ward has no nurses to name")
	panel.free()


## A combine can move the tents to the standard that absorbs the host, so the
## report names them: the dossier the crown was reading must not lose them in
## silence (wiki: combat § Regiment condition; DR-20261112-07).
func test_a_combine_names_the_tents_that_change_standards() -> void:
	var home: ArmyState = _player_home()
	var play: PlaySession = _screen.play
	_screen.army_layer.select(home)
	MapPlayArmies.on_action(play, "detach:%s" % home.regiments[0])
	var field: ArmyState = _screen.army_layer.selected_army
	assert_not_null(field)
	field.field_hospital = true

	_screen.army_layer.select(field)
	MapPlayArmyMuster.merge(play, field)

	assert_true(home.field_hospital, "the Home Army keeps the one train")
	assert_true(_last_toast().contains("field hospital train"), _last_toast())
	assert_true(_last_toast().contains("rides with it"), _last_toast())


## The dossier shows a regiment's own record: chevrons for experience and a
## health bar while it is still mauled (wiki: combat § Strength; DR-20261110-19).
func test_roster_shows_chevrons_and_wounds() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(5, 0, 1, ["guards"], false)
	var regiment: String = army.regiments[0]
	army.regiment_medals[regiment] = 2
	army.regiment_health[regiment] = 60

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	var row: VBoxContainer = panel._roster.get_child(0)
	assert_eq(row.get_child_count(), 3, "name row, detail, condition")
	var condition: HBoxContainer = row.get_child(2)
	assert_true(condition.get_child(0) is TextureRect, "the chevron medallion")
	assert_eq((condition.get_child(1) as Label).text, "×2")
	var bar: ProgressBar = condition.get_child(2)
	assert_almost_eq(bar.value, 0.5, 0.01, "half the pool shows half the bar")
	assert_eq((condition.get_child(3) as Label).text, "50%")
	assert_true(String(panel._strength.text).contains("2 chevrons"))
	panel.free()


## An embarked army is one draft aboard a squadron, so its dossier offers no
## detach order (wiki: military-armies § Split and combine; ships-and-naval
## § Naval transport).
func test_an_embarked_dossier_offers_no_detach_order() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(6, 0, 0, ["guards", "pikemen"], false)
	var fleet := FleetState.in_port(1, 0, 0, ["ship_1", "ship_2"])
	assert_true(bool(NavalTransport.embark(model, army, fleet)["ok"]))

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	var row: VBoxContainer = panel._roster.get_child(0)
	assert_eq(
		(row.get_child(0) as HBoxContainer).get_child_count(),
		2,
		"medallion and name, no detach order while aboard"
	)
	assert_true(String(panel._status.text).contains("Aboard the fleet"))
	panel.free()


## The dossier names the stance as the crown's, never that army's: one plan
## commands every Quick Battle the human fights (wiki: quick-battle § The
## crown's plan; DR-20261110-33).
func test_the_dossier_names_the_crowns_plan() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(8, 0, 1, ["guards"], false)

	var aggressive := ArmyDossierOpening.of(army, true)
	aggressive.plan = "aggressive"
	panel.refresh(model, aggressive)

	assert_eq(String(panel._plan.text), "Crown battle plan: Aggressive")
	assert_true(String(panel._plan.tooltip_text).contains("crown"))
	var hammer := ArmyDossierOpening.of(army, true)
	hammer.plan = "hammer"
	panel.refresh(model, hammer)
	assert_eq(String(panel._plan.text), "Crown battle plan: Balanced", "an unknown stance reads balanced")
	panel.free()


## One tap on any own army's dossier cycles the whole crown's stance, and an
## unknown value starts from balanced rather than stranding the cycle
## (wiki: quick-battle § The crown's plan).
func test_cycling_the_plan_is_crown_wide() -> void:
	var play: PlaySession = _screen.play
	var army: ArmyState = _player_home()
	play.battle_plan = "balanced"

	MapPlayArmies.cycle_plan(play, army)
	assert_eq(play.battle_plan, "aggressive")
	MapPlayArmies.cycle_plan(play, army)
	assert_eq(play.battle_plan, "defensive", "the plan lives on the crown, not the army")
	MapPlayArmies.cycle_plan(play, army)
	assert_eq(play.battle_plan, "balanced")

	play.battle_plan = "hammer"
	MapPlayArmies.cycle_plan(play, army)
	assert_eq(play.battle_plan, "aggressive", "an unknown stance cycles from balanced")


## A rival's general pool grows with its own research: the real Combat phase
## reconciles every crown before binding (wiki: military-generals § Count and
## tech-gated cap). Only the human's ledger used to sync a pool, so a rival flew
## one commander for the whole age.
func test_a_rivals_research_raises_its_generals_at_the_combat_phase() -> void:
	var play: PlaySession = _screen.play
	play.ensure_ai()
	var rival: int = 2
	var ledger: PlayerEconomy = play.ai.economy_for(rival)
	ledger.research.unlock("organised_regiments")
	assert_eq(play.army_layer.generals.count(rival), 1, "one commander before the phase")

	MapPlayLandTurn.resolve(play)

	assert_eq(play.army_layer.generals.count(rival), 2, "organised_regiments lands a second")
	assert_eq(play.army_layer.generals.medals(rival, "general_2"), 0)


## The drill yard leads each row with its regiment's own plate, so a muster
## reads like the roster above it (tools/art/unit-medallions.md).
func test_drill_yard_rows_carry_their_medallion() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(12, 0, 1, ["guards"], true)
	var muster: Array[Dictionary] = [
		{"type_id": "grenadiers", "name": "Grenadiers", "ok": true, "cost_text": "13,000 cash", "reason": ""},
	]

	var muster_opening := ArmyDossierOpening.of(army, true)
	muster_opening.muster = muster
	panel.refresh(model, muster_opening)

	var top: HBoxContainer = panel._muster_box.get_child(0).get_child(0)
	assert_true(top.get_child(0) is UnitMedallion, "the plate leads the drill-yard row")
	assert_eq((top.get_child(1) as Label).text, "Grenadiers")
	panel.free()



## The crown names its own colours: the dossier's name row writes a title the
## army carries, and no rule moves (wiki: naming § Regiment names;
## DR-20261113-03).
func test_the_crown_names_its_colours() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var regiment: String = home.regiments[0]
	var strength: float = home.strength()
	var rations: int = ArmyRoster.food_upkeep_of([home], home.owner)

	MapPlayArmies.on_action(_screen.play, "rename:%s:  Tercio   de la Mar " % regiment)

	assert_eq(
		RegimentNames.of(home, regiment), "Tercio de la Mar",
		"the typed name is tidied and kept"
	)
	assert_true(_last_toast().contains("Tercio de la Mar"), _last_toast())
	assert_eq(home.strength(), strength, "a name buys no strength")
	assert_eq(ArmyRoster.food_upkeep_of([home], home.owner), rations, "a name eats nothing")
	assert_true(_screen.hud.panels.is_army_panel_open(), "the dossier repaints with the name")
	var row: HBoxContainer = (
		_screen.hud.panels.army_panel._roster.get_child(0) as VBoxContainer
	).get_child(0) as HBoxContainer
	assert_true((row.get_child(1) as Label).text.begins_with("Tercio de la Mar —"), "the row prints it")


## A name a title cannot bear is refused with its reason, and the colours keep
## the name they had (wiki: naming § Regiment names; DR-20261113-03).
func test_a_name_the_rules_refuse_leaves_the_colours() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var first: String = home.regiments[0]
	var second: String = home.regiments[1]
	var borne: String = RegimentNames.of(home, first)

	MapPlayArmies.on_action(_screen.play, "rename:%s:   " % first)
	assert_true(_last_toast().contains("needs a name"), _last_toast())
	assert_eq(RegimentNames.of(home, first), borne, "an empty name changes nothing")

	MapPlayArmies.on_action(_screen.play, "rename:%s:%s" % [first, "A".repeat(29)])
	assert_true(_last_toast().contains("28"), _last_toast())
	assert_eq(RegimentNames.of(home, first), borne, "an over-long name changes nothing")

	MapPlayArmies.on_action(
		_screen.play, "rename:%s:%s" % [first, RegimentNames.of(home, second).to_lower()]
	)
	assert_true(_last_toast().contains("Another colour"), _last_toast())
	assert_eq(RegimentNames.of(home, first), borne, "a double name changes nothing")


## A rename rides the split and the save exactly as the christened title does,
## because it is the same store (DR-20261113-03).
func test_a_renamed_title_rides_the_split_and_the_save() -> void:
	var field: ArmyState = _detach_one()
	var regiment: String = field.regiments[0]
	assert_true(bool(RegimentRename.apply(field, regiment, "Tercio de la Mar")["ok"]))

	var saved := ArmyState.from_dict(field.to_dict())
	assert_eq(
		RegimentNames.of(saved, regiment), "Tercio de la Mar",
		"a save keeps the crown's own name"
	)

	var armies: Array[ArmyState] = [field]
	var split: Dictionary = ArmyRoster.split(armies, field, [regiment], 99)
	assert_true(bool(split["ok"]), String(split["reason"]))
	assert_eq(
		RegimentNames.of(split["army"] as ArmyState, regiment), "Tercio de la Mar",
		"a detach carries the name"
	)


## The roster the chart shows and the roster the save copies are one list: a pass
## that hands the table its own copy (the land turn's Home Army recall does) must
## not hide the crown's detach from the reading or the save
## (wiki: campaign-persistence — a save holds armies and regiments;
## military-armies § Split and combine).
func test_a_detach_reaches_the_roster_the_save_copies() -> void:
	var layer: ArmyLayer = _screen.army_layer
	var region: int = _screen.play.model.region_id
	var owner: int = _screen.play.player_faction
	var filed: Array[ArmyState] = []
	filed.assign(layer.armies)
	layer.regions.set_region(region, filed)
	var home: ArmyState = _player_home()
	var split: Dictionary = layer.split(home, [home.regiments[0]])
	assert_true(bool(split.get("ok", false)), String(split.get("reason", "")))
	var created: ArmyState = split["army"] as ArmyState
	var stored: Array[ArmyState] = []
	stored.assign(layer.regions.value(region, []))
	assert_true(stored.has(created), "the chart's roster carries the new standard")
	assert_eq(
		ArmyRoster.count_of(stored, owner), ArmyRoster.count_of(layer.armies, owner),
		"the two rosters count the same men"
	)
	var saved: Dictionary = SaveLayers.capture_armies(layer)
	var saved_ids: Array = []
	for row: Variant in (saved["armies"] as Dictionary).get(region, []):
		saved_ids.append(int((row as Dictionary).get("id", -1)))
	assert_true(saved_ids.has(created.id), "the save names the detached standard")


func test_a_retired_field_army_leaves_the_roster_the_save_copies() -> void:
	var layer: ArmyLayer = _screen.army_layer
	var region: int = _screen.play.model.region_id
	var filed: Array[ArmyState] = []
	filed.assign(layer.armies)
	layer.regions.set_region(region, filed)
	var field: ArmyState = _detach_one()
	assert_not_null(field)
	var result: Dictionary = layer.dismiss(
		field, field.regiments.duplicate(), _screen.play.economy.economy
	)
	assert_true(bool(result.get("retired", false)), "an emptied field army retires")
	var stored: Array[ArmyState] = []
	stored.assign(layer.regions.value(region, []))
	assert_false(stored.has(field), "the retired standard leaves the chart's roster")


## The name row is the crown's door: it opens on the row, commits what was
## typed and never offers itself to a rival's colours (REQ-P5-07).
func test_the_roster_offers_the_name_row_to_the_crown_only() -> void:
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(3, 0, 1, ["guards"], false)
	var panel := ArmyPanel.new()
	add_child(panel)
	var asked: Array = []
	panel.rename_pressed.connect(
		func(regiment_id: String, wanted: String) -> void:
			asked.append("%s=%s" % [regiment_id, wanted])
	)

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	var row: HBoxContainer = (panel._roster.get_child(0) as VBoxContainer).get_child(0) as HBoxContainer
	assert_eq(row.get_child_count(), 4, "medallion, name, detach, the name order")
	assert_eq((row.get_child(3) as Button).text, "Name", "the crown's door sits beside detach")
	(row.get_child(3) as Button).pressed.emit()
	var field: LineEdit = panel._roster._field
	assert_not_null(field, "the name row opens under the colours")
	assert_eq(field.text, RegimentNames.of(army, "unit_301"), "the row starts at the name borne")
	field.text = "Royal Scots"
	panel._roster.commit_rename("unit_301")
	assert_eq(asked, ["unit_301=Royal Scots"], "the typed name is handed to the rules")

	# The way out: cancel closes the row and changes nothing.
	var borne: String = RegimentNames.of(army, "unit_301")
	panel._roster.begin_rename("unit_301")
	panel._roster.cancel_rename()
	assert_null(panel._roster._field, "cancel closes the name row")
	assert_eq(RegimentNames.of(army, "unit_301"), borne, "cancel keeps the name borne")
	panel.free()

	var rival := ArmyFixture.army(4, 1, 2, ["knights"], false)
	var enemy_panel := ArmyPanel.new()
	add_child(enemy_panel)
	enemy_panel.refresh(model, ArmyDossierOpening.of(rival, false))
	var enemy_row: HBoxContainer = (
		enemy_panel._roster.get_child(0) as VBoxContainer
	).get_child(0) as HBoxContainer
	assert_eq(enemy_row.get_child_count(), 2, "a rival's colours carry no order")
	enemy_panel.free()


## The dismissal is destructive, so the row asks once: the first tap arms and
## relabels, the second files the order, and an unarmed tap files nothing
## (wiki: military-armies § Dismissing regiments; DR-20261109-01).
func test_the_roster_arms_a_dismissal_before_filing_it() -> void:
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(3, 0, 1, ["guards", "pikemen"], false)
	var panel := ArmyPanel.new()
	add_child(panel)
	var filed: Array = []
	panel.action_pressed.connect(func(action: String) -> void: filed.append(action))

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	var entry: VBoxContainer = panel._roster.get_child(0)
	var press: Button = (entry.get_child(1) as HBoxContainer).get_child(1) as Button
	assert_eq(press.text, "Dismiss", "the row offers the order at rest")
	press.pressed.emit()
	assert_eq(filed, [], "one tap files nothing")
	assert_eq(army.count(), 2, "the colours stay")
	var armed_press: Button = (
		(panel._roster.get_child(0) as VBoxContainer).get_child(1) as HBoxContainer
	).get_child(1) as Button
	assert_eq(armed_press.text, "Confirm", "the arm relabels the press")
	armed_press.pressed.emit()
	assert_eq(filed, ["dismiss:unit_301"], "the second tap files the order")
	assert_eq(army.count(), 2, "the panel only names the order, the rules file it")
	panel.free()


## The whole standard is shed in one press, armed the same way (REQ-P5-04).
func test_the_dossier_offers_dismiss_all_once() -> void:
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(3, 0, 1, ["guards", "pikemen"], false)
	var panel := ArmyPanel.new()
	add_child(panel)
	var filed: Array = []
	panel.action_pressed.connect(func(action: String) -> void: filed.append(action))

	panel.refresh(model, ArmyDossierOpening.of(army, true))

	var press: Button = panel._dismiss_all
	assert_true(press.visible, "the crown may shed its own standard")
	assert_eq(press.text, "Dismiss all regiments")
	press.pressed.emit()
	assert_eq(filed, [], "one tap files nothing")
	assert_true(press.text.contains("Confirm"), press.text)
	assert_true(press.text.contains("2"), press.text)
	press.pressed.emit()
	assert_eq(filed, ["dismiss_all"], "the second tap files the whole order")
	panel.free()


## An order with no instance id is ignored rather than renaming the wrong
## colours (DR-20261113-03).
func test_a_malformed_name_order_changes_nothing() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var borne: String = RegimentNames.of(home, home.regiments[0])

	MapPlayArmies.on_action(_screen.play, "rename:")
	MapPlayArmies.on_action(_screen.play, "rename::Foo")

	assert_eq(RegimentNames.of(home, home.regiments[0]), borne)


# --- the court's own pick (DR-20261120-10) -----------------------------------


## A pure session on the army fixture's chart: the crown's court, at war or at
## peace, with the roster handed in. No screen is mounted, so the pick's cases
## never pay a re-seat.
func _pick_play(at_war: bool) -> PlaySession:
	var model := ArmyFixture.build()
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(0, 1, 1)
	if at_war:
		state.relation(0, 1).at_war = true
	var play := PlaySession.new()
	play.player_faction = 0
	play.map_seed = 1500
	play.turn = 1
	play.model = model
	play.diplomacy = state
	play.army_layer = ArmyLayer.new()
	play.army_layer.model = model
	return play


## Puts one roster on the chart the session shows, the way the layer stores it.
func _pick_roster(play: PlaySession, armies: Array[ArmyState]) -> void:
	play.army_layer.armies.assign(armies)
	play.army_layer.regions.set_region(play.army_layer.model.region_id, play.army_layer.armies)


## At war on its own border the court takes the seat's guard into the field: the
## pick counts the standards the split's own list carries and the one it holds.
func test_the_courts_pick_takes_the_home_army_into_the_field() -> void:
	var play: PlaySession = _pick_play(true)
	var home := ArmyFixture.army(1, 0, 0, ["guards", "pikemen", "guards"], true)
	_pick_roster(play, [home] as Array[ArmyState])

	var pick: Dictionary = MapPlayArmyPick.pick(play, home)

	assert_eq(String(pick.get("kind", "")), AiMilitaryPlanner.KIND_SPLIT, "the split")
	assert_eq(int(pick.get("regiments", -1)), 2, "every standard but the guard")
	assert_eq(
		String(pick.get("line", "")),
		"the court would take the field — 2 regiments from the seat, 1 held to guard it"
	)
	assert_true(MapPlayArmyPick.line(play, home).begins_with("The court would take"), "one sentence")
	assert_eq(home.count(), 3, "a reading: the seat still holds its three")
	play.army_layer.free()


## A field army beside a hostile province is given the storm, and the words name
## the province the planner chose.
func test_the_courts_pick_storms_a_hostile_beside_the_field_army() -> void:
	var play: PlaySession = _pick_play(true)
	var home := ArmyFixture.army(1, 0, 0, ["guards"], true)
	var field := ArmyFixture.army(2, 0, 1, ["guards", "guards"])
	_pick_roster(play, [home, field] as Array[ArmyState])

	var pick: Dictionary = MapPlayArmyPick.pick(play, field)

	assert_eq(String(pick.get("kind", "")), AiMilitaryPlanner.KIND_MARCH)
	assert_eq(String(pick.get("why", "")), MapPlayArmyPick.WHY_STORM)
	assert_eq(int(pick.get("province", -1)), 4, "the hostile province beside her")
	assert_eq(
		String(pick.get("line", "")),
		"the court would march on %s to storm it" % play.model.province_name(4)
	)
	assert_eq(field.province, 1, "a reading: nothing marches")
	assert_eq(home.count(), 1, "and the seat's guard is not split")
	play.army_layer.free()


## A hostile host standing on the court's own frontier is met, not outmarched:
## the pick reads the relief the planner's own defence premium chose.
func test_the_courts_pick_marches_to_throw_out_a_host() -> void:
	var play: PlaySession = _pick_play(true)
	var home := ArmyFixture.army(1, 0, 0, ["guards"], true)
	var field := ArmyFixture.army(2, 0, 1, ["guards", "guards"])
	var raider := ArmyFixture.army(3, 1, 6, ["guards"])
	_pick_roster(play, [home, field, raider] as Array[ArmyState])

	var pick: Dictionary = MapPlayArmyPick.pick(play, field)

	assert_eq(String(pick.get("why", "")), MapPlayArmyPick.WHY_RELIEF)
	assert_eq(int(pick.get("province", -1)), 6, "the province the host stands on")
	assert_eq(
		String(pick.get("line", "")),
		"the court would march on %s to throw out the host there" % play.model.province_name(6)
	)
	play.army_layer.free()


## With nothing on reach worth storming, the court stages on its own frontier: an
## army standing off the border advances to the province that touches it.
func test_the_courts_pick_stages_on_the_frontier() -> void:
	var play: PlaySession = _pick_play(false)
	# The war is with a third court holding the far province, so the field army's
	# own neighbour (faction 1) is no target and the corridor is the frontier.
	play.diplomacy.ensure_relation(0, 2, 1)
	play.diplomacy.relation(0, 2).at_war = true
	play.model.province_data(2).owner = 2
	var home := ArmyFixture.army(1, 0, 0, ["guards"], true)
	var field := ArmyFixture.army(2, 0, 1, ["guards", "guards"])
	_pick_roster(play, [home, field] as Array[ArmyState])

	var pick: Dictionary = MapPlayArmyPick.pick(play, field)

	assert_eq(String(pick.get("kind", "")), AiMilitaryPlanner.KIND_MARCH)
	assert_eq(String(pick.get("why", "")), MapPlayArmyPick.WHY_FRONTIER)
	assert_eq(int(pick.get("province", -1)), 6, "the corridor that touches the war")
	assert_eq(
		String(pick.get("line", "")),
		"the court would advance to %s, the frontier" % play.model.province_name(6)
	)
	play.army_layer.free()


## At peace with no border to watch a field army on its own ground is given
## nothing at all. (A host standing off its own ground walks home: DR-20261121-15.)
func test_the_courts_pick_gives_a_peaceful_field_army_no_order() -> void:
	var play: PlaySession = _pick_play(false)
	var home := ArmyFixture.army(1, 0, 0, ["guards"], true)
	var field := ArmyFixture.army(2, 0, 1, ["guards"])
	_pick_roster(play, [home, field] as Array[ArmyState])

	assert_true(MapPlayArmyPick.pick(play, field).is_empty(), "no frontier, no march")
	assert_eq(MapPlayArmyPick.line(play, field), "", "and no sentence")
	play.army_layer.free()


## A worn field army away from the seat comes home to merge with the mass the
## Home Army musters (issue #974).
func test_the_courts_pick_marches_a_worn_army_home_to_merge() -> void:
	var play: PlaySession = _pick_play(true)
	var home := ArmyFixture.army(1, 0, 0, ["guards", "guards", "guards"], true)
	var field := ArmyFixture.army(2, 0, 1, ["guards", "guards"])
	_pick_roster(play, [home, field] as Array[ArmyState])

	var pick: Dictionary = MapPlayArmyPick.pick(play, field)

	assert_eq(String(pick.get("kind", "")), AiMilitaryPlanner.KIND_ROTATE)
	assert_eq(int(pick.get("province", -1)), 0, "the seat")
	assert_eq(
		String(pick.get("line", "")),
		"the court would march home to %s to merge with the Home Army"
			% play.model.province_name(0)
	)
	play.army_layer.free()


## A host standing on ground it does not hold walks the first leg home, and the
## dossier names the walk rather than a march to nowhere (wiki: military-armies
## § Movement and attacks; DR-20261121-15).
func test_the_courts_pick_walks_a_stranded_host_home() -> void:
	var play: PlaySession = _pick_play(false)
	# The provinces beside the wilderness are unclaimed too, so no own land is
	# one march away: the road home is a walk, not an interior-lines march.
	play.model.province_data(1).owner = MapModel.NO_ID
	play.model.province_data(6).owner = MapModel.NO_ID
	var home := ArmyFixture.army(1, 0, 0, ["guards"], true)
	var field := ArmyFixture.army(2, 0, 3, ["guards", "guards"])
	_pick_roster(play, [home, field] as Array[ArmyState])

	var pick: Dictionary = MapPlayArmyPick.pick(play, field)

	assert_eq(String(pick.get("kind", "")), AiMilitaryPlanner.KIND_WALK_HOME)
	assert_eq(int(pick.get("province", -1)), 6, "the first leg toward the seat")
	assert_eq(
		String(pick.get("line", "")),
		"the court would march on %s, the first leg home"
			% play.model.province_name(6)
	)
	assert_eq(
		MapPlayArmyOrdersPick.clause(play.model, field, pick),
		"the field army at %s home by way of %s"
			% [play.model.province_name(3), play.model.province_name(6)],
		"the sheet names the walk, not a gate"
	)
	assert_eq(
		MapPlayArmyOrdersPick.clause(null, field, pick), "", "no chart, no walk clause"
	)
	play.army_layer.free()


## The walk's own wording: the road home once the step lands on the court's own
## ground, and nothing for a chart or a province the court cannot read
## (DR-20261121-15).
func test_the_walk_clause_names_own_ground() -> void:
	var model: MapModel = ArmyFixture.build()
	assert_eq(
		MapPlayArmyPickWords.walk_line(model, 0, true),
		"the court would march on %s, its own ground, the road home"
			% model.province_name(0)
	)
	assert_eq(MapPlayArmyPickWords.walk_line(null, 0, false), "", "no chart, no line")
	assert_eq(MapPlayArmyPickWords.walk_line(model, -1, false), "", "no province, no line")


## A Home Army at its muster target cuts a second field force before the march
## (wiki: military-armies § Home Army — the seat's guard is a condition, not a
## lifetime lock), so the roster the pass plans over is the seat the split
## leaves: one guard. The worn army the pre-split chart would have sent home is
## really sent to storm, and the dossier names that march (DR-20261120-10).
func test_the_courts_pick_reads_the_seat_the_split_leaves() -> void:
	var play: PlaySession = _pick_play(true)
	var types: Array[String] = []
	for _index in 9:
		types.append("guards")
	var home := ArmyFixture.army(1, 0, 0, types, true)
	var field := ArmyFixture.army(2, 0, 1, ["guards", "guards"])
	_pick_roster(play, [home, field] as Array[ArmyState])

	assert_eq(
		String(MapPlayArmyPick.pick(play, home).get("kind", "")),
		AiMilitaryPlanner.KIND_SPLIT,
		"the seat takes the field"
	)
	var pick: Dictionary = MapPlayArmyPick.pick(play, field)
	assert_eq(String(pick.get("kind", "")), AiMilitaryPlanner.KIND_MARCH, "not the rotation")
	assert_eq(String(pick.get("why", "")), MapPlayArmyPick.WHY_STORM)
	assert_eq(int(pick.get("province", -1)), 4, "the storm the pass gives her")
	assert_eq(home.count(), 9, "a reading: the seat still holds its nine")

	# A hostile host on the court's own land is met, not outmarched: the same
	# seat reads the relief the pass gives her.
	var raider := ArmyFixture.army(3, 1, 6, ["guards"])
	_pick_roster(play, [home, field, raider] as Array[ArmyState])
	var relief: Dictionary = MapPlayArmyPick.pick(play, field)
	assert_eq(String(relief.get("why", "")), MapPlayArmyPick.WHY_RELIEF)
	assert_eq(int(relief.get("province", -1)), 6, "the province the host stands on")
	play.army_layer.free()


## The pick is only for a standard the court would still order: a rival's army,
## one that has marched, an embarked army and a session whose court runs no
## planner all carry none.
func test_the_courts_pick_names_no_army_the_court_would_leave_alone() -> void:
	var play: PlaySession = _pick_play(true)
	var home := ArmyFixture.army(1, 0, 0, ["guards", "guards", "guards"], true)
	var field := ArmyFixture.army(2, 0, 1, ["guards", "guards"])
	var rival := ArmyFixture.army(3, 1, 4, ["guards"])
	_pick_roster(play, [home, field, rival] as Array[ArmyState])

	assert_false(MapPlayArmyPick.pick(play, field).is_empty(), "the field army marches")
	assert_true(MapPlayArmyPick.pick(play, rival).is_empty(), "a rival answers to her own court")
	field.moved = true
	assert_true(MapPlayArmyPick.pick(play, field).is_empty(), "an army that marched is not re-ordered")
	field.moved = false
	field.embarked_fleet = 1
	assert_true(MapPlayArmyPick.pick(play, field).is_empty(), "the invasion planner steers a landing")
	field.embarked_fleet = -1
	play.ai_mode = AiControl.NOOP
	assert_true(MapPlayArmyPick.pick(play, home).is_empty(), "no planner, no advice")
	assert_eq(MapPlayArmyPick.line(play, home), "", "and no sentence")
	play.army_layer.free()


## The pick reads nothing it cannot: no session, no standard, no chart of
## relations, a campaign already decided, and a region table that stores an army
## the session draws nowhere all answer empty rather than guessing a march.
func test_the_courts_pick_reads_nothing_without_a_session_to_read() -> void:
	var play: PlaySession = _pick_play(true)
	var home := ArmyFixture.army(1, 0, 0, ["guards", "guards"], true)
	_pick_roster(play, [home] as Array[ArmyState])
	assert_true(MapPlayArmyPick.pick(null, home).is_empty(), "no session, no pick")
	assert_true(MapPlayArmyPick.pick(play, null).is_empty(), "no army, no pick")
	var bare := PlaySession.new()
	bare.player_faction = 0
	bare.model = play.model
	assert_true(MapPlayArmyPick.pick(bare, home).is_empty(), "no army layer, no pick")
	bare.army_layer = ArmyLayer.new()
	bare.army_layer.model = play.model
	bare.army_layer.armies.assign([home] as Array[ArmyState])
	assert_true(MapPlayArmyPick.pick(bare, home).is_empty(), "no diplomacy, no pick")
	play.campaign_halted = true
	assert_true(MapPlayArmyPick.pick(play, home).is_empty(), "a decided campaign orders nothing")
	play.campaign_halted = false
	# A chart the session does not draw: the world's own region answers, and the
	# roster the region table stores is the one the pass would plan over.
	var worlded := PlaySession.new()
	worlded.player_faction = 0
	worlded.diplomacy = play.diplomacy
	worlded.army_layer = ArmyLayer.new()
	worlded.army_layer.regions.set_region(
		play.model.region_id, [ArmyFixture.army(1, 0, 0, ["guards", "guards"], true)] as Array[ArmyState]
	)
	var other_chart: MapModel = ArmyFixture.build()
	worlded.world = WorldMap.new()
	worlded.world.add_region(other_chart)
	assert_false(
		MapPlayArmyPick.pick(worlded, worlded.army_layer.regions.value(0, [])[0]).is_empty(),
		"the world's own chart answers for a region off screen"
	)
	worlded.army_layer.free()
	play.army_layer.armies.clear()
	play.army_layer.regions.set_region(play.army_layer.model.region_id, [] as Array[ArmyState])
	assert_true(MapPlayArmyPick.pick(play, home).is_empty(), "an army no roster holds is not read")
	bare.army_layer.free()
	play.army_layer.free()


## Two field armies of the crown plan together, and each picks her own order: the
## plan's other rows are skipped, never handed to the wrong standard.
func test_the_courts_pick_hands_each_army_its_own_order() -> void:
	var play: PlaySession = _pick_play(true)
	var home := ArmyFixture.army(1, 0, 0, ["guards"], true)
	var first := ArmyFixture.army(2, 0, 1, ["guards", "guards"])
	var second := ArmyFixture.army(3, 0, 6, ["guards", "guards"])
	_pick_roster(play, [home, first, second] as Array[ArmyState])

	var one: Dictionary = MapPlayArmyPick.pick(play, first)
	var two: Dictionary = MapPlayArmyPick.pick(play, second)

	assert_false(one.is_empty(), "the first field army is ordered")
	assert_false(two.is_empty(), "and so is the second")
	assert_eq(int(one.get("province", -1)), 4, "the hostile province beside the first")
	assert_eq(int(two.get("province", -1)), 2, "the hostile province beside the second")
	assert_true(
		String(two.get("line", "")).contains(play.model.province_name(2)),
		"each line names its own ground: " + String(two.get("line", ""))
	)
	assert_eq(first.province, 1, "nothing marches")
	assert_eq(second.province, 6, "nothing marches")
	play.army_layer.free()


## Every wording the pick can print, and nothing at all for an order or a chart
## that names no place (REQ-P5-06).
func test_the_pick_words_name_a_place_or_say_nothing() -> void:
	var model: MapModel = ArmyFixture.build()
	assert_eq(MapPlayPickProse.sentence(""), "", "no words, no sentence")
	assert_eq(
		MapPlayPickProse.sentence("the court would advance"),
		"The court would advance.",
		"one capital and a full stop"
	)
	assert_eq(MapPlayArmyPickWords.split_line(0, 2), "", "a split that moves nothing")
	assert_eq(
		MapPlayArmyPickWords.split_line(3, 0),
		"the court would take the field — 3 regiments from the seat",
		"no guard left to name"
	)
	assert_eq(MapPlayArmyPickWords.march_line(null, 0, MapPlayArmyPick.WHY_STORM), "", "no chart")
	assert_eq(MapPlayArmyPickWords.march_line(model, -1, MapPlayArmyPick.WHY_STORM), "", "no ground")
	assert_eq(MapPlayArmyPickWords.march_line(model, 4, ""), "", "no reason, no march")
	assert_eq(MapPlayArmyPickWords.rotate_line(null, 0), "", "no chart, no road home")
	assert_eq(MapPlayArmyPickWords.rotate_line(model, -1), "", "no seat, no road home")


# --- army dossier parts (status / strength / orders; REQ-P3-01) ---------------
## Standing prose and the order block live outside ArmyPanel so the sheet only
## composes them — same shape as the fleet and civilian dossiers.


## Status and hint lines are plain words: enemy, embarked, home, marched,
## stranded walk-home, or free (wiki: military-armies § Movement and attacks).
func test_army_panel_status_words_the_standing_lines() -> void:
	var model := ArmyFixture.build()
	var home := ArmyFixture.army(1, 0, 0, ["guards"], true)
	var field := ArmyFixture.army(2, 0, 1, ["guards"], false)
	var rival := ArmyFixture.army(3, 1, 2, ["knights"], false)
	assert_eq(ArmyPanelStatus.status_text(rival, false), "Enemy colours · no orders")
	assert_eq(
		ArmyPanelStatus.hint_text(rival, false, false),
		"Observe only. Orders require your own army."
	)
	assert_eq(ArmyPanelStatus.status_text(home, true), "Home Army · never leaves the capital")
	field.moved = true
	assert_eq(ArmyPanelStatus.status_text(field, true), "Has marched this turn")
	field.moved = false
	assert_eq(ArmyPanelStatus.status_text(field, true), "1 march this turn")
	assert_eq(
		ArmyPanelStatus.hint_text(field, true, true),
		ArmyMovement.NO_OWN_LAND_REACH,
		"the stranded hint is the rule's own published sentence"
	)
	assert_true(
		ArmyPanelStatus.hint_text(field, true, false, true).contains(
			"only the provinces beside you are open"
		),
		"a host off its own ground is not promised interior lines"
	)
	assert_eq(
		ArmyPanelStatus.ground_note(model, field),
		"",
		"own ground adds nothing"
	)
	model.province_data(1).owner = 1
	var rival_name: String = FactionCatalog.name_of(1)
	var mark: String = "'" if rival_name.ends_with("s") else "'s"
	assert_eq(
		ArmyPanelStatus.ground_note(model, field),
		" — %s%s ground" % [rival_name, mark]
	)


## Strength line names count, firepower, food and the ward or tents from one
## module so the dossier never invents a second figure (REQ-P2-03).
func test_army_panel_strength_names_one_figure() -> void:
	var model := ArmyFixture.build()
	model.province_data(1).hospital_level = 1
	var army := ArmyFixture.army(6, 0, 1, ["guards"], false)
	var line: String = ArmyPanelStrength.line(model, army)
	assert_true(line.contains("regiments"), line)
	assert_true(line.contains("strength"), line)
	assert_true(line.contains("food"), line)
	assert_true(line.contains("rest 40%"), line)
	assert_eq(ArmyPanelStrength.food(army), ArmyRoster.food_upkeep_of([army], army.owner))


## Order presses and the dismiss arm live on one block; the panel only aliases
## them so existing dossier cases keep their field paths.
func test_army_panel_orders_own_the_presses() -> void:
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(8, 0, 1, ["guards", "pikemen"], false)
	var panel := ArmyPanel.new()
	add_child(panel)
	panel.refresh(model, ArmyDossierOpening.of(army, true))
	assert_not_null(panel._orders, "the sheet carries the orders block")
	assert_eq(panel._detach_all, panel._orders.detach_all, "alias matches the block")
	assert_eq(panel._dismiss_all, panel._orders.dismiss_all, "dismiss alias matches")
	assert_true(panel._detach_all.visible, "two colours may split")
	assert_true(panel._dismiss_all.visible, "the standard may be shed")
	assert_true(panel._plan.visible, "the crown's plan stands")
	panel.free()


## The dossier prints the pick under the composition, and a standard the court
## would leave alone carries no line at all.
func test_the_dossier_prints_the_courts_pick() -> void:
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(7, 0, 1, ["guards"])
	var panel := ArmyPanel.new()
	add_child(panel)

	var pick := ArmyDossierOpening.of(army, true)
	pick.pick = "The court would march on Province 4 to storm it."
	panel.refresh(model, pick)
	assert_true(panel._pick.visible, "the line stands")
	assert_eq(panel._pick.text, "The court would march on Province 4 to storm it.")

	panel.refresh(model, ArmyDossierOpening.of(army, true))
	assert_false(panel._pick.visible, "no pick, no line")
	panel.free()


# --- the drill yard's own pick (DR-20261121-03) -------------------------------


## A pure session with a ledger, so the muster policy has a purse to read: the
## crown's court, at war or at peace, on the army fixture's chart.
func _yard_play(at_war: bool) -> PlaySession:
	var play: PlaySession = _pick_play(at_war)
	var controller := EconomyController.new()
	controller.economy = PlayerEconomy.starting()
	play.economy = controller
	return play


## Under its target with a full purse the yard names the line the published muster
## would raise — its own name and the price its row prints — and raises nothing.
func test_the_drill_yard_names_the_line_the_court_would_muster() -> void:
	var play: PlaySession = _yard_play(false)
	var home := ArmyFixture.army(1, 0, 0, ["guards", "pikemen"], true)
	_pick_roster(play, [home] as Array[ArmyState])

	var pick: Dictionary = MapPlayMusterPick.pick(play, home)

	assert_eq(String(pick.get("kind", "")), MapPlayMusterPick.KIND_MUSTER, "a regiment is due")
	var type_id: String = String(pick.get("type", ""))
	assert_false(type_id.is_empty(), "the yard names its line")
	assert_eq(int(pick.get("own", -1)), 2, "the line it holds")
	assert_true(int(pick.get("target", 0)) > 2, "and the line it arms for")
	assert_eq(
		String(pick.get("line", "")),
		"the court would muster %s — %s" % [
			RegimentCatalog.display_name(type_id), RegimentEconomy.cost_text(type_id)
		],
		"the line, priced as its own row prints it"
	)
	assert_true(
		MapPlayMusterPick.line(play, home).begins_with("The court would muster "),
		"one sentence"
	)
	assert_eq(home.count(), 2, "a reading: the seat still holds its two")
	assert_eq(play.economy.economy.treasury, 20000, "and the purse is unspent")
	play.economy.free()
	play.army_layer.free()


## At its target strength the yard names the line it holds against the line it
## arms for, and no regiment is advised.
func test_the_drill_yard_reads_the_target_it_stands_at() -> void:
	var play: PlaySession = _yard_play(false)
	var types: Array[String] = []
	for _index in 6:
		types.append("guards")
	var home := ArmyFixture.army(1, 0, 0, types, true)
	_pick_roster(play, [home] as Array[ArmyState])

	var pick: Dictionary = MapPlayMusterPick.pick(play, home)

	assert_eq(String(pick.get("kind", "")), MapPlayMusterPick.KIND_TARGET, "the target, not a muster")
	assert_eq(
		String(pick.get("line", "")),
		"the court stands at its muster target — 5 of 5 regiments",
		"the line it holds, clamped to the line it arms for"
	)
	play.economy.free()
	play.army_layer.free()


## An empty purse names the pattern the yard means to raise and the purse it is
## filling, so the shortfall is a figure and never a silence (REQ-P5-05).
func test_the_drill_yard_names_the_purse_it_is_saving() -> void:
	var play: PlaySession = _yard_play(false)
	var home := ArmyFixture.army(1, 0, 0, ["guards", "pikemen"], true)
	_pick_roster(play, [home] as Array[ArmyState])
	play.economy.economy.treasury = 0

	var pick: Dictionary = MapPlayMusterPick.pick(play, home)

	assert_eq(String(pick.get("kind", "")), MapPlayMusterPick.KIND_SAVING, "saving, not mustering")
	assert_eq(String(pick.get("why", "")), MapPlayMusterPick.WHY_PURSE)
	var type_id: String = String(pick.get("type", ""))
	assert_eq(
		String(pick.get("line", "")),
		"the court is saving for %s — the purse holds 0 ducats of %s" % [
			RegimentCatalog.display_name(type_id),
			MoneyText.ducats(RegimentCatalog.treasury_cost(type_id))
		]
	)
	play.economy.free()
	play.army_layer.free()


## A full purse and empty stores name the materials the muster row would refuse
## it for, in the catalogue's own commodity names.
func test_the_drill_yard_names_the_stores_it_lacks() -> void:
	var play: PlaySession = _yard_play(false)
	var home := ArmyFixture.army(1, 0, 0, ["guards", "pikemen"], true)
	_pick_roster(play, [home] as Array[ArmyState])
	var economy: PlayerEconomy = play.economy.economy
	economy.take("fabric", economy.quantity("fabric"))
	economy.take("castIron", economy.quantity("castIron"))

	var pick: Dictionary = MapPlayMusterPick.pick(play, home)

	assert_eq(String(pick.get("kind", "")), MapPlayMusterPick.KIND_SAVING)
	assert_eq(String(pick.get("why", "")), MapPlayMusterPick.WHY_STORES)
	var line: String = String(pick.get("line", ""))
	assert_true(line.contains("it lacks "), "the row it is short of: " + line)
	assert_true(line.contains("1 Fabric"), "the cloth the muster row takes: " + line)
	assert_true(line.contains("2 Cast Iron"), "and the iron: " + line)
	play.economy.free()
	play.army_layer.free()


## No spare hand and no regiment due: the planner's own labour gate is worded on
## the yard, so a court that can arm nobody is told why.
func test_the_drill_yard_names_the_hand_it_cannot_spare() -> void:
	var play: PlaySession = _yard_play(false)
	var home := ArmyFixture.army(1, 0, 0, ["guards", "pikemen"], true)
	_pick_roster(play, [home] as Array[ArmyState])
	play.economy.economy.workers.counts = [0, 0, 0, 0]

	var pick: Dictionary = MapPlayMusterPick.pick(play, home)

	assert_eq(String(pick.get("kind", "")), MapPlayMusterPick.KIND_GATE, "a gate, not a muster")
	assert_eq(
		String(pick.get("line", "")),
		"the court would muster nothing — its fields cannot spare another hand"
	)
	play.economy.free()
	play.army_layer.free()


## The yard is the Home Army's own, and a crown's: a rival's seat, a field army,
## a session that runs no planner and one with no ledger all carry no advice.
func test_the_drill_yard_reads_no_line_it_cannot_muster() -> void:
	var play: PlaySession = _yard_play(false)
	var home := ArmyFixture.army(1, 0, 0, ["guards", "pikemen"], true)
	var field := ArmyFixture.army(2, 0, 1, ["guards"])
	var rival := ArmyFixture.army(3, 1, 4, ["guards"], true)
	_pick_roster(play, [home, field, rival] as Array[ArmyState])

	assert_false(MapPlayMusterPick.pick(play, home).is_empty(), "the crown's yard answers")
	assert_true(MapPlayMusterPick.pick(play, field).is_empty(), "a field army musters nowhere")
	assert_true(MapPlayMusterPick.pick(play, rival).is_empty(), "a rival answers to her own court")
	assert_true(MapPlayMusterPick.pick(null, home).is_empty(), "no session, no pick")
	assert_true(MapPlayMusterPick.pick(play, null).is_empty(), "no army, no pick")
	var config: Variant = AiBind.config(AiControl.FULL, 0, 1500, play.ensure_ai().profiles)
	assert_true(
		MapPlayMusterPick.counsel(play, 0, config, AiControl.KIND_SUBJECT, null).is_empty(),
		"no ledger, no counsel"
	)
	assert_true(
		MapPlayArmyMusterAi.plan(play, 0, config, AiControl.KIND_SUBJECT, null).is_empty(),
		"and no plan to read"
	)
	play.ai_mode = AiControl.NOOP
	assert_true(MapPlayMusterPick.pick(play, home).is_empty(), "no planner, no advice")
	play.ai_mode = AiControl.FULL
	play.economy.economy = null
	assert_true(MapPlayMusterPick.pick(play, home).is_empty(), "no ledger, no advice")
	play.economy.free()
	play.army_layer.free()


## The yard prints the pick above its rows while there is one, marks the pattern
## it names, and keeps its published shape when the court would raise nothing
## (REQ-P5-06, DR-20261122-12).
func test_the_drill_yard_block_prints_the_pick_and_orders_nothing() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var rows: Array[Dictionary] = ArmyTraining.rows(economy)
	var block := ArmyMusterBlock.new()
	add_child(block)

	var pick: Dictionary = {
		"kind": MapPlayMusterPick.KIND_MUSTER,
		"type": "guards",
		"line": "the court would muster Guards — 2,000 ducats · 1 Fabric",
	}
	block.fill(rows, pick)
	assert_eq(
		block.pick_line(),
		"The court would muster Guards — 2,000 ducats · 1 Fabric.",
		"the line is the pick's own sentence"
	)
	assert_eq(block.get_child(0), block._pick_line, "the pick stands above the rows")
	assert_eq(block.mark_type(), "guards", "the mark is the pick's own pattern")
	assert_eq(
		_yard_row_name(block, rows, "guards"),
		"%s Guards" % ArmyMusterBlock.COURT_MARK,
		"the pattern the line names wears the mark"
	)
	assert_eq(
		_yard_row_name(block, rows, "peasant_levies"), "Peasant Levies",
		"a pattern the line leaves out keeps its plain name"
	)

	block.fill(rows, {})
	assert_eq(block.pick_line(), "", "no pick, no line")
	assert_eq(block.mark_type(), "", "no pick, no mark")
	assert_ne(block.get_child(0), block._pick_line, "and the yard keeps its published top")
	assert_eq(
		_yard_row_name(block, rows, "guards"), "Guards", "and no row wears the mark"
	)

	assert_eq(economy.treasury, 20000, "a reading: the yard spends nothing")
	block.free()


## One regiment row's name label, by the table row that type stands on.
func _yard_row_name(
	block: ArmyMusterBlock, rows: Array[Dictionary], type_id: String
) -> String:
	var wanted: int = -1
	for index: int in rows.size():
		if String(rows[index].get("type_id", "")) == type_id:
			wanted = index
			break
	if wanted < 0:
		return ""
	var seen: int = 0
	for child: Node in block.get_children():
		if not (child is VBoxContainer) or child.is_queued_for_deletion():
			continue
		if seen == wanted:
			var top := (child as VBoxContainer).get_child(0) as HBoxContainer
			return (top.get_child(1) as Label).text
		seen += 1
	return ""


## Every wording the drill yard can print, and nothing for a case that names no
## gate (REQ-P5-06).
func test_the_muster_words_name_a_line_or_say_nothing() -> void:
	assert_eq(MapPlayPickProse.sentence(""), "", "no words, no sentence")
	assert_eq(
		MapPlayPickProse.sentence("the court would muster Guards"),
		"The court would muster Guards.",
		"one capital and a full stop"
	)
	assert_eq(MapPlayMusterPickWords.target_line(0, 0), "", "no target, no line")
	assert_eq(
		MapPlayMusterPickWords.target_line(9, 5),
		"the court stands at its muster target — 5 of 5 regiments",
		"a line past its target reads at its target"
	)
	assert_eq(MapPlayMusterPickWords.stores_line("guards", {}), "", "nothing missing, no line")
	assert_eq(MapPlayMusterPickWords.gate_line(""), "", "no gate, no line")
	for reason: String in [
		AiArmyReinforce.REASON_LABOUR,
		AiArmyReinforce.REASON_STARVING,
		AiArmyReinforce.REASON_HARVEST,
		AiArmyReinforce.REASON_HULL,
	]:
		assert_true(
			MapPlayMusterPickWords.gate_line(reason).begins_with("the court would muster nothing"),
			"every gate is worded: " + reason
		)
	assert_eq(
		MapPlayMusterPickWords.muster_line("peasant_levies"),
		"the court would muster Peasant Levies — %s" % (
			RegimentEconomy.cost_text("peasant_levies")
		),
		"the catalogue's name and the row's own price"
	)
	assert_eq(
		MapPlayMusterPickWords.purse_line("peasant_levies", 2000, 350),
		"the court is saving for Peasant Levies — the purse holds 350 ducats of 2,000 ducats"
	)
	assert_eq(
		MapPlayMusterPickWords.stores_line("peasant_levies", {"fabric": 2}),
		"the court is saving for Peasant Levies — it lacks 2 Fabric"
	)
