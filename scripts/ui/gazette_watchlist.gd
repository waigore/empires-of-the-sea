class_name GazetteWatchlist
extends VBoxContainer
## The Gazette's watchlist editor (wiki: the-gazette § Courts of interest;
## DR-20261110-14). Every court the crown has met may be followed; a removal
## sticks even when a new treaty binds the court again. Presentation only — it
## edits [GazetteState] and reports the change, so no rule is decided here
## (REQ-P2-03).

signal watch_changed(faction: int)

const INK_SOFT: Color = Color(0.34, 0.26, 0.16)


func _init() -> void:
	add_theme_constant_override("separation", 4)


## Rebuilds the rows for `state`'s list, as the crown sees the world.
func fill(state: GazetteState, diplomacy: DiplomacyState, viewer: int) -> void:
	_clear()
	add_child(
		_label(
			"Every court your crown has met may be followed. Struck-off courts stay "
			+ "struck off, even if a new treaty binds them.",
			13
		)
	)
	var followed: int = 0
	for faction: int in _known_courts(state, diplomacy, viewer):
		var row := CheckBox.new()
		row.text = "%s  ·  %s" % [
			FactionCatalog.name_of(faction),
			FactionCatalog.type_label(FactionCatalog.type_of(faction)),
		]
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color", Palette.INK)
		row.button_pressed = state != null and state.is_watched(faction)
		if row.button_pressed:
			followed += 1
		row.toggled.connect(_on_toggled.bind(state, faction))
		add_child(row)
	if followed == 0:
		add_child(_label("No court is followed — the sheet will be quiet.", 13))


func _on_toggled(on: bool, state: GazetteState, faction: int) -> void:
	if state == null:
		return
	state.set_watched(faction, on)
	watch_changed.emit(faction)


## Every faction this crown has met, plus any it already follows.
static func _known_courts(state: GazetteState, diplomacy: DiplomacyState, viewer: int) -> Array[int]:
	var ids: Array[int] = []
	if state != null:
		ids.append_array(state.watched)
	if diplomacy != null:
		for record: DiplomacyRelation in diplomacy.relations.values():
			if record == null or not (record.a == viewer or record.b == viewer):
				continue
			var other: int = record.other(viewer)
			if other >= 0 and not ids.has(other):
				ids.append(other)
	ids.sort()
	return ids


func _label(text: String, pixels: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UiTheme.serif())
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", INK_SOFT)
	return label


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
