class_name LedgerWorkers
extends VBoxContainer
## WORKERS tab of the ledger: the tier roster with its recruit and disband
## intents. Presentation only — blocked reasons come from PlayerEconomy, so the
## panel never invents a rule (REQ-P2-03).

signal recruit_requested(tier: int)
signal disband_requested(tier: int)

const ROW_HEIGHT: float = 38.0
## A phone row is thumb-sized; the desktop ledger stays dense (REQ-P1-05).
const COMPACT_ROW_HEIGHT: float = 44.0
const ACTION_WIDTH: float = 88.0

var _economy: PlayerEconomy = null
var _compact: bool = false
## Row actions keyed "<action>:<tier>" ("recruit:2", "disband:1") for tooling.
var _buttons: Dictionary = {}
## Tier badges keyed by tier, so tooling reads the mark without walking rows.
var _marks: Dictionary = {}


## Phone geometry from the panel that owns the tab; a live rotation re-fills so
## the rows change size with the screen.
func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	if _economy != null:
		fill(_economy)


func fill(economy: PlayerEconomy) -> void:
	_economy = economy
	_buttons.clear()
	_marks.clear()
	UiRowBuilder.clear(self)
	add_child(
		UiRowBuilder.label(
			"Trained workers eat grain, meat and their tier luxury. Disband refunds nothing.",
			11,
			Palette.TEXT_DIM
		)
	)
	for tier in WorkerPool.TIER_COUNT:
		add_child(_tier_row(tier))
	UiRowBuilder.spacer(self)


func _tier_row(tier: int) -> Control:
	var height: float = COMPACT_ROW_HEIGHT if _compact else ROW_HEIGHT
	var mark: int = WorkerTierArt.MARK_COMPACT if _compact else WorkerTierArt.MARK_SIZE
	var row := UiRowBuilder.row(height)
	var badge := WorkerTierArt.badge(tier, mark)
	row.add_child(badge)
	_marks[tier] = badge
	var name_label := UiRowBuilder.label(WorkerPool.tier_name(tier), 14, Palette.TEXT)
	name_label.custom_minimum_size = Vector2(132, 0)
	row.add_child(name_label)
	var detail := UiRowBuilder.label(
		"%d  ·  labour %d" % [
			_economy.workers.count(tier),
			_economy.workers.count(tier) * WorkerPool.LABOUR_PER_WORKER[tier],
		],
		13,
		Palette.TEXT_DIM
	)
	detail.clip_text = true
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	row.add_child(
		_action(
			"recruit",
			tier,
			"Recruit",
			_economy.recruit_blocked_reason(tier),
			LedgerText.recruit_cost(tier),
			height
		)
	)
	if WorkerPool.is_trained(tier):
		row.add_child(
			_action(
				"disband",
				tier,
				"Disband",
				_economy.disband_blocked_reason(tier),
				LedgerText.disband_hint(tier),
				height
			)
		)
	return row


## One row action. A blocked row stays visible but inert so the roster keeps its
## shape; the tooltip carries the rules reason or, when payable, the price.
func _action(
	kind: String, tier: int, text: String, reason: String, hint: String, height: float
) -> Button:
	var button := UiRowBuilder.button(text, height)
	button.custom_minimum_size = Vector2(ACTION_WIDTH, height)
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason if not reason.is_empty() else hint
	if kind == "disband":
		button.pressed.connect(func() -> void: disband_requested.emit(tier))
	else:
		button.pressed.connect(func() -> void: recruit_requested.emit(tier))
	_buttons["%s:%d" % [kind, tier]] = button
	return button


## Row action buttons keyed "<action>:<tier>"; tests and tooling read this
## instead of walking row children (REQ-P3-02).
func action_buttons() -> Dictionary:
	return _buttons


## Tier badges keyed by tier; the roster mark a row wears for that rank.
func tier_marks() -> Dictionary:
	return _marks
