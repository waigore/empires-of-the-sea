class_name NavalPlate
extends BattlePlateFrame
## The sea's despatch: a painted stretch of water, both colours' hulls standing
## on it as their own medallions, and the engagement told in four beats — the
## meeting, the maths, the losses, what the sea decided (wiki: ships-and-naval
## § Naval Combat Resolution). Presentation only: every number and name is read
## from the resolver's record through [NavalDispatch] (REQ-P2-03). The plate
## furniture is [BattlePlateFrame]'s; skippable on one tap so the report never
## holds the court (REQ-P5-06).

const BEAT_SECONDS: float = 0.95
const SEA_ART: String = "res://assets/art/battle/sea_open.jpg"
const MEDALLION_MIN: float = 22.0
const MEDALLION_MAX: float = 36.0

var zone_name: String = ""

var _beats_shown: int = 0
## The sea band's two lines of hulls, attacker then defender (tests read them).
var _rows: Array[HBoxContainer] = []


## Opens the plate on one engagement, as the land plate opens on its battle.
func show_engagement(p_battle: Dictionary, p_zone: String, p_names: Array) -> void:
	zone_name = p_zone
	_reveal(p_battle, p_names)


# --- frame hooks -------------------------------------------------------------


func _look() -> Dictionary:
	return {
		"title": "A DESPATCH FROM THE SEA",
		"title_pixels": 22,
		"headline_pixels": 14,
		"wrap_headline": true,
		"skip_tip": "Tell the whole despatch at once",
		"panel_fill": Color(0.08, 0.08, 0.07, 0.97),
		"name_width": 140.0,
		"wrap_names": true,
		"outcome_pixels": 20,
	}


## The painted water with one line per colour standing on the band below the
## painting's horizon; each line is its own name followed by a medallion per
## type and the number that flew (REQ-P1-08).
func _build_body(column: VBoxContainer) -> void:
	var sea := Control.new()
	sea.custom_minimum_size = Vector2(0, 132)
	sea.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sea.size_flags_stretch_ratio = 3.0
	sea.clip_contents = true
	column.add_child(sea)
	var art := TextureRect.new()
	if ResourceLoader.exists(SEA_ART):
		art.texture = load(SEA_ART)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sea.add_child(art)
	var band := MarginContainer.new()
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		band.add_theme_constant_override("margin_" + edge, 8)
	sea.add_child(band)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	lines.alignment = BoxContainer.ALIGNMENT_END
	band.add_child(lines)
	for _side: String in [NavalDispatch.ATTACKER, NavalDispatch.DEFENDER]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		lines.add_child(row)
		_rows.append(row)


func _reset_body() -> void:
	_beats_shown = 0


func _populate() -> void:
	_headline.text = NavalDispatch.headline(battle, zone_name, faction_names)
	var index: int = 0
	for side: String in [NavalDispatch.ATTACKER, NavalDispatch.DEFENDER]:
		if index < _rows.size():
			_fill_row(_rows[index], side)
		index += 1
		var owner: int = _owner(side)
		var who: Label = _atk_name if side == NavalDispatch.ATTACKER else _def_name
		var bar: ProgressBar = _atk_bar if side == NavalDispatch.ATTACKER else _def_bar
		who.text = "%s · %s" % [
			NavalDispatch.name_of(faction_names, owner), _hull_text(side)
		]
		_tint_side(who, bar, owner)
		bar.max_value = maxi(NavalDispatch.strength(battle, side), 1)
		bar.value = bar.max_value


## The despatch is read one beat at a time, then the verdict stamps down.
func _play() -> void:
	var beats: Array[String] = NavalDispatch.beats(battle, zone_name, faction_names)
	if beats.is_empty():
		_finish()
		return
	_tween = create_tween()
	for index in beats.size():
		_tween.tween_callback(_add_beat.bind(index))
		_tween.tween_interval(BEAT_SECONDS)
	_tween.tween_callback(_finish)


func _finish() -> void:
	if _finished:
		return
	var beats: Array[String] = NavalDispatch.beats(battle, zone_name, faction_names)
	while _beats_shown < beats.size():
		_add_beat(_beats_shown)
	_set_survivors()
	stamp_outcome(
		NavalDispatch.outcome_text(battle, zone_name, faction_names),
		int(battle.get("outcome", NavalCombat.Outcome.STALEMATE)) \
			!= NavalCombat.Outcome.STALEMATE
	)


## One colour's line on the water: its name, then a medallion per hull type.
func _fill_row(row: HBoxContainer, side: String) -> void:
	for child: Node in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var owner: int = _owner(side)
	row.add_child(_label(NavalDispatch.name_of(faction_names, owner), 13,
		Palette.faction_color(owner)))
	for group: Dictionary in NavalDispatch.groups(battle, side):
		row.add_child(_medal_chip(String(group["type"]), int(group["count"])))
	if row.get_child_count() == 1:
		row.add_child(_label("%d hulls" % NavalDispatch.hull_count(battle, side), 12,
			Palette.TEXT_DIM))


## The two lines of hulls the sea band is drawing, for tests and tooling.
func side_lines() -> Array[HBoxContainer]:
	return _rows


## "6 hulls — 4 Galleon and 2 Sloop", or just "4 Carrack" when she flew one type.
func _hull_text(side: String) -> String:
	var groups: String = NavalDispatch.groups_text(battle, side)
	var count: int = NavalDispatch.hull_count(battle, side)
	if groups.is_empty():
		return "%d %s" % [count, "hull" if count == 1 else "hulls"]
	if NavalDispatch.groups(battle, side).size() == 1:
		return groups
	return "%d hulls — %s" % [count, groups]


## A hull type's medallion and how many of her flew; art is the catalogue's own
## (ShipArt), so a Frigate never reads as a Fluyte (REQ-P1-08).
func _medal_chip(type_id: String, count: int) -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 2)
	var size: float = clampf((_panel.size.x if _panel != null else 0.0) / 18.0,
		MEDALLION_MIN, MEDALLION_MAX)
	chip.tooltip_text = "%d %s" % [count, ShipStats.display_name(type_id)]
	var tex: Texture2D = ShipArt.medallion(type_id)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.custom_minimum_size = Vector2(size, size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
	var tally := _label("×%d" % count, 12, Palette.TEXT)
	tally.custom_minimum_size = Vector2(0, size)
	tally.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(tally)
	return chip


## The bars keep the hulls each colour carried out: the beaten side's are gone
## unless she slipped away, and a retreat takes every hull she still had.
func _set_survivors() -> void:
	var fled: bool = bool((battle.get("retreat", {}) as Dictionary).get("success", false))
	for side: String in [NavalDispatch.ATTACKER, NavalDispatch.DEFENDER]:
		var before: int = NavalDispatch.hull_count(battle, side)
		var lost: int = (battle.get(side + "_lost", []) as Array).size()
		var bar: ProgressBar = _atk_bar if side == NavalDispatch.ATTACKER else _def_bar
		bar.max_value = maxi(before, 1)
		bar.value = before if fled and lost == 0 else maxi(before - lost, 0)


func _add_beat(index: int) -> void:
	var beats: Array[String] = NavalDispatch.beats(battle, zone_name, faction_names)
	if index < 0 or index >= beats.size() or index < _beats_shown:
		return
	_beats_shown = index + 1
	add_line(beats[index])


func _owner(side: String) -> int:
	return int(battle.get(side, 0))
