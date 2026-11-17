class_name BattleSimLayout
extends RefCounted
## Battle Simulator chrome: centre column, despatch panel, and stack/column
## seating for handset vs desktop. Builds Controls; never resolves a fight
## (REQ-P3-01, REQ-P1-05).


## One column on a handset, three on a desktop: panels are re-seated rather than
## rebuilt, so a resize never loses the setup or the record.
static func restack(
	margin: MarginContainer,
	old_row: Container,
	stacked: bool,
	panels: Array
) -> Container:
	var columns: BoxContainer = VBoxContainer.new() if stacked else HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	for child: Control in panels:
		child.get_parent().remove_child(child)
		columns.add_child(child)
	var host: Container = columns
	if stacked:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(columns)
		host = scroll
	margin.remove_child(old_row)
	old_row.queue_free()
	margin.add_child(host)
	return host


## The room each panel takes: a stacked column gives the rail and the despatches
## a bounded window of their own and lets the plate keep the rest.
static func apply_stack(
	setup: Control,
	field: Control,
	log_panel: Control,
	stacked: bool,
	rail_min: float,
	log_min: float,
	field_min: float
) -> void:
	setup.custom_minimum_size = Vector2(0.0 if stacked else 320.0, rail_min if stacked else 0.0)
	setup.size_flags_vertical = Control.SIZE_FILL if stacked else Control.SIZE_EXPAND_FILL
	log_panel.custom_minimum_size = Vector2(0.0 if stacked else 380.0, log_min if stacked else 0.0)
	log_panel.size_flags_vertical = Control.SIZE_FILL if stacked else Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(0, field_min if stacked else 220.0)


## Builds the centre column widgets (header, field, status, round doors).
## Returns {header, field, status, round_buttons}; caller wires pressed signals.
static func build_centre(column: VBoxContainer) -> Dictionary:
	var header: Label = UiRowBuilder.serif_wrapped("No battle yet", 15, Palette.GOLD_PALE)
	column.add_child(header)
	var field := QuickBattleField.new()
	field.custom_minimum_size = Vector2(0, 220)
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(field)
	var status: Label = UiRowBuilder.serif_wrapped(
		"Ready — set the ground, the fort and the men, then Fight.", 12, Palette.TEXT
	)
	column.add_child(status)
	var round_buttons := HFlowContainer.new()
	round_buttons.add_theme_constant_override("separation", 6)
	column.add_child(round_buttons)
	for index in QuickBattle.MAX_ROUNDS:
		var button := Button.new()
		button.text = "Round %s" % QuickBattleCopy.roman(index + 1)
		button.disabled = true
		round_buttons.add_child(button)
	var aftermath := Button.new()
	aftermath.text = "Aftermath"
	aftermath.disabled = true
	round_buttons.add_child(aftermath)
	return {
		"header": header,
		"field": field,
		"status": status,
		"round_buttons": round_buttons,
	}


## Despatches panel: title, rules readout, scrolling log. Returns
## {panel, readout, log}.
static func build_log_panel() -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.09, 0.07, 0.05, 0.97), Palette.GOLD_DIM, 1, 4, Vector4(10, 8, 10, 8))
	)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	column.add_child(UiRowBuilder.serif_wrapped("DESPATCHES", 13, Palette.GOLD))
	var readout: Label = UiRowBuilder.serif_wrapped("", 11, Palette.TEXT_DIM)
	column.add_child(readout)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var log: Label = UiRowBuilder.serif_wrapped("", 12, Palette.TEXT)
	log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(log)
	return {"panel": panel, "readout": readout, "log": log}
