extends GdToolsTest
## Toast plates: a despatch that changed the world is acknowledged, and a siege
## that silenced a battery carries its medallion so the loss is not mistaken for
## chatter (REQ-P5-05, DR-20261110-22).

const LINE := "France holds Burgundy — 2 of 2 emplaced guns silenced"

var _hud: GameHud = null


func before_each() -> void:
	_hud = GameHud.new()
	add_child(_hud)


func after_each() -> void:
	if is_instance_valid(_hud):
		_hud.free()
	_hud = null


func test_a_plain_toast_keeps_its_single_label() -> void:
	_hud.toast("The turn opens")
	var panel: Control = _hud._toast_box.get_child(0)
	assert_eq(panel.get_child_count(), 1)
	var label: Label = panel.get_child(0) as Label
	assert_true(label != null)
	assert_eq(label.text, "The turn opens")


func test_a_siege_toast_carries_the_silenced_battery_medallion() -> void:
	_hud.toast(LINE, "silenced_gun")
	var panel: Control = _hud._toast_box.get_child(0)
	var row: HBoxContainer = panel.get_child(0) as HBoxContainer
	assert_true(row != null, "the medallion sits in a row with its line")
	var medallion: TextureRect = row.get_child(0) as TextureRect
	assert_true(medallion != null)
	assert_true(medallion.texture != null, "the icon asset is imported")
	assert_eq(medallion.custom_minimum_size, Vector2(26.0, 26.0))
	var label: Label = row.get_child(1) as Label
	assert_true(label != null)
	assert_eq(label.text, LINE)


func test_a_hidden_hud_keeps_no_toast_plates() -> void:
	_hud.visible = false
	_hud.toast(LINE, "silenced_gun")
	assert_eq(_hud._toast_box.get_child_count(), 0)
