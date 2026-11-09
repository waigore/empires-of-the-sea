class_name LedgerWorkers
extends VBoxContainer
## WORKERS tab of the ledger: the tier roster and its recruit intents.
## Presentation only — blocked reasons come from PlayerEconomy (REQ-P2-03).

signal recruit_requested(tier: int)

const ROW_HEIGHT: float = 38.0

var _economy: PlayerEconomy = null


func fill(economy: PlayerEconomy) -> void:
	_economy = economy
	UiRowBuilder.clear(self)
	add_child(
		UiRowBuilder.label(
			"Peasants eat 1 food; trained workers eat grain + meat and need their tier luxury.",
			11,
			Palette.TEXT_DIM
		)
	)
	for tier in WorkerPool.TIER_COUNT:
		add_child(_tier_row(tier))
	UiRowBuilder.spacer(self)


func _tier_row(tier: int) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
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
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	var reason: String = _economy.recruit_blocked_reason(tier)
	var recruit := UiRowBuilder.button("Recruit", ROW_HEIGHT)
	recruit.custom_minimum_size = Vector2(88, ROW_HEIGHT)
	recruit.disabled = not reason.is_empty()
	recruit.tooltip_text = reason if not reason.is_empty() else LedgerText.recruit_cost(tier)
	recruit.pressed.connect(func() -> void: recruit_requested.emit(tier))
	row.add_child(recruit)
	return row
