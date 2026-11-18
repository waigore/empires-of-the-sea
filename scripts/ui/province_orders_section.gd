class_name ProvinceOrdersSection
extends VBoxContainer
## The province's order rail: muster, build, the gated town order, the capital
## yard and the civilian muster list. It reads state handed over by the dossier
## and emits intents — the rules decide whether an order may run (REQ-P3-02).

signal action_pressed(action: String)

## A gated row's clause, lifted toward white the way the stat chips lift crimson:
## the dossier is a dark sheet, and the gate must stay legible on a phone.
const GATE_INK := Color(0.765, 0.460, 0.460)

var town_button: Button = null
var shipyard_button: Button = null
var training_box: VBoxContainer = null
## type_id -> {"button", "note"}: one row per craft the roster offers, so a
## refresh can re-read every hire's study gate (DR-20261118-09).
var _train_rows: Dictionary = {}


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
		# The button and its line stay one row: what the craft does, and the study
		# it waits on, under the price it is asked (DR-20261118-09).
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		training_box.add_child(row)
		var train := _order_button(
			"Train %s · %s" % [
				CivilianCatalog.display_name(type_id),
				CivilianCatalog.training_cost_text(type_id),
			]
		)
		train.add_theme_font_size_override("font_size", 13)
		train.pressed.connect(func() -> void: action_pressed.emit("train_%s" % type_id))
		row.add_child(train)
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 11)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(note)
		_train_rows[type_id] = {"button": train, "note": note}
	# A dossier built before any study is read keeps the gated rows greyed.
	set_training({})


## The town order is offered, not refused: the button greys out with the rule's
## own reason until the crown can actually raise the town (REQ-P2-03).
## `stockpile` is the crown's live purse when the caller knows it; null leaves
## the money gate to the order that charges it.
func set_town_order(
	data: ProvinceState, faction: int, tech_unlocked: Dictionary,
	stockpile: Variant = null
) -> void:
	var refusal: String = ""
	if faction >= 0 and data.owner != faction:
		refusal = "This land is not held by your crown."
	if refusal.is_empty():
		refusal = CivilianWorkRefusals.town_upgrade(data, tech_unlocked, stockpile)
	town_button.disabled = not refusal.is_empty()
	town_button.tooltip_text = DossierCopy.TOWN_TIP if refusal.is_empty() else refusal


## The yard is a capital-port order: it launches hulls into the home fleet
## (wiki: ships-and-naval § Home Fleet).
func set_shipyard_visible(visible: bool) -> void:
	shipyard_button.visible = visible


func set_training_visible(visible: bool) -> void:
	training_box.visible = visible


## Every hire names what the craft does and the study it waits on, and a gated
## row greys out with the same reading the order refuses on — a crown reads on the
## rail what it would otherwise only hear in a refusal toast (wiki: civilian-units
## § Training; DR-20261118-09; REQ-P2-03, REQ-P5-05).
func set_training(tech_unlocked: Dictionary) -> void:
	for type_id: String in _train_rows.keys():
		var entry: Dictionary = _train_rows[type_id]
		var tech: String = CivilianHire.locked_tech(type_id, tech_unlocked)
		var open: bool = tech.is_empty()
		var button: Button = entry["button"]
		button.disabled = not open
		button.tooltip_text = (
			"Engaged at your capital; the crew musters when the turn closes."
			if open
			else "Requires %s." % TechCatalog.display_name(tech)
		)
		var note: Label = entry["note"]
		note.text = CivilianHire.line(type_id, tech_unlocked)
		note.add_theme_color_override("font_color", Palette.GOLD if open else GATE_INK)


## One craft's row, for the sheet's own reading and the tests that prove it.
func training_row(type_id: String) -> Dictionary:
	return _train_rows.get(type_id, {}) as Dictionary


func _order_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.add_theme_font_size_override("font_size", 15)
	return button
