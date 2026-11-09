class_name ProposalBanner
extends PanelContainer
## A rival's proposal above the court ledger: the human answers Accept or
## Refuse, and the proposing rival pays (wiki: diplomacy § Court proposals;
## DR-20261109-06). Presentation only — the panel routes the answer to rules.

signal answer_pressed(kind: String, proposer: int)

var _proposal: Dictionary = {}


func setup(proposal: Dictionary) -> void:
	_proposal = proposal
	_build()


func _build() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.12, 0.16, 0.10, 0.95), Color(0.52, 0.66, 0.40), 1, 3, Vector4(12, 8, 12, 8)
		)
	)
	var proposer: int = int(_proposal.get("from", -1))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	column.add_child(_label("RIVAL PROPOSAL", 11, Palette.GOLD_PALE))
	var text := _label(
		"%s proposes %s. The proposing court pays; our treasury is untouched."
		% [FactionCatalog.name_of(proposer), DiplomacyProposals.offer_label(_proposal)],
		13,
		Palette.TEXT
	)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var accept := _small_button("Accept")
	accept.pressed.connect(
		func() -> void: answer_pressed.emit(DiplomacyProposals.KIND_ACCEPT, proposer)
	)
	row.add_child(accept)
	var refuse := _small_button("Refuse")
	refuse.pressed.connect(
		func() -> void: answer_pressed.emit(DiplomacyProposals.KIND_REFUSE, proposer)
	)
	row.add_child(refuse)
	column.add_child(row)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 13)
	return button