class_name CourtPrompts
extends RefCounted
## Consent decisions shown above the court ledger: a waiting call to arms, an
## intervention offer, or a rival's proposal. Only the oldest decision is shown;
## the turn resolver answers them in the same order. Presentation only — buttons
## emit intents and the rules layer decides (REQ-P2-03).


static func fill(box: VBoxContainer, state: DiplomacyState, player: int, emit: Callable) -> void:
	if box == null:
		return
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var call: Dictionary = CallToArms.pending_call_for(state, player)
	var intervention: Dictionary = Intervention.pending_for(state, player)
	var proposal: Dictionary = DiplomacyProposals.pending_for(state, player)
	box.visible = (
		not call.is_empty() or not intervention.is_empty() or not proposal.is_empty()
	)
	if not call.is_empty():
		box.add_child(_call_banner(call, emit))
	elif not intervention.is_empty():
		box.add_child(_intervention_banner(intervention, emit))
	elif not proposal.is_empty():
		box.add_child(_proposal_banner(proposal, emit))


## Mutual defence: join the war on the aggressor, or refuse and break the treaty.
static func _call_banner(call: Dictionary, emit: Callable) -> Control:
	var banner: PanelContainer = _banner(
		Color(0.22, 0.10, 0.08, 0.95), Color(0.72, 0.34, 0.26)
	)
	var column: VBoxContainer = banner.get_child(0) as VBoxContainer
	column.add_child(_label("CALL TO ARMS", 11, Palette.GOLD_PALE))
	var text := _label(
		(
			"%s has declared war on %s. Our formal alliance binds us: join the war"
			+ " against the aggressor, or refuse and break the treaty."
		) % [
			FactionCatalog.name_of(int(call["aggressor"])),
			FactionCatalog.name_of(int(call["defender"])),
		],
		13,
		Palette.TEXT
	)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text)
	var row: HBoxContainer = _row()
	row.add_child(_button("Join the war", emit, CallToArms.KIND_JOIN, int(call["aggressor"])))
	row.add_child(_button("Refuse", emit, CallToArms.KIND_REFUSE, int(call["aggressor"])))
	column.add_child(row)
	return banner


## Intervention: join the war, stand aside and lose the embassy, or protest.
static func _intervention_banner(offer: Dictionary, emit: Callable) -> Control:
	var aggressor: int = int(offer["aggressor"])
	var target: int = int(offer["target"])
	var banner: PanelContainer = _banner(Color(0.18, 0.12, 0.08, 0.95), Palette.GOLD_DIM)
	var column: VBoxContainer = banner.get_child(0) as VBoxContainer
	column.add_child(_label("INTERVENTION", 11, Palette.GOLD_PALE))
	var text := _label(
		(
			"%s has declared war on %s. Our embassy stands: join the war on the"
			+ " aggressor, stand aside and lose the embassy, or protest."
		) % [FactionCatalog.name_of(aggressor), FactionCatalog.name_of(target)],
		13,
		Palette.TEXT
	)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text)
	var row: HBoxContainer = _row()
	row.add_child(_button("Intervene", emit, Intervention.KIND_INTERVENE, aggressor))
	row.add_child(_button("Stand aside", emit, Intervention.KIND_NOTHING, aggressor))
	row.add_child(_button("Protest", emit, Intervention.KIND_PROTEST, aggressor))
	column.add_child(row)
	return banner


## A rival's offer: accept it or refuse, never both.
static func _proposal_banner(offer: Dictionary, emit: Callable) -> Control:
	var from_id: int = int(offer["from"])
	var kind: String = String(offer["kind"])
	var stage: String = String(offer.get("stage", ""))
	var banner: PanelContainer = _banner(
		Color(0.13, 0.17, 0.11, 0.95), Color(0.55, 0.72, 0.45)
	)
	var column: VBoxContainer = banner.get_child(0) as VBoxContainer
	column.add_child(_label("PROPOSAL", 11, Palette.GOLD_PALE))
	var text := _label(
		"%s proposes %s." % [
			FactionCatalog.name_of(from_id), DiplomacyProposals.describe(kind, stage)
		],
		13,
		Palette.TEXT
	)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text)
	var row: HBoxContainer = _row()
	row.add_child(_button("Accept", emit, DiplomacyProposals.KIND_ACCEPT, from_id))
	row.add_child(_button("Refuse", emit, DiplomacyProposals.KIND_REFUSE, from_id))
	column.add_child(row)
	return banner


static func _banner(fill_color: Color, border: Color) -> PanelContainer:
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override(
		"panel",
		UiTheme.box(fill_color, border, 1, 3, Vector4(12, 8, 12, 8))
	)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	banner.add_child(column)
	return banner


static func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	return row


static func _button(text: String, emit: Callable, kind: String, target: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(func() -> void: emit.call(kind, target, ""))
	return button


static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
