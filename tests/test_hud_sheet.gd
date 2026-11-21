extends GdToolsTest
## HudSheet: one reveal law for every HUD sheet, and HudPanels.every() as the
## single list of sheets on the dock rail and on a door (REQ-P3-01,
## REQ-P1-05). Lean: no MapScreen, so the tier-1 budget holds.


class _StubSlot:
	extends HudPanelSlot

	var reveals: int = 0
	var conceals: int = 0

	func reveal(_host: Node, _dock: PanelDock) -> void:
		if open:
			return
		reveals += 1
		open = true

	func conceal(_host: Node, _dock: PanelDock) -> void:
		if not open:
			return
		conceals += 1
		open = false


func test_show_reveals_once_and_repaints_while_open() -> void:
	var slot := _StubSlot.new()
	slot.slides = false
	var painted: Array[String] = []
	HudSheet.show(null, null, slot, func() -> void: painted.append("paint"))
	HudSheet.show(null, null, slot, func() -> void: painted.append("paint"))
	assert_eq(slot.reveals, 1, "a sheet already up is not revealed again")
	assert_eq(painted.size(), 2, "every show paints the newest reading")


func test_hide_sets_aside_once() -> void:
	var slot := _StubSlot.new()
	slot.slides = false
	HudSheet.show(null, null, slot, func() -> void: pass)
	HudSheet.hide(null, null, slot)
	HudSheet.hide(null, null, slot)
	assert_eq(slot.conceals, 1, "the law hands conceal to the slot")
	assert_false(slot.open, "the sheet reads closed after one hide")


func test_show_presses_the_toggles_face_and_hide_lets_it_go() -> void:
	var slot := _StubSlot.new()
	slot.slides = false
	var toggle := CheckBox.new()
	add_child(toggle)
	HudSheet.show(null, null, slot, func() -> void: pass, toggle)
	assert_true(toggle.button_pressed, "the door reads open")
	HudSheet.hide(null, null, slot, toggle)
	assert_false(toggle.button_pressed, "the door reads closed")
	toggle.queue_free()


func test_every_lists_the_rail_and_the_ledgers() -> void:
	var panels := HudPanels.new()
	assert_eq(panels.every().size(), 0, "a bare host names no sheet")
	panels.province = _StubSlot.new()
	panels.fleet = _StubSlot.new()
	panels.civilian = _StubSlot.new()
	panels.army = _StubSlot.new()
	panels.economy = _StubSlot.new()
	panels.research = _StubSlot.new()
	panels.diplomacy = _StubSlot.new()
	assert_eq(panels.selections().size(), 4, "the dock rail keeps four dossiers")
	var all: Array[HudPanelSlot] = panels.every()
	assert_eq(all.size(), 7, "every sheet rides one list")
	for slot: HudPanelSlot in all:
		# The dock side and the lane cover read every entry: a bare null would
		# crash them, so the list never pads itself with empty slots.
		assert_not_null(slot, "every() names only real sheets")