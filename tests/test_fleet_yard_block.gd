extends GdToolsTest
## FleetYardBlock: the dossier's shipyard drawer on its own — the launch rows,
## the toggle, and the break-up arm that asks once (DR-20261109-01). The dossier
## keeps the header and the standing lines, so this block is where the yard can
## be read without a map screen (REQ-P3-01).


func _rows() -> Array[Dictionary]:
	return [
		{
			"type_id": "carrack",
			"name": "Carrack",
			"cost_text": "8000",
			"ok": true,
			"reason": "",
		},
		{
			"type_id": "frigate",
			"name": "Frigate",
			"cost_text": "",
			"ok": false,
			"reason": "no peasants",
		},
	]


func _buttons(block: FleetYardBlock, prefix: String) -> Array[String]:
	var out: Array[String] = []
	for node: Node in block.find_children("*", "Button", true, false):
		var text: String = (node as Button).text
		if text.begins_with(prefix):
			out.append(text)
	return out


func test_the_slip_lists_launches_and_opens_at_once() -> void:
	var block := FleetYardBlock.new()
	add_child(block)

	block.show_slip(_rows(), true)

	assert_true(block._button.visible, "a player with rows gets the yard")
	assert_true(block._open, "the capital slip opens the drawer")
	assert_eq(block._button.text, "Close shipyard")
	assert_eq(_buttons(block, "Launch"), ["Launch", "Launch"])
	block.free()


func test_a_foreign_yard_shows_nothing() -> void:
	var block := FleetYardBlock.new()
	add_child(block)

	block.show_slip(_rows(), false)

	assert_false(block._button.visible, "no orders for another crown")
	assert_false(block._scroll.visible)
	block.free()


func test_a_join_hides_the_yard_and_keeps_the_rows() -> void:
	var block := FleetYardBlock.new()
	add_child(block)
	var fleet := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	block.show_rows(fleet, _rows(), true, true)
	assert_true(block._open, "the fleet opens on the yard")
	block.set_offer_join(true)

	assert_false(block._button.visible, "the join takes the yard's place")
	assert_false(block._scroll.visible, "a hidden drawer takes no height")
	assert_eq(block._rows.size(), 2, "the rows stay for when the join is passed")
	block.free()


func test_a_scrap_asks_once_then_emits() -> void:
	var block := FleetYardBlock.new()
	add_child(block)
	var fleet := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	var emitted: Array[String] = []
	block.action_pressed.connect(func(action: String) -> void: emitted.append(action))
	block.show_rows(fleet, _rows(), true, true)

	block.on_scrap_pressed("ship_1")

	assert_eq(block._armed_hull, "ship_1", "the first tap arms")
	assert_eq(emitted, [] as Array[String], "arming sends nothing")

	block.on_scrap_pressed("ship_1")

	assert_eq(emitted, ["yard:scrap:ship_1"])
	assert_eq(block._armed_hull, "", "a confirmed scrap clears the arm")
	block.free()
