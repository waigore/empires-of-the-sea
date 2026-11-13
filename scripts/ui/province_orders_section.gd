class_name ProvinceOrdersSection
extends VBoxContainer
## The province's order rail: muster, build, the gated town order, the capital
## yard and the civilian muster list. It reads state handed over by the dossier
## and emits intents — the rules decide whether an order may run (REQ-P3-02).

signal action_pressed(action: String)

var town_button: Button = null
var shipyard_button: Button = null
var training_box: VBoxContainer = null


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var caption := Label.new()
	caption.text = "ORDERS"
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	add_child(caption)

	var recruit := _order_button("Recruit Regiment")
	recruit.tooltip_text = "Muster at your capital; the regiment joins the Home Army."
	recruit.pressed.connect(func() -> void: action_pressed.emit("recruit"))
	add_child(recruit)

	shipyard_button = _order_button("Shipyard")
	shipyard_button.tooltip_text = "Launch and break up hulls at your capital port."
	shipyard_button.pressed.connect(func() -> void: action_pressed.emit("shipyard"))
	shipyard_button.visible = false
	add_child(shipyard_button)

	var build := _order_button("Build Improvement")
	build.pressed.connect(func() -> void: action_pressed.emit("build"))
	add_child(build)

	town_button = _order_button("Upgrade Town")
	town_button.tooltip_text = DossierCopy.TOWN_TIP
	town_button.pressed.connect(func() -> void: action_pressed.emit("upgrade_town"))
	add_child(town_button)

	training_box = VBoxContainer.new()
	training_box.add_theme_constant_override("separation", 6)
	training_box.visible = false
	add_child(training_box)

	var training := Label.new()
	training.text = "TRAIN CIVILIANS"
	training.add_theme_font_size_override("font_size", 11)
	training.add_theme_color_override("font_color", Palette.TEXT_DIM)
	training_box.add_child(training)

	for type_id: String in CivilianCatalog.playable_types():
		var train := _order_button(
			"Train %s · %s" % [
				CivilianCatalog.display_name(type_id),
				CivilianCatalog.training_cost_text(type_id),
			]
		)
		train.add_theme_font_size_override("font_size", 13)
		train.pressed.connect(func() -> void: action_pressed.emit("train_%s" % type_id))
		training_box.add_child(train)


## The town order is offered, not refused: the button greys out with the rule's
## own reason until the crown can actually raise the town (REQ-P2-03).
func set_town_order(data: ProvinceState, faction: int, tech_unlocked: Dictionary) -> void:
	var refusal: String = ""
	if faction >= 0 and data.owner != faction:
		refusal = "This land is not held by your crown."
	if refusal.is_empty():
		refusal = CivilianWorkPlan.town_upgrade_refusal(data, tech_unlocked)
	town_button.disabled = not refusal.is_empty()
	town_button.tooltip_text = DossierCopy.TOWN_TIP if refusal.is_empty() else refusal


## The yard is a capital-port order: it launches hulls into the home fleet
## (wiki: ships-and-naval § Home Fleet).
func set_shipyard_visible(visible: bool) -> void:
	shipyard_button.visible = visible


func set_training_visible(visible: bool) -> void:
	training_box.visible = visible


func _order_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.add_theme_font_size_override("font_size", 15)
	return button
