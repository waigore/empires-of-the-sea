class_name GameSetupScreen
extends Control
## New-game setup (wiki: game-setup): choose the human Great Power, map seed and
## map size. Emits one resolved GameConfig; the router owns generation.

signal start_requested(config: GameConfig)
signal back_pressed

var nation_option: OptionButton = null
var seed_field: LineEdit = null
var size_option: OptionButton = null
var start_button: Button = null
var back_button: Button = null

var _summary: Label = null
var _error: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	MenuFrame.backdrop(self)
	_build()
	_refresh_summary()


func _build() -> void:
	var box: VBoxContainer = MenuFrame.column(self, 540.0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(MenuFrame.crest(64))
	box.add_child(MenuFrame.title("NEW GAME", 34))
	box.add_child(MenuFrame.subtitle(
		"Choose a crown and chart a world. The same seed always returns the same seas."
	))
	box.add_child(MenuFrame.separator())

	box.add_child(MenuFrame.caption("Your crown"))
	nation_option = OptionButton.new()
	MenuFrame.style_option(nation_option)
	for faction_id: int in FactionCatalog.great_power_ids():
		nation_option.add_item(FactionCatalog.name_of(faction_id), faction_id)
	nation_option.select(0)
	nation_option.item_selected.connect(func(_index: int) -> void: _refresh_summary())
	box.add_child(nation_option)

	box.add_child(MenuFrame.caption("Map seed"))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	box.add_child(seed_row)
	seed_field = LineEdit.new()
	seed_field.placeholder_text = "Leave blank for a random world"
	seed_field.max_length = 9
	seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuFrame.style_line_edit(seed_field)
	seed_field.text_changed.connect(func(_text: String) -> void: _refresh_summary())
	seed_row.add_child(seed_field)
	var roll := MenuFrame.small_button("ROLL", 96.0)
	roll.pressed.connect(func() -> void:
		seed_field.text = str(GameConfig.random_seed())
		_refresh_summary()
	)
	seed_row.add_child(roll)

	box.add_child(MenuFrame.caption("Map size"))
	size_option = OptionButton.new()
	MenuFrame.style_option(size_option)
	for entry: Dictionary in GameConfig.SIZES:
		size_option.add_item(
			"%s  ·  %d × %d" % [String(entry["label"]), int(entry["width"]), int(entry["height"])]
		)
	size_option.select(GameConfig.DEFAULT_SIZE_INDEX)
	size_option.item_selected.connect(func(_index: int) -> void: _refresh_summary())
	box.add_child(size_option)

	_summary = MenuFrame.subtitle("")
	box.add_child(_summary)

	_error = MenuFrame.notice("")
	_error.visible = false
	box.add_child(_error)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	back_button = MenuFrame.small_button("BACK", 140.0)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	actions.add_child(back_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	start_button = MenuFrame.action_button("SET SAIL")
	start_button.custom_minimum_size = Vector2(220.0, MenuFrame.BUTTON_HEIGHT)
	start_button.pressed.connect(_on_start)
	actions.add_child(start_button)


func _refresh_summary() -> void:
	if _summary == null or nation_option == null or size_option == null:
		return
	var nation: String = nation_option.get_item_text(nation_option.selected)
	var rivals: int = FactionCatalog.great_power_ids().size() - 1
	var seed_text: String = seed_field.text.strip_edges() if seed_field != null else ""
	var seed_label: String = seed_text if not seed_text.is_empty() else "random"
	_summary.text = "You command %s  ·  %d rival crowns sail as AI  ·  seed %s" % [
		nation, rivals, seed_label,
	]


func _on_start() -> void:
	if _error == null:
		return
	_error.visible = false
	var text: String = seed_field.text.strip_edges()
	var seed_value: int = GameConfig.random_seed()
	if not text.is_empty():
		if not text.is_valid_int():
			_error.text = "Enter a whole-number seed, or leave the field blank."
			_error.visible = true
			return
		seed_value = text.to_int()
	var faction: int = int(nation_option.get_item_id(nation_option.selected))
	var config: GameConfig = GameConfig.make(seed_value, size_option.selected, faction)
	start_requested.emit(config)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back_pressed.emit()
